import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Client Rename Operation Contracts")
struct ClientRenameOperationTests {
    @Test("Rename changes only current display text for one stable Client revision")
    func typedRenameHasExactScopeAndPrecondition() throws {
        let command = try Self.command()

        #expect(command.draft.clientId.rawValue == "client-north")
        #expect(command.draft.newDisplayName.rawValue == "North Family")
        #expect(command.draft.expectedRevision == ExpectedClientRevision(17))
        #expect(command.envelope.payload.clientId == command.draft.clientId)
        #expect(command.envelope.payload.displayName == command.draft.newDisplayName)
        #expect(command.subject.kind == .client)
        #expect(command.subject.id.rawValue == command.draft.clientId.rawValue)
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: 17)
        ])

        let topLevelKeys = Set(try Self.jsonObject(
            OperationContractCodec.encode(command)
        ).keys)
        #expect(topLevelKeys == Set(["draft", "envelope", "fingerprint", "subject"]))
        let payloadKeys = try Self.objectKeys(
            OperationContractCodec.encode(command),
            path: ["envelope", "payload"]
        )
        #expect(payloadKeys == Set(["clientId", "displayName"]))

        let encodedText = String(
            decoding: try OperationContractCodec.encode(command),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "projectid", "clientname", "oldname", "lifecycle", "archive", "delete",
            "merge", "alias", "reassign", "invoice", "report", "paid", "history",
            "attachment", "field", "collection", "sql"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Canonical rename evidence survives structured offline restart")
    func canonicalRestartPreservesExactEvidence() throws {
        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
        let restored = try OperationContractCodec.decode(RenameClientCommand.self, from: bytes)

        #expect(restored == command)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.envelope.operationId.rawValue == "operation-rename-client-north")
        #expect(restored.envelope.accountId.rawValue == "account-client-rename-test")
        #expect(restored.envelope.actorPrincipalId.rawValue == "principal-client-rename-test")
        #expect(restored.envelope.contractVersion.rawValue == "client-rename-v1")
        #expect(restored.envelope.clientCreatedAt == Self.t0)
        #expect(restored.fingerprint == (try OperationFingerprint.make(for: restored.envelope)))

        let changedName = try Self.command(
            operationID: "operation-rename-client-north-again",
            displayName: "North Household"
        )
        #expect(changedName.fingerprint != command.fingerprint)

        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://", "file://",
            "bearer", "token", "secret", "serverresult", "server_result",
            "authorization", "authorized", "migrated", "production"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Invalid, rebound, and tampered rename evidence fails atomically")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.directoryFailure {
            try ClientDisplayName(validating: "  \n ")
        } == .invalidClientDisplayName)
        #expect(Self.renameFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidCapturedAt)
        #expect(Self.renameFailure {
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
            value: "client-rename-v2"
        )
        #expect(Self.decodeFailure(changedContract) == .draftContractMismatch)
        let changedPayloadClient = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "clientId"],
            value: "client-other"
        )
        #expect(Self.decodeFailure(changedPayloadClient) == .draftPayloadMismatch)
        let changedPayloadName = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "displayName"],
            value: "Other Name"
        )
        #expect(Self.decodeFailure(changedPayloadName) == .draftPayloadMismatch)
        let changedDraftName = try Self.mutate(
            bytes,
            path: ["draft", "newDisplayName"],
            value: "Another Name"
        )
        #expect(Self.decodeFailure(changedDraftName) == .draftPayloadMismatch)

        let revisionSubject = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "subject", "id"],
            value: "client-other"
        )
        #expect(Self.decodeFailure(revisionSubject) == .revisionPreconditionMismatch)
        let revisionValue = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "revision"],
            value: 18
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
        #expect(Self.renameFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)

        #expect(Self.renameFailure {
            try OperationContractCodec.decode(ClientRenameDraft.self, from: Data("{}".utf8))
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(ClientRenameFailure, String)] = [
            (.invalidCapturedAt, "client_rename_captured_at_invalid"),
            (.draftAccountMismatch, "client_rename_account_mismatch"),
            (.draftActorMismatch, "client_rename_actor_mismatch"),
            (.draftContractMismatch, "client_rename_contract_mismatch"),
            (.draftPayloadMismatch, "client_rename_payload_mismatch"),
            (
                .revisionPreconditionMismatch,
                "client_rename_revision_precondition_mismatch"
            ),
            (.subjectMismatch, "client_rename_subject_mismatch"),
            (.fingerprintMismatch, "client_rename_fingerprint_mismatch"),
            (.receiptMismatch, "client_rename_receipt_mismatch"),
            (.localAcceptanceFailed, "client_rename_local_acceptance_failed"),
            (.invalidEncodedDraft, "client_rename_draft_encoding_invalid"),
            (.invalidEncodedCommand, "client_rename_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The reference port reuses shared queued receipt and replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalClientRenameAdapter(acceptedAt: Self.t1)
        let first = try await adapter.rename(command)
        let replay = try await adapter.rename(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let changedClient = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            clientID: "client-south"
        )
        do {
            _ = try await adapter.rename(changedClient)
            Issue.record("A reused OperationID accepted a changed Client target")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }

        let changedName = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            displayName: "North Household"
        )
        do {
            _ = try await adapter.rename(changedName)
            Issue.record("A reused OperationID accepted changed Client display text")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }

        let changedRevision = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            revision: 18
        )
        do {
            _ = try await adapter.rename(changedRevision)
            Issue.record("A reused OperationID accepted a changed Client revision")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingClientRenameAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.rename(command)
        } catch let failure as ClientRenameFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_801_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_801_000_001)

    private static func draft(
        clientID: String = "client-north",
        displayName: String = "North Family",
        revision: UInt64 = 17,
        capturedAt: Date = t0
    ) throws -> ClientRenameDraft {
        try ClientRenameDraft(
            accountId: AccountID(validating: "account-client-rename-test"),
            actorPrincipalId: PrincipalID(validating: "principal-client-rename-test"),
            operationContractVersion: OperationContractVersion(
                validating: "client-rename-v1"
            ),
            clientId: ClientID(validating: clientID),
            newDisplayName: ClientDisplayName(validating: displayName),
            expectedRevision: ExpectedClientRevision(revision),
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-rename-client-north",
        clientID: String = "client-north",
        displayName: String = "North Family",
        revision: UInt64 = 17
    ) throws -> RenameClientCommand {
        try RenameClientCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(
                clientID: clientID,
                displayName: displayName,
                revision: revision
            )
        )
    }

    private static func renameFailure<T>(
        _ operation: () throws -> T
    ) -> ClientRenameFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ClientRenameFailure {
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

    private static func decodeFailure(_ data: Data) -> ClientRenameFailure? {
        renameFailure {
            try OperationContractCodec.decode(RenameClientCommand.self, from: data)
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientRenameFailure.invalidEncodedCommand
        }
        return object
    }

    private static func objectKeys(_ data: Data, path: [String]) throws -> Set<String> {
        var value: Any = try jsonObject(data)
        for key in path {
            guard let object = value as? [String: Any], let next = object[key] else {
                throw ClientRenameFailure.invalidEncodedCommand
            }
            value = next
        }
        guard let object = value as? [String: Any] else {
            throw ClientRenameFailure.invalidEncodedCommand
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
            throw ClientRenameFailure.invalidEncodedCommand
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
            throw ClientRenameFailure.invalidEncodedCommand
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
                    throw ClientRenameFailure.invalidEncodedCommand
                }
                try set(value, at: tail, in: &child)
                array[index] = child
            }
            object[key] = array
            return
        }
        throw ClientRenameFailure.invalidEncodedCommand
    }
}

private actor JournalClientRenameAdapter: ClientRenaming {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func rename(_ command: RenameClientCommand) async throws -> OperationReceipt {
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

private struct FailingClientRenameAdapter: ClientRenaming {
    func rename(_ command: RenameClientCommand) async throws -> OperationReceipt {
        throw ClientRenameFailure.localAcceptanceFailed
    }
}
