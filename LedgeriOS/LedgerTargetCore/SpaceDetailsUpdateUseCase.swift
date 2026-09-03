import Foundation

/// Transient Space-details form input supplied by presentation.
///
/// This value deliberately does not conform to `Codable`: initial population,
/// dirty-state policy, and restart durability belong to later composition.
public struct SpaceDetailsUpdateFormInput: Equatable, Sendable {
    public let accountId: AccountID
    public let spaceId: SpaceID
    public let expectedRevision: ExpectedSpaceRevision
    public let rawDisplayName: String
    public let rawNotes: String?

    public init(
        accountId: AccountID,
        spaceId: SpaceID,
        expectedRevision: ExpectedSpaceRevision,
        rawDisplayName: String,
        rawNotes: String?
    ) {
        self.accountId = accountId
        self.spaceId = spaceId
        self.expectedRevision = expectedRevision
        self.rawDisplayName = rawDisplayName
        self.rawNotes = rawNotes
    }

    public func replacingRawDisplayName(with rawDisplayName: String) -> Self {
        Self(
            accountId: accountId,
            spaceId: spaceId,
            expectedRevision: expectedRevision,
            rawDisplayName: rawDisplayName,
            rawNotes: rawNotes
        )
    }

    public func replacingRawNotes(with rawNotes: String?) -> Self {
        Self(
            accountId: accountId,
            spaceId: spaceId,
            expectedRevision: expectedRevision,
            rawDisplayName: rawDisplayName,
            rawNotes: rawNotes
        )
    }

    /// Converts raw form text through the canonical Space value objects.
    ///
    /// The application use case calls this immediately before command assembly,
    /// so presentation validation cannot be used to bypass canonical rules.
    public func validatedIntent() throws -> SpaceDetailsUpdateIntent {
        SpaceDetailsUpdateIntent(
            accountId: accountId,
            spaceId: spaceId,
            expectedRevision: expectedRevision,
            displayName: try SpaceDisplayName(validating: rawDisplayName),
            notes: SpaceCreationNotes(rawNotes)
        )
    }
}

/// Canonical complete-replacement intent after presentation-field validation.
public struct SpaceDetailsUpdateIntent: Equatable, Sendable {
    public let accountId: AccountID
    public let spaceId: SpaceID
    public let expectedRevision: ExpectedSpaceRevision
    public let displayName: SpaceDisplayName
    public let notes: SpaceCreationNotes

    fileprivate init(
        accountId: AccountID,
        spaceId: SpaceID,
        expectedRevision: ExpectedSpaceRevision,
        displayName: SpaceDisplayName,
        notes: SpaceCreationNotes
    ) {
        self.accountId = accountId
        self.spaceId = spaceId
        self.expectedRevision = expectedRevision
        self.displayName = displayName
        self.notes = notes
    }
}

/// Application-layer orchestration for one complete Space-details replacement.
public struct SpaceDetailsUpdateUseCase<Updater: SpaceDetailsUpdating>: Sendable {
    private let updater: Updater

    public init(updater: Updater) {
        self.updater = updater
    }

    public func execute(
        input: SpaceDetailsUpdateFormInput,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        let intent = try input.validatedIntent()
        let draft = try SpaceDetailsUpdateDraft(
            accountId: intent.accountId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            spaceId: intent.spaceId,
            displayName: intent.displayName,
            notes: intent.notes,
            expectedRevision: intent.expectedRevision,
            capturedAt: capturedAt
        )
        let command = try UpdateSpaceDetailsCommand(
            operationId: operationId,
            draft: draft
        )

        let receipt: OperationReceipt
        do {
            receipt = try await updater.updateDetails(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as SpaceCreationFailure {
            throw failure
        } catch let failure as SpaceDetailsUpdateFailure {
            throw failure
        } catch {
            throw SpaceDetailsUpdateFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
