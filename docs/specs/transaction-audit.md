# Transaction Audit

## Overview

The transaction audit system provides completeness tracking for transactions with itemized budget categories. It compares the sum of linked item prices against the transaction's pre-tax subtotal to identify gaps in inventory records.

## When Audit Applies

The audit is only relevant when a transaction's budget category has `metadata.categoryType` set to `"itemized"`. Transactions under `"general"` or `"fee"` categories do not have audit tracking.

## Core Calculations

### Items Total
```
itemsNetTotal = sum of purchasePriceCents for all items whose id appears in transaction.itemIds
```
Items with null or zero `purchasePriceCents` contribute $0 to the total.

**Important:** Items are looked up by checking which items have an `id` that appears in `transaction.itemIds`. Do NOT look up items by filtering `item.transactionId == transaction.id` — see data-model.md for the canonical lookup direction.

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

## The `needsReview` Flag

Transactions have a denormalized `needsReview` boolean field. This is set to `true` when the audit completeness is below the "complete" threshold for an itemized category. It enables:
- Filtering transactions that need attention in list views
- Showing review badges on transaction cards
- Prioritizing incomplete transactions in workflows

This flag is updated whenever items are linked/unlinked or prices change.

## Computed Entity: TransactionCompleteness

This is a computed (not persisted) data structure calculated client-side:

| Field | Type | Description |
|-------|------|-------------|
| `itemsNetTotal` | integer (cents) | Sum of linked item purchase prices |
| `itemsCount` | integer | Total linked items |
| `itemsMissingPriceCount` | integer | Items with no purchase price |
| `transactionSubtotal` | integer (cents) | Resolved subtotal (per priority above) |
| `completenessRatio` | decimal | itemsNetTotal / transactionSubtotal |
| `completenessStatus` | string | One of: complete, near, incomplete, over |
| `missingTaxData` | boolean | True if no subtotal and no tax rate |
| `inferredTax` | integer or null (cents) | Tax calculated from rate |
| `taxAmount` | integer or null (cents) | Explicit tax if available |
| `varianceCents` | integer (cents) | itemsNetTotal - transactionSubtotal |
| `variancePercent` | decimal | Variance as percentage of subtotal |

## Edge Cases

1. **Zero items linked**: completenessRatio = 0, status = "incomplete"
2. **Zero transaction subtotal**: status = N/A, do not calculate ratio (division by zero)
3. **All items missing prices**: itemsNetTotal = 0, itemsMissingPriceCount = itemsCount
4. **Negative item prices**: Should not occur (validation prevents it), but if present, they contribute their value to the sum
5. **Very small variance (< $0.05)**: Treat as "complete" if within the 1% threshold
6. **Over 100% completeness**: When items total more than 120% of subtotal, flag as "over" status
7. **Large item counts (100+)**: Calculations should remain performant — all data is already loaded, no additional queries needed

## Offline Behavior

All audit calculations are performed client-side from data already loaded on the transaction detail screen. No additional network requests are needed. The audit renders correctly from cached data when offline.

## Design Decisions

### Why client-side computation (not persisted)?
- The audit depends on item prices which change independently of the transaction
- Persisting would require triggers on every item price update
- Client-side computation is fast (simple arithmetic over already-loaded data)
- Avoids sync conflicts between computed and source data

### Why 1% threshold for "complete" (not exact match)?
- Rounding differences between individual item prices and transaction totals are common
- Tax calculations may introduce small discrepancies
- Requiring exact match would cause false "incomplete" flags
