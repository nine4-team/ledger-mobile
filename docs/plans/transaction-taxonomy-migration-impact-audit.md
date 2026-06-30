# Transaction Taxonomy Migration Impact Audit

Created: 2026-06-26

This is the impact audit for migrating the app toward the system proposed in
`docs/plans/transaction-taxonomy-system-design-recommendation.md`.

Execution plan: `docs/plans/transaction-taxonomy-execution-plan.md`

Target transaction types:

- `purchase`: money spent to buy goods or services. Itemization is determined by budget category, not transaction type.
- `return`: money/item value leaves the project because a prior purchase is reversed.
- `sale`: project-originated items sold/moved back to business inventory.
- `paymentToBusiness`: money received by the business from the client.

Long-term removals:

- Remove `expense` as a transaction type. These become `purchase` plus category semantics.
- Remove `fee` as a transaction type. Planned fees are invoice demand, represented
  by categorized manual New Charge lines. Actual collected client money becomes
  categorized `paymentToBusiness` settlement transaction(s).
- Remove Mixed category support. A category should not accept both itemized purchase/return and non-itemized expense behavior.

## Live Data Snapshot

Source: `GOOGLE_APPLICATION_CREDENTIALS=/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json node scripts/audit-transaction-taxonomy-impact.mjs`

Firestore project: `ledger-nine4`

Totals:

| Area | Count |
| --- | ---: |
| Accounts | 5 |
| Transactions | 621 |
| Transactions with items | 332 |
| Invoices | 2 |
| Settlement transactions | 1 |
| Budget category docs | 89 |
| Mixed category docs | 3 |

Transaction type counts:

| Type | Count | Migration impact |
| --- | ---: | --- |
| `purchase` | 500 | Keep as `purchase`; itemized vs non-itemized must come from category. |
| `return` | 71 | Keep as `return`; verify inventory/vendor-return semantics still work. |
| `sale` | 25 | Keep as `sale`; verify legacy canonical sale handling remains read-compatible. |
| `expense` | 15 | Migrate to `purchase` after category/reporting logic can distinguish non-itemized costs. |
| `fee` | 9 | Split: settlement/payment rows become `paymentToBusiness`; planned/charged fees need invoice/project-charge/manual-line migration or an explicit historical-read plan. |
| `to inventory` | 1 | Legacy value; migrate/read-normalize to `return` if it represents project-to-inventory return. |

Account distribution:

| Account | Transactions | Types present |
| --- | ---: | --- |
| 1584 Design | 565 | `expense` 15, `fee` 8, `purchase` 455, `return` 68, `sale` 19 |
| Assiist Biz | 56 | Playground account: `fee` 1, `purchase` 45, `return` 3, `sale` 6, `to inventory` 1 |
| Other accounts | 0 | None |

Item presence by type:

| Shape | Count |
| --- | ---: |
| `purchase` with items | 263 |
| `purchase` without items | 237 |
| `return` with items | 43 |
| `return` without items | 28 |
| `sale` with items | 25 |
| `expense` without items | 15 |
| `fee` without items | 9 |
| `to inventory` with items | 1 |

Important: `itemIds` being empty does not prove a transaction is non-itemized. We have already found item-capable transactions where items are missing and need data repair/backfill rather than type conversion.

## Data Impact

### `fee` Rows

Current live data has 9 `fee` transactions:

- 1 settlement transaction in the Assiist Biz playground account:
  `accounts/2d612868-852e-4a80-9d02-9d10383898d4/transactions/9CBBD11A-6E17-4261-A9E5-80277402954E`,
  source `Collected CODEx E2E Invoice`, `settlementInvoiceId =
  1FA36F78-02C3-4779-AC43-2D2370F0AB5B`. This proves the existing settlement
  shape but should not drive production 1584 data decisions.
- 8 in 1584 Design, all Design Fee rows. They read like historical design-fee
  invoice/payment records, not item/inventory movements. Several use source
  `1584 Design Inventory`, which is likely bad source labeling from the old fee
  flow.

1584 Design `fee` rows needing migration review:

