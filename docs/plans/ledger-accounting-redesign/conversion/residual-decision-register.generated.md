# M2 Residual Decision Register

Status: generated; do not edit manually. Regenerate with `npm run conversion:residuals:generate`.

This register is the deterministic queue for target-relevant surfaces that cannot yet be mapped without a product/architecture decision or required evidence. Product specs and the decision log remain authority; this file never resolves a decision.

## Summary

- Target-relevant surfaces: 757
- Target-mapped or later: 567
- Residual surfaces: 190
- Distinct blockers: 47

A surface may depend on more than one blocker, so blocker counts do not sum to the residual-surface count.

## Priority Queue

| Priority | Blocker | Surfaces | Kind | Owning context | Required closure |
|---:|---|---:|---|---|---|
| 1 | `O-015` | 46 | product decision | Item accounting model | Approved relational model, constraints, query plan, and migration fixture results |
| 2 | `O-007` | 31 | product decision | Item provenance | Approved authority model, migration mapping, and offline history query tests |
| 3 | `O-026` | 25 | product decision | Shared reference-data authorization | Approved role/capability matrix plus standard-member, admin, cross-account and system-category negative tests |
| 4 | `O-032` | 23 | product decision | Transaction capture/import | Approved posted-versus-draft contract plus offline restart, budget exclusion, completion, import quarantine and concurrency tests |
| 5 | `O-023` | 22 | product decision | Attachments and retention | Approved detach/delete product behavior plus shared-reference, paid-evidence, retry, retention, and restoration tests |
| 6 | `O-005` | 20 | product decision | Budget presentation | Approved arithmetic/visual specification and signed-value snapshot tests |
| 7 | `O-029` | 20 | product decision | Transaction lifecycle | Approved state/dependency policy plus stale-plan, paid/Invoice/Item/lineage/media, retry, human-confirmation and immutable-evidence tests |
| 8 | `O-040` | 17 | product decision | Personal Project budget pinning | Approved feature, target, missing/empty/no-pin/default/card and lifecycle policy plus no-render-write, cross-user, offline conflict/recovery and migration tests |
| 9 | `O-031` | 16 | product decision | Item price/tax basis | Approved tax-inclusive or explicit per-Item allocation rule with mixed-tax, migration and no-silent-inheritance tests |
| 10 | `O-009` | 15 | product decision | Invoice sources | Decision to retire adjustments or define typed category, provenance, edit, and audit rules |
| 11 | `O-034` | 15 | product decision | Sent Invoice revision/delivery | Approved sent-mutation policy plus live-value, membership, resend, offline conflict, collection-race and historical-render tests |
| 12 | `O-003` | 13 | product decision | Credit Settlement | Approved settlement routes and proof that only actual cash refund creates Return |
| 13 | `O-004` | 13 | product decision | Credit Settlement / Invoice lifecycle | Explicit terminal states, accounting effects, and collection rejection tests |
| 14 | `O-010` | 13 | product decision | Invoice lifecycle | Approved cancel/noncollectible behavior and last-line concurrency tests |
| 15 | `O-008` | 11 | product decision | Receipt Lines and Invoicing | Per-line treatment model and exact-cent collection/report tests |
| 16 | `O-030` | 11 | product decision | Receipt completeness | Approved explicit-rounding-line or visible-tolerance behavior with exact-cent fixtures and no inferred tax/discount |
| 17 | `O-027` | 10 | product decision | Item Creation | One approved name/photo/note rule plus offline, API, and migration validation tests |
| 18 | `O-033` | 10 | product decision | Collection/payment variance | Approved exact-match or explicit variance model plus mismatch, retry, rounding, allocation, receipt, budget and correction tests |
| 19 | `O-006` | 9 | product decision | Expense / live Invoice | Field-by-state mutability matrix with concurrent edit/collection tests |
| 20 | `O-037` | 9 | product decision | Space archive and Item assignment | Approved retain/clear/move rule plus assigned/empty, offline, search/report, concurrent assignment and scope-change tests |
| 21 | `O-035` | 8 | product decision | Client Summary financial meaning | Approved paid/open/recognized presentation plus no-double-count, credit, Transfer, open-source, collection and label tests |
| 22 | `O-039` | 8 | product decision | Project-note text validation | Approved cross-runtime trim/control/nonempty/byte rule plus app/MCP parity, zero-dispatch rejection, restart and lossless import/quarantine tests |
| 23 | `A-015` | 7 | architecture decision | Architecture and target spike | blocked: Choose the optimistic projection mechanism for complex offline commands |
| 24 | `O-036` | 7 | product decision | Client-shared receipt evidence | Approved omit/embed/attach/authorized-link policy plus token/path leakage, revocation, expiry, offline, sharing and retention tests |
| 25 | `O-011` | 6 | product decision | Transfer / Item tags | Approved carry/clear/reselect rule and source/destination projection tests |
| 26 | `O-012` | 6 | product decision | Transfer / Space placement | Approved default/optional selection behavior and atomic destination-scope tests |
| 27 | `O-013` | 6 | product decision | Transfer correction | Approved reversal rules; retry/concurrency and immutable-original tests |
| 28 | `O-014` | 6 | product decision | Credit after Transfer | Approved hosting rule and multi-transfer credit/budget tests |
| 29 | `A-016` | 5 | architecture decision | Architecture and target spike | blocked: Approve the bounded offline-access lease |
| 30 | `Canonical production reference/object profile` | 5 | production evidence | Attachment source profiling and migration | Approve and hash the production Firestore-reference/Storage-object graph, including shared, dangling, missing and retained evidence variants. |
| 31 | `O-024` | 5 | product decision | Project lifecycle | Approved archive/delete policy plus empty, child-bearing, financial-history, offline-retry and concurrent-child tests |
| 32 | `O-025` | 5 | product decision | Client/Project correction | Approved mutability boundaries plus cross-Client, prior-Transfer, paid-history, retry and concurrent-change tests |
| 33 | `O-038` | 5 | product decision | Inventory destination planning | Approved retention/granularity/lifecycle and source migration, plus D-013 category isolation, offline, race, security and no-accounting-effect tests |
| 34 | `A-007` | 4 | architecture decision | Architecture and target spike | proposed: Choose Supabase Auth at launch or a temporary Firebase Auth integration |
| 35 | `O-002` | 4 | product decision | Transfer and live Invoice membership | Approved recall/removal rule plus concurrency and audit tests |
| 36 | `O-018` | 3 | product decision | Proto migration and Compatibility | Mapping policy, unresolved queue, source-freeze gate, rollback, and no-loss tests |
| 37 | `O-019` | 3 | product decision | Item reconciliation | Deterministic identity winner, relationship/media merge, audit, and retry tests |
| 38 | `Canonical production profile` | 2 | production evidence | Source data profiling and migration | Approve and hash a canonical immutable production export/profile that proves extant paths, shapes, variants, orphans and counts. |
| 39 | `O-016` | 2 | product decision | Inventory acquisition evidence | Approved state and later-resolution command without fabricated Purchase |
| 40 | `O-020` | 2 | product decision | Compatibility | Target accounting-contract/budget evidence, migration reconciliation, and O-022 source cutoff |
| 41 | `O-022` | 2 | product decision | Compatibility and Cutover | Approved quiescence, source-freeze, and recovery plan; proof late Firebase writes cannot bypass or be lost after final delta |
| 42 | `O-028` | 2 | product decision | Vendor cancellation/non-cash credit | Approved representation that adds no fourth Transaction, conserves every credit cent, and creates Return only for actual money received |
| 43 | `O-041` | 2 | product decision | Vendor-spend report semantics | Approved report meaning plus exact-cent, payer, scope, currency, credit, correction, security, offline-readiness, migration and app/MCP parity tests |
| 44 | `A-003` | 1 | architecture decision | Architecture and target spike | proposed: Supabase Postgres becomes target server authority |
| 45 | `A-004` | 1 | architecture decision | Architecture and target spike | proposed: PowerSync SQLite becomes the target local data plane |
| 46 | `O-017` | 1 | product decision | Item Creation UI/domain boundary | Decision that hint is omitted or explicitly non-authoritative; Link remains authority |
| 47 | `Physical target verification` | 1 | target verification | Offline target spike and physical-device acceptance | Run the isolated Supabase/PowerSync target on physical devices and prove restart, offline lease, queue, readiness and reconnect behavior. |

## Exact Affected Surfaces

### O-015 — 46 surfaces

