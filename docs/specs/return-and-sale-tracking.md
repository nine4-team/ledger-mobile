# Return and Sale Tracking

## Overview

This spec describes how items are returned from transactions, how disposition (what happens to a returned item) is tracked, and how incomplete returns are detected. It also covers the **return-to-inventory** flow, which under the per-batch inventory movement redesign replaces the legacy "sell from project to business inventory" path.

> **Related specs:**
> - [sale-transactions.md](sale-transactions.md) — the active inventory movement transaction model (per-batch, immutable)
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
2. **Returned to business inventory**: Item moves to business inventory scope via a Return transaction with `source: "Business Inventory"`. This is the **only** path back to inventory in the per-batch model — there is no longer a "sell to inventory" sale path. See [inventory-as-store.md](inventory-as-store.md). Creates a `returned` lineage edge and wipes the item's `budgetCategoryId`.
3. **Replaced**: A new item is purchased to replace the returned one. The replacement is a new item linked to a new purchase transaction.
4. **Refunded**: The financial impact is handled by the return transaction's negative amount in budget calculations.

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

In the per-batch model, returning an item from a project to business inventory is **a single return transaction**, not a sale. This replaces the legacy two-step (return + canonical sale) process.

### What Happens

When a user returns items from a project to business inventory, the flow:

1. Creates (or reuses an open) Return transaction at `accounts/{accountId}/transactions/{auto-id}` with:
   - `type: "Return"`
   - `source: "Business Inventory"`
   - `projectId: null` (inventory scope)
   - `amountCents`: sum of `purchasePriceCents` of the returned items
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

### Coalescing Returns

A return-to-inventory transaction can grow during a single user session — if the user returns 3 items, then 2 more in the same flow, both batches can write to the same Return transaction's `itemIds` (using `arrayUnion`) and recalculate `amountCents`. Once the user leaves the flow (or 24h passes), the transaction is treated as closed and clients should create a new one for subsequent returns.

This is the only place mutation of a return-to-inventory transaction is allowed; otherwise these documents are immutable like other inventory movement transactions.

### Budget Impact

Return-to-inventory transactions follow the existing return sign convention: `-1 * amountCents` against the source project's budget for the relevant category. This means the source project's spend decreases by the total of the returned items' purchase prices.

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

A move from one project to another decomposes into two operations in one atomic batch:

1. Return-to-inventory from the source project (this section).
2. New per-batch Purchase-from-inventory into the destination project ([sale-transactions.md](sale-transactions.md)).

Each item gets two lineage edges: one `returned` (source → inventory) and one `purchasedFromInventory` (inventory → destination). The destination purchase's category is collected from the user — the category is wiped during the return hop.

## Return Transaction Properties

Return transactions have specific characteristics:
- `transactionType: "Return"`
- `amountCents`: Positive number (the absolute return amount)
- Budget impact: Negative (multiplied by -1 in budget calculations)
- Can accumulate multiple returned items from the same vendor
- `source`: Typically matches the original purchase transaction's source (vendor name)

## Edge Cases

1. **Returning an item with no purchase price**: The item is returned but contributes $0 to the return transaction's amount.
2. **Returning all items from a transaction**: The source transaction retains its data but has an empty `itemIds` array. It is not deleted.
3. **Partial return**: Only some items from a transaction are returned. The remaining items stay in the source transaction.
4. **Return of a sold item**: If an item was sold (canonical sale) and then returned, the return creates a lineage edge from the canonical sale transaction, not the original purchase.
5. **Double return detection**: If an item already has a "returned" lineage edge from its current transaction, attempting to return it again should be blocked or warned.

## Sign Convention Summary

| Transaction Type | Stored Amount | Budget Multiplier | Budget Effect |
|-----------------|---------------|-------------------|---------------|
| Purchase | Positive | +1 | Adds to spent |
| Return (vendor or inventory) | Positive | -1 | Subtracts from spent |
| Per-batch Sale (`type: "Sale"`, no `isCanonicalInventorySale`) | Positive | +1 | Adds to spent |
| **Legacy** canonical sale, `business_to_project` | Positive | +1 | Adds to spent |
| **Legacy** canonical sale, `project_to_business` | Positive | -1 | Subtracts from spent |
| Canceled (any type) | — | 0 | Excluded |

The legacy canonical sale rows apply only to historical documents with `isCanonicalInventorySale: true`. New writes never produce these. See [canonical-sales.md](canonical-sales.md) for the legacy details.

The sign convention is centralized in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts) `normalizeSpendAmount`. Any new reader must consult this function rather than reimplement the logic.
