# Transaction Taxonomy Execution Plan

Created: 2026-06-26

This is the implementation plan for aligning code, specs, and production data
with the transaction taxonomy in
`docs/plans/transaction-taxonomy-system-design-recommendation.md`.

Related context:

- Master tracker: `docs/plans/transaction-taxonomy-master-tracker.md`
- Impact audit: `docs/plans/transaction-taxonomy-migration-impact-audit.md`
- Decisions log: `docs/plans/transaction-taxonomy-open-decisions.md`
- Existing paused migration plan: `docs/plans/transaction-type-migration.md`

## Target State

Transaction event types:

- `purchase`
- `return`
- `sale`
- `paymentToBusiness`

Removed from new writes:

- `fee`
- `expense`
- Mixed budget categories

Core rules:

- Itemization belongs to the budget category.
- Services and non-itemized costs are still `purchase` transactions.
- Every transaction must have a `budgetCategoryId`.
- Planned design fees are invoice demand, not transactions.
- Existing historical design-fee transaction rows are already transactions and
  migrate to `paymentToBusiness`.
- Invoice collection creates one categorized `paymentToBusiness` transaction per
  budget category represented in the settled invoice lines.
- Manual New Charge lines require an explicit budget category. No silent default.
- Returned-after-collected item credits become negative invoice demand / credit
  lines, not `expense` transactions.

## Phase 0 - Freeze And Guard New Writes

Goal: stop creating more data that has to be cleaned later.

Code work:

- Remove `fee` and `expense` from normal new-transaction creation paths.
- Add `paymentToBusiness` to `TransactionType`.
- Keep temporary decode/read compatibility for existing `fee`, `expense`, and
  legacy `to inventory`.
- Keep inventory routing limited to:

```text
selected category is itemized/items
AND purchasedBy == design-business
AND actual items exist / are being created
```

- Ensure CategoryForm cannot create Mixed categories.
- Ensure the item-entry flow does not show sell-from-inventory options when no
  items exist.

Verification:

- Business-paid non-itemized purchase does not open item/inventory sale flow.
- Business-paid itemized purchase with created items can still offer inventory
  sale flow.
- Category creation offers no Mixed option.

## Phase 1 - Invoice Category Model

Goal: make invoices capable of producing categorized settlement transactions.

Code work:

- Add `budgetCategoryId` to `InvoiceLine`.
- For item-sourced lines, resolve category from `Item.budgetCategoryId`.
- For transaction-sourced lines, resolve category from
  `Transaction.budgetCategoryId`.
- For manual New Charge lines, require explicit budget category in the UI.
- Block invoice save or collection when any selected line cannot resolve a
  category.
- Update invoice display/report code to preserve/render line category where
  useful.

Data audit before write changes:

- Scan invoiceable items missing `budgetCategoryId`.
- Scan invoiceable transactions missing `budgetCategoryId`.
- Scan existing invoice lines that cannot resolve a category from their source.
- Scan manual lines, which currently have no category field.

Verification:

- Draft invoice can include item, transaction, and manual lines with categories.
- New Charge cannot be added without a category.
- Existing draft/sent/paid invoices still render.

## Phase 2 - Categorized Collection

Goal: replace one broad Fee settlement transaction with one or more categorized
`paymentToBusiness` transactions.

Code work:

- Change `InvoiceService.markCollected` to write `paymentToBusiness`, not `fee`.
- Group settled invoice lines by `budgetCategoryId`.
- Create one settlement transaction per category group.
- Set `settlementInvoiceId` on every created payment transaction.
- Set `settlementInvoiceLineIds` to the line IDs included in that category group.
- Require each created settlement transaction to have `budgetCategoryId`.
- Remove the current single "first fee category" lookup in `InvoiceDetailView`.

Verification:

- Single-category invoice collection creates one `paymentToBusiness`.
- Multi-category invoice collection creates one `paymentToBusiness` per category.
- Settlement transactions do not re-enter billable pool.
- Billing summary subtracts settlement totals correctly.

## Phase 3 - Credit Flow For Returned-After-Collected Items

