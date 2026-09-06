// READY scaffold only: no executable Item-to-Space assignment store exists here.
//
// The bounded implementation may conform to the verified ItemSpaceAssigning port
// only for Account-bound encrypted local acceptance. It must validate the exact
// command Account/Principal scope and exact operation identity before database access, then
// atomically persist one canonical AssignItemsToSpaceCommand evidence row and
// one shared queued local-operation row. The command-specific table is localOnly:
// this slice must not create ps_crud upload work or invent an authoritative
// transport contract.
//
// Exact replay may return the one existing receipt only after validating every
// stored command and operation field. Changed, rebound, duplicate, malformed,
// cross-scope, partially written, or terminal evidence must fail closed without
// mutation. Revisions are lossless decimal text across the complete UInt64 range.
// Preserve every finite client Date already accepted by the frozen command,
// including negative and fractional milliseconds, in canonical command/envelope
// JSON; no redundant integer client time may narrow it. Provider acceptance time
// truncates toward zero and must be finite, nonnegative, and Int64-safe before DB.
// The localOnly
// `spike_item_space_assignment_commands` table has implicit text `id`; required
// text `account_id`, `actor_principal_id`, `contract_version`,
// `destination_space_id`, `scope_kind`, `expected_space_revision`, `items_json`,
// `fingerprint`, `command_json`; nullable text `project_id`; required integer
// `accepted_at_ms`; and index
// `item_space_assignment_command_account` on `account_id`. Scope encoding is
// exact `project` plus required project_id or `business_inventory` plus null.
// items_json is sorted-key canonical version `item_space_assignment_items_v1`
// with stable [{itemId,expectedRevision}] command order and decimal revisions.
// The generic row uses destination Space subject, queued state, identical
// accepted/updated times, `assign_items_to_space`, Space revision text, canonical
// envelope JSON, null terminal fields, and no operation-result row.
// Cancellation before commit stores nothing; cancellation after the atomic commit
// cannot erase accepted work. Non-destructive close/reopen retains both rows;
// this slice exposes no deletion or repair API. Close must cancel and join every dedicated operation
// watch before either encrypted database closes, and post-close admission fails.
// Public provider failures are invalidAcceptanceTime, malformedLocalEvidence,
// and operationNotFound. Scope and payload failures reuse existing contract/runtime
// errors; encoding uses invalidEncodedCommand and cancellation remains control flow.
// The Account-scoped watch filters ID plus constructor Account/Principal and emits
// queued-only evidence; absent rows are not found and terminal/result evidence is
// malformed. It does not infer Account ownership from an opaque OperationID.
//
// This prerequisite must not mutate or project Item or Space rows, resolve Item
// eligibility, authorize or apply on a server, add Postgres/RLS/Sync/RPC/upload,
// alter generic upload ordering, change ps_crud, or add app/MCP behavior.
