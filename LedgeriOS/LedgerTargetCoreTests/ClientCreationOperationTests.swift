import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Client Creation Operation Contracts")
struct ClientCreationOperationTests {
    @Test("A typed command preserves stable Client identity independent of display text")
    func typedCommandPreservesIdentity() throws {
        let first = try Self.command(clientID: "client-north")
        let second = try Self.command(
            operationID: "operation-create-client-south",
            clientID: "client-south"
        )

        #expect(first.draft.displayName.rawValue == "North House")
        #expect(first.envelope.payload.displayName == second.envelope.payload.displayName)
        #expect(first.draft.clientId != second.draft.clientId)
        #expect(first.subject != second.subject)
        #expect(first.fingerprint != second.fingerprint)
        #expect(first.subject.kind == .client)
        #expect(first.subject.id.rawValue == first.draft.clientId.rawValue)
        #expect(first.envelope.preconditions.isEmpty)
        #expect(first.envelope.accountId == first.draft.accountId)
        #expect(first.envelope.actorPrincipalId == first.draft.actorPrincipalId)
        #expect(first.envelope.contractVersion == first.draft.operationContractVersion)

        let keys = Set(try Self.jsonObject(OperationContractCodec.encode(first)).keys)
        #expect(keys == Set(["draft", "envelope", "fingerprint", "subject"]))
        let encodedText = String(
            decoding: try OperationContractCodec.encode(first),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "clientname", "lifecycle", "archive", "merge", "reassign", "collection", "sql"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Canonical command evidence survives structured restart without provider claims")
    func canonicalRestartIsByteIdentical() throws {
        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
        let restored = try OperationContractCodec.decode(
            CreateClientCommand.self,
            from: bytes
        )

        #expect(restored == command)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.envelope.operationId.rawValue == "operation-create-client-north")
        #expect(restored.envelope.accountId.rawValue == "account-client-test")
        #expect(restored.envelope.actorPrincipalId.rawValue == "principal-client-test")
        #expect(restored.envelope.contractVersion.rawValue == "client-create-v1")
        #expect(restored.envelope.clientCreatedAt == Self.t0)
        #expect(restored.subject.kind == .client)
        let expectedFingerprint = try OperationFingerprint.make(for: restored.envelope)
        #expect(restored.fingerprint == expectedFingerprint)

        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://", "file://",
            "collection/", "bearer", "token", "secret", "serverresult", "server_result"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Invalid, rebound, and tampered creation evidence fails atomically")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.directoryFailure {
            try ClientDisplayName(validating: " \n\t ")
        } == .invalidClientDisplayName)
        #expect(Self.creationFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidClientCreatedAt)
        #expect(Self.creationFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidClientCreatedAt)

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
            value: "client-create-v2"
        )
        #expect(Self.decodeFailure(changedContract) == .draftContractMismatch)
        let changedPayload = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "clientId"],
            value: "client-other"
        )
        #expect(Self.decodeFailure(changedPayload) == .draftPayloadMismatch)

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
            value: "project"
        )
        #expect(Self.decodeFailure(changedSubject) == .subjectMismatch)
        let changedFingerprint = try Self.mutate(
            bytes,
            path: ["fingerprint"],
            value: String(repeating: "0", count: 64)
        )
        #expect(Self.decodeFailure(changedFingerprint) == .fingerprintMismatch)
        #expect(Self.creationFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(ClientCreationFailure, String)] = [
            (.invalidClientCreatedAt, "client_creation_created_at_invalid"),
            (.draftAccountMismatch, "client_creation_account_mismatch"),
            (.draftActorMismatch, "client_creation_actor_mismatch"),
            (.draftContractMismatch, "client_creation_contract_mismatch"),
            (.draftPayloadMismatch, "client_creation_payload_mismatch"),
            (.unexpectedPreconditions, "client_creation_preconditions_unexpected"),
            (.subjectMismatch, "client_creation_subject_mismatch"),
            (.fingerprintMismatch, "client_creation_fingerprint_mismatch"),
            (.receiptMismatch, "client_creation_receipt_mismatch"),
            (.localAcceptanceFailed, "client_creation_local_acceptance_failed"),
            (.invalidEncodedCommand, "client_creation_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The reference port reuses shared queued receipt and replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalClientCreationAdapter(acceptedAt: Self.t1)
        let first = try await adapter.create(command)
        let replay = try await adapter.create(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let changed = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            clientID: "client-other"
        )
        do {
            _ = try await adapter.create(changed)
            Issue.record("A reused OperationID accepted a changed Client payload")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingClientCreationAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.create(command)
        } catch let failure as ClientCreationFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_500_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_500_001)

    private static func draft(
        capturedAt: Date = t0,
        clientID: String = "client-north"
    ) throws -> ClientCreationDraft {
        try ClientCreationDraft(
            accountId: AccountID(validating: "account-client-test"),
            actorPrincipalId: PrincipalID(validating: "principal-client-test"),
            operationContractVersion: OperationContractVersion(validating: "client-create-v1"),
            clientId: ClientID(validating: clientID),
            displayName: ClientDisplayName(validating: "North House"),
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-create-client-north",
        clientID: String = "client-north"
    ) throws -> CreateClientCommand {
        try CreateClientCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(clientID: clientID)
        )
    }

    private static func creationFailure<T>(
        _ operation: () throws -> T
    ) -> ClientCreationFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ClientCreationFailure {
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

    private static func decodeFailure(_ data: Data) -> ClientCreationFailure? {
        creationFailure {
            try OperationContractCodec.decode(CreateClientCommand.self, from: data)
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientCreationFailure.invalidEncodedCommand
        }
        return object
    }

    private static func mutate(_ data: Data, path: [String], value: Any) throws -> Data {
        var object = try jsonObject(data)
        try Self.set(value, at: path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func set(
        _ value: Any,
        at path: ArraySlice<String>,
        in object: inout [String: Any]
    ) throws {
        guard let key = path.first else {
            throw ClientCreationFailure.invalidEncodedCommand
        }
        if path.count == 1 {
            object[key] = value
            return
        }
        guard var child = object[key] as? [String: Any] else {
            throw ClientCreationFailure.invalidEncodedCommand
        }
        try set(value, at: path.dropFirst(), in: &child)
        object[key] = child
    }
}

private actor JournalClientCreationAdapter: ClientCreationOperating {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func create(_ command: CreateClientCommand) async throws -> OperationReceipt {
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

private struct FailingClientCreationAdapter: ClientCreationOperating {
    func create(_ command: CreateClientCommand) async throws -> OperationReceipt {
        throw ClientCreationFailure.localAcceptanceFailed
    }
}
