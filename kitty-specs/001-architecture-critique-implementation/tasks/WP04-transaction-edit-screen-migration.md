---
work_package_id: WP04
title: Transaction Edit Screen Migration
lane: "doing"
dependencies: []
base_branch: main
base_commit: 44138a3773cb9b0c00e927dd9b6b6f6540b01521
created_at: '2026-02-09T23:56:48.359199+00:00'
subtasks:
- T017
- T018
- T019
- T020
- T021
- T022
- T023
phase: Phase 2D - Edit Screen Migrations
assignee: ''
agent: "claude-implementer"
shell_pid: "8124"
review_status: "has_feedback"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-09T08:45:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP04 - Transaction Edit Screen Migration

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately (right below this notice).
- **You must address all feedback** before your work is complete. Feedback items are your implementation TODO list.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.
- **Report progress**: As you address each feedback item, update the Activity Log explaining what you changed.

---

## Review Feedback

**Reviewed by**: nine4-team
**Status**: ❌ Changes Requested
**Date**: 2026-02-10

## Review Feedback — WP04

### Issue 1 (Critical): Tax/subtotal computed values not included in Firestore update

**Location**: `app/transactions/[id]/edit.tsx` lines 245-262 (save handler)

`form.setFields()` calls React's `setValues` state setter, which is asynchronous — the state update doesn't take effect until the next render. However, the save handler immediately reads `form.getChangedFields()` and `form.values.*` in the same synchronous block:

```typescript
// Line 247-251: sets computed values (async state update, doesn't take effect yet)
form.setFields({
  subtotal: (subtotalCents / 100).toFixed(2),
  taxRatePct: taxRateValue !== null ? taxRateValue.toFixed(2) : '',
});

// Line 255: reads STALE hasChanges (won't see the setFields above)
if (!form.hasChanges) { ... }

// Line 262: reads STALE changedFields (won't include subtotal/taxRatePct from setFields)
const changedFields = form.getChangedFields();

// Lines 297-304: reads STALE form.values.taxRatePct / form.values.subtotal
if ('taxRatePct' in changedFields) {
  const parsedRate = Number.parseFloat(form.values.taxRatePct); // OLD value
}
```

**Impact**: When the user changes the amount on an itemized category, the computed `subtotalCents` and `taxRatePct` values will NOT be included in the Firestore update. This is a functional regression from the original code, which used local variables directly:

```typescript
// ORIGINAL CODE (correct):
updateTransaction(accountId, id, {
  ...
  taxRatePct: taxRateValue,   // local variable, immediately available
  subtotalCents,              // local variable, immediately available
});
```

**Fix**: Do not use `form.setFields()` for computed values in the save handler. Instead, use the locally-computed `subtotalCents` and `taxRateValue` variables directly when building the update payload, similar to the original code:

```typescript
// After computing subtotalCents and taxRateValue...
if (subtotalCents !== null) {
  updates.subtotalCents = subtotalCents;
  updates.taxRatePct = taxRateValue;
}
```

Move `subtotalCents`/`taxRateValue` declarations outside the `if (itemizationEnabled && ...)` block so they're accessible when building the update payload.

---

### Issue 2 (Out of Scope): HeroSection.tsx changes must be removed

**Location**: `app/transactions/[id]/sections/HeroSection.tsx`

This file is part of the transaction **view/detail** screen, not the edit screen. The WP04 spec is specifically scoped to the edit screen migration. The diff removes the amount+date display from the hero section, reverting the intentional enhancement from commit `a112580` ("feat: enhance transaction hero section with amount and date display").

**Fix**: Revert all changes to `HeroSection.tsx`. This file should not be touched by WP04.

---

### Issue 3 (Out of Scope): .gitignore change must be removed

**Location**: `.gitignore`

Adding `kitty-specs/` to `.gitignore` is a worktree artifact. This line should not be committed — sparse-checkout handles exclusion in worktrees, and adding it to `.gitignore` could mask tracking issues in the main repo.

**Fix**: Revert the `.gitignore` changes.


## Markdown Formatting
Wrap HTML/XML tags in backticks: `` `<div>` ``, `` `<script>` ``
Use language identifiers in code blocks: ````typescript`, ````bash`

---

## How to Implement This Work Package

**Run this command to begin**:
```bash
spec-kitty implement WP04
```

