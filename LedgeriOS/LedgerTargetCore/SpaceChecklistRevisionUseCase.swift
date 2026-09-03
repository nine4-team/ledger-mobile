import Foundation

/// Application-layer orchestration for one complete Space-checklist replacement.
public struct SpaceChecklistRevisionUseCase<Reviser: SpaceChecklistRevising>: Sendable {
    private let reviser: Reviser

    public init(reviser: Reviser) {
        self.reviser = reviser
    }

    public func execute(
        draft: SpaceChecklistEditingDraft,
        currentUpdate: SpaceCoreDetailsUpdate,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        let command = try draft.command(
            validating: currentUpdate,
            operationId: operationId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            capturedAt: capturedAt
        )

        let receipt: OperationReceipt
        do {
            receipt = try await reviser.reviseChecklists(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as SpaceChecklistEditingFailure {
            throw failure
        } catch let failure as SpaceChecklistRevisionFailure {
            throw failure
        } catch {
            throw SpaceChecklistRevisionFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
