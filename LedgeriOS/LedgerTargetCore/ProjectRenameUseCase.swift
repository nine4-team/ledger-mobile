import Foundation

/// Transient presentation input for one Project display-name replacement.
///
/// The display name is already validated by `ProjectDisplayName`. This value is
/// not persisted and deliberately does not conform to `Codable`.
public struct ProjectRenameIntent: Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let expectedRevision: ExpectedProjectRevision
    public let newDisplayName: ProjectDisplayName

    public init(
        accountId: AccountID,
        projectId: ProjectID,
        expectedRevision: ExpectedProjectRevision,
        newDisplayName: ProjectDisplayName
    ) {
        self.accountId = accountId
        self.projectId = projectId
        self.expectedRevision = expectedRevision
        self.newDisplayName = newDisplayName
    }
}

/// Application-layer orchestration for one Project display-name replacement.
public struct ProjectRenameUseCase<R: ProjectRenaming>: Sendable {
    private let renamer: R

    public init(renamer: R) {
        self.renamer = renamer
    }

    public func execute(
        input: ProjectRenameIntent,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        let draft = try ProjectRenameDraft(
            accountId: input.accountId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            projectId: input.projectId,
            newDisplayName: input.newDisplayName,
            expectedRevision: input.expectedRevision,
            capturedAt: capturedAt
        )
        let command = try RenameProjectCommand(
            operationId: operationId,
            draft: draft
        )

        let receipt: OperationReceipt
        do {
            receipt = try await renamer.rename(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ProjectRenameFailure {
            throw failure
        } catch {
            throw ProjectRenameFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
