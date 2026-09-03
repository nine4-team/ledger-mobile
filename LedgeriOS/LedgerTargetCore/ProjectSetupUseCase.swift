import Foundation

/// Application-layer orchestration for one complete Project setup.
public struct ProjectSetupUseCase<Setup: ProjectSetupOperating>: Sendable {
    private let setup: Setup

    public init(setup: Setup) {
        self.setup = setup
    }

    public func execute(
        selection: ProjectSetupFormSelection,
        currentPreparation: ProjectSetupFormPreparation,
        projectId: ProjectID,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        let command = try selection.command(
            validating: currentPreparation,
            projectId: projectId,
            operationId: operationId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            capturedAt: capturedAt
        )

        let receipt: OperationReceipt
        do {
            receipt = try await setup.create(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ProjectSetupFormFailure {
            throw failure
        } catch let failure as ProjectSetupFailure {
            throw failure
        } catch {
            throw ProjectSetupFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