This creates an isolated worktree at `.worktrees/001-architecture-critique-implementation-WP04/` branched from `main`.

---

## Objectives & Success Criteria

**Goal**: Migrate transaction edit screen (13 fields, most complex) from multiple `useState` calls to using the `useEditForm` hook with change tracking, special handling for computed fields (tax/subtotal) and budgetCategoryId propagation to linked items.

**Success Criteria**:
- Transaction edit screen uses `useEditForm<TransactionFormValues>` for all 13 fields
- Save operations include only modified fields in update payloads
- Computed fields (tax, subtotal) correctly included in change tracking after calculation
- BudgetCategoryId changes propagate to linked items (preserve existing logic)
- Saves with no changes skip database writes entirely and navigate immediately
- Subscription updates do not overwrite user edits (protected by `shouldAcceptSubscriptionData`)
- TypeScript compilation passes with no new errors
- Manual testing confirms single-field edits, computed fields, budgetCategoryId propagation, no-change saves, and subscription protection work correctly

**Acceptance Test**:
1. Open transaction edit, change budgetCategoryId only, save → verify update contains only `{budgetCategoryId: "..."}` AND linked items update
2. Open transaction edit, change amount, save → verify update contains `{amount: N, tax: T, subtotal: S}` (computed fields included)
3. Open transaction edit, make no changes, save → verify no Firestore write occurs
4. Open transaction edit, start typing in description, wait for subscription → verify typed value preserved

---

## Context & Constraints

**Prerequisites**:
- Phase 1 complete: `useEditForm` hook exists at `src/hooks/useEditForm.ts` with full API
- Refer to implementation plan: `.plans/architecture-critique-implementation-plan.md` Phase 2F
- Refer to spec: `kitty-specs/001-architecture-critique-implementation/spec.md` User Story 1

**useEditForm Hook API** (from Phase 1):
```typescript
useEditForm<T>(initialData: T | null) → {
  values: T                          // current form state
  setField(key, value)               // update one field, marks hasEdited
  setFields(updates)                 // update multiple fields
  hasEdited: boolean                 // user has touched the form
  getChangedFields(): Partial<T>     // only fields that differ from snapshot
  hasChanges: boolean                // getChangedFields() is non-empty
  shouldAcceptSubscriptionData: bool // true until first setField call
  reset()                           // re-accept subscription data
}
```

**Transaction Fields (13 total)**:
1. `date`: Timestamp (transaction date)
2. `description`: string (transaction details)
3. `amount`: number (total transaction amount in cents)
4. `budgetCategoryId`: string (category reference)
5. `accountId`: string (account reference)
6. `payee`: string (who was paid)
7. `notes`: string (additional details)
8. `tax`: number (computed from amount, in cents)
9. `subtotal`: number (computed from amount, in cents)
10. `attachments`: string[] (media references)
11. `tags`: string[] (labels)
12. `status`: enum (pending, cleared, etc.)
13. `type`: enum (expense, income, transfer)

**Key Constraints**:
- **Computed fields**: Tax and subtotal are calculated in save handler from amount. These computed values must go through `form.setFields()` BEFORE calling `getChangedFields()` so they're included if amount changed.
- **BudgetCategoryId propagation**: Lines 248-252 in existing code propagate budgetCategoryId changes to linked items. Preserve this logic, but only fire if `budgetCategoryId` is in the changed set.
- **Linked items**: Transaction may have linked items (e.g., project items). BudgetCategoryId change must update those items too.
- Use `shouldAcceptSubscriptionData` to gate subscription updates (prevent overwrites during editing)
- Skip write entirely if `hasChanges` is false (after computed field updates)
- Follow offline-first rules: Never `await` Firestore writes, use fire-and-forget with `.catch()`

**Architecture Patterns**:
- Refer to `CLAUDE.md` and `MEMORY.md` for offline-first coding rules
- All `update*` service functions use fire-and-forget writes
- Navigation happens immediately after write dispatch

---

## Subtasks & Detailed Guidance

### Subtask T017 - Replace 13 useState calls with useEditForm<TransactionFormValues>

**Purpose**: Convert transaction edit screen from individual `useState` calls to unified `useEditForm` hook.

**Files**:
- Modify: `app/transactions/[id]/edit.tsx`

**Steps**:
1. **Import the hook**:
   ```typescript
   import { useEditForm } from '@/src/hooks/useEditForm';
   ```

