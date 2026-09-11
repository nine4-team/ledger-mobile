import Foundation

public enum ItemSpaceAssignmentUseCaseFailure: Error, Equatable, Sendable {
    case directoryAccountMismatch
    case directoryScopeMismatch
    case destinationNotRepresented

    public var diagnosticCode: String {
        switch self {
        case .directoryAccountMismatch:
            "item_space_assignment_directory_account_mismatch"
        case .directoryScopeMismatch:
            "item_space_assignment_directory_scope_mismatch"
        case .destinationNotRepresented:
            "item_space_assignment_destination_not_represented"
        }
    }
}

/// Transient presentation input for one exact Item-to-Space assignment.
///
/// Destination revision evidence is deliberately excluded. The use case derives
/// that precondition from the current validated destination-directory row.
public struct ItemSpaceAssignmentIntent: Equatable, Sendable {
    public let accountId: AccountID
    public let scope: ItemPlacementScope
    public let destinationSpaceId: SpaceID
    public let items: [ItemSpaceAssignmentCandidate]

    public init(
        accountId: AccountID,
        scope: ItemPlacementScope,
        destinationSpaceId: SpaceID,
        items: [ItemSpaceAssignmentCandidate]
    ) {
        self.accountId = accountId
        self.scope = scope
        self.destinationSpaceId = destinationSpaceId
        self.items = items
    }
}

/// Application-layer orchestration for one exact Item-to-Space assignment.
public struct ItemSpaceAssignmentUseCase<A: ItemSpaceAssigning>: Sendable {
    private let assigner: A

    public init(assigner: A) {
        self.assigner = assigner
    }

    public func execute(
        input: ItemSpaceAssignmentIntent,
        currentDestinations: SpaceAssignmentDestinationDirectorySnapshot,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        guard currentDestinations.request.accountId == input.accountId else {
            throw ItemSpaceAssignmentUseCaseFailure.directoryAccountMismatch
        }
        guard currentDestinations.request.scope == input.scope else {
            throw ItemSpaceAssignmentUseCaseFailure.directoryScopeMismatch
        }
        guard let destination = currentDestinations.local.rows.first(where: {
            $0.id == input.destinationSpaceId
        }) else {
            throw ItemSpaceAssignmentUseCaseFailure.destinationNotRepresented
        }

        let draft = try ItemSpaceAssignmentDraft(
            accountId: input.accountId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            destinationSpaceId: input.destinationSpaceId,
            scope: input.scope,
            expectedSpaceRevision: ExpectedSpaceRevision(destination.revision),
            items: input.items,
            capturedAt: capturedAt
        )
        let command = try AssignItemsToSpaceCommand(
            operationId: operationId,
            draft: draft
        )

        let receipt: OperationReceipt
        do {
            receipt = try await assigner.assignItemsToSpace(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ItemSpaceAssignmentFailure {
            throw failure
        } catch {
            throw ItemSpaceAssignmentFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