- Kind: product decision
- Owning context: Item accounting model
- Required closure: Approved relational model, constraints, query plan, and migration fixture results
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-1BC6BB701AA3` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Pure helper selects purchase versus project price as the current transaction completeness audit basis from legacy type/source/project fields.
- `FUNCMOD-78D697A89342` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Pure helpers identify project Inventory Purchases, compute project-price/tax contributions and deltas, detect paid Invoice membership, and adjust multi-Item transaction totals/audit fields.
- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `FUNCTION-0CBF780A52CC` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On returned/sold lineage-edge creation, recomputes the source transaction isComplete/audit fields and suppresses failures after logging.
- `FUNCTION-8741B9D80FCC` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: When Item.transactionId changes, creates an event-id-derived association edge and, if the destination is a Return transaction, an additional returned-intent edge.
- `FUNCTION-EBFFD3F950A0` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On any Transaction create/update/delete, recalculates budget summaries for old/new Projects and computes isComplete/audit except for loop-guarded Function-only updates.
- `FUNCTION-EE4FDF40EC7B` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On Item cost/project-price/tax changes, adjusts an eligible unpaid project Inventory Purchase once using transactionRepricingEvents, preserves paid Invoice amounts, and recomputes completeness for linked and historical source transactions.
- `RULE-6852D375E671` — `M0-BACKEND-RULES-001` — redesign/characterized: Transactions have member read/create; deletion requires empty itemIds; selected inventory-movement accounting fields are immutable while itemIds and non-accounting fields may change; Functions maintain audits and summaries.
- `RULE-D3CFB25D03AD` — `M0-BACKEND-RULES-001` — redesign/characterized: Core Item records are member-readable/deletable; create/update enforces nonnegative optional prices and project price at least nonzero purchase cost.
- `RULE-FC994C6C2FEA` — `M0-BACKEND-RULES-001` — redesign/characterized: Lineage edges are account-member readable/creatable and immutable after create; Functions and direct app/MCP batches both produce association and movement evidence.
- `MCPMOD-4305DCB6FD6B` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Infers Inventory labels, movement directions and price/audit basis from current Transaction shape and source strings.
- `MCPMOD-DFECB1787DB7` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Plans and atomically corrects one ordinary Transaction with exact two-sided active Item membership, dependency blockers and per-Item correction lineage.
- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPTOOL-044AFFA1EEFB` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Either attaches Items to an existing vendor Return or moves proven Inventory-origin Items back to Inventory while creating per-batch project Returns and credits.
- `MCPTOOL-137430AF9A3B` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Moves Inventory Items into a Project and creates one Project Purchase from Inventory at project-price basis.
- `MCPTOOL-1E36059850BA` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Moves Project Items to another Project via an origin-aware Inventory two-hop with source Return/Sale and destination Purchase.
- `MCPTOOL-2182ACB9E363` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Applies generic Transaction field patches and can cascade scope/category changes or clear Item membership with correction lineage.
- `MCPTOOL-3517FF5089A3` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Acquires project-origin Items into Inventory using a project Sale Transaction at purchase-cost basis.
- `MCPTOOL-6E3CE3C31743` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Corrects a current Inventory Purchase and Items into a Project reimbursement shape when no sold lineage exists.
- `MCPTOOL-9D1270611686` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Dry-runs and transactionally corrects one ordinary current Transaction and its exact active Item aggregate, blocking movement, Invoice, provenance and inconsistent-membership cases.
- `MCPTOOL-BE6AD578A5CD` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Returns proven project-origin Inventory Items to their exact source and creates Project Purchases from immutable entry snapshots.
- `SWIFT-01C928A8B707` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Represents a Firestore Transaction with legacy/current types, overloaded active itemIds, routing flags, receipt subtotal/tax/discount, ingestion, completeness audit and settlement links.
- `SWIFT-089405BED5D8` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Creates loose optional LineageEdges directly and fetches on-demand Item/Transaction history while silently dropping decode failures and sorting optional timestamps client-side.
- `SWIFT-1DCA8A4ADE51` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Composes Inventory/Project/vendor movement as Firestore Transaction, Item, lineage and paid-credit writes, with origin-aware price logic and fixed batch limits.
- `SWIFT-4C47C0D715F5` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Infers incomplete physical returns from Item status, current Transaction type and missing returned lineage.
- `SWIFT-4C8A8E236450` — `M0-INVENTORY-TRANSACTION-001` — replace/characterized: Displays current Inventory Items and invokes current sell/return/reassign actions over Firebase context arrays.
- `SWIFT-7792F727AA52` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Resolves bulk Project movement routes and current origin-dependent return/sale groupings for UI previews.
- `SWIFT-967F1C133CF5` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Routes Inventory Items either back to proven source Project or as a sale to a selected Project using current movement Transactions.
- `SWIFT-BDF8928A5FC7` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Combines Transaction detail, active and lineage-reconstructed Items, proto review, receipt media, completeness, generic association, movement, correction and deletion in one Firebase-driven view.
- `SWIFT-CD04095425B1` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Adds existing Items through generic same-scope association, cross-scope reassignment, return-to-Transaction or sell-to-Project operations and often dismisses before asynchronous outcome.
- `SWIFT-E29B4124133A` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Splits Project Items by inferred origin into current Return-to-Inventory or Sale-to-Inventory operations and previews current budget effects.
- `TEST-7335FA7381B4` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Tests negative inference for current incomplete returned Item processing.
- `MCPTOOL-2B21D2622825` — `M0-INVOICING-BUDGET-001` — replace/characterized: Builds a billable pool from mutable Items, Transactions, Fees, and current Invoice arrays.
- `SWIFT-38F4A97A4FCB` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Builds cached billable candidates, manual lines, and created-Invoice edits in one modal.
- `SWIFT-9A3A702CA92E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Infers invoiceable sources, signed amounts, price locks, membership, and manual credits from mutable app records.
- `MCPMOD-82DC4C25B1B8` — `M0-ITEM-CREATION-LINK-001` — replace/characterized: Registers Admin-SDK Item list/search/get/create/update/bulk/delete and media tools with Firestore-specific invariants. Project create requires transactionId, unlike Swift.
- `MCPTOOL-69F70F0D82F2` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Updates Item fields and can also change scope/category/Transaction membership while maintaining Firestore arrays and correction lineage.
- `SWIFT-0B434663295C` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Shows real Items and a separate Needs Assignment proto section, then composes convert/merge/delete, generic transaction association and bulk Item actions.
- `SWIFT-236679C7D427` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Defines Item detail display-state helpers and an action list that always includes delete and generic set/clear Transaction.
- `SWIFT-2B5DD377E0BB` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Represents a Firestore-shaped physical Item with placement, one overloaded transactionId, category, prices, quantity, media, source/currentSource and inventory-entry snapshot fields.
- `SWIFT-63EEC4FFD5ED` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Implements transaction-first inventory Item entry followed by optional sale of all/selected Items to a Project.
- `SWIFT-AB578AEF4330` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Builds live Item detail from Firebase Item/Transaction/Space/category data and exposes detail, media, movement, generic association, correction and delete actions.
- `SWIFT-C593225376EB` — `M0-ITEM-CREATION-LINK-001` — replace/characterized: Provides Firestore Item CRUD/listeners, price/category normalization, generic transaction association, bulk metadata writes, annotation cleanup and hard delete. Linked create may return generated Items before its asynchronous batch commit completes.
- `TEST-8B555E151D8D` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Tests Item detail route/display/price/action calculations including generic association and always-visible delete.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-007 — 31 surfaces

- Kind: product decision
- Owning context: Item provenance
- Required closure: Approved authority model, migration mapping, and offline history query tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-78D697A89342` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Pure helpers identify project Inventory Purchases, compute project-price/tax contributions and deltas, detect paid Invoice membership, and adjust multi-Item transaction totals/audit fields.
- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `FUNCTION-0CBF780A52CC` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On returned/sold lineage-edge creation, recomputes the source transaction isComplete/audit fields and suppresses failures after logging.
- `FUNCTION-8741B9D80FCC` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: When Item.transactionId changes, creates an event-id-derived association edge and, if the destination is a Return transaction, an additional returned-intent edge.
- `FUNCTION-EE4FDF40EC7B` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On Item cost/project-price/tax changes, adjusts an eligible unpaid project Inventory Purchase once using transactionRepricingEvents, preserves paid Invoice amounts, and recomputes completeness for linked and historical source transactions.
- `RULE-D3CFB25D03AD` — `M0-BACKEND-RULES-001` — redesign/characterized: Core Item records are member-readable/deletable; create/update enforces nonnegative optional prices and project price at least nonzero purchase cost.
- `RULE-FC994C6C2FEA` — `M0-BACKEND-RULES-001` — redesign/characterized: Lineage edges are account-member readable/creatable and immutable after create; Functions and direct app/MCP batches both produce association and movement evidence.
- `MCPMOD-4305DCB6FD6B` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Infers Inventory labels, movement directions and price/audit basis from current Transaction shape and source strings.
- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPTOOL-044AFFA1EEFB` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Either attaches Items to an existing vendor Return or moves proven Inventory-origin Items back to Inventory while creating per-batch project Returns and credits.
- `MCPTOOL-137430AF9A3B` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Moves Inventory Items into a Project and creates one Project Purchase from Inventory at project-price basis.
- `MCPTOOL-BE6AD578A5CD` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Returns proven project-origin Inventory Items to their exact source and creates Project Purchases from immutable entry snapshots.
- `SWIFT-089405BED5D8` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Creates loose optional LineageEdges directly and fetches on-demand Item/Transaction history while silently dropping decode failures and sorting optional timestamps client-side.
- `SWIFT-1DCA8A4ADE51` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Composes Inventory/Project/vendor movement as Firestore Transaction, Item, lineage and paid-credit writes, with origin-aware price logic and fixed batch limits.
- `SWIFT-4C47C0D715F5` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Infers incomplete physical returns from Item status, current Transaction type and missing returned lineage.
- `SWIFT-4C8A8E236450` — `M0-INVENTORY-TRANSACTION-001` — replace/characterized: Displays current Inventory Items and invokes current sell/return/reassign actions over Firebase context arrays.
- `SWIFT-967F1C133CF5` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Routes Inventory Items either back to proven source Project or as a sale to a selected Project using current movement Transactions.
- `SWIFT-BDF8928A5FC7` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Combines Transaction detail, active and lineage-reconstructed Items, proto review, receipt media, completeness, generic association, movement, correction and deletion in one Firebase-driven view.
- `SWIFT-CD04095425B1` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Adds existing Items through generic same-scope association, cross-scope reassignment, return-to-Transaction or sell-to-Project operations and often dismisses before asynchronous outcome.
- `SWIFT-E29B4124133A` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Splits Project Items by inferred origin into current Return-to-Inventory or Sale-to-Inventory operations and previews current budget effects.
- `TEST-7335FA7381B4` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Tests negative inference for current incomplete returned Item processing.
- `MCPMOD-7E2A27F3F12F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Implements Admin-SDK Invoice composition, mutable lines, partial/whole collection, cancel/void, and contract setup.
- `MCPTOOL-2B21D2622825` — `M0-INVOICING-BUDGET-001` — replace/characterized: Builds a billable pool from mutable Items, Transactions, Fees, and current Invoice arrays.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-38F4A97A4FCB` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Builds cached billable candidates, manual lines, and created-Invoice edits in one modal.
- `SWIFT-9A3A702CA92E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Infers invoiceable sources, signed amounts, price locks, membership, and manual credits from mutable app records.
- `SWIFT-E5E95679647A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Combines Invoicing, Invoices, inferred Expenses, Fees, collection actions, and billing totals from independent local caches.
- `SWIFT-0B434663295C` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Shows real Items and a separate Needs Assignment proto section, then composes convert/merge/delete, generic transaction association and bulk Item actions.
- `SWIFT-2B5DD377E0BB` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Represents a Firestore-shaped physical Item with placement, one overloaded transactionId, category, prices, quantity, media, source/currentSource and inventory-entry snapshot fields.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-026 — 25 surfaces

- Kind: product decision
- Owning context: Shared reference-data authorization
- Required closure: Approved role/capability matrix plus standard-member, admin, cross-account and system-category negative tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `FUNCTION-24C086150C5D` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On relevant account budget-category changes, recomputes completeness for category Transactions and budget summaries for every Project in small concurrent batches.
- `RULE-3211FE38A8F0` — `M0-BACKEND-RULES-001` — replace/characterized: Space-template documents below an account preset have account-member CRUD.
- `RULE-79E65DCC45A6` — `M0-BACKEND-RULES-001` — replace/characterized: Account preset document, including default budget category pointer, has account-member CRUD.
- `RULE-AB3E61BAC3E3` — `M0-BACKEND-RULES-001` — redesign/characterized: Per-project category allocation records have account-member CRUD and trigger budget-summary recalculation.
- `RULE-AFC1D6191232` — `M0-BACKEND-RULES-001` — replace/characterized: Vendor-default documents below an account preset have account-member CRUD.
- `RULE-C4FE7FBE534A` — `M0-BACKEND-RULES-001` — redesign/characterized: Account budget-category definitions and metadata have account-member CRUD and drive completeness and budget-summary Functions.
- `SWIFT-A3CDC454B0BA` — `M0-PROJECT-CATEGORY-CONFIGURATION-REVISION-001` — redesign/blocked: Comment-only Project category PowerSync provider placeholder.
- `SWIFT-BD6661CFC518` — `M0-PROJECT-CATEGORY-CONFIGURATION-REVISION-001` — redesign/blocked: Comment-only future read-only staging-view placeholder.
- `SWIFT-D2C84703FEEA` — `M0-PROJECT-CATEGORY-CONFIGURATION-REVISION-001` — redesign/blocked: Comment-only future AppModel placeholder.
- `SWIFT-D3652DD63EA1` — `M0-PROJECT-CATEGORY-CONFIGURATION-REVISION-001` — redesign/blocked: Comment-only future staging-runtime adapter placeholder.
- `TEST-5286613EC809` — `M0-PROJECT-CATEGORY-CONFIGURATION-REVISION-001` — redesign/blocked: Comment-only future provider-test placeholder.
- `TEST-561F3FACCE6F` — `M0-PROJECT-CATEGORY-CONFIGURATION-REVISION-001` — redesign/blocked: Comment-only future AppModel-test placeholder.
- `MCPMOD-CA75CFB7F29D` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Registers category list and Project category enable/update/read tools while also recomputing current Transaction-only spend via Admin SDK.
- `MCPTOOL-9503D6684EDA` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Merge-writes one Project category budgetCents without validating non-negative range, category existence/type, Project existence, permissions or a revision.
- `MCPTOOL-DA72457132EF` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Merge-enables one category for a Project with optional budgetCents and process timestamps, without validating parent/category/account relationships or authorization beyond MCP context.
- `SWIFT-17BB6ABA1400` — `M0-PROJECT-CLIENT-REFERENCE-001` — redesign/characterized: Stores vendor suggestions as one ordered string array, seeds a hardcoded default set, listens to the document and performs non-transactional read-modify-write add-if-missing with whitespace/lowercase normalization.
- `SWIFT-1E0A38FC6F25` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Manages the vendor string array with optimistic local removal/reorder and silent saves; add uses the service's race-prone read-modify-write path.
- `SWIFT-4637466F7F73` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Provides generic Space-template subscribe/create/update/delete and create-from-Space by copying name, notes and checklist state without resetting checked items.
- `SWIFT-8D312DD816C5` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Creates, edits, archives/unarchives and reorders categories. Reorder launches an independent silent write per row; UI validation is not backed by trusted system/reference checks.
- `SWIFT-AFBB07058144` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Provides generic account budget-category subscribe/create/update/delete against the default presets subcollection.
- `SWIFT-BAFED6656104` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Subscribes/sets/deletes Project category allocation documents and also implements Fee installment validation and batch writes in the same source file. Project allocation writes merge budgetCents and optional actor fields.
- `SWIFT-E00DB27DF0BA` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Manages templates with create/edit/hard-delete and independent per-row reorder writes, suppressing all persistence errors.
- `MCPMOD-D391DC704D1F` — `M0-SPACES-REVIEW-001` — replace/characterized: Implements Firebase Space list/get/create/update tools and generic fields.
- `SWIFT-5BB6D8BE3292` — `M0-SPACES-REVIEW-001` — replace/characterized: Computes Space checklist progress, template-role availability, and detail summaries.

### O-032 — 23 surfaces

- Kind: product decision
- Owning context: Transaction capture/import
- Required closure: Approved posted-versus-draft contract plus offline restart, budget exclusion, completion, import quarantine and concurrency tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-1BC6BB701AA3` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Pure helper selects purchase versus project price as the current transaction completeness audit basis from legacy type/source/project fields.
- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `FUNCTION-24C086150C5D` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On relevant account budget-category changes, recomputes completeness for category Transactions and budget summaries for every Project in small concurrent batches.
- `FUNCTION-EBFFD3F950A0` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On any Transaction create/update/delete, recalculates budget summaries for old/new Projects and computes isComplete/audit except for loop-guarded Function-only updates.
- `RULE-6852D375E671` — `M0-BACKEND-RULES-001` — redesign/characterized: Transactions have member read/create; deletion requires empty itemIds; selected inventory-movement accounting fields are immutable while itemIds and non-accounting fields may change; Functions maintain audits and summaries.
- `MCPMOD-868A3F35EBC3` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Registers Admin-SDK Transaction list/detail/search/create/update/bulk/cancel/delete/media tools with current Firestore taxonomy and relationships.
- `MCPTOOL-188AF292FAFF` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Atomically creates a current itemized Transaction and multiple Item documents, can route Inventory source into an additional Project Purchase, inherit tax rate and write lineage.
- `MCPTOOL-88CE4407A0B9` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Generically creates current Purchase/Return/paymentToBusiness records and can directly link Items under Admin access.
- `SWIFT-01C928A8B707` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Represents a Firestore Transaction with legacy/current types, overloaded active itemIds, routing flags, receipt subtotal/tax/discount, ingestion, completeness audit and settlement links.
- `SWIFT-1178D1E9F474` — `M0-INVENTORY-TRANSACTION-001` — replace/characterized: Provides generic Firestore Transaction CRUD/listeners and untyped updates that can cascade scope/category changes to active Items or hard-delete after an itemIds-only check.
- `SWIFT-3348465E2026` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Validates the current Transaction wizard primarily by selected type and explicit inventory-resale handling, leaving detail fields optional.
- `SWIFT-34855F53F580` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Derives a current completeness checklist from category, amount, receipt, Items, payer and positive tax-rate fields plus inventory-purchase intent state.
- `SWIFT-A7915475818E` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Creates Purchase/Return records from a multi-step form, permits type-only submission, derives subtotal/tax, routes business-paid purchases and dismisses after local Firestore submission.
- `TEST-AB7FBFCBDFD4` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Tests current type-only Transaction form validation and inventory-resale routing decisions.
- `MCPMOD-4A73B044281F` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Combines Transaction reconciliation/creation and a legacy incomplete-Transaction triage query in one Firebase module.
- `MCPMOD-917C20FEDA6A` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Computes Project health, Inventory value, vendor spend, budget variance, and Item attention directly from raw Firebase rows.
- `MCPTOOL-93A953185655` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Flags Items missing name, SKU, prices, tax, or carrying legacy workflow statuses.
- `MCPTOOL-BC13265D05FD` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Ranks legacy incomplete Transactions and suggests reconciliation from missing project/category/items/tax fields.
- `MCPTOOL-F15CC6C9A7AC` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Builds Project health from raw Items/Transactions, cached assumptions, and legacy completeness.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.
- `SWIFT-454F9189FDCF` — `M0-SPACES-REVIEW-001` — redesign/characterized: Displays an in-memory legacy incomplete-Transaction review queue from account arrays.
- `SWIFT-C821F5F10EAE` — `M0-SPACES-REVIEW-001` — redesign/characterized: Buckets legacy incomplete Transactions into unassigned/Inventory/Project review lists.

