# Inventory as a Store

> **Status:** Active. Documents the conceptual model shift introduced by the per-batch inventory movement redesign.

## The Idea

**Business inventory is a store the business stocks via two paths.** Projects can buy from inventory (a Purchase, inventory → project) and projects can return to inventory (a Return, project → inventory) when an item is going home. But projects can also **sell** items into inventory — when an item originated in the project and the business is acquiring it for future use. That acquisition is a Sale (project → inventory), not a Return. A Return is reserved for items that came from inventory to begin with.

Inventory items have no budget category; categories belong to projects. Items moving into inventory lose their item category, but the source project Sale/Return transaction keeps `budgetCategoryId` as frozen accounting attribution. Items moving out acquire a destination category.

## What Changed

| Concept | Legacy model | New model |
|---|---|---|
| Inventory → project | Sale transaction (`business_to_project` direction) | **Purchase transaction**, `budgetCategoryId` set |
| Project → inventory (item came from inventory) | Sale transaction (`project_to_business` direction) | **Return transaction** |
| Project → inventory (item originated in project) | Sale transaction (`project_to_business` direction) | **Sale transaction, source `budgetCategoryId` set** |
| Items in inventory | Carry their `budgetCategoryId` across scope moves | Have `budgetCategoryId == null` |
| Category at sell-from-inventory time | Inherited from the item | **Re-resolved** from user input at sell time |
| Category at return-to-inventory time | Preserved on the item | **Wiped** from the item |
| Sale transaction shape | Long-lived aggregator per `(project, direction, category)` | New per-batch transaction per user action |
| Project → project move | Two hops, both as sales | Origin-aware project → inventory hop + new Purchase to destination |
| Inventory → project price | Often fell back to purchase price | **Requires project price**; prompt user if missing |
| Project → inventory price | Sale-direction behavior varied by path | **Uses purchase price** |

## The Core Invariant

For every item:

```
(item.projectId == null) ↔ (item.budgetCategoryId == null)
```

Items in business inventory have no budget category. Items in a project have a budget category. Both clients enforce this on every write.

### Transaction linkage

```
(item.projectId != null) → (item.transactionId != null)
```

Project items must be attached to a transaction — the sale, purchase, or move that placed them in the project. Inventory items may or may not have a `transactionId`. Enforced at the iOS and MCP write layers; not in Firestore security rules.

Legacy orphan items (project items with `transactionId == null` from before this invariant existed) are not backfilled. They remain in place and surface through the Bulk Reassign UI ([BulkSaleResolutionCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/BulkSaleResolutionCalculations.swift)), which lets users attach them to an existing sale.

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

### Moving into inventory — routed by item origin

The user performs a single **Return to Inventory** action. The service routes each item based on origin:

- **Item came from inventory (`item.currentSource != item.source`)** → creates a **Return** transaction (`type: "Return"`, `source: "[Account] Inventory"`). The item is going home.
- **Item originated in the project (`item.currentSource == item.source`, or `currentSource == nil`)** → creates a **Sale-to-Inventory** transaction (`type: "Sale"`, source `budgetCategoryId`, `source: "[Account] Inventory"`). The business is acquiring the item for the first time.

Both paths wipe the item's `budgetCategoryId` and set `projectId` to null. Both emit a lineage edge — `returned` for the Return path, `soldToInventory` for the Sale-to-Inventory path.

**Mixed batches** create both transactions atomically in a single Firestore batch. The UI confirms the split before writing.

**Sign convention:** both paths subtract from the source project's budget (`-1 × amountCents`).

**Price basis:** standalone project → inventory moves use the item's purchase price (`purchasePriceCents`) because the business is acquiring or taking back inventory at cost.

### Moving out of inventory (sell-to-project)

