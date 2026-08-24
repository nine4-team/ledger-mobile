# Inventory Movement Transactions

> **Status:** Active. Replaces the legacy "canonical sale" model documented in [canonical-sales.md](canonical-sales.md).

## Overview

When items move between business inventory and a project, the system creates a per-batch **inventory movement transaction** to represent the financial impact on the project's budget. Inventory → project is a **Purchase** from inventory. Project → inventory acquisition is a **Sale** to inventory. This document is the source of truth for how these per-batch inventory movements work.

## The Per-Batch Model

Every user action that moves items from inventory into a project creates **one new purchase transaction**. The transaction is written with a frozen amount snapshot and an initial active item list. If items later leave through return or sale, they are removed from `itemIds` and preserved through lineage.

This is different from the legacy canonical-sale model, where one long-lived transaction per `(project, direction, category)` triple aggregated every inventory movement over time. The legacy model is preserved for historical data — see "Legacy Canonical Sales" below.

### Why per-batch

- **Aggregator drift avoided.** Each movement is a per-batch document instead of a shared long-lived aggregator. Source `itemIds` still update for normal return/sale membership changes.
- **Accounting-correct.** Historical movement amounts never shift retroactively. A movement records what was true at the moment it happened.
- **Matches user mental model.** "I bought these five things from inventory for Hawaii under Furnishings" = one transaction. Not "this category in this project has accumulated $X of inventory transfers."
- **Atomic failure.** A failed batch fails as a unit. There's no partial state where some items moved and others didn't.

## Movement Direction

Inventory movements go in **both directions** between business inventory and a project:

1. **Business inventory → project** is a `Purchase` from inventory. Items leave inventory and land in the project with a `budgetCategoryId`. The project's budget for that category increases.
2. **Project → business inventory** is a `Sale` to inventory only when items **originated in the project** and the business is acquiring them into inventory. The project's budget decreases. This is distinct from a Return — Returns are reserved for items that came from inventory and are going home.

Direction is not stored as a dedicated field. It is **implicit in the transaction shape**:

| Direction | `type` | `source` | `budgetCategoryId` | Project's budget |
|---|---|---|---|---|
| Inventory → Project | `Purchase` | inventory label | set (destination category) | **increases** |
| Project → Inventory | `Sale` | inventory label | set (source category) | **decreases** |

Item category and transaction category are different concepts. Inventory items have no category, so item `budgetCategoryId` is wiped when the item lands in inventory. The Sale transaction still carries `budgetCategoryId` as frozen source-project accounting attribution.

**Item origin governs which direction applies for project → inventory moves.** Items whose most recent scope move passed through inventory (`currentSource != source`) go back via a Return. Items that originated in the project (`currentSource == source`) go via Sale-to-Inventory. See [reassign-vs-sell.md](reassign-vs-sell.md) for UI routing and [inventory-as-store.md](inventory-as-store.md) for the semantic model.

**Price basis is directional.** Any project-destination Purchase uses `projectPriceCents`. Any project → business inventory exit uses `purchasePriceCents`, including the source exit of a project → project two-hop.

## Inventory Purchase Transaction Shape

```typescript
interface InventoryPurchaseTransaction {
  type: "Purchase";
  projectId: string;                    // destination project
  budgetCategoryId: string;             // destination category
  amountCents: number;                  // frozen at creation; project-price basis
  itemIds: string[];                    // active membership, length 0..100 after returns/sales
  source: "[Account] Inventory";        // inventory label, the non-project side
  notes?: string;                       // optional audit note
  createdAt: Timestamp;
  updatedAt: Timestamp;
  createdBy: string;                    // Firebase Auth uid
}
```

**Auto-generated ID.** No deterministic ID formula. The transaction document ID is a Firestore auto-ID.

**Removed fields.** New per-batch inventory purchases and sale-to-inventory transactions do NOT have `isCanonicalInventorySale` or `inventorySaleDirection`. Those fields exist only on legacy canonical sales.

## Invariants

The following invariants are enforced by Firestore security rules and by tests in both iOS and the MCP server:

1. **Accounting immutability after creation.** `amountCents`, `budgetCategoryId`, `type`, `source`, and `projectId` cannot be updated on an inventory movement transaction after it's created. Mutable fields include `itemIds`, `notes`, `status`, `updatedAt`. `itemIds` is current active membership; lineage carries returned/sold historical membership.
2. **Batch size cap.** Initial `itemIds.length >= 1 && itemIds.length <= 100`. Later returns/sales can reduce `itemIds` to zero on the source transaction. Both clients enforce the initial cap locally; the cap exists because Firestore batch writes have a 500-doc limit and a 100-item movement touches ~305 docs.
3. **Non-negative amount.** `amountCents >= 0`.
4. **Direction is type/source-derived.** `type == "Purchase"` with an inventory source is inventory → project. `type == "Sale"` with an inventory source is project → inventory acquisition. No dedicated direction field is written for new per-batch movements.
5. **Category must be enabled (inventory → project only).** When `budgetCategoryId` is present, it must exist as an enabled `ProjectBudgetCategory` in the destination project at the time of the purchase. Both clients validate before writing; if the category is missing, the user is prompted to enable it (or a different category).
6. **One accounting category per transaction.** Inventory → project purchases use one destination `budgetCategoryId`. Source project egress transactions use one source `budgetCategoryId`; mixed source categories are split into separate first-hop transactions.

## The Sell Flow

When a user purchases items from business inventory into a project:

### 1. Collect inputs from the user

- **Items.** A list of business-inventory items (each must have `projectId == null`).
- **Destination project.**
- **Budget category.** One category, applied to every item in the batch (per invariant 5). The category must be enabled in the destination project.
- **Optional notes.**

### 2. Pre-flight validation

- Every item must have `projectId == null` (in business inventory). If any item is in a project, fail with a clear error.
- Item count must be 1..100.
- Destination project must exist.
- Budget category must exist as a `ProjectBudgetCategory` in the destination project. If not, prompt to enable.
- Every item must resolve to a positive project price. Ledger first applies the canonical item price floor, raising `projectPriceCents` to `purchasePriceCents` whenever it is missing, zero, or lower. An already higher project price is preserved. If neither price is positive, the UI asks the user what to sell it for and non-interactive callers reject the operation.

### 3. Compute the snapshot amount

```
resolvedProjectPrice(item) = max(projectPriceCents ?? 0, purchasePriceCents ?? 0)
amountCents = sum(resolvedProjectPrice(item)) for item in items
```

Inventory → project movements use the project-price basis because this is the amount charged to the destination project/client. A project price below purchase cost is raised to purchase cost; otherwise the higher project price is preserved. If neither price is positive, the UI asks the user what they want to sell it for. The resolved value is written to `projectPriceCents` before or atomically with the movement.

### 4. Build the Firestore batch

One batch, all-or-nothing:

1. **Create the Purchase transaction** at `accounts/{accountId}/transactions/{auto-id}` with the shape above.
2. **For each item:** update at `accounts/{accountId}/items/{itemId}`:
   - `projectId` = destination project ID
   - `budgetCategoryId` = the chosen category
   - `transactionId` = the new purchase transaction ID
   - `status` = `"purchased"`
   - `spaceId` = validated per-item destination assignment when supplied; otherwise null
   - `updatedAt` = serverTimestamp()
3. **Auto-enable destination category** if not already enabled, by writing `accounts/{accountId}/projects/{destProjectId}/budgetCategories/{categoryId}` with `setData(merge: true)`. (Idempotent — preserves existing budget amounts.)
4. **Create one `sold` lineage edge per item** at `accounts/{accountId}/lineageEdges/{auto-id}`:
   - `itemId`
   - `fromProjectId`: null (item was in business inventory)
   - `toProjectId`: destination project
   - `fromTransactionId`: the item's prior `transactionId` if any
   - `toTransactionId`: the new purchase transaction
   - `movementKind`: `"sold"`
   - `createdBy`, `createdAt`

5. **Commit.** Single `batch.commit()`. If any write fails, the whole batch rolls back.

### 5. Side effects (server-side, automatic)

- The `onItemTransactionIdChanged` Cloud Function fires for each item, creating an `association` lineage edge as the audit trail. (Already exists, no change needed.)
- The `onTransactionWritten` Cloud Function fires for the new Purchase transaction and recalculates the destination project's budget summary.

## Project → Project Moves