### O-023 — 22 surfaces

- Kind: product decision
- Owning context: Attachments and retention
- Required closure: Approved detach/delete product behavior plus shared-reference, paid-evidence, retry, retention, and restoration tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-3084F8C3058D` — `M0-BACKEND-RULES-001` — replace/characterized: Space review-note records have account-member CRUD.
- `RULE-D3CFB25D03AD` — `M0-BACKEND-RULES-001` — redesign/characterized: Core Item records are member-readable/deletable; create/update enforces nonnegative optional prices and project price at least nonzero purchase cost.
- `MAN-STORAGE-001` — `M0-BACKEND-STORAGE-001` — replace/characterized: Firebase Storage holds entity-scoped originals and small/medium thumbnails referenced by embedded Firestore URLs. Current rules allow unauthenticated global read/write. iOS has a restart-durable local upload queue; MCP performs privileged copy/upload/delete operations. Object inventory and dangling-reference counts are not yet production-profiled.
- `MCPMOD-B5A85B82D135` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Performs broad Transaction deletion dependency preflight across Items, provenance, Invoices, lineage, drafts, attachments, repricing and ingestion evidence.
- `MCPTOOL-282034D0C8AF` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Dry-runs and default-denies permanent deletion unless one Transaction is canceled, budget-neutral, item/attachment/reference-free, then requires server human confirmation and writes a tombstone atomically.
- `MCPTOOL-BBB9B61F2EE8` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Applies the same deletion preflight/confirmation/tombstone contract to an exact all-or-nothing batch of current Transactions.
- `SWIFT-BDF8928A5FC7` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Combines Transaction detail, active and lineage-reconstructed Items, proto review, receipt media, completeness, generic association, movement, correction and deletion in one Firebase-driven view.
- `MCPMOD-82DC4C25B1B8` — `M0-ITEM-CREATION-LINK-001` — replace/characterized: Registers Admin-SDK Item list/search/get/create/update/bulk/delete and media tools with Firestore-specific invariants. Project create requires transactionId, unlike Swift.
- `MCPTOOL-D2757741F638` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Hard-deletes an Item, removes its current Transaction array reference and best-effort deletes Item-owned Storage objects without target history/paid-dependency policy.
- `SWIFT-236679C7D427` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Defines Item detail display-state helpers and an action list that always includes delete and generic set/clear Transaction.
- `SWIFT-AB578AEF4330` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Builds live Item detail from Firebase Item/Transaction/Space/category data and exposes detail, media, movement, generic association, correction and delete actions.
- `SWIFT-C593225376EB` — `M0-ITEM-CREATION-LINK-001` — replace/characterized: Provides Firestore Item CRUD/listeners, price/category normalization, generic transaction association, bulk metadata writes, annotation cleanup and hard delete. Linked create may return generated Items before its asynchronous batch commit completes.
- `TEST-8B555E151D8D` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Tests Item detail route/display/price/action calculations including generic association and always-visible delete.
- `MCPTOOL-35D04B60563F` — `M0-MEDIA-LIFECYCLE-001` — replace/characterized: Non-destructively removes an Item attachment reference, reselects a primary, preserves all Storage objects and reports namespace warnings.
- `MCPTOOL-608B84DDBEA5` — `M0-MEDIA-LIFECYCLE-001` — redesign/characterized: Removes an Item attachment reference, then attempts permanent deletion only for original/derivative Firebase URLs parsed inside that Item namespace; external/shared URLs are detached with warnings.
- `MCPTOOL-9C8591F5294C` — `M0-MEDIA-LIFECYCLE-001` — redesign/characterized: Removes a Transaction receipt/other reference without primary normalization, then immediately best-effort deletes original and derivative objects without shared-reference or financial-retention checks.
- `MCPTOOL-EAA4B71CE0F5` — `M0-MEDIA-LIFECYCLE-001` — redesign/characterized: Removes a Space attachment reference, repairs primary flags and immediately best-effort deletes original and derivative objects without a shared-reference or retention check.
- `SWIFT-8494F171316C` — `M0-SPACES-REVIEW-001` — replace/characterized: Implements Firestore Space CRUD/listeners, generic updates, attachment normalization, and hard delete.
- `SWIFT-C11974860D78` — `M0-SPACES-REVIEW-001` — replace/characterized: Performs Firestore review-note CRUD with client-authored fields and URL-shaped visual snapshots.
- `SWIFT-DDFAC91775DA` — `M0-SPACES-REVIEW-001` — redesign/characterized: Builds a large Firebase-listener Space detail that also composes Item media, movement, status, relation, delete, note and checklist actions.
- `SWIFT-EF8BEC4E8BE5` — `M0-SPACES-REVIEW-001` — redesign/characterized: Picks, marks, views, and edits URL-keyed Space review-note photo references.
- `TEST-E97A8051035C` — `M0-SPACES-REVIEW-001` — redesign/characterized: Tests review-note Space validation, marker bounds, photo filtering, and Firestore update fields.

### O-005 — 20 surfaces

- Kind: product decision
- Owning context: Budget presentation
- Required closure: Approved arithmetic/visual specification and signed-value snapshot tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-B16FE8CF3DEA` — `M0-BACKEND-RULES-001` — redesign/characterized: Invoice event records are readable and creatable by any account member, then immutable; intended as a payment-correction audit trail.
- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPTOOL-044AFFA1EEFB` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Either attaches Items to an existing vendor Return or moves proven Inventory-origin Items back to Inventory while creating per-batch project Returns and credits.
- `MCPTOOL-3517FF5089A3` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Acquires project-origin Items into Inventory using a project Sale Transaction at purchase-cost basis.
- `SWIFT-1DCA8A4ADE51` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Composes Inventory/Project/vendor movement as Firestore Transaction, Item, lineage and paid-credit writes, with origin-aware price logic and fixed batch limits.
- `SWIFT-E29B4124133A` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Splits Project Items by inferred origin into current Return-to-Inventory or Sale-to-Inventory operations and previews current budget effects.
- `MCPMOD-7E2A27F3F12F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Implements Admin-SDK Invoice composition, mutable lines, partial/whole collection, cancel/void, and contract setup.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-14D0C2F1019A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Derives budget-tab rows and single spent progress from current Transaction/category/allocation arrays.
- `SWIFT-263BA57A580A` — `M0-INVOICING-BUDGET-001` — replace/characterized: Renders one budget progress bar and remaining/over labels.
- `SWIFT-800DE43469FC` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Builds the Project budget screen from independent context listeners and Transaction-only calculations.
- `SWIFT-9A3A702CA92E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Infers invoiceable sources, signed amounts, price locks, membership, and manual credits from mutable app records.
- `SWIFT-AB58F2F2752F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Shows compact single-segment budget progress previews.
- `SWIFT-E4724837204F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Renders category budget tracker values and Fee-specific labels from single spent progress.
- `SWIFT-E5E95679647A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Combines Invoicing, Invoices, inferred Expenses, Fees, collection actions, and billing totals from independent local caches.
- `SWIFT-F1FAE8106010` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Calculates budget tracker values and labels from a single spent amount.
- `TEST-F86623DF8B57` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Tests single-segment budget tracker calculations and labels.
- `MCPTOOL-EDD825A4C317` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Computes per-category budget variance from allocations and Transaction-only signs.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-029 — 20 surfaces