| Date | Source | Amount | Project | Notes |
| --- | --- | ---: | --- | --- |
| 2025-09-10 | 1584 Design | $16,325.00 | Hyer's Martinique Rental | Initial Design Fee |
| 2025-09-20 | 1584 Design Inventory | $4,905.00 | Sandra- BAHAMA Unit | Design fee initial payment |
| 2025-12-26 | 1584 Design | $8,163.00 | Hyer's Martinique Rental | 2nd Design Fee Payment |
| 2026-04-15 | 1584 Design Inventory | $11,400.00 | Kapcsos Martinique Rental | Initial Design Planning Fee |
| 2026-04-30 | 1584 Design Inventory | $4,905.00 | Sandra- BAHAMA Unit | Second design fee (board approval) payment |
| 2026-04-30 | 1584 Design Inventory | $7,358.00 | Sandra- BAHAMA Unit | Third designed fee (procurement) payment |
| 2026-04-30 | 1584 Design Inventory | $3,679.00 | Sandra- BAHAMA Unit | Fourth design fee (install initiation) payment |
| 2026-04-30 | 1584 Design Inventory | $9,850.00 | Kapcsos Martinique Rental | 2nd Design Fee (Procurement Phase) |

Source cleanup rule: design-fee/payment rows should not use an inventory source.
Prefer no `source`; if the transaction model or display requires one, use
`1584 Design`.

Migration risk:

Decision:

- The 1584 Design `fee` rows already exist as historical transactions in the
  database. Treat them as historical payment transactions and migrate them to
  categorized `paymentToBusiness`.
- Do not convert these existing transaction rows into invoice demand.
- Inventory-source fee labeling is bad historical source data. Prefer clearing
  `source`; if a source is required by validation or display, set it to
  `1584 Design`.

### `expense` Rows

Current live data has 15 `expense` transactions:

- 13 are already in expense-only categories.
- 2 are in Mixed categories:
  - Kitchen: `Deni's Kitchens`, 2026-04-30, $5,000.00, client-card
  - Install: `Dean Berryessa- wallpaper install`, 2026-06-09, $5,250.00, client-card

Migration rule:

- `expense` should become `purchase`, not because it is itemized, but because `purchase` means money spent to buy goods/services.
- Non-itemized behavior must remain category-driven. These rows still need to behave as service/labor/fuel/storage cost rows after their type changes.

Code blocker:

- `InventoryOperationsService.appendPaidReturnCredits` still writes `type =
  expense` for paid-return credits. This should be redesigned as negative invoice
  demand / a credit line before removing `expense`, because the credit is not a
  new purchase expense.

### Mixed Categories

Current live data has exactly 3 Mixed categories, all in 1584 Design:

| Category | ID | Linked tx count | Notes |
| --- | --- | ---: | --- |
| Additional Requests | `1aa4b56b-2ff2-4377-b5fa-f7b8650ca9c0` | 4 | BLVD Home and custom artwork move to Furnishings; install work moves to Install Services. |
| Kitchen | `c7aab919-08c3-4407-a6ba-7c20d9e7f6ea` | 4 | Deni's Kitchens rows stay Kitchen. |
| Install | `e1a7af0c-407a-4fd0-9c21-573b90374b53` | 11 | Split/rename into Install Services, Install Supplies, Fuel, and Receiving fallback rules. |

Mixed transactions:

- 17 `purchase`
- 2 `expense`
- 1 with items: Home Depot, 2026-04-30, $44.71, category Install, 4 items.
- 18 without items, but several are probably supposed to contain items and should not be auto-converted to non-itemized.

Required cleanup:

- Split or reclassify Mixed category behavior before type migration.
- Settled transaction-level mapping:
  - BLVD Home -> Furnishings.
  - Custom artwork -> Furnishings.
  - Cinema Works / install work -> Install Services.
  - Deni's Kitchens -> Kitchen.
  - Home Depot, Lowe's, ACE, and similar supply rows -> Install Supplies.
  - Dean install rows and bundled install service rows -> Install Services.
  - Speedway Gas -> Fuel.
  - FedEx receiving/tariff/freight-style rows -> Receiving when the project has
    that category; otherwise Install Services.
- Do not keep app logic that treats `purchase + return + expense` as a valid supportedTypes shape.

