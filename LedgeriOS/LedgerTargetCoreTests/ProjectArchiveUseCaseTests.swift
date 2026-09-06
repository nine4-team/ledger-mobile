import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Archive Use Case Contracts")
struct ProjectArchiveUseCaseTests {
    @Test("Archive intent has exact transient identity and revision shape")
    func exactTransientIntent() throws {
        let zero = try Self.intent(revision: 0)
        let maximum = try Self.intent(projectID: "project-maximum", revision: UInt64.max)

        #expect(zero.expectedRevision == ExpectedProjectRevision(0))
        #expect(maximum.expectedRevision == ExpectedProjectRevision(UInt64.max))
        #expect(zero.projectId != maximum.projectId)
        #expect(!(ProjectArchiveIntent.self is any Codable.Type))
        #expect(Set(Mirror(reflecting: zero).children.compactMap(\.label)) == [
            "accountId", "projectId", "expectedRevision"
        ])
    }

    @Test("Every receipt state returns exactly after one archive dispatch")
    func exactReceiptStatesAndCommand() async throws {
        for localState in LocalOperationState.allCases {
            let operationID = try OperationID(
                validating: "operation-project-archive-\(localState.rawValue)"
            )
            let archiver = RecordingProjectArchiver(response: .matching(localState))
            let receipt = try await ProjectArchiveUseCase(archiver: archiver).execute(
                intent: try Self.intent(
                    accountID: "account-exact",
                    projectID: "project-exact",
                    revision: 73
                ),
                operationId: operationID,
                actorPrincipalId: PrincipalID(validating: "principal-exact"),
                operationContractVersion: OperationContractVersion(
                    validating: "project-archive-v7"
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
                projectID: "project-exact",
                revision: 73,
                operationID: operationID.rawValue,
                actorID: "principal-exact",
                contractVersion: "project-archive-v7",
                capturedAt: Self.t0
            )
            #expect(try command.validate(receipt) == receipt)
        }
    }

    @Test("Every caller field forwards into existing archive evidence")
    func reciprocalFieldForwarding() async throws {
        let baseline = try await Self.recordedCommand()
        let changedAccount = try await Self.recordedCommand(accountID: "account-other")
        let changedProject = try await Self.recordedCommand(projectID: "project-other")
        let changedRevision = try await Self.recordedCommand(revision: UInt64.max)
        let changedOperation = try await Self.recordedCommand(operationID: "operation-other")
        let changedActor = try await Self.recordedCommand(actorID: "principal-other")
        let changedContract = try await Self.recordedCommand(
            contractVersion: "project-archive-v2"
        )
        let changedTime = try await Self.recordedCommand(capturedAt: Self.t1)

        try Self.expectCommand(baseline)
        try Self.expectCommand(changedAccount, accountID: "account-other")
        try Self.expectCommand(changedProject, projectID: "project-other")
        try Self.expectCommand(changedRevision, revision: UInt64.max)
        try Self.expectCommand(changedOperation, operationID: "operation-other")
        try Self.expectCommand(changedActor, actorID: "principal-other")
        try Self.expectCommand(changedContract, contractVersion: "project-archive-v2")
        try Self.expectCommand(changedTime, capturedAt: Self.t1)
    }

    @Test("Construction failure precedes dispatch and receipts cannot mismatch")
    func validationPrecedesDispatch() async throws {
        let invalidTime = RecordingProjectArchiver(response: .matching(.queued))
        do {
            _ = try await ProjectArchiveUseCase(archiver: invalidTime).execute(
                intent: try Self.intent(),
                operationId: OperationID(validating: "operation-invalid-time"),
                actorPrincipalId: PrincipalID(validating: "principal-test"),
                operationContractVersion: OperationContractVersion(
                    validating: "project-archive-v1"
                ),
                capturedAt: Date(timeIntervalSinceReferenceDate: .infinity)
            )
            Issue.record("Nonfinite capture time returned a receipt")
        } catch let failure as ProjectArchiveFailure {
            #expect(failure == .invalidCapturedAt)
        }
        #expect(await invalidTime.recordedCommands().isEmpty)

        let mismatched = RecordingProjectArchiver(
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
        } catch let failure as ProjectArchiveFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatched.recordedCommands().count == 1)
    }

    @Test("Normalized, raw, and cancellation failures stay distinct")
    func boundedFailures() async throws {
        let normalized = RecordingProjectArchiver(response: .archiveFailure(.subjectMismatch))
        do {
            _ = try await Self.execute(using: normalized, operationID: "operation-normalized")
            Issue.record("Normalized failure returned a receipt")
        } catch let failure as ProjectArchiveFailure {
            #expect(failure == .subjectMismatch)
        }
        #expect(await normalized.recordedCommands().count == 1)

        let raw = RecordingProjectArchiver(response: .rawFailure)
        do {
            _ = try await Self.execute(using: raw, operationID: "operation-raw")
            Issue.record("Raw failure returned a receipt")
        } catch let failure as ProjectArchiveFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(await raw.recordedCommands().count == 1)

        let cancelled = RecordingProjectArchiver(response: .cancelled)
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
        let diagnostics: [(ProjectArchiveFailure, String)] = [
            (.invalidCapturedAt, "project_archive_captured_at_invalid"),
            (.draftAccountMismatch, "project_archive_account_mismatch"),
            (.draftActorMismatch, "project_archive_actor_mismatch"),
            (.draftContractMismatch, "project_archive_contract_mismatch"),
            (.draftPayloadMismatch, "project_archive_payload_mismatch"),
            (.revisionPreconditionMismatch, "project_archive_revision_precondition_mismatch"),
            (.subjectMismatch, "project_archive_subject_mismatch"),
            (.fingerprintMismatch, "project_archive_fingerprint_mismatch"),
            (.receiptMismatch, "project_archive_receipt_mismatch"),
            (.localAcceptanceFailed, "project_archive_local_acceptance_failed"),
            (.invalidEncodedDraft, "project_archive_draft_encoding_invalid"),
            (.invalidEncodedCommand, "project_archive_command_encoding_invalid")
        ]
        for (failure, expected) in diagnostics {
            let diagnostic = failure.diagnosticCode
            #expect(diagnostic == expected)
            for forbidden in [
                "account-project-use-case", "project-residence",
                "operation-project-archive", "principal-project-use-case",
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
            "projectId", "expectedRevision", "capturedAt"
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
        #expect(Set(payload.keys) == ["projectId"])
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
            "account-project-use-case", "project-residence",
            "operation-project-archive", "principal-project-use-case",
            "project-archive-v1", "expectedrevision"
        ] {
            #expect(text.contains(required))
        }
        for forbidden in [
            "restore", "unarchive", "delete", "lifecycle", "isarchived",
            "clientid", "clientname", "displayname", "description", "child",
            "space", "note", "itemid", "transaction", "invoice", "accounting",
            "budget", "category", "media", "attachment", "readiness", "cached",
            "confirmation", "dismiss", "firebase", "firestore", "supabase",
            "powersync", "https://", "file://", "path", "credential", "bearer",
            "token", "secret", "raw-provider-detail"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_801_010_000)
    private static let t1 = Date(timeIntervalSince1970: 1_801_010_001)

    private static func intent(
        accountID: String = "account-project-use-case",
        projectID: String = "project-residence",
        revision: UInt64 = 42
    ) throws -> ProjectArchiveIntent {
        try ProjectArchiveIntent(
            accountId: AccountID(validating: accountID),
            projectId: ProjectID(validating: projectID),
            expectedRevision: ExpectedProjectRevision(revision)
        )
    }

    private static func execute(
        using archiver: RecordingProjectArchiver,
        operationID: String
    ) async throws -> OperationReceipt {
        try await ProjectArchiveUseCase(archiver: archiver).execute(
            intent: intent(),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: "principal-project-use-case"),
            operationContractVersion: OperationContractVersion(
                validating: "project-archive-v1"
            ),
            capturedAt: t0
        )
    }

    private static func recordedCommand(
        accountID: String = "account-project-use-case",
        projectID: String = "project-residence",
        revision: UInt64 = 42,
        operationID: String = "operation-project-archive",
        actorID: String = "principal-project-use-case",
        contractVersion: String = "project-archive-v1",
        capturedAt: Date = t0
    ) async throws -> ArchiveProjectCommand {
        let archiver = RecordingProjectArchiver(response: .matching(.queued))
        _ = try await ProjectArchiveUseCase(archiver: archiver).execute(
            intent: intent(
                accountID: accountID,
                projectID: projectID,
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
        _ command: ArchiveProjectCommand,
        accountID: String = "account-project-use-case",
        projectID: String = "project-residence",
        revision: UInt64 = 42,
        operationID: String = "operation-project-archive",
        actorID: String = "principal-project-use-case",
        contractVersion: String = "project-archive-v1",
        capturedAt: Date = t0
    ) throws {
        #expect(command.draft.accountId == (try AccountID(validating: accountID)))
        #expect(command.draft.projectId == (try ProjectID(validating: projectID)))
        #expect(command.draft.expectedRevision == ExpectedProjectRevision(revision))
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
        #expect(command.envelope.payload.projectId == command.draft.projectId)
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: revision)
        ])
        #expect(command.subject.kind == .project)
        #expect(command.subject.id.rawValue == projectID)
        #expect(command.fingerprint == (try OperationFingerprint.make(for: command.envelope)))
    }
}

private actor RecordingProjectArchiver: ProjectArchiving {
    enum Response: Sendable {
        case matching(LocalOperationState)
        case mismatched(OperationID)
        case archiveFailure(ProjectArchiveFailure)
        case rawFailure
        case cancelled
    }

    private let response: Response
    private var commands: [ArchiveProjectCommand] = []

    init(response: Response) {
        self.response = response
    }

    func archive(_ command: ArchiveProjectCommand) async throws -> OperationReceipt {
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
            throw RawProjectArchivePortFailure.transportPayload("raw-provider-detail")
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [ArchiveProjectCommand] {
        commands
    }
}

private enum RawProjectArchivePortFailure: Error {
    case transportPayload(String)
}
