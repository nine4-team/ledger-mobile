// READY CONTRACT — ITEM SPACE ASSIGNMENT USE CASE
//
// This leaf is intentionally comment-only until its exact READY commit passes
// the complete conversion gate. Implementation may replace only this comment.
//
// Frozen public API:
//
// public enum ItemSpaceAssignmentUseCaseFailure: Error, Equatable, Sendable {
//     case directoryAccountMismatch
//     case directoryScopeMismatch
//     case destinationNotRepresented
//
//     public var diagnosticCode: String { get }
// }
//
// The three diagnostic codes are exactly:
// - item_space_assignment_directory_account_mismatch
// - item_space_assignment_directory_scope_mismatch
// - item_space_assignment_destination_not_represented
//
// public struct ItemSpaceAssignmentIntent: Equatable, Sendable {
//     public let accountId: AccountID
//     public let scope: ItemPlacementScope
//     public let destinationSpaceId: SpaceID
//     public let items: [ItemSpaceAssignmentCandidate]
//
//     public init(
//         accountId: AccountID,
//         scope: ItemPlacementScope,
//         destinationSpaceId: SpaceID,
//         items: [ItemSpaceAssignmentCandidate]
//     )
// }
//
// public struct ItemSpaceAssignmentUseCase<A: ItemSpaceAssigning>: Sendable {
//     public init(assigner: A)
//
//     public func execute(
//         input: ItemSpaceAssignmentIntent,
//         currentDestinations: SpaceAssignmentDestinationDirectorySnapshot,
//         operationId: OperationID,
//         actorPrincipalId: PrincipalID,
//         operationContractVersion: OperationContractVersion,
//         capturedAt: Date
//     ) async throws -> OperationReceipt
// }
//
// ItemSpaceAssignmentIntent is transient and must not conform to Codable. Its
// stored shape is exactly the four fields above. The caller supplies typed Item
// identity/revision candidates; the use case accepts no Item or Space name,
// route string, backend path, copied Space revision, attachment, marker, or
// accounting value.
//
// execute first requires the current validated directory request to match the
// intent Account and placement scope. It resolves the destination only by its
// stable SpaceID and derives ExpectedSpaceRevision from that exact active row.
// A represented row may dispatch from ready, partial, or stale local evidence.
// An absent row always returns destinationNotRepresented; that code describes
// only the supplied local evidence and never claims an incomplete directory
// proves authoritative nonexistence.
//
// execute constructs ItemSpaceAssignmentDraft and AssignItemsToSpaceCommand
// before the port-error boundary, invokes ItemSpaceAssigning.assignItemsToSpace
// exactly once, validates the returned receipt outside that boundary, and
// returns the exact receipt and LocalOperationState.
//
// The three ItemSpaceAssignmentUseCaseFailure values arise before the port and
// remain exact. CancellationError and all 16 ItemSpaceAssignmentFailure values
// thrown by the port remain distinct. Only an unknown port error becomes
// ItemSpaceAssignmentFailure.localAcceptanceFailed. Evidence or construction
// failures make zero port calls; receipt mismatch follows exactly one call.
//
// This use case assigns one exact nonempty Item selection to one represented
// destination. It cannot clear placement, select Items, read a destination
// directory, decide archive behavior, update photo markers, move Item scope,
// mutate accounting/provenance, persist or project rows, authorize a caller,
// define a service/provider/schema/RLS/Sync implementation, wire app/MCP
// behavior, transform source data, deploy, release, or cut over.
