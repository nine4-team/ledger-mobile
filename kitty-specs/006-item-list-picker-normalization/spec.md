# Item List Picker Normalization

## Feature Overview

**Goal:** Make `SharedItemsList` the single component for all item list rendering with selection, fully absorbing `SharedItemPicker`. No functionality from either component may be dropped.

**Motivation:** The app currently has two separate components that render item lists with grouping and selection — `SharedItemsList` and `SharedItemPicker` — with divergent behavior, duplicated logic, and inconsistent UX. Maintaining both components is a maintenance burden and the source of bugs (e.g., grouped items in the picker cannot be quick-added individually, and collapsed group body tap expands instead of selecting).

## Actors

- **App user:** Interacts with item lists in standalone screens (business inventory, project items) and in embedded/picker contexts (space detail "Add Existing Items," transaction detail "Add Existing Items").
- **Developer:** Maintains a single list component instead of two, reducing surface area for bugs.

## Audit Findings

### Two Components, Same Job

| Feature | SharedItemsList | SharedItemPicker |
|---------|----------------|-----------------|
| Selection state | `useItemsManager` or internal `selectedIds` | Parent-controlled `selectedIds` + `onSelectionChange` |
| Group selection | `setGroupSelection(ids, bool)` via manager | `handleGroupToggle(ids, bool)` inline |
| Bulk actions | BulkSelectionBar + BottomSheet with configurable actions | "Add Selected" button in control bar |
| Search/sort/filter | Full control bar (`ItemsListControlBar`) | Search only (`ItemPickerControlBar`) |
| Individual add button | No (uses `onPress` for navigation) | Yes (`headerAction` with Add button) — **but only on ungrouped items** |
| Grouping logic | Configurable via composite key `name::sku::source` | Groups by `name.toLowerCase()` (hardcoded) |
| Eligibility checks | None (all items are interactive) | `isEligible` / `getStatusLabel` / `isAlreadyInTarget` |

### Selection Behavior Differences

#### SharedItemsList (standalone FlatList mode)
- **Group header selector**: Shows when `onSelectedChange` is provided; toggles all items via `setGroupSelection`
- **Child items (expanded)**: Each has `onSelectedChange`, `onPress` (navigation), `onStatusPress`, `onBookmarkPress`, `menuItems`
- **Body tap**: Navigates to item detail

#### SharedItemPicker
- **Group header selector**: Shows; toggles only eligible items via `handleGroupToggle`
- **Child items (expanded)**: Have `onSelectedChange` and `onPress` (both toggle selection) — no bookmark, status, menu
- **Body tap (collapsed group)**: Expands/collapses the group — **does NOT toggle selection** (unlike individual items where body tap = select)
- **Missing**: `headerAction` (Add button) not passed to grouped item children — only individual items get it

### Root Cause of "Can't Select" Bug

When items in the picker share the same name and get grouped, the grouped card's collapsed body tap expands instead of selecting. Meanwhile, individual (ungrouped) items toggle selection on body tap. This inconsistency is confusing.

Additionally, grouped item children in the picker don't have the individual "Add" button (`headerAction`) that ungrouped items do, making it impossible to quick-add a single item from within a group.

### Where SharedItemPicker Is Used

| Screen | Component | File | Lines | Config |
|--------|-----------|------|-------|--------|
| Space detail | `SpaceDetailContent` | `src/components/SpaceDetailContent.tsx` | 1125-1152 | 2 tabs (`current`/`outside`), eligibility by spaceId/transactionId, has `onAddSingle` + `addedIds` |
| Transaction detail | `TransactionDetailScreen` | `app/transactions/[id]/index.tsx` | 1365-1391 | 2-3 tabs (`suggested`/`project`?/`outside`), bulk selection only (no `onAddSingle`/`addedIds`) |

### Where SharedItemsList Is Used

- **Standalone mode**: Main items list screens (business inventory, project items)
- **Embedded mode**: Space detail items section, transaction detail items section

### Where ItemPickerControlBar Is Used

- Only consumer: `SharedItemPicker` internally (lines 318-328). Not used anywhere else.

## Functional Requirements

### FR-1: New Picker Mode Props on SharedItemsList

Add optional props that enable picker-specific behavior when `picker={true}`:

```typescript
type ItemEligibilityCheck = {
  /** Returns false for items that cannot be selected (e.g., already in target space, locked) */
  isEligible: (item: ScopedItem | Item) => boolean;
  /** Returns a status label for ineligible items (e.g., "Already here", "Linked") */
  getStatusLabel?: (item: ScopedItem | Item) => string | undefined;
  /** Returns true if item was already added to the target (shows "Added" badge, not the same as ineligible) */
  isAlreadyInTarget?: (item: ScopedItem | Item) => boolean;
};

type SharedItemsListProps = {
  // ... existing props ...

  /** Enables picker mode: body tap toggles selection, no bookmark/status/menu, shows picker control bar */
  picker?: boolean;

  /** Eligibility check for picker mode — ineligible items are visually locked and unselectable */
  eligibilityCheck?: ItemEligibilityCheck;

  /** Callback for per-item quick-add (renders "Add" button in each item's header) */
  onAddSingle?: (item: ScopedItem | Item) => void | Promise<void>;

  /** Set of IDs already added (shows "Added" badge on those items) */
  addedIds?: Set<string>;

  /** Callback for the "Add Selected" button in picker control bar */
  onAddSelected?: () => void | Promise<void>;

  /** Label prefix for the add button (default: "Add") */
  addButtonLabel?: string;

  /** Loading state for outside items tab */
  outsideLoading?: boolean;

  /** Error message for outside items tab */
  outsideError?: string | null;

  /** Placeholder text for picker search input */
  searchPlaceholder?: string;
};
```

### FR-2: Picker Mode Rendering Behavior

When `picker={true}`:

1. **Body tap** on both individual and grouped items toggles selection (not navigation). `onPress` wired to toggle selection, not `handleOpenItem`.
2. **Grouped items (collapsed)**: Body tap toggles group selection for all eligible items. The `onPress` prop on `GroupedItemCard` calls `setGroupSelection` on eligible items.
3. **`headerAction`** with Add button renders on ALL items — both ungrouped items and grouped item children. This is wired via the `items` array passed to `GroupedItemCard` (which spreads props to child `ItemCard`s).
4. **Ineligible items**: `onSelectedChange: undefined`, `onPress: undefined`, reduced opacity (`0.5`). The eligibility check via `eligibilityCheck.isEligible(item)` controls this.
5. **Already-added items**: Show "Added" badge (via `headerAction` rendering the badge instead of an "Add" button) when `addedIds?.has(item.id)`.
6. **No bookmark/status/menu** actions rendered in picker mode.
7. **Select-all** only toggles eligible, non-already-added items (respects eligibility check).
8. **Group selector** only toggles eligible items within the group.

### FR-3: Control Bar in Picker Mode

When `picker={true}`, the control bar changes layout:

- **Approach:** Conditionally render `ItemPickerControlBar` inside `SharedItemsList` when `picker={true}`, instead of `ItemsListControlBar`. The `ItemPickerControlBar` component already has the correct layout (select-all + search + "Add (N)" in one row).
- The control bar renders regardless of `embedded` when `picker={true}` (unlike non-picker embedded mode which hides the control bar entirely).

Props wired to `ItemPickerControlBar`:

```typescript
<ItemPickerControlBar
  search={query}
  onChangeSearch={setQuery}
  searchPlaceholder={searchPlaceholder}
  onSelectAll={handleSelectAll}       // only toggles eligible items
  allSelected={allEligibleSelected}   // true when all eligible visible items are selected
  hasItems={eligibleIds.length > 0}
  onAddSelected={onAddSelected!}
  selectedCount={selectedIds.length}
  addButtonLabel={addButtonLabel}
/>
```

### FR-4: Eligibility / Locking

Eligibility is enforced per-item during rendering:

```typescript
// For each item in the list:
const eligible = !eligibilityCheck || eligibilityCheck.isEligible(item);
const alreadyAdded = addedIds?.has(item.id) ?? false;
const statusLabel = eligibilityCheck?.getStatusLabel?.(item);

// ItemCard props when ineligible:
{
  onSelectedChange: eligible && !alreadyAdded ? (next) => setItemSelected(id, next) : undefined,
  onPress: eligible && !alreadyAdded ? () => setItemSelected(id, !isSelected) : undefined,
  style: [!eligible ? { opacity: 0.5 } : null],
  headerAction: alreadyAdded
    ? <AddedBadge />          // "Added" chip/badge
    : onAddSingle && eligible
      ? <AddButton onPress={() => onAddSingle(item)} />
      : undefined,
}
```

For grouped items, the group-level `onSelectedChange` only toggles eligible items:

```typescript
const eligibleGroupIds = groupIds.filter(id => {
  const item = findItem(id);
  return item && (!eligibilityCheck || eligibilityCheck.isEligible(item))
    && !addedIds?.has(id);
});

<GroupedItemCard
  onSelectedChange={eligibleGroupIds.length > 0
    ? (next) => setGroupSelection(eligibleGroupIds, next)
    : undefined}
  selected={eligibleGroupIds.length > 0 && eligibleGroupIds.every(id => selectedIds.includes(id))}
/>
```

### FR-5: headerAction Wired to Grouped Item Children

When building the `items` array for `GroupedItemCard`, each child `ItemCardProps` must include `headerAction`:

