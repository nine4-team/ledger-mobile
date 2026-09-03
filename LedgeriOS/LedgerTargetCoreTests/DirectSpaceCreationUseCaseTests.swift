import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Direct Space Creation Use Case Contracts")
struct DirectSpaceCreationUseCaseTests {
    @Test("Raw form state is caller supplied and canonicalized only on validation")
    func rawFormStateAndCanonicalIntent() throws {
        let input = try Self.input(
            name: "  Design   Studio \n",
            notes: "\t East   wall  "
        )

        #expect(input.rawDisplayName == "  Design   Studio \n")
        #expect(input.rawNotes == "\t East   wall  ")

        let renamed = input.replacingRawDisplayName(with: "\n  ")
        #expect(renamed.accountId == input.accountId)
        #expect(renamed.spaceId == input.spaceId)
        #expect(renamed.scope == input.scope)
        #expect(renamed.rawDisplayName == "\n  ")
        #expect(renamed.rawNotes == input.rawNotes)

        let renoted = input.replacingRawNotes(with: "  ")
        #expect(renoted.accountId == input.accountId)
        #expect(renoted.spaceId == input.spaceId)
        #expect(renoted.scope == input.scope)
        #expect(renoted.rawDisplayName == input.rawDisplayName)
        #expect(renoted.rawNotes == "  ")

        let intent = try input.validatedIntent()
        #expect(intent.accountId == input.accountId)
        #expect(intent.spaceId == input.spaceId)
        #expect(intent.scope == input.scope)
        #expect(intent.displayName.rawValue == "Design   Studio")
        #expect(intent.notes.value == "East   wall")
        #expect(try renoted.validatedIntent().notes.value == nil)
        #expect(Self.spaceFailure { try renamed.validatedIntent() } == .invalidDisplayName)

        let empty = input
            .replacingRawDisplayName(with: "")
            .replacingRawNotes(with: "")
        #expect(empty.rawDisplayName == "")
        #expect(empty.rawNotes == "")
        #expect(Self.spaceFailure { try empty.validatedIntent() } == .invalidDisplayName)

        let noNotes = input.replacingRawNotes(with: nil)
        #expect(noNotes.rawNotes == nil)
        #expect(try noNotes.validatedIntent().notes.value == nil)

        let emptyNotes = input.replacingRawNotes(with: "")
        #expect(emptyNotes.rawNotes == "")
        #expect(try emptyNotes.validatedIntent().notes.value == nil)

        let longName = String(repeating: "Long room name ", count: 511) + "Long room name"
        let longNotes = String(repeating: "Long notes value ", count: 511) + "Long notes value"
        let longInput = try Self.input(
            name: "  \(longName)  ",
            notes: "  \(longNotes)  "
        )
        #expect(longInput.rawDisplayName == "  \(longName)  ")
        #expect(longInput.rawNotes == "  \(longNotes)  ")
        let longIntent = try longInput.validatedIntent()
        #expect(longIntent.displayName.rawValue == longName)
        #expect(longIntent.notes.value == longNotes)
    }

    @Test("Project and Business Inventory identities allow duplicate display names")
    func exactScopesAndDuplicateNames() throws {
        let projectA = try Self.input(
            spaceID: "space-project-studio-a",
            scope: .project(ProjectID(validating: "project-residence")),
            name: "Studio"
        ).validatedIntent()
        let projectB = try Self.input(
            spaceID: "space-project-studio-b",
            scope: .project(ProjectID(validating: "project-residence")),
            name: " Studio "
        ).validatedIntent()
        let inventory = try Self.input(
            spaceID: "space-inventory-studio",
            scope: .businessInventory,
            name: "Receiving"
        ).validatedIntent()

        #expect(projectA.accountId == projectB.accountId)
        #expect(projectA.spaceId != projectB.spaceId)
        #expect(projectA.scope == projectB.scope)
        #expect(projectA.displayName == projectB.displayName)
        #expect(inventory.scope == .businessInventory)

        let intentFields = Set(Mirror(reflecting: projectA).children.compactMap(\.label))
        #expect(intentFields == ["accountId", "spaceId", "scope", "displayName", "notes"])
    }

