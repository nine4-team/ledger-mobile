# Sale Transactions

> **Status:** Active. Replaces the legacy "canonical sale" model documented in [canonical-sales.md](canonical-sales.md).

## Overview

When items move between business inventory and a project, the system creates a **sale transaction** to represent the financial impact on the project's budget. This document is the source of truth for how sales work in the new per-batch model.

## The Per-Batch Model

Every user action that sells items from inventory into a project creates **one new sale transaction**. The transaction is written once, with a frozen list of items and a frozen amount snapshot, and is **never mutated after creation**. If the user sells more items later, that's a separate transaction.

This is different from the legacy canonical-sale model, where one long-lived transaction per `(project, direction, category)` triple aggregated every sale of that combination over time. The legacy model is preserved for historical data — see "Legacy Canonical Sales" below.

### Why per-batch

- **Drift impossible.** Each sale is an immutable document. There's no shared mutable state across implementations to drift.
- **Accounting-correct.** Historical sale amounts never shift retroactively. A sale records what was true at the moment it happened.
- **Matches user mental model.** "I sold these five things to Hawaii under Furnishings" = one transaction. Not "this category in this project has accumulated $X of inventory transfers."
- **Atomic failure.** A failed batch fails as a unit. There's no partial state where some items moved and others didn't.

## Sale Direction

Sales go in **both directions** between business inventory and a project:

