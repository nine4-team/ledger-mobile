---
work_package_id: WP04
title: Cleanup & Dead Code Removal
lane: planned
dependencies:
- WP02
- WP03
subtasks:
- T014
- T015
- T016
phase: Phase 3 - Polish
assignee: ''
agent: ''
shell_pid: ''
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-11T05:38:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP04 – Cleanup & Dead Code Removal

## Review Feedback

> **Populated by `/spec-kitty.review`** – Reviewers add detailed feedback here when work needs changes.

*[This section is empty initially.]*

---

## Objectives & Success Criteria

- Delete `SharedItemPicker.tsx` (fully absorbed into SharedItemsList picker mode)
- Remove barrel exports for `SharedItemPicker` from `src/components/index.ts`
- Ensure `ItemEligibilityCheck` type is properly exported from `src/hooks/usePickerMode.ts`
- Verify no stale imports remain anywhere in the codebase
- **Success**: Clean TypeScript build. No references to `SharedItemPicker` in any file. `ItemPickerControlBar` still exported and used by SharedItemsList.

## Context & Constraints

- **Spec**: `kitty-specs/006-item-list-picker-normalization/spec.md` — "Files to Delete After Migration"
- **Plan**: `kitty-specs/006-item-list-picker-normalization/plan.md` — Stage 4 (WP04)
- **Dependency**: WP02 AND WP03 must both be complete (all consumers migrated)
- This is the final cleanup step — no functional changes, only dead code removal

### Files to Modify/Delete

| File | Action |
|------|--------|
| `src/components/SharedItemPicker.tsx` | **DELETE** |
| `src/components/index.ts` | **MODIFY** — remove line 35 |
| `src/hooks/usePickerMode.ts` | **VERIFY** — ItemEligibilityCheck exported |

### Implementation Command

```bash
spec-kitty implement WP04 --base WP03
```

(Use WP03 as base since it's the last consumer migration. If WP02 and WP03 were done in parallel, merge both first.)

---

## Subtasks & Detailed Guidance

### Subtask T014 – Delete SharedItemPicker.tsx

**Purpose**: Remove the now-unused component file.

**Steps**:
1. Delete the file:
   ```bash
   rm src/components/SharedItemPicker.tsx
   ```

2. Verify the file contained only the `SharedItemPicker` component and its local types (`ItemEligibilityCheck`, `SharedItemPickerProps`). If it exported any types still used elsewhere, those must have been migrated in WP01 (T001).

**Files**: `src/components/SharedItemPicker.tsx` (DELETE)

**Notes**:
- `ItemEligibilityCheck` type was defined in this file (lines 22-35). It should already be re-exported from `src/hooks/usePickerMode.ts` (created in WP01/T001).
- `SharedItemPickerProps` type is only used internally by SharedItemPicker — no migration needed.

---

### Subtask T015 – Update Barrel Exports in index.ts

**Purpose**: Remove the dead export for `SharedItemPicker` while keeping `ItemPickerControlBar`.

**Steps**:
1. Open `src/components/index.ts`
2. Remove line 35:
   ```typescript
   // REMOVE THIS LINE:
   export { SharedItemPicker } from './SharedItemPicker';
   ```
3. **KEEP** line 36:
   ```typescript
   // KEEP THIS LINE — ItemPickerControlBar is now consumed by SharedItemsList:
   export { ItemPickerControlBar } from './ItemPickerControlBar';
   ```

4. Check if there was a type export for `ItemEligibilityCheck` from the barrel. If so, either:
   - Remove it (consumers import directly from `usePickerMode`)
   - Or re-export it from the barrel: `export type { ItemEligibilityCheck } from '../hooks/usePickerMode';`

   The simpler approach is to have consumers import from `usePickerMode` directly.

**Files**: `src/components/index.ts`

**Notes**:
- Only remove `SharedItemPicker` export. Do NOT remove `ItemPickerControlBar` — it's still actively used.

---

### Subtask T016 – Verify No Stale Imports + Type Re-exports

**Purpose**: Ensure the codebase is clean with no references to the deleted component.

**Steps**:
1. Run a codebase-wide search for `SharedItemPicker`:
   ```bash
   grep -r "SharedItemPicker" --include="*.ts" --include="*.tsx" src/ app/
   ```
   **Expected result**: Zero matches. If any matches found, update those imports.

2. Run a codebase-wide search for any imports from the deleted file path:
   ```bash
   grep -r "from.*SharedItemPicker" --include="*.ts" --include="*.tsx" src/ app/
   ```

3. Verify `ItemEligibilityCheck` is properly exported from `src/hooks/usePickerMode.ts`:
   ```bash
   grep "export.*ItemEligibilityCheck" src/hooks/usePickerMode.ts
   ```
   Should find the export. If not, add it.

4. Check that consumers importing `ItemEligibilityCheck` use the correct path:
   ```bash
   grep -r "ItemEligibilityCheck" --include="*.ts" --include="*.tsx" src/ app/
   ```
   All imports should reference `usePickerMode`, not `SharedItemPicker`.

5. Run TypeScript type check to verify clean build:
   ```bash
   npx tsc --noEmit
   ```
   **Note**: There are pre-existing TSC errors unrelated to this feature (see MEMORY.md). Focus only on errors mentioning `SharedItemPicker`, `ItemEligibilityCheck`, or `usePickerMode`.

**Files**: Multiple (verification only, no changes unless stale imports found)

**Notes**:
- Pre-existing TSC errors are documented in MEMORY.md:
  - `__tests__/` files: missing `@types/jest`
  - `SharedItemsList.tsx`, `SharedTransactionsList.tsx`: icon type mismatches
  - `resolveItemMove.ts`: variable shadowing
  - `settings.tsx`: `BudgetCategoryType` union mismatch
  - `accountContextStore.ts`: null handling
- Ignore these. Only flag NEW errors introduced by this feature.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Stale import missed | Low | Low | Codebase-wide grep catches all references |
| Type export missing | Low | Medium | Verify ItemEligibilityCheck export in T016 step 3 |
| Accidental deletion of ItemPickerControlBar | Low | High | Explicit instruction to KEEP it |

## Review Guidance

- **Critical check**: `SharedItemPicker.tsx` is deleted
- **Export check**: Line 35 removed from index.ts, line 36 kept
- **Import check**: Zero references to `SharedItemPicker` in codebase
- **Type check**: `ItemEligibilityCheck` accessible from `usePickerMode`
- **Build check**: No new TypeScript errors (ignore pre-existing ones)

## Activity Log

- 2026-02-11T05:38:00Z – system – lane=planned – Prompt created.
