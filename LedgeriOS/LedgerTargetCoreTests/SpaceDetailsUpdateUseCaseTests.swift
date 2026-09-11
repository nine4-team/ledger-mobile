import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Space Details Update Use Case Contracts")
struct SpaceDetailsUpdateUseCaseTests {
    @Test("Raw form text is transient and uses canonical Space validation")
    func rawTextAndCanonicalIntent() throws {
        let input = try Self.input(
            name: "  Design   Studio \n",
            notes: "\t East   wall  "
        )

        #expect(input.rawDisplayName == "  Design   Studio \n")
        #expect(input.rawNotes == "\t East   wall  ")
        let intent = try input.validatedIntent()
        #expect(intent.accountId == input.accountId)
        #expect(intent.spaceId == input.spaceId)
        #expect(intent.expectedRevision == input.expectedRevision)
        #expect(intent.displayName.rawValue == "Design   Studio")
        #expect(intent.notes.value == "East   wall")

        for blankName in ["", " ", "\n", " \n\t "] {
            let blank = input.replacingRawDisplayName(with: blankName)
            #expect(blank.rawDisplayName == blankName)
            #expect(Self.creationFailure { try blank.validatedIntent() } == .invalidDisplayName)
        }

        for absentNotes: String? in [nil, "", " ", "\n\t"] {
            let changed = input.replacingRawNotes(with: absentNotes)
            #expect(changed.rawNotes == absentNotes)
            #expect(try changed.validatedIntent().notes.value == nil)
        }

        let interior = input.replacingRawNotes(with: "  east \n west  ")
        #expect(try interior.validatedIntent().notes.value == "east \n west")

        let longName = String(repeating: "Long room name ", count: 511) + "Long room name"
        let longNotes = String(repeating: "Long notes value ", count: 511) + "Long notes value"
        let longInput = try Self.input(
            name: "  \(longName)  ",
            notes: "  \(longNotes)  "
        )
        #expect(longInput.rawDisplayName == "  \(longName)  ")
        #expect(longInput.rawNotes == "  \(longNotes)  ")
        #expect(try longInput.validatedIntent().displayName.rawValue == longName)
        #expect(try longInput.validatedIntent().notes.value == longNotes)
    }

