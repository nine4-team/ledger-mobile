# Return and Sale Tracking

> **Target-state notice (2026-08-30):** The workflow-status and origin rules
> remain relevant, but project financial effects move from movement Transactions
> to Item charges/credits under
> [Inventory Item Invoicing and Return Lifecycle](inventory-item-invoicing-lifecycle.md).
> Treat Transaction-specific mechanics below as current implementation behavior.

## Overview

This spec describes how items are returned from transactions, how disposition (what happens to a returned item) is tracked, and how incomplete returns are detected. It also covers the origin-aware project-to-inventory flow: items that came from inventory go home through a Return, while project-originated items enter inventory through a Sale-to-Inventory transaction.

> **Related specs:**
> - [sale-transactions.md](sale-transactions.md) — the active inventory movement transaction model (per-batch, frozen identity fields with one controlled destination-Purchase repricing exception)
> - [inventory-as-store.md](inventory-as-store.md) — why returning to inventory is a return, not a sale
> - [canonical-sales.md](canonical-sales.md) — the legacy canonical-sale model (historical reads only)

## Item Status Lifecycle

Items have a `status` field that tracks their lifecycle:

| Status | Meaning |
|--------|---------|
| `to purchase` | Item needs to be purchased (created before a purchase transaction) |
| `purchased` | Item has been purchased and is active |
| `to return` | Item is flagged for return but hasn't been returned yet |
| `returned` | Item has been returned to the vendor/source |

Status transitions:
- `to purchase` → `purchased` (when linked to a purchase transaction)
- `purchased` → `to return` (when user marks for return)
- `to return` → `returned` (when return is processed)
- `returned` → `purchased` (if return is undone/reversed)

## Return Flow

When a user returns an item, the following happens:

### Step 1: Mark for Return
User marks item status as `to return`. This is a Tier 1 write (fire-and-forget update to the item's `status` field). No other data changes at this point.

### Step 2: Process Return
The actual return is processed via a request doc (Tier 2 write) because it involves multiple document updates:

1. **Update item fields:**
   - `status` → `returned`
   - `transactionId` → the return transaction's ID (or cleared)

2. **Update source transaction:**
   - Remove item ID from source transaction's `itemIds` array

3. **Create or update return transaction:**
   - If a return transaction exists for this vendor/source, add item to its `itemIds`
   - If not, create a new return transaction with `transactionType: "Return"`

4. **Create lineage edge:**
   - `movementKind: "returned"`
   - `fromTransactionId`: the source purchase transaction
   - `toTransactionId`: the return transaction
   - `itemId`: the returned item

### Step 3: Budget Impact
Return transactions have their amounts multiplied by -1 in budget calculations:
```
if transactionType is "Return": budget_multiplier = -1
```
This means a $100 return subtracts $100 from the budget category's spent amount.

## Disposition Lifecycle

After an item is returned, it may go through several dispositions:

1. **Returned to vendor**: Item goes back to the vendor. The return transaction has the vendor's name as `source`. No further tracking needed.
2. **Returned to business inventory**: An item that previously came from inventory goes home through a Return transaction with the account inventory source label. This creates a `returned` lineage edge and wipes the item's `budgetCategoryId`.
3. **Sold to business inventory**: A project-originated item that the business is acquiring for the first time uses a Sale-to-Inventory transaction. This creates a `soldToInventory` lineage edge and wipes the item's `budgetCategoryId`.
4. **Replaced**: A new item is purchased to replace the returned one. The replacement is a new item linked to a new purchase transaction.
5. **Refunded**: The financial impact is handled by the return transaction's negative amount in budget calculations.

## Incomplete Return Detection

An "incomplete return" is an item that has been marked as returned (`status: "returned"`) but hasn't been properly processed through the return flow. This can happen when:
- A user manually sets an item's status to "returned" without going through the return flow
- The return request doc failed partway through
- Data was manually edited in Firestore

### Detection Rules

An item has an incomplete return when ALL of these are true:
1. `item.status` is `"returned"` or `"to return"`
2. The item is still listed in a non-return transaction's `itemIds` (i.e., it's still in a purchase transaction)
3. No lineage edge with `movementKind: "returned"` exists for this item from its current transaction

### Detection Algorithm (pseudocode)
```
for each item where status is "returned" or "to return":
  currentTransaction = find transaction where itemIds contains item.id
  if currentTransaction exists AND currentTransaction.transactionType is not "Return":
    returnEdge = find lineageEdge where itemId == item.id
                 AND movementKind == "returned"
                 AND fromTransactionId == currentTransaction.id
    if returnEdge does not exist:
      flag item as "incomplete return"
```

### What to Do with Incomplete Returns

The system surfaces incomplete returns to the user so they can:
1. **Complete the return**: Process the return through the proper flow (creates return transaction + lineage edge)
2. **Undo the status**: Change status back to `purchased` if the return was marked in error
3. **Ignore**: Some items may be legitimately in a transitional state

## Returning to Inventory

In the per-batch model, an inventory-origin item going home from a project is **a single Return transaction**. Project-originated items instead use Sale-to-Inventory. This replaces the legacy canonical-sale aggregator model.

### What Happens

When a user returns inventory-origin items from a project to business inventory, the flow:

1. Creates a new per-batch Return transaction at `accounts/{accountId}/transactions/{auto-id}` with:
   - `type: "Return"`
   - `source: "[Account Name] Inventory"` (or `"Business Inventory"` fallback)
   - `projectId`: source project ID, so the budget reversal lands on that project
   - `budgetCategoryId`: source project category
   - `amountCents`: sum of the returned items' normalized `projectPriceCents`, including per-item tax when recorded
   - `itemIds`: the returned items