Goal: remove the current `expense`-transaction credit workaround.

Code work:

- Stop `InventoryOperationsService.appendPaidReturnCredits` from writing
  `type = expense`.
- Replace it with negative invoice demand / credit-line creation or a queued
  credit-line workflow.
- Keep credits distinct from settlement transactions.

Decision already made:

- This case is rare.
- It should be invoice credit demand, not an expense transaction.
- If money later actually moves back to the client, that refund/payment is a
  separate transaction.

Verification:

- Returning an item from a collected invoice creates/finds a credit path.
- The credit remains invoiceable.
- The credit is not excluded as settlement.

## Phase 4 - Production Category Cleanup

Goal: remove Mixed category dependence.

Run as dry-run first. Do not commit until the generated decision map is reviewed.

1584 category decisions:

| Existing row/source | Target category |
| --- | --- |
| BLVD Home | Furnishings |
| Art Explore / custom artwork | Furnishings |
| Cinema Works / install work | Install Services |
| Deni's Kitchens | Kitchen |
| Home Depot | Install Supplies |
| Lowe's | Install Supplies |
| ACE Hardware | Install Supplies |
| Dean Berryessa install rows | Install Services |
| Install Expenses bundled service row | Install Services |
| Speedway Gas | Fuel |
| FedEx receiving/tariff/freight-style rows | Storage & Receiving when project has it; otherwise Install Services |

Category shape work:

- Remove `supportedTypes = ["purchase", "return", "expense"]`.
- Preserve/repair category itemization metadata where needed.
- Align with existing category names where possible. Current 1584 preset names
  include `Install`, `Storage & Receiving`, `Fuel`, `Furnishings`, `Kitchen`,
  and `Design Fee`; do not create disconnected duplicates if rename/split is
  the cleaner path.

Verification:

- No Mixed category remains in production presets.
- Existing linked transactions still appear under the intended project/category.
- Itemized rows that need item detail are flagged for item backfill.

## Phase 5 - Transaction Data Migration

Goal: migrate stored transaction event types and approved legacy string variants.

All scripts must support dry-run and emit a reviewed JSONL decision log before
commit.

Type migrations:

- `expense -> purchase` for project-cost rows.
- Historical 1584 Design `fee -> paymentToBusiness`.
- Assiist Biz is a playground account; do not use it as the production migration
  model.
- Legacy `to inventory` row: inspect and migrate/read-normalize to `return` if
  it represents project-to-inventory return.

Design-fee source cleanup:

- Prefer no `source` for historical design-fee/payment rows.
- If a source is required by validation/display, set `source = "1584 Design"`.
- Replace `1584 Design Inventory` on design-fee/payment rows.

Approved string normalizations:

`purchasedBy`:

| Current | Target |
| --- | --- |
| `Client` | `client-card` |
| `Design Business` | `design-business` |
| empty string | missing/null |
| `client-card` | keep |
| `design-business` | keep |

`reimbursementType`:

| Current | Target |
| --- | --- |
| `Client Owes Design Business` | `owed-to-company` |
| `Design Business Owes Client` | `owed-to-client` |
| empty string | missing/null |
| `owed-to-company` | keep |
| `owed-to-client` | keep |
| `none` | keep unless a later code pass chooses nil as the canonical none |

Verification:

- No production `expense` rows remain after commit.
- No production `fee` rows remain after commit, except any intentionally retained
  legacy/playground rows.
- No design-fee/payment row has source `1584 Design Inventory`.
- Approved string variants no longer appear in production data.
- Budget totals and billing summaries match expected before/after deltas.

## Phase 6 - Read Compatibility Cleanup

Goal: remove legacy branches only after data and new writes are safe.

Code work:

- Remove `fee` and `expense` from normal UI choices and write APIs.
- Keep or remove decode compatibility based on whether any historical/playground
  data remains.
- Remove Mixed category shape handling from helpers and display.
- Update MCP schema/prompts/tools to stop advertising/writing `Fee`, `Expense`,
  and Mixed.
- Retire or mark obsolete the old fee/expense migration scripts.

