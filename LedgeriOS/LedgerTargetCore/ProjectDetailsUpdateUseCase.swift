import Foundation

/// Transient presentation input for one Project-description replacement.
///
/// The raw description remains a presentation value until `execute` applies
/// the canonical `ProjectDescriptionReplacement` rules. This value is not
/// persisted and deliberately does not conform to `Codable`.
public struct ProjectDetailsUpdateFormInput: Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let expectedRevision: ExpectedProjectRevision
    public let rawDescription: String?

    public init(
        accountId: AccountID,
        projectId: ProjectID,
        expectedRevision: ExpectedProjectRevision,
        rawDescription: String?
    ) {
        self.accountId = accountId
        self.projectId = projectId
        self.expectedRevision = expectedRevision
        self.rawDescription = rawDescription
    }
}

/// Application-layer orchestration for one Project-description replacement.
public struct ProjectDetailsUpdateUseCase<Updater: ProjectDetailsUpdating>: Sendable {
    private let updater: Updater

    public init(updater: Updater) {
        self.updater = updater
    }

    public func execute(
        input: ProjectDetailsUpdateFormInput,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        let replacement = ProjectDescriptionReplacement(input.rawDescription)
        let draft = try ProjectDetailsUpdateDraft(
            accountId: input.accountId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            projectId: input.projectId,
            descriptionReplacement: replacement,
            expectedRevision: input.expectedRevision,
            capturedAt: capturedAt
        )
        let command = try UpdateProjectDetailsCommand(
            operationId: operationId,
            draft: draft
        )

        let receipt: OperationReceipt
        do {
            receipt = try await updater.updateDetails(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ProjectDetailsUpdateFailure {
            throw failure
        } catch {
            throw ProjectDetailsUpdateFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
