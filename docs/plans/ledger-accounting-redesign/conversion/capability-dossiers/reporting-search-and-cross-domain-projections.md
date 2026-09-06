# Capability Dossier — Reporting, Search, and Cross-Domain Projections

Status: reviewed static characterization; 19 of 37 target-relevant surfaces are
exactly target-mapped. Eighteen report-semantic/delivery/posting/mutation
surfaces remain honestly withheld on their named blockers; implementation
remains unauthorized

## Outcome

An authorized Ledger user can search the synchronized working set and identify
the correct Project, Client, Item, Space, Transaction, Invoice, or accounting
source with enough context to act safely. The user can generate consistent
on-screen, PDF, print, CSV, and MCP representations from the same canonical,
visibility-safe, readiness-complete projections while offline. Every result and
artifact states its scope and as-of/version boundary; no search hit, count,
total, field, link, or omission leaks restricted financial facts.

Search, reporting, export, and analytics do not own accounting or mutation.
They consume stable projections from the contexts that do. A renderer cannot
convert status into payment, rederive money from raw entities, infer missing
provenance, or widen authorization.

## Boundary

This dossier owns:

- universal search matching, ranking, result context, stable paging, local
  readiness, and action-capability presentation;
- Invoice, Client Summary, and Property Management report snapshots and their
  screen/PDF/print renderers;
- Transaction/accounting CSV export selection, stable row semantics, artifact
  manifest, and local file lifecycle;
- MCP bulk lookup, resources, response projections, analytics, size budgets,
  stable cursors, and visibility-safe output profiles;
- cross-domain summary fields and the rule that every derived amount names one
  canonical projection/version; and
- migration and parity evidence for legacy reports, exports, cached summaries,
  raw/full MCP responses, search results, and client-visible totals.

It does not own the underlying Item, placement, Transaction, Invoice, Expense,
Fee, budget, Client, attachment, membership, or correction rules. It consumes
the completed capability contracts for those contexts. Search result actions
invoke their typed command ports and are not alternate CRUD implementations.

## Source Surfaces

### Swift search and navigation

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-42D1850CD848` | `SearchCalculations` | In-memory substring, normalized-SKU, and formatted-amount prefix matching over Item, ProtoItem, Transaction, and Space arrays |
| `SWIFT-F3BDD0968C6D` | `UniversalSearchView` | Debounced account-wide scan, tabbed results/counts, Project-name lookup, selection totals, navigation, and broad Item/Transaction bulk mutations |
| `SWIFT-1AFC0C0D73D7`, `SWIFT-E16F2BBFB7DB`, `SWIFT-AE46427AE831` | Search field/control/placeholder | Search entry and empty shell presentation |
| `SWIFT-6A89422B64D8` | `SpaceSearchDetailView` | Minimal Space detail resolved from account-wide arrays with an in-memory Item count |
| `SWIFT-7BC5A6440292` | `BulkSelectionBar` | Shared selection/count/amount action presentation |

Search scans whatever independent `AccountContext` listeners have currently
loaded. It does not know whether the account/project working set is complete.
Items, Transactions, and Spaces preserve source array order rather than one
documented relevance/order contract. Current app and MCP matching fields differ,
and the app searches legacy ProtoItems that the target retires.

The universal screen also owns generic status, Space, Transaction-link, move,
and delete actions. Those mutation mechanics belong to the Item, movement, and
Transaction command contexts; only the discoverability and selection outcomes
belong here.

### Swift reports and exports

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-602AA12C6003` | `AccountingTabView` | Recomputes payables and three reports from independently loaded Project/Account arrays |
| `SWIFT-6109B0A97167` | `ReportAggregationCalculations` | Converts legacy Transaction/reimbursement/movement fields, mutable Items, current Invoice lines, Fees and Spaces into Invoice, Client Summary and Property Management data |
| `SWIFT-E09C688A850B`, `SWIFT-1772D7B7CE10`, `SWIFT-CC7424F01DD0` | Report views | Present Invoice, Client Summary and Property Management totals/rows and start PDF sharing |
| `SWIFT-7C0540EDB528`, `SWIFT-DA1BA46ED84B` | HTML builder/styles | Independently renders the report models to escaped HTML/CSS, but recalculates some Item/Space values during rendering |
| `SWIFT-AC99E4923E17` | PDF sharing | Uses one retained `WKWebView`, a fixed delay, predictable temporary filenames, and print/share/download sinks |
| `SWIFT-63EA86A59559`, `SWIFT-CB4AC317DF5E`, `SWIFT-DFC984E30F2F` | Export fields/calculation/modal | Lets the user select raw Transaction-shaped columns, emits CSV from caller arrays, writes it to a temporary path, and shares it |

