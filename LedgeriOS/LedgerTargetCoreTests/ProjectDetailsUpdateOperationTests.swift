import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Details Update Operation Contracts")
struct ProjectDetailsUpdateOperationTests {
    @Test("Description update is one normalized replacement on one revision-aware Project")
    func typedUpdateHasExactScopeAndNormalization() throws {
        let command = try Self.command(
            description: "  Client requested\nbench seating  "
        )
        let clear = try Self.command(
            operationID: "operation-clear-project-description",
            description: " \n\t "
        )

        #expect(command.draft.projectId.rawValue == "project-residence")
        #expect(command.draft.descriptionReplacement.value == "Client requested\nbench seating")
        #expect(clear.draft.descriptionReplacement.value == nil)
        #expect(ProjectDescriptionReplacement(nil).value == nil)
        #expect(command.envelope.payload.projectId == command.draft.projectId)
        #expect(command.envelope.payload.descriptionReplacement == command.draft.descriptionReplacement)
        #expect(command.subject.kind == .project)
        #expect(command.subject.id.rawValue == command.draft.projectId.rawValue)
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: 57)
        ])

        let topLevelKeys = Set(try Self.jsonObject(
            OperationContractCodec.encode(command)
        ).keys)
        #expect(topLevelKeys == Set(["draft", "envelope", "fingerprint", "subject"]))

        let payloadKeys = try Self.objectKeys(
            OperationContractCodec.encode(command),
            path: ["envelope", "payload"]
        )
        #expect(payloadKeys == Set(["projectId", "descriptionReplacement"]))
        let replacementKeys = try Self.objectKeys(
            OperationContractCodec.encode(clear),
            path: ["envelope", "payload", "descriptionReplacement"]
        )
        #expect(replacementKeys == Set(["value"]))

        let clearObject = try Self.jsonObject(OperationContractCodec.encode(clear))
        let clearEnvelope = try #require(clearObject["envelope"] as? [String: Any])
        let clearPayload = try #require(clearEnvelope["payload"] as? [String: Any])
        let clearReplacement = try #require(
            clearPayload["descriptionReplacement"] as? [String: Any]
        )
        #expect(clearReplacement["value"] is NSNull)

        let encodedText = String(
            decoding: try OperationContractCodec.encode(command),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "displayname", "projectname", "clientid", "category", "media", "image",
            "archive", "delete", "transaction", "invoice", "accounting", "history",
            "child", "field", "collection", "sql"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Canonical set and clear evidence survive structured offline restart")
    func canonicalRestartPreservesExactEvidence() throws {
        for command in [
            try Self.command(description: "Client requested\nbench seating"),
            try Self.command(
                operationID: "operation-clear-project-description",
                description: nil
            )
        ] {
            let bytes = try OperationContractCodec.encode(command)
            let restored = try OperationContractCodec.decode(
                UpdateProjectDetailsCommand.self,
                from: bytes
            )

            #expect(restored == command)
            #expect(try OperationContractCodec.encode(restored) == bytes)
            #expect(restored.envelope.accountId.rawValue == "account-project-test")
            #expect(restored.envelope.actorPrincipalId.rawValue == "principal-project-test")
            #expect(restored.envelope.contractVersion.rawValue == "project-details-update-v1")
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

    @Test("Noncanonical, rebound, and tampered Project details evidence fails atomically")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.detailsFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidCapturedAt)
        #expect(Self.detailsFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidCapturedAt)

        let command = try Self.command(description: "Client requested bench seating")
        let bytes = try OperationContractCodec.encode(command)
        let noncanonicalReplacement = try Self.mutate(
            bytes,
            path: ["draft", "descriptionReplacement", "value"],
            value: "  Client requested bench seating  "
        )
        #expect(Self.decodeFailure(noncanonicalReplacement) == .invalidEncodedDescriptionReplacement)
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
            value: "project-details-update-v2"
        )
        #expect(Self.decodeFailure(changedContract) == .draftContractMismatch)
        let changedProject = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "projectId"],
            value: "project-other"
        )
        #expect(Self.decodeFailure(changedProject) == .draftPayloadMismatch)
        let changedDescription = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "descriptionReplacement", "value"],
            value: "Different description"
        )
        #expect(Self.decodeFailure(changedDescription) == .draftPayloadMismatch)

        let revisionSubject = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "subject", "id"],
            value: "project-other"
        )
        #expect(Self.decodeFailure(revisionSubject) == .revisionPreconditionMismatch)
        let revisionValue = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "revision"],
            value: 58
        )
        #expect(Self.decodeFailure(revisionValue) == .revisionPreconditionMismatch)
        let noPreconditions = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions"],
            value: []
        )
        #expect(Self.decodeFailure(noPreconditions) == .revisionPreconditionMismatch)
        let duplicatePreconditions = try Self.duplicateFirstPrecondition(bytes)
        #expect(Self.decodeFailure(duplicatePreconditions) == .revisionPreconditionMismatch)

        let changedSubject = try Self.mutate(
            bytes,
            path: ["subject", "id"],
            value: "project-other"
        )
        #expect(Self.decodeFailure(changedSubject) == .subjectMismatch)
        let changedFingerprint = try Self.mutate(
            bytes,
            path: ["fingerprint"],
            value: String(repeating: "0", count: 64)
        )
        #expect(Self.decodeFailure(changedFingerprint) == .fingerprintMismatch)
        #expect(Self.detailsFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)

        #expect(Self.detailsFailure {
            try OperationContractCodec.decode(
                ProjectDescriptionReplacement.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDescriptionReplacement)
        #expect(Self.detailsFailure {
            try OperationContractCodec.decode(
                ProjectDetailsUpdateDraft.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(ProjectDetailsUpdateFailure, String)] = [
            (.invalidCapturedAt, "project_details_update_captured_at_invalid"),
            (.draftAccountMismatch, "project_details_update_account_mismatch"),
            (.draftActorMismatch, "project_details_update_actor_mismatch"),
            (.draftContractMismatch, "project_details_update_contract_mismatch"),
            (.draftPayloadMismatch, "project_details_update_payload_mismatch"),
            (
                .revisionPreconditionMismatch,
                "project_details_update_revision_precondition_mismatch"
            ),
            (.subjectMismatch, "project_details_update_subject_mismatch"),
            (.fingerprintMismatch, "project_details_update_fingerprint_mismatch"),
            (.receiptMismatch, "project_details_update_receipt_mismatch"),
            (.localAcceptanceFailed, "project_details_update_local_acceptance_failed"),
            (
                .invalidEncodedDescriptionReplacement,
                "project_details_update_description_replacement_encoding_invalid"
            ),
            (.invalidEncodedDraft, "project_details_update_draft_encoding_invalid"),
            (.invalidEncodedCommand, "project_details_update_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The Project details port reuses shared queued receipt and replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command(description: "Client requested bench seating")
        let adapter = JournalProjectDetailsUpdateAdapter(acceptedAt: Self.t1)
        let first = try await adapter.updateDetails(command)
        let replay = try await adapter.updateDetails(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let changedProject = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            projectID: "project-other",
            description: "Client requested bench seating"
        )
        do {
            _ = try await adapter.updateDetails(changedProject)
            Issue.record("A reused OperationID accepted a changed Project target")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }

        let changedDescription = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            description: "Different description"
        )
        do {
            _ = try await adapter.updateDetails(changedDescription)
            Issue.record("A reused OperationID accepted a changed Project description")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }

        let changedRevision = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            description: "Client requested bench seating",
            revision: 58
        )
        do {
            _ = try await adapter.updateDetails(changedRevision)
            Issue.record("A reused OperationID accepted a changed Project revision")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingProjectDetailsUpdateAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.updateDetails(command)
        } catch let failure as ProjectDetailsUpdateFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_900_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_900_001)

    private static func draft(
        projectID: String = "project-residence",
        description: String? = "Client requested bench seating",
        revision: UInt64 = 57,
        capturedAt: Date = t0
    ) throws -> ProjectDetailsUpdateDraft {
        try ProjectDetailsUpdateDraft(
            accountId: AccountID(validating: "account-project-test"),
            actorPrincipalId: PrincipalID(validating: "principal-project-test"),
            operationContractVersion: OperationContractVersion(
                validating: "project-details-update-v1"
            ),
            projectId: ProjectID(validating: projectID),
            descriptionReplacement: ProjectDescriptionReplacement(description),
            expectedRevision: ExpectedProjectRevision(revision),
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-update-project-description",
        projectID: String = "project-residence",
        description: String? = "Client requested bench seating",
        revision: UInt64 = 57
    ) throws -> UpdateProjectDetailsCommand {
        try UpdateProjectDetailsCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(
                projectID: projectID,
                description: description,
                revision: revision
            )
        )
    }

    private static func detailsFailure<T>(
        _ operation: () throws -> T
    ) -> ProjectDetailsUpdateFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ProjectDetailsUpdateFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> ProjectDetailsUpdateFailure? {
        detailsFailure {
            try OperationContractCodec.decode(UpdateProjectDetailsCommand.self, from: data)
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectDetailsUpdateFailure.invalidEncodedCommand
        }
        return object
    }

    private static func objectKeys(_ data: Data, path: [String]) throws -> Set<String> {
        var value: Any = try jsonObject(data)
        for key in path {
            guard let object = value as? [String: Any], let next = object[key] else {
                throw ProjectDetailsUpdateFailure.invalidEncodedCommand
            }
            value = next
        }
        guard let object = value as? [String: Any] else {
            throw ProjectDetailsUpdateFailure.invalidEncodedCommand
        }
        return Set(object.keys)
    }

    private static func mutate(_ data: Data, path: [String], value: Any) throws -> Data {
        var object = try jsonObject(data)
        try Self.set(value, at: path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func duplicateFirstPrecondition(_ data: Data) throws -> Data {
        var object = try jsonObject(data)
        guard var envelope = object["envelope"] as? [String: Any],
              var preconditions = envelope["preconditions"] as? [Any],
              let first = preconditions.first else {
            throw ProjectDetailsUpdateFailure.invalidEncodedCommand
        }
        preconditions.append(first)
        envelope["preconditions"] = preconditions
        object["envelope"] = envelope
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func set(
        _ value: Any,
        at path: ArraySlice<String>,
        in object: inout [String: Any]
    ) throws {
        guard let key = path.first else {
            throw ProjectDetailsUpdateFailure.invalidEncodedCommand
        }
        if path.count == 1 {
            object[key] = value
            return
        }

        let remaining = path.dropFirst()
        if var child = object[key] as? [String: Any] {
            try set(value, at: remaining, in: &child)
            object[key] = child
            return
        }
        if var array = object[key] as? [Any],
           let index = Int(remaining.first ?? ""),
           array.indices.contains(index) {
            let tail = remaining.dropFirst()
            if tail.isEmpty {
                array[index] = value
            } else {
                guard var child = array[index] as? [String: Any] else {
                    throw ProjectDetailsUpdateFailure.invalidEncodedCommand
                }
                try set(value, at: tail, in: &child)
                array[index] = child
            }
            object[key] = array
            return
        }
        throw ProjectDetailsUpdateFailure.invalidEncodedCommand
    }
}

private actor JournalProjectDetailsUpdateAdapter: ProjectDetailsUpdating {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func updateDetails(
        _ command: UpdateProjectDetailsCommand
    ) async throws -> OperationReceipt {
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

private struct FailingProjectDetailsUpdateAdapter: ProjectDetailsUpdating {
    func updateDetails(
        _ command: UpdateProjectDetailsCommand
    ) async throws -> OperationReceipt {
        throw ProjectDetailsUpdateFailure.localAcceptanceFailed
    }
}