2. For each item, updates `accounts/{accountId}/items/{itemId}`:
   - `projectId` → null (back to inventory)
   - `budgetCategoryId` → **null** (wiped on entry to inventory; this is the core invariant)
   - `transactionId` → the new return transaction ID
   - `status` → `"purchased"` (still owned, just back in stock)
   - `spaceId` → null
3. Removes each item from its prior project transaction's `itemIds` array.
4. Creates one `returned` lineage edge per item:
   - `fromTransactionId`: the item's prior transaction
   - `toTransactionId`: the new return transaction
   - `fromProjectId`: source project
   - `toProjectId`: null
   - `movementKind`: `"returned"`

All in one Firestore batch. Atomic.

### Paid Invoice Credits

If a returned item appears as a charge line on a paid invoice, the return flow
also creates client credit demand in invoicing. It must not create a synthetic
credit transaction.

The credit is written as an ordinary draft invoice containing manual credit
lines:

- `sourceType: "manual"`
- `sourceId: null`
- `sign: -1`
- `amountCents`: copied from the original paid invoice line
- `budgetCategoryId`: copied from the original paid invoice line
- `itemIds: []`
- `transactionIds: []`

The credit line ID is deterministic from the original paid invoice id, original
paid invoice line id, and returned item id. That ID prevents duplicate credits
across non-voided invoices.

The inventory return movement and draft credit invoice should be written in the
same Firestore batch when invoice context is available. If a caller cannot
resolve invoice context, it should route through a context-aware flow or surface
a blocking warning instead of silently skipping the credit.

### Per-Batch Returns

Every return-to-inventory action creates a new Return transaction. Return transactions are not reused across later actions. Their accounting fields, including `amountCents`, stay frozen after creation; `itemIds` may only change as items later leave that transaction through another movement.

### Budget Impact

Return-to-inventory transactions follow the existing return sign convention: `-1 * amountCents` against the source project's budget for the relevant category. Because these items previously came from business inventory, the Return reverses their effective project-sale prices (including per-item tax when recorded), matching the project-side Purchase rather than creating a new acquisition at supplier cost.

The destination ("Business Inventory") has no budget — it doesn't appear in any rollup.

### Lineage

Two layers, as always (see [lineage-tracking.md](lineage-tracking.md)):

- **Intent layer:** the `returned` edge created client-side by the return-to-inventory flow.
- **Audit layer:** the `association` edge created server-side by `onItemTransactionIdChanged` when the item's `transactionId` changes.

Both fire for every item in the batch.

### Why a Single Step (Not Two)

Under the legacy canonical-sale model, returning to inventory required two operations: a return transaction (vendor return) followed by a canonical sale (project → business). This created two budget impacts (one on the return, one on the canonical sale) that had to net out, plus two lineage edges (`returned` and `sold`) per item.

The per-batch model collapses this to one return transaction with one budget impact and one lineage edge per item. Simpler, atomic, and accounting-correct: a return is a return, regardless of where the items end up.

### Project → Project Moves

A move from one project to another decomposes into two origin-aware operations in one atomic batch:

1. Source-project exit: Return for inventory-origin items, or Sale-to-Inventory for project-originated items.
2. New per-batch Purchase-from-inventory into the destination project ([sale-transactions.md](sale-transactions.md)).

Each item gets two lineage edges: `returned` or `soldToInventory` for the source exit, then `sold` for the inventory-to-destination Purchase. The destination purchase's category is collected from the user; the source category is not carried through inventory.

## Return Transaction Properties

Return transactions have specific characteristics:
- `transactionType: "Return"`
- `amountCents`: Positive number (the absolute return amount)
- Budget impact: Negative (multiplied by -1 in budget calculations)
- Can accumulate multiple returned items from the same vendor
- `source`: Typically matches the original purchase transaction's source (vendor name)

## Edge Cases

1. **Returning an item with no explicit project price**: Ledger uses the normalized project price, which falls back to a positive purchase price under the project-price floor. If neither price is positive, the item contributes $0.
2. **Returning all items from a transaction**: The source transaction retains its data but has an empty `itemIds` array. It is not deleted.
3. **Partial return**: Only some items from a transaction are returned. The remaining items stay in the source transaction.
4. **Return of a sold item**: If an item was sold (canonical sale) and then returned, the return creates a lineage edge from the canonical sale transaction, not the original purchase.
5. **Double return detection**: If an item already has a "returned" lineage edge from its current transaction, attempting to return it again should be blocked or warned.

## Sign Convention Summary

| Transaction Type | Stored Amount | Budget Multiplier | Budget Effect |
|-----------------|---------------|-------------------|---------------|
| Purchase | Positive | +1 | Adds to spent |
| Return (vendor or inventory) | Positive | -1 | Subtracts from spent |
| Per-batch Sale-to-Inventory (`type: "Sale"`, no `isCanonicalInventorySale`) | Positive | -1 | Subtracts from spent |
| **Legacy** canonical sale, `business_to_project` | Positive | +1 | Adds to spent |
| **Legacy** canonical sale, `project_to_business` | Positive | -1 | Subtracts from spent |
| Canceled (any type) | — | 0 | Excluded |

The legacy canonical sale rows apply only to historical documents with `isCanonicalInventorySale: true`. New writes never produce these. See [canonical-sales.md](canonical-sales.md) for the legacy details.

The sign convention is centralized in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts) `normalizeSpendAmount`. Any new reader must consult this function rather than reimplement the logic.
