// READY CONTRACT — PROJECT RENAME USE CASE
//
// This leaf is intentionally comment-only until its exact READY commit passes
// the complete conversion gate. Implementation may replace only this comment.
//
// Frozen public API:
//
// public struct ProjectRenameIntent: Equatable, Sendable {
//     public let accountId: AccountID
//     public let projectId: ProjectID
//     public let expectedRevision: ExpectedProjectRevision
//     public let newDisplayName: ProjectDisplayName
//
//     public init(
//         accountId: AccountID,
//         projectId: ProjectID,
//         expectedRevision: ExpectedProjectRevision,
//         newDisplayName: ProjectDisplayName
//     )
// }
//
// public struct ProjectRenameUseCase<R: ProjectRenaming>: Sendable {
//     public init(renamer: R)
//
//     public func execute(
//         input: ProjectRenameIntent,
//         operationId: OperationID,
//         actorPrincipalId: PrincipalID,
//         operationContractVersion: OperationContractVersion,
//         capturedAt: Date
//     ) async throws -> OperationReceipt
// }
//
// ProjectRenameIntent is transient and must not conform to Codable. Its stored
// shape is exactly the four fields above. The caller supplies an already-
// validated ProjectDisplayName; this use case accepts no raw String and owns no
// trimming, blank-name, length or other display-name normalization policy.
//
// execute constructs ProjectRenameDraft and RenameProjectCommand before the
// port-error boundary, invokes ProjectRenaming.rename exactly once, validates
// the returned receipt outside that boundary, and returns the exact receipt
// and LocalOperationState.
//
// CancellationError and every one of the 12 ProjectRenameFailure values remain
// distinct. Only an unknown error thrown by the port becomes
// ProjectRenameFailure.localAcceptanceFailed. Construction failures make zero
// port calls; receipt mismatch follows exactly one call.
//
// This use case changes only one Project display name. It cannot read or decide
// readiness/lifecycle/no-op/UI state; change Client, description, category,
// allocation, budget, media, child, accounting or history state; persist or
// project a row; authorize a caller; define a service implementation; wire
// app/MCP behavior; transform source data; deploy, release or cut over.