- Kind: product decision
- Owning context: Transaction lifecycle
- Required closure: Approved state/dependency policy plus stale-plan, paid/Invoice/Item/lineage/media, retry, human-confirmation and immutable-evidence tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `FUNCTION-EBFFD3F950A0` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On any Transaction create/update/delete, recalculates budget summaries for old/new Projects and computes isComplete/audit except for loop-guarded Function-only updates.
- `RULE-6852D375E671` — `M0-BACKEND-RULES-001` — redesign/characterized: Transactions have member read/create; deletion requires empty itemIds; selected inventory-movement accounting fields are immutable while itemIds and non-accounting fields may change; Functions maintain audits and summaries.
- `MCPMOD-868A3F35EBC3` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Registers Admin-SDK Transaction list/detail/search/create/update/bulk/cancel/delete/media tools with current Firestore taxonomy and relationships.
- `MCPMOD-B5A85B82D135` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Performs broad Transaction deletion dependency preflight across Items, provenance, Invoices, lineage, drafts, attachments, repricing and ingestion evidence.
- `MCPTOOL-2182ACB9E363` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Applies generic Transaction field patches and can cascade scope/category changes or clear Item membership with correction lineage.
- `MCPTOOL-282034D0C8AF` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Dry-runs and default-denies permanent deletion unless one Transaction is canceled, budget-neutral, item/attachment/reference-free, then requires server human confirmation and writes a tombstone atomically.
- `MCPTOOL-BBB9B61F2EE8` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Applies the same deletion preflight/confirmation/tombstone contract to an exact all-or-nothing batch of current Transactions.
- `MCPTOOL-DFCD5082BE2F` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Sets canceled with a durable note in a Firestore transaction but does not preflight Item/Invoice/lineage/attachment dependencies.
- `SWIFT-04CC0C101EA4` — `M0-INVENTORY-TRANSACTION-001` — replace/characterized: Displays Project Transactions with local filters/groups/selection/totals and exposes single or bulk deletion through the weak iOS dependency check.
- `SWIFT-1178D1E9F474` — `M0-INVENTORY-TRANSACTION-001` — replace/characterized: Provides generic Firestore Transaction CRUD/listeners and untyped updates that can cascade scope/category changes to active Items or hard-delete after an itemIds-only check.
- `SWIFT-4003332541C1` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Edits Transaction fields through an untyped dictionary, including cancellation; submits transactionType/hasEmailReceipt keys that differ from persisted type/receiptEmailed names.
- `SWIFT-582C58D417AA` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Builds Transaction menus that broadly expose delete and generic whole-Transaction Correct/Move while freezing selected generated movements.
- `SWIFT-674F92BED6F7` — `M0-INVENTORY-TRANSACTION-001` — replace/characterized: Displays Inventory Transactions and intended-project groups with local filters/selection/totals and broad deletion.
- `SWIFT-BDF8928A5FC7` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Combines Transaction detail, active and lineage-reconstructed Items, proto review, receipt media, completeness, generic association, movement, correction and deletion in one Firebase-driven view.
- `TEST-86F344E55403` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Tests current Transaction action-menu exposure for movement, correction and deletion states.
- `MCPTOOL-03C1DA443F46` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Cancels Invoice settlement Transactions and changes a paid Invoice back to sent.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `SWIFT-F3BDD0968C6D` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Scans account arrays, shows tab counts/results, resolves context, and performs broad generic bulk mutations from search.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-040 — 17 surfaces

- Kind: product decision
- Owning context: Personal Project budget pinning
- Required closure: Approved feature, target, missing/empty/no-pin/default/card and lifecycle policy plus no-render-write, cross-user, offline conflict/recovery and migration tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `RULE-684AA9BB1569` — `M0-BACKEND-RULES-001` — replace/characterized: Per-user project preference document has member-wide CRUD; the rule does not restrict writes to the uid named in the path.
- `SWIFT-14D0C2F1019A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Derives budget-tab rows and single spent progress from current Transaction/category/allocation arrays.
- `SWIFT-800DE43469FC` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Builds the Project budget screen from independent context listeners and Transaction-only calculations.
- `SWIFT-D6F4A0ED81EF` — `M0-INVOICING-BUDGET-001` — replace/characterized: Displays pinned category progress from current single-segment budget values.
- `TEST-04DAF7B43B47` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Tests current budget-tab Transaction/category/allocation arithmetic.
- `MCPMOD-8FC7F6247E2F` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Registers Project list/get/budget/create/update/archive tools over Admin SDK. Client is free text; create/update/note side effects are independent; Project get scans Items; budget recomputes current Transaction-only arithmetic.
- `MCPTOOL-55857D0737AE` — `M0-PROJECT-CLIENT-REFERENCE-001` — redesign/characterized: Creates a Project with name/free-text clientName and then independently creates an optional nested note; no Client identity, Project category setup or shared idempotency result exists.
- `SWIFT-093E5E4F8D20` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Directly listens to one/all Project preference documents under a supplied user path and merge-writes pinned IDs. Listener errors become nil/empty and no caller/path principal equality is enforced in this service.
- `SWIFT-1DA3D2CE9B31` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Activates nine independent Project-scoped listeners, stores partial results in memory, applies financial filtering locally, derives budget state, and exposes Project archive/delete and note CRUD. It does not expose a complete-history or durable operation state.
- `SWIFT-27CA6EAC7092` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Defines the Project service seam in Firebase ListenerRegistration and untyped field dictionaries, including free-text clientName creation and unconditional delete.
- `SWIFT-58A14BD25578` — `M0-PROJECT-CLIENT-REFERENCE-001` — redesign/characterized: Creates a Project from name and free-text clientName, dismisses after the first local Firestore write, then independently and silently writes selected category allocations and enqueues hero media. Missing allocation input becomes explicit zero.
- `SWIFT-B6C3B72884E1` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Defines a Firestore-Codable Project preference with redundant account/user/Project IDs and pinned category IDs while omitting timestamps from explicit Codable keys.
- `SWIFT-D73C92887393` — `M0-PROJECT-CLIENT-REFERENCE-001` — redesign/characterized: Displays Project and free-text Client name, owns tabs/export/quick note/edit/archive, and offers destructive Project deletion that warns only about Items while leaving all children orphaned.
- `SWIFT-E1A771F6A409` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Provides generic Firestore Project get/create/update/delete and unfiltered account listeners. Creation generates a Project with free-text clientName; update accepts arbitrary field dictionaries; delete removes only the Project document.
- `SWIFT-E23DAF7A18FA` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Shows active/archived Project cards from the account cache, sorted by Project name, and independently subscribes to every current user's Project preferences for denormalized budget previews.
- `TEST-3D0D949763A1` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Tests Project archive filters, Project/clientName search, name sorting, empty copy and budget preview ordering.

### O-031 — 16 surfaces

- Kind: product decision
- Owning context: Item price/tax basis
- Required closure: Approved tax-inclusive or explicit per-Item allocation rule with mixed-tax, migration and no-silent-inheritance tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-1BC6BB701AA3` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Pure helper selects purchase versus project price as the current transaction completeness audit basis from legacy type/source/project fields.
- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `FUNCTION-EBFFD3F950A0` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On any Transaction create/update/delete, recalculates budget summaries for old/new Projects and computes isComplete/audit except for loop-guarded Function-only updates.
- `MCPTOOL-188AF292FAFF` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Atomically creates a current itemized Transaction and multiple Item documents, can route Inventory source into an additional Project Purchase, inherit tax rate and write lineage.
- `MCPTOOL-34265DD4542A` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Reports current Transaction subtotal/discount/item variance and suggests generic field/Item fixes using percentage tolerance.
- `SWIFT-01C928A8B707` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Represents a Firestore Transaction with legacy/current types, overloaded active itemIds, routing flags, receipt subtotal/tax/discount, ingestion, completeness audit and settlement links.
- `SWIFT-34855F53F580` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Derives a current completeness checklist from category, amount, receipt, Items, payer and positive tax-rate fields plus inventory-purchase intent state.
- `SWIFT-A7915475818E` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Creates Purchase/Return records from a multi-step form, permits type-only submission, derives subtotal/tax, routes business-paid purchases and dismisses after local Firestore submission.
- `MCPMOD-4B5868CBF5DC` — `M0-PLATFORM-CONTROL-001` — redesign/characterized: Derives current Item price/tax behavior from legacy fields.
- `MCPMOD-4A73B044281F` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Combines Transaction reconciliation/creation and a legacy incomplete-Transaction triage query in one Firebase module.
- `MCPMOD-917C20FEDA6A` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Computes Project health, Inventory value, vendor spend, budget variance, and Item attention directly from raw Firebase rows.
- `MCPTOOL-4ED77CBCA500` — `M0-REPORTING-SEARCH-001` — replace/characterized: Aggregates current Inventory count/value/status/vendor from raw Items.
- `MCPTOOL-93A953185655` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Flags Items missing name, SKU, prices, tax, or carrying legacy workflow statuses.
- `MCPTOOL-BC13265D05FD` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Ranks legacy incomplete Transactions and suggests reconciliation from missing project/category/items/tax fields.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-009 — 15 surfaces

