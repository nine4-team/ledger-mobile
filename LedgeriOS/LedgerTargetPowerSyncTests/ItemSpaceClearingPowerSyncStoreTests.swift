// DRAFT scaffold only: executable tests replace this comment only after the
// Item-to-Space clearing local-durability dossier is promoted to READY and its exact commit passes
// independent review and immutable CI.
//
// Required proof covers Project and Business Inventory scope; single- and
// mixed-current-Space commands; a non-UUID opaque OperationID; canonical Item
// order; zero, Int64.max, Int64.max+1, and UInt64.max revision text; byte-exact
// canonical command/envelope replay for negative and fractional finite client
// times without decoded-Date equality; ordinary fractional provider-time
// truncation; exact high positive Date-round-trippable provider time; negative,
// nonfinite, beyond-Int64, and in-range-but-not-Date-round-trippable provider-time refusal; malformed stored acceptance-time
// refusal; replay while the fresh clock is invalid; pre-database Account/
// Principal rejection; atomic two-row persistence; exact replay; every required
// field's tamper/null/orphan/terminal/result refusal; concurrent same-ID
// convergence; complete/orphan/malformed collisions against every family in the
// separately verified centralized OperationID inventory, in both submission
// directions; exact beforeTransaction, inventoryConstruction, inventoryRead,
// afterOwnershipInspection, existingRead, commandWrite, operationWrite,
// beforeCommit, afterCommit, watchConstruction, watchRead, and watchIteration
// checkpoints; transaction/guard/read/write/watch fault rollback, bounded error
// mapping, and CancellationError passthrough at every pre-commit guard boundary;
// cancellation on both sides of commit; encrypted restart; dedicated watch
// cancellation/drainage; runtime close/post-close refusal; exactly-one pending-
// work count; and byte-unchanged ps_crud/upload selection.
//
// Clearing-specific proof must establish Project-or-Account generic subject,
// null generic expected revision, currentSpaceId on every canonical Item, valid
// mixed-current-Space input, and cross-command OperationID collision refusal
// against all existing registered command-family evidence. Static containment must prove the exact
// localOnly table/columns/nullability/implicit-ID/index and reject Item/Space/
// marker/media writes, command deletion/repair, remote apply, authorization,
// Postgres/RLS/Sync/RPC, UI, MCP, source-backend, migration, production, or cutover
// expansion. Diagnostics must remain finite and reveal no IDs, payloads, SQL,
// paths, credentials, or remote-success claims; CancellationError remains
// structured control flow.