### Category Taxonomy Fields

Current category shape counts:

| `supportedTypes` shape | Count |
| --- | ---: |
| missing | 80 |
| `purchase+return` | 1 |
| `expense` | 3 |
| `fee` | 2 |
| `expense+purchase+return` | 3 |

Current `metadata.categoryType` counts:

| Metadata type | Count |
| --- | ---: |
| missing | 77 |
| `itemized` | 5 |
| `fee` | 5 |
| `standard` | 2 |

Migration risk:

- Current iOS read fallback treats missing category taxonomy as item-capable in `BudgetCategory.resolvedSupportedTypes`.
- Many category docs are project copies with missing taxonomy fields. Migration must identify the canonical source of truth for category taxonomy and backfill project copies or stop relying on project copies for itemization decisions.
- `metadata.categoryType` is still the clearest legacy itemization signal where present. It should not be cleared until all read paths use a new explicit replacement.

### `purchasedBy` and `reimbursementType`

Live `purchasedBy` values:

- `client-card`: 355
- `design-business`: 114
- missing: 120
- legacy/display variants: `Client` 24, `Design Business` 6, empty string 2

Live `reimbursementType` values:

- missing: 512
- `none`: 28
- `owed-to-company`: 26
- `owed-to-client`: 8
- legacy/display variants: `Client Owes Design Business` 42, `Design Business Owes Client` 5

Migration impact:

- Normalize legacy/display reimbursement values before relying on reports or invoice eligibility.
- Normalize `purchasedBy` variants before using it for route/invoice behavior.
- Do not use `reimbursementType` as a substitute for transaction type. It answers who ultimately owes whom, not whether the transaction is an itemized purchase.

### Invoices and Settlement

Live invoices:

- 2 total: 1 draft, 1 paid.
- 1 settlement transaction, currently `type = fee`.

Migration impact:

- Settlement transactions should become `paymentToBusiness`.
- Every settlement transaction must carry a `budgetCategoryId`.
- Invoice collection code must stop creating one broad `fee` transaction.
- Invoice collection should create one `paymentToBusiness` transaction per budget
  category represented by the settled invoice lines.
- Manual New Charge lines must require an explicit budget category; no silent
  default category.
- Invoice-line and billing-summary calculations must continue excluding settlement transactions from billable demand.
- Historical paid invoices without settlement transactions must still be supported by summary fallback logic.

## Code Impact

### iOS Models

Files:

- `LedgeriOS/LedgeriOS/Models/Shared/Enums.swift`
- `LedgeriOS/LedgeriOS/Models/Transaction.swift`
- `LedgeriOS/LedgeriOS/Models/BudgetCategory.swift`

Impacts:

- Add `TransactionType.paymentToBusiness`.
- Remove `fee` and `expense` from write paths after data migration; keep temporary decode/read compatibility if needed.
- Fix `Transaction.needsItemizedAudit`; it currently keys off `purchase || return`, but itemized audit must be category-driven.
- Keep or replace `BudgetCategory.metadata.categoryType` as the explicit itemization source. If replaced, migrate all code and data at once.
- Remove Mixed support from `BudgetCategory.resolvedSupportedTypes`, `CategoryDisplay`, and taxonomy helpers.
- Update `TransactionTaxonomy.resolve`; it currently maps `purchase + fee/expense category` into `fee`/`expense`, which is the old model.

### iOS Creation and Editing

Files:

- `LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift`
- `LedgeriOS/LedgeriOS/Views/Creation/ItemEntryFlowView.swift`
- `LedgeriOS/LedgeriOS/Components/Modals/CategoryFormModal.swift`
- `LedgeriOS/LedgeriOS/Modals/EditTransactionDetailsModal.swift`
- `LedgeriOS/LedgeriOS/Modals/ImportInvoiceModal.swift`

Impacts:

- Type picker should expose only approved transaction types for normal creation.
- Normal transaction creation should not offer inventory sale routing unless the selected category is itemized and `purchasedBy == design-business`.
- Tax/subtotal/item entry fields must be category-driven, not transaction-type-driven.
- Category form must not create Mixed categories.
- Editing existing Mixed categories must not silently rewrite them to a wrong category shape; either block edit with an explicit cleanup prompt or migrate first.
- Import flow must preserve itemized category behavior when imported invoices create items/transactions.

