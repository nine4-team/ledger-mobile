# Transaction Audit

## Overview

The transaction audit system provides completeness tracking for transactions with itemized budget categories. It compares the sum of linked item prices against the transaction's pre-tax subtotal to identify gaps in inventory records.

## When Audit Applies

The audit is only relevant when a transaction's budget category has `metadata.categoryType` set to `"itemized"`. Transactions under `"general"` or `"fee"` categories do not have audit tracking.

## Core Calculations

### Items Total
```
itemsNetTotal = linkedItemsSum + returnedItemsSum + soldItemsSum
```
Where each sum uses the transaction's canonical item-price basis:
- Inventory-movement Purchases and Returns with a project and inventory-label source use normalized `projectPriceCents`.
- Ordinary vendor Purchases, vendor Returns, and Sale-to-Inventory acquisitions use `purchasePriceCents`.
- `linkedItemsSum` covers items whose id appears in `transaction.itemIds`.
- `returnedItemsSum` covers lineage edges where `fromTransactionId == transaction.id` and `movementKind == "returned"`.
- `soldItemsSum` covers lineage edges where `fromTransactionId == transaction.id` and `movementKind == "sold"`.

Items with no usable price on the transaction's canonical basis contribute $0 to the total. Lineage items already present in `transaction.itemIds` are excluded from the lineage sums to prevent double-counting.

**Important:** Linked items are looked up by checking which items have an `id` that appears in `transaction.itemIds`. Do NOT look up items by filtering `item.transactionId == transaction.id` — see data-model.md for the canonical lookup direction. Lineage items are found by querying `lineageEdges` where `fromTransactionId == transaction.id`.

### Transaction Subtotal Resolution

The subtotal used for comparison is resolved with this priority:
1. **Explicit subtotal**: `transaction.subtotalCents` if set
2. **Inferred from tax rate**: If `amountCents` and `taxRatePct` are both set: `subtotal = amountCents / (1 + taxRatePct / 100)`, rounded to nearest cent
3. **Fallback to total**: `transaction.amountCents` as final fallback

### Completeness Ratio
```
completenessRatio = itemsNetTotal / transactionSubtotal
```
Expressed as a decimal where 1.0 = 100%.

### Variance
```
varianceCents = itemsNetTotal - transactionSubtotal
variancePercent = (varianceCents / transactionSubtotal) * 100
```
- Positive variance = items exceed the transaction total (over-itemized)
- Negative variance = items account for less than the transaction total (under-itemized)

## Completeness Status Tiers

| Status | Condition | Meaning |
|--------|-----------|---------|
| `complete` | Absolute variance percent <= 1% | Items fully account for the transaction |
| `near` | Absolute variance percent between 1% and 20% | Nearly complete, small gap |
| `incomplete` | Absolute variance percent > 20% (and ratio < 1.2) | Significant gap needs attention |
| `over` | Ratio > 1.2 (items exceed 120% of subtotal) | Items exceed transaction total — possible data error |
| N/A | Transaction subtotal is zero or null | Cannot calculate — show neutral state |

## Missing Price Tracking

Items linked to a transaction that have null or zero `purchasePriceCents` are counted separately:
```
itemsMissingPriceCount = count of items in transaction.itemIds where purchasePriceCents is null or 0
```

This helps users distinguish between "costs don't add up" (variance) and "data hasn't been entered yet" (missing prices).

## Tax Data

### Inferred Tax
When `subtotalCents` is not set but `amountCents` and `taxRatePct` are both available:
```
inferredSubtotal = round(amountCents / (1 + taxRatePct / 100))
inferredTax = amountCents - inferredSubtotal
```

### Missing Tax Data Flag
```
missingTaxData = (subtotalCents is null) AND (taxRatePct is null)
```
When true, the system cannot distinguish pre-tax from post-tax amounts, reducing audit accuracy.

### Explicit Tax Amount
When both `amountCents` and `subtotalCents` are set:
```
taxAmount = amountCents - subtotalCents
```

## The `isComplete` Flag

Transactions have an `isComplete` boolean field, auto-computed by a Cloud Function. The app shows a "Needs Review" badge when `isComplete` is `false` or `null`.

The Cloud Function is the **single source of truth** — no client recomputes completeness. The stored `audit` object contains the computed numbers (resolvedSubtotalCents, itemsSumCents, varianceCents, variancePercent) so all clients read stored data.

**Full spec:** `docs/specs/transaction-completeness.md`

## Stored Entity: TransactionAudit

This is a persisted nested object on the transaction document, written by the Cloud Function:

| Field | Type | Description |
|-------|------|-------------|
| `resolvedSubtotalCents` | integer (cents) | Pre-tax subtotal used for comparison (per subtotal resolution priority) |
| `itemsSumCents` | integer (cents) | Total sum: `linkedItemsSumCents + returnedItemsSumCents + soldItemsSumCents` |
| `varianceCents` | integer (cents) | `itemsSumCents - resolvedSubtotalCents` |
| `variancePercent` | decimal | `(varianceCents / resolvedSubtotalCents) × 100` |
| `linkedItemsSumCents` | integer (cents) | Sum of the transaction's canonical item price for items currently in `transaction.itemIds` |
| `returnedItemsSumCents` | integer (cents) | Sum of the transaction's canonical item price for items that left via `"returned"` lineage edges |
| `returnedItemsCount` | integer | Count of items that left via `"returned"` lineage edges |
| `soldItemsSumCents` | integer (cents) | Sum of the transaction's canonical item price for items that left via `"sold"` lineage edges |
| `soldItemsCount` | integer | Count of items that left via `"sold"` lineage edges |

`audit` is `null` when category is not itemized, transaction is canonical, subtotal can't be resolved, or no items are linked (neither in `itemIds` nor via lineage edges).

## Edge Cases

1. **Zero items linked (and no lineage edges)**: `isComplete = false`, `audit = null`
8. **All items returned**: `itemIds` is empty but lineage edges exist with `movementKind: "returned"`. Audit is computed from lineage items. `isComplete` can be `true` if returned items cover the subtotal.
9. **Item returned and price later changes**: The `onItemPriceChanged` trigger queries lineage edges (not just `itemIds`) to find source transactions and recompute their audits.
2. **Zero transaction subtotal**: `isComplete = false`, `audit = null` (subtotal not resolvable)
3. **All items missing prices**: `itemsSumCents = 0`, variance will be large → `isComplete = false`
4. **Negative item prices**: Should not occur (validation prevents it), but if present, they contribute their value to the sum
5. **Very small variance (< $0.05)**: Treated as complete if within the ±1% threshold
6. **Over 100% completeness**: `isComplete = false` if variance exceeds ±1%
7. **Large item counts (100+)**: Calculations remain performant — Cloud Function uses batched Firestore queries

## Offline Behavior

Audit data (`isComplete` + `audit` object) is stored on the transaction document by the Cloud Function. The native Firestore SDK caches this data, so the audit panel renders correctly from cached data when offline. No client-side computation is needed.

## Design Decisions

### Why server-side computation (Cloud Function)?
- Single source of truth — no parallel recomputation in MCP server or Swift app
- Automatically recomputes when item prices change (via Firestore triggers)
- All clients read stored data — consistent across platforms
- Enables Firestore queries on `isComplete` for filtering

### Why 1% threshold for "complete" (not exact match)?
- Rounding differences between individual item prices and transaction totals are common
- Tax calculations may introduce small discrepancies
- Requiring exact match would cause false "incomplete" flags