- **Triggered by:** the user selling items from inventory into a project.
- **Requires a budget category.** The user picks one category for the whole batch. The category must be enabled in the destination project. If not enabled, prompt to enable or choose another.
- **Creates a per-batch Purchase transaction.** See [sale-transactions.md](sale-transactions.md).
- **Requires project prices.** If any selected item lacks `projectPriceCents`, the UI asks what the item should sell for and saves that value before creating the Purchase transaction.
- **Sets `budgetCategoryId`** on each item to the chosen category. The category is now part of the item's identity in the destination project.
- **Sign convention:** budget impact is `+1 * amountCents` on the destination project.

### Moving between projects

The model has no direct project-to-project transfer. The flow is a two-hop routing through inventory, with the first hop origin-aware:

1. **First hop** — items exit the source project. Each item's path depends on origin:
   - From-inventory items → Return transaction against the source project.
   - Originated-in-project items → Sale-to-Inventory transaction against the source project.
   - Mixed batches produce both transactions in the same Firestore batch.
2. **Second hop** — all items land in the destination project via one Purchase transaction (`budgetCategoryId` set).

All hops commit atomically when the user invokes **Sell** with a project destination from a project context. Lineage edges link the path. The two-hop mechanic is invisible to the user — from their perspective it's a single Sell action.

**Price basis:** project → project uses project price for both the source project exit and the destination project Purchase.

If any item lacks a project price for the destination hop, the UI asks what it should sell for and saves that value before the atomic move is committed.

Non-interactive inventory tools must reject project-price movements with missing `projectPriceCents` instead of silently using purchase price or writing a zero-amount destination Purchase.

## Display

Business inventory continues to render as a sibling to projects in the UI. The "Business Inventory" card on the projects screen, the inventory tab, the inventory item lists — all unchanged.

What changes:

- **Items in inventory have no category badge.** UI components that previously displayed a category for inventory items should hide the badge when `projectId == null`.
- **Inventory item filters by category** are removed. There's no category to filter by.
- **The project-context "Return to Inventory" action** is only for items that originally came from inventory. Project-originated items use **Sell → Business Inventory** and create a Sale-to-Inventory transaction.
- **Transaction lists group inventory movement records visually.** Inventory acquisitions, inventory-to-project Sales, Sale-to-Inventory records, and return-to-inventory records can render as expandable grouped rows. The grouped row is not a transaction and is never written to Firestore; it exists only to keep one-off inventory movements readable in the UI. Expanding the row reveals the underlying child transactions.

### Transaction List Grouping Rules

Grouping is intentionally broader than `type: "Sale"` because inventory purchase transactions are also part of the business-inventory story.

Group these records:

- Inventory-scope purchases (`type: "Purchase"`, `projectId: null`) as `Added to Business Inventory`.
- Inventory → project Purchases (`type: "Purchase"`, `budgetCategoryId` set) as `From [inventory label]`.
- Project → inventory Sales (`type: "Sale"`, source `budgetCategoryId`) as `Sold to [inventory label]`.
- Return-to-inventory transactions (`type: "Return"`, source is the inventory label) as `Returned to [inventory label]`.

Do not group normal project purchases, fees, expenses, vendor returns, or ambiguous records. Grouping keys include date bucket, movement direction, source/inventory label, project ID, category ID where present, and transaction type so opposite financial effects are never merged.

## Edge Cases

1. **Existing inventory items with stale categories.** Items currently in inventory that have a non-null `budgetCategoryId` from before the migration are left as-is. The next time one of them moves (return or sell), the new flow takes over and overwrites or wipes the field. No backfill is run.
2. **Items created via direct Firestore writes (e.g. tests, migrations).** Should respect the invariant. The MCP and iOS write paths enforce it; tests should match.
3. **Returning to a vendor instead of inventory.** Still works the same way as before. The user picks "Return to vendor" and the return transaction has the vendor's name as `source`, not `"Business Inventory"`.
4. **A category is later disabled in a project that has historical sales.** The historical sales remain valid (they reference the category by ID, not by enabled status). Budget rollups still include them. The category just no longer appears as an option in the project's category picker for new transactions.

## Migration

There is no migration step. The shape change applies to **new** writes only. Legacy data (canonical sales, items with stale inventory categories) remains intact and continues to render correctly via the dual-read path in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts).
