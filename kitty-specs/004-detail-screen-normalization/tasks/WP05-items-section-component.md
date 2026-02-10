---
work_package_id: WP05
title: Create ItemsSection Component + Integration
lane: "doing"
dependencies: [WP02, WP04]
base_branch: 004-detail-screen-normalization-WP05-merge-base
base_commit: 1db3b5e391290e0c28dad0729b19f3a2baa82c14
created_at: '2026-02-10T03:50:42.508435+00:00'
subtasks:
- T021
- T022
- T023
- T024
- T025
phase: Phase 2 - Shared Items Management
assignee: ''
agent: "claude-sonnet"
shell_pid: "8818"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-10T02:25:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP05 – Create ItemsSection Component + Integration

## Important: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP05 --base WP02
```

Depends on WP02 (space detail on SectionList) and WP04 (useItemsManager hook).

---

## Objectives & Success Criteria

- **Objective**: Create a shared `ItemsSection` component that renders the items list with `ItemCard` components and a bulk action panel. Integrate into both space detail and transaction detail, replacing duplicated items rendering logic.
- Completes **User Story 3** (shared items management).
- Completes **FR-004** (shared items management components) and **SC-004** (items code in one place).

**Success Criteria**:
1. `src/components/ItemsSection.tsx` renders item list + bulk panel using `useItemsManager` return value
2. Space detail uses `ItemsSection` for its items section rendering
3. Transaction detail uses `ItemsSection` for its items section rendering
4. Search, sort, filter, bulk select work identically on both screens
5. Screen-specific bulk actions are config-driven (not hardcoded in ItemsSection)
6. Control bar remains in `renderSectionHeader` (sticky) — ItemsSection only handles the list content

## Context & Constraints

**Architecture**: ItemsSection is a **presentation component** that receives its state from `useItemsManager`. The control bar (`ItemsListControlBar`) stays in each screen's `renderSectionHeader` callback because it needs to be sticky. ItemsSection renders what goes **inside** the items section: the item cards and the bulk action panel.

**Reference: data-model.md** — Section 4 defines `ItemsSectionProps` and `BulkAction` types.

**Current items rendering locations**:
- **Space detail** (`SpaceDetailContent`): renders `filteredSpaceItems.map(item => <ItemCard .../>)` with inline bulk panel
- **Transaction detail** (`app/transactions/[id]/index.tsx`): renders items in `renderItem` case `'items'` as `<ItemCard .../>`

**Bulk operations differ by screen**:
| Screen | Bulk Actions |
|--------|-------------|
| Space detail | Move to space, Remove from space |
| Transaction detail | Set space, Set status, Set SKU, Remove from transaction, Delete |

Both screens show the bulk panel inline when items are selected. The panel includes a selection count, action buttons, and a "clear selection" option.

---

## Subtasks & Detailed Guidance

### Subtask T021 – Create ItemsSection component skeleton

**Purpose**: Establish the shared component file with props interface.

**Steps**:
1. Create `src/components/ItemsSection.tsx`
2. Define the props interface:
   ```typescript
   import { UseItemsManagerReturn } from '../hooks/useItemsManager';
   import { ScopedItem } from '../services/itemsService';
   import { AnchoredMenuItem } from './BottomSheetMenuList';

   export type BulkAction = {
     id: string;
     label: string;
     variant: 'primary' | 'secondary' | 'destructive';
     icon?: string;
   };

   export type ItemsSectionProps = {
     // State from useItemsManager
     manager: UseItemsManagerReturn;

     // Item rendering
     items: ScopedItem[];
     onItemPress: (id: string) => void;
     getItemMenuItems: (item: ScopedItem) => AnchoredMenuItem[];
     onBookmarkPress?: (item: ScopedItem) => void;

     // Bulk actions (screen-specific)
     bulkActions?: BulkAction[];
     onBulkAction?: (actionId: string, selectedIds: string[]) => void;

     // Display
     emptyMessage?: string;
   };
   ```

3. Create the component function:
   ```typescript
   export function ItemsSection({
     manager,
     items,
     onItemPress,
     getItemMenuItems,
     onBookmarkPress,
     bulkActions,
     onBulkAction,
     emptyMessage = 'No items.',
   }: ItemsSectionProps) {
     // T022-T023 fill this in
   }
   ```

**Files**:
- `src/components/ItemsSection.tsx` (new, ~30 lines skeleton)

**Notes**:
- The `items` prop receives `manager.filteredAndSortedItems` — the filtered/sorted array from the hook
- `manager` provides selection state and handlers
- The component does NOT render `ItemsListControlBar` — that stays in `renderSectionHeader` for stickiness

---

### Subtask T022 – Implement items list rendering

**Purpose**: Render the list of `ItemCard` components with selection and menu integration.

**Steps**:
1. Implement the items list:
   ```typescript
   const { selectedIds, toggleSelection, hasSelection } = manager;
   const uiKitTheme = useUIKitTheme();

   // Helper to get primary image URI
   const getPrimaryImageUri = (item: ScopedItem): string | undefined => {
     const primary = item.images?.find(img => img.isPrimary);
     return primary?.url ?? item.images?.[0]?.url;
   };

   // Helper to get display price
   const getDisplayPrice = (item: ScopedItem): string | undefined => {
     if (typeof item.purchasePriceCents === 'number') {
       return `$${(item.purchasePriceCents / 100).toFixed(2)}`;
     }
     return undefined;
   };

   return (
     <View>
       {/* Bulk panel (T023) */}

       {/* Items list */}
       {items.length === 0 ? (
         <View style={styles.emptyState}>
           <AppText variant="body" style={{ color: uiKitTheme.text.secondary }}>
             {emptyMessage}
           </AppText>
         </View>
       ) : (
         <View style={styles.list}>
           {items.map(item => (
             <ItemCard
               key={item.id}
               name={item.name?.trim() || 'Untitled item'}
               sku={item.sku ?? undefined}
               priceLabel={getDisplayPrice(item)}
               thumbnailUri={getPrimaryImageUri(item)}
               bookmarked={item.bookmark ?? undefined}
               selected={hasSelection ? selectedIds.has(item.id) : undefined}
               onSelectedChange={hasSelection
                 ? () => toggleSelection(item.id)
                 : undefined}
               onBookmarkPress={onBookmarkPress
                 ? () => onBookmarkPress(item)
                 : undefined}
               onPress={() => onItemPress(item.id)}
               menuItems={getItemMenuItems(item)}
             />
           ))}
         </View>
       )}
     </View>
   );
   ```

2. **Selection visibility**: Only show selection checkboxes when `hasSelection` is true (i.e., at least one item is selected or bulk mode is active). This matches the current space detail behavior where selection appears only in bulk mode.

3. **Note on SectionList integration**: When used inside a SectionList, this component renders in `renderItem` for each item in the items section. However, it's cleaner to have the SectionList section data contain a single marker, and `renderItem` renders the entire ItemsSection once. This avoids the SectionList managing individual items (which would break the bulk panel placement).

   Alternatively, the consumer can choose: either pass individual items as section data (and renderItem renders each ItemCard), or pass a single marker and renderItem renders the entire ItemsSection. The space and transaction detail implementations (T024, T025) will determine the best approach.

**Files**:
- `src/components/ItemsSection.tsx` (modify)

---

### Subtask T023 – Implement bulk action panel

**Purpose**: Render the bulk selection panel with screen-specific action buttons when items are selected.

**Steps**:
1. Add the bulk panel above the items list:
   ```typescript
   {hasSelection && bulkActions && onBulkAction && (
     <View style={styles.bulkPanel}>
       <View style={styles.bulkHeader}>
         <AppText variant="body">
           {manager.selectionCount} selected
         </AppText>
         <View style={styles.bulkActions}>
           <Pressable onPress={manager.selectAll}>
             <AppText variant="caption" style={{ color: uiKitTheme.primary.main }}>
               {manager.allSelected ? 'Deselect All' : 'Select All'}
             </AppText>
           </Pressable>
           <Pressable onPress={manager.clearSelection}>
             <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
               Clear
             </AppText>
           </Pressable>
         </View>
       </View>

       <View style={styles.bulkButtonRow}>
         {bulkActions.map(action => (
           <AppButton
             key={action.id}
             title={action.label}
             variant={action.variant === 'destructive' ? 'secondary' : action.variant}
             onPress={() => onBulkAction(action.id, [...manager.selectedIds])}
             icon={action.icon}
           />
         ))}
       </View>
     </View>
   )}
   ```

2. Bulk panel shows:
   - Selection count ("3 selected")
   - Select All / Deselect All toggle
   - Clear selection button
   - Screen-specific action buttons (rendered from `bulkActions` config)

3. When a bulk action is triggered, call `onBulkAction(actionId, selectedIds[])`. The screen handles the actual operation (Alert confirmation, service calls, etc.).

4. Add styles:
   ```typescript
   const styles = StyleSheet.create({
     list: { gap: 10 },
     emptyState: { alignItems: 'center', paddingVertical: 16 },
     bulkPanel: { gap: 10, marginBottom: 12 },
     bulkHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
     bulkActions: { flexDirection: 'row', gap: 12, alignItems: 'center' },
     bulkButtonRow: { flexDirection: 'row', gap: 10, flexWrap: 'wrap' },
   });
   ```

**Files**:
- `src/components/ItemsSection.tsx` (modify)

**Notes**:
- Space detail currently has: "Move to space" (SpaceSelector), "Remove from space" (destructive)
- Transaction detail currently has: "Set space", "Set status", "Set SKU", "Remove from transaction" (destructive), "Delete" (destructive)
- The SpaceSelector for "Move to space" is screen-specific UI. The space detail screen will handle showing it when `onBulkAction('move', ids)` is called.

---

### Subtask T024 – Integrate ItemsSection into SpaceDetailContent

**Purpose**: Replace the inline items rendering in SpaceDetailContent with the shared ItemsSection component.

**Steps**:
1. Initialize `useItemsManager` in SpaceDetailContent:
   ```typescript
   import { useItemsManager } from '../hooks/useItemsManager';

   const itemsManager = useItemsManager({
     items: spaceItems,  // the raw items array from subscription
     defaultSort: 'created-desc',
     defaultFilter: 'all',
     sortModes: ['created-desc', 'created-asc', 'alphabetical-asc', 'alphabetical-desc'],
     filterModes: ['all', 'bookmarked', 'no-sku', 'no-image'],
     filterFn: (item, mode) => {
       switch (mode) {
         case 'bookmarked': return item.bookmark === true;
         case 'no-sku': return !item.sku?.trim();
         case 'no-image': return !item.images?.length;
         default: return true;
       }
     },
   });
   ```

2. Remove the existing inline state: `searchQuery`, `showSearch`, `sortMode`, `sortMenuVisible`, `filterMode`, `filterMenuVisible`, `bulkSelectedIds`, `bulkMode`

3. Update `renderSectionHeader` for items section to use `itemsManager`:
   ```typescript
   // In renderSectionHeader for items:
   <ItemsListControlBar
     search={itemsManager.searchQuery}
     onChangeSearch={itemsManager.setSearchQuery}
     showSearch={itemsManager.showSearch}
     onToggleSearch={itemsManager.toggleSearch}
     onSort={() => itemsManager.setSortMenuVisible(true)}
     isSortActive={itemsManager.isSortActive}
     onFilter={() => itemsManager.setFilterMenuVisible(true)}
     isFilterActive={itemsManager.isFilterActive}
     onAdd={itemsManager.hasSelection
       ? () => { /* open bulk menu */ }
       : () => setAddMenuVisible(true)}
   />
   ```

4. Update `renderItem` for items section:
   ```typescript
   case 'items':
     return (
       <ItemsSection
         manager={itemsManager}
         items={itemsManager.filteredAndSortedItems}
         onItemPress={(id) => { /* navigate to item detail */ }}
         getItemMenuItems={getItemMenuItems}
         bulkActions={[
           { id: 'move', label: 'Move', variant: 'secondary', icon: 'swap-horiz' },
           { id: 'remove', label: 'Remove', variant: 'destructive', icon: 'remove-circle-outline' },
         ]}
         onBulkAction={handleBulkAction}
       />
     );
   ```

5. Implement `handleBulkAction` callback:
   ```typescript
   const handleBulkAction = useCallback((actionId: string, ids: string[]) => {
     switch (actionId) {
       case 'move':
         setBulkTargetSpaceId(null); // reset
         // Show space selector...
         break;
       case 'remove':
         handleBulkRemove(ids);
         break;
     }
   }, [handleBulkRemove]);
   ```

6. Update sections array: items section data should be `itemsManager.filteredAndSortedItems` (instead of the old `filteredSpaceItems`)

7. Update sort/filter menu items to use `itemsManager.setSortMode` and `itemsManager.setFilterMode`

8. Remove `filteredSpaceItems` useMemo (now handled by hook)

**Files**:
- `src/components/SpaceDetailContent.tsx` (modify)

**Notes**:
- The `bulkMode` toggle ("Select multiple items...") can be replaced by tapping the select-all button or long-pressing an item. Alternatively, keep the toggle but wire it to `itemsManager.selectAll()` or a local `bulkMode` state that shows selection checkboxes.
- SpaceSelector for bulk move remains screen-specific UI outside ItemsSection

---

### Subtask T025 – Integrate ItemsSection into transaction detail

**Purpose**: Replace the inline items rendering in transaction detail with the shared ItemsSection component.

**Steps**:
1. Initialize `useItemsManager` in transaction detail:
   ```typescript
   const itemsManager = useItemsManager({
     items: scopedItems,  // from subscription
     defaultSort: 'created-desc',
     defaultFilter: 'all',
     sortModes: ['created-desc', 'created-asc', 'alphabetical-asc', 'alphabetical-desc', 'price-asc', 'price-desc'],
     filterModes: ['all', 'bookmarked', 'no-sku', 'no-name', 'no-price', 'no-image'],
     filterFn: (item, mode) => {
       switch (mode) {
         case 'bookmarked': return item.bookmark === true;
         case 'no-sku': return !item.sku?.trim();
         case 'no-name': return !item.name?.trim();
         case 'no-price': return item.purchasePriceCents == null;
         case 'no-image': return !item.images?.length;
         default: return true;
       }
     },
     sortFn: (a, b, mode) => {
       switch (mode) {
         case 'price-asc':
           return (a.purchasePriceCents ?? 0) - (b.purchasePriceCents ?? 0);
         case 'price-desc':
           return (b.purchasePriceCents ?? 0) - (a.purchasePriceCents ?? 0);
         // Base modes handled by hook's built-in sort
         default: return 0;
       }
     },
   });
   ```

2. Remove existing inline state: `searchQuery`, `showSearch`, `sortMode`, `sortMenuVisible`, `filterMode`, `filterMenuVisible`, `selectedItemIds`

3. Update `renderSectionHeader` to use `itemsManager` (same pattern as T024)

4. Update the `renderItem` case for `'items'` to render ItemCard using `itemsManager`:
   ```typescript
   case 'items':
     return (
       <ItemCard
         key={item.id}
         name={item.name?.trim() || 'Untitled item'}
         // ... existing props
         selected={itemsManager.selectedIds.has(item.id)}
         onSelectedChange={() => itemsManager.toggleSelection(item.id)}
       />
     );
   ```

   **Note**: Transaction detail's items section already renders individual items via SectionList section data. It may be cleaner to keep this pattern (individual ItemCards in renderItem) and only use ItemsSection for the bulk panel, or switch to the single-marker pattern. Choose the approach that minimizes changes to the existing SectionList structure.

5. Implement `handleBulkAction` for transaction-specific operations:
   ```typescript
   const handleBulkAction = useCallback((actionId: string, ids: string[]) => {
     switch (actionId) {
       case 'set-space': handleBulkSetSpace(ids); break;
       case 'set-status': handleBulkSetStatus(ids); break;
       case 'set-sku': handleBulkSetSKU(ids); break;
       case 'remove': handleBulkRemove(ids); break;
       case 'delete': handleBulkDelete(ids); break;
     }
   }, [handleBulkSetSpace, handleBulkSetStatus, handleBulkSetSKU, handleBulkRemove, handleBulkDelete]);
   ```

6. Update sort/filter/bulk menu items to use `itemsManager` methods

7. Remove `filteredAndSortedItems` useMemo and `handleSelectAll` (now in hook)

**Files**:
- `app/transactions/[id]/index.tsx` (modify)

**Notes**:
- Transaction detail has a more complex items setup: conflict resolution, item duplication, per-item status submenu
- The `getItemMenuItems` function with its rich subactions stays screen-specific
- Bulk operations (space picker, status picker, SKU input) use bottom sheet modals that are screen-specific — keep these in the transaction detail file

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Bulk action UX differences | Medium | Medium | Config-driven: each screen passes its own bulkActions array |
| SectionList integration patterns differ | Low | Medium | Analyze both screens' SectionList structure before choosing pattern |
| Selection state transition (string[] to Set) | Low | Low | Space detail already moves to useItemsManager which uses Set |

## Review Guidance

1. **Space detail**: Search, sort, filter, bulk move, bulk remove all work
2. **Transaction detail**: Same + set space, set status, set SKU, remove, delete bulk actions
3. No inline items state remains in either screen (all via useItemsManager)
4. Control bar is sticky on both screens
5. Empty state shows when all items are filtered out
6. Selection count is accurate; select all/clear work correctly

---

## Activity Log

- 2026-02-10T02:25:42Z – system – lane=planned – Prompt created.
- 2026-02-10T03:50:42Z – claude-sonnet – shell_pid=54610 – lane=doing – Assigned agent via workflow command
- 2026-02-10T04:11:44Z – claude-sonnet – shell_pid=54610 – lane=for_review – Ready for review: ItemsSection component created and integrated into both space detail and transaction detail screens. All subtasks complete.
- 2026-02-10T04:16:04Z – claude-sonnet – shell_pid=8818 – lane=doing – Started review via workflow command
