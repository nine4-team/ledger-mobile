import Foundation

/// Transient archive intent supplied after presentation selects one Client.
///
/// The value is deliberately not `Codable`. The existing command has a
/// canonical encoding, but physical local durability and restart behavior
/// remain outside this use case.
public struct ClientArchiveIntent: Equatable, Sendable {
    public let accountId: AccountID
    public let clientId: ClientID
    public let expectedRevision: ExpectedClientRevision

    public init(
        accountId: AccountID,
        clientId: ClientID,
        expectedRevision: ExpectedClientRevision
    ) {
        self.accountId = accountId
        self.clientId = clientId
        self.expectedRevision = expectedRevision
    }
}

/// Application-layer orchestration for one archive-only Client operation.
public struct ClientArchiveUseCase<Archiver: ClientArchiving>: Sendable {
    private let archiver: Archiver

    public init(archiver: Archiver) {
        self.archiver = archiver
    }

    public func execute(
        intent: ClientArchiveIntent,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        let draft = try ClientArchiveDraft(
            accountId: intent.accountId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            clientId: intent.clientId,
            expectedRevision: intent.expectedRevision,
            capturedAt: capturedAt
        )
        let command = try ArchiveClientCommand(
            operationId: operationId,
            draft: draft
        )

        let receipt: OperationReceipt
        do {
            receipt = try await archiver.archive(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ClientArchiveFailure {
            throw failure
        } catch {
            throw ClientArchiveFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
