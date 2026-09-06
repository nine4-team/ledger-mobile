# Capability Dossier — Invoicing, Collection, and Budget Authority

Status: reviewed static characterization; 21 of 44 target-relevant surfaces are
exactly target-mapped. Twenty-three decision-sensitive source/collection/
lifecycle/display/correction surfaces remain honestly withheld on their named
blockers; implementation remains unauthorized

## Outcome

An authorized Ledger user can see every project amount the Client has paid and
every amount still owed to or credited by 1584, assemble eligible Item,
Expense, Fee, and approved credit sources into one live Invoice, mark it sent,
and record whole-Invoice collection exactly once. Collection creates one
project Purchase for the actual Client-to-1584 payment, freezes the exact paid
contents and category allocations, and moves those allocations from unpaid to
paid budget segments without increasing total recognized project value.

The app and MCP use the same typed commands and locally query the same
authorization-safe projections. Neither client writes Invoice status, line
amounts, source membership, payment Transactions, or budget summaries directly.

## Boundary

This dossier owns:

- Item-charge/credit, Expense, Fee, and approved-adjustment eligibility for
  Invoicing;
- live Invoice source membership, revision, lifecycle, rendering inputs, and
  single-active-Invoice exclusivity;
- whole-Invoice collection, frozen membership/allocation, the one Purchase,
  and correction boundary;
- category-level paid/unpaid budget projection and project-list summary
  authority;
- financial visibility for Invoice, Fee, Expense, collection, and budget data;
- offline Invoice editor, Invoicing workspace, collection-operation, and budget
  read models; and
- migration/reconciliation of current Invoices, Fee installments, reimbursable
  Transactions, settlement Transactions, Invoice events, and budget summaries.

It does not own physical Item placement, occurrence DDL, Transaction receipt
capture, attachment-byte durability, Client identity, Transfer mechanics, or
general reporting/export presentation. It consumes those contracts from the
adjacent dossiers and canonical product specs. Vendor-document “Invoice Import”
is purchase-evidence intake, not Client Invoicing; it is included here only to
close that naming-related coverage gap and route it to the typed Purchase or
Expense flow.

## Source Surfaces

### Swift Invoice model, service, and UI

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-31DB4E9B5136` | `Invoice`, `InvoiceLine` | Firestore-shaped Invoice with optional embedded signed lines, flat Item/Transaction membership arrays, lifecycle timestamps, mutable totals, settlement IDs, and compatibility fields |
| `SWIFT-0B430AAF3B6E`, `SWIFT-8818DB7D6FFB` | `InvoiceService`, protocol | Client-side Firestore create/edit/send/paid/collect/cancel/payment-void composition; public contract receives storage-shaped entities and caller-materialized lines |
| `SWIFT-9A3A702CA92E` | `InvoiceLineCalculations` | Infers current Item/Transaction invoiceability and amount basis, source membership, payable balance, price locks, and returned-paid-Item manual credits from mutable records and lineage heuristics |
| `SWIFT-38F4A97A4FCB` | `CreateInvoiceModal` | Builds the current billable pool, creates/edits created Invoices, creates manual charges, and materializes Item/Transaction/Fee lines from locally cached state |
| `SWIFT-EA6B4B939093`, `SWIFT-E5E95679647A` | Invoice detail and Project Finances/Billing | Renders live Invoices, Fee groups and candidate receivables; invokes status changes, collection, payment correction, Fee creation, and navigation directly from context snapshots |
| `SWIFT-37B70FDD1318`, `SWIFT-C51DAED1C3CE` | billing summary calculation/card | Independently derives total spent, invoiced, collected and outstanding amounts, including compatibility fallback from paid Invoice status when settlement evidence is absent |

Created and sent totals are repeatedly reconstructed in the modal, Invoice row,
Invoice detail, billing summary, payable cards, and report aggregation. The
same business rule therefore has several implementations with different inputs
and fallbacks.

### Swift Fee, budget, state, access, and display

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-51D84FD65ADE`, `SWIFT-BAFED6656104`, `SWIFT-9CF3A4F84903` | Project budget/Fee models, services, protocols | Stores Fee installments under a Project, validates aggregate amount against a client-supplied Project fee total, and performs generic allocation/Fee Firestore writes |
| `SWIFT-14D0C2F1019A`, `SWIFT-C25AEA49443F`, `SWIFT-99CD48FC486A` | budget calculations/service/model | Sums normalized project Transactions by category into one `spentCents` value and applies current legacy Sale/Return/payment-to-business sign rules |
| `SWIFT-800DE43469FC`, `SWIFT-263BA57A580A`, `SWIFT-AB58F2F2752F`, `SWIFT-D6F4A0ED81EF`, `SWIFT-E4724837204F`, `SWIFT-F1FAE8106010`, `SWIFT-FD51852D673A` | budget views/components/formatters | Displays a single progress amount, remaining/over labels, category pins, project-list preview, and fee-specific “received” vocabulary |
| `SWIFT-1DA3D2CE9B31`, `SWIFT-C05952F542AD` | Project/Account contexts | Assemble Invoice, Item, Transaction, category, allocation, and Fee state through independent listeners and expose partially refreshed in-memory snapshots |
| `SWIFT-47AEA80908AD` | `FinancialAccessPolicy` | Filters already-downloaded Transactions, categories, and whole Invoices in memory, with fail-closed logic for some ambiguous Fee/manual lines |

