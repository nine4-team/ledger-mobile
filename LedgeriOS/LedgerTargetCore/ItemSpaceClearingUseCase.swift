import Foundation

/// Transient presentation input for one exact Item placement clear.
public struct ItemSpaceClearingIntent: Equatable, Sendable {
    public let accountId: AccountID
    public let scope: ItemPlacementScope
    public let items: [ItemSpaceClearingCandidate]

    public init(
        accountId: AccountID,
        scope: ItemPlacementScope,
        items: [ItemSpaceClearingCandidate]
    ) {
        self.accountId = accountId
        self.scope = scope
        self.items = items
    }
}

/// Application-layer orchestration for one exact Item placement clear.
public struct ItemSpaceClearingUseCase<C: ItemSpaceAssignmentClearing>: Sendable {
    private let clearer: C

    public init(clearer: C) {
        self.clearer = clearer
    }

    public func execute(
        input: ItemSpaceClearingIntent,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        let draft = try ItemSpaceClearingDraft(
            accountId: input.accountId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            scope: input.scope,
            items: input.items,
            capturedAt: capturedAt
        )
        let command = try ClearItemSpaceAssignmentsCommand(
            operationId: operationId,
            draft: draft
        )

        let receipt: OperationReceipt
        do {
            receipt = try await clearer.clearItemSpaceAssignments(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ItemSpaceClearingFailure {
            throw failure
        } catch {
            throw ItemSpaceClearingFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
