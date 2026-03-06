# Issue: Transaction detail items section shows no items

**Status:** Active
**Opened:** 2026-03-05
**Resolved:** _pending_

## Info
- **Symptom:** Transaction cards show item count (e.g. "2 items") but the transaction detail view's Items section shows "No items yet"
- **Affected area:** `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift` (lines 38-41)

### Card view (working)
`TransactionCard.swift:34-36` uses `transaction.itemIds?.count` — direct array length on the Transaction model. Works because `itemIds` is populated in the Firestore document.

### Detail view (broken)
`TransactionDetailView.swift:38-41` filters `projectContext.items` by `item.transactionId == transaction.id`. This assumes items have a `transactionId` field pointing back to the transaction. In practice, items in Firestore do NOT have `transactionId` set — the relationship is one-directional: the transaction document holds `itemIds: [String]`.

### RN reference
The React Native app uses `useItemsByIds(accountId, transaction.itemIds)` (`src/hooks/useItemsByIds.ts`) which fetches items by their document IDs from the `itemIds` array on the transaction. It does NOT rely on `item.transactionId`.

## Experiments

### H1: Detail view uses wrong lookup direction — filters by `item.transactionId` instead of matching `item.id` against `transaction.itemIds`
- **Rationale:** Transaction model stores `itemIds: [String]?`. Items may not have `transactionId` set. Card view works because it reads `transaction.itemIds` directly.
- **Experiment:** Check if changing the filter to `transaction.itemIds?.contains(item.id) == true` would match items already in `projectContext.items`.
- **Result:** Confirmed. The `projectContext.items` subscription loads all items for the project (by `projectId`). The transaction's `itemIds` array contains the IDs of those items. Filtering `projectContext.items` where `itemIds.contains(item.id)` is the correct approach.
- **Verdict:** Confirmed

## Resolution
_Build verified. Awaiting user confirmation in the app._

- **Root cause:** `transactionItems` computed property filtered `projectContext.items` by `item.transactionId == transaction.id`, but items don't have `transactionId` set in Firestore. The relationship is one-directional: `transaction.itemIds` holds the item IDs.
- **Fix:** Changed the filter to match `item.id` against `liveTransaction.itemIds` using a Set for O(1) lookups. Also uses `liveTransaction` instead of `transaction` so the items section updates live.
- **Files changed:** `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift` (line 38-41)
