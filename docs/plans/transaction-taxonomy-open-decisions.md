# Transaction Taxonomy Open Decisions

Status: tracking
Created: 2026-06-26

Master tracker: [transaction-taxonomy-master-tracker.md](transaction-taxonomy-master-tracker.md)

## Why This Exists

The transaction/category model has drifted in ways that now affect inventory
routing, item entry, audit/completeness, category filtering, and production data.
This doc tracks the decisions that must be made before we keep patching around
the drift.

## Known Facts

- Original transaction type model was `purchase`, `sale`, and `return`.
- `fee` and `expense` were added to `TransactionType` on 2026-04-20 in commit
  `ed120edf` (`feat(ios): multi-type budget categories via supportedTypes`).
- The production rewrite script was added on 2026-04-20 in commit `d7aa0e14`
  (`feat(scripts): transaction-type migration scripts and backup config`).
- The 1584 production transaction migration ran on 2026-04-21 at
  `2026-04-21T00:20:11Z`.
- That migration touched 286 transaction rows:
  - 228 `Purchase -> purchase`
  - 40 `Return -> return`
  - 8 `Sale -> sale`
  - 8 `Purchase -> expense`
  - 2 `Purchase -> fee`
- The first committed migration only remapped:
  - Fuel: 7 transactions to `expense`
  - Storage & Receiving: 1 transaction to `expense`
  - Design Fee: 2 transactions to `fee`
- Production currently has 3 Mixed category docs in 1584 preset categories:
  - `Additional Requests`
  - `Kitchen`
  - `Install`
- Those 3 Mixed categories use `supportedTypes = ["purchase", "return", "expense"]`.
- Those 3 Mixed categories have 19 linked transactions.
- Many linked transactions have `itemIds = []` but are still likely intended to
  be itemized purchases. Missing item docs cannot be treated as proof that a
  transaction is non-itemized.

## Core Questions

### 1. Should transaction `type` include `fee` and `expense`?

Decision: no, not as long-term transaction event types.

Target event types are `purchase`, `return`, `sale`, and `paymentToBusiness`.
`expense` migrates to `purchase` plus category semantics. `fee` splits into
categorized invoice demand for planned/unpaid fees and categorized
`paymentToBusiness` transactions for actual client payments.

### 2. What is the canonical itemization signal?

Decision: budget category itemization.

Inventory routing uses:

```text
selected category is itemized/items
AND purchasedBy == design-business
AND actual items exist / are being created
```

`transaction.type == purchase` is not an itemization signal because services
and non-itemized costs can also be purchased.

### 3. Are Mixed categories allowed?

Decision: no.

- Remove Mixed as a supported category shape.
- Existing production Mixed rows must be repaired with an explicit decision map.
- Code may tolerate Mixed only as legacy/corrupt data during migration; it should
  not offer Mixed as a normal product path.

### 4. What should happen to 1584 `Additional Requests`?

Decision: move the item-like rows to Furnishings; install work goes to Install
Services.

Current production rows:

| Date | Source | Amount | Stored type | Items | Notes |
|---|---|---:|---|---:|---|
| 2026-03-30 | BLVD Home | $5,047.72 | purchase | 0 | 2 sets LG washers/dryers |
| 2026-03-30 | BLVD HOme | $6,831.93 | purchase | 0 | TVs & mounts |
| 2026-03-31 | Cinema Works | $410.00 | purchase | 0 | Installed TVs |
| 2026-06-16 | Art Explore | $1,728.99 | purchase | 0 | custom artwork |

Decision map:

- BLVD Home rows -> Furnishings.
- Art Explore custom artwork -> Furnishings.
- Cinema Works install work -> Install Services.
- Backfill item docs where rows are itemized purchases and the item detail is
  needed.

### 5. What should happen to 1584 `Kitchen`?

Decision: Deni's Kitchens rows stay Kitchen.

Current production rows:

| Date | Source | Amount | Stored type | Items | Notes |
|---|---|---:|---|---:|---|
| 2025-12-26 | Deni's Kitchens | $5,000.00 | purchase | 0 | Kitchen Supplies & Install |
| 2026-03-16 | Deni's Kitchens | $5,000.00 | purchase | 0 | |
| 2026-04-30 | Deni's Kitchens | $5,000.00 | expense | 0 | Kitchen install |
| 2026-05-02 | Deni's kitchens | $5,000.00 | purchase | 0 | |