1. **Business inventory → project** (a Purchase from Inventory, from the project's POV). Items leave inventory and land in the project with a `budgetCategoryId`. The project's budget for that category increases.
2. **Project → business inventory** (a Sale to Inventory, from the project's POV). Items that **originated in the project** are acquired into inventory. The project's budget decreases. This is distinct from a Return — Returns are reserved for items that came from inventory and are going home.

Direction is not stored as a dedicated field. It is **implicit in the transaction shape**:

| Direction | `type` | `source` | `budgetCategoryId` | Project's budget |
|---|---|---|---|---|
| Inventory → Project | `Sale` | inventory label | set (destination category) | **increases** |
| Project → Inventory | `Sale` | inventory label | absent | **decreases** |

This leverages the core invariant `item.projectId == null ↔ item.budgetCategoryId == null`: inventory items have no category, so a Sale involving inventory as destination cannot carry one.

**Item origin governs which direction applies for project → inventory moves.** Items whose most recent scope move passed through inventory (`currentSource != source`) go back via a Return. Items that originated in the project (`currentSource == source`) go via Sale-to-Inventory. See [reassign-vs-sell.md](reassign-vs-sell.md) for UI routing and [inventory-as-store.md](inventory-as-store.md) for the semantic model.

## Sale Transaction Shape

```typescript
interface SaleTransaction {
  type: "Sale";
  projectId: string;                    // project side of the transaction (required)
  //                                    // inventory → project: the destination
  //                                    // project → inventory: the source
  budgetCategoryId?: string;            // present = inventory → project; absent = project → inventory
  amountCents: number;                  // frozen at creation; sum of item projectPriceCents
  itemIds: string[];                    // frozen at creation, length 1..100
  source: "[Account] Inventory";        // inventory label, the non-project side
  notes?: string;                       // optional audit note
  createdAt: Timestamp;
  updatedAt: Timestamp;
  createdBy: string;                    // Firebase Auth uid
}
```

**Auto-generated ID.** No deterministic ID formula. The transaction document ID is a Firestore auto-ID.

**Removed fields.** New per-batch sales do NOT have `isCanonicalInventorySale` or `inventorySaleDirection`. Those fields exist only on legacy canonical sales.

## Invariants

The following invariants are enforced by Firestore security rules and by tests in both iOS and the MCP server:

1. **Immutability after creation.** `amountCents`, `itemIds`, `budgetCategoryId`, `type`, `source`, and `projectId` cannot be updated on a Sale transaction after it's created. Mutable fields: `notes`, `status`, `updatedAt`.
2. **Batch size cap.** `itemIds.length >= 1 && itemIds.length <= 100`. Both clients enforce locally; the cap exists because Firestore batch writes have a 500-doc limit and a sale of 100 items touches ~305 docs.
3. **Non-negative amount.** `amountCents >= 0`.
4. **Direction is shape-derived.** `budgetCategoryId` presence distinguishes inventory → project (set) from project → inventory (absent). The direction is derivable from `(type, source, budgetCategoryId)` alone — no dedicated field.
5. **Category must be enabled (inventory → project only).** When `budgetCategoryId` is present, it must exist as an enabled `ProjectBudgetCategory` in the destination project at the time of the sale. Both clients validate before writing; if the category is missing, the user is prompted to enable it (or a different category).
6. **One category per batch.** An inventory → project sale has exactly one `budgetCategoryId`. There's no per-item category override. Users wanting mixed categories must sell in separate batches. Project → inventory sales have no category (items leave the project's category system entirely).

## The Sell Flow

When a user sells items from business inventory into a project:

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

### 3. Compute the snapshot amount

```
amountCents = sum(item.projectPriceCents ?? item.purchasePriceCents ?? 0) for item in items
```

### 4. Build the Firestore batch

One batch, all-or-nothing:

1. **Create the Sale transaction** at `accounts/{accountId}/transactions/{auto-id}` with the shape above.
2. **For each item:** update at `accounts/{accountId}/items/{itemId}`:
   - `projectId` = destination project ID
   - `budgetCategoryId` = the chosen category
   - `transactionId` = the new sale transaction ID
   - `status` = `"purchased"`
   - `spaceId` = null
   - `updatedAt` = serverTimestamp()
3. **Auto-enable destination category** if not already enabled, by writing `accounts/{accountId}/projects/{destProjectId}/budgetCategories/{categoryId}` with `setData(merge: true)`. (Idempotent — preserves existing budget amounts.)
4. **Create one `sold` lineage edge per item** at `accounts/{accountId}/lineageEdges/{auto-id}`:
   - `itemId`
   - `fromProjectId`: null (item was in business inventory)
   - `toProjectId`: destination project
   - `fromTransactionId`: the item's prior `transactionId` if any
   - `toTransactionId`: the new sale transaction
   - `movementKind`: `"sold"`
   - `createdBy`, `createdAt`

5. **Commit.** Single `batch.commit()`. If any write fails, the whole batch rolls back.

### 5. Side effects (server-side, automatic)

- The `onItemTransactionIdChanged` Cloud Function fires for each item, creating an `association` lineage edge as the audit trail. (Already exists, no change needed.)
- The `onTransactionWritten` Cloud Function fires for the new Sale transaction and recalculates the destination project's budget summary.

## Project → Project Moves

Moving items from one project to another is a **two-hop** operation in a single atomic batch. The first hop is origin-aware:

1. **First hop (per-item, per origin):**
   - From-inventory items (`currentSource != source`) → a **Return** transaction against the source project.
   - Items that originated in the source project (`currentSource == source`) → a **Sale-to-Inventory** transaction (`type: "Sale"`, no `budgetCategoryId`) against the source project.
   - Mixed batches produce **both** first-hop transactions in the same Firestore batch.
2. **Second hop:** one **Sale-to-Project** transaction (`type: "Sale"`, with `budgetCategoryId`) against the destination project. Covers every item in the batch.

The iOS UI presents this as a single "move to project" action. The service layer issues all hops in one atomic Firestore batch. Lineage edges link each hop.

The destination category is collected from the user — items don't carry a category through the inventory hop.

## Lineage Edges

Every sale creates one `sold` lineage edge per item. See [lineage-tracking.md](lineage-tracking.md) for the edge schema.

For project→project moves, **two** edges are created per item:
- A `returned` edge from the source project to the return transaction.
- A `sold` edge from inventory to the destination sale transaction.

Together they record the full path: source project → inventory → destination project.

## Amount Calculation

The Sale transaction's `amountCents` is computed **once**, at creation time:

```
amountCents = sum(item.projectPriceCents ?? item.purchasePriceCents ?? 0) for item in items
```

After creation, `amountCents` does not change, even if an item's `projectPriceCents` is later updated. This is intentional — historical sales should not retroactively shift in price. The `onItemPriceChanged` Cloud Function explicitly skips Sale transactions.

If an item has neither `projectPriceCents` nor `purchasePriceCents` at sell time, it contributes $0 to the sale total but is still included in `itemIds`.

## Sign Convention

| Transaction | Multiplier on project budget | Effect |
|---|---|---|
| Sale, inventory → project (`type: "Sale"`, `budgetCategoryId` set) | +1 | Adds to project spend (destination category) |
| Sale, project → inventory (`type: "Sale"`, `budgetCategoryId` absent) | –1 | Items leave the project; item-level category is wiped on the item |
| Return (`type: "Return"`) | –1 | Subtracts from project spend; items leave |
| Legacy canonical sale (`isCanonicalInventorySale: true`) | direction-based | See "Legacy Canonical Sales" below |

The sign convention is centralized in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts) `normalizeSpendAmount`. Any new reader must consult this function rather than reimplement the convention.