The pure formatting and pinning interactions are useful. The single-segment
Transaction-only spend model, locally enforced Fee ceiling, independent listener
timing, and post-download financial filtering are not target authority.

### Vendor-document import

`SWIFT-D7E8B2EB55DF` plus the Invoice import calculation, Amazon/Wayfair parser,
draft-row, parse-summary, and debug surfaces parse a local vendor PDF and then
compose a Project Purchase plus Items through separate services. The parse/review
outcome is valuable, but the name “Invoice Import” obscures that this is vendor
purchase evidence. The target must ask/know who paid and route the reviewed
evidence to `RecordProjectPurchase`, `RecordInventoryPurchase`, or `CreateExpense`;
it must not always create a Project Purchase or assemble Item membership through
separate generic writes.

### MCP Invoice and budget paths

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `MCPMOD-7E2A27F3F12F` and Invoice tools | `tools/invoices.ts` | Admin-SDK billable pool, Invoice CRUD-like line edits, send/cancel, whole and selected-line collection, and contract setup with manual Fee-like charges |
| `MCPMOD-1710A9547AEB` | `util/budget.ts` | A second Transaction sign normalizer used by MCP budget reads |
| budget tools/resources | Projects, budget tools, resources | Recompute or expose Project budget values from current Transactions and allocations with no shared target projection contract |

MCP `validateLines` trusts caller-supplied amounts for Item and Transaction
sources, checks source/category state before rather than inside collection, and
does not atomically claim source membership. Its duplicate-settlement reads
also occur before the final batch, so concurrent requests can both pass.
`list_invoices` uses unordered offset pagination.

### Current rules, Functions, scripts, and tests

- `RULE-9B7212EBB760`, `RULE-0905373DBB19`, `RULE-AB3E61BAC3E3`, and
  `RULE-C4FE7FBE534A` give ordinary account members broad direct CRUD over
  Invoices, Fee installments, Project allocations, and category definitions.
  `RULE-B16FE8CF3DEA` lets any member append Invoice events. Admin MCP bypasses
  these rules.
- `FUNCTION-EBFFD3F950A0`, `FUNCTION-AADED40AD19C`,
  `FUNCTION-24C086150C5D`, and `FUNCTION-EE4FDF40EC7B` asynchronously recalculate
  Transaction completeness, Project `budgetSummary`, and current movement
  repricing/paid locks. The callable `FUNCTION-5612C1011897` can rebuild an
  arbitrary supplied account's budget summaries without verifying account
  membership/admin authority.
