import Foundation

/// Transient presentation input for one Client display-name replacement.
///
/// The display name is already validated by `ClientDisplayName`. This value is
/// not persisted and deliberately does not conform to `Codable`.
public struct ClientRenameIntent: Equatable, Sendable {
    public let accountId: AccountID
    public let clientId: ClientID
    public let expectedRevision: ExpectedClientRevision
    public let newDisplayName: ClientDisplayName

    public init(
        accountId: AccountID,
        clientId: ClientID,
        expectedRevision: ExpectedClientRevision,
        newDisplayName: ClientDisplayName
    ) {
        self.accountId = accountId
        self.clientId = clientId
        self.expectedRevision = expectedRevision
        self.newDisplayName = newDisplayName
    }
}

/// Application-layer orchestration for one Client display-name replacement.
public struct ClientRenameUseCase<R: ClientRenaming>: Sendable {
    private let renamer: R

    public init(renamer: R) {
        self.renamer = renamer
    }

    public func execute(
        input: ClientRenameIntent,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) async throws -> OperationReceipt {
        let draft = try ClientRenameDraft(
            accountId: input.accountId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            clientId: input.clientId,
            newDisplayName: input.newDisplayName,
            expectedRevision: input.expectedRevision,
            capturedAt: capturedAt
        )
        let command = try RenameClientCommand(
            operationId: operationId,
            draft: draft
        )

        let receipt: OperationReceipt
        do {
            receipt = try await renamer.rename(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ClientRenameFailure {
            throw failure
        } catch {
            throw ClientRenameFailure.localAcceptanceFailed
        }

        return try command.validate(receipt)
    }
}
