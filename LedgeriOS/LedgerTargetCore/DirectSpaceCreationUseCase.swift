import Foundation

/// Transient direct-Space form input supplied by presentation.
///
/// This value deliberately does not conform to `Codable`: retaining the form
/// across process restarts requires a separate, explicitly durable contract.
public struct SpaceCreationFormInput: Equatable, Sendable {
    public let accountId: AccountID
    public let spaceId: SpaceID
    public let scope: SpaceCreationScope
    public let rawDisplayName: String
    public let rawNotes: String?

    public init(
        accountId: AccountID,
        spaceId: SpaceID,
        scope: SpaceCreationScope,
        rawDisplayName: String,
        rawNotes: String?
    ) {
        self.accountId = accountId
        self.spaceId = spaceId
        self.scope = scope
        self.rawDisplayName = rawDisplayName
        self.rawNotes = rawNotes
    }

    public func replacingRawDisplayName(with rawDisplayName: String) -> Self {
        Self(
            accountId: accountId,
            spaceId: spaceId,
            scope: scope,
            rawDisplayName: rawDisplayName,
            rawNotes: rawNotes
        )
    }

    public func replacingRawNotes(with rawNotes: String?) -> Self {
        Self(
            accountId: accountId,
            spaceId: spaceId,
            scope: scope,
            rawDisplayName: rawDisplayName,
            rawNotes: rawNotes
        )
    }

    /// Converts raw form text through the canonical Space value objects.
    ///
    /// Presentation may call this for immediate validation. The application
    /// use case calls the same method again before invoking its operation port,
    /// so a caller cannot bypass validation by skipping presentation checks.
    public func validatedIntent() throws -> DirectSpaceCreationIntent {
        DirectSpaceCreationIntent(
            accountId: accountId,
            spaceId: spaceId,
            scope: scope,
            displayName: try SpaceDisplayName(validating: rawDisplayName),
            notes: SpaceCreationNotes(rawNotes)
        )
    }
}

/// Canonical direct-Space intent after presentation-field validation.
public struct DirectSpaceCreationIntent: Equatable, Sendable {
    public let accountId: AccountID
    public let spaceId: SpaceID
    public let scope: SpaceCreationScope
    public let displayName: SpaceDisplayName
    public let notes: SpaceCreationNotes

    fileprivate init(
        accountId: AccountID,
        spaceId: SpaceID,
        scope: SpaceCreationScope,
        displayName: SpaceDisplayName,
        notes: SpaceCreationNotes
    ) {
        self.accountId = accountId
        self.spaceId = spaceId
        self.scope = scope
        self.displayName = displayName
        self.notes = notes
    }
}

/// Application-layer orchestration for one direct Space creation intent.
public struct DirectSpaceCreationUseCase<Creator: SpaceCreating>: Sendable {
    private let creator: Creator

    public init(creator: Creator) {
        self.creator = creator
    }

    public func execute(
        input: SpaceCreationFormInput,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        let intent = try input.validatedIntent()
        let draft = try SpaceCreationDraft(
            accountId: intent.accountId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            spaceId: intent.spaceId,
            scope: intent.scope,
            displayName: intent.displayName,
            notes: intent.notes,
            capturedAt: capturedAt
        )
        let command = try CreateSpaceCommand(operationId: operationId, draft: draft)

        let receipt: OperationReceipt
        do {
            receipt = try await creator.create(command)
        } catch is CancellationError {
            // Structured-concurrency cancellation is control flow, not a
            // transport failure to normalize into the application taxonomy.
            throw CancellationError()
        } catch let failure as SpaceCreationFailure {
            throw failure
        } catch {
            throw SpaceCreationFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