### iOS Invoicing and Billing

Files:

- `LedgeriOS/LedgeriOS/Services/InvoiceService.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/InvoiceDetailView.swift`
- `LedgeriOS/LedgeriOS/Logic/InvoiceLineCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/BillingSummaryCalculations.swift`
- `LedgeriOS/LedgeriOS/Modals/CreateInvoiceModal.swift`

Impacts:

- `InvoiceService.markCollected` currently writes `type = TransactionType.fee.rawValue`. It must write categorized `paymentToBusiness` transaction(s).
- `InvoiceDetailView` currently selects a single fee category for collection. It
  must instead group settled invoice lines by budget category and create one
  settlement transaction per category.
- `InvoiceLine` currently has no `budgetCategoryId`; manual New Charge lines
  need an explicit category, and item/transaction sourced lines need a reliable
  category resolver.
- `InvoiceLineCalculations` already excludes settlement transactions by `settlementInvoiceId`; keep that behavior.
- `BillingSummaryCalculations.isNonItemized` currently treats any transaction without items as directly billable. That needs category/type review so missing itemized data does not become an invoiceable service line by accident.
- Manual invoice lines take over planned fee demand when `fee` transactions are removed.

### iOS Budget, Reports, and Display

Files:

- `LedgeriOS/LedgeriOS/Logic/BudgetTabCalculations.swift`
- `LedgeriOS/LedgeriOS/Services/BudgetProgressService.swift`
- `LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/FinancialAccessPolicy.swift`
- `LedgeriOS/LedgeriOS/Logic/TransactionDisplayCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/TransactionCardCalculations.swift`
- `LedgeriOS/LedgeriOS/Components/SharedTransactionsList.swift`
- `LedgeriOS/LedgeriOS/Components/TransactionFilterMenu.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift`

Impacts:

- Budget normalization currently handles return/sale direction but assumes everything else is positive spend. `paymentToBusiness` must not inflate project spend.
- Fee-category filtering and limited financial access currently uses `TransactionTaxonomy.resolve(... ) == .fee`; that needs a new rule for invoice/project-charge visibility.
- Report invoiceability currently uses `reimbursementType` plus settlement exclusion. It needs to survive `expense -> purchase` and `fee -> paymentToBusiness/manual line`.
- Search/filter/card labels need updated labels and legacy mapping.
- Project lists and budget cards must keep itemized/non-itemized display based on category, not transaction type.

### Inventory Operations

Files:

- `LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift`
- `LedgeriOS/LedgeriOS/Modals/SellToProjectModal.swift`
- `LedgeriOS/LedgeriOS/Modals/SellToBusinessModal.swift`
- `LedgeriOS/LedgeriOS/Logic/IncompleteReturnDetection.swift`
- `LedgeriOS/LedgeriOS/Logic/TransactionNextStepsCalculations.swift`

Impacts:

- Inventory movement types remain `purchase`, `return`, and `sale`.
- The sell-from-inventory prompt must remain limited to itemized business-paid purchases with actual items.
- `appendPaidReturnCredits` currently creates `expense` rows for paid return credits. That must be redesigned as invoice credit/manual adjustment or another explicit mechanism before `expense` is removed.
- Next-step/audit logic must distinguish missing items in itemized categories from valid non-itemized service purchases.

### MCP Server and External Writes

Files:

- `mcp-server/src/util/enums.ts`
- `mcp-server/src/index.ts`
- `mcp-server/src/http.ts`
- `mcp-server/src/types.ts`
- `mcp-server/src/util/budget.ts`
- MCP transaction/invoice tools under `mcp-server/src`

Impacts:

- MCP enum still presents `Fee`, `Expense`, and `To Inventory` as transaction types.
- MCP prompt still says invoice collection creates a Fee transaction.
- MCP category enums (`general`, `labor`, `materials`, `fees`, `reimbursable`) do not match current iOS category taxonomy (`general`, `itemized`, `fee`, `expense`) or the proposed future model.
- Any MCP create/update transaction tool must stop accepting/writing old taxonomy values after migration, or explicitly legacy-normalize them.
- MCP budget normalization must match the iOS budget/report rules exactly.

