---
work_package_id: WP03
title: Migrate TransactionDetailScreen
lane: "for_review"
dependencies: [WP01]
base_branch: 006-item-list-picker-normalization-WP01
base_commit: f32cc4587085bbc59992dddae249895453dbfc9f
created_at: '2026-02-11T06:34:56.978085+00:00'
subtasks:
- T011
- T012
- T013
phase: Phase 2 - Consumer Migration
assignee: ''
agent: "claude-sonnet"
shell_pid: "20094"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-11T05:38:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP03 – Migrate TransactionDetailScreen

## Review Feedback

> **Populated by `/spec-kitty.review`** – Reviewers add detailed feedback here when work needs changes.

*[This section is empty initially.]*

---

## Objectives & Success Criteria

- Replace `SharedItemPicker` usage in `TransactionDetailScreen` with `SharedItemsList` in picker mode
- Maintain ALL existing picker functionality: dynamic tabs (suggested/project/outside), bulk add (onAddSelected), eligibility checks, conflict dialog handling
- This consumer does **NOT** use `onAddSingle` or `addedIds` — bulk selection only
- **Success**: Transaction detail picker is visually and functionally identical to before. SharedItemPicker import is removed from this file.

## Context & Constraints

- **Spec**: `kitty-specs/006-item-list-picker-normalization/spec.md` — Migration Path, Consumer 2
- **Plan**: `kitty-specs/006-item-list-picker-normalization/plan.md` — Stage 3 (WP03)
- **Dependency**: WP01 must be complete (picker mode exists on SharedItemsList)
- **Can run in parallel with WP02** (different file)
- This is the **simpler** consumer: no onAddSingle, no addedIds, bulk-only mode
- Dynamic tabs: 2 tabs (suggested + outside) when no project, 3 tabs (suggested + project + outside) when projectId exists

### Key File to Modify

- `app/transactions/[id]/index.tsx` (1,796 lines)

### Key Lines to Understand

| What | Lines | Purpose |
|------|-------|---------|
| Picker state vars | ~105-107 | `isPickingItems`, `pickerTab`, `pickerSelectedIds` |
| suggestedItems | ~267-273 | Filtered by normalizedSource |
| projectItems | ~275 | Filtered by projectId |
| activePickerItems | ~277-281 | Computed from pickerTab |
| pickerTabOptions | ~283-290 | Dynamic tab array |
| handleAddSelectedItems | ~411-461 | Bulk add with conflict checking |
| BottomSheet wrapper | ~1510 | 85% height bottom sheet |
| SharedItemPicker usage | ~1522-1548 | **THE TARGET** — replace this |

### Implementation Command

```bash
spec-kitty implement WP03 --base WP01
```

---

## Subtasks & Detailed Guidance

### Subtask T011 – Add useItemsManager Instance + Manager Adapter

**Purpose**: Replace `useState<string[]>` picker selection with `useItemsManager` for picker state management.

**Steps**:
1. Import `useItemsManager` if not already imported:
   ```typescript
   import { useItemsManager } from '../../src/hooks/useItemsManager';
   ```
   **Note**: Check the exact import path — this is in `app/transactions/[id]/index.tsx`, so the relative path to `src/hooks/` will differ from components in `src/`.

2. Replace the picker selection state (~line 107):
   ```typescript
   // BEFORE:
   const [pickerSelectedIds, setPickerSelectedIds] = useState<string[]>([]);

   // AFTER:
   const pickerManager = useItemsManager({
     items: activePickerItems,
   });
   ```

3. Create a manager adapter (same pattern as WP02/T007):
   ```typescript
   const pickerManagerAdapter = useMemo(() => ({
     ...pickerManager,
     setGroupSelection: (ids: string[], selected: boolean) => {
       ids.forEach(id => {
         const isCurrentlySelected = pickerManager.selectedIds.has(id);
         if (selected !== isCurrentlySelected) {
           pickerManager.toggleSelection(id);
         }
       });
     },
     setItemSelected: (id: string, selected: boolean) => {
       const isCurrentlySelected = pickerManager.selectedIds.has(id);
       if (selected !== isCurrentlySelected) {
         pickerManager.toggleSelection(id);
       }
     },
   }), [pickerManager]);
   ```

4. Update `handleAddSelectedItems` to use new selection state:
   ```typescript
   // BEFORE (if references pickerSelectedIds):
   const selectedItems = items.filter(i => pickerSelectedIds.includes(i.id));

   // AFTER:
   const selectedItems = items.filter(i => pickerManager.selectedIds.has(i.id));
   ```
   Check the handler implementation (~lines 411-461) for all references to old selection state.

5. Remove `pickerSelectedIds` state and `setPickerSelectedIds` — search for ALL references in the file.

**Files**: `app/transactions/[id]/index.tsx`

**Notes**:
- The `activePickerItems` computation depends on `pickerTab`. Ensure the manager receives updated items when tab changes.
- `handleAddSelectedItems` uses `showItemConflictDialog` for conflict handling — this stays unchanged, just update the selection state references.
- React hooks rules: the `useItemsManager` call must be unconditional (not inside `if (isPickingItems)`).

---

### Subtask T012 – Build Tab Bar in TransactionDetailScreen

**Purpose**: Render a tab bar for the picker with dynamic tab count (2 or 3 tabs based on projectId).

**Steps**:
1. Find the existing `pickerTabOptions` computation (~lines 283-290):
   ```typescript
   const pickerTabOptions = useMemo(() => {
     const tabs = [{ value: 'suggested', label: 'Suggested' }];
     if (projectId) tabs.push({ value: 'project', label: 'Project' });
     tabs.push({ value: 'outside', label: 'Outside' });
     return tabs;
   }, [projectId]);
   ```
   This already exists — reuse it for the tab bar.

