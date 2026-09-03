// READY CONTRACT — CLIENT RENAME USE CASE
//
// This leaf is intentionally comment-only until its exact READY commit passes
// the complete conversion gate. Implementation may replace only this comment.
//
// Frozen public API:
//
// public struct ClientRenameIntent: Equatable, Sendable {
//     public let accountId: AccountID
//     public let clientId: ClientID
//     public let expectedRevision: ExpectedClientRevision
//     public let newDisplayName: ClientDisplayName
//
//     public init(
//         accountId: AccountID,
//         clientId: ClientID,
//         expectedRevision: ExpectedClientRevision,
//         newDisplayName: ClientDisplayName
//     )
// }
//
// public struct ClientRenameUseCase<R: ClientRenaming>: Sendable {
//     public init(renamer: R)
//
//     public func execute(
//         input: ClientRenameIntent,
//         operationId: OperationID,
//         actorPrincipalId: PrincipalID,
//         operationContractVersion: OperationContractVersion,
//         capturedAt: Date
//     ) async throws -> OperationReceipt
// }
//
// ClientRenameIntent is transient and must not conform to Codable. Its stored
// shape is exactly the four fields above. The caller supplies an already-
// validated ClientDisplayName; this use case accepts no raw String and owns no
// trimming, blank-name, length or other display-name normalization policy.
//
// execute constructs ClientRenameDraft and RenameClientCommand before the
// port-error boundary, invokes ClientRenaming.rename exactly once, validates
// the returned receipt outside that boundary, and returns the exact receipt
// and LocalOperationState.
//
// CancellationError and every one of the 12 ClientRenameFailure values remain
// distinct. Only an unknown error thrown by the port becomes
// ClientRenameFailure.localAcceptanceFailed. Construction failures make zero
// port calls; receipt mismatch follows exactly one call.
//
// This use case changes only one Client display name. It cannot read or decide
// readiness/lifecycle/no-op/UI state; change Client identity, archive/delete/
// merge state, Project ownership or reassignment, or frozen accounting/history
// display evidence; persist or project a row; authorize a caller; define a
// service implementation; wire app/MCP behavior; transform source data;
// deploy, release or cut over.