The report screen and HTML builder can compute the same displayed value more
than once. Report input models carry neither source identity/revision nor local
readiness, visibility scope, accounting authority version, currency, or as-of
time. PDF failure is printed rather than surfaced; one global active web view
can be replaced by a concurrent request; temporary artifacts have no explicit
cleanup/retention contract.

Current Client Summary `totalSpentCents` is the sum of active physical Items'
project prices. It is not actual Client money and excludes Expenses, Fees,
credits, collection state, and Transfer allocations. Its report label therefore
asserts a financial meaning the inputs do not prove.

### MCP resources, analytics, search, and bulk reads

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `MCPMOD-14F6F6559251` plus `MCPRESOURCE-12DDDD1FF641`, `MCPRESOURCE-46F41439CD48`, `MCPRESOURCE-DF8684F8F268` | resources | Exposes all active Project cached budgets, one raw Project document, and Inventory Item count/value summaries |
| `MCPMOD-917C20FEDA6A` plus analytics tools | analytics | Computes Project health, Inventory value, raw spending by vendor, budget variance, and Item-attention lists directly from Firebase rows |
| `MCPMOD-B4D4B0CAEF8C` plus bulk-get tools | bulk getters | Fetches up to 50 known IDs with summary/full/arbitrary-field projection and byte capping |
| `MCPMOD-69B08099B8DF` | response projections | Defines backend-shaped summaries, raw/full and arbitrary-field selection, formatted money, byte truncation, and offset continuation |
| `MCPMOD-6B3872A8E6FB` | search helpers | Independently implements text/SKU/amount matching for MCP Item/Transaction/Quick Draft paths |
| `MCPMOD-4A73B044281F`, `MCPTOOL-BC13265D05FD` | composite/triage | Ranks incomplete Transactions using legacy ingestion/completeness/category/tax fields and suggests a generic reconciliation tool |

Already-characterized list/search/detail tools in the Item, Project, Invoice and
Transaction dossiers also consume these shared projection helpers. They remain
dependencies here without being classified twice.

Useful MCP outcomes include batching, explicit found/missing IDs, compact
default summaries, response-size budgets, truncation disclosure, filters, and
read-only analytics. The current `full`/arbitrary-field modes, Admin-SDK reads,
offset continuation, cached budget fields, raw-document resources, and
per-tool accounting logic are not target contracts.

### Tests and manual coverage surface

- `TEST-E7854675A914` proves much of the current app text/SKU/amount matcher and
  legacy Transaction naming behavior.
- `TEST-880C5785FD49` and `TEST-BA9C46AF6F3D` encode report aggregation,
  paid-status freezing, movement/reimbursement fallbacks, active-Item Client
  totals, receipt links, and Property grouping.
- `TEST-10C486B0508C` and `TEST-7F63900EA573` prove field selection, formatting,
  escaping, and the current legacy/raw CSV schema.
- `MAN-REPORT-001` remains the manual parity/reconciliation gate for reports,
  PDFs, exports, search projections, and client-visible totals. It is blocked
  until staging migration and production-like evidence exist.

## Current Observable Behavior and Defects

1. Search and reports cannot distinguish “zero results” from “required streams
   are still partial.” A disconnected or newly opened scope can appear complete.
2. Universal search scans all currently loaded arrays for every query and has
   no indexed/ranked/paged contract. Results inherit array/listener ordering.
3. App and MCP search fields differ. App includes IDs, category names, current
   source and mutable display names; MCP omits several and searches backend
   field names. Results are not portable across surfaces.
