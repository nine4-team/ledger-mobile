# EVID-CAPABILITY-REPORTING-SEARCH-001 — Reporting, Search, and Cross-Domain Projections

- Timestamp: 2026-08-31
- Class: static source/spec characterization and capability synthesis
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Primary artifact:
  `capability-dossiers/reporting-search-and-cross-domain-projections.md`

## Sources Reviewed

- Swift universal search matcher/view, search controls/placeholder, Space search
  detail, selection UI and the Project/Client context lookups/actions they use;
- Accounting report navigation, report aggregation, Invoice/Client Summary/
  Property views, HTML/CSS builder, PDF renderer/share/download lifecycle;
- Transaction CSV field configuration, row generation, escaping, temporary-file
  creation, and tests;
- MCP resources, analytics, bulk getters, projections/response budgets, search
  helpers, incomplete-Transaction triage, and already-characterized list/search
  consumers;
- search, report, Invoice-centered accounting, financial access, offline, media,
  Item, placement, Transaction and Client/Transfer specs; and
- current tests plus the manual report/export/search parity gate.

## Method and Result

Every current result or artifact was traced backward from visible fields/totals
to its raw array/query inputs, arithmetic, authorization boundary, readiness
assumption, renderer, and tests. Those source mechanics were reconciled against
the completed identity, media, Project/Client, Item, Inventory/Transaction, and
Invoicing/budget dossiers.

The result defines target-neutral `UniversalSearchPage`, `ReportSnapshot`, and
`ExportSnapshot` contracts with named visibility-safe profiles, stable ordering/
cursors, source and accounting-authority versions, as-of/currency metadata, and
explicit input readiness. It separates pure rendering from accounting, removes
target raw/full backend projections, and requires app/MCP/PDF/CSV parity from one
canonical projection authority.

O-035 now tracks the unsupported “Total Spent” meaning in Client Summary.
O-036 tracks receipt evidence in client-shared artifacts; raw private paths and
expiring bearer URLs are prohibited regardless of the eventual policy.

## Material Findings

- Current app search performs full scans of partially loaded independent arrays,
  has no readiness/rank/page contract, and differs from MCP matching fields.
- Search includes target-retired ProtoItems, omits authoritative Client/Project
  result kinds, and owns broad generic mutations that should invoke typed domain
  commands instead.
- Amount hits/counts can leak hidden financial values unless authorization is
  enforced before local search indexing.
- The generic Accounting “Invoice” report derives demand from all inferred
  reimbursable Transactions instead of one Invoice revision/source set.
- Paid status can select frozen rendering without proven payment; missing live
  sources fall back to plausible stored values without an integrity warning.
- Client Summary calls active physical Item project prices “Total Spent” and
  omits the complete paid/open/credit/Expense/Fee/Transfer accounting model.
- Report views and HTML builder recompute some values; no snapshot carries
  readiness, visibility, version, currency, as-of, or source-revision evidence.
- Current PDF/logo/receipt handling depends on network URLs, can embed tokenized
  Storage access, uses one global renderer, swallows errors, and has no explicit
  protected-file cleanup contract.
- CSV exports mutable raw Transaction arrays and legacy/internal fields/URLs
  without deterministic order, completeness/version manifest, or formula-input
  hardening.
- MCP resources/bulk getters expose raw/full/arbitrary fields, cached budget
  summaries, unstable offsets, and service-credential analytics with duplicated
  or incorrect accounting semantics.

## Limitations

Production report usage, exported field selection, Invoice-render variants,
receipt/logo URL shapes, Client Summary expectations, search query/ranking
patterns, result sizes, MCP response profiles, hidden-data exposure, PDF failure
rates, and current artifact retention remain unconfirmed until read-only
profiling, telemetry review where authorized, and staging migration fixtures.
Final target mapping depends on O-003–O-016/O-023/O-028–O-036,
A-003/A-004/A-015/A-016, production-scale local index measurement, and
`MAN-REPORT-001` evidence.

This evidence supports target-independent query, renderer, security, offline,
migration, and test design only. It does not authorize Postgres DDL, Supabase
RLS/RPCs, PowerSync Streams, Firebase refactoring/adapters, production reads/
mutations, migration, or cutover.
