---
work_package_id: WP01
title: usePickerMode Hook + SharedItemsList Integration
lane: "done"
dependencies: []
base_branch: main
base_commit: 7cf6e72530bb76c8fce906b1fae60f897a40c0dc
created_at: '2026-02-11T06:00:16.141388+00:00'
subtasks:
- T001
- T002
- T003
- T004
- T005
- T006
phase: Phase 1 - Foundation
assignee: ''
agent: "claude-sonnet"
shell_pid: "15303"
review_status: "has_feedback"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-11T05:38:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP01 – usePickerMode Hook + SharedItemsList Integration

## Review Feedback

**Reviewed by**: nine4-team
**Status**: ❌ Changes Requested
**Date**: 2026-02-11

## Review Feedback for WP01

**Reviewed by**: claude-sonnet
**Status**: ❌ Changes Requested
**Date**: 2026-02-11

### ✅ Previous Issues Fixed

The two issues from the previous review have been correctly addressed:
1. ✅ `eligibleIds` now correctly filters out items in `addedIds` (lines 130-138)
2. ✅ `handleSelectAll` logic has been simplified per spec (lines 147-156)

### ❌ New Issues Found

### Issue 1: `getPickerItemProps` doesn't check `addedIds` for card interaction

**Location**: `src/hooks/usePickerMode.tsx`, lines 159-187

**Problem**: Items that are already added (`addedIds.has(item.id)`) should NOT be interactable (no `onPress`, no `onSelectedChange`). Currently, the function only checks `locked` (which is `!isEligible`), not whether the item is already added.

**Current code** (lines 163-176):
```typescript
const locked = !actualEligibilityCheck.isEligible(item);
// ...
onSelectedChange: locked
  ? undefined
  : (next) => {
      setItemSelected(item.id, next);
    },
onPress: locked
  ? undefined
  : () => {
      setItemSelected(item.id, !isSelected);
    },
```

**Expected behavior** (from spec lines 332-336):
```typescript
const eligible = !eligibilityCheck || eligibilityCheck.isEligible(item);
const alreadyAdded = addedIds?.has(item.id) ?? false;
const canInteract = eligible && !alreadyAdded;

return {
  onPress: canInteract ? () => setItemSelected(item.id, !isSelected) : undefined,
  onSelectedChange: canInteract ? (next: boolean) => setItemSelected(item.id, next) : undefined,
  // ... rest
};
```

**Fix required**:
1. Add `const alreadyAdded = addedIds?.has(item.id) ?? false;` after line 163
2. Change `locked` checks to `canInteract = eligible && !alreadyAdded` for `onPress` and `onSelectedChange`
3. Keep using `locked` (not `alreadyAdded`) for the opacity style - only ineligible items should be dimmed
4. Pass `!eligible || alreadyAdded` to `renderAddButton` (not just `locked`)
5. Add `addedIds` to the dependency array (line 186)

**Impact**: Without this fix, users can select/deselect items that are already added (showing "Added" badge), which is confusing and violates the spec.

---

### Issue 2: `getPickerGroupProps` doesn't filter out `addedIds`

**Location**: `src/hooks/usePickerMode.tsx`, lines 190-218

**Problem**: When computing eligible group IDs for group selection, the function should exclude items that are in `addedIds`. Currently it only filters by eligibility.

**Current code** (lines 200-202):
```typescript
const groupEligibleIds = groupItems
  .filter((item) => actualEligibilityCheck.isEligible(item))
  .map((item) => item.id);
```

**Expected behavior** (from spec lines 357-361):
```typescript
const eligibleGroupIds = groupIds.filter(id => {
  const item = groupItems.find(i => /* id match */);
  return item && (!eligibilityCheck || eligibilityCheck.isEligible(item))
    && !addedIds?.has(id);
});
```

**Fix required**:
1. Add check for `!addedIds?.has(item.id)` in the filter condition (line 201)
2. Add `addedIds` to the dependency array (line 217)

**Impact**: Without this fix, group "select all" will include already-added items, causing them to be selected when they should be locked out.

---

### Positive Findings

