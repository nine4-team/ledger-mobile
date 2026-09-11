# EVID-M2-REPORTING-SEARCH-001 — Reporting, Search, and Export Target Mapping

- Timestamp: 2026-08-31
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Mapping batch: `M0-REPORTING-SEARCH-001`
- Method: `target-mapping-method.md`

## Scope and Result

The batch contains 37 `replace`, `redesign`, or `migrate` surfaces. Nineteen
stable named-projection/search/lookup/artifact/export/property/test surfaces now
have complete target maps. Eighteen remain deliberately `characterized` because
their exact report/analytics meaning, receipt delivery, posting readiness or
generic-mutation behavior depends on A-015 or O-003–O-015/O-027–O-036.

## Mapping Decisions

- Raw/full/arbitrary-field MCP resources and bulk getters map to named versioned
  visibility-safe projection profiles and `EntityLookupQuerying`. Every requested
  ID is re-authorized; missing and inaccessible use one non-enumerating result.
- Universal search uses authorized versioned local index rows, stable ranking/
  cursors and explicit readiness. Legacy proto matches resolve only through
  their imported Item/quarantine outcome; app and MCP share predicates.
- Project catalog, Project detail, Inventory summary and Space navigation use
  canonical snapshots with source/authority versions, not raw documents or
  cached budget fields.
- PDF/CSV generation consumes immutable authorized `ReportSnapshot`/
  `ExportSnapshot` values. Rendering cannot recalculate domain values or widen
  fields; temporary artifacts are protected, randomized, receipted and cleaned.
- Named CSV profiles replace raw backend/URL/legacy movement columns. Exact
  cents, stable row order and escaping are deterministic.
- Property reporting derives Item-by-Space placement from authoritative stable
  relationships and declares partial readiness rather than scanning mutable
  context arrays.

Architecture contracts now explicitly include `EntityLookupQuerying` alongside
the existing search/report/export and protected artifact ports.

## Withheld Surfaces

The 18 held entries name only mapping-changing decisions. O-035 still owns
Client Summary financial semantics and O-036 owns client-shared receipt evidence
and delivery; neither is silently answered by current UI/HTML/CSV behavior.
Cross-domain analytics and posting/reconciliation surfaces retain their exact
underlying accounting/evidence blockers.

## Verification

The batch must contain 37 target-relevant surfaces, 19 `target_mapped` entries
and 18 named holds. Every mapped entry must have non-empty owner, target
surfaces, security, Sync, migration rule, reconciliation, tests and acceptance
fields. Conversion/capability/query checks and M0 remain required. M1 remains
blocked only by the canonical production profile and O-022 cutover evidence.

This evidence proves reviewed target mapping only. It does not resolve held
decisions, build indexes/projections/renderers, implement app/MCP behavior,
access production, migrate data, release, or cut over.
