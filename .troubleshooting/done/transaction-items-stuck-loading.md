# Issue: Transaction items stuck at "Loading items..." when navigating from item detail

**Status:** Resolved
**Opened:** 2026-02-10
**Resolved:** 2026-02-10

## Context
- **Symptom:** When clicking on a transaction link from an item detail screen, the transaction detail screen shows "Loading items..." indefinitely instead of displaying the items list
- **Affected area:** Transaction detail screen (`app/transactions/[id]/index.tsx`), item detail screen navigation
- **Severity:** Blocks user
- **Reproduction steps:**
  1. Open an item detail screen
  2. Click on the linked transaction text (e.g., "Transaction: <name>")
  3. Transaction detail screen opens but items section shows "Loading items..." and never loads
- **Environment:** React Native, current branch: main

## Research

### Navigation Flows Identified

**Working flow (from transactions list):**
- File: `src/components/SharedTransactionsList.tsx:1171-1180`
- Passes all required params: `id`, `scope`, `projectId`, `listStateKey`, `backTarget`

**Broken flow (from item detail hero card):**
- File: `app/items/[id]/index.tsx:536`
- Uses simplified navigation: `router.push(\`/transactions/${item.transactionId}\`)`
- **Missing params:** `scope`, `projectId`

**Correct flow in same file (handleOpenTransaction):**
- File: `app/items/[id]/index.tsx:191-199`
- Passes all required params correctly

### Transaction Detail Screen Dependencies

File: `app/transactions/[id]/index.tsx:165-180`

The items loading `useEffect` has a hard dependency on `scope` param:
```typescript
if (!accountId || !id || !scope) {
  setItems([]);
  return;
}
```

If `scope` is missing, it returns early and sets `items = []`, preventing the subscription to `subscribeToScopedItems`.

### SharedItemsList Loading State Issue

File: `src/components/SharedItemsList.tsx`

1. `isLoading` initialized to `true` (line 201)
2. In embedded mode, all loading state management is skipped (lines 296-300, 334-337)
3. Parent (transaction detail) never manages `isLoading` — only passes empty array
4. Result: `isLoading` stays `true` forever, showing "Loading items..."

## Investigation Log

### H1: Missing navigation parameters cause items to never load
- **Rationale:** Hero card navigation uses simplified `router.push(\`/transactions/${id}\`)` syntax, which doesn't pass `scope` and `projectId` params. Transaction detail screen requires these params to load items.
- **Experiment:** Compare navigation code in item detail hero card (line 536) vs handleOpenTransaction (lines 191-199) vs working transactions list navigation. Check transaction detail's items loading logic for param dependencies.
- **Evidence:**
  - Item detail hero card: `router.push(\`/transactions/${item.transactionId}\`)` — no params (line 536)
  - Transaction detail requires `scope`: `if (!accountId || !id || !scope) { setItems([]); return; }` (line 166)
  - SharedItemsList in embedded mode skips all `isLoading` management, relies on parent
  - `isLoading` initialized to `true`, never updated when items array is empty
- **Verdict:** Confirmed

## Conclusion

**Root Cause:** The transaction link in the item detail hero card uses simplified navigation syntax that doesn't include the required `scope` and `projectId` parameters.

**Chain of Failures:**
1. Hero card uses `router.push(\`/transactions/${id}\`)` without params object (line 536)
2. Transaction detail screen receives no `scope` param
3. Items loading `useEffect` returns early due to missing `scope` (line 166)
4. `setItems([])` is called with empty array
5. `SharedItemsList` in embedded mode doesn't manage its own `isLoading` state
6. `isLoading` stays `true`, displays "Loading items..." indefinitely

**Evidence:**
- Broken nav: `app/items/[id]/index.tsx:536`
- Correct pattern exists in same file: `app/items/[id]/index.tsx:191-199` (handleOpenTransaction)
- Working reference: `src/components/SharedTransactionsList.tsx:1171-1180`
- Dependency: `app/transactions/[id]/index.tsx:166`

## Resolution
- **Fix:** Changed hero card transaction link navigation from simplified string syntax to object-based syntax with all required params (`scope`, `projectId`, `backTarget`)
- **Files changed:**
  - `app/items/[id]/index.tsx:536` — Updated hero card `onPress` handler to pass all navigation params
- **Commit:** 622ee8b
- **Verified by user:** Yes

## Lessons Learned
- Simplified navigation syntax (`router.push(\`/path/${id}\`)`) doesn't pass route params, only the dynamic segment
- When refactoring navigation, check that all nav paths to a screen pass the same required params
- Transaction/item detail screens have hard dependencies on scope params for data loading — missing params cause silent failures
- SharedItemsList in embedded mode delegates loading state to parent — parent must ensure params are valid before rendering
