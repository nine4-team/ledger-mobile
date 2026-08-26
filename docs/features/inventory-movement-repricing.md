# Inventory Movement Repricing

## Purpose

An item can be sold from business inventory into a project before its final markup is known. Editing that sold item's project price updates the amount of the separate project-side `Purchase` from inventory without touching the original vendor Purchase.

## Data Flow

1. `InventoryOperationsService.sellToProject` (or the matching MCP tool) creates a project-scoped `Purchase` whose initial subtotal is the sold items' normalized project prices and whose amount includes their per-item tax.
2. The sell batch changes the item's project and transaction association. That association change is not a repricing event; the transaction was already created with the correct initial amount.
3. A later item update with the same non-null `projectId` and `transactionId` triggers `onItemPriceChanged`.
4. The trigger verifies that the associated transaction is a non-legacy project-side Purchase whose source ends in ` Inventory`.
5. If the item was not already locked by a paid invoice, the trigger atomically applies the item's subtotal and tax-inclusive amount deltas to the transaction.
6. `onTransactionWritten` recalculates the existing project budget summary. Firestore listeners refresh transaction cards, exports, search results, and budget screens through their existing transaction reads.

## Safety Contract

- Item fields contain prices; transaction fields contain amounts.
- Original vendor Purchases are never selected because they are not project-scoped Purchases from an inventory-labeled source.
- Project-to-inventory Sales and Returns are never selected.
- Direct client and MCP edits to movement `amountCents` and `subtotalCents` remain prohibited.
- The adjustment is a delta for one stable item association. Never recompute the whole transaction from `itemIds`, because that array contains only active membership and may omit items that left later.
- Cloud event IDs are recorded in `accounts/{accountId}/transactionRepricingEvents/{eventHash}` in the same Firestore transaction as the amount update. Retried delivery cannot apply a delta twice, and separate deltas commute if events arrive out of order.
- Created and sent invoices remain live under the active billing model. A paid invoice locks the project price and movement amount for that item.
- A delayed price event that occurred before collection may still apply; the trigger compares the item document update time with `invoice.datePaid`.
- Transactions missing legacy `subtotalCents` receive an amount adjustment only; the trigger does not invent a subtotal from a tax-inclusive total.

## UI

`ItemDetailView` passes current-project paid-invoice lock state into `EditItemDetailsModal`. The Project Price field is disabled with an explanation after collection. Inventory movement transaction detail keeps non-accounting edits available while disabling its managed source, totals, type, and category fields.

## Verification

- Pure Cloud Function tests cover project-price deltas, purchase-cost floor changes, tax-only changes, transaction-shape filtering, multi-item total adjustment, missing legacy subtotal, and negative-result rejection.
- Invoice calculation tests cover paid-invoice project-price locking, prior-project resale, and legacy invoice lines without a flat membership index.
- The Firestore integration test for post-sale price changes expects the project Purchase amount to follow the new project price.
- Firestore rules tests confirm direct amount/subtotal edits remain rejected on Purchase-from-Inventory transactions while notes remain editable.