Cleanup:

- Convert the stored `expense` row back to `purchase` as part of removing
  `expense` from transaction type.
- Backfill item docs only where Kitchen rows need item-level detail.

### 6. What should happen to 1584 `Install`?

Decision: split legacy Install behavior.

Current production rows include labor, freight/tariffs/gas, and material/supply
purchases.

Service/non-itemized rows:

- Dean Berryessa cash/invoices/wallpaper install
- Install Expenses: storage, delivery, movers, assembly, install crew
- FedEx receiving/tariff/freight-style rows, unless a project has a Receiving
  category

Supply/material rows:

- Home Depot: has 4 item docs.
- Lowe's: supplies/hooks/rods/etc., no item docs.
- ACE Hardware: install supplies, no item docs.

Decision map:

- Use `Install Services` for Dean install rows and bundled install service rows.
  Align this with the existing `Install` category during cleanup, likely by
  renaming/splitting the existing category rather than inventing a disconnected
  duplicate.
- Use `Install Supplies` for Home Depot, Lowe's, ACE, and similar supply rows.
- Use `Fuel` for Speedway Gas.
- Use `Receiving` for FedEx when the project has a Receiving category;
  otherwise use `Install Services`.
- Backfill item docs for supply rows only where item-level detail is needed.

### 7. How should invoice settlement categories work?

Decision: every transaction needs a `budgetCategoryId`.

- Manual New Charge lines must require an explicit budget category. No silent
  default.
- When an invoice is collected, create one `paymentToBusiness` transaction per
  budget category represented by the settled invoice lines.
- Remaining work: scan production for invoiceable items/transactions/manual-line
  paths with missing budget categories, because current invoice creation allows
  them.

### 8. How should returned-after-collected item credits work?

Decision: represent the client credit as negative invoice demand / a credit line,
not as an `expense` transaction.

This case should be rare, but `InventoryOperationsService.appendPaidReturnCredits`
currently writes `expense` transactions and must be redesigned before removing
`expense`.

### 9. What should happen to historical design-fee transaction sources?

Decision: design-fee/payment rows should not use an inventory source.

- Prefer no `source` for historical design-fee/payment rows.
- If a source is required by validation or display, use the business name, e.g.
  `1584 Design`.
- The Assiist Biz settlement row is from a playground account and should not
  drive production 1584 migration decisions.

## Code Work To Track

- `NewTransactionView` must not route through inventory from transaction type
  alone.
- `ItemEntryFlowView` must not show sell-from-inventory prompts when no items
  exist.
- Category creation must not offer Mixed.
- Category display/filtering must not normalize Mixed into a supported shape.
- Audit/completeness logic must be reviewed for whether it keys off transaction
  type or category itemization.
- Any repair script must be decision-map driven, not blanket `purchase -> expense`.

## Spec Work To Track

- Find and explain why specs introduced `fee` and `expense` as transaction
  types.
- Identify which specs still say `purchase` means itemized-only.
- Identify which specs say category shape is irrelevant to audit/completeness.
- Decide whether `docs/specs/transaction-type.md` is superseded, partially
  salvageable, or should be rewritten.
- Reconcile:
  - `docs/specs/item-entry-flow.md`
  - `docs/specs/transaction-creation.md`
  - `docs/specs/transaction-type.md`
  - `docs/specs/transaction-audit.md`
  - `docs/specs/budget-management.md`

## Production Data Work To Track

- Run `scripts/audit-mixed-categories.mjs` before and after any production repair.
- Do not run a blanket Mixed repair.
- Build an explicit transaction-level repair map after decisions above.
- Run an invoiceability/category audit to find invoiceable lines that cannot
  resolve a budget category.
- For every itemized transaction missing item docs, decide whether to:
  - backfill items,
  - leave as an itemized transaction with missing item detail,
  - or move it to a non-itemized category.

## Current Guardrail

Until decisions are made, do not introduce new Mixed categories, do not infer
itemization from `transaction.type == purchase`, and do not convert historical
item-looking purchases to non-itemized solely because `itemIds` is empty.