### Scripts and Migration Utilities

Files:

- `scripts/migrate-transactions-to-fee-expense.mjs`
- `scripts/revert-transactions-to-fee-expense.mjs`
- `scripts/migrate-categories-add-supported-types.mjs`
- `scripts/overrides/1584-categories.json`
- `scripts/audit-mixed-categories.mjs`
- `scripts/audit-transaction-taxonomy-impact.mjs`

Impacts:

- The existing fee/expense migration script represents the old direction and should be retired or clearly marked obsolete.
- A new migration script should be dry-run-first and produce per-row decisions for `fee`, `expense`, Mixed categories, and legacy `to inventory`.
- Category migration must avoid blindly converting Mixed rows.
- The audit script added with this doc should be kept as the baseline scanner and extended to export CSV/JSONL decision files if needed.

### Tests

Impacted test groups:

- `LedgeriOS/LedgeriOSTests/BudgetCalculationTests.swift`
- `LedgeriOS/LedgeriOSTests/BudgetTabCalculationTests.swift`
- `LedgeriOS/LedgeriOSTests/BillingSummaryCalculationTests.swift`
- `LedgeriOS/LedgeriOSTests/FinancialAccessPolicyTests.swift`
- `LedgeriOS/LedgeriOSTests/TransactionDisplayCalculationTests.swift`
- `LedgeriOS/LedgeriOSTests/ModelCodableTests.swift`
- `LedgeriOS/LedgeriOSTests/SearchCalculationsTests.swift`
- `LedgeriOS/LedgeriOSTests/ExportFieldConfigTests.swift`
- `LedgeriOS/LedgeriOSTests/InventoryOperationsExecutionTests.swift`

Required coverage:

- `expense` legacy rows read as purchase-like non-itemized costs after migration.
- `fee` settlement rows read/write as `paymentToBusiness`.
- Non-settlement historical fee rows do not become project spend by accident.
- Collected invoices with multiple categories create one `paymentToBusiness`
  transaction per category.
- Manual New Charge lines require explicit budget categories.
- Itemized category purchase with no items is flagged for item backfill/review, not auto-treated as non-itemized service cost.
- Non-itemized service purchase does not trigger sell-from-inventory.
- Mixed category creation is impossible.
- Legacy `to inventory` decodes or migrates without crashing transaction lists.

## Proposed Migration Work Order

1. Freeze taxonomy writes:
   - app creation stops writing `fee`, `expense`, or Mixed categories
   - invoice collection writes categorized `paymentToBusiness` transactions,
     one per settled budget category
   - New Charge/manual invoice lines require explicit budget category
   - MCP stops advertising/writing old taxonomy

2. Normalize read compatibility:
   - add `paymentToBusiness`
   - keep temporary decode support for `fee`, `expense`, and `to inventory`
   - route display/reporting through explicit legacy-normalization helpers

3. Clean category data:
   - eliminate Mixed categories by deliberate category decisions
   - backfill category taxonomy fields onto canonical category docs and any project copies still used by read paths

4. Clean transaction data:
   - map `expense -> purchase`
   - map settlement `fee -> paymentToBusiness`
   - map historical 1584 Design `fee` transaction rows to `paymentToBusiness`
   - normalize legacy `purchasedBy` and `reimbursementType` display strings
   - resolve the one `to inventory` row

5. Backfill itemized data:
   - identify itemized-category purchases/returns with empty `itemIds`
   - create/backfill item records where those transactions are supposed to contain items
   - only classify true service/labor rows as non-itemized category purchases

6. Remove old branches:
   - remove old `fee`/`expense` write support
   - remove Mixed category shape support
   - retire old migration scripts
   - update specs and MCP schema

## Decisions Still Needed

- For invoice settlement grouping, how should we handle selected lines with no
  resolvable budget category? This needs a prod scan and UI validation.
- Should category itemization remain `metadata.categoryType`, become a new explicit field, or be represented by a strict `supportedTypes == [purchase, return]` shape after cleanup?
