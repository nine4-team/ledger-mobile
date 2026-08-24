# Correct/Move vs Sell vs Return

## Overview

When items need to move between transactions, projects, or business inventory, there are three distinct operations with different semantics: **Correct/Move**, **Sell**, and **Return**. Users must understand which they're performing because the financial implications differ.

UI labels (final):

- **Correct / Move** — corrections only, no financial impact. Within-scope reassignment.
- **Sell** — financial sale flow. User chooses Project or, when eligible, Business Inventory as the destination.
- **Return to Inventory** — items originally from inventory returning home to business inventory.
- **Return to Vendor** — items being physically sent back to the vendor.

## Correct / Move (Reassign)

### Definition

Correct/Move reassigns an item from one transaction to another **within the same scope** (same project, or within business inventory). No financial impact — no new transactions are created, no budget amounts change. The "Correct" half of the label signals intent (this is a data fix, not a business event); the "Move" half describes the mechanic (the item is being relocated between transactions).

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
- If scopes differ, the operation is a Sell, not a Correct/Move

## Sell

### Definition

Sell is a financial operation. The user chooses the destination: a project, or business inventory when the selected project items originated in that project.

Under the per-batch model ([sale-transactions.md](sale-transactions.md)), project-destination sales require the user to pick one budget category that applies to every item in the batch. Project-destination flows:

- **Inventory → Project** (single Purchase). One new per-batch Purchase transaction.
- **Project A → Project B** (two-hop, atomic). Hop 1 is origin-aware against Project A (Return-to-Inventory if the item came from inventory, Sale-to-Inventory if it originated in Project A). Hop 2 is a new Purchase from inventory into Project B with the chosen category. All writes land in the same Firestore batch.

Inventory-destination sale:

- **Project → Business Inventory** is a Sale-to-Inventory only when the item originated in the project. The sale uses purchase price because the business is acquiring the item as inventory.

Project-destination sales always charge the destination project at normalized `projectPriceCents`. Ledger first raises it to at least `purchasePriceCents`; the UI asks what to sell it for only when neither price is positive.

### What Changes

- `item.projectId` set to destination project ID
- `item.budgetCategoryId` set to the chosen batch category
- `item.transactionId` set to the new Purchase transaction ID
- `item.status` set to `"purchased"`
- A new Purchase transaction is created (auto-ID, frozen `amountCents`, current `itemIds`)
- Items removed from any prior transaction's `itemIds`
- One `"sold"` lineage edge per item
- Budget spend in the destination project increases

### When to Use

- Selling items from business inventory into a project
- Selling items from one project to another project
- Selling project-originated items into business inventory

### Budget Impact

- Adds to destination project's budget for the chosen category at project price
- For project-to-project sales, the source project decreases at purchase price and the destination project increases at project price
- For project-to-inventory sales, the source project decreases at purchase price

See [sale-transactions.md](sale-transactions.md) for the full per-batch inventory movement flow.

## Return to Inventory (Project → Inventory)

Return to Inventory is only for items that originally came from inventory.

### Return to Inventory (item came from inventory)

When `item.currentSource != item.source`, the item passed through inventory before landing in this project. A Return transaction is created (`type: "Return"`, `source: "[Account] Inventory"`). The item is going home.

### What Changes (both paths)

- `item.projectId` set to null
- `item.budgetCategoryId` wiped to null (inventory invariant)
- `item.transactionId` set to the new transaction ID
- `item.status` set to `"purchased"` (still owned, now in inventory)
- `item.currentSource` set to the inventory label
- Source project's budget decreases by `-1 × amountCents`; `amountCents` is based on `purchasePriceCents`

### Lineage

- Return path emits a `"returned"` edge.

## Decision Matrix

