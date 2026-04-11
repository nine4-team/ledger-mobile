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

There is exactly **one** direction for sale transactions: **business inventory → project.**

The reverse direction (project → business inventory) is no longer a sale. It's a **return**. See [return-and-sale-tracking.md](return-and-sale-tracking.md) for the return flow.

This is the biggest semantic change from the legacy model. Treat business inventory as a store: you buy from it (sale) and you return to it (return). You don't sell back to it.

## Sale Transaction Shape

```typescript
interface SaleTransaction {
  type: "Sale";
  projectId: string;                    // destination project (required, non-null)
  budgetCategoryId: string;             // required, must be enabled in destination project
  amountCents: number;                  // frozen at creation; sum of item projectPriceCents
  itemIds: string[];                    // frozen at creation, length 1..100
  source: "Business Inventory";
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
4. **Category must be enabled.** `budgetCategoryId` must exist as an enabled `ProjectBudgetCategory` in the destination project at the time of the sale. Both clients validate before writing; if the category is missing, the user is prompted to enable it (or a different category).
5. **One category per batch.** A sale transaction has exactly one `budgetCategoryId`. There's no per-item category override. Users wanting mixed categories must sell in separate batches.

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

Moving items from one project to another is **two transactions** in one batch:

1. A **return-to-inventory transaction** for the source project (item's category is wiped on the item).
2. A **new per-batch sale transaction** for the destination project (category re-resolved from user input).

The iOS UI presents this as a single "move to project" action. Under the hood, the service layer issues both writes in the same Firestore batch, atomically. Lineage edges link them.

The category for the destination sale is collected from the user — items don't carry a category through the inventory hop.

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

Per-batch sales contribute **positively** to the destination project's budget for the chosen category. There is no negative direction — that case is a Return.

| Transaction | Multiplier | Effect |
|---|---|---|
| Per-batch Sale (`type: "Sale"`, no `isCanonicalInventorySale`) | +1 | Adds to project spend |
| Return (`type: "Return"`) | -1 | Subtracts from project spend |
| Legacy canonical sale (`isCanonicalInventorySale: true`) | direction-based | See "Legacy Canonical Sales" below |

The sign convention is centralized in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts) `normalizeSpendAmount`. Any new reader must consult this function rather than reimplement the convention.

## Display

Sale transactions appear in the destination project's transaction list with:

- **Type badge:** "Sale"
- **Source:** "Business Inventory"
- **Amount:** the frozen `amountCents`
- **Items:** rendered from `itemIds`

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