- Current billing/budget tests prove useful source behavior, but several encode
  superseded requirements: sent snapshotting, partial collection, one payment
  Transaction per category, `paymentToBusiness`, single-segment Transaction
  spend, and paid-status fallback without payment evidence.
- Billing-status stripping, Invoice-line/category backfills, Fee/Expense
  Transaction rewrites, budget-summary backfills, and record-specific repairs
  are source history. They are migration fixtures, not target runtime code.

## Current Observable Behavior and Defects

1. Current collection creates one `paymentToBusiness` Transaction per category.
   The target requires exactly one Project Purchase per whole Invoice.
2. Swift and MCP support selected-line collection. The target explicitly has no
   partial-payment or line-level collection model.
3. `InvoiceService.markCollected` accepts `amountCents` but never uses it. It
   calculates category totals from caller-provided lines, so the API suggests
   actual-payment evidence that is silently discarded.
4. Swift collection replaces the fetched Invoice lines with lines reconstructed
   from the caller's local caches, then passes those into a client-side batch.
   No authoritative read validates current source membership, revision, amount,
   eligibility, or prior collection at commit time.
5. MCP performs duplicate and source checks before a non-transactional batch.
   Two concurrent collection requests can pass the same reads and create
   duplicate payment records.
6. The app can collect a `created` Invoice without first marking it sent. Whether
   this is desirable is not represented as an explicit lifecycle rule.
7. Invoice creation exclusivity is computed from cached arrays. No database
   uniqueness rule prevents two clients from placing one source on different
   active Invoices.
8. Source-backed line amounts are duplicated in embedded Invoice lines. Created
   and sent screens sometimes rederive them while MCP and other readers may use
   stored values, creating amount and client-rendering drift.
9. Legacy lines missing an ID decode with a fresh random UUID on every decode.
   That cannot be stable settlement, migration, or correction identity.
10. Sending stores a snapshot, while target semantics keep source amounts live
    until collection. Current comments, tests, MCP descriptions, stored values,
    and readers disagree about whether send freezes value.
11. Payment correction cancels settlement Transactions and changes a paid
    Invoice back to sent. It does not clear line settlement IDs and is not yet a
    complete append-only target correction/reversal model.
12. Cancel operations are status patches. MCP can cancel any Invoice, including
    one with settlement evidence, without the app's paid-state gate.
13. A returned paid Item is represented as an automatically created Invoice
    containing a `manual` credit line. Deterministic line naming helps dedupe,
    but `manual` erases the typed Item occurrence/provenance relationship.
14. There is no dedicated current Expense entity. “Expenses” are inferred from
    non-itemized Transactions, category type, payer/reimbursement flags, and
    legacy taxonomy migrations. This conflates direct Client-paid money with a
    1584-paid open demand.
15. Fee-installment validation uses a locally supplied total and existing sum.
    Concurrent creates/updates can exceed the intended Fee total, while deletion
    can ignore active Invoice membership.
16. Current budget authority sums Transactions only. It counts
    `paymentToBusiness`, current Inventory movement pseudo-Transactions, and
    legacy Sale signs, while it cannot represent open Item, Expense, or Fee
    sources as the required unpaid segment.
17. The Project card can read a Function-maintained `budgetSummary` while the
    Project budget tab calculates live from Transactions. Existing documented
    production discrepancies prove these can drift.
18. Invoice, billing summary, payable balance, budget, MCP, analytics, and report
    surfaces each implement related arithmetic. Compatibility fallbacks can make
    a paid Invoice look collected even when no actual payment evidence exists.
19. Financial access is primarily enforced after broad rows have downloaded.
    Hidden Fee/Invoice amounts, counts, source names, and history may therefore
    exist on an unauthorized device even if a Swift view filters them.
20. Vendor-PDF import always creates a Project Purchase and Items, can omit a
    category, and commits the Transaction before the Item batch. A later Item
    failure can leave incomplete canonical money evidence; payer/scope is not
    established by the import flow.

## Product and Spec Reconciliation