4. Search includes legacy ProtoItems and not authoritative Clients/Projects as
   first-class results even though the shell says it searches projects.
5. Amount matching searches Item purchase, project, and market values together.
   Without pre-download financial filtering, a match/count can reveal a hidden
   amount even if the row later redacts it.
6. Search result totals and Space counts are recomputed from account-wide arrays
   and can be stale, partial, unauthorized, or expensive.
7. Search directly exposes generic hard delete, status, Transaction-link, Space,
   and movement composition. Search is an entry point, not a second mutation
   authority.
8. The generic Accounting report creates an “Invoice” from all current inferred
   reimbursable Transactions instead of selecting one canonical Invoice source
   set/revision.
9. Invoice report freezing is keyed to `status == paid`; status-only legacy rows
   can render as immutable/collected without proven payment evidence.
10. Missing live sources fall back to copied line values without a report
    readiness/integrity warning, which can silently turn missing evidence into a
    plausible total.
11. Client Summary labels active physical Item project prices as “Total Spent.”
    It neither proves payment nor includes the complete accounting source set.
12. Client Summary and Property reports infer current inclusion from mutable
    Item status/project fields rather than the authoritative placement and
    contribution projections.
13. Receipt badges conflate vendor receipts with Client Invoices and can embed
    resolved Storage URLs in PDFs. Tokenized URLs can expire or leak bearer
    access after sharing.
14. Logo fetches bypass the attachment/local-cache contract, so nominally
    offline report generation can lose the logo or attempt network access.
15. Screen and HTML renderers recalculate Item/Space values, allowing different
    output paths to drift from the prepared report model.
16. PDF generation uses one global active renderer, a fixed layout delay,
    predictable filenames, no explicit file-protection/cleanup policy, and no
    user-visible failure result.
17. CSV export receives mutable caller arrays and has no scope completeness,
    authority version, stable ordering, artifact manifest, or formula-injection
    policy.
18. CSV fields expose source IDs, legacy movement/reimbursement/status fields,
    raw receipt URLs, and mutable `item.transactionId` membership without a
    named visibility-safe export profile.
19. MCP `project-detail` returns a raw Project document; bulk reads permit
    `full` rows and arbitrary field names. Those APIs couple callers to source
    persistence and can bypass field-level confidentiality.
20. MCP Project summaries trust asynchronous `budgetSummary`; Project health
    and budget variance independently re-sum current Transactions.
21. `spending_by_vendor` adds raw amounts without scope-relative Purchase/
    Return/Transfer, settlement, or contribution semantics, so its result is not
    dependable spend.
22. Inventory summary and Item attention compute over raw current rows without
    provenance/readiness and flag missing per-Item tax under a still-open O-031
    rule.
23. MCP triage ranks incomplete Transactions by legacy `isComplete`, missing
    tax/category/project and amount, even though O-032 and the accepted receipt
    model redefine posting/review readiness.
24. Response byte caps disclose truncation usefully, but offset continuation is
    not a stable cursor and `totalCount` can leak hidden existence unless computed
    after authorization.
25. No output carries the query/projection contract version needed to explain
    why app, MCP, PDF, CSV, and migration results differ over time.

## Product and Spec Reconciliation