2. **Define form type**:
   ```typescript
   interface TransactionFormValues {
     date: Timestamp | Date; // or string if date picker uses ISO strings
     description: string;
     amount: number; // in cents
     budgetCategoryId: string;
     accountId: string;
     payee: string;
     notes: string;
     tax: number; // in cents
     subtotal: number; // in cents
     attachments: string[];
     tags: string[];
     status: TransactionStatus; // or string if enum not imported
     type: TransactionType; // or string if enum not imported
   }
   ```

3. **Replace useState calls**:
   - **Remove** (13 useState calls):
     - `const [date, setDate] = useState<Date>(new Date())`
     - `const [description, setDescription] = useState<string>('')`
     - `const [amount, setAmount] = useState<number>(0)`
     - `const [budgetCategoryId, setBudgetCategoryId] = useState<string>('')`
     - `const [accountId, setAccountId] = useState<string>('')`
     - `const [payee, setPayee] = useState<string>('')`
     - `const [notes, setNotes] = useState<string>('')`
     - `const [tax, setTax] = useState<number>(0)`
     - `const [subtotal, setSubtotal] = useState<number>(0)`
     - `const [attachments, setAttachments] = useState<string[]>([])`
     - `const [tags, setTags] = useState<string[]>([])`
     - `const [status, setStatus] = useState<string>('pending')`
     - `const [type, setType] = useState<string>('expense')`

   - **Add**:
     ```typescript
     const form = useEditForm<TransactionFormValues>(
       transaction ? {
         date: transaction.date,
         description: transaction.description || '',
         amount: transaction.amount || 0,
         budgetCategoryId: transaction.budgetCategoryId || '',
         accountId: transaction.accountId || '',
         payee: transaction.payee || '',
         notes: transaction.notes || '',
         tax: transaction.tax || 0,
         subtotal: transaction.subtotal || 0,
         attachments: transaction.attachments || [],
         tags: transaction.tags || [],
         status: transaction.status || 'pending',
         type: transaction.type || 'expense'
       } : null
     );
     ```

4. **Update input bindings**:
   - Change `value={description}` to `value={form.values.description}`
   - Change `onChangeText={setDescription}` to `onChangeText={(val) => form.setField('description', val)}`
   - For date picker: `onChange={(val) => form.setField('date', val)}`
   - For pickers/dropdowns: `onValueChange={(val) => form.setField('budgetCategoryId', val)}`
   - For amount input: `onChangeText={(val) => form.setField('amount', parseAmountToCents(val))}`
   - For tag arrays: `onTagsChange={(val) => form.setField('tags', val)}`
   - Repeat for all 13 fields

5. **Tax/subtotal computation handled in T018** (save handler logic)

**Validation**:
- [ ] TypeScript compiles with no errors
- [ ] All 13 fields accessible via `form.values`
- [ ] All input fields update correctly on user input
- [ ] Date picker works with form state
- [ ] Amount field converts to cents correctly

**Edge Cases**:
- Transaction is null during load: Form shows empty/default values
- Fields with null/undefined values: Use `||` operator for safe defaults
- Date field type: Ensure date picker and Firestore Timestamp are compatible
- Array fields (attachments, tags): Handle empty array vs undefined

---

### Subtask T018 - Implement tax/subtotal computation in save handler

**Purpose**: Calculate tax and subtotal from amount in save handler, update form before getting changed fields.

**Files**:
- Modify: `app/transactions/[id]/edit.tsx`

**Steps**:
1. **Locate the save handler** (likely `handleSave` or `handleSubmit`):
   ```typescript
   const handleSave = () => {
     // Existing validation and save logic
   };
   ```

2. **Add computation BEFORE getting changed fields**:
   ```typescript
   const handleSave = () => {
     // Compute tax and subtotal from amount (if amount changed)
     const taxRate = 0.0825; // Example: 8.25% - get from config or props
     const computedTax = Math.round(form.values.amount * taxRate);
     const computedSubtotal = form.values.amount - computedTax;

     // Update form with computed values (this marks them as edited if different)
     form.setFields({
       tax: computedTax,
       subtotal: computedSubtotal
     });

     // NOW get changed fields (will include tax/subtotal if amount changed)
     if (!form.hasChanges) {
       // No changes - skip write, just navigate
       router.back();
       return;
     }

     const changedFields = form.getChangedFields();

     // Rest of save logic...
   };
   ```