Verification:

- iOS build and tests pass.
- MCP schema no longer presents old transaction types as normal write options.
- Searches/filters/cards still render migrated historical rows correctly.

## Ship Gates

Do not run production commits until all of these are true:

- New write paths are fixed first.
- Dry-run output is reviewed.
- Scripts produce per-document logs.
- There is a backup/rollback plan.
- We have counts before and after:
  - transaction type counts
  - Mixed category count
  - invoice lines missing category
  - itemized-category transactions missing items
  - approved legacy string variants

## Code Impact Pass

This is the file-level work that has to move together. The earlier phases are
the sequencing; this section is the implementation checklist.

### Shared Models And Taxonomy Helpers

Files:

- `LedgeriOS/LedgeriOS/Models/Shared/Enums.swift`
- `LedgeriOS/LedgeriOS/Models/Transaction.swift`
- `LedgeriOS/LedgeriOS/Models/BudgetCategory.swift`
- `LedgeriOS/LedgeriOS/Models/BudgetProgress.swift`
- `LedgeriOS/LedgeriOS/Models/Project.swift`

Required changes:

- Add `paymentToBusiness` as the only money-in transaction event type.
- Keep decode/read compatibility for existing `fee`, `expense`, and legacy
  `to inventory` values until data migration is complete.
- Remove `fee` and `expense` from normal picker/write surfaces.
- Make `purchase` mean an actual money-out purchase of goods or services,
  whether paid by the client or the design business.
- Keep itemization category-driven. Do not add a transaction-level itemized flag.
- Require `budgetCategoryId` on every transaction write except any explicitly
  documented inventory/account-level exception.
- Replace helpers that infer fee/expense semantics from category shape with
  helpers that distinguish category usage from existing category metadata and
  transaction context:
  - itemized project cost categories,
  - non-itemized project cost categories,
  - categories used by payment-to-business invoice settlement.
- Remove Mixed as a normal category shape. Temporary read compatibility can
  render it, but no code path should create it.

Known cleanup targets:

- `TransactionTaxonomy.resolve` currently preserves the old fee/expense model.
  It needs a migration-only role or removal once stored rows are migrated.
- `BudgetCategory.resolvedSupportedTypes` still falls back from legacy
  `metadata.categoryType`. That fallback is acceptable only during migration.
- `Project.CategorySummary.resolvedSupportedTypes` still defaults unknown legacy
  category summaries to a mixed shape. That should be narrowed after category
  data is cleaned.

Verification:

- Model codable tests cover new and legacy raw values.
- `TransactionType.allCases` no longer drives UI choices that include legacy
  values.
- A legacy `fee` row renders, but no new normal app path writes `fee`.

### Transaction Creation And Editing

Files:

- `LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift`
- `LedgeriOS/LedgeriOS/Views/Creation/ItemEntryFlowView.swift`
- `LedgeriOS/LedgeriOS/Modals/EditTransactionDetailsModal.swift`
- `LedgeriOS/LedgeriOS/Components/Modals/CategoryFormModal.swift`
- `LedgeriOS/LedgeriOS/Views/Settings/BudgetCategoryManagementView.swift`
- `LedgeriOS/LedgeriOS/Modals/EditProjectModal.swift`

Required changes:

- New transaction creation should offer purchase/return only for ordinary user
  entry. `sale` remains inventory-operation-only. `paymentToBusiness` is created
  by invoice collection, not by the normal purchase wizard unless a separate
  product decision adds a direct payment-entry flow.
- Business-paid purchase routes through inventory only when the selected
  category is itemized and actual item rows exist.
- Non-itemized purchases, including services, must never show the sell-from-
  inventory path.
- Category filtering must not use Mixed support as proof that a transaction is
  itemized.
- Category management must stop creating legacy fee/expense/Mixed
  `supportedTypes` shapes as normal options once the final category metadata
  handling is implemented.
- Edit transaction details must normalize legacy `purchasedBy` and
  `reimbursementType` display/write values, but should not let the user mutate a
  migrated payment-to-business transaction into an invalid project cost.

