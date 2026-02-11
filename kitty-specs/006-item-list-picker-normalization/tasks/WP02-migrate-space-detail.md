---
work_package_id: "WP02"
subtasks:
  - "T007"
  - "T008"
  - "T009"
  - "T010"
title: "Migrate SpaceDetailContent"
phase: "Phase 2 - Consumer Migration"
lane: "planned"
assignee: ""
agent: ""
shell_pid: ""
review_status: ""
reviewed_by: ""
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-11T05:38:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP02 – Migrate SpaceDetailContent

## Review Feedback

> **Populated by `/spec-kitty.review`** – Reviewers add detailed feedback here when work needs changes.

*[This section is empty initially.]*

---

## Objectives & Success Criteria

- Replace `SharedItemPicker` usage in `SpaceDetailContent.tsx` with `SharedItemsList` in picker mode
- Maintain ALL existing picker functionality: tabs, search, single add (onAddSingle), bulk add (onAddSelected), eligibility checks, "Added" badges
- Tab switching clears selection via `pickerManager.clearSelection()`
- Loading/error states for the outside tab work correctly
- **Success**: Space detail picker is visually and functionally identical to before. SharedItemPicker import is removed from this file.

## Context & Constraints

- **Spec**: `kitty-specs/006-item-list-picker-normalization/spec.md` — Migration Path, Consumer 1
- **Plan**: `kitty-specs/006-item-list-picker-normalization/plan.md` — Stage 2 (WP02)
- **Research**: `kitty-specs/006-item-list-picker-normalization/research.md` — Decision D3 (state management bridge), Consumer Analysis
- **Dependency**: WP01 must be complete (picker props + hook exist on SharedItemsList)
- **Offline-first**: No awaited Firestore writes. Fire-and-forget for item moves.
- SpaceDetailContent is the **more complex** consumer: it uses `onAddSingle`, `addedIds`, and has 2 fixed tabs.

### Key File to Modify

- `src/components/SpaceDetailContent.tsx` (1,254 lines)

### Key Lines to Understand

| What | Lines | Purpose |
|------|-------|---------|
| Picker state vars | ~152-154 | `isPickingItems`, `pickerTab`, `pickerSelectedIds` |
| activePickerItems | ~296 | Computed from pickerTab |
| handleAddSingleItem | ~360-380 | Single item add handler |
| handleAddSelectedItems | ~380-397 | Bulk add handler |
| spaceItemIds | ~419 | Set of IDs already in the space |
| BottomSheet wrapper | ~1115-1122 | 85% height bottom sheet |
| SharedItemPicker usage | ~1125-1152 | **THE TARGET** — replace this |

### Implementation Command

```bash
spec-kitty implement WP02 --base WP01
```

---

## Subtasks & Detailed Guidance

### Subtask T007 – Add useItemsManager Instance + Manager Adapter

**Purpose**: Replace `useState<string[]>` picker selection with `useItemsManager` for picker state management.

**Steps**:
1. Import `useItemsManager` (check existing imports — SpaceDetailContent likely already uses it for the embedded items section):
   ```typescript
   import { useItemsManager } from '../hooks/useItemsManager';
   ```

2. Replace the picker selection state (~line 154):
   ```typescript
   // BEFORE:
   const [pickerSelectedIds, setPickerSelectedIds] = useState<string[]>([]);

   // AFTER:
   const pickerManager = useItemsManager({
     items: activePickerItems,
     // No sort/filter needed for picker — search handled by SharedItemsList
   });
   ```
   **Note**: `useItemsManager` needs `items` — but `activePickerItems` depends on `pickerTab` which changes. Make sure the manager receives the currently active items so selection/search operates on the right set.

3. Check if `useItemsManager` needs to be called unconditionally (React rules of hooks). If the picker is conditionally shown (e.g., only when `isPickingItems` is true), the hook must still be called — just pass empty items when picker is hidden, or always call it.