    @Test("Both scopes dispatch one exact command and preserve every receipt state")
    func exactCommandAndReceiptState() async throws {
        let scopes: [(String, SpaceCreationScope)] = [
            ("space-project", try .project(ProjectID(validating: "project-home"))),
            ("space-inventory", .businessInventory)
        ]

        for (spaceID, scope) in scopes {
            for localState in LocalOperationState.allCases {
                let operationID = try OperationID(
                    validating: "operation-\(spaceID)-\(localState.rawValue)"
                )
                let creator = RecordingSpaceCreator(
                    response: .matching(localState: localState)
                )
                let receipt = try await DirectSpaceCreationUseCase(creator: creator).execute(
                    input: try Self.input(
                        accountID: "account-exact",
                        spaceID: spaceID,
                        scope: scope,
                        name: "  Receiving  ",
                        notes: "  North wall  "
                    ),
                    operationId: operationID,
                    actorPrincipalId: PrincipalID(validating: "principal-exact"),
                    operationContractVersion: OperationContractVersion(
                        validating: "space-create-v7"
                    ),
                    capturedAt: Self.t0
                )

                #expect(receipt.operationId == operationID)
                #expect(receipt.localState == localState)
                let commands = await creator.recordedCommands()
                #expect(commands.count == 1)
                let command = try #require(commands.first)
                #expect(command.envelope.operationId == operationID)
                #expect(command.envelope.accountId == (try AccountID(validating: "account-exact")))
                #expect(command.envelope.actorPrincipalId == (try PrincipalID(validating: "principal-exact")))
                #expect(command.envelope.contractVersion == (try OperationContractVersion(validating: "space-create-v7")))
                #expect(command.envelope.clientCreatedAt == Self.t0)
                #expect(command.envelope.preconditions.isEmpty)
                #expect(command.draft.spaceId == (try SpaceID(validating: spaceID)))
                #expect(command.draft.scope == scope)
                #expect(command.draft.displayName.rawValue == "Receiving")
                #expect(command.draft.notes.value == "North wall")
                #expect(command.envelope.payload.spaceId == command.draft.spaceId)
                #expect(command.envelope.payload.scope == command.draft.scope)
                #expect(command.envelope.payload.displayName == command.draft.displayName)
                #expect(command.envelope.payload.notes == command.draft.notes)
                #expect(try command.validate(receipt) == receipt)
            }
        }
    }