    @Test("Immutable replacement preserves identity and duplicate names need no query")
    func immutableReplacementAndIdentity() throws {
        let input = try Self.input(revision: 0)
        let renamed = input.replacingRawDisplayName(with: "  Library  ")
        let renoted = input.replacingRawNotes(with: nil)

        #expect(renamed.accountId == input.accountId)
        #expect(renamed.spaceId == input.spaceId)
        #expect(renamed.expectedRevision == ExpectedSpaceRevision(0))
        #expect(renamed.rawDisplayName == "  Library  ")
        #expect(renamed.rawNotes == input.rawNotes)
        #expect(renoted.accountId == input.accountId)
        #expect(renoted.spaceId == input.spaceId)
        #expect(renoted.expectedRevision == input.expectedRevision)
        #expect(renoted.rawDisplayName == input.rawDisplayName)
        #expect(renoted.rawNotes == nil)

        let maximum = try Self.input(
            spaceID: "space-maximum-revision",
            revision: UInt64.max,
            name: " Studio "
        ).validatedIntent()
        let duplicate = try Self.input(
            spaceID: "space-duplicate-name",
            revision: 44,
            name: "Studio"
        ).validatedIntent()
        #expect(maximum.expectedRevision == ExpectedSpaceRevision(UInt64.max))
        #expect(maximum.spaceId != duplicate.spaceId)
        #expect(maximum.displayName == duplicate.displayName)

        let inputFields = Set(Mirror(reflecting: input).children.compactMap(\.label))
        #expect(inputFields == [
            "accountId", "spaceId", "expectedRevision", "rawDisplayName", "rawNotes"
        ])
        let intentFields = Set(Mirror(reflecting: maximum).children.compactMap(\.label))
        #expect(intentFields == [
            "accountId", "spaceId", "expectedRevision", "displayName", "notes"
        ])
    }

    @Test("One complete replacement preserves every matching receipt state")
    func exactCommandAndReceiptState() async throws {
        for localState in LocalOperationState.allCases {
            let operationID = try OperationID(
                validating: "operation-space-update-\(localState.rawValue)"
            )
            let updater = RecordingSpaceDetailsUpdater(
                response: .matching(localState: localState)
            )
            let receipt = try await SpaceDetailsUpdateUseCase(updater: updater).execute(
                input: try Self.input(
                    accountID: "account-exact",
                    spaceID: "space-exact",
                    revision: 73,
                    name: "  Receiving  ",
                    notes: "  North wall  "
                ),
                operationId: operationID,
                actorPrincipalId: PrincipalID(validating: "principal-exact"),
                operationContractVersion: OperationContractVersion(
                    validating: "space-details-v7"
                ),
                capturedAt: Self.t0
            )

            #expect(receipt.operationId == operationID)
            #expect(receipt.localState == localState)
            let commands = await updater.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            try Self.expectCommand(
                command,
                accountID: "account-exact",
                spaceID: "space-exact",
                revision: 73,
                name: "Receiving",
                notes: "North wall",
                operationID: operationID.rawValue,
                actorID: "principal-exact",
                contractVersion: "space-details-v7",
                capturedAt: Self.t0
            )
            #expect(try command.validate(receipt) == receipt)
        }
    }

    @Test("Every caller field forwards exactly and validation precedes dispatch")
    func exhaustiveForwardingAndValidationOrder() async throws {
        let baseline = try await Self.recordedCommand()
        let changedAccount = try await Self.recordedCommand(accountID: "account-other")
        let changedSpace = try await Self.recordedCommand(spaceID: "space-other")
        let changedRevision = try await Self.recordedCommand(revision: UInt64.max)
        let changedName = try await Self.recordedCommand(name: "  Library  ")
        let changedNotes = try await Self.recordedCommand(notes: nil)
        let changedOperation = try await Self.recordedCommand(operationID: "operation-other")
        let changedActor = try await Self.recordedCommand(actorID: "principal-other")
        let changedContract = try await Self.recordedCommand(contractVersion: "space-details-v2")
        let changedTime = try await Self.recordedCommand(capturedAt: Self.t1)

        try Self.expectCommand(
            baseline,
            accountID: "account-space-use-case",
            spaceID: "space-design-studio",
            revision: 42,
            name: "Design Studio",
            notes: "East wall",
            operationID: "operation-space-update",
            actorID: "principal-space-use-case",
            contractVersion: "space-details-v1",
            capturedAt: Self.t0
        )
        try Self.expectCommand(changedAccount, accountID: "account-other")
        try Self.expectCommand(changedSpace, spaceID: "space-other")
        try Self.expectCommand(changedRevision, revision: UInt64.max)
        try Self.expectCommand(changedName, name: "Library")
        try Self.expectCommand(changedNotes, notes: nil)
        try Self.expectCommand(changedOperation, operationID: "operation-other")
        try Self.expectCommand(changedActor, actorID: "principal-other")
        try Self.expectCommand(changedContract, contractVersion: "space-details-v2")
        try Self.expectCommand(changedTime, capturedAt: Self.t1)

        let blankUpdater = RecordingSpaceDetailsUpdater(response: .matching(localState: .queued))
        do {
            _ = try await SpaceDetailsUpdateUseCase(updater: blankUpdater).execute(
                input: try Self.input(name: " \n\t "),
                operationId: OperationID(validating: "operation-blank"),
                actorPrincipalId: PrincipalID(validating: "principal-test"),
                operationContractVersion: OperationContractVersion(
                    validating: "space-details-v1"
                ),
                capturedAt: Self.t0
            )
            Issue.record("Blank name returned a receipt")
        } catch let failure as SpaceCreationFailure {
            #expect(failure == .invalidDisplayName)
        }
        #expect(await blankUpdater.recordedCommands().isEmpty)

        let invalidTimeUpdater = RecordingSpaceDetailsUpdater(
            response: .matching(localState: .queued)
        )
        do {
            _ = try await SpaceDetailsUpdateUseCase(updater: invalidTimeUpdater).execute(
                input: try Self.input(),
                operationId: OperationID(validating: "operation-invalid-time"),
                actorPrincipalId: PrincipalID(validating: "principal-test"),
                operationContractVersion: OperationContractVersion(
                    validating: "space-details-v1"
                ),
                capturedAt: Date(timeIntervalSinceReferenceDate: .infinity)
            )
            Issue.record("Nonfinite time returned a receipt")
        } catch let failure as SpaceDetailsUpdateFailure {
            #expect(failure == .invalidCapturedAt)
        }
        #expect(await invalidTimeUpdater.recordedCommands().isEmpty)
    }

    @Test("Receipt, normalized, raw, and cancellation failures stay distinct")
    func failuresNeverReturnFalseReceipts() async throws {
        let mismatched = RecordingSpaceDetailsUpdater(
            response: .mismatched(
                operationId: try OperationID(validating: "operation-wrong")
            )
        )
        do {
            _ = try await Self.execute(using: mismatched, operationID: "operation-mismatch")
            Issue.record("Mismatched receipt returned")
        } catch let failure as SpaceDetailsUpdateFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatched.recordedCommands().count == 1)

        let creationFailure = RecordingSpaceDetailsUpdater(
            response: .creationFailure(.invalidEncodedNotes)
        )
        do {
            _ = try await Self.execute(using: creationFailure, operationID: "operation-value")
            Issue.record("Normalized Space value failure returned a receipt")
        } catch let failure as SpaceCreationFailure {
            #expect(failure == .invalidEncodedNotes)
        }
        #expect(await creationFailure.recordedCommands().count == 1)

        for failure in [
            SpaceDetailsUpdateFailure.revisionPreconditionMismatch,
            .localAcceptanceFailed
        ] {
            let updater = RecordingSpaceDetailsUpdater(response: .updateFailure(failure))
            do {
                _ = try await Self.execute(
                    using: updater,
                    operationID: "operation-\(failure.diagnosticCode)"
                )
                Issue.record("Normalized update failure returned a receipt")
            } catch let received as SpaceDetailsUpdateFailure {
                #expect(received == failure)
            }
            #expect(await updater.recordedCommands().count == 1)
        }

        let raw = RecordingSpaceDetailsUpdater(response: .rawFailure)
        do {
            _ = try await Self.execute(using: raw, operationID: "operation-raw")
            Issue.record("Raw failure returned a receipt")
        } catch let failure as SpaceDetailsUpdateFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(await raw.recordedCommands().count == 1)

        let cancelled = RecordingSpaceDetailsUpdater(response: .cancelled)
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

    @Test("Diagnostics are private and encoded shape stays within the boundary")
    func diagnosticsAndPermanentExclusions() async throws {
        let diagnostics: [(String, String)] = [
            (SpaceCreationFailure.invalidDisplayName.diagnosticCode,
             "space_creation_display_name_invalid"),
            (SpaceCreationFailure.invalidEncodedNotes.diagnosticCode,
             "space_creation_notes_encoding_invalid"),
            (SpaceDetailsUpdateFailure.revisionPreconditionMismatch.diagnosticCode,
             "space_details_update_revision_precondition_mismatch"),
            (SpaceDetailsUpdateFailure.receiptMismatch.diagnosticCode,
             "space_details_update_receipt_mismatch"),
            (SpaceDetailsUpdateFailure.localAcceptanceFailed.diagnosticCode,
             "space_details_update_local_acceptance_failed")
        ]
        for (diagnostic, expected) in diagnostics {
            #expect(diagnostic == expected)
            #expect(!diagnostic.contains("Design Studio"))
            #expect(!diagnostic.contains("East wall"))
            #expect(!diagnostic.contains("account-space-use-case"))
            #expect(!diagnostic.contains("space-design-studio"))
            #expect(!diagnostic.contains("operation-space-update"))
            #expect(!diagnostic.contains("principal-space-use-case"))
            #expect(!diagnostic.contains("space-details-v1"))
            #expect(!diagnostic.contains("raw-provider-detail"))
        }

        let command = try await Self.recordedCommand()
        let encoded = try OperationContractCodec.encode(command)
        let text = String(decoding: encoded, as: UTF8.self).lowercased()
        for required in [
            "account-space-use-case", "space-design-studio", "design studio",
            "east wall", "operation-space-update", "principal-space-use-case",
            "space-details-v1", "expectedrevision"
        ] {
            #expect(text.contains(required))
        }
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "template",
            "checklist", "attachment", "image", "itemid", "transaction",
            "occurrence", "invoice", "budget", "payer", "price", "scope",
            "archive", "review", "completion", "authorization", "readiness",
            "queryfingerprint", "cachedstatus", "originalname", "basename",
            "dirty", "unchanged", "https://", "file://", "bearer", "token",
            "secret", "production"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_991_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_991_001)

    private static func input(
        accountID: String = "account-space-use-case",
        spaceID: String = "space-design-studio",
        revision: UInt64 = 42,
        name: String = "Design Studio",
        notes: String? = "East wall"
    ) throws -> SpaceDetailsUpdateFormInput {
        try SpaceDetailsUpdateFormInput(
            accountId: AccountID(validating: accountID),
            spaceId: SpaceID(validating: spaceID),
            expectedRevision: ExpectedSpaceRevision(revision),
            rawDisplayName: name,
            rawNotes: notes
        )
    }

    private static func execute(
        using updater: RecordingSpaceDetailsUpdater,
        operationID: String
    ) async throws -> OperationReceipt {
        try await SpaceDetailsUpdateUseCase(updater: updater).execute(
            input: input(),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: "principal-space-use-case"),
            operationContractVersion: OperationContractVersion(
                validating: "space-details-v1"
            ),
            capturedAt: t0
        )
    }

    private static func recordedCommand(
        accountID: String = "account-space-use-case",
        spaceID: String = "space-design-studio",
        revision: UInt64 = 42,
        name: String = "Design Studio",
        notes: String? = "East wall",
        operationID: String = "operation-space-update",
        actorID: String = "principal-space-use-case",
        contractVersion: String = "space-details-v1",
        capturedAt: Date = t0
    ) async throws -> UpdateSpaceDetailsCommand {
        let updater = RecordingSpaceDetailsUpdater(response: .matching(localState: .queued))
        _ = try await SpaceDetailsUpdateUseCase(updater: updater).execute(
            input: input(
                accountID: accountID,
                spaceID: spaceID,
                revision: revision,
                name: name,
                notes: notes
            ),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: actorID),
            operationContractVersion: OperationContractVersion(
                validating: contractVersion
            ),
            capturedAt: capturedAt
        )
        let commands = await updater.recordedCommands()
        #expect(commands.count == 1)
        return try #require(commands.first)
    }

    private static func expectCommand(
        _ command: UpdateSpaceDetailsCommand,
        accountID: String = "account-space-use-case",
        spaceID: String = "space-design-studio",
        revision: UInt64 = 42,
        name: String = "Design Studio",
        notes: String? = "East wall",
        operationID: String = "operation-space-update",
        actorID: String = "principal-space-use-case",
        contractVersion: String = "space-details-v1",
        capturedAt: Date = t0
    ) throws {
        #expect(command.draft.accountId == (try AccountID(validating: accountID)))
        #expect(command.draft.spaceId == (try SpaceID(validating: spaceID)))
        #expect(command.draft.expectedRevision == ExpectedSpaceRevision(revision))
        #expect(command.draft.displayName.rawValue == name)
        #expect(command.draft.notes.value == notes)
        #expect(command.draft.actorPrincipalId == (try PrincipalID(validating: actorID)))
        #expect(
            command.draft.operationContractVersion ==
                (try OperationContractVersion(validating: contractVersion))
        )
        #expect(command.draft.capturedAt == capturedAt)
        #expect(command.envelope.operationId == (try OperationID(validating: operationID)))
        #expect(command.envelope.accountId == command.draft.accountId)
        #expect(command.envelope.actorPrincipalId == command.draft.actorPrincipalId)
        #expect(command.envelope.contractVersion == command.draft.operationContractVersion)
        #expect(command.envelope.clientCreatedAt == command.draft.capturedAt)
        #expect(command.envelope.payload.spaceId == command.draft.spaceId)
        #expect(command.envelope.payload.displayName == command.draft.displayName)
        #expect(command.envelope.payload.notes == command.draft.notes)
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: revision)
        ])
        #expect(command.subject.kind == .space)
        #expect(command.subject.id.rawValue == spaceID)
        #expect(command.fingerprint == (try OperationFingerprint.make(for: command.envelope)))
    }

    private static func creationFailure<T>(
        _ body: () throws -> T
    ) -> SpaceCreationFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as SpaceCreationFailure {
            return failure
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }
}

private actor RecordingSpaceDetailsUpdater: SpaceDetailsUpdating {
    enum Response: Sendable {
        case matching(localState: LocalOperationState)
        case mismatched(operationId: OperationID)
        case creationFailure(SpaceCreationFailure)
        case updateFailure(SpaceDetailsUpdateFailure)
        case rawFailure
        case cancelled
    }

    private let response: Response
    private var commands: [UpdateSpaceDetailsCommand] = []

    init(response: Response) {
        self.response = response
    }

    func updateDetails(
        _ command: UpdateSpaceDetailsCommand
    ) async throws -> OperationReceipt {
        commands.append(command)
        switch response {
        case .matching(let localState):
            return OperationReceipt(
                operationId: command.envelope.operationId,
                localState: localState
            )
        case .mismatched(let operationId):
            return OperationReceipt(operationId: operationId, localState: .queued)
        case .creationFailure(let failure):
            throw failure
        case .updateFailure(let failure):
            throw failure
        case .rawFailure:
            throw RawSpaceDetailsPortFailure.transportPayload("raw-provider-detail")
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [UpdateSpaceDetailsCommand] {
        commands
    }
}

private enum RawSpaceDetailsPortFailure: Error {
    case transportPayload(String)
}
