# Transaction Completeness (`isComplete`)

## Overview

The transaction completeness system determines whether a transaction has been fully accounted for. A Cloud Function is the **single source of truth** — it computes `isComplete` and a stored `audit` object on every transaction write, item price change, or budget category type change. All clients (MCP server, Swift app) read stored data; no client recomputes completeness.

The app shows a **"Needs Review" badge** when `isComplete === false`.

## The `isComplete` Field

**Path:** `accounts/{accountId}/transactions/{transactionId}.isComplete`
**Type:** `boolean | null`

- `true` — transaction is complete
- `false` — transaction needs review (app shows badge)
- `null` / missing — legacy data, not yet computed (treated as `false` in UI)

### Replaces `needsReview`

`isComplete` replaced the legacy `needsReview` field. Semantics are inverted: old `needsReview: true` → new `isComplete: false`. The `needsReview` field has been removed from the model and stripped from stored documents.

## Completeness Criteria

`isComplete = true` when **any** of:
1. **Canonical/system transaction** — `isCanonicalInventorySale === true` or `isCanonicalInventory === true`
2. **Non-itemized category** — budget category's `metadata.categoryType` is not `"itemized"` (includes `"general"`, `"standard"`, `"fee"`, or no category)
3. **All conditions met** for an itemized category:
   - Tax data present — `subtotalCents` is set (not null/undefined) **or** `taxRatePct` is set (not null/undefined, including `0`)
   - Has items — `itemIds` is non-empty **or** lineage edges with `movementKind` "returned", "sold", or "soldToInventory" exist for this transaction
   - Items match subtotal — `abs(variancePercent) ≤ 1%` (where `itemsSumCents` includes both linked and lineage items, with any transaction-level discount applied before comparison)

`isComplete = false` when itemized category **and any** of:
- Missing tax data (neither `subtotalCents` nor `taxRatePct` is set)
- No items linked and no qualifying lineage edges (`itemIds` is null/empty AND no returned/sold/soldToInventory edges)
- Items don't match subtotal (variance > ±1%)
- No amount data (`amountCents` is null or 0)

### Tax Data Check

The check for `taxRatePct` must use strict null/undefined comparison (`!== null && !== undefined`), **not** falsy check. `taxRatePct: 0` means "no tax" and is valid tax data. `taxRatePct: null` means "tax rate unknown."

## Subtotal Resolution

The pre-tax subtotal used for comparison is resolved with this priority (first match wins):

1. **Explicit subtotal** — `subtotalCents` if set and > 0
2. **Inferred from tax rate** — `round(amountCents / (1 + taxRatePct / 100))` when both `amountCents` and `taxRatePct` are set, and `taxRatePct > 0`
3. **Amount as subtotal** — `amountCents` when `taxRatePct` is explicitly `0` (no-tax purchase)
4. **Not resolvable** — if none of the above apply, subtotal cannot be resolved → `isComplete = false`

**Important:** Raw `amountCents` is **not** used as a fallback when `taxRatePct` is null. Comparing pre-tax item prices against a post-tax total is unreliable.

## Stored `audit` Object

The Cloud Function writes a nested `audit` object alongside `isComplete`:

```json
{
  "isComplete": false,
  "audit": {
    "resolvedSubtotalCents": 16973,
    "itemsSumCents": 17973,
    "discountCents": 1000,
    "varianceCents": 0,
    "variancePercent": 0,
    "linkedItemsSumCents": 12973,
    "returnedItemsSumCents": 3000,
    "returnedItemsCount": 2,
    "soldItemsSumCents": 0,
    "soldItemsCount": 0
  }
}
```

`audit` is `null` when:
- Category is not itemized
- Transaction is canonical
- Subtotal cannot be resolved
- No items are linked and no qualifying lineage edges exist

### Audit Fields