✅ Previous review issues correctly fixed
✅ All type definitions are correct and well-documented
✅ Hook integration in SharedItemsList is correct
✅ Both embedded and standalone rendering paths updated correctly
✅ ItemPickerControlBar renders correctly in picker mode
✅ Loading/error states implemented correctly
✅ All memoization patterns correct (except for missing `addedIds` dependencies noted above)
✅ No TypeScript errors

---

### Action Required

Please fix the two issues above related to `addedIds` handling and re-submit for review.


## Review Feedback for WP01

### Issue 1: `eligibleIds` computation doesn't filter out `addedIds`

**Location**: `src/hooks/usePickerMode.tsx`, lines 130-133

**Problem**: The current implementation only filters by `isEligible` but doesn't exclude items that are already in `addedIds`. Per the spec (T002, step 1), eligible IDs should exclude both ineligible items AND already-added items.

**Current code**:
```typescript
const eligibleIds = useMemo(() => {
  if (!enabled) return [];
  return items.filter((item) => actualEligibilityCheck.isEligible(item)).map((item) => item.id);
}, [enabled, items, actualEligibilityCheck]);
```

**Expected code** (from spec lines 195-206):
```typescript
const eligibleIds = useMemo(() => {
  if (!enabled) return [];
  return items
    .filter(item => {
      if (!actualEligibilityCheck.isEligible(item)) return false;
      return !addedIds?.has(item.id);
    })
    .map(item => item.id);
}, [enabled, items, actualEligibilityCheck, addedIds]);
```

**Impact**: Without this fix, "select all" will include already-added items, and the eligible count will be incorrect.

---

### Issue 2: `handleSelectAll` deselect logic is unnecessarily complex

**Location**: `src/hooks/usePickerMode.tsx`, lines 142-158

**Problem**: The deselect branch has unnecessary complexity. It filters remaining items and sets them to `true` (which they already are), and the select branch has an unnecessary check for already-selected items.

**Current code**:
```typescript
const handleSelectAll = useCallback(() => {
  if (!enabled) return;
  if (allEligibleSelected) {
    const eligibleSet = new Set(eligibleIds);
    const remaining = selectedIds.filter((id) => !eligibleSet.has(id));
    remaining.forEach((id) => setItemSelected(id, true));  // Pointless
    eligibleIds.forEach((id) => setItemSelected(id, false));
  } else {
    eligibleIds.forEach((id) => {
      if (!selectedIds.includes(id)) {  // Unnecessary check
        setItemSelected(id, true);
      }
    });
  }
}, [enabled, allEligibleSelected, eligibleIds, selectedIds, setItemSelected]);
```

**Expected code** (from spec lines 217-228):
```typescript
const handleSelectAll = useCallback(() => {
  if (!enabled) return;
  if (allEligibleSelected) {
    // Deselect all eligible
    eligibleIds.forEach(id => setItemSelected(id, false));
  } else {
    // Select all eligible (additive, don't clear other selections)
    eligibleIds.forEach(id => setItemSelected(id, true));
  }
}, [enabled, allEligibleSelected, eligibleIds, setItemSelected]);
```

**Impact**: Minor - the current code works but is harder to understand and unnecessarily complex. The `setItemSelected` handler should be idempotent anyway.

---

### Positive Findings

✅ All type definitions are correct and complete (T001)
✅ Props added to SharedItemsList correctly with all fields optional (T003)
✅ Hook integration in SharedItemsList is correct (T004)
✅ ItemPickerControlBar renders correctly in picker mode (T004)
✅ Both embedded (View+map) and standalone (FlatList) rendering paths updated (T005)
✅ Loading/error states implemented correctly (T006)
✅ No TypeScript errors introduced
✅ All memoization is correct (except for missing `addedIds` dependency)
✅ No expected regressions to existing modes

---

### Action Required

Please fix the two issues above and re-submit for review. Once fixed, the implementation will be complete and ready to merge.


## Objectives & Success Criteria

- Create `src/hooks/usePickerMode.ts` with complete hook implementation
- Add picker-mode props to `SharedItemsListProps` (all optional, no effect when absent)
- Integrate the hook into SharedItemsList so that `picker={true}` activates picker rendering
- Render `ItemPickerControlBar` when in picker mode (even in embedded mode)
- Modify both embedded (View + map) and standalone (FlatList) rendering paths to use hook output
- **Success**: SharedItemsList renders identically in all existing modes. Picker props exist but are unused by any consumer yet. Zero regressions.