Moving items from one project to another is a **two-hop** operation in a single atomic batch. The first hop is origin-aware:

1. **First hop (per-item, per origin):**
   - From-inventory items (`currentSource != source`) → a **Return** transaction against the source project.
   - Items that originated in the source project (`currentSource == source`) → a **Sale-to-Inventory** transaction (`type: "Sale"`, source `budgetCategoryId`) against the source project.
   - Mixed batches produce **both** first-hop transactions in the same Firestore batch.
2. **Second hop:** one **Purchase-from-Inventory** transaction (`type: "Purchase"`, with `budgetCategoryId`) against the destination project. Covers every item in the batch.

The iOS UI presents this as a single "move to project" action. The service layer issues all hops in one atomic Firestore batch. Lineage edges link each hop.

The destination category is collected from the user — items don't carry a category through the inventory hop. Before commit, every item's project price is normalized to at least its purchase price. The UI asks what to sell it for, and MCP/tooling callers reject, only when neither price is positive.

## Lineage Edges

Every inventory → project purchase creates one `sold` lineage edge per item. See [lineage-tracking.md](lineage-tracking.md) for the edge schema.

For project→project moves, **two** edges are created per item:
- A `returned` edge from the source project to the return transaction.
- A `sold` edge from inventory to the destination purchase transaction.

Together they record the full path: source project → inventory → destination project.

## Amount Calculation

The inventory movement transaction's `amountCents` is computed **once**, at creation time:

| Movement | Price basis |
|---|---|
| Inventory → project Purchase | Project price (`projectPriceCents`) |
| Project → inventory Sale-to-Inventory | Purchase price (`purchasePriceCents`) |
| Return to inventory | Purchase price (`purchasePriceCents`) |
| Project → project source exit | Purchase price (`purchasePriceCents`) |
| Project → project destination Purchase | Project price (`projectPriceCents`) |

```
amountCents = sum(max(item.projectPriceCents ?? 0, item.purchasePriceCents ?? 0)) for item in items
```

The formula above is the project-price basis used by inventory → project and the destination Purchase in project → project movement. Project → business inventory exits use `sum(item.purchasePriceCents ?? 0)` because the business is taking the item into inventory at cost.

After creation, `amountCents` does not change, even if an item's prices are later updated. This is intentional — historical movement records should not retroactively shift in price. The `onItemPriceChanged` Cloud Function explicitly skips frozen inventory movement transactions.

Before a project-price movement, Ledger persists `projectPriceCents = max(projectPriceCents ?? 0, purchasePriceCents ?? 0)`. If neither price is positive, the UI must collect a price and non-interactive tools reject the call.

## Sign Convention

| Transaction | Multiplier on project budget | Effect |
|---|---|---|
| Purchase, inventory → project (`type: "Purchase"`, `budgetCategoryId` set, inventory source) | +1 | Adds to project spend (destination category) |
| Sale, project → inventory (`type: "Sale"`, source `budgetCategoryId`) | –1 | Items leave the project; item-level category is wiped on the item |
| Return (`type: "Return"`) | –1 | Subtracts from project spend; items leave |
| Legacy canonical sale (`isCanonicalInventorySale: true`) | direction-based | See "Legacy Canonical Sales" below |

The sign convention is centralized in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts) `normalizeSpendAmount`. Any new reader must consult this function rather than reimplement the convention.

## Display — Naming Convention

Inventory movement direction is rendered in the transaction's **display name**, from the project's point of view. There is no direction badge — direction lives in the name.

| Direction | Display name | Example |
|---|---|---|
| Inventory → Project (Purchase with `budgetCategoryId`) | `Purchase from [source]` | `Purchase from 1584 Design Inventory` |
| Project → Inventory (Sale with source `budgetCategoryId`) | `Sale to [source]` | `Sale to 1584 Design Inventory` |
| Return to inventory (`type: "Return"`) | `Return to [source]` | `Return to 1584 Design Inventory` |
| Return to vendor (`type: "Return"`) | `Return to [source]` | `Return to Wayfair` |

Resolution is implemented in `TransactionDisplayCalculations.displayName(for:)` and mirrored in `SearchCalculations.transactionDisplayName(for:)` for search cards.

