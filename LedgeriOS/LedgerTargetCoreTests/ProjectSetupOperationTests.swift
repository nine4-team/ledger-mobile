import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Setup Operation Contracts")
struct ProjectSetupOperationTests {
    @Test("Existing and new Client setup preserves stable identity and exact category state")
    func typedSetupPreservesIdentityAndCategoryState() throws {
        let existing = try Self.command()
        let newClient = try Self.command(
            operationID: "operation-create-project-south",
            projectID: "project-south",
            newClient: true
        )

        #expect(existing.draft.displayName.rawValue == "North House")
        #expect(newClient.draft.displayName == existing.draft.displayName)
        #expect(existing.draft.projectId != newClient.draft.projectId)
        #expect(existing.subject != newClient.subject)
        #expect(existing.fingerprint != newClient.fingerprint)
        #expect(existing.subject.kind == .project)
        #expect(existing.subject.id.rawValue == existing.draft.projectId.rawValue)
        #expect(existing.draft.clientSelection.clientId.rawValue == "client-north")
        #expect(existing.draft.clientSelection.newClientDisplayName == nil)
        #expect(newClient.draft.clientSelection.clientId.rawValue == "client-south")
        #expect(newClient.draft.clientSelection.newClientDisplayName?.rawValue == "South Family")
        #expect(existing.envelope.preconditions.isEmpty)

        let allocations = existing.envelope.payload.categoryAllocations
        #expect(allocations.map(\.categoryId.rawValue) == [
            "category-design", "category-furnishings", "category-install"
        ])
        #expect(allocations[0].allocation == Money.zero(currency: Self.usd))
        #expect(allocations[1].allocation == nil)
        #expect(allocations[2].allocation == Money(minorUnits: 125_000, currency: Self.usd))
        #expect(!allocations.contains { $0.categoryId.rawValue == "category-absent" })

        let empty = try Self.command(
            operationID: "operation-create-project-empty",
            projectID: "project-empty",
            allocations: []
        )
        #expect(empty.envelope.payload.categoryAllocations.isEmpty)

        let keys = Set(try Self.jsonObject(OperationContractCodec.encode(existing)).keys)
        #expect(keys == Set(["draft", "envelope", "fingerprint", "subject"]))
        let encodedText = String(
            decoding: try OperationContractCodec.encode(existing),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "clientname", "mainimage", "media", "attachment", "archive", "delete",
            "reassign", "collection", "sql"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Canonical setup survives restart and category input order is not identity")
    func canonicalRestartAndCategoryOrder() throws {
        let forward = try Self.categories()
        let reversed = Array(forward.reversed())
        let first = try Self.command(allocations: forward)
        let second = try Self.command(allocations: reversed)

        #expect(first == second)
        #expect(first.fingerprint == second.fingerprint)
        let firstBytes = try OperationContractCodec.encode(first)
        #expect(try OperationContractCodec.encode(second) == firstBytes)

        let restored = try OperationContractCodec.decode(
            CreateProjectCommand.self,
            from: firstBytes
        )
        #expect(restored == first)
        #expect(try OperationContractCodec.encode(restored) == firstBytes)
        #expect(restored.envelope.operationId.rawValue == "operation-create-project-north")
        #expect(restored.envelope.accountId.rawValue == "account-project-test")
        #expect(restored.envelope.actorPrincipalId.rawValue == "principal-project-test")
        #expect(restored.envelope.contractVersion.rawValue == "project-create-v1")
        #expect(restored.envelope.clientCreatedAt == Self.t0)
        #expect(restored.envelope.payload.description == "Whole-home redesign")
        #expect(restored.subject.kind == .project)
        #expect(restored.fingerprint == (try OperationFingerprint.make(for: restored.envelope)))

        let nullAllocation = try Self.command(allocations: [
            Self.allocation("category-design", minorUnits: nil)
        ])
        let explicitZero = try Self.command(allocations: [
            Self.allocation("category-design", minorUnits: 0)
        ])
        #expect(nullAllocation.fingerprint != explicitZero.fingerprint)
        #expect(nullAllocation.envelope.payload.categoryAllocations[0].allocation == nil)
        #expect(explicitZero.envelope.payload.categoryAllocations[0].allocation?.minorUnits == 0)

        let text = String(decoding: firstBytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://", "file://",
            "collection/", "bearer", "token", "secret", "serverresult", "server_result",
            "attachment", "imageurl", "image_url"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Invalid, rebound, and tampered setup evidence fails atomically")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.directoryFailure {
            try ProjectDisplayName(validating: " \n\t ")
        } == .invalidProjectDisplayName)
        #expect(Self.directoryFailure {
            try ClientDisplayName(validating: " \n\t ")
        } == .invalidClientDisplayName)
        #expect(Self.setupFailure {
            try Self.allocation("category-negative", minorUnits: -1)
        } == .negativeCategoryAllocation)

        let duplicate = try Self.allocation("category-duplicate", minorUnits: nil)
        #expect(Self.setupFailure {
            try Self.draft(allocations: [duplicate, duplicate])
        } == .duplicateCategoryIdentity)
        #expect(Self.setupFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidProjectCreatedAt)
        #expect(Self.setupFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidProjectCreatedAt)

        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
        let changedAccount = try Self.mutate(
            bytes,
            path: ["envelope", "accountId"],
            value: "account-other"
        )
        #expect(Self.decodeFailure(changedAccount) == .draftAccountMismatch)
        let changedActor = try Self.mutate(
            bytes,
            path: ["envelope", "actorPrincipalId"],
            value: "principal-other"
        )
        #expect(Self.decodeFailure(changedActor) == .draftActorMismatch)
        let changedContract = try Self.mutate(
            bytes,
            path: ["envelope", "contractVersion"],
            value: "project-create-v2"
        )
        #expect(Self.decodeFailure(changedContract) == .draftContractMismatch)
        let changedProject = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "projectId"],
            value: "project-other"
        )
        #expect(Self.decodeFailure(changedProject) == .draftPayloadMismatch)
        let changedClient = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "clientSelection", "clientId"],
            value: "client-other"
        )
        #expect(Self.decodeFailure(changedClient) == .draftPayloadMismatch)
        let changedCategory = try Self.mutateFirstCategoryAllocation(
            bytes,
            value: ["currency": "USD", "minorUnits": 999]
        )
        #expect(Self.decodeFailure(changedCategory) == .draftPayloadMismatch)
        let invalidSelection = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "clientSelection", "kind"],
            value: "copied_name"
        )
        #expect(Self.decodeFailure(invalidSelection) == .invalidClientSelection)

        let precondition = OperationPrecondition.noUnresolvedOperation(
            subject: command.subject
        )
        let preconditionJSON = try JSONSerialization.jsonObject(
            with: OperationContractCodec.encode([precondition])
        )
        let changedPreconditions = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions"],
            value: preconditionJSON
        )
        #expect(Self.decodeFailure(changedPreconditions) == .unexpectedPreconditions)
        let changedSubject = try Self.mutate(
            bytes,
            path: ["subject", "kind"],
            value: "client"
        )
        #expect(Self.decodeFailure(changedSubject) == .subjectMismatch)
        let changedFingerprint = try Self.mutate(
            bytes,
            path: ["fingerprint"],
            value: String(repeating: "0", count: 64)
        )
        #expect(Self.decodeFailure(changedFingerprint) == .fingerprintMismatch)
        #expect(Self.setupFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)

        let negativeJSON = Data(
            #"{"allocation":{"currency":"USD","minorUnits":-1},"categoryId":"category-negative"}"#.utf8
        )
        #expect(Self.setupFailure {
            try OperationContractCodec.decode(
                NullableCategoryAllocation.self,
                from: negativeJSON
            )
        } == .negativeCategoryAllocation)
        #expect(Self.setupFailure {
            try OperationContractCodec.decode(
                NullableCategoryAllocation.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedCategoryAllocation)
        #expect(Self.setupFailure {
            try OperationContractCodec.decode(
                ProjectSetupDraft.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(ProjectSetupFailure, String)] = [
            (.invalidClientSelection, "project_setup_client_selection_invalid"),
            (.negativeCategoryAllocation, "project_setup_category_allocation_negative"),
            (.duplicateCategoryIdentity, "project_setup_category_identity_duplicate"),
            (.invalidProjectCreatedAt, "project_setup_created_at_invalid"),
            (.draftAccountMismatch, "project_setup_account_mismatch"),
            (.draftActorMismatch, "project_setup_actor_mismatch"),
            (.draftContractMismatch, "project_setup_contract_mismatch"),
            (.draftPayloadMismatch, "project_setup_payload_mismatch"),
            (.unexpectedPreconditions, "project_setup_preconditions_unexpected"),
            (.subjectMismatch, "project_setup_subject_mismatch"),
            (.fingerprintMismatch, "project_setup_fingerprint_mismatch"),
            (.receiptMismatch, "project_setup_receipt_mismatch"),
            (.localAcceptanceFailed, "project_setup_local_acceptance_failed"),
            (
                .invalidEncodedCategoryAllocation,
                "project_setup_category_allocation_encoding_invalid"
            ),
            (.invalidEncodedDraft, "project_setup_draft_encoding_invalid"),
            (.invalidEncodedCommand, "project_setup_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The reference port reuses shared queued receipt and replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalProjectSetupAdapter(acceptedAt: Self.t1)
        let first = try await adapter.create(command)
        let replay = try await adapter.create(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let changed = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            projectID: "project-other",
            newClient: true
        )
        do {
            _ = try await adapter.create(changed)
            Issue.record("A reused OperationID accepted changed Project setup")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingProjectSetupAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.create(command)
        } catch let failure as ProjectSetupFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_600_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_600_001)
    private static let usd = try! CurrencyCode(validating: "USD")

    private static func allocation(
        _ categoryID: String,
        minorUnits: Int64?
    ) throws -> NullableCategoryAllocation {
        try NullableCategoryAllocation(
            categoryId: BudgetCategoryID(validating: categoryID),
            allocation: minorUnits.map { Money(minorUnits: $0, currency: usd) }
        )
    }

    private static func categories() throws -> [NullableCategoryAllocation] {
        [
            try allocation("category-install", minorUnits: 125_000),
            try allocation("category-furnishings", minorUnits: nil),
            try allocation("category-design", minorUnits: 0)
        ]
    }

    private static func draft(
        capturedAt: Date = t0,
        projectID: String = "project-north",
        newClient: Bool = false,
        allocations: [NullableCategoryAllocation]? = nil
    ) throws -> ProjectSetupDraft {
        let clientSelection: ProjectClientSelectionInput
        if newClient {
            clientSelection = ProjectClientSelectionInput(
                newClientId: try ClientID(validating: "client-south"),
                displayName: try ClientDisplayName(validating: "South Family")
            )
        } else {
            clientSelection = ProjectClientSelectionInput(
                existing: try ClientID(validating: "client-north")
            )
        }
        return try ProjectSetupDraft(
            accountId: AccountID(validating: "account-project-test"),
            actorPrincipalId: PrincipalID(validating: "principal-project-test"),
            operationContractVersion: OperationContractVersion(
                validating: "project-create-v1"
            ),
            projectId: ProjectID(validating: projectID),
            clientSelection: clientSelection,
            displayName: ProjectDisplayName(validating: "North House"),
            description: "Whole-home redesign",
            categoryAllocations: allocations ?? categories(),
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-create-project-north",
        projectID: String = "project-north",
        newClient: Bool = false,
        allocations: [NullableCategoryAllocation]? = nil
    ) throws -> CreateProjectCommand {
        try CreateProjectCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(
                projectID: projectID,
                newClient: newClient,
                allocations: allocations
            )
        )
    }

    private static func setupFailure<T>(
        _ operation: () throws -> T
    ) -> ProjectSetupFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ProjectSetupFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func directoryFailure<T>(
        _ operation: () throws -> T
    ) -> ClientProjectDirectoryFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ClientProjectDirectoryFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> ProjectSetupFailure? {
        setupFailure {
            try OperationContractCodec.decode(CreateProjectCommand.self, from: data)
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectSetupFailure.invalidEncodedCommand
        }
        return object
    }

    private static func mutate(_ data: Data, path: [String], value: Any) throws -> Data {
        var object = try jsonObject(data)
        try Self.set(value, at: path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func mutateFirstCategoryAllocation(
        _ data: Data,
        value: Any
    ) throws -> Data {
        var object = try jsonObject(data)
        guard var envelope = object["envelope"] as? [String: Any],
              var payload = envelope["payload"] as? [String: Any],
              var allocations = payload["categoryAllocations"] as? [[String: Any]],
              !allocations.isEmpty else {
            throw ProjectSetupFailure.invalidEncodedCommand
        }
        allocations[0]["allocation"] = value
        payload["categoryAllocations"] = allocations
        envelope["payload"] = payload
        object["envelope"] = envelope
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func set(
        _ value: Any,
        at path: ArraySlice<String>,
        in object: inout [String: Any]
    ) throws {
        guard let key = path.first else {
            throw ProjectSetupFailure.invalidEncodedCommand
        }
        if path.count == 1 {
            object[key] = value
            return
        }
        guard var child = object[key] as? [String: Any] else {
            throw ProjectSetupFailure.invalidEncodedCommand
        }
        try set(value, at: path.dropFirst(), in: &child)
        object[key] = child
    }
}

private actor JournalProjectSetupAdapter: ProjectSetupOperating {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func create(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        let receipt = try journal.accept(command.envelope, at: acceptedAt)
        return try command.validate(receipt)
    }

    var snapshotCount: Int {
        journal.snapshots.count
    }

    func fingerprint(for operationId: OperationID) -> OperationFingerprint? {
        journal.snapshot(for: operationId)?.fingerprint
    }
}

private struct FailingProjectSetupAdapter: ProjectSetupOperating {
    func create(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        throw ProjectSetupFailure.localAcceptanceFailed
    }
}
