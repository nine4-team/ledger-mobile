import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Space Creation Operation Contracts")
struct SpaceCreationOperationTests {
    @Test("Direct creation has one exact scope and only canonical identity, name, and notes")
    func directCreationHasExactScopeAndFields() throws {
        let project = try Self.command(
            name: "  Living\n Room  ",
            notes: "  Near\n east wall  "
        )
        let inventory = try Self.command(
            operationID: "operation-create-inventory-space",
            spaceID: "space-inventory-east",
            scope: .businessInventory,
            name: "  Receiving  ",
            notes: " \n\t "
        )
        let duplicateName = try Self.command(
            operationID: "operation-create-other-space",
            spaceID: "space-other",
            name: "Living\n Room"
        )

        #expect(project.draft.spaceId.rawValue == "space-studio")
        #expect(project.draft.displayName.rawValue == "Living\n Room")
        #expect(project.draft.notes.value == "Near\n east wall")
        #expect(inventory.draft.displayName.rawValue == "Receiving")
        #expect(inventory.draft.notes.value == nil)
        #expect(SpaceCreationNotes(nil).value == nil)
        #expect(duplicateName.draft.displayName == project.draft.displayName)
        #expect(duplicateName.draft.spaceId != project.draft.spaceId)

        if case .project(let projectId) = project.draft.scope {
            #expect(projectId.rawValue == "project-residence")
        } else {
            Issue.record("Expected a Project creation scope")
        }
        #expect(inventory.draft.scope == .businessInventory)
        #expect(project.envelope.payload == CreateSpacePayload(
            spaceId: project.draft.spaceId,
            scope: project.draft.scope,
            displayName: project.draft.displayName,
            notes: project.draft.notes
        ))
        #expect(project.envelope.preconditions.isEmpty)
        #expect(project.subject.kind == .space)
        #expect(project.subject.id.rawValue == project.draft.spaceId.rawValue)

        let projectBytes = try OperationContractCodec.encode(project)
        let inventoryBytes = try OperationContractCodec.encode(inventory)
        #expect(Set(try Self.jsonObject(projectBytes).keys) == Set([
            "draft", "envelope", "fingerprint", "subject"
        ]))
        #expect(try Self.objectKeys(projectBytes, path: ["envelope", "payload"]) == Set([
            "spaceId", "scope", "displayName", "notes"
        ]))
        #expect(try Self.objectKeys(projectBytes, path: ["envelope", "payload", "scope"]) == Set([
            "kind", "projectId"
        ]))
        #expect(try Self.objectKeys(inventoryBytes, path: ["envelope", "payload", "scope"]) == Set([
            "kind"
        ]))
        #expect(try Self.objectKeys(inventoryBytes, path: ["envelope", "payload", "notes"]) == Set([
            "value"
        ]))

        let inventoryObject = try Self.jsonObject(inventoryBytes)
        let envelope = try #require(inventoryObject["envelope"] as? [String: Any])
        let payload = try #require(envelope["payload"] as? [String: Any])
        let notes = try #require(payload["notes"] as? [String: Any])
        #expect(notes["value"] is NSNull)

        let encodedText = String(decoding: projectBytes, as: UTF8.self).lowercased()
        for forbidden in [
            "checklist", "template", "attachment", "review", "complete", "archive",
            "transaction", "occurrence", "invoice", "budget", "payer", "price",
            "fieldmap", "collectionpath", "sql", "servertimestamp"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Project and Business Inventory evidence survives byte-identical offline restart")
    func canonicalRestartPreservesExactEvidence() throws {
        for command in [
            try Self.command(),
            try Self.command(
                operationID: "operation-create-inventory-space",
                spaceID: "space-inventory-east",
                scope: .businessInventory,
                name: "Receiving",
                notes: nil
            )
        ] {
            let bytes = try OperationContractCodec.encode(command)
            let restored = try OperationContractCodec.decode(
                CreateSpaceCommand.self,
                from: bytes
            )

            #expect(restored == command)
            #expect(try OperationContractCodec.encode(restored) == bytes)
            #expect(restored.envelope.accountId.rawValue == "account-space-test")
            #expect(restored.envelope.actorPrincipalId.rawValue == "principal-space-test")
            #expect(restored.envelope.contractVersion.rawValue == "space-create-v1")
            #expect(restored.envelope.clientCreatedAt == Self.t0)
            #expect(restored.fingerprint == (try OperationFingerprint.make(for: restored.envelope)))

            let text = String(decoding: bytes, as: UTF8.self).lowercased()
            for forbidden in [
                "firebase", "firestore", "supabase", "powersync", "https://", "file://",
                "bearer", "token", "secret", "serverresult", "server_result",
                "authorization", "authorized", "migrated", "production"
            ] {
                #expect(!text.contains(forbidden))
            }
        }
    }

    @Test("Invalid, noncanonical, rebound, and tampered Space evidence fails atomically")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.spaceFailure {
            try SpaceDisplayName(validating: " \n\t ")
        } == .invalidDisplayName)
        #expect(Self.spaceFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidCapturedAt)
        #expect(Self.spaceFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidCapturedAt)

        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
        let noncanonicalName = try Self.mutate(
            bytes,
            path: ["draft", "displayName"],
            value: "  Studio  "
        )
        #expect(Self.decodeFailure(noncanonicalName) == .invalidEncodedDisplayName)
        let noncanonicalNotes = try Self.mutate(
            bytes,
            path: ["draft", "notes", "value"],
            value: "  East wall  "
        )
        #expect(Self.decodeFailure(noncanonicalNotes) == .invalidEncodedNotes)
        let unknownScope = try Self.mutate(
            bytes,
            path: ["draft", "scope", "kind"],
            value: "warehouse"
        )
        #expect(Self.decodeFailure(unknownScope) == .invalidCreationScope)
        let missingProject = try Self.removing(
            bytes,
            path: ["draft", "scope", "projectId"]
        )
        #expect(Self.decodeFailure(missingProject) == .invalidCreationScope)
        let inventoryWithProject = try Self.mutate(
            bytes,
            path: ["draft", "scope", "kind"],
            value: "businessInventory"
        )
        #expect(Self.decodeFailure(inventoryWithProject) == .invalidCreationScope)

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
            value: "space-create-v2"
        )
        #expect(Self.decodeFailure(changedContract) == .draftContractMismatch)
        let changedSpace = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "spaceId"],
            value: "space-other"
        )
        #expect(Self.decodeFailure(changedSpace) == .draftPayloadMismatch)
        let changedScope = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "scope"],
            value: ["kind": "businessInventory"]
        )
        #expect(Self.decodeFailure(changedScope) == .draftPayloadMismatch)
        let changedName = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "displayName"],
            value: "Library"
        )
        #expect(Self.decodeFailure(changedName) == .draftPayloadMismatch)
        let changedNotes = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "notes", "value"],
            value: "West wall"
        )
        #expect(Self.decodeFailure(changedNotes) == .draftPayloadMismatch)
        let unexpectedPreconditions = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions"],
            value: [[
                "expectedRevision": [
                    "subject": ["kind": "space", "id": "space-studio"],
                    "revision": 1
                ]
            ]]
        )
        #expect(Self.decodeFailure(unexpectedPreconditions) == .unexpectedPreconditions)
        let changedSubject = try Self.mutate(
            bytes,
            path: ["subject", "id"],
            value: "space-other"
        )
        #expect(Self.decodeFailure(changedSubject) == .subjectMismatch)
        let changedFingerprint = try Self.mutate(
            bytes,
            path: ["fingerprint"],
            value: String(repeating: "0", count: 64)
        )
        #expect(Self.decodeFailure(changedFingerprint) == .fingerprintMismatch)
        #expect(Self.spaceFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)

        #expect(Self.spaceFailure {
            try OperationContractCodec.decode(
                SpaceDisplayName.self,
                from: Data("\"  Studio  \"".utf8)
            )
        } == .invalidEncodedDisplayName)
        #expect(Self.spaceFailure {
            try OperationContractCodec.decode(
                SpaceCreationNotes.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedNotes)
        #expect(Self.spaceFailure {
            try OperationContractCodec.decode(
                SpaceCreationScope.self,
                from: Data("{}".utf8)
            )
        } == .invalidCreationScope)
        #expect(Self.spaceFailure {
            try OperationContractCodec.decode(
                SpaceCreationDraft.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(SpaceCreationFailure, String)] = [
            (.invalidDisplayName, "space_creation_display_name_invalid"),
            (.invalidEncodedDisplayName, "space_creation_display_name_encoding_invalid"),
            (.invalidEncodedNotes, "space_creation_notes_encoding_invalid"),
            (.invalidCreationScope, "space_creation_scope_invalid"),
            (.invalidCapturedAt, "space_creation_captured_at_invalid"),
            (.draftAccountMismatch, "space_creation_account_mismatch"),
            (.draftActorMismatch, "space_creation_actor_mismatch"),
            (.draftContractMismatch, "space_creation_contract_mismatch"),
            (.draftPayloadMismatch, "space_creation_payload_mismatch"),
            (.unexpectedPreconditions, "space_creation_preconditions_unexpected"),
            (.subjectMismatch, "space_creation_subject_mismatch"),
            (.fingerprintMismatch, "space_creation_fingerprint_mismatch"),
            (.receiptMismatch, "space_creation_receipt_mismatch"),
            (.localAcceptanceFailed, "space_creation_local_acceptance_failed"),
            (.invalidEncodedDraft, "space_creation_draft_encoding_invalid"),
            (.invalidEncodedCommand, "space_creation_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The Space creation port reuses shared queued receipt and replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalSpaceCreationAdapter(acceptedAt: Self.t1)
        let first = try await adapter.create(command)
        let replay = try await adapter.create(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let variants = [
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                spaceID: "space-other"
            ),
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                scope: .project(ProjectID(validating: "project-other"))
            ),
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                name: "Library"
            ),
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                notes: "West wall"
            )
        ]
        for variant in variants {
            do {
                _ = try await adapter.create(variant)
                Issue.record("A reused OperationID accepted changed Space-create intent")
            } catch let failure as OperationContractFailure {
                #expect(failure == .payloadMismatch(command.envelope.operationId))
            }
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingSpaceCreationAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.create(command)
        } catch let failure as SpaceCreationFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_950_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_950_001)

    private static func draft(
        spaceID: String = "space-studio",
        scope: SpaceCreationScope? = nil,
        name: String = "Studio",
        notes: String? = "East wall",
        capturedAt: Date = t0
    ) throws -> SpaceCreationDraft {
        try SpaceCreationDraft(
            accountId: AccountID(validating: "account-space-test"),
            actorPrincipalId: PrincipalID(validating: "principal-space-test"),
            operationContractVersion: OperationContractVersion(
                validating: "space-create-v1"
            ),
            spaceId: SpaceID(validating: spaceID),
            scope: try scope ?? .project(ProjectID(validating: "project-residence")),
            displayName: SpaceDisplayName(validating: name),
            notes: SpaceCreationNotes(notes),
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-create-space",
        spaceID: String = "space-studio",
        scope: SpaceCreationScope? = nil,
        name: String = "Studio",
        notes: String? = "East wall"
    ) throws -> CreateSpaceCommand {
        try CreateSpaceCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(
                spaceID: spaceID,
                scope: scope,
                name: name,
                notes: notes
            )
        )
    }

    private static func spaceFailure<T>(
        _ operation: () throws -> T
    ) -> SpaceCreationFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as SpaceCreationFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> SpaceCreationFailure? {
        spaceFailure {
            try OperationContractCodec.decode(CreateSpaceCommand.self, from: data)
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpaceCreationFailure.invalidEncodedCommand
        }
        return object
    }

    private static func objectKeys(_ data: Data, path: [String]) throws -> Set<String> {
        var value: Any = try jsonObject(data)
        for key in path {
            guard let object = value as? [String: Any], let next = object[key] else {
                throw SpaceCreationFailure.invalidEncodedCommand
            }
            value = next
        }
        guard let object = value as? [String: Any] else {
            throw SpaceCreationFailure.invalidEncodedCommand
        }
        return Set(object.keys)
    }

    private static func mutate(_ data: Data, path: [String], value: Any) throws -> Data {
        var object = try jsonObject(data)
        try Self.set(value, at: path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func removing(_ data: Data, path: [String]) throws -> Data {
        var object = try jsonObject(data)
        try Self.remove(at: path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func set(
        _ value: Any,
        at path: ArraySlice<String>,
        in object: inout [String: Any]
    ) throws {
        guard let key = path.first else {
            throw SpaceCreationFailure.invalidEncodedCommand
        }
        if path.count == 1 {
            object[key] = value
            return
        }
        guard var child = object[key] as? [String: Any] else {
            throw SpaceCreationFailure.invalidEncodedCommand
        }
        try set(value, at: path.dropFirst(), in: &child)
        object[key] = child
    }

    private static func remove(
        at path: ArraySlice<String>,
        in object: inout [String: Any]
    ) throws {
        guard let key = path.first else {
            throw SpaceCreationFailure.invalidEncodedCommand
        }
        if path.count == 1 {
            guard object.removeValue(forKey: key) != nil else {
                throw SpaceCreationFailure.invalidEncodedCommand
            }
            return
        }
        guard var child = object[key] as? [String: Any] else {
            throw SpaceCreationFailure.invalidEncodedCommand
        }
        try remove(at: path.dropFirst(), in: &child)
        object[key] = child
    }
}

private actor JournalSpaceCreationAdapter: SpaceCreating {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func create(_ command: CreateSpaceCommand) async throws -> OperationReceipt {
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

private struct FailingSpaceCreationAdapter: SpaceCreating {
    func create(_ command: CreateSpaceCommand) async throws -> OperationReceipt {
        throw SpaceCreationFailure.localAcceptanceFailed
    }
}