    @Test("Every caller-owned field reaches only its canonical command field")
    func exhaustiveCallerFieldForwarding() async throws {
        let baseline = try await Self.recordedCommand()
        let changedAccount = try await Self.recordedCommand(accountID: "account-other")
        let changedSpace = try await Self.recordedCommand(spaceID: "space-other")
        let changedScope = try await Self.recordedCommand(scope: .businessInventory)
        let changedName = try await Self.recordedCommand(name: "  Library  ")
        let changedNotes = try await Self.recordedCommand(notes: nil)
        let changedOperation = try await Self.recordedCommand(operationID: "operation-other")
        let changedActor = try await Self.recordedCommand(actorID: "principal-other")
        let changedContract = try await Self.recordedCommand(contractVersion: "space-create-v2")
        let changedTime = try await Self.recordedCommand(capturedAt: Self.t1)

        let projectScope = try SpaceCreationScope.project(
            ProjectID(validating: "project-residence")
        )
        try Self.expectCommand(
            baseline,
            accountID: "account-space-use-case",
            spaceID: "space-design-studio",
            scope: projectScope,
            name: "Design Studio",
            notes: "East wall",
            operationID: "operation-space-create",
            actorID: "principal-space-use-case",
            contractVersion: "space-create-v1",
            capturedAt: Self.t0
        )
        try Self.expectCommand(
            changedAccount,
            accountID: "account-other",
            spaceID: "space-design-studio",
            scope: projectScope,
            name: "Design Studio",
            notes: "East wall",
            operationID: "operation-space-create",
            actorID: "principal-space-use-case",
            contractVersion: "space-create-v1",
            capturedAt: Self.t0
        )
        try Self.expectCommand(
            changedSpace,
            accountID: "account-space-use-case",
            spaceID: "space-other",
            scope: projectScope,
            name: "Design Studio",
            notes: "East wall",
            operationID: "operation-space-create",
            actorID: "principal-space-use-case",
            contractVersion: "space-create-v1",
            capturedAt: Self.t0
        )
        try Self.expectCommand(
            changedScope,
            accountID: "account-space-use-case",
            spaceID: "space-design-studio",
            scope: .businessInventory,
            name: "Design Studio",
            notes: "East wall",
            operationID: "operation-space-create",
            actorID: "principal-space-use-case",
            contractVersion: "space-create-v1",
            capturedAt: Self.t0
        )
        try Self.expectCommand(
            changedName,
            accountID: "account-space-use-case",
            spaceID: "space-design-studio",
            scope: projectScope,
            name: "Library",
            notes: "East wall",
            operationID: "operation-space-create",
            actorID: "principal-space-use-case",
            contractVersion: "space-create-v1",
            capturedAt: Self.t0
        )
        try Self.expectCommand(
            changedNotes,
            accountID: "account-space-use-case",
            spaceID: "space-design-studio",
            scope: projectScope,
            name: "Design Studio",
            notes: nil,
            operationID: "operation-space-create",
            actorID: "principal-space-use-case",
            contractVersion: "space-create-v1",
            capturedAt: Self.t0
        )
        try Self.expectCommand(
            changedOperation,
            accountID: "account-space-use-case",
            spaceID: "space-design-studio",
            scope: projectScope,
            name: "Design Studio",
            notes: "East wall",
            operationID: "operation-other",
            actorID: "principal-space-use-case",
            contractVersion: "space-create-v1",
            capturedAt: Self.t0
        )
        try Self.expectCommand(
            changedActor,
            accountID: "account-space-use-case",
            spaceID: "space-design-studio",
            scope: projectScope,
            name: "Design Studio",
            notes: "East wall",
            operationID: "operation-space-create",
            actorID: "principal-other",
            contractVersion: "space-create-v1",
            capturedAt: Self.t0
        )
        try Self.expectCommand(
            changedContract,
            accountID: "account-space-use-case",
            spaceID: "space-design-studio",
            scope: projectScope,
            name: "Design Studio",
            notes: "East wall",
            operationID: "operation-space-create",
            actorID: "principal-space-use-case",
            contractVersion: "space-create-v2",
            capturedAt: Self.t0
        )
        try Self.expectCommand(
            changedTime,
            accountID: "account-space-use-case",
            spaceID: "space-design-studio",
            scope: projectScope,
            name: "Design Studio",
            notes: "East wall",
            operationID: "operation-space-create",
            actorID: "principal-space-use-case",
            contractVersion: "space-create-v1",
            capturedAt: Self.t1
        )
    }