Verification:

- Client-paid service purchase creates a purchase transaction with category and
  no source/inventory prompt.
- Design-business-paid service purchase creates a purchase transaction with no
  sell-from-inventory prompt.
- Design-business-paid itemized purchase with items can still offer inventory
  handling.
- Editing a legacy transaction does not re-save obsolete display strings.

### Invoice Model And Creation

Files:

- `LedgeriOS/LedgeriOS/Models/Invoice.swift`
- `LedgeriOS/LedgeriOS/Logic/InvoiceLineCalculations.swift`
- `LedgeriOS/LedgeriOS/Modals/CreateInvoiceModal.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/FinancesTabView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift`

Required changes:

- Add `budgetCategoryId` to `InvoiceLine`.
- `makeLine(item:)` copies `Item.budgetCategoryId`.
- `makeLine(transaction:)` copies `Transaction.budgetCategoryId`.
- Manual New Charge lines require an explicit budget category picker.
- Invoice creation/editing must block save when any line lacks a category.
- Manual lines can represent planned design fees because invoices are demand;
  they must not create transactions until collection.
- Returned-after-collected item credits should be modeled as negative invoice
  demand / credit lines, not expense transactions.
- Billable membership must exclude settlement/payment transactions and include
  legitimate non-itemized project-cost purchases.

Verification:

- Invoice draft with items, non-itemized purchases, and manual charges stores a
  category on every line.
- Missing source category blocks invoice save with a clear UI state.
- Manual New Charge cannot be saved without a category.
- Existing invoices without line categories still render during migration, but
  are flagged by audit scripts.

### Invoice Collection And Settlement

Files:

- `LedgeriOS/LedgeriOS/Services/InvoiceService.swift`
- `LedgeriOS/LedgeriOS/Services/Protocols/InvoiceServiceProtocol.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/InvoiceDetailView.swift`
- `LedgeriOS/LedgeriOS/Logic/BillingSummaryCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/FinancialAccessPolicy.swift`
- `LedgeriOS/LedgeriOS/Views/Settings/UsersView.swift`

Required changes:

- Replace single fee transaction settlement with grouped
  `paymentToBusiness` transactions.
- `markCollected` should return multiple transaction IDs or a settlement result,
  not a single transaction ID.
- Group collected invoice lines by `budgetCategoryId`.
- Each settlement transaction stores:
  - `type = paymentToBusiness`,
  - the grouped `budgetCategoryId`,
  - `settlementInvoiceId`,
  - `settlementInvoiceLineIds`.
- Remove the `InvoiceDetailView` lookup for the first fee category.
- Billing summary must treat `paymentToBusiness` as collected money, not
  invoiceable spend and not budget spend.
- Financial access rules and user settings currently speak in fee-category
  terms. They need to be renamed or reframed around company revenue/payment
  categories while preserving the intended permission boundary.

Verification:

- Single-category invoice collection creates one payment transaction.
- Multi-category invoice collection creates one payment transaction per
  category.
- Settlement rows do not appear as invoiceable charges.
- Limited financial-access users retain the intended invoice/payment visibility.

### Budget, Reports, Cards, Search, And Export

Files:

- `LedgeriOS/LedgeriOS/Logic/BudgetTabCalculations.swift`
- `LedgeriOS/LedgeriOS/Services/BudgetProgressService.swift`
- `LedgeriOS/LedgeriOS/Logic/BudgetTrackerCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/TransactionDisplayCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/TransactionCardCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/TransactionNextStepsCalculations.swift`
- `LedgeriOS/LedgeriOS/Components/SharedTransactionsList.swift`
- `LedgeriOS/LedgeriOS/Components/TransactionFilterMenu.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift`
- `LedgeriOS/LedgeriOS/Logic/SearchCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/ExportFieldConfig.swift`
- `LedgeriOS/LedgeriOS/Logic/TransactionExportCalculations.swift`

Required changes:

- Budget spend math must count:
  - `purchase` as positive project cost,
  - `return` as negative project cost,
  - inventory `sale` as negative project cost where current specs define that,
  - `paymentToBusiness` as collected money, not project spend.
