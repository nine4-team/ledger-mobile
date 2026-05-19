# Correct/Move vs Sell vs Return

## Overview

When items need to move between transactions, projects, or business inventory, there are three distinct operations with different semantics: **Correct/Move**, **Sell**, and **Return**. Users must understand which they're performing because the financial implications differ.

UI labels (final):

- **Correct / Move** — corrections only, no financial impact. Within-scope reassignment.
- **Sell to Project** — one menu item that handles both inventory→project and project→project sales (the two-hop is an implementation detail invisible to the user).
- **Return to Inventory** — items returning home to business inventory (origin-aware under the hood).
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

## Sell to Project

### Definition

Sell moves items **into a project**. From the user's perspective this is a single operation regardless of where the item starts — the menu item is **Sell to Project** whether the item is in business inventory or in another project.

Under the per-batch model ([sale-transactions.md](sale-transactions.md)), the user picks one budget category that applies to every item in the batch. Two underlying flows, transparent to the user:

- **Inventory → Project** (single Sale). One new immutable Sale transaction.
- **Project A → Project B** (two-hop, atomic). Hop 1 is origin-aware against Project A (Return-to-Inventory if the item came from inventory, Sale-to-Inventory if it originated in Project A). Hop 2 is a new Sale into Project B with the chosen category. All writes land in the same Firestore batch.

> **Note:** The reverse direction (project → business inventory) is **not** a Sell from the user's perspective — it's the **Return to Inventory** action below. See [return-and-sale-tracking.md](return-and-sale-tracking.md) for the return flow details.

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

## Return to Inventory (Project → Inventory) — Origin-Aware

A single user action — **Return to Inventory** — routes each item to one of two transaction types based on its origin:

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

| Source | Destination | User-facing action | Underlying mechanics | Financial Impact |
|--------|-------------|--------------------|----------------------|------------------|
| Project A, Transaction X | Project A, Transaction Y | **Correct / Move** | `transactionId` swap | None |
| Business Inventory, Txn X | Business Inventory, Txn Y | **Correct / Move** | `transactionId` swap | None |
| Business Inventory | Project A | **Sell to Project** | Single Sale (inventory → project) | Adds to Project A budget |
| Project A | Business Inventory (item came from inventory) | **Return to Inventory** | Return transaction | Subtracts from Project A budget |
| Project A | Business Inventory (item originated in A) | **Return to Inventory** | Sale-to-Inventory transaction | Subtracts from Project A budget |
| Project A | Project B | **Sell to Project** | Two-hop atomic: origin-aware hop 1 + destination Sale | Subtracts from A, adds to B |
| Project A or Inventory | Vendor | **Return to Vendor** | Vendor Return transaction (new or appended) | Subtracts from source budget (if from project) |

### Sell to Project — Project-to-Project Mechanics

When the source is another project, **Sell to Project** decomposes into a **two-hop** atomic batch. The user does not see this — to them it's a single Sell action. The first hop is origin-aware:

1. **Hop 1 (per origin).** From-inventory items → Return against Project A. Originated-in-A items → Sale-to-Inventory (no `budgetCategoryId`) against Project A. Mixed batches write both.
2. **Hop 2.** One Sale into Project B (`budgetCategoryId` set), covering all items.

All writes land in the same Firestore batch. Lineage edges link the path. See [sale-transactions.md](sale-transactions.md) "Project → Project Moves."

## Menu Visibility Rules

The actions available to users depend on context.

### "Correct / Move" is available when:

- Item is linked to a transaction
- Other transactions exist in the same scope (same projectId, or both null for business inventory)
- Framed in the UI as a correction — no money moves, no Sale or Return created

### "Sell to Project" is available when:

- Item is in business inventory (projectId is null) AND at least one project exists, OR
- Item is in a project (projectId is not null) AND at least one other project exists
- Single menu item regardless of source; underlying single-hop vs two-hop is invisible to the user

### "Return to Inventory" is available when:

- Item is in a project (projectId is not null)
- Origin-aware under the hood (Return transaction vs Sale-to-Inventory transaction)

(Previously "Send to Inventory." Renamed to make it clear this is a Return, not a Sale.)

### "Return to Vendor" is available when:

- Item is in a Purchase transaction (vendor-sourced)
- Items being physically sent back to the vendor
- Routes through a vendor Return transaction (new or appended); see [return-and-sale-tracking.md](return-and-sale-tracking.md) for the coalescing rules

## Budget Category Resolution During Sell

Under the per-batch model, **inventory items have no `budgetCategoryId`** (the inventory invariant). Every sell-to-project requires the user to pick exactly one batch-wide category before the sale can proceed:

1. The picker shows categories enabled in the destination project.
2. If the user picks a category that's not enabled, the system auto-enables it (creates a `ProjectBudgetCategory` doc with `setData(merge: true)`).
3. The chosen category is set on the new Sale transaction AND on every item in the batch.

There is no per-item category override and no mixed-category batches. Users wanting mixed categories must sell in separate batches. See [sale-transactions.md](sale-transactions.md) D4a.

## Design Decision: Why Separate Operations?

Correct/Move and Sell could theoretically be one "move" operation that detects scope changes automatically. They are kept separate because:

1. **User intent matters.** Correcting a mistake vs selling (financial transaction) have different mental models. Conflating them leads to accidental financial entries. The label "Correct / Move" exists specifically to make the corrective intent visible — without "Correct," users might choose Sell when they meant to fix a data error.
2. **Reversibility.** Correct/Move is trivially reversible (just reassign back). Sell creates Sale transactions and lineage edges that persist.
3. **Validation differs.** Sell requires budget category selection and may need user input. Correct/Move is always immediate.
4. **Audit trail clarity.** The lineage edge types (`"association"` vs `"sold"` vs `"returned"`) clearly distinguish organizational moves from financial ones.
