# EVID-CAPABILITY-INVOICING-BUDGET-001 — Invoicing, Collection, and Budget Authority

- Timestamp: 2026-08-31
- Class: static source/spec characterization and capability synthesis
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Primary artifact:
  `capability-dossiers/invoicing-collection-and-budget-authority.md`

## Sources Reviewed

- Swift Invoice/InvoiceLine models, service/protocol, creation/detail/Finances
  views, line/billing/date/money calculations, Fee services/models, project and
  account contexts, and financial-access filtering;
- Swift budget service/model/calculations and budget/category/pin/project-card
  presentation surfaces;
- local Amazon/Wayfair vendor-document parsing, review, debug, and commit flow;
- MCP Invoice module and tools, contract setup, billable-pool and budget
  resources/queries, plus the independent budget-sign utility;
- current Firestore rules, Invoice events, Fee/allocation/category permissions,
  budget/completeness/repricing Functions, backfills, repair scripts, and
  migration utilities;
- Swift/MCP tests for collection, line selection, billing summaries, budget
  arithmetic, formatting, access filtering, and legacy behavior; and
- canonical Invoice-centered accounting and Item-lifecycle specs, current
  billing/budget specs, redesign impact analysis, decision log, and architecture
  package.

## Method and Result

The review followed each visible Invoice, Invoicing, Fee, vendor-import, budget,
and collection outcome through its model, UI caller, Swift service, MCP path,
rules/Functions, tests, and migration evidence. Current observable behavior was
then reconciled against D-001–D-027 and existing open decisions. Source
mechanics were classified separately from outcomes worth preserving.

The resulting dossier defines target-neutral typed Invoice/Expense/Fee command
families; separates live source links from immutable paid lines; specifies one
serializable, idempotent whole-Invoice collection; and defines one stable
budget-contribution identity that moves unpaid to paid without double counting.
It also routes the misleadingly named vendor “Invoice Import” to Purchase or
Expense intake based on payer/scope instead of Client Invoicing.

Two previously untracked decisions were added: O-033 controls actual payment
variance at collection, with exact equality as the safe provisional contract;
O-034 controls sent-Invoice membership revision, resend, render, and delivery
audit while preserving D-011 live source values.

## Material Findings

- Swift accepts an actual collection amount and ignores it; Swift and MCP then
  create one `paymentToBusiness` Transaction per category rather than the one
  target Project Purchase.
- Both app and MCP support selected-line/partial collection even though the
  approved redesign permits only whole-Invoice collection.
- Collection is composed from caller-cached source lines or MCP preflight reads,
  with no serializable source-set/revision claim. Concurrent or stale clients
  can produce duplicate or incorrect settlement evidence.
- Created/sent source amounts are duplicated and various readers disagree about
  whether send freezes them. Missing legacy line IDs decode nondeterministically.
- Public paid/status/cancel/payment-correction paths mutate lifecycle state
  without one complete append-only correction contract.
- Returned paid-Item credit is stored as a manual line, erasing the typed Item
  occurrence and provenance relationship.
- Current “Expenses” are inferred from Transactions; Fee ceiling and membership
  validation is client-snapshot based and race-prone.
- Budget authority is split between live Transaction-only arithmetic and an
  asynchronously maintained `budgetSummary`; neither represents the required
  paid/unpaid source segments, and both can drift.
- Invoice, billing, budget, MCP, analytics, and report surfaces duplicate related
  arithmetic and sometimes infer collection from paid status without payment
  evidence.
- Current financial access primarily filters rows after download. The target
  must exclude unauthorized values, row counts, source names, and provenance at
  RLS and Sync Stream boundaries.
- Vendor-document import always creates a Project Purchase before separately
  creating Items, without establishing payer/scope or one atomic outcome.

## Target Contract Established

- `CreateInvoice`, `ReviseCreatedInvoice`, `MarkInvoiceSent`, `CancelInvoice`,
  and `CollectInvoice`; sent-membership revision remains gated by O-034.
- Typed Expense and Fee create/update/cancel operations with state-specific
  mutability; O-006/O-009/O-010 retain their product gates.
- No target `MarkInvoicePaid`, selected-line collection, generic line CRUD, or
  caller-authored source financial value.
- Collection locks and re-resolves the exact source set, validates one actual
  payment, freezes every source/allocation revision, creates one Project
  Purchase, and stores one durable operation result atomically.
- `ProjectBudgetSnapshot` derives paid, unpaid, recognized, budget, remaining,
  and overage values from canonical stable contributions; Invoice links and the
  collection Purchase face amount are non-additive evidence.
- Migration treats paid status, partial settlement, grouped payment rows, and
  cached budget summaries as evidence to reconcile or quarantine, never as
  permission to invent target payment or budget authority.

## Limitations

Production Invoice status/line/source distributions, missing/unstable IDs,
partial/grouped settlement frequency, status-only paid rows, manual-line kinds,
Fee overage, category drift, budget-summary divergence, and access-policy data
exposure remain unconfirmed until the fail-closed read-only production profile
runs. Final schema and enabled capabilities still depend on O-003–O-010,
O-015, O-023, O-029–O-034, A-003/A-004/A-015/A-016, the target vertical spike,
and reviewed migration classifications.

This evidence supports target-independent command, read-model, security,
offline, migration, and test design only. It does not authorize Postgres DDL,
Supabase RLS/RPCs, PowerSync Streams, Firebase refactoring/adapters, production
reads/mutations, migration, or cutover.