- Replace fee/expense labels in cards, filters, search, and export with the new
  taxonomy labels.
- Itemized audit and next-step logic must use category itemization plus item
  presence, not transaction type alone.
- Report aggregation must include non-itemized purchases as invoiceable cost
  lines and exclude settlement/payment rows.
- Project list budget summaries should not treat `paymentToBusiness` as over/under
  spend.

Verification:

- Budget totals before/after migration have explainable deltas only.
- Payment-to-business rows appear in revenue/collection context, not as project
  costs.
- Transaction filters still allow finding migrated historical rows.
- Exports include canonical normalized values.

### Inventory Operations

Files:

- `LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift`
- `LedgeriOS/LedgeriOS/Modals/SellToProjectModal.swift`
- `LedgeriOS/LedgeriOS/Modals/SellToBusinessModal.swift`
- `LedgeriOS/LedgeriOS/Views/Creation/NewItemView.swift`
- `LedgeriOS/LedgeriOS/Modals/AddExistingItemsPicker.swift`

Required changes:

- Keep inventory movement transaction semantics aligned with inventory specs:
  purchase for inventory-to-project, return for returning inventory-originated
  items, sale for business acquiring project-originated items.
- Do not use `expense` for returned-after-collected credits.
- Make any "mixed" wording in this layer refer only to mixed item origins inside
  an inventory batch, not Mixed budget categories.
- Confirm item category assignment is destination-category-driven and wiped when
  items move back into inventory.

Verification:

- Inventory-to-project creates purchase rows with destination category.
- Project-to-inventory return/sale rows preserve source accounting category.
- Returned-after-collected item path creates credit demand, not expense rows.

### MCP Server

Files:

- `mcp-server/src/types.ts`
- `mcp-server/src/util/enums.ts`
- `mcp-server/src/util/budget.ts`
- `mcp-server/src/index.ts`
- `mcp-server/src/http.ts`
- `mcp-server/src/resources/index.ts`
- `mcp-server/src/tools/schema.ts`
- `mcp-server/src/tools/invoices.ts`
- `mcp-server/src/tools/transactions.ts`
- `mcp-server/src/tools/budget.ts`
- `mcp-server/src/tools/projects.ts`
- `mcp-server/src/tools/inventory-operations.ts`
- `mcp-server/src/util/projections.ts`

Required changes:

- Update schemas and prompts so agents stop advertising Fee, Expense, and Mixed
  as normal write concepts.
- Add `paymentToBusiness` to transaction type definitions.
- Add `budgetCategoryId` to invoice line schemas.
- Invoice tools must require categories on manual lines and grouped collection.
- MCP invoice collection tools must create categorized payment transactions, not
  one Fee transaction.
- Budget/category utilities must stop deriving Mixed as a default normal shape.
- Keep read compatibility only where necessary for legacy documents.

Verification:

- MCP schema resource describes purchase/return/sale/paymentToBusiness.
- MCP `mark_invoice_collected` and line-collection tools produce grouped
  payment transactions.
- MCP-created invoice manual lines cannot omit `budgetCategoryId`.

### Migration Scripts And Production Data

Existing scripts to retire or supersede:

- `scripts/migrate-transactions-to-fee-expense.mjs`
- `scripts/migrate-transaction-types-stage1.mjs`
- `scripts/migrate-transaction-types-stage2.mjs`
- `scripts/migrate-transaction-types-stage3.mjs`

New or updated scripts:

- Audit invoiceable items, transactions, and invoice lines missing category.
- Dry-run Mixed category transaction decision map using the user-approved
  category assignments.
- Dry-run transaction type migration:
  - `expense -> purchase` for project-cost rows,
  - historical 1584 Design `fee -> paymentToBusiness`,
  - inspect/migrate legacy `to inventory`.
- Dry-run approved string normalization for `purchasedBy` and
  `reimbursementType`.
- Dry-run design-fee source cleanup from `1584 Design Inventory` to missing
  source or `1584 Design` if validation requires a value.