    @Test("Validation, receipt, normalized failure, and raw failure all fail closed")
    func failuresNeverReturnFalseReceipts() async throws {
        let blankCreator = RecordingSpaceCreator(response: .matching(localState: .queued))
        do {
            _ = try await DirectSpaceCreationUseCase(creator: blankCreator).execute(
                input: try Self.input(name: " \n\t "),
                operationId: OperationID(validating: "operation-blank"),
                actorPrincipalId: PrincipalID(validating: "principal-test"),
                operationContractVersion: OperationContractVersion(validating: "space-create-v1"),
                capturedAt: Self.t0
            )
            Issue.record("Blank name returned a receipt")
        } catch let failure as SpaceCreationFailure {
            #expect(failure == .invalidDisplayName)
        }
        #expect(await blankCreator.recordedCommands().isEmpty)

        let invalidTimeCreator = RecordingSpaceCreator(response: .matching(localState: .queued))
        do {
            _ = try await DirectSpaceCreationUseCase(creator: invalidTimeCreator).execute(
                input: try Self.input(),
                operationId: OperationID(validating: "operation-invalid-time"),
                actorPrincipalId: PrincipalID(validating: "principal-test"),
                operationContractVersion: OperationContractVersion(validating: "space-create-v1"),
                capturedAt: Date(timeIntervalSinceReferenceDate: .infinity)
            )
            Issue.record("Nonfinite time returned a receipt")
        } catch let failure as SpaceCreationFailure {
            #expect(failure == .invalidCapturedAt)
        }
        #expect(await invalidTimeCreator.recordedCommands().isEmpty)

        let mismatchedCreator = RecordingSpaceCreator(
            response: .mismatched(operationId: try OperationID(validating: "operation-wrong"))
        )
        do {
            _ = try await Self.execute(using: mismatchedCreator, operationID: "operation-mismatch")
            Issue.record("Mismatched receipt returned")
        } catch let failure as SpaceCreationFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatchedCreator.recordedCommands().count == 1)

