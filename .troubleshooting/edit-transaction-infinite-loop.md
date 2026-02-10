# Issue: EditTransactionScreen Infinite Loop (Maximum Update Depth)

**Status:** Active
**Opened:** 2026-02-09
**Resolved:** _pending_

## Context
- **Symptom:** React Native warning "Maximum update depth exceeded" in EditTransactionScreen. A useEffect is calling setState in a way that triggers itself repeatedly, causing an infinite render loop.
- **Affected area:** `app/transactions/[id]/edit.tsx` - EditTransactionScreen component
- **Severity:** Blocks user - infinite loop can freeze UI and drain battery
- **Reproduction steps:** Navigate to edit transaction screen
- **Environment:**
  - Branch: main
  - React Native mobile app
  - Error stack shows: EditTransactionScreen → Route → NativeStackNavigator

## Research

**EditTransactionScreen structure:**
- Lines 101-113: useEffect subscribing to transaction
- Lines 115-121: useEffect subscribing to budget categories
- Lines 124-139: useEffect subscribing to scoped items
- Lines 71-87: Calls `useEditForm` hook with form initial data object

**useEditForm hook analysis (src/hooks/useEditForm.ts):**
- Lines 35-52: useEffect that depends on `[initialData, hasEdited]`
- When `initialData` is non-null, it calls `setValues(initialData)` to update form state
- This is designed to accept subscription updates until user edits

**The smoking gun:**
In EditTransactionScreen lines 71-87, the form initial data is created as a NEW OBJECT on every render:
```typescript
const form = useEditForm<TransactionFormValues>(
  transaction ? {
    source: transaction.source ?? '',
    transactionDate: transaction.transactionDate ?? '',
    // ... etc
  } : null
);
```

Even though the VALUES are the same, JavaScript creates a new object reference every render. The useEffect in useEditForm depends on `initialData` by reference, so it sees it as changed every time → calls `setValues` → triggers re-render → creates new object → useEffect fires again → infinite loop!

## Investigation Log

### H1: Form initial data object recreated on every render
- **Rationale:** The useEditForm hook has a useEffect that depends on `initialData`. In EditTransactionScreen, the initial data is created as a new object literal on every render (lines 71-87). Even if the transaction object reference is stable, the transformation creates a new object each time, causing useEffect to fire infinitely.
- **Experiment:** Examined EditTransactionScreen form initialization and useEditForm's useEffect dependencies
- **Evidence:**
  - `EditTransactionScreen:71-87` - Creates new object: `transaction ? { source: ..., transactionDate: ... } : null`
  - `useEditForm.ts:35-52` - useEffect depends on `[initialData, hasEdited]` and calls `setValues(initialData)`
  - Object reference changes every render even if transaction is stable
  - useEffect fires → setValues → re-render → new object → useEffect fires → infinite loop
- **Verdict:** **Confirmed** - This is the root cause

## Conclusion

The infinite loop is caused by creating a new form initial data object on every render in EditTransactionScreen. The `useEditForm` hook's useEffect depends on the `initialData` parameter by reference, so when a new object is passed each render, it triggers the effect, which calls `setValues`, causing a re-render, which creates another new object, repeating infinitely.

**Fix:** Wrap the form initial data object in `useMemo` with `transaction` as the dependency, so the object reference only changes when the transaction actually changes.

## Resolution
- **Fix:** Wrap form initial data in `useMemo` hook in EditTransactionScreen
- **File to change:** `app/transactions/[id]/edit.tsx` (lines 71-87)
- **Change needed:**
  ```typescript
  // Add useMemo import at top
  import { useEffect, useMemo, useState } from 'react';

  // Replace lines 71-87 with:
  const formInitialData = useMemo(() =>
    transaction ? {
      source: transaction.source ?? '',
      transactionDate: transaction.transactionDate ?? '',
      amount: typeof transaction.amountCents === 'number' ? (transaction.amountCents / 100).toFixed(2) : '',
      status: transaction.status ?? '',
      purchasedBy: transaction.purchasedBy ?? '',
      reimbursementType: transaction.reimbursementType ?? '',
      notes: transaction.notes ?? '',
      type: transaction.transactionType ?? '',
      budgetCategoryId: transaction.budgetCategoryId ?? '',
      hasEmailReceipt: !!transaction.hasEmailReceipt,
      taxRatePct: typeof transaction.taxRatePct === 'number' ? transaction.taxRatePct.toFixed(2) : '',
      subtotal: typeof transaction.subtotalCents === 'number' ? (transaction.subtotalCents / 100).toFixed(2) : '',
      taxAmount: '',
    } : null,
    [transaction]
  );

  const form = useEditForm<TransactionFormValues>(formInitialData);
  ```
- **Files changed:**
  - `app/transactions/[id]/edit.tsx` (lines 71-91) - Wrapped form initial data in useMemo
  - `app/items/[id]/edit.tsx` (lines 65-81) - Same fix applied (had same bug)
- **Commit:** _pending_
- **Verified by user:** Pending

## Pattern Analysis

**Feature 001 work packages:**
- **WP01** (commit `40608cf`): Fixed this exact issue - "wrap initialData in useMemo to prevent infinite render loop" for 3 simple edit screens
- **WP03** (commit `403f833`): Migrated item edit screen - missed the useMemo pattern ❌
- **WP04** (commit `a5c0f86`): Migrated transaction edit screen - missed the useMemo pattern ❌
- **Project edit screen**: Correctly uses useMemo ✓

**Inconsistency:** The fix pattern was established in WP01 but not consistently applied in subsequent WP03 and WP04 migrations.

## Lessons Learned

1. **useEditForm pattern requirement:** When passing computed object literals to `useEditForm`, ALWAYS wrap them in `useMemo` with the source data as the dependency. The hook's internal useEffect depends on reference equality, so a new object on every render causes infinite loops.

2. **Pattern consistency across work packages:** When a fix pattern is established in one WP (like WP01's useMemo requirement), it must be documented and applied consistently in all subsequent related work. Consider adding pattern requirements to CLAUDE.md or creating a patterns guide.

3. **Code review checklist:** For useEditForm migrations, verify:
   - Is the initial data wrapped in useMemo?
   - Are the dependencies correct (the source object, not derived fields)?
   - Are there any other object/array literals being passed to hooks without memoization?

4. **Hook design consideration:** The useEditForm hook could potentially be made more resilient by using deep equality checking instead of reference equality, but that has performance tradeoffs. The current approach is correct if used properly.