3. **Alternative approach** (compute only if amount is in changed fields):
   ```typescript
   const handleSave = () => {
     // Get preliminary changed fields
     const preliminaryChanges = form.getChangedFields();

     // If amount changed, compute and update tax/subtotal
     if ('amount' in preliminaryChanges) {
       const taxRate = 0.0825; // Get from config
       const computedTax = Math.round(form.values.amount * taxRate);
       const computedSubtotal = form.values.amount - computedTax;

       form.setFields({
         tax: computedTax,
         subtotal: computedSubtotal
       });
     }

     // Get final changed fields (now includes computed values if amount changed)
     if (!form.hasChanges) {
       router.back();
       return;
     }

     const changedFields = form.getChangedFields();

     // Continue with save...
   };
   ```

4. **Preserve existing computation logic**: If tax/subtotal calculation is more complex (multiple tax rates, line items, etc.), preserve that logic. Just ensure computed values go through `form.setFields()` before `getChangedFields()`.

**Validation**:
- [ ] Changing amount causes tax and subtotal to be recomputed
- [ ] `getChangedFields()` includes tax and subtotal when amount changes
- [ ] Tax and subtotal not included in changed fields if amount unchanged
- [ ] Computation matches existing behavior (same tax rate, rounding, etc.)

**Edge Cases**:
- Amount is 0: Tax and subtotal should be 0
- Negative amount (refund): Tax calculation may need adjustment
- Tax rate varies by transaction type or account: Use appropriate rate
- Rounding errors: Use `Math.round()` consistently to avoid cents drift

---

### Subtask T019 - Add budgetCategoryId change propagation to linked items

**Purpose**: Preserve existing logic (lines 248-252) that propagates budgetCategoryId changes to linked items, but gate on presence in changed fields.

**Files**:
- Modify: `app/transactions/[id]/edit.tsx`

**Context**:
- **Existing code** (lines 248-252): When budgetCategoryId changes, update all linked items (e.g., project items) to use the same category
- **Requirement**: Preserve this logic, but only fire if `budgetCategoryId` is in the changed set

**Steps**:
1. **Find existing budgetCategoryId propagation logic**:
   ```typescript
   // Lines 248-252 (approximate)
   if (budgetCategoryId !== transaction.budgetCategoryId) {
     // Update linked items
     const linkedItemIds = transaction.linkedItemIds || [];
     linkedItemIds.forEach(itemId => {
       updateItem(itemId, { budgetCategoryId }).catch(console.error);
     });
   }
   ```

2. **Preserve logic, gate on changed fields**:
   ```typescript
   const handleSave = () => {
     // Compute tax/subtotal (from T018)
     // ...

     if (!form.hasChanges) {
       router.back();
       return;
     }

     const changedFields = form.getChangedFields();

     // Propagate budgetCategoryId to linked items if changed
     if ('budgetCategoryId' in changedFields) {
       const linkedItemIds = transaction?.linkedItemIds || [];
       if (linkedItemIds.length > 0) {
         // Fire-and-forget updates for each linked item
         linkedItemIds.forEach(itemId => {
           updateItem(itemId, {
             budgetCategoryId: form.values.budgetCategoryId
           }).catch((err) => {
             console.error('Failed to update linked item:', itemId, err);
           });
         });
       }
     }

     // Update transaction with changed fields
     updateTransaction(transactionId, changedFields).catch((err) => {
       console.error('Failed to update transaction:', err);
     });

     // Navigate immediately (offline-first)
     router.back();
   };
   ```

3. **Ensure linked item updates are fire-and-forget**: No `await`, no blocking on completion

4. **Order of operations**:
   - Compute tax/subtotal
   - Get changed fields
   - Fire linked item updates (if budgetCategoryId changed)
   - Fire transaction update
   - Navigate immediately