| Authority | Assessment |
|---|---|
| `invoice-centered-project-accounting.md` | Canonical target authority for routing, live Invoice sources, whole-Invoice collection, immutable paid membership, Expenses and the two-segment no-double-count budget |
| `inventory-item-invoicing-lifecycle.md` | Canonical target authority for Item charge/credit eligibility, removal, paid returns, resale and occurrence provenance consumed by Invoicing |
| `proto-item-capture.md` | Canonical target authority for Business-paid Link creating open Item demand without a Project Transaction and Client-paid Link attaching actual Purchase evidence |
| `non-item-receipt-lines/design.md` | Canonical target direction for receipt reconstruction; unresolved billability, rounding and tax-basis policy remains blocked rather than inferred |
| D-007/D-009 | Direct Client-paid Project costs remain Purchase/Return money evidence; 1584-paid non-itemized costs become Expenses in Invoicing |
| D-008/D-013/D-014 | Project Item demand is a typed signed occurrence in Furnishings; user-facing Invoice source is the Item, not a movement Transaction |
| D-010/D-015 | Collection is whole-Invoice, atomic and idempotent; it creates one Purchase and preserves complete frozen membership/allocation |
| D-011 | `created` and `sent` are live; collection, not send, freezes final financial values |
| D-012/D-017 | Budget has paid and unpaid segments; collection changes segment ownership only, and Transfer reallocation does not create Client-wide value |
| D-016 | Expense/Purchase receipt completeness may include signed `NonItemReceiptLine` evidence without fabricating Items or Invoice lines |
| D-022 | An Invoice Item source references the one physical Item plus the exact accounting occurrence; it is not a cloned Item |
| O-003–O-010 | Credit settlement, negative display, Expense locks, occurrence authority, receipt-line treatment, manual adjustments, and zero-dollar lifecycle remain blockers where they alter commands/schema |
| O-029/O-033/O-034 | Transaction/payment correction, actual-payment variance, and sent-Invoice revision/delivery semantics must close before those paths are enabled |

## Behavior Decisions

| Classification | Decision |
|---|---|
| Preserve | Curated Invoice creation; `created/sent/paid/canceled` vocabulary; live-until-paid value; Fee installment intent; source search/filter; Invoice number/notes/PDF presentation; category allocations; pins; deterministic currency formatting; local vendor-PDF parse/review where reliable |
| Correct | Partial collection; category-grouped payment rows; unused payment amount; random decoded line IDs; caller-authored source amounts; preflight races; status patches; untyped manual returned-Item credit; Transaction-inferred Expenses; post-download financial filtering; divergent/cached budget arithmetic; optimistic multi-service import composition |
| Improve | Stable source/revision identities; one Invoice revision/event stream; exact rejection reasons; offline queued-operation state; explicit read-model readiness; deterministic cursors; authoritative Fee ceiling/membership checks; source-aware migration confidence; shared app/MCP contracts |
| Redesign | Separate live source links from frozen paid lines; add Expense and Fee source contracts; one authoritative `CollectInvoice`; derive one two-segment budget projection from canonical contributions; move security filtering into RLS/Sync Streams |
| Retire | `paymentToBusiness`; selected-line collection; public `markPaid`; generic line amount/category mutation; `containsCompanyRevenue` as security authority; client-written budget summaries; target Firebase triggers/rules/Admin-SDK composition; legacy Expense/Fee Transaction writes |
| Source only | Current Firebase app/services/rules/Functions, Invoice arrays, migration markers, repair scripts, cached summaries, and legacy settlement/type/billing fields after source freeze |
| Open | O-003–O-010, O-015, O-023, O-029–O-034, A-003/A-004/A-015/A-016, final production profile and migration classifications |

## Target Source and Invoice Contract

### Invoiceable sources

Every live Invoice source is a typed record with stable identity, Project,
signed amount, category allocation, revision, eligibility state, and provenance:

