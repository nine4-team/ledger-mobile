import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Archive Operation Contracts")
struct ProjectArchiveOperationTests {
    @Test("Archive is one revision-aware, history-preserving Project intent")
    func typedArchiveHasExactScopeAndPrecondition() throws {
        let command = try Self.command()

        #expect(command.draft.projectId.rawValue == "project-north")
        #expect(command.draft.expectedRevision == ExpectedProjectRevision(41))
        #expect(command.envelope.payload.projectId == command.draft.projectId)
        #expect(command.subject.kind == .project)
        #expect(command.subject.id.rawValue == command.draft.projectId.rawValue)
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: 41)
        ])

        let topLevelKeys = Set(try Self.jsonObject(
            OperationContractCodec.encode(command)
        ).keys)
        #expect(topLevelKeys == Set(["draft", "envelope", "fingerprint", "subject"]))

        let payloadKeys = try Self.objectKeys(
            OperationContractCodec.encode(command),
            path: ["envelope", "payload"]
        )
        #expect(payloadKeys == Set(["projectId"]))

        let encodedText = String(
            decoding: try OperationContractCodec.encode(command),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "clientid", "clientname", "displayname", "description", "category",
            "media", "attachment", "child", "delete", "restore", "unarchive",
            "isarchived", "field", "collection", "sql"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Canonical archive evidence survives structured offline restart")
    func canonicalRestartPreservesExactEvidence() throws {
        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
        let restored = try OperationContractCodec.decode(
            ArchiveProjectCommand.self,
            from: bytes
        )

        #expect(restored == command)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.envelope.operationId.rawValue == "operation-archive-project-north")
        #expect(restored.envelope.accountId.rawValue == "account-project-test")
        #expect(restored.envelope.actorPrincipalId.rawValue == "principal-project-test")
        #expect(restored.envelope.contractVersion.rawValue == "project-archive-v1")
        #expect(restored.envelope.clientCreatedAt == Self.t0)
        #expect(restored.fingerprint == (try OperationFingerprint.make(for: restored.envelope)))

        let changedRevision = try Self.command(
            operationID: "operation-archive-project-revision-42",
            revision: 42
        )
        #expect(changedRevision.fingerprint != command.fingerprint)

        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://", "file://",
            "bearer", "token", "secret", "serverresult", "server_result",
            "authorization", "authorized", "migrated", "production"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Invalid, rebound, and tampered archive evidence fails atomically")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.archiveFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidCapturedAt)
        #expect(Self.archiveFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidCapturedAt)

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
            value: "project-archive-v2"
        )
        #expect(Self.decodeFailure(changedContract) == .draftContractMismatch)
        let changedPayload = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "projectId"],
            value: "project-other"
        )
        #expect(Self.decodeFailure(changedPayload) == .draftPayloadMismatch)

        let revisionSubject = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "subject", "id"],
            value: "project-other"
        )
        #expect(Self.decodeFailure(revisionSubject) == .revisionPreconditionMismatch)
        let revisionValue = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "revision"],
            value: 42
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
        #expect(Self.archiveFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)

        #expect(Self.archiveFailure {
            try OperationContractCodec.decode(
                ProjectArchiveDraft.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(ProjectArchiveFailure, String)] = [
            (.invalidCapturedAt, "project_archive_captured_at_invalid"),
            (.draftAccountMismatch, "project_archive_account_mismatch"),
            (.draftActorMismatch, "project_archive_actor_mismatch"),
            (.draftContractMismatch, "project_archive_contract_mismatch"),
            (.draftPayloadMismatch, "project_archive_payload_mismatch"),
            (
                .revisionPreconditionMismatch,
                "project_archive_revision_precondition_mismatch"
            ),
            (.subjectMismatch, "project_archive_subject_mismatch"),
            (.fingerprintMismatch, "project_archive_fingerprint_mismatch"),
            (.receiptMismatch, "project_archive_receipt_mismatch"),
            (.localAcceptanceFailed, "project_archive_local_acceptance_failed"),
            (.invalidEncodedDraft, "project_archive_draft_encoding_invalid"),
            (.invalidEncodedCommand, "project_archive_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The reference port reuses shared queued receipt and replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalProjectArchiveAdapter(acceptedAt: Self.t1)
        let first = try await adapter.archive(command)
        let replay = try await adapter.archive(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let changedProject = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            projectID: "project-south"
        )
        do {
            _ = try await adapter.archive(changedProject)
            Issue.record("A reused OperationID accepted a changed Project archive target")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }

        let changedRevision = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            revision: 42
        )
        do {
            _ = try await adapter.archive(changedRevision)
            Issue.record("A reused OperationID accepted a changed Project revision")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingProjectArchiveAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.archive(command)
        } catch let failure as ProjectArchiveFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_700_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_700_001)

    private static func draft(
        projectID: String = "project-north",
        revision: UInt64 = 41,
        capturedAt: Date = t0
    ) throws -> ProjectArchiveDraft {
        try ProjectArchiveDraft(
            accountId: AccountID(validating: "account-project-test"),
            actorPrincipalId: PrincipalID(validating: "principal-project-test"),
            operationContractVersion: OperationContractVersion(
                validating: "project-archive-v1"
            ),
            projectId: ProjectID(validating: projectID),
            expectedRevision: ExpectedProjectRevision(revision),
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-archive-project-north",
        projectID: String = "project-north",
        revision: UInt64 = 41
    ) throws -> ArchiveProjectCommand {
        try ArchiveProjectCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(projectID: projectID, revision: revision)
        )
    }

    private static func archiveFailure<T>(
        _ operation: () throws -> T
    ) -> ProjectArchiveFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ProjectArchiveFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> ProjectArchiveFailure? {
        archiveFailure {
            try OperationContractCodec.decode(ArchiveProjectCommand.self, from: data)
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectArchiveFailure.invalidEncodedCommand
        }
        return object
    }

    private static func objectKeys(_ data: Data, path: [String]) throws -> Set<String> {
        var value: Any = try jsonObject(data)
        for key in path {
            guard let object = value as? [String: Any], let next = object[key] else {
                throw ProjectArchiveFailure.invalidEncodedCommand
            }
            value = next
        }
        guard let object = value as? [String: Any] else {
            throw ProjectArchiveFailure.invalidEncodedCommand
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
            throw ProjectArchiveFailure.invalidEncodedCommand
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
            throw ProjectArchiveFailure.invalidEncodedCommand
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
                    throw ProjectArchiveFailure.invalidEncodedCommand
                }
                try set(value, at: tail, in: &child)
                array[index] = child
            }
            object[key] = array
            return
        }
        throw ProjectArchiveFailure.invalidEncodedCommand
    }
}

private actor JournalProjectArchiveAdapter: ProjectArchiving {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func archive(_ command: ArchiveProjectCommand) async throws -> OperationReceipt {
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

private struct FailingProjectArchiveAdapter: ProjectArchiving {
    func archive(_ command: ArchiveProjectCommand) async throws -> OperationReceipt {
        throw ProjectArchiveFailure.localAcceptanceFailed
    }
}