- Kind: product decision
- Owning context: Invoice sources
- Required closure: Decision to retire adjustments or define typed category, provenance, edit, and audit rules
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-9B7212EBB760` — `M0-BACKEND-RULES-001` — redesign/characterized: Invoice records have account-member CRUD and contain both legacy embedded lines and newer flat membership representations used by price-lock logic.
- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPMOD-7E2A27F3F12F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Implements Admin-SDK Invoice composition, mutable lines, partial/whole collection, cancel/void, and contract setup.
- `MCPTOOL-0FC981412C3D` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Creates an Invoice from caller-authored line DTOs after non-transactional validation.
- `MCPTOOL-2B21D2622825` — `M0-INVOICING-BUDGET-001` — replace/characterized: Builds a billable pool from mutable Items, Transactions, Fees, and current Invoice arrays.
- `MCPTOOL-F01CAFFDE387` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Mutates stored Invoice line amount/category/description through a generic tool.
- `MCPTOOL-FCF917D2F4D8` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Creates contract-design-fee charges as manual Invoice lines while applying project setup.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-31DB4E9B5136` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Models Firebase Invoice arrays, embedded signed lines, mutable totals/status and compatibility settlement fields.
- `SWIFT-38F4A97A4FCB` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Builds cached billable candidates, manual lines, and created-Invoice edits in one modal.
- `SWIFT-9A3A702CA92E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Infers invoiceable sources, signed amounts, price locks, membership, and manual credits from mutable app records.
- `SWIFT-E5E95679647A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Combines Invoicing, Invoices, inferred Expenses, Fees, collection actions, and billing totals from independent local caches.
- `SWIFT-EA6B4B939093` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Reconstructs Invoice lines from cached Items/Transactions/Fees and invokes send, collect, cancel, and payment correction.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-034 — 15 surfaces

- Kind: product decision
- Owning context: Sent Invoice revision/delivery
- Required closure: Approved sent-mutation policy plus live-value, membership, resend, offline conflict, collection-race and historical-render tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-9B7212EBB760` — `M0-BACKEND-RULES-001` — redesign/characterized: Invoice records have account-member CRUD and contain both legacy embedded lines and newer flat membership representations used by price-lock logic.
- `MCPMOD-7E2A27F3F12F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Implements Admin-SDK Invoice composition, mutable lines, partial/whole collection, cancel/void, and contract setup.
- `MCPTOOL-4CF82E3A1594` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Adds a caller-described line to a live Invoice after preflight checks.
- `MCPTOOL-B07353E174CA` — `M0-INVOICING-BUDGET-001` — replace/characterized: Marks an Invoice sent through a direct lifecycle mutation.
- `MCPTOOL-F01CAFFDE387` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Mutates stored Invoice line amount/category/description through a generic tool.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-31DB4E9B5136` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Models Firebase Invoice arrays, embedded signed lines, mutable totals/status and compatibility settlement fields.
- `SWIFT-38F4A97A4FCB` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Builds cached billable candidates, manual lines, and created-Invoice edits in one modal.
- `SWIFT-E5E95679647A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Combines Invoicing, Invoices, inferred Expenses, Fees, collection actions, and billing totals from independent local caches.
- `SWIFT-EA6B4B939093` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Reconstructs Invoice lines from cached Items/Transactions/Fees and invokes send, collect, cancel, and payment correction.
- `TEST-49D678CB6929` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Tests Firestore Invoice service behavior including snapshots, partial collection, grouped settlements, cancel, and void.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `SWIFT-E09C688A850B` — `M0-REPORTING-SEARCH-001` — replace/characterized: Displays Invoice charge/credit lines/totals/meta and downloads a PDF.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.
- `TEST-BA9C46AF6F3D` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests live/frozen Invoice report lines using status and current source fallbacks.

### O-003 — 13 surfaces

- Kind: product decision
- Owning context: Credit Settlement
- Required closure: Approved settlement routes and proof that only actual cash refund creates Return
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-B16FE8CF3DEA` — `M0-BACKEND-RULES-001` — redesign/characterized: Invoice event records are readable and creatable by any account member, then immutable; intended as a payment-correction audit trail.
- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPTOOL-044AFFA1EEFB` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Either attaches Items to an existing vendor Return or moves proven Inventory-origin Items back to Inventory while creating per-batch project Returns and credits.
- `MCPTOOL-3517FF5089A3` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Acquires project-origin Items into Inventory using a project Sale Transaction at purchase-cost basis.
- `SWIFT-1DCA8A4ADE51` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Composes Inventory/Project/vendor movement as Firestore Transaction, Item, lineage and paid-credit writes, with origin-aware price logic and fixed batch limits.
- `SWIFT-E29B4124133A` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Splits Project Items by inferred origin into current Return-to-Inventory or Sale-to-Inventory operations and previews current budget effects.
- `MCPMOD-7E2A27F3F12F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Implements Admin-SDK Invoice composition, mutable lines, partial/whole collection, cancel/void, and contract setup.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-9A3A702CA92E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Infers invoiceable sources, signed amounts, price locks, membership, and manual credits from mutable app records.
- `SWIFT-E5E95679647A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Combines Invoicing, Invoices, inferred Expenses, Fees, collection actions, and billing totals from independent local caches.
- `SWIFT-EA6B4B939093` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Reconstructs Invoice lines from cached Items/Transactions/Fees and invokes send, collect, cancel, and payment correction.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-004 — 13 surfaces

- Kind: product decision
- Owning context: Credit Settlement / Invoice lifecycle
- Required closure: Explicit terminal states, accounting effects, and collection rejection tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-B16FE8CF3DEA` — `M0-BACKEND-RULES-001` — redesign/characterized: Invoice event records are readable and creatable by any account member, then immutable; intended as a payment-correction audit trail.
- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPTOOL-044AFFA1EEFB` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Either attaches Items to an existing vendor Return or moves proven Inventory-origin Items back to Inventory while creating per-batch project Returns and credits.
- `MCPTOOL-3517FF5089A3` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Acquires project-origin Items into Inventory using a project Sale Transaction at purchase-cost basis.
- `SWIFT-1DCA8A4ADE51` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Composes Inventory/Project/vendor movement as Firestore Transaction, Item, lineage and paid-credit writes, with origin-aware price logic and fixed batch limits.
- `SWIFT-E29B4124133A` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Splits Project Items by inferred origin into current Return-to-Inventory or Sale-to-Inventory operations and previews current budget effects.
- `MCPMOD-7E2A27F3F12F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Implements Admin-SDK Invoice composition, mutable lines, partial/whole collection, cancel/void, and contract setup.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-9A3A702CA92E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Infers invoiceable sources, signed amounts, price locks, membership, and manual credits from mutable app records.
- `SWIFT-E5E95679647A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Combines Invoicing, Invoices, inferred Expenses, Fees, collection actions, and billing totals from independent local caches.
- `SWIFT-EA6B4B939093` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Reconstructs Invoice lines from cached Items/Transactions/Fees and invokes send, collect, cancel, and payment correction.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-010 — 13 surfaces

- Kind: product decision
- Owning context: Invoice lifecycle
- Required closure: Approved cancel/noncollectible behavior and last-line concurrency tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-9B7212EBB760` — `M0-BACKEND-RULES-001` — redesign/characterized: Invoice records have account-member CRUD and contain both legacy embedded lines and newer flat membership representations used by price-lock logic.
- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPMOD-7E2A27F3F12F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Implements Admin-SDK Invoice composition, mutable lines, partial/whole collection, cancel/void, and contract setup.
- `MCPTOOL-0FC981412C3D` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Creates an Invoice from caller-authored line DTOs after non-transactional validation.
- `MCPTOOL-2B21D2622825` — `M0-INVOICING-BUDGET-001` — replace/characterized: Builds a billable pool from mutable Items, Transactions, Fees, and current Invoice arrays.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-31DB4E9B5136` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Models Firebase Invoice arrays, embedded signed lines, mutable totals/status and compatibility settlement fields.
- `SWIFT-38F4A97A4FCB` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Builds cached billable candidates, manual lines, and created-Invoice edits in one modal.
- `SWIFT-9A3A702CA92E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Infers invoiceable sources, signed amounts, price locks, membership, and manual credits from mutable app records.
- `SWIFT-E5E95679647A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Combines Invoicing, Invoices, inferred Expenses, Fees, collection actions, and billing totals from independent local caches.
- `SWIFT-EA6B4B939093` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Reconstructs Invoice lines from cached Items/Transactions/Fees and invokes send, collect, cancel, and payment correction.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-008 — 11 surfaces

