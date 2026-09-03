// READY CONTRACT — PROJECT DETAILS UPDATE USE CASE
//
// This leaf is intentionally comment-only until its exact READY commit passes
// the complete conversion gate. Implementation may replace only this comment.
//
// Frozen public API:
//
// public struct ProjectDetailsUpdateFormInput: Equatable, Sendable {
//     public let accountId: AccountID
//     public let projectId: ProjectID
//     public let expectedRevision: ExpectedProjectRevision
//     public let rawDescription: String?
//
//     public init(
//         accountId: AccountID,
//         projectId: ProjectID,
//         expectedRevision: ExpectedProjectRevision,
//         rawDescription: String?
//     )
// }
//
// public struct ProjectDetailsUpdateUseCase<Updater: ProjectDetailsUpdating>:
//     Sendable {
//     public init(updater: Updater)
//
//     public func execute(
//         input: ProjectDetailsUpdateFormInput,
//         operationId: OperationID,
//         actorPrincipalId: PrincipalID,
//         operationContractVersion: OperationContractVersion,
//         capturedAt: Date
//     ) async throws -> OperationReceipt
// }
//
// ProjectDetailsUpdateFormInput is transient and must not conform to Codable.
// Its stored shape is exactly the four fields above. It owns no initial value,
// read snapshot, readiness, lifecycle, dirty/no-op, dismissal or error UI state.
//
// execute constructs ProjectDescriptionReplacement from rawDescription, then
// ProjectDetailsUpdateDraft and UpdateProjectDetailsCommand, before entering
// the port-error boundary. It invokes ProjectDetailsUpdating.updateDetails
// exactly once, validates the returned receipt outside that boundary, and
// returns the exact receipt and LocalOperationState.
//
// CancellationError and every ProjectDetailsUpdateFailure remain distinct.
// Only an unknown error thrown by the port becomes
// ProjectDetailsUpdateFailure.localAcceptanceFailed. Construction failures
// make zero port calls; receipt mismatch follows exactly one call.
//
// This use case changes only the canonical optional Project description. It
// cannot rename or reassign a Project; change Client, category, allocation,
// budget, media, lifecycle, child, accounting or history state; decide form
// admission or no-op behavior; persist or project a row; authorize a caller;
// define a service implementation; wire app/MCP behavior; transform source
// data; deploy, release or cut over.