| Authority | Assessment |
|---|---|
| `invoice-centered-project-accounting.md` | Canonical target authority for reported Purchases/Returns, live and paid Invoice values, Expenses/Fees and paid/unpaid budget segments |
| `inventory-item-invoicing-lifecycle.md` | Canonical target authority for Item charge/credit cycles, occurrence history and explainable Inventory/Project provenance |
| `proto-item-capture.md` | Canonical target authority for one real Item search identity, derived accounting status and migration-only proto review |
| `client-identity-and-project-transfers.md` | Canonical target authority for Client grouping, same-Client Transfer interpretation and Client-wide net-zero reporting |
| `non-item-receipt-lines/design.md` | Canonical target direction for receipt evidence and reconstructed totals; unresolved client-delivery policy remains blocked |
| D-001/D-007 | Reports/analytics use scope-relative Purchase/Return/Transfer; legacy Sale/payment/Expense/Fee Transaction labels are source evidence only |
| D-008–D-017 | Invoice and budget outputs consume live sources, frozen paid allocations, one collection Purchase and stable contribution identity without double count |
| D-022/D-023 | Item/search/report identity follows one physical Item and explicit Link/occurrence state, not a cloned Invoice Item or Space-derived accounting |
| D-025/O-018 | Target search contains real Items, not a new ProtoItem result kind; unresolved source proto records appear only in migration review |
| O-003–O-015/O-028–O-034 | Reports expose only approved credit, occurrence, receipt, correction, variance and sent-revision behavior; blocked semantics remain visibly unavailable |
| O-035 | Client Summary financial labels and aggregation basis remain blocked; current active-Item “spent” is not adopted |
| O-036 | Client-shared receipt inclusion/delivery remains blocked; raw paths and bearer URLs are prohibited regardless |
| O-041 | Business Vendor Cash Movement payer perspective, included Purchase/Expense/Return facts, signs, scope/date basis, credit treatment, currency partition and exact label-snapshot grouping remain blocked; current raw Transaction sum is not adopted |

## Behavior Decisions

| Classification | Decision |
|---|---|
| Preserve | Universal search entry point; case-insensitive text and normalized SKU matching; authorized amount search; Project context in results; offline report review; Invoice/Client Summary/Property report presentation; HTML escaping/styling; PDF/print/share; selectable CSV columns and correct CSV quoting; MCP batch found/missing behavior, compact summaries, response budgets and explicit truncation |
| Correct | Partial-read-as-empty; unstable ordering/offsets; app/MCP matcher divergence; status-as-payment; generic inferred Invoice report; active-Item-as-paid-spend label; missing-source silent fallback; receipt/Invoice conflation; remote logo/token URLs; renderer recomputation/concurrency/error/temp-file lifecycle; raw CSV relationships; analytics sign/accounting errors; hidden count/field leakage |
| Improve | Indexed local search, explicit ranking/cursors/scope readiness, Client/Project result kinds, source integrity warnings, named projection profiles, deterministic export manifests, data/formula hardening, visible artifact failures, protected cleanup, query versions and observability |
| Redesign | `UniversalSearchPage`, `ReportSnapshot`, and `ExportSnapshot`; one canonical query resolver per accounting/provenance value; Invoice live/frozen revision rendering; visibility-safe server aggregates; MCP queries over the same profiles; typed action capabilities that invoke owning commands |
| Retire | Target ProtoItem search; generic all-reimbursable “Invoice” report; MCP raw/full document mode and arbitrary field picker; source `budgetSummary` report authority; legacy Sale/payment-to-business/reimbursement export fields as normal target columns; expiring Storage URL export |
| Source only | Firebase array/query mechanics, legacy report/CSV shapes, cached summary values, status-only paid rendering and source parity fixtures after cutover |
| Open | O-003–O-015/O-023/O-028–O-036/O-041, A-003/A-004/A-015/A-016, final target query/index measurements and migration classifications |

## Target Query Contracts

### Readiness and version envelope

Every search/report/export/analytics result carries:

```text
accountId
requestedScope
visibilityScope
projectionContractVersion
accountingAuthorityVersion
localDataVersion or serverSnapshotVersion
asOf
currency
readiness.requiredInputs
readiness.state = complete | loading | partial | unavailable | integrity_blocked
```

Ordinary client-visible reports require `complete`. A diagnostic migration or
operator report may intentionally use `partial`, but it labels every omitted
scope and can never be delivered as a complete Client artifact.

### Universal search

`UniversalSearchRequest` contains normalized query text, authorized account/
optional Project scope, entity kinds, filters, page size, opaque cursor, and a
named result profile. `UniversalSearchPage` returns stable result IDs/kinds,
display context, matched-field class, rank/sort key, visibility-safe highlights,
action capabilities, next cursor, and readiness/version metadata.

