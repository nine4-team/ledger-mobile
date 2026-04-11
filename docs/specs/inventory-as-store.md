# Inventory as a Store

> **Status:** Active. Documents the conceptual model shift introduced by the per-batch sale redesign.

## The Idea

**Business inventory is treated like any other store.** When a project needs something from inventory, it "buys" it (a sale transaction). When a project no longer needs something from inventory, it "returns" it (a return transaction). The mechanics mirror how the project would interact with any external vendor.

This replaces an earlier model where business inventory was a special scope with bidirectional sales (project ↔ inventory) and where items in inventory carried budget categories that travelled with them across moves.

## What Changed

| Concept | Legacy model | New model |
|---|---|---|
| Inventory → project | Sale transaction (`business_to_project` direction) | Sale transaction (the only direction) |
| Project → inventory | Sale transaction (`project_to_business` direction) | **Return transaction** (`source: "Business Inventory"`) |
| Items in inventory | Carry their `budgetCategoryId` across scope moves | Have `budgetCategoryId == null` |
| Category at sell-from-inventory time | Inherited from the item | **Re-resolved** from user input at sell time |
| Category at return-to-inventory time | Preserved on the item | **Wiped** from the item |
| Sale transaction shape | Long-lived aggregator per `(project, direction, category)` | New per-batch transaction per user action |
| Project → project move | Two hops, both as sales | Return-to-inventory + new sale to destination |

## The Core Invariant

For every item:

```
(item.projectId == null) ↔ (item.budgetCategoryId == null)
```

Items in business inventory have no budget category. Items in a project have a budget category. Both clients enforce this on every write.

## Why It Matters

### Mental model alignment

The legacy model had a quirk: items in business inventory carried a budget category that wasn't meaningful (inventory has no budget). The category was metadata kept around for the next time the item moved into a project. Users found this confusing — "why does this item have a Furnishings category when it's just sitting in inventory?"

In the new model, the answer is simple: it doesn't. Categories belong to projects.

### Drift elimination

The legacy model required keeping the item's `budgetCategoryId` in sync across scope moves, sell flows, and return flows. Multiple code paths wrote it. They drifted. Under the new model, the rule is mechanical: moving into inventory wipes the category; moving into a project sets it. There's nothing to drift.

### Simpler accounting

A return transaction is a return transaction, whether the items go back to a vendor or back to inventory. The same `-1` budget multiplier applies. The same lineage edge type (`returned`) is created. There's no special "this is a sale that goes the other way" case.

## Behavioral Rules

### Items in inventory (`projectId == null`)

- **Have `budgetCategoryId == null`.** Always. No exceptions for new items.
- **No budget impact.** They don't appear in any project's budget rollup.
- **No category-specific organization.** They're a flat pool, organized by name, source, and space (warehouse spaces, etc.).
- **Created with `budgetCategoryId == null`.** If a caller passes a category when creating an item with `projectId: null`, the value is ignored or rejected.

### Moving into inventory (return-to-inventory)

- **Triggered by:** the user choosing to return items from a project, with the destination being inventory rather than the original vendor.
- **Creates a return transaction** with `type: "Return"` and `source: "Business Inventory"`. May coalesce with an existing open return transaction within the same session.
- **Wipes `budgetCategoryId`** on each item. This is a hard rule, not optional.
- **Creates a `returned` lineage edge** from the item's prior project transaction to the new return transaction.
- **Sign convention:** budget impact is `-1 * amountCents` on the source project (matches all returns).

### Moving out of inventory (sell-to-project)

- **Triggered by:** the user selling items from inventory into a project.
- **Requires a budget category.** The user picks one category for the whole batch. The category must be enabled in the destination project. If not enabled, prompt to enable or choose another.
- **Creates a per-batch Sale transaction.** See [sale-transactions.md](sale-transactions.md).
- **Sets `budgetCategoryId`** on each item to the chosen category. The category is now part of the item's identity in the destination project.
- **Sign convention:** budget impact is `+1 * amountCents` on the destination project.

### Moving between projects

The new model has no direct project-to-project transfer. The flow is:

1. Return items from the source project to inventory (creates a return tx, wipes the category).
2. Sell items from inventory to the destination project (creates a new sale tx, sets a fresh category).

Both happen in one atomic batch when the user invokes "move to project." The UI presents this as one action; the data model records it as two transactions linked by lineage edges.

## Display

Business inventory continues to render as a sibling to projects in the UI. The "Business Inventory" card on the projects screen, the inventory tab, the inventory item lists — all unchanged.

What changes:

- **Items in inventory have no category badge.** UI components that previously displayed a category for inventory items should hide the badge when `projectId == null`.
- **Inventory item filters by category** are removed. There's no category to filter by.
- **The "Sell to inventory" action** is removed from project-context item menus and replaced with "Return to inventory."

## Edge Cases

1. **Existing inventory items with stale categories.** Items currently in inventory that have a non-null `budgetCategoryId` from before the migration are left as-is. The next time one of them moves (return or sell), the new flow takes over and overwrites or wipes the field. No backfill is run.
2. **Items created via direct Firestore writes (e.g. tests, migrations).** Should respect the invariant. The MCP and iOS write paths enforce it; tests should match.
3. **Returning to a vendor instead of inventory.** Still works the same way as before. The user picks "Return to vendor" and the return transaction has the vendor's name as `source`, not `"Business Inventory"`.
4. **A category is later disabled in a project that has historical sales.** The historical sales remain valid (they reference the category by ID, not by enabled status). Budget rollups still include them. The category just no longer appears as an option in the project's category picker for new transactions.

## Migration

There is no migration step. The shape change applies to **new** writes only. Legacy data (canonical sales, items with stale inventory categories) remains intact and continues to render correctly via the dual-read path in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts).
