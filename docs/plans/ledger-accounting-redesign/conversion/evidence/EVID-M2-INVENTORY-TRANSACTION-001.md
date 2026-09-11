# EVID-M2-INVENTORY-TRANSACTION-001 — Inventory, Transaction, and Provenance Target Mapping

- Timestamp: 2026-08-31
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  from the history now carried by `firebase`; the historical audit began from a
  dirty source checkout
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Mapping batch: `M0-INVENTORY-TRANSACTION-001`
- Method: `target-mapping-method.md`

## Scope and Result

The batch contains 66 `replace`, `redesign`, or `migrate` surfaces. Twenty-three
stable contract/query/presentation/history/correction/test surfaces now have
complete target maps. Forty-three remain deliberately `characterized`
because their exact money, movement, occurrence, receipt, lifecycle, correction
or retention contract depends on the named A-015/O-002–O-016/O-023/O-027/
O-029–O-032 decisions.

## Mapping Decisions

- The Firebase Transaction CRUD/listener seam maps to typed
  `TransactionQuerying`, Purchase, money Return, Transfer and correction
  operations. Generic patch/delete/Item association is not a target operation.
- Transaction list/detail/filter/card/search projections preserve real money
  evidence and classify legacy source types; mutable Item arrays, source strings
  and movement flags do not become target authority. App and MCP share one
  bounded indexed projection and visibility policy.
- Inventory workspace Sync explicitly includes visibility-safe occurrence/
  lineage evidence sufficient to explain current placement and sale/return/
  resale provenance offline. On-demand history has stable cursors and explicit
  complete/partial readiness; optional/latest-edge inference is retired.
- Source Purchase planning intent remains explicit migration evidence but is
  not mapped target behavior. O-038 decides retention, Purchase-versus-Item
  granularity, destination/category shape and lifecycle; D-013 prevents the
  legacy intended category from becoming Item-charge category authority.
- Stable correction surfaces map to typed scope/placement correction commands
  with before/after evidence, expected revisions, durable receipts and no
  invented cash. Generic actions that may actually be movement/Transfer remain
  held on the relationship model.
- Vendor custody/disposition is separate from an actual scope-owned money
  Return. Story-specific eligibility queries replace attaching Items to generic
  Transactions.
- Receipt audit maps to the D-016 exact-cent line equation and authoritative
  history evidence; percentage tolerance and mutable membership are excluded.
- Story and integration tests are owned by semantic target suites against
  isolated local/cloud staging, never the production Firebase app.

Architecture contracts now name Transaction and Item/Project history ports. The
Inventory stream continues to require offline accounting provenance evidence;
planning ports/stream membership remain absent until O-038 closes.

## Withheld Surfaces

The 43 held entries list only their mapping-changing decision IDs. Confirmed
D-decisions remain authoritative—especially three Transaction types, scope-
relative money, same-Client Transfer, no fake Business-paid Project Purchase
and no vendor-credit type—but do not justify choosing unresolved occurrence,
credit, tax, lifecycle or deletion schema.

## Verification

The batch must contain 66 target-relevant surfaces, 23 `target_mapped` entries
and 43 named holds. Every mapped entry must have non-empty owner, target
surfaces, security, Sync, migration rule, reconciliation, tests and acceptance
fields. Conversion/capability/query checks and M0 remain required. M1 remains
blocked only by the canonical production profile and O-022 cutover evidence.

This evidence proves reviewed target mapping only. It does not resolve held
product questions, approve Supabase/PowerSync, create schema/handlers/streams,
implement app/MCP behavior, access production, migrate data, release, or cut
over.

## Corrective Authority Audit — 2026-09-02

Enhanced subagent-pilot review caught that three planning surfaces had been
advanced from a broad batch authority set even though no canonical target spec
or confirmed D decision preserved the feature. The audit demoted
`MCPTOOL-42E5CABFC6F6`, `MCPTOOL-4FF3862CBCD5`, and
`FUNCMOD-E7CB6889A620`, added O-038 to the combined MCP module and current
next-step logic, removed premature planning ports, and retained only the safe
source-evidence/no-accounting-effect migration boundary. No implementation was
delegated or accepted.
