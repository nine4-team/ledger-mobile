# EVID-M2-SPACES-REVIEW-001 — Spaces, Review, and Work-Queue Target Mapping

- Timestamp: 2026-08-31
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Mapping batch: `M0-SPACES-REVIEW-001`
- Method: `target-mapping-method.md`

## Scope and Result

The batch contains 27 `replace`, `redesign`, or `migrate` surfaces. Sixteen
stable Space/query/model/create/update/checklist/assignment/test surfaces now
have complete target maps. Eleven remain deliberately `characterized` because
O-023, O-026, O-032, O-037 or A-015 can still change their archive, attachment-
removal, work-queue or optimistic-operation boundary.

## Mapping Decisions

- `SpaceQuerying` returns Project/Inventory-scoped local list/detail snapshots
  with stable Space/checklist IDs, revisions and readiness. Missing IDs are
  normalized during migration, never randomized during decode.
- Create, detail update, checklist revision and Item assignment use typed
  durable operations with expected revisions and one observable result. Generic
  field dictionaries, full-array fan-out and cross-scope Item assignment are
  excluded.
- Space review notes map to stable note IDs, trusted actor/time evidence and
  `AttachmentID` visual references. Firebase URLs remain migration correlation,
  not identity; attachment removal remains held on O-023.
- Project and Inventory Space workspaces consume the same local query contract.
  Template selection uses authorized reference snapshots but never grants
  template mutation authority.
- Target tests cover stable ordering, checklist progress, assignment, readiness,
  security and isolated Supabase/PowerSync integration rather than Firebase
  CRUD/listener mechanics.

Architecture contracts now explicitly include `SpaceQuerying`; the existing
typed `SpaceOperations`/`SpaceReviewOperations` remain the only mutation
boundaries. Physical archive/delete behavior is not guessed.

## Withheld Surfaces

The 11 held entries list only their mapping-changing decision IDs. In
particular, O-037 owns assigned-Item effects when archiving a Space, O-032 owns
posting-review state, O-023 owns review attachment removal/retention and A-015
owns complex optimistic projection. Generic Space hard delete is never a
provisional target operation.

## Verification

The batch must contain 27 target-relevant surfaces, 16 `target_mapped` entries
and 11 named holds. Every mapped entry must have non-empty owner, target
surfaces, security, Sync, migration rule, reconciliation, tests and acceptance
fields. Conversion/capability/query checks and M0 remain required. M1 remains
blocked only by the canonical production profile and O-022 cutover evidence.

This evidence proves reviewed target mapping only. It does not resolve the held
decisions, create target schema/handlers/streams, implement app/MCP behavior,
access production, migrate data, release, or cut over.