## Context & Constraints

- **Spec**: `kitty-specs/006-item-list-picker-normalization/spec.md` — FRs 1-5, 7-8
- **Plan**: `kitty-specs/006-item-list-picker-normalization/plan.md` — Hook API, integration pattern
- **Research**: `kitty-specs/006-item-list-picker-normalization/research.md` — Decision D1 (hook extraction), component analysis
- **Offline-first**: No awaited Firestore writes. All interactions must be instant.
- **Performance**: 60fps scrolling. All hook derivations must be memoized.
- SharedItemsList is 1,342 lines with dual-mode architecture (standalone FlatList vs. embedded View+map). Both paths must be updated.

### Key Files to Read Before Starting

1. `src/components/SharedItemsList.tsx` — Target component (1,342 lines)
2. `src/components/SharedItemPicker.tsx` — Source of picker logic to extract (500 lines)
3. `src/hooks/useItemsManager.ts` — Selection state management (294 lines)
4. `src/components/ItemPickerControlBar.tsx` — Reused control bar (150 lines)
5. `src/components/ItemCard.tsx` — Item card props (check `headerAction` prop)
6. `src/components/GroupedItemCard.tsx` — Group card (confirm `{...item}` spread)

### Implementation Command

```bash
spec-kitty implement WP01
```

---

## Subtasks & Detailed Guidance

### Subtask T001 – Create `usePickerMode.ts` Type Definitions

**Purpose**: Define the hook's input/output types and the `ItemEligibilityCheck` type (migrated from SharedItemPicker).

**Steps**:
1. Create new file `src/hooks/usePickerMode.ts`
2. Copy the `ItemEligibilityCheck` type from `src/components/SharedItemPicker.tsx` (lines 22-35):
   ```typescript
   export type ItemEligibilityCheck = {
     /** Returns false for items that cannot be selected */
     isEligible: (item: ScopedItem | Item) => boolean;
     /** Returns a status label for ineligible items */
     getStatusLabel?: (item: ScopedItem | Item) => string | undefined;
     /** Returns true if item was already added to the target */
     isAlreadyInTarget?: (item: ScopedItem | Item) => boolean;
   };
   ```
3. Define `UsePickerModeConfig` input type:
   ```typescript
   type UsePickerModeConfig = {
     enabled: boolean;
     items: Array<ScopedItem | Item>;
     eligibilityCheck?: ItemEligibilityCheck;
     onAddSingle?: (item: ScopedItem | Item) => void | Promise<void>;
     addedIds?: Set<string>;
     selectedIds: string[];
     setItemSelected: (id: string, next: boolean) => void;
     setGroupSelection: (ids: string[], next: boolean) => void;
   };
   ```
4. Define `UsePickerModeReturn` output type per plan.md (see "Hook API" section)

**Files**: `src/hooks/usePickerMode.ts` (new, ~40 lines for types)

**Notes**:
- Import `ScopedItem` and `Item` types from wherever SharedItemPicker imports them (check its imports)
- Import `ItemCardProps` type from `ItemCard` (needed for `getPickerItemProps` return type)
- Export `ItemEligibilityCheck` so consumers can import it

---

### Subtask T002 – Implement usePickerMode Hook Logic

**Purpose**: Implement the full hook with all derived state and handler factories.

**Steps**:
1. Implement `eligibleIds` computation (memoized with `useMemo`):
   ```typescript
   const eligibleIds = useMemo(() => {
     if (!enabled) return [];
     return items
       .filter(item => {
         const id = 'id' in item ? item.id : (item as any).id;
         if (!eligibilityCheck || eligibilityCheck.isEligible(item)) {
           return !addedIds?.has(id);
         }
         return false;
       })
       .map(item => 'id' in item ? item.id : (item as any).id);
   }, [enabled, items, eligibilityCheck, addedIds]);
   ```