4. The manager provides `selectedIds: Set<string>`. SharedItemsList's manager interface expects an object with `selectedIds`, `setItemSelected`, `setGroupSelection`, etc. Check what interface SharedItemsList expects for its `manager` prop and create an adapter if needed:
   ```typescript
   // Check SharedItemsList's UseItemsManagerReturn type
   // The manager prop likely expects the full useItemsManager return value
   // If setGroupSelection is missing, create an adapter:
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

5. Remove `pickerSelectedIds` state variable and all references to `setPickerSelectedIds`.

**Files**: `src/components/SpaceDetailContent.tsx`

**Notes**:
- Look at how the existing embedded SharedItemsList in this file uses its manager — replicate that pattern for the picker manager.
- `activePickerItems` is computed from `pickerTab` (~line 296). The manager must receive the correct items for the active tab.
- `clearSelection` on tab change: `pickerManager.clearSelection()` replaces `setPickerSelectedIds([])`.

---

### Subtask T008 – Build Tab Bar in SpaceDetailContent

**Purpose**: Extract tab bar rendering from SharedItemPicker into SpaceDetailContent. The tab bar sits above the SharedItemsList in the bottom sheet.

**Steps**:
1. Study SharedItemPicker's tab bar rendering (lines 254-317) for the visual pattern: tab buttons with counts, active indicator, horizontal layout.

2. Create a simple inline tab bar in SpaceDetailContent (above where SharedItemsList will be rendered):
   ```tsx
   {/* Inside the BottomSheet, above the list */}
   <View style={styles.pickerTabBar}>
     {[
       { value: 'current', label: pickerTabLabel },
       { value: 'outside', label: 'Outside' },
     ].map((tab) => {
       const count = tab.value === 'current'
         ? availableItems.length
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

3. Add styles for the tab bar:
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
     backgroundColor: theme.colors.primary + '20', // 12% opacity
   },
   pickerTabText: {
     // default text styling from AppText
   },
   ```

4. **Alternative**: Check if the codebase has a `SegmentedControl` or `ScreenTabs` component that could be reused (both are exported from `src/components/index.ts`). If `SegmentedControl` matches the tab pattern, use it instead of building custom JSX.

**Files**: `src/components/SpaceDetailContent.tsx`

**Notes**:
- The tab bar must be rendered inside the BottomSheet but ABOVE the SharedItemsList.
- Tab change must clear selection via `pickerManager.clearSelection()`.
- Match the visual style of SharedItemPicker's existing tabs as closely as possible.
- Accessibility: use `role="tab"` and `selected` state.

---

### Subtask T009 – Replace SharedItemPicker with SharedItemsList in Picker Mode

**Purpose**: Swap the component and wire all picker props.

**Steps**:
1. Find the `<SharedItemPicker>` usage (~lines 1125-1152). Replace with:
   ```tsx
   <SharedItemsList
     embedded={true}
     picker={true}
     items={activePickerItems}
     manager={pickerManagerAdapter}
     eligibilityCheck={{
       isEligible: (item) => item.spaceId !== spaceId && !item.transactionId,
       getStatusLabel: (item) => {
         if (item.spaceId === spaceId) return 'Already here';
         if (item.transactionId) return 'Linked';
         return undefined;
       },
     }}
     onAddSelected={handleAddSelectedItems}
     onAddSingle={handleAddSingleItem}
     addedIds={spaceItemIds}
     outsideLoading={pickerTab === 'outside' ? outsideItemsHook.loading : false}
     outsideError={pickerTab === 'outside' ? outsideItemsHook.error : null}
   />
   ```

2. **Key differences from SharedItemPicker call**:
   - `embedded={true}` + `picker={true}` (new props)
   - `manager={pickerManagerAdapter}` replaces `selectedIds` + `onSelectionChange`
   - No `tabs`, `tabCounts`, `selectedTab`, `onTabChange` props (tab bar is now rendered by parent)
   - All other props (eligibilityCheck, onAddSelected, onAddSingle, addedIds, loading, error) map directly

3. Update the `handleAddSelectedItems` handler if it references `pickerSelectedIds`:
   ```typescript
   // BEFORE (if it uses pickerSelectedIds):
   const selectedItems = items.filter(i => pickerSelectedIds.includes(i.id));

   // AFTER:
   const selectedItems = items.filter(i => pickerManager.selectedIds.has(i.id));
   ```
   Check the handler implementation and update any references to the old selection state.

4. Similarly update `handleAddSingleItem` if it clears selection:
   ```typescript
   // BEFORE: setPickerSelectedIds([])
   // AFTER: pickerManager.clearSelection()
   ```

**Files**: `src/components/SpaceDetailContent.tsx`

**Notes**:
- The `eligibilityCheck` object is identical to what was passed to SharedItemPicker — copy it directly.
- `spaceItemIds` (Set) maps directly to `addedIds` prop.
- Make sure `handleAddSelectedItems` and `handleAddSingleItem` still work with the new selection state format.

---

### Subtask T010 – Wire Tab Change, Loading/Error, Remove Old Import

**Purpose**: Final wiring and cleanup for the SpaceDetailContent migration.

**Steps**:
1. Update the tab change handler (already handled in T008 tab bar, but verify):
   ```typescript
   // Tab change should:
   setPickerTab(next as ItemPickerTab);
   pickerManager.clearSelection(); // replaces setPickerSelectedIds([])
   ```

2. Verify loading/error props are wired correctly:
   ```typescript
   outsideLoading={pickerTab === 'outside' ? outsideItemsHook.loading : false}
   outsideError={pickerTab === 'outside' ? outsideItemsHook.error : null}
   ```

3. Remove the `SharedItemPicker` import:
   ```typescript
   // REMOVE:
   import { SharedItemPicker } from './SharedItemPicker';
   // or from '../components' barrel
   ```

4. Remove any unused imports that were only needed for SharedItemPicker (e.g., if `ItemEligibilityCheck` was imported from SharedItemPicker, it's now imported from usePickerMode via SharedItemsList).

5. Add the `SharedItemsList` import if not already present (it likely is, for the embedded items section).

6. Clean up the old `pickerSelectedIds` state and any adapter code that's no longer needed.

**Files**: `src/components/SpaceDetailContent.tsx`

**Notes**:
- Search for ALL references to `pickerSelectedIds` and `setPickerSelectedIds` in the file — they must all be replaced.
- The `isPickingItems` state and `setIsPickingItems` remain unchanged (controls bottom sheet visibility).

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Selection state bridge bugs | Low | Medium | useItemsManager adapter pattern already proven in codebase |
| Tab bar styling mismatch | Low | Low | Extract directly from SharedItemPicker; styles are inline |
| Handler references to old state | Medium | Medium | Search file for all `pickerSelectedIds` references |
| Bottom sheet layout shift | Low | Low | SharedItemsList embedded mode is already used in this file |

## Review Guidance

- **Critical check**: Picker functionality parity — tabs, search, single add, bulk add, eligibility, Added badges
- **State check**: No references to `pickerSelectedIds` or `setPickerSelectedIds` remain
- **Import check**: `SharedItemPicker` import removed, `SharedItemsList` import present
- **Visual check**: Tab bar matches SharedItemPicker's tab styling
- **Edge cases**: Tab switching clears selection; ineligible items can't be selected; fully-ineligible groups are no-op on tap

## Activity Log

- 2026-02-11T05:38:00Z – system – lane=planned – Prompt created.