        let normalizedCreator = RecordingSpaceCreator(
            response: .normalizedFailure(.receiptMismatch)
        )
        do {
            _ = try await Self.execute(using: normalizedCreator, operationID: "operation-normalized")
            Issue.record("Normalized port failure returned a receipt")
        } catch let failure as SpaceCreationFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await normalizedCreator.recordedCommands().count == 1)

        let localAcceptanceCreator = RecordingSpaceCreator(
            response: .normalizedFailure(.localAcceptanceFailed)
        )
        do {
            _ = try await Self.execute(
                using: localAcceptanceCreator,
                operationID: "operation-local-acceptance"
            )
            Issue.record("Local-acceptance failure returned a receipt")
        } catch let failure as SpaceCreationFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(await localAcceptanceCreator.recordedCommands().count == 1)

        let rawCreator = RecordingSpaceCreator(response: .rawFailure)
        do {
            _ = try await Self.execute(using: rawCreator, operationID: "operation-raw")
            Issue.record("Raw port failure returned a receipt")
        } catch let failure as SpaceCreationFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(await rawCreator.recordedCommands().count == 1)

        let cancelledCreator = RecordingSpaceCreator(response: .cancelled)
        do {
            _ = try await Self.execute(
                using: cancelledCreator,
                operationID: "operation-cancelled"
            )
            Issue.record("Cancellation returned a receipt")
        } catch is CancellationError {
            // Expected: cancellation remains Swift structured-concurrency control flow.
        } catch {
            Issue.record("Cancellation was rewritten as: \(error)")
        }
        #expect(await cancelledCreator.recordedCommands().count == 1)

    }

    @Test("Diagnostics and command shape stay inside the provider-free boundary")
    func diagnosticsAndPermanentExclusions() async throws {
        let diagnostics: [(SpaceCreationFailure, String)] = [
            (.invalidDisplayName, "space_creation_display_name_invalid"),
            (.invalidCapturedAt, "space_creation_captured_at_invalid"),
            (.receiptMismatch, "space_creation_receipt_mismatch"),
            (.localAcceptanceFailed, "space_creation_local_acceptance_failed")
        ]
        for (failure, expected) in diagnostics {
            #expect(failure.diagnosticCode == expected)
            #expect(!failure.diagnosticCode.contains("Studio"))
            #expect(!failure.diagnosticCode.contains("account"))
            #expect(!failure.diagnosticCode.contains("principal"))
        }

        let command = try await Self.recordedCommand()
        let encoded = try OperationContractCodec.encode(command)
        let text = String(decoding: encoded, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "template",
            "checklist", "attachment", "image", "itemid", "transaction",
            "occurrence", "invoice", "budget", "payer", "price", "archive",
            "review", "completion", "authorization", "https://", "file://",
            "bearer", "token", "secret", "production"
        ] {
            #expect(!text.contains(forbidden))
        }

        let inputFields = Set(
            Mirror(reflecting: try Self.input()).children.compactMap(\.label)
        )
        #expect(inputFields == [
            "accountId", "spaceId", "scope", "rawDisplayName", "rawNotes"
        ])
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_990_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_990_001)

    private static func input(
        accountID: String = "account-space-use-case",
        spaceID: String = "space-design-studio",
        scope: SpaceCreationScope? = nil,
        name: String = "Design Studio",
        notes: String? = "East wall"
    ) throws -> SpaceCreationFormInput {
        try SpaceCreationFormInput(
            accountId: AccountID(validating: accountID),
            spaceId: SpaceID(validating: spaceID),
            scope: scope ?? .project(ProjectID(validating: "project-residence")),
            rawDisplayName: name,
            rawNotes: notes
        )
    }

    private static func execute(
        using creator: RecordingSpaceCreator,
        operationID: String
    ) async throws -> OperationReceipt {
        try await DirectSpaceCreationUseCase(creator: creator).execute(
            input: input(),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: "principal-space-use-case"),
            operationContractVersion: OperationContractVersion(
                validating: "space-create-v1"
            ),
            capturedAt: t0
        )
    }

    private static func recordedCommand(
        accountID: String = "account-space-use-case",
        spaceID: String = "space-design-studio",
        scope: SpaceCreationScope? = nil,
        name: String = "Design Studio",
        notes: String? = "East wall",
        operationID: String = "operation-space-create",
        actorID: String = "principal-space-use-case",
        contractVersion: String = "space-create-v1",
        capturedAt: Date = t0
    ) async throws -> CreateSpaceCommand {
        let creator = RecordingSpaceCreator(response: .matching(localState: .queued))
        _ = try await DirectSpaceCreationUseCase(creator: creator).execute(
            input: input(
                accountID: accountID,
                spaceID: spaceID,
                scope: scope,
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
        let commands = await creator.recordedCommands()
        #expect(commands.count == 1)
        return try #require(commands.first)
    }

    private static func expectCommand(
        _ command: CreateSpaceCommand,
        accountID: String,
        spaceID: String,
        scope: SpaceCreationScope,
        name: String,
        notes: String?,
        operationID: String,
        actorID: String,
        contractVersion: String,
        capturedAt: Date
    ) throws {
        #expect(command.draft.accountId == (try AccountID(validating: accountID)))
        #expect(command.draft.spaceId == (try SpaceID(validating: spaceID)))
        #expect(command.draft.scope == scope)
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
        #expect(command.envelope.payload.scope == command.draft.scope)
        #expect(command.envelope.payload.displayName == command.draft.displayName)
        #expect(command.envelope.payload.notes == command.draft.notes)
        #expect(command.envelope.preconditions.isEmpty)
        #expect(command.subject.kind == .space)
        #expect(command.subject.id.rawValue == spaceID)
        #expect(command.fingerprint == (try OperationFingerprint.make(for: command.envelope)))
    }

    private static func spaceFailure<T>(_ body: () throws -> T) -> SpaceCreationFailure? {
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

private actor RecordingSpaceCreator: SpaceCreating {
    enum Response: Sendable {
        case matching(localState: LocalOperationState)
        case mismatched(operationId: OperationID)
        case normalizedFailure(SpaceCreationFailure)
        case rawFailure
        case cancelled
    }

    private let response: Response
    private var commands: [CreateSpaceCommand] = []

    init(response: Response) {
        self.response = response
    }

    func create(_ command: CreateSpaceCommand) async throws -> OperationReceipt {
        commands.append(command)
        switch response {
        case .matching(let localState):
            return OperationReceipt(
                operationId: command.envelope.operationId,
                localState: localState
            )
        case .mismatched(let operationId):
            return OperationReceipt(operationId: operationId, localState: .queued)
        case .normalizedFailure(let failure):
            throw failure
        case .rawFailure:
            throw RawPortFailure.transportPayload("raw-provider-detail")
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [CreateSpaceCommand] {
        commands
    }
}

private enum RawPortFailure: Error {
    case transportPayload(String)
}
