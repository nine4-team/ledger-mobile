// DRAFT scaffold only: no executable Item-to-Space clearing store exists here.
//
// The bounded implementation may conform to the verified
// ItemSpaceAssignmentClearing port only for Account-bound encrypted local
// acceptance. It must validate the exact command Account/Principal scope before
// database access, treat OperationID as opaque with no provider-specific format,
// then atomically persist one
// canonical ClearItemSpaceAssignmentsCommand evidence row and one shared queued
// local-operation row. The command-specific table is localOnly: this slice must
// create no ps_crud work and define no authoritative transport contract.
//
// Clearing is intentionally asymmetric with assignment. There is no destination
// Space or expected destination-Space revision. The generic operation subject is
// the Project for Project scope or the Account for Business Inventory scope, and
// command_expected_revision is null. Each canonical Item entry preserves
// itemId, lossless decimal-text expectedRevision, and currentSpaceId; one command
// may contain Items from different current Spaces.
//
// Exact replay may return the existing queued receipt only after validating
// every command and operation field. Changed, rebound, duplicate, malformed,
// cross-scope, partially written, orphaned, terminal, result-bearing, or
// cross-command evidence must fail closed without repair or mutation. This
// provider depends on the separately verified shared local OperationID guard.
// It must register `clear_item_space_assignments` and its local command relation
// once in that centralized inventory, so evidence owned by any existing or
// future registered family can never be rebound. It must not add a pairwise
// store lookup or otherwise change existing provider semantics.
//
// The localOnly `spike_item_space_clearing_commands` table has implicit text
// `id`; required text `account_id`, `actor_principal_id`, `contract_version`,
// `scope_kind`, `items_json`, `fingerprint`, `command_json`; nullable text
// `project_id`; required integer `accepted_at_ms`; and index
// `item_space_clearing_command_account` on `account_id`. Scope is exactly
// `project` with required matching project_id or `business_inventory` with null.
// items_json is sorted-key canonical version `item_space_clearing_items_v1` in
// stable command order with [{itemId,expectedRevision,currentSpaceId}].
//
// Preserve byte-identical canonical command/envelope JSON for every finite
// client Date already accepted by the frozen command; no integer derivative or
// decoded-Date equality may narrow or redefine canonical codec evidence.
// Provider acceptance time is consulted only for new admission, truncates toward
// zero, and must be finite, nonnegative, Int64-safe, and exactly round-trippable
// through the public Date snapshot. Exact replay never consults a fresh clock.
// Cancellation before commit stores nothing; cancellation after atomic commit
// cannot erase accepted work. Non-destructive close/reopen retains both rows.
//
// The Account-scoped watch filters opaque OperationID plus constructor Account/
// Principal and emits queued-only evidence. Close cancels and joins every
// clearing watch and admitted finite operation before either encrypted database
// closes; post-close admission refuses before database access. Pending-work
// counts the shared queued operation exactly once. This slice exposes no command
// deletion, repair, terminal transition, or upload API.
//
// This prerequisite must not mutate or optimistically project Item, Space, or
// marker rows; delete attachment references or bytes; alter accounting; resolve
// actual placement, membership, or authorization; add Postgres/RLS/Sync/RPC or
// upload behavior; or add app/MCP/hosted/source-backend/migration/production/cutover
// behavior. O-023/O-027/O-037 and A-003/A-004/A-007/A-015/A-016 remain open.