**Validation**:
- [ ] Changing budgetCategoryId triggers linked item updates
- [ ] NOT changing budgetCategoryId skips linked item updates
- [ ] Linked item updates use fire-and-forget pattern
- [ ] Transaction update still fires with all changed fields
- [ ] Navigation happens immediately (doesn't wait for linked item writes)

**Edge Cases**:
- No linked items: `linkedItemIds` is empty or undefined, loop doesn't run
- Many linked items: Fire all updates in parallel (forEach, no await)
- Linked item update fails: Logged to console, doesn't block transaction update or navigation
- BudgetCategoryId changed to empty/null: Propagate null to linked items (clears category)

---

### Subtask T020 - Add shouldAcceptSubscriptionData protection

**Purpose**: Prevent subscription updates from overwriting user edits during form interaction.

**Files**:
- Modify: `app/transactions/[id]/edit.tsx`

**Steps**:
1. **Find the subscription effect** (likely `useEffect` listening to `transaction` from query):
   ```typescript
   useEffect(() => {
     if (transaction) {
       // Existing code that updates state when transaction changes
     }
   }, [transaction]);
   ```

2. **Add protection gate**:
   ```typescript
   useEffect(() => {
     if (transaction && form.shouldAcceptSubscriptionData) {
       // Update form values from subscription
       form.setFields({
         date: transaction.date,
         description: transaction.description || '',
         amount: transaction.amount || 0,
         budgetCategoryId: transaction.budgetCategoryId || '',
         accountId: transaction.accountId || '',
         payee: transaction.payee || '',
         notes: transaction.notes || '',
         tax: transaction.tax || 0,
         subtotal: transaction.subtotal || 0,
         attachments: transaction.attachments || [],
         tags: transaction.tags || [],
         status: transaction.status || 'pending',
         type: transaction.type || 'expense'
       });
     }
   }, [transaction, form.shouldAcceptSubscriptionData]);
   ```

3. **Include dependency**: Add `form.shouldAcceptSubscriptionData` to dependency array

4. **Handle date field type**: Ensure date from subscription is compatible with form state (Timestamp → Date conversion if needed)

**Validation**:
- [ ] On initial load, form accepts transaction data correctly
- [ ] After user types in any field, `form.shouldAcceptSubscriptionData` becomes false
- [ ] Subsequent subscription updates do NOT overwrite form values
- [ ] All 13 fields protected from subscription overwrites during editing

**Testing**:
- Simulate subscription update by modifying transaction in Firestore console while editing
- Verify typed value is preserved (not replaced by subscription data)

---

### Subtask T021 - Update save handler with getChangedFields

**Purpose**: Use change tracking to send only modified fields to `updateTransaction`, skip write if no changes.

**Files**:
- Modify: `app/transactions/[id]/edit.tsx`

**Steps**:
1. **Integrate all previous subtasks** into complete save handler:
   ```typescript
   const handleSave = () => {
     // 1. Compute tax/subtotal (T018)
     const preliminaryChanges = form.getChangedFields();
     if ('amount' in preliminaryChanges) {
       const taxRate = 0.0825; // Get from config
       const computedTax = Math.round(form.values.amount * taxRate);
       const computedSubtotal = form.values.amount - computedTax;
       form.setFields({
         tax: computedTax,
         subtotal: computedSubtotal
       });
     }

     // 2. Check for changes
     if (!form.hasChanges) {
       // No changes - skip write, just navigate
       router.back();
       return;
     }

     // 3. Get final changed fields (includes computed values)
     const changedFields = form.getChangedFields();

     // 4. Validation (preserve existing)
     if (changedFields.description !== undefined && form.values.description.trim() === '') {
       // Description required - show error
       return;
     }

     // 5. Propagate budgetCategoryId to linked items (T019)
     if ('budgetCategoryId' in changedFields) {
       const linkedItemIds = transaction?.linkedItemIds || [];
       linkedItemIds.forEach(itemId => {
         updateItem(itemId, {
           budgetCategoryId: form.values.budgetCategoryId
         }).catch((err) => {
           console.error('Failed to update linked item:', itemId, err);
         });
       });
     }

     // 6. Fire-and-forget transaction update
     updateTransaction(transactionId, changedFields).catch((err) => {
       console.error('Failed to update transaction:', err);
       // TODO: Add user-facing error handling
     });

     // 7. Navigate immediately (offline-first)
     router.back();
   };
   ```

2. **Remove any `await` on updates**: Ensure all writes are fire-and-forget

3. **Remove any `isSubmitting` state**: Navigation should happen immediately, not gate on write completion

4. **Preserve existing validation**: Keep required fields, amount limits, etc.

**Validation**:
- [ ] No-change save navigates without calling `updateTransaction`
- [ ] Single-field change sends only that field (unless computed fields triggered)
- [ ] Amount change sends amount + tax + subtotal
- [ ] BudgetCategoryId change sends budgetCategoryId + triggers linked item updates
- [ ] Multi-field change sends all changed fields
- [ ] Navigation happens immediately (no spinner waiting on writes)
- [ ] Existing validation preserved

**Edge Cases**:
- User changes amount then budgetCategoryId: Changed fields include amount, tax, subtotal, budgetCategoryId
- User changes field then reverts: `hasChanges` should be false
- Required field validation: Only validate fields that are changed or currently invalid
- Date field in changed fields: Ensure Firestore accepts the date format (Timestamp vs Date)

---

### Subtask T022 - Verify TypeScript compilation passes

**Purpose**: Ensure no new TypeScript errors were introduced by the changes.

**Steps**:
1. Run TypeScript compiler:
   ```bash
   npx tsc --noEmit
   ```

2. **Expected output**: All errors should be pre-existing (documented in MEMORY.md)

3. **If new errors appear**:
   - Review the error messages
   - Common issues:
     - `form.values` property access type errors (ensure `TransactionFormValues` matches all field types)
     - Date field type mismatch (Timestamp vs Date)
     - Computed field types (`tax`, `subtotal` as `number`)
     - Array field types (`attachments: string[]`, `tags: string[]`)
     - Missing imports for helper functions or types
     - `getChangedFields()` return type compatibility with `updateTransaction` parameter
     - Linked items iteration type errors

4. **Pre-existing errors are OK** (do not fix):
   - `__tests__/` files: missing `@types/jest`
   - `SharedItemsList.tsx`, `SharedTransactionsList.tsx`: icon type mismatches
   - `resolveItemMove.ts`: variable shadowing
   - `settings.tsx`: `BudgetCategoryType` union mismatch
   - `accountContextStore.ts`: null handling

**Validation**:
- [ ] `tsc --noEmit` completes without new errors
- [ ] All new code passes type checking
- [ ] Pre-existing errors remain unchanged
- [ ] Computed field calculations have correct types

---

### Subtask T023 - Manual verification of transaction edit screen

**Purpose**: Manually test the transaction edit screen to verify change tracking, computed fields, and budgetCategoryId propagation work correctly.

**Test Script**:

**Setup**:
1. Open the app
2. Navigate to any transaction detail screen
3. Tap Edit button to open transaction edit screen
4. Ensure test transaction has at least one linked item (for budgetCategoryId propagation test)

**Test Case 1: No-change save**
1. Open transaction edit
2. Do NOT modify any fields
3. Tap Save
4. **Verify**:
   - [ ] Navigation happens immediately
   - [ ] Console shows no `updateTransaction` call
   - [ ] No Firestore write in network tab

**Test Case 2: Description-only edit**
1. Open transaction edit
2. Change description field only (e.g., "Lunch" → "Team Lunch")
3. Tap Save
4. **Verify**:
   - [ ] Console/network shows update with only `{description: "Team Lunch"}`
   - [ ] Transaction detail shows new description
   - [ ] All other fields unchanged

**Test Case 3: Amount edit (triggers computed fields)**
1. Open transaction edit
2. Note current tax and subtotal values
3. Change amount field only (e.g., $100 → $150)
4. Tap Save
5. **Verify**:
   - [ ] Update contains `{amount: 15000, tax: <computed>, subtotal: <computed>}` (all in cents)
   - [ ] Tax and subtotal values are recomputed based on new amount
   - [ ] Other fields not included (description, budgetCategoryId, etc.)

**Test Case 4: BudgetCategoryId edit (triggers linked item propagation)**
1. Open transaction edit for transaction WITH linked items
2. Note current budgetCategoryId and linked item IDs
3. Change budgetCategoryId to a different category
4. Tap Save
5. **Verify**:
   - [ ] Transaction update contains `{budgetCategoryId: "new-category-id"}`
   - [ ] Console shows `updateItem` calls for each linked item with same budgetCategoryId
   - [ ] Navigation happens immediately (doesn't wait for linked item writes)
   - [ ] After sync, linked items have new budgetCategoryId

**Test Case 5: Multi-field edit**
1. Open transaction edit
2. Change description, payee, and notes
3. Tap Save
4. **Verify**:
   - [ ] Update contains `{description: "...", payee: "...", notes: "..."}`
   - [ ] Amount, tax, subtotal not included (unchanged)

**Test Case 6: Date change**
1. Open transaction edit
2. Change date via date picker
3. Tap Save
4. **Verify**:
   - [ ] Update contains `{date: <new-date>}`
   - [ ] Date format is correct for Firestore (Timestamp or ISO string)
   - [ ] Transaction detail shows new date

**Test Case 7: Account change**
1. Open transaction edit
2. Change account via picker/dropdown
3. Tap Save
4. **Verify**:
   - [ ] Update contains `{accountId: "new-account-id"}`
   - [ ] Transaction detail shows new account label

**Test Case 8: Tags/attachments change**
1. Open transaction edit
2. Add or remove tags
3. Tap Save
4. **Verify**:
   - [ ] Update contains `{tags: ["tag1", "tag2", ...]}`
   - [ ] Transaction detail shows updated tags

**Test Case 9: Status change**
1. Open transaction edit
2. Change status (e.g., "pending" → "cleared")
3. Tap Save
4. **Verify**:
   - [ ] Update contains `{status: "cleared"}`
   - [ ] Transaction detail shows new status

**Test Case 10: Subscription protection**
1. Open transaction edit
2. Start typing in description field
3. Simulate subscription update (modify transaction in another device/Firestore console)
4. **Verify**:
   - [ ] Typed value in description field is preserved (not overwritten)
   - [ ] Form continues to work normally

**Test Case 11: Amount + budgetCategoryId change (combined)**
1. Open transaction edit with linked items
2. Change amount (e.g., $100 → $200)
3. Change budgetCategoryId
4. Tap Save
5. **Verify**:
   - [ ] Update contains `{amount: 20000, tax: <computed>, subtotal: <computed>, budgetCategoryId: "..."}`
   - [ ] Linked items receive budgetCategoryId update
   - [ ] All computed fields correct

**Test Case 12: Revert changes**
1. Open transaction edit
2. Change description field
3. Change it back to original value
4. Tap Save
5. **Verify**:
   - [ ] Navigation happens (no write, change was reverted)
   - [ ] Transaction unchanged in detail screen

**Test Case 13: No linked items (budgetCategoryId change)**
1. Open transaction edit WITHOUT linked items
2. Change budgetCategoryId
3. Tap Save
4. **Verify**:
   - [ ] Transaction update contains `{budgetCategoryId: "..."}`
   - [ ] No linked item updates fired (linkedItemIds is empty)
   - [ ] No errors in console

**Debugging Tips**:
- Add `console.log('Changed fields:', form.getChangedFields())` before save
- Add `console.log('Computed tax:', computedTax, 'subtotal:', computedSubtotal)` to verify calculations
- Add `console.log('Linked item IDs:', linkedItemIds)` to verify propagation
- Check React Native debugger network tab for Firestore payloads
- Verify cents values are integers (no floating point)
- Check that linked item updates fire in parallel (no sequential delays)

**Validation Checklist**:
- [ ] All 13 test cases pass
- [ ] No TypeScript errors in console
- [ ] No runtime errors during testing
- [ ] Computed fields (tax/subtotal) calculated correctly
- [ ] BudgetCategoryId propagation works for linked items
- [ ] Change tracking detects all field types (string, number, date, array)
- [ ] Subscription protection works reliably
- [ ] Navigation is immediate (offline-first)
- [ ] Fire-and-forget pattern used for all writes

---

## Test Strategy

**No automated tests required for this work package.**

Manual testing (T023) provides comprehensive verification for form behavior, computed fields, and linked item propagation.

---

## Risks & Mitigations

**Risk 1: Computed field calculation errors**
- **Mitigation**: Preserve existing tax/subtotal computation logic exactly. Test with various amounts to verify calculations.
- **Verification**: Compare computed values against existing behavior (before migration)

**Risk 2: BudgetCategoryId propagation breaks or creates inconsistency**
- **Mitigation**: Preserve exact logic from lines 248-252. Only gate on field presence in changed set. Use fire-and-forget for linked item updates.
- **Verification**: Test with transactions that have multiple linked items. Verify all update correctly.

**Risk 3: Form state complexity with 13 fields**
- **Mitigation**: Use `useEditForm` hook to centralize state management. Test each field type independently.
- **Verification**: Test each of the 13 fields in isolation before testing combinations

**Risk 4: Date field type compatibility (Timestamp vs Date)**
- **Mitigation**: Ensure date picker output matches Firestore Timestamp format. Convert if needed.
- **Verification**: Test date changes, verify Firestore accepts the format

**Risk 5: Subscription timing issues (overwrites during typing)**
- **Mitigation**: Use `shouldAcceptSubscriptionData` to gate all subscription updates
- **Verification**: Simulate subscription during editing, verify typed value preserved

**Risk 6: Linked item updates fail silently**
- **Mitigation**: Log errors for linked item updates. Don't block transaction update on linked item failures.
- **Verification**: Test with intentional failures (invalid item IDs), verify transaction still updates

---

## Review Guidance

**Key Checkpoints for `/spec-kitty.review`**:

1. **Code Review**:
   - [ ] Transaction edit uses `useEditForm<TransactionFormValues>` with correct generic type
   - [ ] All 13 fields included in form type and initialization
   - [ ] Tax/subtotal computation BEFORE `getChangedFields()` call
   - [ ] BudgetCategoryId propagation logic preserved (lines 248-252)
   - [ ] Propagation only fires if `budgetCategoryId` in changed fields
   - [ ] Linked item updates use fire-and-forget (no `await`)
   - [ ] `getChangedFields()` used before `updateTransaction` call
   - [ ] No-change check exists before update call
   - [ ] All Firestore writes use fire-and-forget (no `await`)
   - [ ] Navigation happens immediately after write dispatch
   - [ ] Subscription effect checks `shouldAcceptSubscriptionData`

2. **Testing Evidence**:
   - [ ] T023 manual testing checklist fully completed (all 13 test cases)
   - [ ] Screenshots or logs showing computed fields in payloads (optional)
   - [ ] Evidence of linked item propagation (logs or console output)
   - [ ] Confirmation that TypeScript compilation passes

3. **Pattern Consistency**:
   - [ ] Follows same pattern as WP01-WP03 (useEditForm hook, change tracking)
   - [ ] Error handling consistent (fire-and-forget with `.catch()`)
   - [ ] No await on Firestore writes (offline-first)
   - [ ] Computed fields included in change tracking correctly

**Questions for Reviewer**:
- Are computed fields (tax/subtotal) included correctly when amount changes?
- Does budgetCategoryId propagation work for all linked items?
- Are there any edge cases with date field type conversions?
- Is the existing validation logic preserved correctly?
- Does subscription protection work reliably with 13 fields?

---

## Activity Log

> **CRITICAL**: Activity log entries MUST be in chronological order (oldest first, newest last).

### How to Add Activity Log Entries

**When adding an entry**:
1. Scroll to the bottom of this file (Activity Log section below "Valid lanes")
2. **APPEND the new entry at the END** (do NOT prepend or insert in middle)
3. Use exact format: `- YYYY-MM-DDTHH:MM:SSZ - agent_id - lane=<lane> - <action>`
4. Timestamp MUST be current time in UTC (check with `date -u "+%Y-%m-%dT%H:%M:%SZ"`)
5. Lane MUST match the frontmatter `lane:` field exactly
6. Agent ID should identify who made the change (claude-sonnet-4-5, codex, etc.)

**Format**:
```
- YYYY-MM-DDTHH:MM:SSZ - <agent_id> - lane=<lane> - <brief action description>
```

**Valid lanes**: `planned`, `doing`, `for_review`, `done`

**Initial entry**:
- 2026-02-09T08:45:00Z - system - lane=planned - Prompt created via /spec-kitty.tasks
- 2026-02-09T23:56:48Z – claude-implementer – shell_pid=85892 – lane=doing – Assigned agent via workflow command
- 2026-02-10T00:01:52Z – claude-implementer – shell_pid=85892 – lane=for_review – Ready for review: Transaction edit screen migrated to useEditForm with full change tracking, tax/subtotal computation, budgetCategoryId propagation, and subscription protection. TypeScript compilation passes with no new errors.
- 2026-02-10T00:06:34Z – claude-reviewer – shell_pid=97486 – lane=doing – Started review via workflow command
- 2026-02-10T00:09:34Z – claude-reviewer – shell_pid=97486 – lane=planned – Moved to planned
- 2026-02-10T00:15:55Z – claude-implementer – shell_pid=8124 – lane=doing – Started implementation via workflow command