2. Implement `allEligibleSelected`:
   ```typescript
   const allEligibleSelected = useMemo(() => {
     if (!enabled || eligibleIds.length === 0) return false;
     return eligibleIds.every(id => selectedIds.includes(id));
   }, [enabled, eligibleIds, selectedIds]);
   ```

3. Implement `handleSelectAll` (eligibility-aware, per spec FR-8):
   ```typescript
   const handleSelectAll = useCallback(() => {
     if (!enabled) return;
     if (allEligibleSelected) {
       // Deselect all eligible
       eligibleIds.forEach(id => setItemSelected(id, false));
     } else {
       // Select all eligible (additive, don't clear other selections)
       eligibleIds.forEach(id => setItemSelected(id, true));
     }
   }, [enabled, allEligibleSelected, eligibleIds, setItemSelected]);
   ```

4. Implement `getPickerItemProps` factory (per spec FR-2, FR-4):
   ```typescript
   const getPickerItemProps = useCallback((
     item: ScopedItem | Item,
     isSelected: boolean
   ): Partial<ItemCardProps> => {
     if (!enabled) return {};
     const id = /* extract item id */;
     const eligible = !eligibilityCheck || eligibilityCheck.isEligible(item);
     const alreadyAdded = addedIds?.has(id) ?? false;
     const canInteract = eligible && !alreadyAdded;

     return {
       onPress: canInteract ? () => setItemSelected(id, !isSelected) : undefined,
       onSelectedChange: canInteract ? (next: boolean) => setItemSelected(id, next) : undefined,
       headerAction: renderAddButton(item, !eligible || alreadyAdded),
       style: !eligible ? { opacity: 0.5 } : undefined,
       // Suppress non-picker actions:
       onBookmarkPress: undefined,
       onStatusPress: undefined,
       menuItems: undefined,
     };
   }, [enabled, eligibilityCheck, addedIds, setItemSelected, renderAddButton]);
   ```

5. Implement `getPickerGroupProps` factory (per spec FR-4, edge cases):
   ```typescript
   const getPickerGroupProps = useCallback((
     groupItems: Array<ScopedItem | Item>,
     groupIds: string[]
   ) => {
     if (!enabled) return { onPress: undefined, onSelectedChange: undefined, selected: false };

     const eligibleGroupIds = groupIds.filter(id => {
       const item = groupItems.find(i => /* id match */);
       return item && (!eligibilityCheck || eligibilityCheck.isEligible(item))
         && !addedIds?.has(id);
     });

     const allSelected = eligibleGroupIds.length > 0
       && eligibleGroupIds.every(id => selectedIds.includes(id));

     return {
       onPress: eligibleGroupIds.length > 0
         ? () => setGroupSelection(eligibleGroupIds, !allSelected)
         : undefined,
       onSelectedChange: eligibleGroupIds.length > 0
         ? (next: boolean) => setGroupSelection(eligibleGroupIds, next)
         : undefined,
       selected: allSelected,
     };
   }, [enabled, eligibilityCheck, addedIds, selectedIds, setGroupSelection]);
   ```

6. Implement `renderAddButton` (extracted from SharedItemPicker lines 207-250):
   - If `alreadyAdded`: render "Added" badge (green chip/text)
   - If `onAddSingle && eligible`: render Add button (Pressable with "+" icon)
   - Otherwise: `undefined`
   - Use same styling as SharedItemPicker's existing implementation
   - Make sure to import theme hooks (`useTheme`, `useUIKitTheme`)

7. **Early return when disabled**: At the top of the hook, if `!enabled`, return all no-ops:
   ```typescript
   if (!enabled) {
     return {
       eligibleIds: [],
       allEligibleSelected: false,
       handleSelectAll: () => {},
       getPickerItemProps: () => ({}),
       getPickerGroupProps: () => ({ onPress: undefined, onSelectedChange: undefined, selected: false }),
       renderAddButton: () => undefined,
     };
   }
   ```
   **Important**: This must come AFTER all `useMemo`/`useCallback` calls to satisfy React's rules of hooks (no conditional hooks). Use the `enabled` flag inside each hook instead.

**Files**: `src/hooks/usePickerMode.ts` (~150 lines total)