- Kind: product decision
- Owning context: Receipt Lines and Invoicing
- Required closure: Per-line treatment model and exact-cent collection/report tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `SWIFT-A7915475818E` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Creates Purchase/Return records from a multi-step form, permits type-only submission, derives subtotal/tax, routes business-paid purchases and dismisses after local Firestore submission.
- `MCPMOD-7E2A27F3F12F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Implements Admin-SDK Invoice composition, mutable lines, partial/whole collection, cancel/void, and contract setup.
- `MCPTOOL-2B21D2622825` — `M0-INVOICING-BUDGET-001` — replace/characterized: Builds a billable pool from mutable Items, Transactions, Fees, and current Invoice arrays.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-38F4A97A4FCB` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Builds cached billable candidates, manual lines, and created-Invoice edits in one modal.
- `SWIFT-9A3A702CA92E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Infers invoiceable sources, signed amounts, price locks, membership, and manual credits from mutable app records.
- `SWIFT-E5E95679647A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Combines Invoicing, Invoices, inferred Expenses, Fees, collection actions, and billing totals from independent local caches.
- `MCPMOD-4B5868CBF5DC` — `M0-PLATFORM-CONTROL-001` — redesign/characterized: Derives current Item price/tax behavior from legacy fields.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-030 — 11 surfaces

- Kind: product decision
- Owning context: Receipt completeness
- Required closure: Approved explicit-rounding-line or visible-tolerance behavior with exact-cent fixtures and no inferred tax/discount
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-1BC6BB701AA3` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Pure helper selects purchase versus project price as the current transaction completeness audit basis from legacy type/source/project fields.
- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `FUNCTION-EBFFD3F950A0` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: On any Transaction create/update/delete, recalculates budget summaries for old/new Projects and computes isComplete/audit except for loop-guarded Function-only updates.
- `MCPTOOL-34265DD4542A` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Reports current Transaction subtotal/discount/item variance and suggests generic field/Item fixes using percentage tolerance.
- `SWIFT-01C928A8B707` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Represents a Firestore Transaction with legacy/current types, overloaded active itemIds, routing flags, receipt subtotal/tax/discount, ingestion, completeness audit and settlement links.
- `SWIFT-34855F53F580` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Derives a current completeness checklist from category, amount, receipt, Items, payer and positive tax-rate fields plus inventory-purchase intent state.
- `SWIFT-A7915475818E` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Creates Purchase/Return records from a multi-step form, permits type-only submission, derives subtotal/tax, routes business-paid purchases and dismisses after local Firestore submission.
- `MCPMOD-4A73B044281F` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Combines Transaction reconciliation/creation and a legacy incomplete-Transaction triage query in one Firebase module.
- `MCPTOOL-BC13265D05FD` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Ranks legacy incomplete Transactions and suggests reconciliation from missing project/category/items/tax fields.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-027 — 10 surfaces

- Kind: product decision
- Owning context: Item Creation
- Required closure: One approved name/photo/note rule plus offline, API, and migration validation tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-D3CFB25D03AD` — `M0-BACKEND-RULES-001` — redesign/characterized: Core Item records are member-readable/deletable; create/update enforces nonnegative optional prices and project price at least nonzero purchase cost.
- `MCPTOOL-188AF292FAFF` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Atomically creates a current itemized Transaction and multiple Item documents, can route Inventory source into an additional Project Purchase, inherit tax rate and write lineage.
- `MCPMOD-82DC4C25B1B8` — `M0-ITEM-CREATION-LINK-001` — replace/characterized: Registers Admin-SDK Item list/search/get/create/update/bulk/delete and media tools with Firestore-specific invariants. Project create requires transactionId, unlike Swift.
- `MCPTOOL-90873708F7CA` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Creates one Firestore Item and optional Transaction back-reference but rejects project Items without transactionId.
- `MCPTOOL-A0EFDDABC6F3` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Creates multiple Firestore Item documents in one batch with shared/overridden scope and Transaction defaults.
- `SWIFT-068E43CFFCC5` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Implements a separate Quick Add form that accepts photo or note, extracts candidates, writes a ProtoItem and queues proto media.
- `SWIFT-8BA5197CA887` — `M0-ITEM-CREATION-LINK-001` — replace/characterized: Validates full Item creation as name-or-image and rejects negative optional prices; it does not accept a note as minimum identity evidence.
- `SWIFT-D2EEB690D6AD` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Combines the full Item form with Firebase listeners, Item writes, direct accounting/lineage batches, inventory routing, legacy conversion and media enqueue. Quantity branches can create N Items while retaining quantity N on each.
- `TEST-322BEAB07F90` — `M0-ITEM-CREATION-LINK-001` — replace/characterized: Proves the current name-or-image Item validation and nonnegative price checks.
- `MCPTOOL-93A953185655` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Flags Items missing name, SKU, prices, tax, or carrying legacy workflow statuses.

### O-033 — 10 surfaces

- Kind: product decision
- Owning context: Collection/payment variance
- Required closure: Approved exact-match or explicit variance model plus mismatch, retry, rounding, allocation, receipt, budget and correction tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MCPMOD-7E2A27F3F12F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Implements Admin-SDK Invoice composition, mutable lines, partial/whole collection, cancel/void, and contract setup.
- `MCPTOOL-03C1DA443F46` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Cancels Invoice settlement Transactions and changes a paid Invoice back to sent.
- `MCPTOOL-B87FC2B11214` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Collects caller-selected lines and creates category-grouped payment-to-business Transactions.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-E5E95679647A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Combines Invoicing, Invoices, inferred Expenses, Fees, collection actions, and billing totals from independent local caches.
- `SWIFT-EA6B4B939093` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Reconstructs Invoice lines from cached Items/Transactions/Fees and invokes send, collect, cancel, and payment correction.
- `TEST-49D678CB6929` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Tests Firestore Invoice service behavior including snapshots, partial collection, grouped settlements, cancel, and void.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.
- `TEST-BA9C46AF6F3D` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests live/frozen Invoice report lines using status and current source fallbacks.

### O-006 — 9 surfaces

- Kind: product decision
- Owning context: Expense / live Invoice
- Required closure: Field-by-state mutability matrix with concurrent edit/collection tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPMOD-7E2A27F3F12F` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Implements Admin-SDK Invoice composition, mutable lines, partial/whole collection, cancel/void, and contract setup.
- `MCPTOOL-2B21D2622825` — `M0-INVOICING-BUDGET-001` — replace/characterized: Builds a billable pool from mutable Items, Transactions, Fees, and current Invoice arrays.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-38F4A97A4FCB` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Builds cached billable candidates, manual lines, and created-Invoice edits in one modal.
- `SWIFT-9A3A702CA92E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Infers invoiceable sources, signed amounts, price locks, membership, and manual credits from mutable app records.
- `SWIFT-E5E95679647A` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Combines Invoicing, Invoices, inferred Expenses, Fees, collection actions, and billing totals from independent local caches.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-037 — 9 surfaces

- Kind: product decision
- Owning context: Space archive and Item assignment
- Required closure: Approved retain/clear/move rule plus assigned/empty, offline, search/report, concurrent assignment and scope-change tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `FUNCTION-92CE4FD9E25B` — `M0-BACKEND-FUNCTIONS-001` — replace/characterized: When a Space transitions to archived, batches through same-scope Items and clears spaceId; errors are logged and suppressed so cleanup may lag or fail independently.
- `RULE-3AB695EA4F67` — `M0-BACKEND-RULES-001` — replace/characterized: Space records have account-member CRUD. Archiving a Space asynchronously clears matching Item spaceId values.
- `MCPMOD-D391DC704D1F` — `M0-SPACES-REVIEW-001` — replace/characterized: Implements Firebase Space list/get/create/update tools and generic fields.
- `MCPTOOL-7259894A6F1C` — `M0-SPACES-REVIEW-001` — replace/characterized: Updates generic Firebase Space fields.
- `SWIFT-3D6443DA0A90` — `M0-SPACES-REVIEW-001` — replace/characterized: Exposes Firebase ListenerRegistration, generic field dictionaries, hard delete, and scope listeners for Spaces.
- `SWIFT-5BB6D8BE3292` — `M0-SPACES-REVIEW-001` — replace/characterized: Computes Space checklist progress, template-role availability, and detail summaries.
- `SWIFT-8494F171316C` — `M0-SPACES-REVIEW-001` — replace/characterized: Implements Firestore Space CRUD/listeners, generic updates, attachment normalization, and hard delete.
- `SWIFT-DDFAC91775DA` — `M0-SPACES-REVIEW-001` — redesign/characterized: Builds a large Firebase-listener Space detail that also composes Item media, movement, status, relation, delete, note and checklist actions.

### O-035 — 8 surfaces

- Kind: product decision
- Owning context: Client Summary financial meaning
- Required closure: Approved paid/open/recognized presentation plus no-double-count, credit, Transfer, open-source, collection and label tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MAN-REPORT-001` — `M0-REPORTING-SEARCH-001` — replace/characterized: Requires parity/reconciliation across reports, PDFs, CSV exports, search projections, MCP outputs, and client-visible totals.
- `MCPMOD-917C20FEDA6A` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Computes Project health, Inventory value, vendor spend, budget variance, and Item attention directly from raw Firebase rows.
- `MCPTOOL-EDD825A4C317` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Computes per-category budget variance from allocations and Transaction-only signs.
- `MCPTOOL-F15CC6C9A7AC` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Builds Project health from raw Items/Transactions, cached assumptions, and legacy completeness.
- `SWIFT-1772D7B7CE10` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Displays Client Summary active-Item totals, categories, receipt links, logo, and PDF sharing.
- `SWIFT-602AA12C6003` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Builds payable cards and Invoice/Client/Property reports from independent mutable context arrays.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-039 — 8 surfaces

- Kind: product decision
- Owning context: Project-note text validation
- Required closure: Approved cross-runtime trim/control/nonempty/byte rule plus app/MCP parity, zero-dispatch rejection, restart and lossless import/quarantine tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `SWIFT-A3E38557F13F` — `M0-APP-SHELL-PRESENTATION-001` — redesign/characterized: Collects a Project note and writes through current Account/Auth/Project contexts.
- `MCPMOD-DAB760104CEE` — `M0-PLATFORM-CONTROL-001` — replace/characterized: Provides structured MCP error payloads and note validation helpers.
- `MCPMOD-7774C2CE6D09` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Registers note add, newest-first list and case-insensitive substring search. Add does not first prove Project existence; search loads all Project notes before filtering.
- `MCPTOOL-D7FEF2D5FE3B` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Adds an MCP-authored Project note only when trimmed text has at least three characters, uses server process time and returns its ID, without a shared operation ID or explicit parent preflight.
- `SWIFT-1DA3D2CE9B31` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Activates nine independent Project-scoped listeners, stores partial results in memory, applies financial filtering locally, derives budget state, and exposes Project archive/delete and note CRUD. It does not expose a complete-history or durable operation state.
- `SWIFT-5B59D74F6B13` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Defines Firebase-shaped Project note subscribe/create/update/delete methods with untyped update fields.
- `SWIFT-7DC1AEC51D21` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Displays legacy Project.notes plus nested notes sorted newest-first by optional client timestamp and permits add/edit/delete with generic errors.
- `SWIFT-A3AB0F29E150` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Subscribes to and directly creates, updates and deletes nested Project note documents through the generic repository.

### A-015 — 7 surfaces

