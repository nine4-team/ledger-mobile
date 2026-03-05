# Return and Sale Tracking

## Overview

This spec describes how items are returned from transactions, how disposition (what happens to a returned item) is tracked, and how incomplete returns are detected. It also covers the interaction between returns and the canonical sale system.

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

1. **Returned to vendor**: Item goes back to the vendor. No further tracking needed.
2. **Returned to business inventory**: Item moves to business inventory scope. This triggers a canonical sale (project → business) with `movementKind: "sold"` in lineage.
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

## Interaction with Canonical Sales

When a returned item needs to go back to business inventory:
1. First, process the return (remove from source transaction, create return lineage edge)
2. Then, process the canonical sale (project → business inventory, create sold lineage edge)

This creates two lineage edges for the item:
- `returned`: from purchase transaction to return transaction
- `sold`: from project to business inventory

The two operations are sequential — the return must complete before the scope change.

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

| Transaction Type | amountCents Storage | Budget Multiplier | Budget Effect |
|-----------------|--------------------|--------------------|---------------|
| Purchase | Positive | +1 | Adds to spent |
| Return | Positive | -1 | Subtracts from spent |
| Sale (business→project) | Positive | +1 | Adds to spent |
| Sale (project→business) | Positive | -1 | Subtracts from spent |