**Notes**:
- Study SharedItemPicker's `renderAddButton` (lines 207-250) closely for styling
- Study SharedItemPicker's `handleGroupToggle` (lines 198-205) for group eligibility filtering pattern
- All callbacks must be memoized with `useCallback` for render performance
- Item ID extraction: check how SharedItemPicker accesses `item.id` vs `(item as ScopedItem).id`

---

### Subtask T003 – Add Picker Mode Props to SharedItemsListProps

**Purpose**: Extend `SharedItemsListProps` with optional picker props. No behavior change when props are absent.

**Steps**:
1. In `src/components/SharedItemsList.tsx`, add to the `SharedItemsListProps` type (around line 34-96):
   ```typescript
   // Import the type:
   import { ItemEligibilityCheck } from '../hooks/usePickerMode';

   type SharedItemsListProps = {
     // ... existing props ...

     /** Enables picker mode: body tap toggles selection, no bookmark/status/menu */
     picker?: boolean;

     /** Eligibility check for picker mode */
     eligibilityCheck?: ItemEligibilityCheck;

     /** Callback for per-item quick-add */
     onAddSingle?: (item: ScopedItem | Item) => void | Promise<void>;

     /** Set of IDs already added (shows "Added" badge) */
     addedIds?: Set<string>;

     /** Callback for "Add Selected" button in picker control bar */
     onAddSelected?: () => void | Promise<void>;

     /** Label prefix for add button (default: "Add") */
     addButtonLabel?: string;

     /** Loading state for items (shown in picker mode) */
     outsideLoading?: boolean;

     /** Error message (shown in picker mode) */
     outsideError?: string | null;

     /** Placeholder for picker search */
     searchPlaceholder?: string;
   };
   ```

2. Destructure the new props in the component function (around line 151-187):
   ```typescript
   const {
     // ... existing destructured props ...
     picker,
     eligibilityCheck,
     onAddSingle,
     addedIds,
     onAddSelected,
     addButtonLabel,
     outsideLoading,
     outsideError,
     searchPlaceholder,
   } = props;
   ```

**Files**: `src/components/SharedItemsList.tsx`

**Notes**:
- All new props are optional — no existing call sites break
- No default values needed (undefined = not picker mode)

---

### Subtask T004 – Integrate Hook + Conditional ItemPickerControlBar

**Purpose**: Call `usePickerMode` in SharedItemsList and render `ItemPickerControlBar` when `picker={true}`.

**Steps**:
1. Import the hook and control bar:
   ```typescript
   import { usePickerMode } from '../hooks/usePickerMode';
   import { ItemPickerControlBar } from './ItemPickerControlBar';
   ```

2. Call the hook in the component body (after selection state is resolved, around line 234):
   ```typescript
   const pickerMode = usePickerMode({
     enabled: picker ?? false,
     items,
     eligibilityCheck,
     onAddSingle,
     addedIds,
     selectedIds: Array.isArray(selectedIds) ? selectedIds : Array.from(selectedIds),
     setItemSelected,
     setGroupSelection,
   });
   ```
   **Note**: `selectedIds` may be a Set (from useItemsManager) or array (internal state). Convert to array for the hook. Check which form `selectedIds` is in at line 234.

3. Add conditional control bar rendering. Find where `ItemsListControlBar` is rendered (likely in the embedded check block). Add:
   ```typescript
   {picker ? (
     <ItemPickerControlBar
       search={query}
       onChangeSearch={setQuery}
       searchPlaceholder={searchPlaceholder}
       onSelectAll={pickerMode.handleSelectAll}
       allSelected={pickerMode.allEligibleSelected}
       hasItems={pickerMode.eligibleIds.length > 0}
       onAddSelected={onAddSelected!}
       selectedCount={selectedIds.length}
       addButtonLabel={addButtonLabel}
     />
   ) : !embedded ? (
     <ItemsListControlBar ... /> /* existing */
   ) : null}
   ```
   **Important**: Picker control bar renders even when `embedded={true}` — this is different from non-picker embedded mode which hides controls entirely. The `picker` check must come before the `embedded` check.

4. Wire `query` and `setQuery`: SharedItemsList already has search state (check line ~188-230 for useState calls). Reuse the existing search query state.

