import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Client Archive Operation Contracts")
struct ClientArchiveOperationTests {
    @Test("Archive is one revision-aware Client intent with no dependent mutation")
    func typedArchiveHasExactScopeAndPrecondition() throws {
        let command = try Self.command()

        #expect(command.draft.clientId.rawValue == "client-acme")
        #expect(command.draft.expectedRevision == ExpectedClientRevision(43))
        #expect(command.envelope.payload.clientId == command.draft.clientId)
        #expect(command.subject.kind == .client)
        #expect(command.subject.id.rawValue == command.draft.clientId.rawValue)
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: 43)
        ])

        let topLevelKeys = Set(try Self.jsonObject(
            OperationContractCodec.encode(command)
        ).keys)
        #expect(topLevelKeys == Set(["draft", "envelope", "fingerprint", "subject"]))

        let payloadKeys = try Self.objectKeys(
            OperationContractCodec.encode(command),
            path: ["envelope", "payload"]
        )
        #expect(payloadKeys == Set(["clientId"]))

        let encodedText = String(
            decoding: try OperationContractCodec.encode(command),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "projectid", "projects", "clientname", "displayname", "history",
            "transaction", "invoice", "accounting", "delete", "merge", "restore",
            "unarchive", "isarchived", "replacementclient", "reassign", "field",
            "collection", "sql"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Canonical Client archive evidence survives structured offline restart")
    func canonicalRestartPreservesExactEvidence() throws {
        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
        let restored = try OperationContractCodec.decode(
            ArchiveClientCommand.self,
            from: bytes
        )

        #expect(restored == command)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.envelope.operationId.rawValue == "operation-archive-client-acme")
        #expect(restored.envelope.accountId.rawValue == "account-client-test")
        #expect(restored.envelope.actorPrincipalId.rawValue == "principal-client-test")
        #expect(restored.envelope.contractVersion.rawValue == "client-archive-v1")
        #expect(restored.envelope.clientCreatedAt == Self.t0)
        #expect(restored.fingerprint == (try OperationFingerprint.make(for: restored.envelope)))

        let changedRevision = try Self.command(
            operationID: "operation-archive-client-revision-44",
            revision: 44
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

    @Test("Invalid, rebound, and tampered Client archive evidence fails atomically")
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
            value: "client-archive-v2"
        )
        #expect(Self.decodeFailure(changedContract) == .draftContractMismatch)
        let changedPayload = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "clientId"],
            value: "client-other"
        )
        #expect(Self.decodeFailure(changedPayload) == .draftPayloadMismatch)

        let revisionSubject = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "subject", "id"],
            value: "client-other"
        )
        #expect(Self.decodeFailure(revisionSubject) == .revisionPreconditionMismatch)
        let revisionValue = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "revision"],
            value: 44
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
            value: "project"
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
                ClientArchiveDraft.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(ClientArchiveFailure, String)] = [
            (.invalidCapturedAt, "client_archive_captured_at_invalid"),
            (.draftAccountMismatch, "client_archive_account_mismatch"),
            (.draftActorMismatch, "client_archive_actor_mismatch"),
            (.draftContractMismatch, "client_archive_contract_mismatch"),
            (.draftPayloadMismatch, "client_archive_payload_mismatch"),
            (
                .revisionPreconditionMismatch,
                "client_archive_revision_precondition_mismatch"
            ),
            (.subjectMismatch, "client_archive_subject_mismatch"),
            (.fingerprintMismatch, "client_archive_fingerprint_mismatch"),
            (.receiptMismatch, "client_archive_receipt_mismatch"),
            (.localAcceptanceFailed, "client_archive_local_acceptance_failed"),
            (.invalidEncodedDraft, "client_archive_draft_encoding_invalid"),
            (.invalidEncodedCommand, "client_archive_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The Client archive port reuses shared queued receipt and replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalClientArchiveAdapter(acceptedAt: Self.t1)
        let first = try await adapter.archive(command)
        let replay = try await adapter.archive(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let changedClient = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            clientID: "client-globex"
        )
        do {
            _ = try await adapter.archive(changedClient)
            Issue.record("A reused OperationID accepted a changed Client archive target")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }

        let changedRevision = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            revision: 44
        )
        do {
            _ = try await adapter.archive(changedRevision)
            Issue.record("A reused OperationID accepted a changed Client revision")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingClientArchiveAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.archive(command)
        } catch let failure as ClientArchiveFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_800_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_800_001)

    private static func draft(
        clientID: String = "client-acme",
        revision: UInt64 = 43,
        capturedAt: Date = t0
    ) throws -> ClientArchiveDraft {
        try ClientArchiveDraft(
            accountId: AccountID(validating: "account-client-test"),
            actorPrincipalId: PrincipalID(validating: "principal-client-test"),
            operationContractVersion: OperationContractVersion(
                validating: "client-archive-v1"
            ),
            clientId: ClientID(validating: clientID),
            expectedRevision: ExpectedClientRevision(revision),
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-archive-client-acme",
        clientID: String = "client-acme",
        revision: UInt64 = 43
    ) throws -> ArchiveClientCommand {
        try ArchiveClientCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(clientID: clientID, revision: revision)
        )
    }

    private static func archiveFailure<T>(
        _ operation: () throws -> T
    ) -> ClientArchiveFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ClientArchiveFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> ClientArchiveFailure? {
        archiveFailure {
            try OperationContractCodec.decode(ArchiveClientCommand.self, from: data)
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientArchiveFailure.invalidEncodedCommand
        }
        return object
    }

    private static func objectKeys(_ data: Data, path: [String]) throws -> Set<String> {
        var value: Any = try jsonObject(data)
        for key in path {
            guard let object = value as? [String: Any], let next = object[key] else {
                throw ClientArchiveFailure.invalidEncodedCommand
            }
            value = next
        }
        guard let object = value as? [String: Any] else {
            throw ClientArchiveFailure.invalidEncodedCommand
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
            throw ClientArchiveFailure.invalidEncodedCommand
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
            throw ClientArchiveFailure.invalidEncodedCommand
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
                    throw ClientArchiveFailure.invalidEncodedCommand
                }
                try set(value, at: tail, in: &child)
                array[index] = child
            }
            object[key] = array
            return
        }
        throw ClientArchiveFailure.invalidEncodedCommand
    }
}

private actor JournalClientArchiveAdapter: ClientArchiving {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func archive(_ command: ArchiveClientCommand) async throws -> OperationReceipt {
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

private struct FailingClientArchiveAdapter: ClientArchiving {
    func archive(_ command: ArchiveClientCommand) async throws -> OperationReceipt {
        throw ClientArchiveFailure.localAcceptanceFailed
    }
}
