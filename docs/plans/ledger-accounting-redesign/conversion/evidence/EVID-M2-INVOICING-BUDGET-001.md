# EVID-M2-INVOICING-BUDGET-001 — Invoicing, Collection, and Budget Target Mapping

- Timestamp: 2026-08-31
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Mapping batch: `M0-INVOICING-BUDGET-001`
- Method: `target-mapping-method.md`

## Scope and Result

The batch contains 44 `replace`, `redesign`, or `migrate` surfaces. Twenty-one
stable budget/Invoice/billing/authorization/vendor-intake/port/test surfaces now
have complete target maps. Twenty-three remain deliberately `characterized`
because O-003–O-010, O-015, O-029, O-033, O-034 or A-015 can still change their
exact source, collection, lifecycle, display, correction or delivery contract.

## Mapping Decisions

- `ProjectBudgetSnapshot` is the sole budget read authority. Stable contribution
  identities map each economic value into paid, unpaid and recognized segments
  without Invoice links, collection Purchase face value or cached summaries
  double counting it.
- Invoice list/detail projections transform embedded Firebase arrays into
  relational live source links and immutable collection evidence with revision,
  readiness and visibility metadata. App and MCP use one projection contract.
- `ProjectBillingSummarySnapshot` derives open, invoiced, collected, credited
  and outstanding values from authoritative demand/collection evidence, not
  paid-status or payment-Transaction fallbacks.
- Financial RLS/security-invoker queries and Sync Streams remove unauthorized
  rows, counts, amounts and categories before local download. In-memory filters
  remain presentation defense only.
- Vendor-document drafts use stable local document/line IDs and one durable
  typed commit operation for Purchase/Expense/Item effects. UI-layer Firebase
  fan-out and silent partial success are excluded.
- Firebase Invoice service seams map to `InvoiceQuerying`, typed
  `InvoiceOperations`, `BillingSummaryQuerying` and durable receipts. Generic
  embedded-line mutation and partial collection are absent pending decisions.
- Contribution and collection contract tests assert one real collection
  Purchase, immutable frozen evidence and unpaid-to-paid movement without total
  spend growth. Decision-sensitive payment variance/delivery cases remain held.

Architecture contracts now explicitly name Invoice and billing query ports and
vendor-document intake operations.

## Withheld Surfaces

The 23 held entries list only mapping-changing decisions. In particular O-009
manual adjustments and O-010 zero-dollar Invoice behavior remain first-class
schema/validation blockers, and O-033/O-034 remain collection-payment and sent-
membership/delivery blockers. Current embedded lines, partial collection and
Transaction-only budgets are never provisional target behavior.

## Verification

The batch must contain 44 target-relevant surfaces, 21 `target_mapped` entries
and 23 named holds. Every mapped entry must have non-empty owner, target
surfaces, security, Sync, migration rule, reconciliation, tests and acceptance
fields. Conversion/capability/query checks and M0 remain required. M1 remains
blocked only by the canonical production profile and O-022 cutover evidence.

This evidence proves reviewed target mapping only. It does not resolve held
decisions, create target schema/handlers/streams, implement app/MCP behavior,
access production, migrate data, release, or cut over.