Initial target result kinds are Client, Project, Item, Space, Purchase/Return/
Transfer, Invoice, and eligible Invoicing source. Migration-review records are a
separate operator surface. The local adapter uses indexed SQLite/FTS and
normalized SKU/amount-search columns measured against real account sizes. A
tie-breaker stable ID makes paging deterministic. Search indexes contain only
rows/fields already authorized for that local principal.

Search presents action capabilities such as `canOpen`, `canTransfer`, or
`canArchive`; selecting one launches the owning typed command flow. It never
performs generic field mutation or hard delete itself.

### Reports

`ReportRequest` names one report kind, Account/Project/Invoice scope, requested
as-of mode, visibility-safe profile, locale, and currency. `ReportSnapshot`
contains fully prepared rows/totals/labels, stable source identities, integrity
warnings, render metadata, and no mutable domain entities.

- Created/sent Invoice snapshots resolve the current canonical live sources and
  exact Invoice revision. Collected snapshots use immutable frozen paid lines,
  allocations, payment evidence, and delivery revision only.
- Client Summary financial rows remain disabled or explicitly nonfinancial until
  O-035 approves their basis and labels.
- Property Management uses current authoritative Item placements and value basis,
  with missing history/readiness explicit.
- Screen, HTML, PDF and print render the same snapshot values without another
  business calculation.

Rendering is local/offline after the snapshot and required attachment bytes are
ready. Branding uses stable attachment identity/local-or-remote display sources.
Report artifacts use unique protected temporary files, deliver a typed success/
failure receipt, and follow explicit cleanup/retention. O-034 owns Invoice
delivery evidence; other on-demand reports record enough version/as-of metadata
to reproduce or explain the result without necessarily storing every artifact.

### Exports

`ExportRequest` selects a named row profile and allowed column IDs rather than
raw storage fields. `ExportSnapshot` contains deterministic rows/order, schema
version, source scope/version, selected fields, visibility scope, readiness and
artifact metadata. CSV formatting remains pure and correct, additionally
neutralizing spreadsheet formula prefixes for untrusted text fields.

Target Transaction export uses Purchase/Return/Transfer and stable relationship
projections. Legacy fields may appear only in an explicit migration-audit export.
Receipt evidence uses stable eligible attachment metadata under O-036, never raw
paths or signed/tokenized URLs.

### MCP resources, lookup, and analytics

MCP uses the same named projection profiles and authorization facts as the app.
Known-ID batch lookup remains useful, but found/missing is computed after tenant
and financial authorization so it does not reveal another account or hidden row.
There is no `full` canonical document or arbitrary field-name mode.

List/search resources use opaque stable cursors and page sizes plus response-byte
budgets. Truncation never changes the cursor contract. Analytics query canonical
budget, Inventory, posting-readiness and provenance projections; they do not
reimplement signs, infer payment from status, or query raw rows through a service
credential without caller-bound policy. No vendor-spend aggregate is a target
contract until O-041 approves its payer perspective and exact accounting basis.

## Security and Privacy

- RLS and Sync Streams remove unauthorized source/projection rows before local
  search indexing. Safe server aggregates cannot reveal hidden counts, amounts,
  categories, names, source existence, or cursor totals.
- Named profiles enumerate fields by capability and financial visibility. Client
  requests can narrow a profile but cannot widen it.
- Result snippets, matched-field indicators, empty states, autocomplete counts,
  PDF/CSV filenames, telemetry, errors, and operation capability flags are all
  treated as possible side channels.
- Report/CSV/PDF output records the creator, account/project, visibility scope,
  projection version and creation time. Sensitive local files use platform file
  protection and explicit retention/cleanup.
- HTML escapes all untrusted text; links use an allowlist and approved delivery
  boundary. Raw Storage paths, query tokens, bearer URLs, local paths and HTML/
  spreadsheet formulas never pass through as inert “data.”

## Offline and Sync

- Previously synchronized authorized search works fully offline from local
  indexes. Results state which account/project scopes are complete.
- Reports/exports build offline only from a complete required working set.
  Missing uncached branding/evidence is explicit and follows the chosen policy;
  the renderer does not silently fetch network resources.
