---
work_package_id: WP01
title: Simple Edit Screens Migration
lane: "planned"
dependencies: []
base_branch: main
base_commit: c969f7b10576fed880f5ff39d28a5fa35e7f016f
created_at: '2026-02-09T19:39:39.846887+00:00'
subtasks:
- T001
- T002
- T003
- T004
- T005
phase: Phase 2A - Edit Screen Migrations
assignee: ''
agent: "claude-orchestrator"
shell_pid: "376"
review_status: "has_feedback"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-09T08:45:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP01 - Simple Edit Screens Migration

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

## Issue 1: Project Edit - Broken Subscription Updates (CRITICAL)

**Location:** [app/project/[projectId]/edit.tsx:42](app/project/[projectId]/edit.tsx#L42)

**Problem:** The `useEditForm` hook is initialized with `null` instead of the project data:
```typescript
const form = useEditForm<ProjectBasicFields>(null);
```

This breaks the subscription update mechanism. Here's what happens:
1. Hook starts with `hasEdited = false`, so `shouldAcceptSubscriptionData = true`
2. Manual subscription effect (lines 72-80) calls `form.setFields()` on first project update
3. `setFields()` sets `hasEdited = true`, making `shouldAcceptSubscriptionData = false`
4. **Result:** No further subscription updates are accepted, even though the user hasn't actually edited anything

**Required Fix:** Pass the project data to the hook constructor (as specified in the prompt, lines 218-226):
```typescript
const form = useEditForm<ProjectBasicFields>(
  project ? {
    name: project.name || '',
    clientName: project.clientName || '',
    description: project.description || ''
  } : null
);
```

**Then remove the manual subscription effect** (lines 72-80) since the hook's internal effect will handle it correctly.

**Why this matters:** 
- Violates success criteria: "Subscription updates do not overwrite user edits"
- In this case, subscription updates stop working entirely after first load
- If another user/device updates the project, changes won't appear until reload

---

## Issue 2: Space Edit Screens - Inconsistent Whitespace Handling

**Locations:** 
- [app/business-inventory/spaces/[spaceId]/edit.tsx:46-48](app/business-inventory/spaces/[spaceId]/edit.tsx#L46-L48)
- [app/project/[projectId]/spaces/[spaceId]/edit.tsx:53-55](app/project/[projectId]/spaces/[spaceId]/edit.tsx#L53-L55)

**Problem:** The name field compares trimmed values but stores untrimmed:
```typescript
if (values.name.trim() !== space?.name) {
  updates.name = values.name;  // ❌ stores UNTRIMMED value
}
```

This means trailing/leading whitespace can be saved to Firestore, causing data inconsistency.

**Contrast with notes field** (done correctly):
```typescript
const normalizedNotes = values.notes?.trim() || null;
if (normalizedNotes !== (space?.notes ?? null)) {
  updates.notes = normalizedNotes;  // ✅ stores TRIMMED value
}
```

**Required Fix:** Apply the same pattern to the name field:
```typescript
const normalizedName = values.name.trim();
if (normalizedName !== space?.name) {
  updates.name = normalizedName;
}
```

---

## Verification Checklist After Fixes

- [ ] TypeScript compilation passes with no NEW errors (pre-existing errors are OK)
- [ ] Project edit: Open project, don't edit, wait for subscription update → form accepts the update
- [ ] Project edit: Open project, start typing in name field, wait for subscription update → typed value is NOT overwritten
- [ ] Project edit: Save with no changes → navigates immediately, no Firestore write
- [ ] Project edit: Change name only → update payload contains only `{name: "..."}`
- [ ] Space edits: Enter name with trailing spaces → saved value has spaces trimmed
- [ ] Space edits: Save with no changes → navigates immediately, no Firestore write


## Markdown Formatting
Wrap HTML/XML tags in backticks: `` `<div>` ``, `` `<script>` ``
Use language identifiers in code blocks: ````typescript`, ````bash`

---

## How to Implement This Work Package

**Run this command to begin**:
```bash
spec-kitty implement WP01
```

This creates an isolated worktree at `.worktrees/001-architecture-critique-implementation-WP01/` branched from `main`.

---

## Objectives & Success Criteria

**Goal**: Migrate the 3 simplest edit screens (project edit, 2 space edits) from multiple `useState` calls to using the `useEditForm` hook with partial write change tracking.

**Success Criteria**:
- All 3 screens use `useEditForm` hook for form state management
- Save operations include only modified fields in update payloads (verified via console logging or network inspection)
- Saves with no changes skip database writes entirely and navigate immediately
- Subscription updates do not overwrite user edits (protected by `shouldAcceptSubscriptionData`)
- TypeScript compilation passes with no new errors
- Manual testing confirms single-field edits, no-change saves, and subscription protection work correctly

**Acceptance Test**:
1. Open project edit, change name only, save → verify update payload contains only `{name: "..."}`
2. Open project edit, make no changes, save → verify no Firestore write occurs, navigation happens immediately
3. Open space edit, start typing in name field, wait for subscription update → verify typed value not overwritten
4. Repeat for both space edit screens (business inventory and project spaces)

---

## Context & Constraints

**Prerequisites**:
- Phase 1 complete: `useEditForm` hook exists at `src/hooks/useEditForm.ts` with full API
- Refer to implementation plan: `.plans/architecture-critique-implementation-plan.md` Phase 2A
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

**Key Constraints**:
- Project edit: Only migrate basic fields (name, clientName, description). Budget handling stays separate (not in scope).
- Space edits: Add change detection in screen's `handleSubmit`. Do NOT modify `SpaceForm` component.
- All screens: Use `shouldAcceptSubscriptionData` to gate subscription updates (prevent overwrites during editing)
- All screens: Skip write entirely if `hasChanges` is false
- Follow offline-first rules: Never `await` Firestore writes, use fire-and-forget with `.catch()`

**Architecture Patterns**:
- Refer to `CLAUDE.md` and `MEMORY.md` for offline-first coding rules
- All `create*` and `update*` service functions use fire-and-forget writes
- Navigation happens immediately after write dispatch

---

## Subtasks & Detailed Guidance

### Subtask T001 - Migrate project edit screen (3 basic fields)

**Purpose**: Convert project edit screen from `useState` to `useEditForm` for name, clientName, description fields.

**Files**:
- Modify: `app/project/[projectId]/edit.tsx`

**Steps**:
1. **Import the hook**:
   ```typescript
   import { useEditForm } from '@/src/hooks/useEditForm';
   ```

2. **Define form type**:
   ```typescript
   interface ProjectBasicFields {
     name: string;
     clientName: string;
     description: string;
   }
   ```

3. **Replace useState calls**:
   - Remove: `const [name, setName] = useState<string>('')`
   - Remove: `const [clientName, setClientName] = useState<string>('')`
   - Remove: `const [description, setDescription] = useState<string>('')`
   - Add:
   ```typescript
   const form = useEditForm<ProjectBasicFields>(
     project ? {
       name: project.name || '',
       clientName: project.clientName || '',
       description: project.description || ''
     } : null
   );
   ```

4. **Update input bindings**:
   - Change `value={name}` to `value={form.values.name}`
   - Change `onChangeText={setName}` to `onChangeText={(val) => form.setField('name', val)}`
   - Repeat for clientName and description

5. **Update subscription effect**:
   - Find the `useEffect` that listens to `project` changes
   - Wrap the state updates in `shouldAcceptSubscriptionData` check:
   ```typescript
   useEffect(() => {
     if (project && form.shouldAcceptSubscriptionData) {
       form.setFields({
         name: project.name || '',
         clientName: project.clientName || '',
         description: project.description || ''
       });
       // Reset the hook to re-enable subscription acceptance
       // after the initial load
     }
   }, [project, form.shouldAcceptSubscriptionData]);
   ```

6. **Update save handler**:
   ```typescript
   const handleSave = () => {
     if (!form.hasChanges) {
       // No changes - skip write, just navigate
       router.back();
       return;
     }

     const changedFields = form.getChangedFields();

     // Fire-and-forget Firestore write
     updateProject(projectId, changedFields).catch((err) => {
       console.error('Failed to update project:', err);
       // TODO: Add user-facing error handling
     });

     // Navigate immediately (offline-first)
     router.back();
   };
   ```

7. **Leave budget handling untouched**:
   - Budget fields use separate state and write logic
   - Do NOT migrate budget state to useEditForm
   - Preserve existing `userHasEditedBudgets` logic

**Validation**:
- [ ] TypeScript compiles with no errors
- [ ] Form accepts initial project data correctly
- [ ] Typing in name field updates `form.values.name`
- [ ] Save with no changes navigates without calling `updateProject`
- [ ] Save with name change only sends `{name: "new value"}` to `updateProject`
- [ ] Subscription update after user edit does not overwrite typed value

**Edge Cases**:
- Project is null during load: Form shows empty fields, `form.values` handles null gracefully
- User reverts name to original value: `hasChanges` becomes false, save skips write
- Rapid typing during subscription update: `shouldAcceptSubscriptionData` is false, typed value preserved

---

### Subtask T002 - Migrate business inventory space edit (2 fields)

**Purpose**: Add change detection to business inventory space edit screen (name, notes).

**Files**:
- Modify: `app/business-inventory/spaces/[spaceId]/edit.tsx`

**Steps**:
1. **Add inline change detection in `handleSubmit`**:
   - This screen already uses `SpaceForm` component - do NOT modify the component
   - In the edit screen's `handleSubmit`, compare form values against initial space:
   ```typescript
   const handleSubmit = (values: { name: string; notes: string }) => {
     // Get initial space from query/state
     const initialValues = {
       name: space.name || '',
       notes: space.notes || ''
     };

     // Detect changes
     const changedFields: Partial<typeof values> = {};
     if (values.name !== initialValues.name) {
       changedFields.name = values.name;
     }
     if (values.notes !== initialValues.notes) {
       changedFields.notes = values.notes;
     }

     // Skip write if no changes
     if (Object.keys(changedFields).length === 0) {
       router.back();
       return;
     }

     // Fire-and-forget Firestore write
     updateSpace(spaceId, changedFields).catch((err) => {
       console.error('Failed to update space:', err);
     });

     // Navigate immediately
     router.back();
   };
   ```

2. **No hook needed**: This is inline comparison, not `useEditForm` (simpler for 2-field modal)

3. **Preserve SpaceForm component**: Do NOT modify `SpaceForm` - changes are screen-level only

**Validation**:
- [ ] Save with no changes navigates without calling `updateSpace`
- [ ] Save with name change only sends `{name: "new value"}`
- [ ] Save with notes change only sends `{notes: "new value"}`
- [ ] Save with both changes sends `{name: "...", notes: "..."}`

**Edge Cases**:
- Empty fields: If name is required, validation should catch before reaching this logic
- Whitespace-only changes: Consider trimming before comparison if needed

**Parallel**: Can proceed in parallel with T003 (different file)

---

### Subtask T003 - Migrate project space edit (2 fields)

**Purpose**: Add change detection to project space edit screen (name, notes).

**Files**:
- Modify: `app/project/[projectId]/spaces/[spaceId]/edit.tsx`

**Steps**:
1. **Follow exact same pattern as T002**:
   - Add inline change detection in `handleSubmit`
   - Compare against initial space values
   - Build `changedFields` object with only modified fields
   - Skip write if no changes
   - Fire-and-forget Firestore write with immediate navigation

2. **Implementation**:
   ```typescript
   const handleSubmit = (values: { name: string; notes: string }) => {
     const initialValues = {
       name: space.name || '',
       notes: space.notes || ''
     };

     const changedFields: Partial<typeof values> = {};
     if (values.name !== initialValues.name) {
       changedFields.name = values.name;
     }
     if (values.notes !== initialValues.notes) {
       changedFields.notes = values.notes;
     }

     if (Object.keys(changedFields).length === 0) {
       router.back();
       return;
     }

     updateSpace(spaceId, changedFields).catch((err) => {
       console.error('Failed to update space:', err);
     });

     router.back();
   };
   ```

3. **No changes to SpaceForm component**

**Validation**:
- [ ] Same validation checklist as T002
- [ ] Verify both space edit screens behave identically

**Parallel**: Can proceed in parallel with T002 (different file)

---

### Subtask T004 - Verify TypeScript compilation passes

**Purpose**: Ensure no new TypeScript errors were introduced by the changes.

**Steps**:
1. Run TypeScript compiler:
   ```bash
   npx tsc --noEmit
   ```

2. **Expected output**: All errors should be pre-existing (documented in MEMORY.md)

3. **If new errors appear**:
   - Review the error messages
   - Fix type mismatches (likely form value types or function signatures)
   - Common issues:
     - `form.values` property access on possibly undefined types
     - Missing imports for `useEditForm`
     - Incorrect generic type parameters

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

---

### Subtask T005 - Manual verification of all 3 screens

**Purpose**: Manually test each migrated screen to verify change tracking works correctly.

**Test Script**:

**For Project Edit (`app/project/[projectId]/edit.tsx`)**:
1. Open any project, tap Edit
2. **Test 1: No-change save**
   - Do not modify any fields
   - Tap Save
   - **Verify**: Navigation happens immediately, console shows no `updateProject` call
3. **Test 2: Single-field edit**
   - Change name field only (e.g., "Test Project" → "Test Project Updated")
   - Tap Save
   - **Verify**: Console/network shows update with only `{name: "Test Project Updated"}`, no other fields
4. **Test 3: Subscription protection**
   - Start typing in clientName field
   - Wait for subscription update (if live)
   - **Verify**: Typed value is NOT overwritten by subscription data
5. **Test 4: Multi-field edit**
   - Change name and description
   - Tap Save
   - **Verify**: Update contains only `{name: "...", description: "..."}`

**For Business Inventory Space Edit (`app/business-inventory/spaces/[spaceId]/edit.tsx`)**:
1. Navigate to Business Inventory → Spaces → tap any space
2. **Test 1: No-change save**
   - Do not modify name or notes
   - Tap Save
   - **Verify**: Navigation without `updateSpace` call
3. **Test 2: Name-only edit**
   - Change name field only
   - Tap Save
   - **Verify**: Update contains only `{name: "..."}`
4. **Test 3: Notes-only edit**
   - Change notes field only
   - Tap Save
   - **Verify**: Update contains only `{notes: "..."}`

**For Project Space Edit (`app/project/[projectId]/spaces/[spaceId]/edit.tsx`)**:
1. Open any project → Spaces → tap any space
2. Repeat same test script as business inventory space edit

**Validation Checklist**:
- [ ] Project edit: No-change save works (no write)
- [ ] Project edit: Single-field edit sends only changed field
- [ ] Project edit: Subscription protection works (typed value preserved)
- [ ] Business inventory space edit: No-change save works
- [ ] Business inventory space edit: Field-specific changes work
- [ ] Project space edit: No-change save works
- [ ] Project space edit: Field-specific changes work
- [ ] All 3 screens navigate immediately after save (offline-first)
- [ ] No TypeScript errors in console
- [ ] No runtime errors during testing

**Debugging Tips**:
- Add `console.log('Changed fields:', changedFields)` before update calls to verify payload
- Check React Native debugger network tab for Firestore write payloads
- If subscription overwrites occur, verify `shouldAcceptSubscriptionData` is being checked correctly

---

## Test Strategy

**No automated tests required for this work package.**

Manual testing (T005) provides sufficient verification for form behavior changes.

---

## Risks & Mitigations

**Risk 1: Breaking existing project edit behavior (especially budgets)**
- **Mitigation**: Only migrate basic fields (name, clientName, description). Leave all budget state and logic untouched.
- **Verification**: Test budget editing independently to ensure it still works

**Risk 2: SpaceForm component changes break other usages**
- **Mitigation**: Do NOT modify SpaceForm component. All changes are in edit screen handlers only.
- **Verification**: Check for other usages of SpaceForm in the codebase (grep for "SpaceForm")

**Risk 3: Subscription timing issues (overwrites during typing)**
- **Mitigation**: Use `shouldAcceptSubscriptionData` to gate all subscription updates
- **Verification**: Manual test with intentional delays to trigger subscription during editing

**Risk 4: Form state persistence across navigation**
- **Mitigation**: React Navigation should unmount components on back navigation, resetting state
- **Verification**: Navigate to edit → back → edit again, verify clean slate

---

## Review Guidance

**Key Checkpoints for `/spec-kitty.review`**:

1. **Code Review**:
   - [ ] Project edit uses `useEditForm` with correct generic type
   - [ ] All 3 screens use `getChangedFields()` or inline comparison before updates
   - [ ] No-change check exists before all `update*` calls
   - [ ] All Firestore writes use fire-and-forget (no `await`)
   - [ ] Navigation happens immediately after write dispatch
   - [ ] Subscription effects check `shouldAcceptSubscriptionData`
   - [ ] Budget handling in project edit is UNCHANGED

2. **Testing Evidence**:
   - [ ] T005 manual testing checklist is fully completed
   - [ ] Screenshots or logs showing changed field payloads (optional but helpful)
   - [ ] Confirmation that TypeScript compilation passes

3. **Pattern Consistency**:
   - [ ] All 3 screens follow same pattern (useEditForm or inline comparison)
   - [ ] Error handling is consistent (fire-and-forget with `.catch()`)
   - [ ] No new anti-patterns introduced (e.g., awaiting writes, blocking navigation)

**Questions for Reviewer**:
- Are the changed field payloads correctly excluding unchanged fields?
- Does the subscription protection work reliably during testing?
- Are there any edge cases not covered by the manual test script?

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
- 2026-02-09T19:39:50Z – claude-sonnet – shell_pid=15640 – lane=doing – Assigned agent via workflow command
- 2026-02-09T20:57:57Z – claude-sonnet – shell_pid=15640 – lane=for_review – Ready for review: Migrated 3 simple edit screens with change tracking. All screens skip writes when unchanged. Subscription protection added to project edit screen.
- 2026-02-09T21:02:50Z – claude-orchestrator – shell_pid=376 – lane=doing – Started review via workflow command
- 2026-02-09T21:12:20Z – claude-orchestrator – shell_pid=376 – lane=planned – Moved to planned
