---
work_package_id: WP03
title: Item Edit Screen Migration
lane: "planned"
dependencies: []
base_branch: main
base_commit: c64b91de6acfeaa5d4c063c8d2d2c91eaaffabef
created_at: '2026-02-09T21:22:48.324318+00:00'
subtasks:
- T011
- T012
- T013
- T014
- T015
- T016
phase: Phase 2C - Edit Screen Migrations
assignee: ''
agent: "claude-reviewer-3"
shell_pid: "59448"
review_status: "has_feedback"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-09T08:45:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP03 - Item Edit Screen Migration

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
**Date**: 2026-02-09

# WP03 Review Feedback - Changes Requested

Reviewer: claude-reviewer-3
Date: 2026-02-09

## Critical Issue: Incomplete Subscription Protection

**Location**: [app/items/[id]/edit.tsx:126-145](app/items/[id]/edit.tsx#L126-L145)

**Problem**: The subscription effect (lines 126-145) only updates the display strings for price fields, but **does NOT update the form values** via `form.setFields()`. This violates the spec requirement in T013.

**Current Code**:
```typescript
useEffect(() => {
  if (item && form.shouldAcceptSubscriptionData) {
    // Only updates display strings - form values are NOT updated!
    setPurchasePriceDisplay(...);
    setProjectPriceDisplay(...);
    setMarketValueDisplay(...);
  }
}, [item, form.shouldAcceptSubscriptionData]);
```

**Expected (per spec lines 408-442)**:
```typescript
useEffect(() => {
  if (item && form.shouldAcceptSubscriptionData) {
    // Update form values from subscription
    form.setFields({
      name: item.name || '',
      source: item.source ?? null,
      sku: item.sku ?? null,
      status: item.status ?? null,
      purchasePriceCents: item.purchasePriceCents ?? null,
      projectPriceCents: item.projectPriceCents ?? null,
      marketValueCents: item.marketValueCents ?? null,
      notes: item.notes ?? null,
      spaceId: item.spaceId ?? null,
    });

    // Update display strings too
    setPurchasePriceDisplay(
      item.purchasePriceCents !== null && item.purchasePriceCents !== undefined
        ? formatCentsToDisplay(item.purchasePriceCents)
        : ''
    );
    setProjectPriceDisplay(
      item.projectPriceCents !== null && item.projectPriceCents !== undefined
        ? formatCentsToDisplay(item.projectPriceCents)
        : ''
    );
    setMarketValueDisplay(
      item.marketValueCents !== null && item.marketValueCents !== undefined
        ? formatCentsToDisplay(item.marketValueCents)
        : ''
    );
  }
}, [item, form.shouldAcceptSubscriptionData]);
```

**Why This Matters**: Without calling `form.setFields()`, the form values won't reflect subscription updates. The form will be stuck with the initial values from the hook initialization (line 65-77), and any subscription updates will only affect display strings, causing a disconnect between form state and displayed values.

**Fix Required**: Add `form.setFields()` call at the start of the subscription effect to update all 9 form fields, then update display strings.

---

## Summary

- ✅ All 9 fields correctly migrated to `useEditForm<ItemFormValues>`
- ✅ Price field handlers correctly convert display → cents → `setField()`
- ✅ Save handler uses `getChangedFields()` for partial updates
- ✅ No-change saves skip Firestore writes (line 192-196)
- ✅ TypeScript compilation passes with no new errors
- ✅ Offline-first pattern followed (no `await` on `updateItem`)
- ❌ **Subscription effect incomplete - missing `form.setFields()` call**

**Action Required**: Add `form.setFields()` call to the subscription effect before updating display strings.


## Markdown Formatting
Wrap HTML/XML tags in backticks: `` `<div>` ``, `` `<script>` ``
Use language identifiers in code blocks: ````typescript`, ````bash`

---

## How to Implement This Work Package

**Run this command to begin**:
```bash
spec-kitty implement WP03
```

This creates an isolated worktree at `.worktrees/001-architecture-critique-implementation-WP03/` branched from `main`.

---

## Objectives & Success Criteria

**Goal**: Migrate item edit screen (9 fields) from multiple `useState` calls to using the `useEditForm` hook with change tracking, special handling for price fields (cents values).

**Success Criteria**:
- Item edit screen uses `useEditForm<ItemFormValues>` for all 9 fields
- Price fields (3) correctly track cents values in form state while displaying formatted strings
- Save operations include only modified fields in update payloads
- Saves with no changes skip database writes entirely and navigate immediately
- Subscription updates do not overwrite user edits (protected by `shouldAcceptSubscriptionData`)
- TypeScript compilation passes with no new errors
- Manual testing confirms single-field edits, price handling, no-change saves, and subscription protection work correctly

**Acceptance Test**:
1. Open item edit, change name only, save → verify update payload contains only `{name: "..."}`
2. Open item edit, change estimatedPrice to $15.99, save → verify payload contains `{estimatedPriceCents: 1599}`
3. Open item edit, make no changes, save → verify no Firestore write occurs
4. Open item edit, start typing in description, wait for subscription → verify typed value preserved

---

## Context & Constraints

**Prerequisites**:
- Phase 1 complete: `useEditForm` hook exists at `src/hooks/useEditForm.ts` with full API
- Refer to implementation plan: `.plans/architecture-critique-implementation-plan.md` Phase 2E
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

**Item Fields (9 total)**:
1. `name`: string (item title)
2. `description`: string (details)
3. `spaceId`: string (location reference)
4. `status`: enum (active, archived, etc.)
5. `estimatedPriceCents`: number (planning price in cents)
6. `purchasePriceCents`: number (actual buy price in cents)
7. `salePriceCents`: number (actual sell price in cents)
8. `quantity`: number (item count)
9. `tags`: string[] (labels)

**Key Constraints**:
- **Price fields**: Hook tracks cents values (data model), but UI shows formatted strings. On change, parse display string to cents and call `setField('estimatedPriceCents', centsValue)`.
- **Separate display strings**: Keep 3 separate `useState` for price display strings (`estimatedPriceDisplay`, `purchasePriceDisplay`, `salePriceDisplay`). These are UI-only, not tracked by hook.
- Use `shouldAcceptSubscriptionData` to gate subscription updates (prevent overwrites during editing)
- Skip write entirely if `hasChanges` is false
- Follow offline-first rules: Never `await` Firestore writes, use fire-and-forget with `.catch()`

**Architecture Patterns**:
- Refer to `CLAUDE.md` and `MEMORY.md` for offline-first coding rules
- All `update*` service functions use fire-and-forget writes
- Navigation happens immediately after write dispatch

---

## Subtasks & Detailed Guidance

### Subtask T011 - Replace 9 useState calls with useEditForm<ItemFormValues>

**Purpose**: Convert item edit screen from individual `useState` calls to unified `useEditForm` hook.

**Files**:
- Modify: `app/items/[id]/edit.tsx`

**Steps**:
1. **Import the hook**:
   ```typescript
   import { useEditForm } from '@/src/hooks/useEditForm';
   ```

2. **Define form type**:
   ```typescript
   interface ItemFormValues {
     name: string;
     description: string;
     spaceId: string;
     status: ItemStatus; // or string if enum not imported
     estimatedPriceCents: number | null;
     purchasePriceCents: number | null;
     salePriceCents: number | null;
     quantity: number;
     tags: string[];
   }
   ```

3. **Replace useState calls**:
   - **Remove** (9 useState calls):
     - `const [name, setName] = useState<string>('')`
     - `const [description, setDescription] = useState<string>('')`
     - `const [spaceId, setSpaceId] = useState<string>('')`
     - `const [status, setStatus] = useState<string>('')`
     - `const [estimatedPriceCents, setEstimatedPriceCents] = useState<number | null>(null)`
     - `const [purchasePriceCents, setPurchasePriceCents] = useState<number | null>(null)`
     - `const [salePriceCents, setSalePriceCents] = useState<number | null>(null)`
     - `const [quantity, setQuantity] = useState<number>(1)`
     - `const [tags, setTags] = useState<string[]>([])`

   - **Add**:
     ```typescript
     const form = useEditForm<ItemFormValues>(
       item ? {
         name: item.name || '',
         description: item.description || '',
         spaceId: item.spaceId || '',
         status: item.status || 'active',
         estimatedPriceCents: item.estimatedPriceCents ?? null,
         purchasePriceCents: item.purchasePriceCents ?? null,
         salePriceCents: item.salePriceCents ?? null,
         quantity: item.quantity ?? 1,
         tags: item.tags || []
       } : null
     );
     ```

4. **Keep separate display strings** (UI-only state):
   ```typescript
   // These track formatted display strings, NOT data model values
   const [estimatedPriceDisplay, setEstimatedPriceDisplay] = useState<string>('');
   const [purchasePriceDisplay, setPurchasePriceDisplay] = useState<string>('');
   const [salePriceDisplay, setSalePriceDisplay] = useState<string>('');
   ```

5. **Update input bindings** (non-price fields):
   - Change `value={name}` to `value={form.values.name}`
   - Change `onChangeText={setName}` to `onChangeText={(val) => form.setField('name', val)}`
   - Repeat for: description, spaceId, status, quantity, tags
   - For picker/dropdown components: `onValueChange={(val) => form.setField('spaceId', val)}`
   - For tag arrays: `onTagsChange={(val) => form.setField('tags', val)}`

6. **Price fields handled in T012** (special conversion logic)

**Validation**:
- [ ] TypeScript compiles with no errors
- [ ] All 9 fields accessible via `form.values`
- [ ] Non-price fields update correctly on user input
- [ ] Display strings remain independent (not tracked by hook)

**Edge Cases**:
- Item is null during load: Form shows empty/default values
- Fields with null/undefined values: Use `??` operator for safe defaults
- Array fields (tags): Handle empty array vs undefined

---

### Subtask T012 - Implement price field handling (cents values)

**Purpose**: Connect price display strings (UI) to cents values (data model) with proper conversion.

**Files**:
- Modify: `app/items/[id]/edit.tsx`

**Steps**:
1. **Initialize display strings from cents values**:
   ```typescript
   useEffect(() => {
     if (item) {
       // Convert cents to display strings
       setEstimatedPriceDisplay(
         item.estimatedPriceCents !== null
           ? formatCentsToDisplay(item.estimatedPriceCents)
           : ''
       );
       setPurchasePriceDisplay(
         item.purchasePriceCents !== null
           ? formatCentsToDisplay(item.purchasePriceCents)
           : ''
       );
       setSalePriceDisplay(
         item.salePriceCents !== null
           ? formatCentsToDisplay(item.salePriceCents)
           : ''
       );
     }
   }, [item]);
   ```

2. **Price input handlers** (convert display string → cents → update form):
   ```typescript
   const handleEstimatedPriceChange = (displayValue: string) => {
     // Update display string (for UI)
     setEstimatedPriceDisplay(displayValue);

     // Parse to cents and update form (for data model)
     const centsValue = parseDisplayToCents(displayValue);
     form.setField('estimatedPriceCents', centsValue);
   };

   const handlePurchasePriceChange = (displayValue: string) => {
     setPurchasePriceDisplay(displayValue);
     const centsValue = parseDisplayToCents(displayValue);
     form.setField('purchasePriceCents', centsValue);
   };

   const handleSalePriceChange = (displayValue: string) => {
     setSalePriceDisplay(displayValue);
     const centsValue = parseDisplayToCents(displayValue);
     form.setField('salePriceCents', centsValue);
   };
   ```

3. **Update price input bindings**:
   ```tsx
   <TextInput
     value={estimatedPriceDisplay}
     onChangeText={handleEstimatedPriceChange}
     keyboardType="decimal-pad"
     placeholder="$0.00"
   />
   {/* Repeat for purchase and sale price */}
   ```

4. **Helper functions** (may already exist, verify):
   ```typescript
   // Convert cents to display string: 1599 → "15.99"
   const formatCentsToDisplay = (cents: number): string => {
     return (cents / 100).toFixed(2);
   };

   // Parse display string to cents: "15.99" → 1599, "" → null
   const parseDisplayToCents = (display: string): number | null => {
     const cleaned = display.replace(/[^0-9.]/g, '');
     if (!cleaned) return null;
     const dollars = parseFloat(cleaned);
     if (isNaN(dollars)) return null;
     return Math.round(dollars * 100);
   };
   ```

**Validation**:
- [ ] Display strings show formatted values (e.g., "15.99")
- [ ] Typing in price field updates both display string and form.values cents
- [ ] `form.values.estimatedPriceCents` contains integer cents (1599 for "$15.99")
- [ ] Empty price input stores `null` in form (not 0)
- [ ] Price changes detected correctly by `getChangedFields()`

**Edge Cases**:
- User types non-numeric characters: Strip them in parse function
- User types multiple decimals: `parseFloat` handles this (takes first valid number)
- User clears price field: Should store `null`, not 0
- Negative prices: Decide if allowed (likely not for items)

---

### Subtask T013 - Add shouldAcceptSubscriptionData protection

**Purpose**: Prevent subscription updates from overwriting user edits during form interaction.

**Files**:
- Modify: `app/items/[id]/edit.tsx`

**Steps**:
1. **Find the subscription effect** (likely `useEffect` listening to `item` from query):
   ```typescript
   useEffect(() => {
     if (item) {
       // Existing code that updates state when item changes
     }
   }, [item]);
   ```

2. **Add protection gate**:
   ```typescript
   useEffect(() => {
     if (item && form.shouldAcceptSubscriptionData) {
       // Update form values from subscription
       form.setFields({
         name: item.name || '',
         description: item.description || '',
         spaceId: item.spaceId || '',
         status: item.status || 'active',
         estimatedPriceCents: item.estimatedPriceCents ?? null,
         purchasePriceCents: item.purchasePriceCents ?? null,
         salePriceCents: item.salePriceCents ?? null,
         quantity: item.quantity ?? 1,
         tags: item.tags || []
       });

       // Update display strings too
       setEstimatedPriceDisplay(
         item.estimatedPriceCents !== null
           ? formatCentsToDisplay(item.estimatedPriceCents)
           : ''
       );
       setPurchasePriceDisplay(
         item.purchasePriceCents !== null
           ? formatCentsToDisplay(item.purchasePriceCents)
           : ''
       );
       setSalePriceDisplay(
         item.salePriceCents !== null
           ? formatCentsToDisplay(item.salePriceCents)
           : ''
       );
     }
   }, [item, form.shouldAcceptSubscriptionData]);
   ```

3. **Include dependency**: Add `form.shouldAcceptSubscriptionData` to dependency array

**Validation**:
- [ ] On initial load, form accepts item data correctly
- [ ] After user types in any field, `form.shouldAcceptSubscriptionData` becomes false
- [ ] Subsequent subscription updates do NOT overwrite form values
- [ ] Display strings also protected (not overwritten during typing)

**Testing**:
- Simulate subscription update by modifying item in Firestore console while editing
- Verify typed value is preserved (not replaced by subscription data)

---

### Subtask T014 - Update save handler with getChangedFields

**Purpose**: Use change tracking to send only modified fields to `updateItem`, skip write if no changes.

**Files**:
- Modify: `app/items/[id]/edit.tsx`

**Steps**:
1. **Find the save handler** (likely `handleSave`, `handleSubmit`, or `onSave`):
   ```typescript
   const handleSave = () => {
     // Existing validation logic
     // Existing update call
   };
   ```

2. **Add change detection**:
   ```typescript
   const handleSave = () => {
     // Check for changes
     if (!form.hasChanges) {
       // No changes - skip write, just navigate
       router.back();
       return;
     }

     // Get only changed fields
     const changedFields = form.getChangedFields();

     // Preserve existing validation if needed
     if (!changedFields.name && form.values.name.trim() === '') {
       // Name is required - show error
       // (only validate if name is in changed fields or is currently empty)
       return;
     }

     // Fire-and-forget Firestore write
     updateItem(itemId, changedFields).catch((err) => {
       console.error('Failed to update item:', err);
       // TODO: Add user-facing error handling
     });

     // Navigate immediately (offline-first)
     router.back();
   };
   ```

3. **Remove any `await` on `updateItem`**: Ensure fire-and-forget pattern

4. **Remove any `isSubmitting` state**: Navigation should happen immediately, not gate on write completion

**Validation**:
- [ ] No-change save navigates without calling `updateItem`
- [ ] Single-field change sends only that field to `updateItem`
- [ ] Multi-field change sends all changed fields
- [ ] Navigation happens immediately (no spinner waiting on write)
- [ ] Existing validation preserved (e.g., required fields)

**Edge Cases**:
- User changes name then changes it back: `hasChanges` should be false
- User changes price from $10 to $10.00: Should NOT be detected as change (same cents value)
- Required field validation: Only validate fields that are changed or currently invalid

---

### Subtask T015 - Verify TypeScript compilation passes

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
     - `form.values` property access type errors (ensure `ItemFormValues` matches all field types)
     - Price field type mismatches (`number | null` vs `number`)
     - Array field types (`tags: string[]` vs `tags: string[] | undefined`)
     - Missing imports for helper functions or types
     - `parseDisplayToCents` return type mismatch with `setField` parameter

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
- [ ] Price conversion functions have correct type signatures

---

### Subtask T016 - Manual verification of item edit screen

**Purpose**: Manually test the item edit screen to verify change tracking and price handling work correctly.

**Test Script**:

**Setup**:
1. Open the app
2. Navigate to any item detail screen
3. Tap Edit button to open item edit screen

**Test Case 1: No-change save**
1. Open item edit
2. Do NOT modify any fields
3. Tap Save
4. **Verify**:
   - [ ] Navigation happens immediately
   - [ ] Console shows no `updateItem` call
   - [ ] No Firestore write in network tab

**Test Case 2: Name-only edit**
1. Open item edit
2. Change name field only (e.g., "Widget" → "Widget Pro")
3. Tap Save
4. **Verify**:
   - [ ] Console/network shows update with only `{name: "Widget Pro"}`
   - [ ] Item detail screen shows new name
   - [ ] All other fields unchanged

**Test Case 3: Description-only edit**
1. Open item edit
2. Change description field only
3. Tap Save
4. **Verify**:
   - [ ] Update contains only `{description: "..."}`
   - [ ] Name and other fields unchanged

**Test Case 4: Price field edit (estimatedPrice)**
1. Open item edit
2. Change estimated price to "$15.99"
3. Tap Save
4. **Verify**:
   - [ ] Update contains `{estimatedPriceCents: 1599}` (not display string)
   - [ ] Item detail shows "$15.99" formatted correctly
   - [ ] Other price fields unchanged

**Test Case 5: Multiple price fields**
1. Open item edit
2. Change estimated price to "$10.00"
3. Change purchase price to "$8.50"
4. Tap Save
5. **Verify**:
   - [ ] Update contains `{estimatedPriceCents: 1000, purchasePriceCents: 850}`
   - [ ] Sale price not included (unchanged)

**Test Case 6: Empty price field**
1. Open item edit with existing price
2. Clear estimated price field (delete all text)
3. Tap Save
4. **Verify**:
   - [ ] Update contains `{estimatedPriceCents: null}`
   - [ ] Item detail shows no price (empty or placeholder)

**Test Case 7: Multi-field edit**
1. Open item edit
2. Change name, description, and quantity
3. Tap Save
4. **Verify**:
   - [ ] Update contains `{name: "...", description: "...", quantity: N}`
   - [ ] Price fields and other unchanged fields not included

**Test Case 8: Subscription protection**
1. Open item edit
2. Start typing in name field
3. Simulate subscription update (modify item in another device/Firestore console)
4. **Verify**:
   - [ ] Typed value in name field is preserved (not overwritten)
   - [ ] Form continues to work normally

**Test Case 9: Space selection**
1. Open item edit
2. Change space via picker/dropdown
3. Tap Save
4. **Verify**:
   - [ ] Update contains `{spaceId: "new-space-id"}`
   - [ ] Item detail shows new space label

**Test Case 10: Tag editing**
1. Open item edit
2. Add or remove tags
3. Tap Save
4. **Verify**:
   - [ ] Update contains `{tags: ["tag1", "tag2", ...]}`
   - [ ] Item detail shows updated tags

**Test Case 11: Revert changes**
1. Open item edit
2. Change name field
3. Change it back to original value
4. Tap Save
5. **Verify**:
   - [ ] Navigation happens (no write, change was reverted)
   - [ ] Item unchanged in detail screen

**Debugging Tips**:
- Add `console.log('Changed fields:', form.getChangedFields())` before save
- Add `console.log('Price cents:', form.values.estimatedPriceCents)` to verify conversion
- Check React Native debugger network tab for Firestore payloads
- Verify cents values are integers (no floating point: 1599 not 1599.0)

**Validation Checklist**:
- [ ] All 11 test cases pass
- [ ] No TypeScript errors in console
- [ ] No runtime errors during testing
- [ ] Price conversion works correctly (display ↔ cents)
- [ ] Change tracking detects all field types (string, number, array)
- [ ] Subscription protection works reliably
- [ ] Navigation is immediate (offline-first)

---

## Test Strategy

**No automated tests required for this work package.**

Manual testing (T016) provides comprehensive verification for form behavior and price handling.

---

## Risks & Mitigations

**Risk 1: Price conversion errors (cents ↔ display string)**
- **Mitigation**: Use well-tested helper functions (`formatCentsToDisplay`, `parseDisplayToCents`). Test edge cases (empty, invalid input, large values).
- **Verification**: Test all 3 price fields independently with various inputs

**Risk 2: Form state synchronization between display strings and cents values**
- **Mitigation**: Display strings are UI-only state, cents values are source of truth in form. Always convert display → cents on change.
- **Verification**: Check `form.values` in debugger to ensure cents values are correct

**Risk 3: Subscription timing issues (overwrites during typing)**
- **Mitigation**: Use `shouldAcceptSubscriptionData` to gate all subscription updates
- **Verification**: Simulate subscription during editing, verify typed value preserved

**Risk 4: Array and object field comparison in getChangedFields**
- **Mitigation**: `useEditForm` should handle array comparison correctly (shallow). Tags array changes should be detected.
- **Verification**: Test tag addition/removal, verify changes detected

**Risk 5: Breaking existing validation logic**
- **Mitigation**: Preserve all existing validation. Only add change detection, don't modify validation rules.
- **Verification**: Test required fields, invalid inputs, edge cases

---

## Review Guidance

**Key Checkpoints for `/spec-kitty.review`**:

1. **Code Review**:
   - [ ] Item edit uses `useEditForm<ItemFormValues>` with correct generic type
   - [ ] All 9 fields included in form type and initialization
   - [ ] Price display strings are separate state (not in form)
   - [ ] Price handlers convert display string → cents → `setField`
   - [ ] `getChangedFields()` used before `updateItem` call
   - [ ] No-change check exists before update call
   - [ ] Firestore write uses fire-and-forget (no `await`)
   - [ ] Navigation happens immediately after write dispatch
   - [ ] Subscription effect checks `shouldAcceptSubscriptionData`
   - [ ] Helper functions have correct type signatures

2. **Testing Evidence**:
   - [ ] T016 manual testing checklist fully completed (all 11 test cases)
   - [ ] Screenshots or logs showing price cents values in payloads (optional)
   - [ ] Confirmation that TypeScript compilation passes

3. **Pattern Consistency**:
   - [ ] Follows same pattern as WP01 (useEditForm hook, change tracking)
   - [ ] Error handling consistent (fire-and-forget with `.catch()`)
   - [ ] No await on Firestore writes (offline-first)
   - [ ] Price handling follows established pattern (cents storage)

**Questions for Reviewer**:
- Are price conversions working correctly for all 3 price fields?
- Does the subscription protection work reliably during testing?
- Are there any edge cases with array fields (tags) not covered?
- Is the validation logic preserved correctly?

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
- 2026-02-09T21:22:48Z – claude-implementer – shell_pid=22113 – lane=doing – Assigned agent via workflow command
- 2026-02-09T23:27:00Z – claude-implementer – shell_pid=22113 – lane=for_review – Ready for review: Migrated item edit screen to useEditForm hook with price field handling and change tracking
- 2026-02-09T23:33:41Z – claude-reviewer-3 – shell_pid=59448 – lane=doing – Started review via workflow command
- 2026-02-09T23:39:03Z – claude-reviewer-3 – shell_pid=59448 – lane=planned – Moved to planned