- Kind: architecture decision
- Owning context: Architecture and target spike
- Required closure: blocked: Choose the optimistic projection mechanism for complex offline commands
- Authority: `docs/architecture/redesign/architecture-decisions.md`

Affected surfaces:

- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `SWIFT-CD04095425B1` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Adds existing Items through generic same-scope association, cross-scope reassignment, return-to-Transaction or sell-to-Project operations and often dismisses before asynchronous outcome.
- `SWIFT-0B430AAF3B6E` — `M0-INVOICING-BUDGET-001` — redesign/characterized: Composes Firestore Invoice creation, line edits, send, status paid, partial/whole collection, cancel, and payment voiding.
- `SWIFT-0B434663295C` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Shows real Items and a separate Needs Assignment proto section, then composes convert/merge/delete, generic transaction association and bulk Item actions.
- `MAN-OFFLINE-001` — `M0-PLATFORM-CONTROL-001` — replace/characterized: Tracks current Firebase cache/pending-write/listener/reconnect behavior and target offline parity.
- `SWIFT-F3BDD0968C6D` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Scans account arrays, shows tab counts/results, resolves context, and performs broad generic bulk mutations from search.
- `SWIFT-DDFAC91775DA` — `M0-SPACES-REVIEW-001` — redesign/characterized: Builds a large Firebase-listener Space detail that also composes Item media, movement, status, relation, delete, note and checklist actions.

### O-036 — 7 surfaces

- Kind: product decision
- Owning context: Client-shared receipt evidence
- Required closure: Approved omit/embed/attach/authorized-link policy plus token/path leakage, revocation, expiry, offline, sharing and retention tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MAN-REPORT-001` — `M0-REPORTING-SEARCH-001` — replace/characterized: Requires parity/reconciliation across reports, PDFs, CSV exports, search projections, MCP outputs, and client-visible totals.
- `SWIFT-1772D7B7CE10` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Displays Client Summary active-Item totals, categories, receipt links, logo, and PDF sharing.
- `SWIFT-602AA12C6003` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Builds payable cards and Invoice/Client/Property reports from independent mutable context arrays.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `SWIFT-63EA86A59559` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Defines selectable CSV columns over raw Transaction, Item, category, URL, and legacy movement fields.
- `SWIFT-7C0540EDB528` — `M0-REPORTING-SEARCH-001` — replace/characterized: Escapes and renders Invoice/Client/Property HTML but recalculates some Item and Space values and embeds resolved receipt URLs.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-011 — 6 surfaces

- Kind: product decision
- Owning context: Transfer / Item tags
- Required closure: Approved carry/clear/reselect rule and source/destination projection tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPTOOL-1E36059850BA` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Moves Project Items to another Project via an origin-aware Inventory two-hop with source Return/Sale and destination Purchase.
- `SWIFT-1DCA8A4ADE51` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Composes Inventory/Project/vendor movement as Firestore Transaction, Item, lineage and paid-credit writes, with origin-aware price logic and fixed batch limits.
- `SWIFT-7792F727AA52` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Resolves bulk Project movement routes and current origin-dependent return/sale groupings for UI previews.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-012 — 6 surfaces

- Kind: product decision
- Owning context: Transfer / Space placement
- Required closure: Approved default/optional selection behavior and atomic destination-scope tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPTOOL-1E36059850BA` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Moves Project Items to another Project via an origin-aware Inventory two-hop with source Return/Sale and destination Purchase.
- `SWIFT-1DCA8A4ADE51` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Composes Inventory/Project/vendor movement as Firestore Transaction, Item, lineage and paid-credit writes, with origin-aware price logic and fixed batch limits.
- `SWIFT-7792F727AA52` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Resolves bulk Project movement routes and current origin-dependent return/sale groupings for UI previews.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-013 — 6 surfaces

- Kind: product decision
- Owning context: Transfer correction
- Required closure: Approved reversal rules; retry/concurrency and immutable-original tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPTOOL-1E36059850BA` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Moves Project Items to another Project via an origin-aware Inventory two-hop with source Return/Sale and destination Purchase.
- `SWIFT-1DCA8A4ADE51` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Composes Inventory/Project/vendor movement as Firestore Transaction, Item, lineage and paid-credit writes, with origin-aware price logic and fixed batch limits.
- `SWIFT-7792F727AA52` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Resolves bulk Project movement routes and current origin-dependent return/sale groupings for UI previews.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-014 — 6 surfaces

- Kind: product decision
- Owning context: Credit after Transfer
- Required closure: Approved hosting rule and multi-transfer credit/budget tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPTOOL-1E36059850BA` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Moves Project Items to another Project via an origin-aware Inventory two-hop with source Return/Sale and destination Purchase.
- `SWIFT-1DCA8A4ADE51` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Composes Inventory/Project/vendor movement as Firestore Transaction, Item, lineage and paid-credit writes, with origin-aware price logic and fixed batch limits.
- `SWIFT-7792F727AA52` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Resolves bulk Project movement routes and current origin-dependent return/sale groupings for UI previews.
- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### A-016 — 5 surfaces

- Kind: architecture decision
- Owning context: Architecture and target spike
- Required closure: blocked: Approve the bounded offline-access lease
- Authority: `docs/architecture/redesign/architecture-decisions.md`

Affected surfaces:

- `MAN-AUTH-001` — `M0-BACKEND-AUTH-001` — replace/characterized: Firebase Auth supplies email/password and Google identities and persistent sessions. Membership documents supply account, role, and financial-access authorization; no active custom-claim authorization was found. Public HTTP Functions verify Firebase bearer tokens. MCP exchanges Firebase identity for its own HMAC OAuth tokens.
- `SWIFT-C9CE3FC9787D` — `M0-BACKEND-AUTH-001` — replace/characterized: Observes Firebase auth state; signs in/up with email/password, signs in with Google credential exchange, and signs out only from Firebase Auth.
- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `MAN-STORAGE-001` — `M0-BACKEND-STORAGE-001` — replace/characterized: Firebase Storage holds entity-scoped originals and small/medium thumbnails referenced by embedded Firestore URLs. Current rules allow unauthenticated global read/write. iOS has a restart-durable local upload queue; MCP performs privileged copy/upload/delete operations. Object inventory and dangling-reference counts are not yet production-profiled.
- `MAN-OFFLINE-001` — `M0-PLATFORM-CONTROL-001` — replace/characterized: Tracks current Firebase cache/pending-write/listener/reconnect behavior and target offline parity.

### Canonical production reference/object profile — 5 surfaces

- Kind: production evidence
- Owning context: Attachment source profiling and migration
- Required closure: Approve and hash the production Firestore-reference/Storage-object graph, including shared, dangling, missing and retained evidence variants.

Affected surfaces:

- `MAN-STORAGE-001` — `M0-BACKEND-STORAGE-001` — replace/characterized: Firebase Storage holds entity-scoped originals and small/medium thumbnails referenced by embedded Firestore URLs. Current rules allow unauthenticated global read/write. iOS has a restart-durable local upload queue; MCP performs privileged copy/upload/delete operations. Object inventory and dangling-reference counts are not yet production-profiled.
- `MCPTOOL-35D04B60563F` — `M0-MEDIA-LIFECYCLE-001` — replace/characterized: Non-destructively removes an Item attachment reference, reselects a primary, preserves all Storage objects and reports namespace warnings.
- `MCPTOOL-608B84DDBEA5` — `M0-MEDIA-LIFECYCLE-001` — redesign/characterized: Removes an Item attachment reference, then attempts permanent deletion only for original/derivative Firebase URLs parsed inside that Item namespace; external/shared URLs are detached with warnings.
- `MCPTOOL-9C8591F5294C` — `M0-MEDIA-LIFECYCLE-001` — redesign/characterized: Removes a Transaction receipt/other reference without primary normalization, then immediately best-effort deletes original and derivative objects without shared-reference or financial-retention checks.
- `MCPTOOL-EAA4B71CE0F5` — `M0-MEDIA-LIFECYCLE-001` — redesign/characterized: Removes a Space attachment reference, repairs primary flags and immediately best-effort deletes original and derivative objects without a shared-reference or retention check.

### O-024 — 5 surfaces

- Kind: product decision
- Owning context: Project lifecycle
- Required closure: Approved archive/delete policy plus empty, child-bearing, financial-history, offline-retry and concurrent-child tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-0AD4AC2A568C` — `M0-BACKEND-RULES-001` — redesign/characterized: Project records have account-member CRUD and receive Function-maintained budgetSummary; current identity uses free-text clientName.
- `SWIFT-1DA3D2CE9B31` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Activates nine independent Project-scoped listeners, stores partial results in memory, applies financial filtering locally, derives budget state, and exposes Project archive/delete and note CRUD. It does not expose a complete-history or durable operation state.
- `SWIFT-27CA6EAC7092` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Defines the Project service seam in Firebase ListenerRegistration and untyped field dictionaries, including free-text clientName creation and unconditional delete.
- `SWIFT-D73C92887393` — `M0-PROJECT-CLIENT-REFERENCE-001` — redesign/characterized: Displays Project and free-text Client name, owns tabs/export/quick note/edit/archive, and offers destructive Project deletion that warns only about Items while leaving all children orphaned.
- `SWIFT-E1A771F6A409` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Provides generic Firestore Project get/create/update/delete and unfiltered account listeners. Creation generates a Project with free-text clientName; update accepts arbitrary field dictionaries; delete removes only the Project document.

### O-025 — 5 surfaces

- Kind: product decision
- Owning context: Client/Project correction
- Required closure: Approved mutability boundaries plus cross-Client, prior-Transfer, paid-history, retry and concurrent-change tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-0AD4AC2A568C` — `M0-BACKEND-RULES-001` — redesign/characterized: Project records have account-member CRUD and receive Function-maintained budgetSummary; current identity uses free-text clientName.
- `MCPTOOL-A9FCDED31D3F` — `M0-PROJECT-CLIENT-REFERENCE-001` — redesign/characterized: Directly updates name, free-text clientName and description and independently appends an optional note.
- `SWIFT-27CA6EAC7092` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Defines the Project service seam in Firebase ListenerRegistration and untyped field dictionaries, including free-text clientName creation and unconditional delete.
- `SWIFT-CF459111B7BB` — `M0-PROJECT-CLIENT-REFERENCE-001` — redesign/characterized: Edits Project name, free-text clientName, description, category selection/allocation and hero image, dismissing before independent Project, per-category and media tasks finish while suppressing their errors.
- `SWIFT-E1A771F6A409` — `M0-PROJECT-CLIENT-REFERENCE-001` — replace/characterized: Provides generic Firestore Project get/create/update/delete and unfiltered account listeners. Creation generates a Project with free-text clientName; update accepts arbitrary field dictionaries; delete removes only the Project document.

### O-038 — 5 surfaces

- Kind: product decision
- Owning context: Inventory destination planning
- Required closure: Approved retention/granularity/lifecycle and source migration, plus D-013 category isolation, offline, race, security and no-accounting-effect tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-E7CB6889A620` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Pure helper selects budgetCategoryId or fallback intendedBudgetCategoryId when evaluating legacy transaction completeness.
- `MCPMOD-D14DD1E83CFE` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Reads/updates Inventory Purchase planning intent and corrects an acquisition into the current project-reimbursement model.
- `MCPTOOL-42E5CABFC6F6` — `M0-INVENTORY-TRANSACTION-001` — replace/characterized: Lists Inventory resale Purchases with intended Project/category and derives follow-up state from Items and lineage.
- `MCPTOOL-4FF3862CBCD5` — `M0-INVENTORY-TRANSACTION-001` — replace/characterized: Sets, clears or resolves intended Project/category metadata on current Inventory resale Purchases.
- `SWIFT-34855F53F580` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Derives a current completeness checklist from category, amount, receipt, Items, payer and positive tax-rate fields plus inventory-purchase intent state.