- A local data-version change invalidates or marks a prepared live report stale.
  Collected Invoice snapshots remain reproducible from immutable frozen rows.
- Permission revocation removes future local index/projection rows on reconnect;
  A-016 still bounds what a disconnected previously authorized device can see.
- Schema/index upgrades preserve prior client contracts through the supported
  release window and rebuild local indexes deterministically.

## Migration and Reconciliation

For every source account/project:

1. inventory legacy report/export/search shapes and source versions;
2. preserve raw report-relevant fields and relationship IDs as migration evidence;
3. map legacy Invoice reports to live or frozen target revisions only when
   source/payment evidence proves the classification;
4. classify current Client Summary, budget, vendor-spend and other totals as
   exact, intentionally changed, or blocked with source-level explanations;
5. verify current Item placement/Space grouping and quarantine unexplained
   returned/sold/orphan relationships;
6. map target CSV fields from canonical relationships while preserving a
   separate explicit legacy audit export where needed;
7. rebuild target search indexes/projections from imported canonical rows rather
   than copying source search/cache output; and
8. render staging screen/PDF/CSV/MCP fixtures and compare stable row identities,
   totals, categories, visibility and artifact metadata under approved semantic
   differences.

Source `budgetSummary`, `isComplete`, paid status, reimbursement/movement fields,
raw URLs and current report totals are comparison evidence, never unexplained
target authority.

## Verification Contract

### Search

- text, normalized SKU and authorized amount matching parity;
- Unicode/case/diacritic, token, prefix, empty, long-query and special-character
  fixtures;
- deterministic rank/tie/cursor behavior across insert/update/delete and restart;
- complete versus partial/empty readiness and offline restart;
- Project/Client/Item/Space/accounting context correctness;
- no ProtoItem result outside migration review;
- no hidden result, matched-field, count, total, snippet, cursor or action leak;
- target command invocation from a result without generic mutation; and
- measured index size/query latency at production-like account scale.

### Reports and exports

- screen/HTML/PDF/print/CSV equality from one immutable snapshot;
- created/sent live revision and collected frozen revision behavior;
- missing source/integrity/readiness blocks rather than plausible fallback;
- paid/open/recognized, credits, Returns, Transfers and collection no-double-count
  after O-035 closes;
- Property grouping from authoritative placement and stable ordering;
- locale/currency/rounding/negative/zero/large-value exactness;
- HTML, filename, URL and CSV formula-injection fixtures;
- offline generation/restart, missing branding/evidence, concurrent renders,
  user-visible failure, file protection and cleanup;
- O-036 receipt eligibility/delivery/revocation/expiry/retention when approved;
- full/limited/none financial access with zero hidden row/count/total leakage; and
- migration parity with every intentional difference named by source IDs.

### MCP and analytics

- app/MCP projection equality for the same actor/scope/version;
- named profile allowlist and rejection of raw/full/arbitrary hidden fields;
- known-ID found/missing isolation across account/financial boundaries;
- stable cursor and byte truncation under concurrent changes;
- canonical Project health, budget, Inventory, vendor and posting-readiness
  fixtures; and
- service-credential calls remain bound to the authenticated Ledger Principal,
  capability and audit.

## Dependencies and Gates

- Product authority: D-001–D-027 and O-002–O-036.
- O-035 blocks the target Client Summary financial total/label contract.
- O-036 blocks client-shared receipt evidence delivery; omission is safe now.
- O-034 blocks sent-Invoice membership/delivery revision details.
- O-003–O-015/O-028–O-033 block only report fields/analytics that depend on
  those unresolved behaviors, not the query/snapshot foundation.
- A-003/A-004 remain proposed until the PowerSync/Supabase vertical spike.
- A-015 controls complex optimistic operation overlays visible in search.
- A-016 controls disconnected authorization duration.
- Production parity classifications remain blocked on the fail-closed profile,
  migration fixtures, and `MAN-REPORT-001` staging evidence.

This dossier does not authorize target DDL, Supabase/PowerSync implementation,
production reads/mutations, migration, or cutover. It creates no Firebase
adapter and requires no new Firebase report/search implementation.