| User section | Canonical source | Live amount authority |
|---|---|---|
| Items | exact Item charge/credit occurrence referencing one physical Item | occurrence price basis/sign/category; current eligible Item presentation joins by ID |
| Expenses | Expense paid by 1584 for the Project | Expense final amount/category and approved receipt-line treatment |
| Fees | Fee or Fee installment | Fee source amount/category and explicit Fee-plan rules |
| Credits | typed Item/Client credit source once approved | credit occurrence/settlement state, never a synthetic Transaction |
| Adjustments | only an O-009-approved typed adjustment | its own category, reason, actor, audit and edit rules |

A direct Client-paid Project Purchase is not an Invoice source because the
Client already paid. A collection Purchase is not a new Invoice source. An
Invoice line never accepts a financial amount for a sourced row from the app or
MCP.

### Live membership and frozen lines

- A live source link records Invoice ID, source type/ID, expected source
  revision, client-facing description/order, and membership audit evidence.
- A source may belong to at most one non-canceled, uncollected Invoice. The
  authoritative database enforces this under concurrency.
- Created and sent totals resolve from current eligible source revisions.
  Invoice-local presentation may change independently, but cannot change money.
- Every source edit that affects a live Invoice increments the source and
  Invoice-visible revision and writes auditable provenance.
- Collection creates immutable paid lines containing source/occurrence ID,
  Item/Expense/Fee identity, final sign/amount/category/currency, descriptions,
  source revision, and collection membership.
- Paid lines and their Purchase link never change. Later credits, refunds, or
  corrections append new evidence.
- Missing legacy IDs receive deterministic migration IDs. Runtime decode never
  invents identity.

### Lifecycle commands

| Command | Required effect |
|---|---|
| `CreateInvoice` | Create one Project Invoice and exact source links after eligibility/exclusivity validation; no Transaction |
| `ReviseCreatedInvoice` | Replace the reviewed source set/presentation against expected Invoice/source revisions; preserve audit; O-010 handles final-line behavior |
| `MarkInvoiceSent` | Record sent state, revision and delivery evidence; does not freeze source money |
| `ReviseSentInvoice` | Placeholder gated by O-034; no silent membership rewrite after client delivery |
| `CancelInvoice` | Cancel only a non-paid Invoice under expected revision, release live source links, and preserve event/history |
| `CollectInvoice` | Atomically freeze the whole current Invoice, create exactly one Project Purchase, move every source allocation to paid state, mark Invoice paid, and store the operation result |
| `CorrectInvoiceCollection` | Placeholder only; append-only correction/reversal behavior remains gated by O-029 and the paid-history rules |

There is no target `MarkInvoicePaid`, `MarkInvoiceLinesCollected`, generic
`AddInvoiceLine(amount:)`, arbitrary status update, or line-level collection.

### Expense and Fee commands

Candidate operation families are:

- `CreateExpense`, `UpdateOpenExpense`, and `CancelOpenExpense`;
- `CreateFee`, `UpdateOpenFee`, and `CancelOpenFee`; and
- explicit Fee-plan/installment operations if installment planning remains the
  approved user model.

The handler derives Invoice impact and budget projections. It rejects edits or
deletes that conflict with active membership/collection. O-006 owns the exact
Expense field-by-state matrix. Fee aggregate/ceiling rules must be checked in
the authoritative transaction, not against a caller-supplied cached sum.

## Whole-Invoice Collection Contract

`CollectInvoice` carries one operation ID, Invoice ID, expected Invoice
revision/source-set hash, actual payment amount and currency, effective payment
date, optional payment-instrument/evidence references, actor, and contract/
accounting-authority versions.

Inside one authoritative database transaction the handler:

1. claims the operation ID and rejects payload reuse with a different hash;
2. resolves the signed principal and financial capability;
3. locks the Invoice, live source links, sources, Project authority, and any
   existing collection row in deterministic order;
4. requires `created` or `sent`, uncollected, non-canceled status and the exact
   expected source set/revisions;
5. resolves every final signed amount/category from canonical sources and
   rejects missing, duplicate, ineligible, stale, zero/unsupported, or
   unauthorized contents;