```typescript
items={row.items.map((item) => {
  const eligible = !eligibilityCheck || eligibilityCheck.isEligible(item.item);
  const alreadyAdded = addedIds?.has(item.id) ?? false;

  return {
    // ... existing props ...
    headerAction: picker
      ? alreadyAdded
        ? <AddedBadge />
        : onAddSingle && eligible
          ? <AddButton onPress={() => onAddSingle(item.item)} />
          : undefined
      : undefined,
  };
})}
```

Since `GroupedItemCard` uses `{...item}` spread when rendering child `ItemCard`s, the `headerAction` prop flows through automatically. **No changes to `GroupedItemCard` or `ItemCard` are needed.**

### FR-6: Tabs Stay in the Parent

`SharedItemsList` remains tab-unaware. Tab handling stays in the parent component:

- `SpaceDetailContent` renders its tab bar, manages `pickerTab` state, swaps `items` prop based on active tab.
- `TransactionDetailScreen` does the same with its dynamic tabs.
- Tab change resets selection (parent calls `manager.clearSelection()`).

### FR-7: Loading / Error States in Picker Mode

When `picker={true}` and `outsideLoading` is true, show a loading indicator. When `outsideError` is set, show an error message. These replace the empty state message when applicable.

### FR-8: Select-All Respects Eligibility