**Other display:**
- **Type badge:** "Purchase", "Sale", or "Return" (type only — never direction).
- **Source field:** the inventory label for inventory-involved transactions, the vendor name for vendor transactions.
- **Amount:** the frozen `amountCents`.
- **Items:** current active items rendered from `itemIds`; items that left via return/sale render from lineage sections.

Inventory movement transactions are NOT user-editable for accounting shape. Users can edit `notes` and add/cancel via `status`; inventory flows may update `itemIds` as items leave via return/sale.

### Transaction List Grouping

Transaction lists visually group inventory-movement records so the list reads as movement activity per project/category rather than a stream of per-batch documents. This grouping is **presentation-only**:

- The underlying Sale, Return, and Purchase documents remain separate auditable records with frozen accounting fields.
- Transaction detail always opens the real child transaction.
- Bulk selection, export, and totals operate on the child transaction IDs.
- No grouped row is written back to Firestore and no grouped row becomes a canonical aggregate.

Groupable records:

| Record | Group row | Notes |
|---|---|---|
| Inventory purchase/acquisition (`type: "Purchase"`, `projectId: null`) | `Added to Business Inventory` | Groups inventory-scope acquisition purchases by vendor/type. |
| Inventory → project Purchase (`type: "Purchase"`, `budgetCategoryId` set) | `From [inventory label]` | Groups by inventory label, project, category, and transaction type. |
| Project -> inventory Sale (`type: "Sale"`, source `budgetCategoryId`) | `Sold to [inventory label]` | Groups by inventory label, project, category, and transaction type. |
| Return to inventory (`type: "Return"`, inventory-label source) | `Returned to [inventory label]` | Vendor returns are excluded; only inventory-label returns are grouped. |

The grouping key includes movement direction, source/inventory label, project ID, budget category ID, and transaction type. **Date is not part of the key** — all matching batches collapse into a single row regardless of when they happened, so a project that pulls from inventory across many days shows one card per (direction, source, category). Charges and credits must not be collapsed into a misleading net row; that's why direction and type are part of the key.

The group's displayed date is the most recent `effectiveSortDate` among its child transactions.

## Legacy Canonical Sales

Existing sale transactions written under the canonical-sale model remain in the data as read-only historical records. They are identified by the field `isCanonicalInventorySale: true` and have an `inventorySaleDirection` field of either `"business_to_project"` or `"project_to_business"`.

**Reading legacy canonical sales:**
- Their amounts are frozen (the `onItemPriceChanged` recalc has been removed).
- They display normally in transaction lists.
- Their sign convention follows the original direction-based rule (see [budget-management.md](budget-management.md) Sign Conventions).
- They remain mutable for narrow operations (`cancel_transaction` updates `status`); the new immutability rules carve them out via `isCanonicalInventorySale: true`.

**No migration.** Legacy canonical sales are not converted to per-batch shape. The dual-read path in `util/budget.ts` is the maintenance cost of preserving them. If the volume becomes problematic, a one-time migration script can be considered as a follow-up.

**Why preserve them:** rewriting historical financial records is risky. Freezing them is the safe move. The new shape applies only to inventory movement records created after this taxonomy correction ships.

## Edge Cases

1. **Inventory → project item with a missing or below-cost project price.** Ledger raises it to the positive purchase price automatically. The movement requires user input only when neither price is positive. The normalized value is persisted on `item.projectPriceCents` and used for the Purchase amount.
2. **Project → inventory item with no purchase price.** Contributes $0 to the Return or Sale-to-Inventory amount. Still included in `itemIds`. Lineage edge still created.
3. **Movement with 0 total amount.** Allowed for project → inventory moves when items have no recorded purchase price.
4. **Category not enabled in destination.** Pre-flight validation rejects with a clear error. UI prompts user to enable or pick a different category.
5. **Item already in destination project.** Pre-flight validation rejects — the purchase-from-inventory flow only accepts inventory items.
6. **Concurrent moves of the same item.** Firestore batch atomicity handles this: whichever batch commits second will fail because the item's `projectId` no longer matches inventory state. The user sees a "stale data" error and refreshes.
7. **Cancellation.** Setting `status: "canceled"` on an inventory movement transaction excludes it from budget calculations. The transaction remains in the data; items are not automatically reverted. Manual cleanup via `update_item` if needed.