| Source | Destination | User-facing action | Underlying mechanics | Financial Impact |
|--------|-------------|--------------------|----------------------|------------------|
| Project A, Transaction X | Project A, Transaction Y | **Correct / Move** | `transactionId` swap | None |
| Business Inventory, Txn X | Business Inventory, Txn Y | **Correct / Move** | `transactionId` swap | None |
| Business Inventory | Project A | **Sell → Project** | Single Purchase from inventory | Adds to Project A budget |
| Project A | Business Inventory (item came from inventory) | **Return to Inventory** | Return transaction | Subtracts from Project A budget |
| Project A | Business Inventory (item originated in A) | **Sell → Business Inventory** | Sale-to-Inventory transaction | Subtracts from Project A budget |
| Project A | Project B | **Sell → Project** | Two-hop atomic: origin-aware hop 1 + destination Purchase from inventory | Subtracts from A, adds to B |
| Project A or Inventory | Vendor | **Return to Vendor** | Vendor Return transaction (new or appended) | Subtracts from source budget (if from project) |

### Project-to-Project Sale Mechanics

When the source is another project and the destination is a project, **Sell** decomposes into a **two-hop** atomic batch. The user chooses the destination project; the first hop is origin-aware:

1. **Hop 1 (per origin).** From-inventory items → Return against Project A. Originated-in-A items → Sale-to-Inventory with source `budgetCategoryId` against Project A. Mixed batches write both.
2. **Hop 2.** One Purchase from inventory into Project B (`budgetCategoryId` set), covering all items.

All writes land in the same Firestore batch. Lineage edges link the path. See [sale-transactions.md](sale-transactions.md) "Project → Project Moves."

Pricing follows the sale destination: project-to-project uses purchase price for Hop 1 and normalized project price for Hop 2. Standalone project-to-business-inventory uses purchase price. Project-destination sales collect a price only when neither project nor purchase price is positive.

## Menu Visibility Rules

The actions available to users depend on context.

### "Correct / Move" is available when:

- Item is linked to a transaction
- Other transactions exist in the same scope (same projectId, or both null for business inventory)
- Framed in the UI as a correction — no money moves, no Sale or Return created

### "Sell" is available when:

- Item is in business inventory (projectId is null) AND at least one project exists, OR
- Item is in a project (projectId is not null) AND at least one other project exists
- Item is in a project and originated in that project, allowing the **Business Inventory** destination
- A project destination uses the single-hop or two-hop mechanics above

### "Return to Inventory" is available when:

- Item is in a project (projectId is not null)
- Item originally came from inventory (`currentSource != source`)

(Previously "Send to Inventory." Renamed to make it clear this is a Return, not a Sale.)

### "Return to Vendor" is available when:

- Item is in a Purchase transaction (vendor-sourced)
- Items being physically sent back to the vendor
- Routes through a vendor Return transaction (new or appended); see [return-and-sale-tracking.md](return-and-sale-tracking.md) for the coalescing rules

## Budget Category Resolution During Sell

Under the per-batch model, **inventory items have no `budgetCategoryId`** (the inventory invariant). Every sell-to-project requires the user to pick exactly one batch-wide category before the sale can proceed:

1. The picker shows categories enabled in the destination project.
2. If the user picks a category that's not enabled, the system auto-enables it (creates a `ProjectBudgetCategory` doc with `setData(merge: true)`).
3. The chosen category is set on the new Purchase transaction AND on every item in the batch.

There is no per-item category override and no mixed-category batches. Users wanting mixed categories must sell in separate batches. See [sale-transactions.md](sale-transactions.md) D4a.

The sell flow also requires a positive project price for every item. Before confirmation, Ledger persists `projectPriceCents = max(projectPriceCents ?? 0, purchasePriceCents ?? 0)`, preserving higher markup and raising any lower value to cost. A price-entry step appears only when neither price is positive. The resulting values become the frozen amount snapshot for the destination Purchase.

## Design Decision: Why Separate Operations?

Correct/Move and Sell could theoretically be one "move" operation that detects scope changes automatically. They are kept separate because:

1. **User intent matters.** Correcting a mistake vs selling (financial transaction) have different mental models. Conflating them leads to accidental financial entries. The label "Correct / Move" exists specifically to make the corrective intent visible — without "Correct," users might choose Sell when they meant to fix a data error.
2. **Reversibility.** Correct/Move is trivially reversible (just reassign back). Sell to Project creates inventory movement transactions and lineage edges that persist.
3. **Validation differs.** Sell requires budget category selection and may need user input. Correct/Move is always immediate.
4. **Audit trail clarity.** The lineage edge types (`"association"` vs `"sold"` vs `"returned"`) clearly distinguish organizational moves from financial ones.