When `picker={true}`, `handleSelectAll` must:
1. Compute `eligibleIds` = all visible items passing `eligibilityCheck.isEligible` and not in `addedIds`
2. If all eligible items are selected, deselect all
3. Otherwise, select all eligible items (add to existing selection, don't clear ineligible selections)

## Migration Path

### Consumer 1: SpaceDetailContent

**Before** (lines 1125-1152):
```tsx
<SharedItemPicker
  tabs={[
    { value: 'current', label: pickerTabLabel, accessibilityLabel: '...' },
    { value: 'outside', label: 'Outside', accessibilityLabel: 'Outside items tab' },
  ]}
  tabCounts={{ current: availableItems.length, outside: outsideItemsHook.items.length }}
  selectedTab={pickerTab}
  onTabChange={(next) => { setPickerTab(next); setPickerSelectedIds([]); }}
  items={activePickerItems}
  selectedIds={pickerSelectedIds}
  onSelectionChange={setPickerSelectedIds}
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

**After:**
```tsx
{/* Tab bar rendered by parent */}
<TabBar
  tabs={[
    { value: 'current', label: pickerTabLabel },
    { value: 'outside', label: 'Outside' },
  ]}
  tabCounts={{ current: availableItems.length, outside: outsideItemsHook.items.length }}
  selected={pickerTab}
  onChange={(next) => { setPickerTab(next); pickerManager.clearSelection(); }}
/>
<SharedItemsList
  embedded={true}
  picker={true}
  items={activePickerItems}
  manager={pickerManager}
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

**Note:** `pickerManager` is a `useItemsManager()` instance. The parent owns selection state via the manager, replacing the previous `pickerSelectedIds` / `setPickerSelectedIds` pattern. The `TabBar` component can be extracted from `SharedItemPicker`'s existing tab rendering or built as a simple inline component.

### Consumer 2: TransactionDetailScreen

**Before** (lines 1365-1391):
```tsx
<SharedItemPicker
  tabs={pickerTabOptions}
  tabCounts={{
    suggested: suggestedItems.length,
    ...(projectId ? { project: projectItems.length } : {}),
    outside: outsideItemsHook.items.length,
  }}
  selectedTab={pickerTab}
  onTabChange={(next) => { setPickerTab(next); setPickerSelectedIds([]); }}
  items={activePickerItems}
  selectedIds={pickerSelectedIds}
  onSelectionChange={setPickerSelectedIds}
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

**After:**
```tsx
{/* Tab bar rendered by parent */}
<TabBar
  tabs={pickerTabOptions}
  tabCounts={{
    suggested: suggestedItems.length,
    ...(projectId ? { project: projectItems.length } : {}),
    outside: outsideItemsHook.items.length,
  }}
  selected={pickerTab}
  onChange={(next) => { setPickerTab(next); pickerManager.clearSelection(); }}
/>
<SharedItemsList
  embedded={true}
  picker={true}
  items={activePickerItems}
  manager={pickerManager}
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

**Note:** This consumer does NOT use `onAddSingle` or `addedIds`, so no per-item Add buttons appear — only bulk selection. This is existing behavior preserved.

## Files to Delete After Migration

| File | Action |
|------|--------|
| `src/components/SharedItemPicker.tsx` | Delete — fully absorbed into SharedItemsList picker mode |
| `src/components/index.ts` lines 35-36 | Remove barrel exports for `SharedItemPicker` and `ItemPickerControlBar` |

`ItemPickerControlBar.tsx` is **kept** — it's now consumed by `SharedItemsList` in picker mode instead of `SharedItemPicker`.

## What NOT to Change

- **`GroupedItemCard`**: No modifications needed. It already spreads all `ItemCardProps` to child `ItemCard`s, so `headerAction` flows through if included in the items array.
- **`ItemCard`**: No modifications needed. It already renders `headerAction` in the header slot.
- **`ItemsListControlBar`**: No modifications needed (picker mode uses `ItemPickerControlBar` instead).
- **Existing standalone and embedded mode behavior**: All current SharedItemsList functionality (search, sort, filter, bookmark, status, menu, bulk actions, duplicate grouping) must continue working unchanged when `picker` is `false` or absent.

## Grouping Alignment

SharedItemPicker groups by `name.toLowerCase()` only. SharedItemsList groups by `name::sku::source` (composite key). After normalization, the picker mode uses the same composite key grouping as SharedItemsList, which is more precise and avoids incorrectly grouping items that share a name but differ in SKU/source.

## User Scenarios & Testing

### Scenario 1: Space Detail — Add Items via Picker
1. User opens a space detail screen
2. User taps "Add Existing Items" button
3. Bottom sheet opens with tab bar (current/outside) and SharedItemsList in picker mode
4. User sees items with select-all checkbox, search field, and "Add (N)" button
5. Ineligible items (already in space, linked to transaction) appear at reduced opacity and cannot be selected
6. User selects individual items via selector circle or body tap
7. User taps per-item "Add" button to quick-add a single item
8. "Added" badge appears on successfully added items
9. User selects multiple items and taps "Add (N)" to bulk-add
10. User switches tabs — selection is cleared

### Scenario 2: Transaction Detail — Add Items via Picker
1. User opens a transaction detail screen
2. User taps "Add Items" button
3. Bottom sheet opens with tab bar (suggested/project?/outside) and SharedItemsList in picker mode
4. User sees items without per-item Add buttons (this consumer uses bulk-only mode)
5. User selects items and taps "Add (N)" button
6. Items already linked to this transaction appear as ineligible

### Scenario 3: Grouped Items in Picker
1. Items sharing the same name+SKU+source appear as a grouped card
2. Tapping the collapsed group body selects all eligible items in the group
3. Expanding the group shows child items, each with their own selector and Add button
4. Ineligible children within a group are visually locked (reduced opacity, no selector)
5. Group selector circle only reflects and toggles eligible children

### Scenario 4: Existing Standalone/Embedded Mode Unchanged
1. Business inventory screen continues to show full control bar with search/sort/filter/add
2. Embedded mode on space detail continues to work without picker features
3. Bulk selection bar and bulk actions sheet continue to work

## Success Criteria

- All item picker functionality from SharedItemPicker is available via SharedItemsList with `picker={true}`
- Per-item "Add" buttons work on both ungrouped items and grouped item children
- Ineligible items are visually locked and cannot be selected or added
- "Added" badge correctly appears for already-added items
- Select-all respects eligibility (only selects eligible, non-added items)
- Group selection respects eligibility
- Existing standalone and embedded mode behavior is unchanged
- SharedItemPicker.tsx and its barrel export are removed
- Both consumers (SpaceDetailContent, TransactionDetailScreen) migrated with no functionality loss

## Assumptions

- The `TabBar` component for rendering picker tabs either already exists elsewhere in the codebase or can be trivially extracted from SharedItemPicker's existing tab rendering logic (~20 lines of JSX).
- The `useItemsManager` hook is already compatible with picker use cases (it manages selection state generically). If it needs extensions (e.g., eligibility-aware selectAll), those will be added to the hook.
- `ItemPickerControlBar` is kept as a separate file (not merged into `ItemsListControlBar`) since its layout is fundamentally different (single row with inline add button vs. multi-action toolbar).

## Dependencies

- `useItemsManager` hook (already exists, may need minor extension for eligibility-aware selectAll)
- `GroupedItemCard` and `ItemCard` (no changes needed)
- `ItemPickerControlBar` (reused as-is from picker mode)

## Scope Boundaries

**In scope:**
- Adding picker mode props to SharedItemsList
- Picker-mode rendering logic (eligibility, headerAction, body tap behavior)
- Picker control bar integration
- Migration of both consumers
- Deletion of SharedItemPicker.tsx

**Out of scope:**
- Refactoring the duplicate rendering logic between embedded map and standalone FlatList paths (pre-existing tech debt)
- Fixing the missing `budgetCategoryName` in standalone grouped items (pre-existing bug, not related to this feature)
- Any changes to GroupedItemCard or ItemCard
- Sort/filter in picker mode (picker only has search, which is existing behavior)