6. applies the initial-release amount rule. Until O-033 closes, a payment whose
   amount differs from the positive Invoice total is rejected rather than
   silently modeled as partial payment, overpayment, discount, or fee;
7. writes the immutable paid Invoice snapshot and collected allocations;
8. creates one Project `Purchase` for actual Client-to-1584 money, marked as an
   Invoice-collection Purchase and linked to the Invoice;
9. marks every included source occurrence/Expense/Fee/adjustment collected and
   removes it from active Invoicing without deleting source history;
10. records the Invoice lifecycle event, operation result, actor and server
    timestamps; and
11. commits all effects or none.

An identical retry returns the prior Purchase/Invoice result. A stale retry
whose Invoice was collected by a different operation returns an authoritative
already-collected conflict; it never creates a second Purchase.

## Budget Authority

For each Project/category/currency, the canonical projection exposes at least:

```text
paid(c) =
    signed qualifying direct Client-paid Purchase/Return allocation
  + signed frozen allocations from collected Invoices
  + approved signed Transfer reallocation

unpaid(c) =
    signed active Item occurrences
  + signed active Expenses
  + signed active Fees
  + signed approved credits/adjustments

recognized(c) = paid(c) + unpaid(c)
```

Rules:

- An Invoice link has no additional budget contribution; its source already
  contributes to unpaid.
- An Invoice-collection Purchase face amount has no additional budget
  contribution; frozen collected allocations contribute to paid.
- Collection closes each open contribution and opens its equal frozen paid
  allocation in the same commit. `recognized(c)` is identical immediately
  before and after collection.
- A direct Client-paid Transaction contributes once by its own category/lines.
- Item charge/credit activity always contributes to Furnishings. Additional
  Requests is a filtered overlay and never another contribution.
- A contribution has one stable identity and exactly one active segment. This
  identity, rather than a screen-specific sum, is the double-count guard.
- Unknown/unmapped legacy categories are surfaced as reconciliation failures or
  an explicit migration holding category; they are never silently omitted.
- Category allocation configuration preserves absent, enabled-without-budget,
  and explicit-zero states.

`ProjectBudgetSnapshot` is the only app/MCP budget read contract. It contains
per-category paid, unpaid, recognized, budget, remaining/over, source counts,
projection revision/readiness, and presentation metadata. Project cards, the
Budget tab, Invoicing, reports, search, and exports consume the same resolver or
projection. A stored Postgres projection is permitted for performance only if
it is rebuildable, revisioned, never client-written, and continuously compared
with canonical contribution rows.

The provider-free Phase 1 `ProjectBudgetSegmentSnapshot` is deliberately only
a leaf foundation for that complete contract. It may establish exact
Account/Project/currency query identity, category identity/order, signed paid
and unpaid values, derived recognized arithmetic, explicit local plus
accounting-authority versions, readiness/restart and bounded refusal. It does
not resolve contribution sources, calculate budget/remaining/over/source
counts, choose presentation, or create a competing app/MCP budget authority.

## Offline and Sync Contract

The Project workspace Sync Stream must include all authorized rows needed to
render without a round trip:

- Invoice summaries, live source links and current source revisions;
- eligible Item occurrences, Expenses, Fees and approved credits/adjustments;
- paid Invoice snapshots and collection-Purchase references required by detail;
- category definitions/Project allocations and the canonical budget projection
  or sufficient contribution rows;
- Invoice lifecycle and source-revision summaries needed for audit/readiness;
  and
- queued/applied/rejected operation results.

Financial permission is applied before download. A mixed Invoice containing any
restricted Fee source is either wholly visible under the approved capability or
wholly absent; partial line filtering must not expose an inconsistent total.
Counts, search tokens, names, and projection rows follow the same rule.

Create/revise/send/cancel/collect commands may be accepted into the durable
local operation queue offline. Local acceptance is never displayed as remote
commit. Until A-015 passes the spike, complex collection does not mutate
canonical local paid/source rows optimistically; the UI shows a separate
“collection queued” overlay and retains authoritative source state. A server
rejection remains visible with a stable remedy. Confirmed local budget state
and optional pending deltas are labeled separately.

