# EVID-M2-ITEM-CREATION-001 — Unified Item Creation and Link Target Mapping

- Timestamp: 2026-08-31
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Mapping batch: `M0-ITEM-CREATION-LINK-001`
- Method: `target-mapping-method.md`

## Scope and Result

The batch contains 31 `replace`, `redesign`, or `migrate` surfaces. Fourteen
stable query/presentation/port/bulk/test surfaces now have complete target maps.
Seventeen remain deliberately `characterized` because A-015 or O-007/O-015–
O-019/O-023/O-027 can still change their exact schema, validation, Link,
reconciliation, optimistic projection or dependency/retention command.

O-021 is explicitly treated as UI-only. It may choose one expandable screen or
two sequential steps, but it does not block Item identity, commands, schema or
migration mapping. Surfaces that mention O-021 remain held only when another
named domain/product decision changes their map.

## Mapping Decisions

- Firebase listener/CRUD seams map to typed `ItemQuerying`,
  `ItemDetailReadModelQuerying`, `ProjectItemAccountingQuerying`,
  `ItemOperations` and `BulkItemOperations`; there is no Firebase adapter,
  arbitrary field update or generic set/clear Transaction operation.
- Local Item lists/details/cards use one stable physical Item identity plus
  explicit readiness and authorized relationship evidence. Space, Invoice
  membership and an unready/missing relationship cannot fabricate Accounting
  For state.
- MCP list/detail/search uses the same versioned projections as the app, with
  indexed bounded queries, stable cursors, Principal/Account authorization and
  financial-field filtering rather than Admin SDK scans/client filtering.
- Bulk metadata changes use a typed safe-field allowlist, stable Item IDs,
  expected revisions and a resumable per-Item result. Sequential backend chunks
  cannot silently masquerade as one successful logical action.
- Target tests replace Firebase-emulator/free-text/unlinked-rejection mechanics
  with semantic stable-ID Item fixtures. The confirmed CreateItem/Link behavior
  suite asserts that an Unaccounted For Project Item is valid and financially
  inert; decision-sensitive validation/schema cases remain parameterized holds.

Architecture contracts now explicitly include Item list/search/detail/
accounting-section query ports, typed detail operations and bulk operation
receipts. A generic hard delete remains absent.

## Withheld Surfaces

The 17 held surfaces name only applicable blockers: final occurrence/
relationship schema (O-007/O-015), missing acquisition evidence (O-016),
optional capture hint (O-017), proto import/reconciliation (O-018/O-019),
optimistic complex projection (A-015), retention/deletion (O-023) and the shared
minimum-evidence rule (O-027). No source proto, transactionId or hard-delete
mechanic is treated as provisional target authority.

## Verification

The batch must contain 31 target-relevant surfaces, 14 `target_mapped` entries
and 17 named holds. Every mapped entry must have non-empty owner, target
surfaces, security, Sync, migration rule, reconciliation, tests and acceptance
fields. Conversion/capability/query checks and M0 remain required. M1 remains
blocked only by the canonical production profile and O-022 cutover evidence.

This evidence proves reviewed target mapping only. It does not resolve the held
decisions, create target schema/handlers/streams, implement Item behavior,
access production, import proto records, release, or cut over.
