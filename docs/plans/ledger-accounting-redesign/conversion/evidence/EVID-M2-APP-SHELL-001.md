# EVID-M2-APP-SHELL-001 — App Shell, Presentation, and Test Target Mapping

- Timestamp: 2026-08-31
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Mapping batch: `M0-APP-SHELL-PRESENTATION-001`
- Method: `target-mapping-method.md`

## Scope and Result

All 39 `replace`/`redesign` surfaces in the final 115-surface app-shell batch
now have exact target ownership, named typed surfaces, security obligations,
local/Sync behavior, source migration treatment, reconciliation, tests, and
observable acceptance. All 39 reached `target_mapped`; all corresponding field-
completeness queries return zero gaps.

The other 76 surfaces in the batch are deliberate `preserve`, `retire`, or
`source_only` outcomes and do not require an M2 replacement map under the
manifest gate.

## Mapping Decisions

- `MainTabView` maps to one `WorkspaceCoordinator` and
  `WorkspaceReadinessSnapshot`, not view-owned Account/Inventory listeners.
- Auth/account/member views map to Identity and Membership snapshots and typed
  commands; Firebase Auth/Firestore types and provider sessions do not cross the
  presentation boundary.
- Item controllers, sheets, menus and conflicts map to
  `AvailableItemActionsSnapshot`, story-specific command ports and shared
  operation results; no generic raw patch, relationship clear, delete, Sale, or
  ambiguous Return command survives.
- Item editing/copy/status/image-evidence flows use typed drafts/commands,
  stable Item/Attachment IDs, durable local acceptance, server revalidation and
  visible rejection/conflict.
- List controls/filter/sort/grouping map to named readiness-aware local query
  contracts with stable order/cursors and authorized facets. Display grouping
  never becomes physical identity or accounting authority.
- zoom/image grouping maps to stable Attachment identity and a local-first
  authorized resolver instead of URL identity/direct URLSession fetch as the
  domain contract.
- Firebase listener/relationship and source-era Sale/payment tests map to target
  workspace, PowerSync, RLS, durable-operation, Purchase/Return/Transfer and
  story-specific contract tests. Useful source assertions remain evidence, not
  target semantics.

## Blocker Treatment

Named product/architecture blockers remain on the applicable entries. They gate
provider choice, capability enablement, schema detail, or implementation tests;
they do not change the provider-neutral owner and boundary recorded here. No
generic implementation blocker was used.

This does not resolve A-004/A-007/A-016 or O-002–O-037, approve A-003/A-004,
or authorize implementation. If a later product decision changes an owner,
command/query boundary, security policy, Sync responsibility, migration rule,
or acceptance outcome, the affected target map must be revised and re-reviewed.

## Verification

The following passed after synchronization:

- batch JSON parsing;
- conversion sync/check with 685 recorded / 673 currently discovered, zero
  errors and zero warnings;
- 39 target-relevant and 39 `target_mapped` surfaces in the batch;
- zero missing owner, target surface, security, Sync, migration rule,
  reconciliation, test, or acceptance fields in the batch; and
- cumulative M0 remains passing while M1 remains correctly blocked only by
  `MAN-DATA-001` and `MAN-CUTOVER-001`.

This evidence proves reviewed M2 design mapping for this bounded batch only. It
does not prove implementation, production data coverage, security enforcement,
offline durability, migration, rehearsal, release, or cutover.