Readiness states distinguish complete local workspace, partial history,
permission-filtered data, pending operations, and projection rebuild. The UI
must not label a partial projection as the complete budget.

## Security and Authorization

- RLS and Sync Streams use immutable account scope, active membership, Project
  access, and financial capability. Swift filtering is defense-in-depth only.
- Creating/revising/sending/canceling an Invoice, mutating Fees/Expenses, and
  collecting require explicit financial capabilities; O-026 controls shared
  category mutation separately.
- Source eligibility, category access, Invoice visibility, and collection
  authority are rechecked inside every handler.
- The app never receives a service-role key. MCP may authenticate through a
  server identity but invokes the same typed handlers and records both human
  actor and acting service.
- Safe parent views cannot leak restricted child existence through totals,
  counts, timestamps, search, or operation results.
- Paid snapshots, collection links, events, and correction evidence are
  append-only and not directly updateable through the Data API.

## Migration Mapping and Reconciliation

1. Preserve every raw Firebase Invoice, line, membership array, Fee installment,
   candidate Expense Transaction, settlement Transaction, Invoice event,
   category/allocation, and relevant source revision in immutable export
   evidence before transformation.
2. Preserve stored Invoice/line IDs. Generate missing line IDs deterministically
   from source Invoice ID, normalized source kind/ID, original ordinal, and
   migration version. Duplicate source identities are quarantined rather than
   randomly deduplicated.
3. Map `draft` to `created`, `voided` to `canceled`, and retain all original
   lifecycle values/timestamps in correlation evidence. Unknown transitions are
   blockers.
4. For uncollected Invoices, build live source links only when the exact source
   exists, belongs to the Project, is invoiceable under the target mapping, and
   is not claimed elsewhere. Preserve stored totals as comparison evidence, not
   live authority.
5. For paid Invoices, prefer stored historical line values and proven settlement
   links. A missing-line backfill that used mutable current source values is
   marked reconstructed with confidence/provenance; it is not presented as
   original client-facing fact.
6. Never invent one target Purchase merely because legacy `Invoice.status ==
   paid`. Correlate active legacy settlement rows and external evidence. Multiple
   category-grouped rows may consolidate only when evidence proves one actual
   payment event and amount; otherwise preserve them as legacy collection
   evidence and block canonical conversion for review.
7. Any selected-line/partial settlement is incompatible with the initial target
   lifecycle. Preserve the exact paid/unpaid line evidence and quarantine it for
   an approved repair, rather than pretending the whole Invoice was collected.
8. Map eligible `FeeInstallment` rows to typed Fee sources with source IDs and
   active Invoice membership. Do not trust the current cached aggregate ceiling
   without recomputation.
9. Classify legacy Expense/Fee/non-itemized Purchase Transactions using payer,
   reimbursement direction, category, attachments, Invoice membership, and
   actual money evidence. Ambiguous rows remain explicit migration-review items;
   a Transaction is not silently converted into an Expense solely from its
   legacy type/category.
10. Map Item lines only after the occurrence/provenance importer identifies the
    exact charge/credit occurrence and amount basis. `itemId` alone is
    insufficient across return/resale cycles.
11. Manual lines remain blocked on O-009. Returned-paid-Item manual credits map
    to typed credit occurrence evidence when provenance is exact; other manual
    lines retain raw evidence and require an approved type/category mapping.
12. Do not migrate `budgetSummary` or any current screen total as authority.
    Rebuild the target projection, then compare source/current and corrected
    target results through named semantic-difference rules.
13. Treat the local Amazon/Wayfair parser output as draft evidence. The target
    import command chooses Project Purchase, Inventory Purchase, or Expense from
    reviewed payer/scope and commits parent, Items/receipt lines, attachment
    metadata, and operation result atomically.

Required reconciliation includes:

