import Foundation

/// Transient archive intent supplied after presentation selects one Project.
///
/// The value is deliberately not `Codable`. The existing command has a
/// canonical encoding, but physical local durability and restart behavior
/// remain outside this use case.
public struct ProjectArchiveIntent: Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let expectedRevision: ExpectedProjectRevision

    public init(
        accountId: AccountID,
        projectId: ProjectID,
        expectedRevision: ExpectedProjectRevision
    ) {
        self.accountId = accountId
        self.projectId = projectId
        self.expectedRevision = expectedRevision
    }
}

/// Application-layer orchestration for one archive-only Project operation.
public struct ProjectArchiveUseCase<Archiver: ProjectArchiving>: Sendable {
    private let archiver: Archiver

    public init(archiver: Archiver) {
        self.archiver = archiver
    }

    public func execute(
        intent: ProjectArchiveIntent,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        let draft = try ProjectArchiveDraft(
            accountId: intent.accountId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            projectId: intent.projectId,
            expectedRevision: intent.expectedRevision,
            capturedAt: capturedAt
        )
        let command = try ArchiveProjectCommand(
            operationId: operationId,
            draft: draft
        )

        let receipt: OperationReceipt
        do {
            receipt = try await archiver.archive(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ProjectArchiveFailure {
            throw failure
        } catch {
            throw ProjectArchiveFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