### A-007 — 4 surfaces

- Kind: architecture decision
- Owning context: Architecture and target spike
- Required closure: proposed: Choose Supabase Auth at launch or a temporary Firebase Auth integration
- Authority: `docs/architecture/redesign/architecture-decisions.md`

Affected surfaces:

- `MAN-AUTH-001` — `M0-BACKEND-AUTH-001` — replace/characterized: Firebase Auth supplies email/password and Google identities and persistent sessions. Membership documents supply account, role, and financial-access authorization; no active custom-claim authorization was found. Public HTTP Functions verify Firebase bearer tokens. MCP exchanges Firebase identity for its own HMAC OAuth tokens.
- `MCPMOD-4938EA5E6169` — `M0-BACKEND-AUTH-001` — replace/characterized: Implements MCP OAuth/PKCE around Firebase login, stores one-time codes in _mcp_auth_codes, keeps dynamic client registrations in memory, and issues HMAC access/refresh JWTs whose payloads currently omit expiration.
- `SWIFT-C9CE3FC9787D` — `M0-BACKEND-AUTH-001` — replace/characterized: Observes Firebase auth state; signs in/up with email/password, signs in with Google credential exchange, and signs out only from Firebase Auth.
- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.

### O-002 — 4 surfaces

- Kind: product decision
- Owning context: Transfer and live Invoice membership
- Required closure: Approved recall/removal rule plus concurrency and audit tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MCPMOD-F5D411967411` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Implements five Firestore movement tools with origin resolution, per-batch Transactions, price snapshots, lineage, dry-run and atomic commits.
- `MCPTOOL-1E36059850BA` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Moves Project Items to another Project via an origin-aware Inventory two-hop with source Return/Sale and destination Purchase.
- `SWIFT-1DCA8A4ADE51` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Composes Inventory/Project/vendor movement as Firestore Transaction, Item, lineage and paid-credit writes, with origin-aware price logic and fixed batch limits.
- `SWIFT-7792F727AA52` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Resolves bulk Project movement routes and current origin-dependent return/sale groupings for UI previews.

### O-018 — 3 surfaces

- Kind: product decision
- Owning context: Proto migration and Compatibility
- Required closure: Mapping policy, unresolved queue, source-freeze gate, rollback, and no-loss tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-4DD3733CBE59` — `M0-BACKEND-RULES-001` — migrate/characterized: Legacy proto/quick-draft Item records have account-member CRUD and may carry media and candidate transaction links.
- `MCPMOD-3330B6FD5A68` — `M0-BACKEND-STORAGE-001` — replace/characterized: Copies quick-draft attachments into an Item-owned namespace, verifies bytes, generates thumbnails, and best-effort cleans newly created objects if promotion fails while preserving source originals.
- `SWIFT-1B50ECDA7CA1` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Edits and observes one live ProtoItem, its media, Space and route hint, then offers Assign, Match Existing or destructive removal.

### O-019 — 3 surfaces

- Kind: product decision
- Owning context: Item reconciliation
- Required closure: Deterministic identity winner, relationship/media merge, audit, and retry tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-4DD3733CBE59` — `M0-BACKEND-RULES-001` — migrate/characterized: Legacy proto/quick-draft Item records have account-member CRUD and may carry media and candidate transaction links.
- `MCPMOD-3330B6FD5A68` — `M0-BACKEND-STORAGE-001` — replace/characterized: Copies quick-draft attachments into an Item-owned namespace, verifies bytes, generates thumbnails, and best-effort cleans newly created objects if promotion fails while preserving source originals.
- `SWIFT-1B50ECDA7CA1` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Edits and observes one live ProtoItem, its media, Space and route hint, then offers Assign, Match Existing or destructive removal.

### Canonical production profile — 2 surfaces

- Kind: production evidence
- Owning context: Source data profiling and migration
- Required closure: Approve and hash a canonical immutable production export/profile that proves extant paths, shapes, variants, orphans and counts.

Affected surfaces:

- `MAN-DATA-001` — `M0-BACKEND-RULES-001` — migrate/blocked: Static source paths and known embedded variants are cataloged, but no canonical production export has confirmed collections, fields, types, enums, orphans, or counts.
- `MAN-DATA-002` — `M0-BACKEND-RULES-001` — redesign/characterized: Static source reveals transactionRepricingEvents idempotency markers, transactionDeletionTombstones audit records, root _mcp_auth_codes, starter quota/object paths, and dynamically selected createWithQuota collection paths outside the ordinary client collection catalog.

### O-016 — 2 surfaces

- Kind: product decision
- Owning context: Inventory acquisition evidence
- Required closure: Approved state and later-resolution command without fabricated Purchase
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MCPMOD-D14DD1E83CFE` — `M0-INVENTORY-TRANSACTION-001` — redesign/characterized: Reads/updates Inventory Purchase planning intent and corrects an acquisition into the current project-reimbursement model.
- `SWIFT-D2EEB690D6AD` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Combines the full Item form with Firebase listeners, Item writes, direct accounting/lineage batches, inventory routing, legacy conversion and media enqueue. Quantity branches can create N Items while retaining quantity N on each.

### O-020 — 2 surfaces

- Kind: product decision
- Owning context: Compatibility
- Required closure: Target accounting-contract/budget evidence, migration reconciliation, and O-022 source cutoff
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `RULE-4DD3733CBE59` — `M0-BACKEND-RULES-001` — migrate/characterized: Legacy proto/quick-draft Item records have account-member CRUD and may carry media and candidate transaction links.
- `MCPMOD-3330B6FD5A68` — `M0-BACKEND-STORAGE-001` — replace/characterized: Copies quick-draft attachments into an Item-owned namespace, verifies bytes, generates thumbnails, and best-effort cleans newly created objects if promotion fails while preserving source originals.

### O-022 — 2 surfaces

- Kind: product decision
- Owning context: Compatibility and Cutover
- Required closure: Approved quiescence, source-freeze, and recovery plan; proof late Firebase writes cannot bypass or be lost after final delta
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `FUNCMOD-B42AA317B971` — `M0-BACKEND-FUNCTIONS-001` — redesign/characterized: Single Functions entrypoint contains account/invite APIs, starter quota API, lineage/price/Space triggers, accounting audit logic, budget projections, and backfills.
- `MAN-CUTOVER-001` — `M0-CUTOVER-CONTROL-001` — redesign/blocked: No approved stale-client write-freeze, final-delta, rejected-write recovery, and rollback-boundary mechanism exists yet.

### O-028 — 2 surfaces

- Kind: product decision
- Owning context: Vendor cancellation/non-cash credit
- Required closure: Approved representation that adds no fourth Transaction, conserves every credit cent, and creates Return only for actual money received
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `SWIFT-6109B0A97167` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Derives report totals/rows from legacy Transaction movement/reimbursement fields, mutable Items, Invoice status/lines, Fees, and Spaces.
- `TEST-880C5785FD49` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Tests current report aggregation from reimbursement/movement Transactions, Items, Spaces, and active status.

### O-041 — 2 surfaces

- Kind: product decision
- Owning context: Vendor-spend report semantics
- Required closure: Approved report meaning plus exact-cent, payer, scope, currency, credit, correction, security, offline-readiness, migration and app/MCP parity tests
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `MCPMOD-917C20FEDA6A` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Computes Project health, Inventory value, vendor spend, budget variance, and Item attention directly from raw Firebase rows.
- `MCPTOOL-556E4BBD4A8C` — `M0-REPORTING-SEARCH-001` — redesign/characterized: Adds raw noncanceled Transaction amounts by source/vendor without scope-relative accounting signs.

### A-003 — 1 surface

- Kind: architecture decision
- Owning context: Architecture and target spike
- Required closure: proposed: Supabase Postgres becomes target server authority
- Authority: `docs/architecture/redesign/architecture-decisions.md`

Affected surfaces:

- `CONFIG-2F4D7DBFD096` — `M0-PLATFORM-CONTROL-001` — replace/characterized: Pins the current Swift dependency graph, including Firebase-era packages.

### A-004 — 1 surface

- Kind: architecture decision
- Owning context: Architecture and target spike
- Required closure: proposed: PowerSync SQLite becomes the target local data plane
- Authority: `docs/architecture/redesign/architecture-decisions.md`

Affected surfaces:

- `CONFIG-2F4D7DBFD096` — `M0-PLATFORM-CONTROL-001` — replace/characterized: Pins the current Swift dependency graph, including Firebase-era packages.

### O-017 — 1 surface

- Kind: product decision
- Owning context: Item Creation UI/domain boundary
- Required closure: Decision that hint is omitted or explicitly non-authoritative; Link remains authority
- Authority: `docs/plans/ledger-accounting-redesign/decision-log.md`
- Traceability: `docs/architecture/redesign/product-decision-traceability.md`

Affected surfaces:

- `SWIFT-068E43CFFCC5` — `M0-ITEM-CREATION-LINK-001` — redesign/characterized: Implements a separate Quick Add form that accepts photo or note, extracts candidates, writes a ProtoItem and queues proto media.

### Physical target verification — 1 surface

- Kind: target verification
- Owning context: Offline target spike and physical-device acceptance
- Required closure: Run the isolated Supabase/PowerSync target on physical devices and prove restart, offline lease, queue, readiness and reconnect behavior.

Affected surfaces:

- `MAN-OFFLINE-001` — `M0-PLATFORM-CONTROL-001` — replace/characterized: Tracks current Firebase cache/pending-write/listener/reconnect behavior and target offline parity.

## Update Rule

When a decision closes, update the canonical spec/decision log first, then traceability and architecture, then the affected classification entries and target-mapping evidence. Regenerate this register and require `npm run conversion:residuals:check` to pass. Do not reduce the count by replacing an exact blocker with a generic implementation placeholder.
