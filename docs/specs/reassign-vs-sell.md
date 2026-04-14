# Reassign vs Sell

## Overview

When items need to move between projects or between a project and business inventory, there are two distinct operations with different semantics. Users must understand which they're performing because the financial implications differ.

## Reassign

### Definition

Reassign moves an item from one transaction to another **within the same scope** (same project, or within business inventory). No financial impact — no new transactions are created, no budget amounts change.

### What Changes

- `item.transactionId` is updated to the new transaction
- The item is removed from the old transaction's `itemIds` array
- The item is added to the new transaction's `itemIds` array
- A `"correction"` intent edge is created client-side (records that this was a data fix)
- An `"association"` audit edge is created server-side by `onItemTransactionIdChanged` (records the transactionId change)

### What Does NOT Change

- `item.projectId` stays the same
- No Sale or Return transaction is created
- No budget impact
- `item.budgetCategoryId` — set from destination transaction's `budgetCategoryId` if item's current value is null; otherwise unchanged

### When to Use

- Correcting a data entry mistake (item was linked to wrong transaction)
- Reorganizing items between transactions within the same project
- Moving an item from one business inventory transaction to another

### Validation

- Source and destination must be in the same scope (same projectId, or both null for business inventory)
- If scopes differ, the operation is a "sell," not a "reassign"

## Sell (Inventory → Project)

### Definition

Sell moves items **from business inventory into a project**. Under the per-batch model ([sale-transactions.md](sale-transactions.md)), this creates **one new immutable Sale transaction** for the batch. The user picks one budget category that applies to every item in the batch.

> **Note:** The reverse direction (project → business inventory) is no longer a sell. It's a Return-to-Inventory. See "Return to Inventory" below and [return-and-sale-tracking.md](return-and-sale-tracking.md).

### What Changes

- `item.projectId` set to destination project ID
- `item.budgetCategoryId` set to the chosen batch category
- `item.transactionId` set to the new Sale transaction ID
- `item.status` set to `"purchased"`
- A new Sale transaction is created (auto-ID, frozen `amountCents` and `itemIds`)
- Items removed from any prior transaction's `itemIds`
- One `"sold"` lineage edge per item
- Budget spend in the destination project increases

### When to Use

- Moving items from business inventory into a project (project is "buying")

### Budget Impact

- Adds to destination project's budget for the chosen category

See [sale-transactions.md](sale-transactions.md) for the full per-batch sale flow.

## Move to Inventory (Project → Inventory) — Origin-Aware

A single user action — "Move to Inventory" — routes each item to one of two transaction types based on its origin:

### Return to Inventory (item came from inventory)

When `item.currentSource != item.source`, the item passed through inventory before landing in this project. A Return transaction is created (`type: "Return"`, `source: "[Account] Inventory"`). The item is going home.

### Sale to Inventory (item originated in the project)

When `item.currentSource == item.source` (or `currentSource == nil`), the item has never been in inventory. The business is acquiring it now — creates a **Sale** transaction (`type: "Sale"`, `source: "[Account] Inventory"`, **no `budgetCategoryId`**). This is the restored sell-to-inventory path.

### Mixed Batches

The UI confirms the split before writing, then writes both transactions in a single atomic Firestore batch.

### What Changes (both paths)

- `item.projectId` set to null
- `item.budgetCategoryId` wiped to null (inventory invariant)
- `item.transactionId` set to the new transaction ID
- `item.status` set to `"purchased"` (still owned, now in inventory)
- `item.currentSource` set to the inventory label
- Source project's budget decreases by `-1 × amountCents`

### Lineage

- Return path emits a `"returned"` edge.
- Sale-to-Inventory path emits a `"soldToInventory"` edge.

## Decision Matrix

| Source | Destination | Operation | Financial Impact |
|--------|-------------|-----------|------------------|
| Project A, Transaction X | Project A, Transaction Y | Reassign | None |
| Business Inventory, Txn X | Business Inventory, Txn Y | Reassign | None |
| Business Inventory | Project A | **Sell to Project** (inventory → project Sale) | Adds to Project A budget |
| Project A | Business Inventory (item came from inventory) | **Return to Inventory** | Subtracts from Project A budget |
| Project A | Business Inventory (item originated in A) | **Sale to Inventory** (project → inventory Sale) | Subtracts from Project A budget |
| Project A | Project B | **Move Between Projects** (origin-aware hop 1 + destination Sale, atomic) | Subtracts from A, adds to B |

### Project-to-Project Moves

Moving items between projects is a single user action that decomposes into a **two-hop** atomic batch. The first hop is origin-aware:

1. **Hop 1 (per origin).** From-inventory items → Return against Project A. Originated-in-A items → Sale-to-Inventory (no `budgetCategoryId`) against Project A. Mixed batches write both.
2. **Hop 2.** One Sale into Project B (`budgetCategoryId` set), covering all items.

All writes land in the same Firestore batch. Lineage edges link the path. See [sale-transactions.md](sale-transactions.md) "Project → Project Moves."

## Menu Visibility Rules

The actions available to users depend on context.

### "Reassign" is available when:

- Item is linked to a transaction
- Other transactions exist in the same scope

### "Sell to Project" is available when:

- Item is in business inventory (projectId is null)
- At least one project exists

### "Return to Inventory" is available when:

- Item is in a project (projectId is not null)

(Previously "Send to Inventory." Renamed to make it clear this is a Return transaction, not a Sale.)

### "Move to Different Project" is available when:

- Item is in a project
- Other projects exist
- Implemented as Return-to-Inventory + new Sale, atomically in one batch

## Budget Category Resolution During Sell

Under the per-batch model, **inventory items have no `budgetCategoryId`** (the inventory invariant). Every sell-to-project requires the user to pick exactly one batch-wide category before the sale can proceed:

1. The picker shows categories enabled in the destination project.
2. If the user picks a category that's not enabled, the system auto-enables it (creates a `ProjectBudgetCategory` doc with `setData(merge: true)`).
3. The chosen category is set on the new Sale transaction AND on every item in the batch.

There is no per-item category override and no mixed-category batches. Users wanting mixed categories must sell in separate batches. See [sale-transactions.md](sale-transactions.md) D4a.

## Design Decision: Why Separate Operations?

Reassign and sell could theoretically be one "move" operation that detects scope changes automatically. They are kept separate because:

1. **User intent matters.** Reassigning (fixing a mistake) vs selling (financial transaction) have different mental models. Conflating them leads to accidental financial entries.
2. **Reversibility.** Reassign is trivially reversible (just reassign back). Sell creates Sale transactions and lineage edges that persist.
3. **Validation differs.** Sell requires budget category selection and may need user input. Reassign is always immediate.
4. **Audit trail clarity.** The lineage edge types (`"association"` vs `"sold"` vs `"returned"`) clearly distinguish organizational moves from financial ones.
