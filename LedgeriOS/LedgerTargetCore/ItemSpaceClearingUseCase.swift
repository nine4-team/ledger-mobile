// READY CONTRACT — ITEM SPACE CLEARING USE CASE
//
// This leaf is intentionally comment-only until its exact READY commit passes
// the complete conversion gate. Implementation may replace only this comment.
//
// Frozen public API:
//
// public struct ItemSpaceClearingIntent: Equatable, Sendable {
//     public let accountId: AccountID
//     public let scope: ItemPlacementScope
//     public let items: [ItemSpaceClearingCandidate]
//
//     public init(
//         accountId: AccountID,
//         scope: ItemPlacementScope,
//         items: [ItemSpaceClearingCandidate]
//     )
// }
//
// public struct ItemSpaceClearingUseCase<C: ItemSpaceAssignmentClearing>: Sendable {
//     public init(clearer: C)
//
//     public func execute(
//         input: ItemSpaceClearingIntent,
//         operationId: OperationID,
//         actorPrincipalId: PrincipalID,
//         operationContractVersion: OperationContractVersion,
//         capturedAt: Date
//     ) async throws -> OperationReceipt
// }
//
// ItemSpaceClearingIntent is transient and must not conform to Codable. Its
// stored shape is exactly the three fields above. The caller supplies one exact
// typed Account and Project-or-Business-Inventory scope plus typed Item
// identity/revision/current-Space candidates. The intent accepts no destination
// Space, nullable field, display name, route, backend path, attachment, marker,
// or accounting value.
//
// execute binds the exact Account and immutable placement scope to every typed
// Item/revision/current-Space candidate by constructing ItemSpaceClearingDraft
// and ClearItemSpaceAssignmentsCommand before the port-error boundary. Those
// verified contracts validate the internal consistency of the nonempty
// canonical selection, duplicate-free Item identity, finite time, operation
// metadata, scope subject, caller-supplied conflict preconditions, payload, and
// fingerprint. They do not establish actual scope or current-Space truth;
// trusted authoritative handling must revalidate both.
//
// execute invokes ItemSpaceAssignmentClearing.clearItemSpaceAssignments
// exactly once after construction, validates the returned receipt outside the
// port-error boundary, and returns the exact receipt and LocalOperationState.
// CancellationError and all 15 ItemSpaceClearingFailure values thrown by the
// port remain distinct. Only an unknown port error becomes
// ItemSpaceClearingFailure.localAcceptanceFailed. Construction failures make
// zero port calls; receipt mismatch follows exactly one call.
//
// This use case only dispatches an explicit nonempty clear whose candidates
// each carry caller-supplied current-Space conflict evidence. Nil/no-current-
// Space intent is structurally unrepresentable and no synthetic no-op receipt
// exists. Stale assigned-looking evidence may dispatch and later conflict.
// Mixed assigned/unassigned admission or filtering belongs to a future read/UI
// boundary. This use case cannot choose or read Items, decide UI eligibility,
// assign a destination, move Item scope, archive a Space, submit or delete
// attachment references or bytes, mutate photo/checkmark or review-note
// markers, change accounting or provenance, persist or project rows, authorize
// a caller, define a service, provider, schema, RLS, or Sync implementation,
// wire app/MCP behavior, transform source data, deploy, release, or cut over.
