# EVID-M2-PROJECT-REFERENCE-001 — Client, Project, and Reference-Data Target Mapping

- Timestamp: 2026-09-03 correction
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  from the history now carried by `firebase`; the historical audit began from a
  dirty source checkout
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Mapping batch: `M0-PROJECT-CLIENT-REFERENCE-001`
- Method: `target-mapping-method.md`

## Scope and Result

The batch contains 52 `replace`, `redesign`, or `migrate` surfaces. Twenty-nine
now have complete target maps. Twenty-three remain deliberately `characterized`
because O-024, O-025, O-026 or O-040 can still change the exact deletion/
correction command, dependency/retention behavior, writer ownership,
authorization or Project budget-pin product contract.

The completed map covers stable Client/Project identity and local directories,
Project setup and stable selection projections, Project notes, provider-free
preference-shaped primitives, category/vendor/template read models, Project
category/allocation views, bounded application ports, capability-driven settings/pickers, MCP
Project/note/reference queries and semantic target tests.

## Mapping Decisions

- A Project owns one stable `ClientID`; copied/free-text Client names are
  migration evidence and display snapshots, never relationship or authorization
  keys. Ambiguous source-name clusters quarantine instead of silently merging.
- Project setup uses one durable idempotent operation for the stable
  Client/Project relation and exact selected-category set. It preserves absent,
  enabled-without-allocation and explicit-zero states. Hero media has its own
  durable attachment receipt and visible outcome.
- Client/Project lists and details are local versioned snapshots with explicit
  scope/history readiness and financial visibility. Cached Firebase
  `budgetSummary` and Transaction-only recomputation are not target authority.
- Project notes have stable IDs, immutable creator/creation evidence, revision/
  tombstone state and deterministic `(createdAt,id)` paging/search. App and MCP
  use one operation/query contract.
- Verified Project-preference leaves prove provider-free row/operation shapes
  only. O-040 decides whether pins survive, typed targets, missing/empty/no-pin
  defaults, Project-detail/card fallbacks and lifecycle/cleanup; no target
  download/write/app behavior is mapped yet.
- Categories, vendor suggestions and Space templates use stable revisioned
  entries and local reference snapshots. Suggestion selection preserves
  free-text source data; it does not create Vendor identity. Template application
  resets checklist state.
- Settings and pickers consume capability/readiness snapshots and route logout
  through `AccountSessionEnding`; they do not own Firebase listeners, debug
  access or raw settings writes.

Architecture contracts now name Client/Project directory, notes, reference
queries and typed Client/Project/note/preference operations. `ChangeProjectClient`
and physical Project deletion are intentionally absent pending O-025/O-024.

## Withheld Surfaces

Six surfaces that expose generic Project delete or Client reassignment/update
remain withheld on O-024/O-025. Ten category/vendor/template/configuration
writer surfaces remain withheld on O-026 because the approved capability matrix
can change their public operation and security boundary. Their batch entries
name only those decision IDs; no source generic CRUD behavior is provisional.
Seven preference, Project creation/list/card/test and MCP surfaces are newly
withheld on O-040; five already-held Project/context/service/calculation
surfaces also carry O-040 without a status change.

## Verification

The batch must contain 52 target-relevant surfaces, 29 `target_mapped` entries
and 23 named holds. Every mapped entry must have non-empty owner, target
surfaces, security, Sync, migration rule, reconciliation, tests and acceptance
fields. Conversion/capability/query checks and M0 remain required. M1 remains
blocked only by the canonical production profile and O-022 cutover evidence.

This evidence proves reviewed target mapping only. It does not resolve
O-024–O-026/O-040, create Supabase tables/policies or PowerSync streams, implement
app/MCP commands, access production, migrate data, release, or cut over.