**Files**: `src/components/SharedItemsList.tsx`

**Notes**:
- Check how `selectedIds` is typed in the component — it might be `string[]` (internal) or `Set<string>` (from manager). The hook expects `string[]`.
- The `selectedIds.length` for the control bar count must also handle Set vs. Array. Use `Array.isArray(selectedIds) ? selectedIds.length : selectedIds.size`.

---

### Subtask T005 – Modify Item/Group Card Rendering for Picker Mode

**Purpose**: When `picker={true}`, use hook output to override item and group card props in both rendering paths.

**Steps**:

#### 5a: Embedded Mode (View + map, ~lines 985-1110)

1. **Single item rendering** (~lines 1077-1099):
   Find where `ItemCard` props are assembled for non-grouped items. Add picker override:
   ```typescript
   // Before existing props:
   const pickerProps = picker
     ? pickerMode.getPickerItemProps(item, isSelected)
     : {};

   // In JSX:
   <ItemCard
     {...baseProps}
     onPress={picker ? pickerProps.onPress : () => handleOpenItem(id)}
     onSelectedChange={picker ? pickerProps.onSelectedChange : existingOnSelectedChange}
     onBookmarkPress={picker ? undefined : existingOnBookmarkPress}
     onStatusPress={picker ? undefined : existingOnStatusPress}
     menuItems={picker ? undefined : existingMenuItems}
     headerAction={picker ? pickerProps.headerAction : undefined}
     style={[existingStyle, pickerProps.style]}
   />
   ```

2. **Grouped item children** (~lines 1032-1056):
   Find where the `items` array is built for `GroupedItemCard`. Each child `ItemCardProps` must include picker overrides:
   ```typescript
   items={row.items.map((item) => {
     const isSelected = /* existing check */;
     const pickerProps = picker
       ? pickerMode.getPickerItemProps(item.item ?? item, isSelected)
       : {};

     return {
       ...existingProps,
       // Override with picker props when in picker mode:
       ...(picker ? {
         onPress: pickerProps.onPress,
         onSelectedChange: pickerProps.onSelectedChange,
         onBookmarkPress: undefined,
         onStatusPress: undefined,
         menuItems: undefined,
         headerAction: pickerProps.headerAction,
         style: pickerProps.style,
       } : {}),
     };
   })}
   ```
   Since `GroupedItemCard` uses `{...item}` spread on child `ItemCard`s, `headerAction` flows through automatically.

3. **Group card props** (~lines 1012-1066):
   Find where `GroupedItemCard` receives `selected`, `onSelectedChange`, `onPress`. Override in picker mode:
   ```typescript
   const groupProps = picker
     ? pickerMode.getPickerGroupProps(row.items.map(i => i.item ?? i), row.items.map(i => i.id))
     : { selected: existingSelected, onSelectedChange: existingOnSelectedChange, onPress: existingOnPress };

   <GroupedItemCard
     selected={groupProps.selected}
     onSelectedChange={groupProps.onSelectedChange}
     onPress={groupProps.onPress}
     // ... rest of existing props
   />
   ```

#### 5b: Standalone FlatList Mode (~lines 1111-1244)

Apply the **exact same pattern** as 5a to the FlatList `renderItem` callback:
- Single items: ~lines 1167-1192
- Grouped items: ~lines 1150-1200
- Group card: same pattern as embedded

The rendering logic is duplicated between embedded and standalone — both must receive picker overrides.

**Files**: `src/components/SharedItemsList.tsx`

**Notes**:
- This is the largest subtask. Read both rendering paths carefully before making changes.
- The key principle: in picker mode, `getPickerItemProps` and `getPickerGroupProps` provide ALL interaction props. Non-picker mode uses existing prop assembly.
- Don't remove existing prop assembly — conditionally override with picker props.
- Check if `headerAction` is already used anywhere in SharedItemsList (research says it's not — it exists on ItemCard but isn't used in SharedItemsList today).

---

### Subtask T006 – Add Loading/Error State Rendering for Picker Mode

**Purpose**: When `picker={true}`, show loading indicator for `outsideLoading` and error message for `outsideError`.