- Optional invoice-line category backfill script after the invoice model lands.

Verification:

- Every script supports dry-run and commit modes.
- Every commit mode writes a JSONL per-document decision log.
- Before/after counts are captured in the migration impact audit.
- Production scripts are account-aware and do not treat Assiist Biz playground
  data as production policy.

### Specs And Tracking Docs

Files:

- `docs/specs/transaction-type.md`
- `docs/specs/transaction-creation.md`
- `docs/specs/billing-invoicing.md`
- `docs/specs/data-model.md`
- `docs/specs/financial-access-controls.md`
- `docs/specs/project-closeout-report.md`
- `docs/specs/transaction-completeness.md`
- `docs/specs/sale-transactions.md`
- `docs/specs/inventory-as-store.md`
- `docs/specs/_app-map.md`
- `docs/plans/transaction-taxonomy-system-design-recommendation.md`
- `docs/plans/transaction-taxonomy-migration-impact-audit.md`
- `docs/plans/transaction-taxonomy-open-decisions.md`
- `docs/plans/inventory-routing-taxonomy-remediation.md`

Required changes:

- Remove the old claim that fee/expense are transaction types in the target
  state.
- Remove Mixed budget categories as a supported product concept.
- Keep "mixed" only where it means mixed inventory item origins or batches, and
  spell that out to avoid collision with budget category taxonomy.
- Update invoice docs to say collection creates categorized
  `paymentToBusiness` rows.
- Update access-control docs from fee-category language to the final
  revenue/payment visibility language.
- Update data model docs with `InvoiceLine.budgetCategoryId` and normalized
  transaction type values.

Verification:

- `rg "fee|expense|Mixed|mixed|paymentToBusiness|InvoiceLine|supportedTypes"`
  over specs no longer shows contradictory target-state claims.

### Test Pass

Test targets to update or add:

- `LedgeriOSTests/ModelCodableTests.swift`
- `LedgeriOSTests/BudgetCalculationTests.swift`
- `LedgeriOSTests/BudgetTabCalculationTests.swift`
- `LedgeriOSTests/BillingSummaryCalculationTests.swift`
- `LedgeriOSTests/FinancialAccessPolicyTests.swift`
- `LedgeriOSTests/TransactionDisplayCalculationTests.swift`
- `LedgeriOSTests/TransactionCardCalculationTests.swift`
- `LedgeriOSTests/SearchCalculationsTests.swift`
- `LedgeriOSTests/ExportFieldConfigTests.swift`
- `LedgeriOSTests/InventoryOperationsExecutionTests.swift`
- Add or extend invoice-line calculation tests for line categories and grouped
  settlement.

Required scenarios:

- Legacy decode for `fee`, `expense`, and `to inventory`.
- New write values reject/avoid legacy types.
- Invoice manual line requires category.
- Grouped invoice collection creates one payment per category.
- Payment-to-business is excluded from project spend and billable pool.
- Non-itemized purchase remains invoiceable.
- Itemized purchase without items is flagged by category/item logic.
- Returned-after-collected item creates invoice credit demand, not expense.

## Immediate Next Work

1. Finish Phase 0 code guards that are already partially implemented:
   - `paymentToBusiness` enum/read compatibility,
   - no fee/expense normal picker writes,
   - no Mixed category creation,
   - inventory routing limited to itemized categories with actual items.
2. Implement the invoice model change:
   - add `InvoiceLine.budgetCategoryId`,
   - require manual New Charge category,
   - block invoice save/collection for missing categories.
3. Update invoice collection:
   - grouped `paymentToBusiness` writes,
   - protocol/signature changes,
   - billing summary and access-control follow-through.
4. Build the invoice/category audit script for missing categories.
5. Build dry-run-only migration scripts for:
   - Mixed category transaction decision map
   - transaction type migration
   - approved string normalization
   - design-fee source cleanup
6. Update MCP schemas/tools so external writes follow the same taxonomy.
7. Update specs and tests, then run the iOS test/build pass plus MCP checks.
8. Review dry-run output before any production commit.
