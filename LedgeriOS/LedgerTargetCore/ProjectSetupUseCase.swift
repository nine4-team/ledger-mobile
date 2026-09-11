import Foundation

/// The exact command accepted by the Project setup port and its validated receipt.
///
/// Returning both keeps command derivation in Core while allowing callers to retain
/// the immutable identity and fingerprint required to observe that operation.
public struct ProjectSetupExecutionResult: Equatable, Sendable {
    public let command: CreateProjectCommand
    public let receipt: OperationReceipt

    public init(command: CreateProjectCommand, receipt: OperationReceipt) {
        self.command = command
        self.receipt = receipt
    }
}

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
    ) async throws -> ProjectSetupExecutionResult {
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

        return ProjectSetupExecutionResult(
            command: command,
            receipt: try command.validate(receipt)
        )
    }
}