## Display — Naming Convention

Sale direction is rendered in the transaction's **display name**, from the project's point of view. There is no direction badge — direction lives in the name.

| Direction | Display name | Example |
|---|---|---|
| Inventory → Project (Sale with `budgetCategoryId`) | `Purchase from [source]` | `Purchase from 1584 Design Inventory` |
| Project → Inventory (Sale without `budgetCategoryId`) | `Sale to [source]` | `Sale to 1584 Design Inventory` |
| Return to inventory (`type: "Return"`) | `Return to [source]` | `Return to 1584 Design Inventory` |
| Return to vendor (`type: "Return"`) | `Return to [source]` | `Return to Wayfair` |

Resolution is implemented in `TransactionDisplayCalculations.displayName(for:)` and mirrored in `SearchCalculations.transactionDisplayName(for:)` for search cards.

**Other display:**
- **Type badge:** "Sale" or "Return" (type only — never direction).
- **Source field:** the inventory label for inventory-involved transactions, the vendor name for vendor transactions.
- **Amount:** the frozen `amountCents`.
- **Items:** rendered from `itemIds`.

Sale transactions are NOT user-editable. The shape fields are immutable. Users can edit `notes` and add/cancel via `status`.

## Legacy Canonical Sales

Existing sale transactions written under the canonical-sale model remain in the data as read-only historical records. They are identified by the field `isCanonicalInventorySale: true` and have an `inventorySaleDirection` field of either `"business_to_project"` or `"project_to_business"`.

**Reading legacy canonical sales:**
- Their amounts are frozen (the `onItemPriceChanged` recalc has been removed).
- They display normally in transaction lists.
- Their sign convention follows the original direction-based rule (see [budget-management.md](budget-management.md) Sign Conventions).
- They remain mutable for narrow operations (`cancel_transaction` updates `status`); the new immutability rules carve them out via `isCanonicalInventorySale: true`.

**No migration.** Legacy canonical sales are not converted to per-batch shape. The dual-read path in `util/budget.ts` is the maintenance cost of preserving them. If the volume becomes problematic, a one-time migration script can be considered as a follow-up.

**Why preserve them:** rewriting historical financial records is risky. Freezing them is the safe move. The new shape applies only to sales created after the per-batch model ships.

## Edge Cases

1. **Item with no price.** Contributes $0 to `amountCents`. Still included in `itemIds`. Lineage edge still created.
2. **Sale with 0 total amount.** Allowed. Some items may legitimately have no recorded price.
3. **Category not enabled in destination.** Pre-flight validation rejects with a clear error. UI prompts user to enable or pick a different category.
4. **Item already in destination project.** Pre-flight validation rejects — the sell flow only accepts inventory items.
5. **Concurrent sells of the same item.** Firestore batch atomicity handles this: whichever batch commits second will fail because the item's `projectId` no longer matches inventory state. The user sees a "stale data" error and refreshes.
6. **Cancellation.** Setting `status: "canceled"` on a Sale transaction excludes it from budget calculations. The transaction remains in the data; items are not automatically reverted. Manual cleanup via `update_item` if needed.
