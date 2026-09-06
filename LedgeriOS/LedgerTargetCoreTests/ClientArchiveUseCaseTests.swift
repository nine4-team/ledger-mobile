import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Client Archive Use Case Contracts")
struct ClientArchiveUseCaseTests {
    @Test("Archive intent has exact transient identity and revision shape")
    func exactTransientIntent() throws {
        let zero = try Self.intent(revision: 0)
        let maximum = try Self.intent(clientID: "client-maximum", revision: UInt64.max)

        #expect(zero.expectedRevision == ExpectedClientRevision(0))
        #expect(maximum.expectedRevision == ExpectedClientRevision(UInt64.max))
        #expect(zero.clientId != maximum.clientId)
        Self.requireEquatableAndSendable(ClientArchiveIntent.self)
        #expect(!(ClientArchiveIntent.self is any Codable.Type))
        #expect(Set(Mirror(reflecting: zero).children.compactMap(\.label)) == [
            "accountId", "clientId", "expectedRevision"
        ])
    }

    @Test("Every receipt state returns exactly after one archive dispatch")
    func exactReceiptStatesAndCommand() async throws {
        for localState in LocalOperationState.allCases {
            let operationID = try OperationID(
                validating: "operation-client-archive-\(localState.rawValue)"
            )
            let archiver = RecordingClientArchiver(response: .matching(localState))
            let receipt = try await ClientArchiveUseCase(archiver: archiver).execute(
                intent: try Self.intent(
                    accountID: "account-exact",
                    clientID: "client-exact",
                    revision: 73
                ),
                operationId: operationID,
                actorPrincipalId: PrincipalID(validating: "principal-exact"),
                operationContractVersion: OperationContractVersion(
                    validating: "client-archive-v7"
                ),
                capturedAt: Self.t0
            )

            #expect(receipt.operationId == operationID)
            #expect(receipt.localState == localState)
            let commands = await archiver.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            try Self.expectCommand(
                command,
                accountID: "account-exact",
                clientID: "client-exact",
                revision: 73,
                operationID: operationID.rawValue,
                actorID: "principal-exact",
                contractVersion: "client-archive-v7",
                capturedAt: Self.t0
            )
            #expect(try command.validate(receipt) == receipt)
        }
    }

    @Test("Every caller field forwards into existing archive evidence")
    func reciprocalFieldForwarding() async throws {
        let baseline = try await Self.recordedCommand()
        let changedAccount = try await Self.recordedCommand(accountID: "account-other")
        let changedClient = try await Self.recordedCommand(clientID: "client-other")
        let changedRevision = try await Self.recordedCommand(revision: UInt64.max)
        let changedOperation = try await Self.recordedCommand(operationID: "operation-other")
        let changedActor = try await Self.recordedCommand(actorID: "principal-other")
        let changedContract = try await Self.recordedCommand(
            contractVersion: "client-archive-v2"
        )
        let changedTime = try await Self.recordedCommand(capturedAt: Self.t1)

        try Self.expectCommand(baseline)
        try Self.expectCommand(changedAccount, accountID: "account-other")
        try Self.expectCommand(changedClient, clientID: "client-other")
        try Self.expectCommand(changedRevision, revision: UInt64.max)
        try Self.expectCommand(changedOperation, operationID: "operation-other")
        try Self.expectCommand(changedActor, actorID: "principal-other")
        try Self.expectCommand(changedContract, contractVersion: "client-archive-v2")
        try Self.expectCommand(changedTime, capturedAt: Self.t1)
    }

    @Test("Construction failure precedes dispatch and receipts cannot mismatch")
    func validationPrecedesDispatch() async throws {
        let invalidTime = RecordingClientArchiver(response: .matching(.queued))
        do {
            _ = try await ClientArchiveUseCase(archiver: invalidTime).execute(
                intent: try Self.intent(),
                operationId: OperationID(validating: "operation-invalid-time"),
                actorPrincipalId: PrincipalID(validating: "principal-test"),
                operationContractVersion: OperationContractVersion(
                    validating: "client-archive-v1"
                ),
                capturedAt: Date(timeIntervalSinceReferenceDate: .infinity)
            )
            Issue.record("Nonfinite capture time returned a receipt")
        } catch let failure as ClientArchiveFailure {
            #expect(failure == .invalidCapturedAt)
        }
        #expect(await invalidTime.recordedCommands().isEmpty)

        let invalidNaN = RecordingClientArchiver(response: .matching(.queued))
        do {
            _ = try await ClientArchiveUseCase(archiver: invalidNaN).execute(
                intent: try Self.intent(),
                operationId: OperationID(validating: "operation-invalid-nan"),
                actorPrincipalId: PrincipalID(validating: "principal-test"),
                operationContractVersion: OperationContractVersion(
                    validating: "client-archive-v1"
                ),
                capturedAt: Date(timeIntervalSinceReferenceDate: .nan)
            )
            Issue.record("NaN capture time returned a receipt")
        } catch let failure as ClientArchiveFailure {
            #expect(failure == .invalidCapturedAt)
        }
        #expect(await invalidNaN.recordedCommands().isEmpty)

        let mismatched = RecordingClientArchiver(
            response: .mismatched(
                try OperationID(validating: "operation-wrong-receipt")
            )
        )
        do {
            _ = try await Self.execute(
                using: mismatched,
                operationID: "operation-expected-receipt"
            )
            Issue.record("Mismatched receipt returned")
        } catch let failure as ClientArchiveFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatched.recordedCommands().count == 1)
    }

    @Test("Normalized, raw, and cancellation failures stay distinct")
    func boundedFailures() async throws {
        let normalized = RecordingClientArchiver(response: .archiveFailure(.subjectMismatch))
        do {
            _ = try await Self.execute(using: normalized, operationID: "operation-normalized")
            Issue.record("Normalized failure returned a receipt")
        } catch let failure as ClientArchiveFailure {
            #expect(failure == .subjectMismatch)
        }
        #expect(await normalized.recordedCommands().count == 1)

        let raw = RecordingClientArchiver(response: .rawFailure)
        do {
            _ = try await Self.execute(using: raw, operationID: "operation-raw")
            Issue.record("Raw failure returned a receipt")
        } catch let failure as ClientArchiveFailure {
            #expect(failure == .localAcceptanceFailed)
            #expect(failure.diagnosticCode == "client_archive_local_acceptance_failed")
            #expect(!failure.diagnosticCode.contains("raw-provider-detail"))
        }
        #expect(await raw.recordedCommands().count == 1)

        let cancelled = RecordingClientArchiver(response: .cancelled)
        do {
            _ = try await Self.execute(using: cancelled, operationID: "operation-cancelled")
            Issue.record("Cancellation returned a receipt")
        } catch is CancellationError {
            // Expected structured-concurrency control flow.
        } catch {
            Issue.record("Cancellation was rewritten as: \(error)")
        }
        #expect(await cancelled.recordedCommands().count == 1)
    }

    @Test("Diagnostics and encoded command remain inside archive-only boundary")
    func diagnosticsAndCommandShape() async throws {
        let diagnostics: [(ClientArchiveFailure, String)] = [
            (.invalidCapturedAt, "client_archive_captured_at_invalid"),
            (.draftAccountMismatch, "client_archive_account_mismatch"),
            (.draftActorMismatch, "client_archive_actor_mismatch"),
            (.draftContractMismatch, "client_archive_contract_mismatch"),
            (.draftPayloadMismatch, "client_archive_payload_mismatch"),
            (.revisionPreconditionMismatch, "client_archive_revision_precondition_mismatch"),
            (.subjectMismatch, "client_archive_subject_mismatch"),
            (.fingerprintMismatch, "client_archive_fingerprint_mismatch"),
            (.receiptMismatch, "client_archive_receipt_mismatch"),
            (.localAcceptanceFailed, "client_archive_local_acceptance_failed"),
            (.invalidEncodedDraft, "client_archive_draft_encoding_invalid"),
            (.invalidEncodedCommand, "client_archive_command_encoding_invalid")
        ]
        for (failure, expected) in diagnostics {
            let diagnostic = failure.diagnosticCode
            #expect(diagnostic == expected)
            for forbidden in [
                "account-client-use-case", "client-residence",
                "operation-client-archive", "principal-client-use-case",
                "raw-provider-detail", "firebase", "supabase", "powersync"
            ] {
                #expect(!diagnostic.contains(forbidden))
            }
        }

        let command = try await Self.recordedCommand()
        let encoded = try OperationContractCodec.encode(command)
        let root = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(Set(root.keys) == ["draft", "envelope", "subject", "fingerprint"])

        let draft = try #require(root["draft"] as? [String: Any])
        #expect(Set(draft.keys) == [
            "accountId", "actorPrincipalId", "operationContractVersion",
            "clientId", "expectedRevision", "capturedAt"
        ])
        let expectedRevision = try #require(
            draft["expectedRevision"] as? [String: Any]
        )
        #expect(Set(expectedRevision.keys) == ["rawValue"])

        let envelope = try #require(root["envelope"] as? [String: Any])
        #expect(Set(envelope.keys) == [
            "operationId", "contractVersion", "accountId", "actorPrincipalId",
            "clientCreatedAt", "payload", "preconditions"
        ])
        let payload = try #require(envelope["payload"] as? [String: Any])
        #expect(Set(payload.keys) == ["clientId"])
        let preconditions = try #require(envelope["preconditions"] as? [[String: Any]])
        #expect(preconditions.count == 1)
        let precondition = try #require(preconditions.first)
        #expect(Set(precondition.keys) == ["expectedRevision"])
        let revisionBody = try #require(
            precondition["expectedRevision"] as? [String: Any]
        )
        #expect(Set(revisionBody.keys) == ["subject", "revision"])
        let revisionSubject = try #require(
            revisionBody["subject"] as? [String: Any]
        )
        #expect(Set(revisionSubject.keys) == ["kind", "id"])

        let subject = try #require(root["subject"] as? [String: Any])
        #expect(Set(subject.keys) == ["kind", "id"])
        let fingerprint = try #require(root["fingerprint"] as? String)
        #expect(fingerprint.utf8.count == 64)

        let text = String(decoding: encoded, as: UTF8.self).lowercased()
        for required in [
            "account-client-use-case", "client-residence",
            "operation-client-archive", "principal-client-use-case",
            "client-archive-v1", "expectedrevision"
        ] {
            #expect(text.contains(required))
        }
        for forbidden in [
            "restore", "unarchive", "delete", "merge", "rename", "lifecycle",
            "isarchived", "displayname", "projectid", "projectlist", "cascade",
            "transaction", "invoice", "accounting", "history", "readiness",
            "confirmation", "dismiss", "firebase", "firestore", "supabase",
            "powersync", "https://", "file://", "path", "credential", "bearer",
            "token", "secret", "raw-provider-detail", "production"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_801_020_000)
    private static let t1 = Date(timeIntervalSince1970: 1_801_020_001)

    private static func requireEquatableAndSendable<Value: Equatable & Sendable>(
        _: Value.Type
    ) {}

    private static func intent(
        accountID: String = "account-client-use-case",
        clientID: String = "client-residence",
        revision: UInt64 = 42
    ) throws -> ClientArchiveIntent {
        try ClientArchiveIntent(
            accountId: AccountID(validating: accountID),
            clientId: ClientID(validating: clientID),
            expectedRevision: ExpectedClientRevision(revision)
        )
    }

    private static func execute(
        using archiver: RecordingClientArchiver,
        operationID: String
    ) async throws -> OperationReceipt {
        try await ClientArchiveUseCase(archiver: archiver).execute(
            intent: intent(),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: "principal-client-use-case"),
            operationContractVersion: OperationContractVersion(
                validating: "client-archive-v1"
            ),
            capturedAt: t0
        )
    }

    private static func recordedCommand(
        accountID: String = "account-client-use-case",
        clientID: String = "client-residence",
        revision: UInt64 = 42,
        operationID: String = "operation-client-archive",
        actorID: String = "principal-client-use-case",
        contractVersion: String = "client-archive-v1",
        capturedAt: Date = t0
    ) async throws -> ArchiveClientCommand {
        let archiver = RecordingClientArchiver(response: .matching(.queued))
        _ = try await ClientArchiveUseCase(archiver: archiver).execute(
            intent: intent(
                accountID: accountID,
                clientID: clientID,
                revision: revision
            ),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: actorID),
            operationContractVersion: OperationContractVersion(
                validating: contractVersion
            ),
            capturedAt: capturedAt
        )
        let commands = await archiver.recordedCommands()
        #expect(commands.count == 1)
        return try #require(commands.first)
    }

    private static func expectCommand(
        _ command: ArchiveClientCommand,
        accountID: String = "account-client-use-case",
        clientID: String = "client-residence",
        revision: UInt64 = 42,
        operationID: String = "operation-client-archive",
        actorID: String = "principal-client-use-case",
        contractVersion: String = "client-archive-v1",
        capturedAt: Date = t0
    ) throws {
        #expect(command.draft.accountId == (try AccountID(validating: accountID)))
        #expect(command.draft.clientId == (try ClientID(validating: clientID)))
        #expect(command.draft.expectedRevision == ExpectedClientRevision(revision))
        #expect(command.draft.actorPrincipalId == (try PrincipalID(validating: actorID)))
        #expect(command.draft.operationContractVersion == (
            try OperationContractVersion(validating: contractVersion)
        ))
        #expect(command.draft.capturedAt == capturedAt)
        #expect(command.envelope.operationId == (try OperationID(validating: operationID)))
        #expect(command.envelope.accountId == command.draft.accountId)
        #expect(command.envelope.actorPrincipalId == command.draft.actorPrincipalId)
        #expect(command.envelope.contractVersion == command.draft.operationContractVersion)
        #expect(command.envelope.clientCreatedAt == command.draft.capturedAt)
        #expect(command.envelope.payload.clientId == command.draft.clientId)
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: revision)
        ])
        #expect(command.subject.kind == .client)
        #expect(command.subject.id.rawValue == clientID)
        #expect(command.fingerprint == (try OperationFingerprint.make(for: command.envelope)))
    }
}

private actor RecordingClientArchiver: ClientArchiving {
    enum Response: Sendable {
        case matching(LocalOperationState)
        case mismatched(OperationID)
        case archiveFailure(ClientArchiveFailure)
        case rawFailure
        case cancelled
    }

    private let response: Response
    private var commands: [ArchiveClientCommand] = []

    init(response: Response) {
        self.response = response
    }

    func archive(_ command: ArchiveClientCommand) async throws -> OperationReceipt {
        commands.append(command)
        switch response {
        case .matching(let localState):
            return OperationReceipt(
                operationId: command.envelope.operationId,
                localState: localState
            )
        case .mismatched(let operationId):
            return OperationReceipt(operationId: operationId, localState: .queued)
        case .archiveFailure(let failure):
            throw failure
        case .rawFailure:
            throw RawClientArchivePortFailure.transportPayload("raw-provider-detail")
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [ArchiveClientCommand] {
        commands
    }
}

private enum RawClientArchivePortFailure: Error {
    case transportPayload(String)
}