2. Render the tab bar inside the BottomSheet, above where SharedItemsList will go:
   ```tsx
   <View style={styles.pickerTabBar}>
     {pickerTabOptions.map((tab) => {
       const count = tab.value === 'suggested'
         ? suggestedItems.length
         : tab.value === 'project'
           ? projectItems.length
           : outsideItemsHook.items.length;
       const isActive = pickerTab === tab.value;

       return (
         <TouchableOpacity
           key={tab.value}
           onPress={() => {
             setPickerTab(tab.value as ItemPickerTab);
             pickerManager.clearSelection();
           }}
           style={[
             styles.pickerTab,
             isActive && styles.pickerTabActive,
           ]}
           accessibilityRole="tab"
           accessibilityState={{ selected: isActive }}
         >
           <AppText
             variant="body"
             style={[
               styles.pickerTabText,
               isActive && { color: theme.colors.primary },
             ]}
           >
             {tab.label} ({count})
           </AppText>
         </TouchableOpacity>
       );
     })}
   </View>
   ```

3. Add tab bar styles (same as WP02):
   ```typescript
   pickerTabBar: {
     flexDirection: 'row',
     paddingHorizontal: 16,
     paddingVertical: 8,
     gap: 12,
   },
   pickerTab: {
     paddingVertical: 6,
     paddingHorizontal: 12,
     borderRadius: 8,
   },
   pickerTabActive: {
     backgroundColor: theme.colors.primary + '20',
   },
   ```

4. **Alternative**: Check if WP02 created a reusable `PickerTabBar` component. If so, import and reuse it. If not, inline the JSX (it's small enough).

5. **Alternative**: Check for existing `SegmentedControl` component in the codebase that could be reused.

**Files**: `app/transactions/[id]/index.tsx`

**Notes**:
- The tab count computation uses `tabCounts` object — adapt from the existing SharedItemPicker props.
- The `pickerTabOptions` array is already computed — just map over it for the tab bar UI.
- Tab change clears selection: `pickerManager.clearSelection()`.

---

### Subtask T013 – Replace SharedItemPicker with SharedItemsList in Picker Mode

**Purpose**: Swap the component, wire all props, and clean up imports.

**Steps**:
1. Find the `<SharedItemPicker>` usage (~lines 1522-1548). Replace with:
   ```tsx
   <SharedItemsList
     embedded={true}
     picker={true}
     items={activePickerItems}
     manager={pickerManagerAdapter}
     eligibilityCheck={{
       isEligible: (item) => item.transactionId !== id,
       getStatusLabel: (item) => {
         if (item.transactionId === id) return 'Already linked';
         if (item.transactionId) return 'Linked elsewhere';
         return undefined;
       },
     }}
     onAddSelected={handleAddSelectedItems}
     outsideLoading={pickerTab === 'outside' ? outsideItemsHook.loading : false}
     outsideError={pickerTab === 'outside' ? outsideItemsHook.error : null}
   />
   ```

2. **Key differences from SpaceDetailContent (WP02)**:
   - **No** `onAddSingle` prop (no per-item Add button)
   - **No** `addedIds` prop (no "Added" badges)
   - Only `onAddSelected` for bulk add
   - Different eligibility logic (checks `transactionId` instead of `spaceId`)

3. Remove the `SharedItemPicker` import:
   ```typescript
   // REMOVE:
   import { SharedItemPicker } from '../../src/components/SharedItemPicker';
   // or from the barrel: import { SharedItemPicker } from '../../src/components';
   ```

4. Add/verify the `SharedItemsList` import (it's likely already imported for the embedded items section).

5. Remove any unused imports that were only needed for SharedItemPicker.

6. Remove the `tabs`, `tabCounts`, `selectedTab`, `onTabChange` props from SharedItemPicker — they're no longer needed (tab bar is parent-rendered).

7. Search for ALL remaining references to `pickerSelectedIds` and `setPickerSelectedIds` — they must all be updated or removed.

**Files**: `app/transactions/[id]/index.tsx`

**Notes**:
- The `handleAddSelectedItems` handler (~lines 411-461) uses `showItemConflictDialog` — this flow is unchanged, just verify selection state references are updated.
- The `isPickingItems` state and bottom sheet wrapper remain unchanged.
- `outsideItemsHook` loading/error props map directly.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Dynamic tab count regression | Low | Medium | Reuse existing `pickerTabOptions` computation |
| Conflict dialog broken | Low | High | Handler logic unchanged; only selection state access changes |
| Handler references old state | Medium | Medium | Search file for ALL `pickerSelectedIds` references |
| Import path wrong | Low | Low | Verify relative path from `app/transactions/[id]/` to `src/hooks/` |

## Review Guidance

- **Critical check**: Picker functionality parity — dynamic tabs, search, bulk add, eligibility, conflict dialog
- **State check**: No references to `pickerSelectedIds` or `setPickerSelectedIds` remain
- **Import check**: `SharedItemPicker` import removed, correct imports for SharedItemsList and useItemsManager
- **Bulk-only check**: No onAddSingle or addedIds props should be present (this consumer is bulk-only)
- **Dynamic tabs check**: 2 tabs without projectId, 3 tabs with projectId

## Activity Log

- 2026-02-11T05:38:00Z – system – lane=planned – Prompt created.
- 2026-02-11T06:34:57Z – claude-sonnet – shell_pid=20094 – lane=doing – Assigned agent via workflow command
- 2026-02-11T06:38:18Z – claude-sonnet – shell_pid=20094 – lane=for_review – Ready for review: Migrated TransactionDetailScreen to SharedItemsList picker mode with dynamic tab bar