**Steps**:
1. Find where the empty state / "no items" message is rendered in SharedItemsList.
2. Add picker-specific states before the empty state check:
   ```typescript
   {picker && outsideLoading && (
     <View style={styles.pickerLoadingContainer}>
       <ActivityIndicator size="small" color={theme.colors.primary} />
       <AppText variant="caption" style={{ marginTop: 8 }}>Loading items...</AppText>
     </View>
   )}
   {picker && outsideError && (
     <View style={styles.pickerErrorContainer}>
       <AppText variant="caption" style={{ color: theme.colors.error ?? 'red' }}>
         {outsideError}
       </AppText>
     </View>
   )}
   ```
3. Add minimal styles for the loading/error containers (centered, with padding).
4. Import `ActivityIndicator` from `react-native` if not already imported.

**Files**: `src/components/SharedItemsList.tsx`

**Notes**:
- Check what SharedItemPicker does for loading/error (lines ~420-440) and replicate the pattern.
- These states only apply when `picker={true}` — non-picker mode is unaffected.
- Keep styling minimal and consistent with existing empty state styling.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Non-picker mode regression | Medium | High | Hook returns no-ops when disabled; all props optional |
| Dual-path rendering missed | Medium | Medium | Prompt specifies exact line ranges for both paths |
| Performance (hook overhead) | Low | Medium | All derivations memoized; short-circuit when disabled |
| headerAction not flowing through GroupedItemCard | Low | Low | Confirmed: GroupedItemCard uses `{...item}` spread |

## Review Guidance

- **Critical check**: Verify both embedded (View+map) and standalone (FlatList) paths are updated
- **Regression check**: Existing standalone and embedded modes must render identically with no picker props
- **Hook isolation**: All picker logic should be in `usePickerMode.ts`, not inline in SharedItemsList
- **Memoization**: All `useMemo`/`useCallback` dependencies must be correct (no stale closures)
- **Type safety**: No `any` casts unless unavoidable; prefer proper type narrowing

## Activity Log

- 2026-02-11T05:38:00Z – system – lane=planned – Prompt created.
- 2026-02-11T06:00:16Z – claude-sonnet – shell_pid=79999 – lane=doing – Assigned agent via workflow command
- 2026-02-11T06:13:30Z – claude-sonnet – shell_pid=79999 – lane=for_review – Ready for review: usePickerMode hook created and integrated into SharedItemsList with picker mode props. All picker props optional - no regressions to existing modes.
- 2026-02-11T06:13:52Z – claude-sonnet – shell_pid=95662 – lane=doing – Started review via workflow command
- 2026-02-11T06:16:21Z – claude-sonnet – shell_pid=95662 – lane=planned – Moved to planned
- 2026-02-11T06:17:19Z – claude-sonnet – shell_pid=99683 – lane=doing – Started implementation via workflow command
- 2026-02-11T06:19:00Z – claude-sonnet – shell_pid=99683 – lane=for_review – Ready for review: Fixed both review issues - eligibleIds now excludes addedIds, handleSelectAll simplified per spec
- 2026-02-11T06:20:13Z – claude-sonnet – shell_pid=3516 – lane=doing – Started review via workflow command
- 2026-02-11T06:24:32Z – claude-sonnet – shell_pid=3516 – lane=planned – Moved to planned
- 2026-02-11T06:27:44Z – claude-sonnet – shell_pid=11558 – lane=doing – Started implementation via workflow command
- 2026-02-11T06:30:18Z – claude-sonnet – shell_pid=11558 – lane=for_review – Ready for review: Fixed both addedIds issues - getPickerItemProps now prevents interaction with already-added items, getPickerGroupProps excludes addedIds from eligible group selection
- 2026-02-11T06:30:55Z – claude-sonnet – shell_pid=15303 – lane=doing – Started review via workflow command
- 2026-02-11T06:33:53Z – claude-sonnet – shell_pid=15303 – lane=done – Review passed: All previous issues fixed. usePickerMode hook correctly filters addedIds in eligibleIds, getPickerItemProps, and getPickerGroupProps. Both embedded and standalone rendering paths properly integrated. All subtasks complete. Zero regressions, no new TS errors. Ready to merge.