- every source Invoice and line mapped, quarantined, or explicitly retired;
- no source linked to two active target Invoices;
- exact paid Invoice/Purchase cardinality for canonical converted records;
- exact source-set, sign, amount, category, currency, and total agreement for
  every collected Invoice;
- paid plus unpaid equals recognized by Project/category before and after every
  converted collection;
- no collection-Purchase face amount counted as an additional contribution;
- Fee plan/installment totals and Invoice membership agree;
- Expense candidates reconcile to actual payer evidence;
- no unexplained unknown category, restricted-data leak, orphan source,
  duplicate contribution, or random identity; and
- rebuilt Project-card, Budget-tab, MCP, report, and export projections agree.

## Verification Contract

### Domain and handler tests

- one source cannot join two active Invoices under concurrent create/revise;
- sourced amounts/categories cannot be supplied or changed by app/MCP payloads;
- created/sent source edits update one Invoice revision and unpaid projection;
- send never freezes money; collection freezes exact current values;
- whole collection creates one Purchase and complete frozen membership;
- selected-line, zero/negative, stale-source, mismatched-total, unauthorized,
  already-collected, and missing-source collection rejects atomically;
- same operation retry returns the same Purchase; changed-payload reuse rejects;
- lost response/retry and two-device collection produce one financial effect;
- collection moves every category amount unpaid-to-paid with zero recognized
  delta and no Purchase-face double count;
- Item return/credit/resale and Expense/Fee edits respect open/live/paid locks;
- Fee aggregate and active-Invoice membership remain valid under concurrent
  create/update/delete; and
- correction cannot rewrite paid Invoice lines or detach historical membership.

### Offline, projection, and UI tests

- cached project workspace renders Invoice editor, Fees/Expenses/Items and both
  budget segments in airplane mode;
- offline create/revise/send/collect survives restart and account-safe queue
  lifecycle, with queued versus applied state visible;
- a stale offline collection rejects without showing authoritative paid state;
- Project card, Budget tab, Invoicing, MCP, report, and export fixtures resolve
  identical contribution IDs/totals;
- projection rebuild/interruption cannot expose a plausible but incomplete
  budget as ready;
- negative credits follow O-005 once approved; and
- sent-Invoice revision/resend UI follows O-034 once approved.

### Security and migration tests

- role/capability matrix covers full, limited, none, revoked, mixed-Invoice,
  cross-account, direct Data API, RPC, MCP and Sync Stream access;
- unauthorized devices receive no restricted rows, counts, totals, search
  tokens, events, operations, or object paths;
- legacy missing/random line IDs map deterministically across reruns;
- paid-without-settlement, grouped settlement, partial settlement, conflicting
  membership, missing category/source, reconstructed line, manual line, and
  stale budget-summary fixtures all fail closed or produce reviewed mappings;
- repeated reset/import yields identical IDs, classifications, projections and
  reconciliation artifacts; and
- no Firebase app adapter, Firestore redesign writer, Function, rule, or index
  is required for target behavior.

## Completeness and Remaining Gates

This static pass follows the Invoice/line/source paths through Swift model,
service, contexts, UI, access policy and tests; MCP tools/resources; current
rules/Functions; budget readers/projections; vendor-document import; and
migration/repair utilities. It also names downstream report/rendering consumers
that will receive their own reporting dossier rather than silently treating
their current arithmetic as authoritative.

The dossier is not target DDL or migration authorization. Before target mapping
becomes implementation-ready it still requires:

- O-003–O-010 and O-015 where referenced;
- O-029 for financial correction/void policy;
- O-033 for actual payment versus Invoice-total variance;
- O-034 for sent-Invoice membership revision/delivery semantics;
- A-003/A-004 vertical-spike proof and A-015 optimistic-operation decision;
- A-016/offline authorization approval;
- canonical production shape/profile evidence; and
- a reviewed occurrence/Expense/Fee schema and migration mapping.

Product specs and the decision log remain product authority. This dossier
defines implementation contracts and rejects known source defects; it does not
silently resolve open product choices.