| Field | Type | Description |
|-------|------|-------------|
| `resolvedSubtotalCents` | integer (cents) | Pre-tax subtotal used for comparison (per resolution priority) |
| `itemsSumCents` | integer (cents) | Total: `linkedItemsSumCents + returnedItemsSumCents + soldItemsSumCents` |
| `discountCents` | integer (cents) | Transaction-level discount applied before comparing item totals. Uses `discount.amountCents` when present |
| `varianceCents` | integer (cents) | `(itemsSumCents - discountCents) - resolvedSubtotalCents` |
| `variancePercent` | decimal | `(varianceCents / resolvedSubtotalCents) × 100` |
| `linkedItemsSumCents` | integer (cents) | Sum of `purchasePriceCents` for items currently in `itemIds` |
| `returnedItemsSumCents` | integer (cents) | Sum of `purchasePriceCents` for items that left via `"returned"` lineage edges |
| `returnedItemsCount` | integer | Count of items that left via `"returned"` lineage edges |
| `soldItemsSumCents` | integer (cents) | Sum of `purchasePriceCents` for items that left via `"sold"` lineage edges |
| `soldItemsCount` | integer | Count of items that left via `"sold"` lineage edges |

## Cloud Function Triggers

### 1. Transaction Write (`onTransactionWritten`)

Fires on every transaction create, update, or delete. Computes `isComplete` + `audit` for the transaction.

**Loop guard:** Skips when the **only** fields that changed are `isComplete`, `audit`, and/or `updatedAt`. This prevents infinite loops when the function writes back to the same document.

**Runs for ALL transactions**, not just project-scoped ones (unlike budget summary recalculation which skips no-projectId transactions).

### 2. Item Price Change

When `purchasePriceCents` changes on an item, queries for parent transactions via `array-contains` on `itemIds`, then recomputes `isComplete` for each. Also queries lineage edges where `itemId == changedItemId` and `movementKind` in `["returned", "sold", "soldToInventory"]` to find source transactions (`fromTransactionId`) that should be recomputed — this handles items that have already left their source transaction.

### 3. Budget Category Type Change (`onAccountBudgetCategoryWritten`)

When `metadata.categoryType` changes on an account-level budget category:

- **To non-itemized:** Query transactions with that `budgetCategoryId`, batch set `isComplete = true, audit = null`
- **To itemized:** Query transactions with that `budgetCategoryId`, batch set `isComplete = false, audit = null` (marks for review; full computation happens on next transaction write or via backfill)

### 4. Lineage Edge Creation (`onLineageEdgeCreated`)

When a lineage edge is created with `movementKind` "returned", "sold", or "soldToInventory", recomputes `isComplete` + `audit` on the source transaction (`fromTransactionId`). This is a safety net for non-atomic flows where the edge is created after the transaction's `itemIds` was already updated.

Guards:
- Skip if `movementKind` is not "returned" or "sold" (avoids cascading on frequent "association" edges)
- Skip if `fromTransactionId` is null

### 5. Backfill (`backfillIsComplete`)

Callable Cloud Function that iterates all transactions in an account, computes `isComplete` + `audit`, and writes results. Only writes `isComplete`, `audit`, and `updatedAt` — the loop guard prevents budget summary cascade.

Runs in batches of 500 with throttling.

## MCP Tool Contract

### `get_transaction`

Returns stored `isComplete` and `audit` from the transaction document. No computation.

### `list_transactions`

Supports `isComplete` filter parameter. Firestore query: `where("isComplete", "==", value)`. Use `isComplete: false` to find transactions needing audit.

### `create_transaction`

New transactions start with `isComplete: false`. The Cloud Function recomputes immediately after the write.

### `update_transaction`

`isComplete` is **not** in the update schema — it cannot be set manually. The Cloud Function recomputes automatically after every write.

### `bulk_update_transactions`

Filter supports `isComplete`. `isComplete` is not in the update payload — system-managed only.

## UI Badge Mapping

| `isComplete` value | Badge | Meaning |
|---------------------|-------|---------|
| `true` | None | Transaction is complete |
| `false` | "Needs Review" | Transaction needs attention |
| `null` / missing | "Needs Review" | Legacy data, treated as incomplete |

When users say a transaction "needs review," they mean `isComplete` is `false`.

## Edge Cases

1. **No budget category** — treated as non-itemized → `isComplete = true`
2. **Canceled transactions** — still computed normally (cancellation is a separate concern)
3. **Items on non-itemized transactions** — items can exist, audit just isn't computed (`audit = null`)
4. **Zero `amountCents`** — subtotal not resolvable → `isComplete = false`
5. **Very small variance (< $0.05)** — treated as complete if within ±1% threshold
6. **`taxRatePct: 0`** — valid tax data meaning "no tax"; `amountCents` used directly as subtotal
