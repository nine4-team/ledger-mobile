# Grouped Item Selection Normalization

## Problem Statement

Grouped item cards cannot be selected in the "Add Existing Items" picker for spaces. More broadly, there are **two separate components** rendering item lists with grouping and selection — `SharedItemsList` and `SharedItemPicker` — with divergent behavior.

## Audit Findings

### Two Components, Same Job

| Feature | SharedItemsList | SharedItemPicker |
|---------|----------------|-----------------|
| Selection state | `useItemsManager` or internal `selectedIds` | Parent-controlled `selectedIds` + `onSelectionChange` |
| Group selection | `setGroupSelection(ids, bool)` via manager | `handleGroupToggle(ids, bool)` inline |
| Bulk actions | BulkSelectionBar + BottomSheet with configurable actions | "Add Selected" button in control bar |
| Search/sort/filter | Full control bar (`ItemsListControlBar`) | Search only (`ItemPickerControlBar`) |
| Individual add button | No (uses `onPress` for navigation) | Yes (`headerAction` with Add button) — **but only on ungrouped items** |
| Grouping logic | Configurable via `groupBy` prop | Groups by `name.toLowerCase()` (hardcoded) |
| Eligibility checks | None (all items are interactive) | `isEligible` / `getStatusLabel` / `isAlreadyInTarget` |

### Selection Behavior Differences

#### SharedItemsList (standalone FlatList mode, lines 1136-1237)
- **Group header selector**: Shows when `onSelectedChange` is provided; toggles all items via `setGroupSelection`
- **Child items (expanded)**: Each has `onSelectedChange`, `onPress` (navigation), `onStatusPress`, `onBookmarkPress`, `menuItems`
- **Body tap**: Navigates to item detail

#### SharedItemPicker (lines 340-391)
- **Group header selector**: Shows; toggles only eligible items via `handleGroupToggle`
- **Child items (expanded)**: Have `onSelectedChange` and `onPress` (both toggle selection) — no bookmark, status, menu
- **Body tap (collapsed group)**: Expands/collapses the group — **does NOT toggle selection** (unlike individual items where body tap = select)
- **Missing**: `headerAction` (Add button) not passed to grouped item children — only individual items get it

### Root Cause of "Can't Select" Bug

The specific bug: when items in the picker share the same name and get grouped, the grouped card's **collapsed body tap expands instead of selecting**. Meanwhile, individual (ungrouped) items toggle selection on body tap. This inconsistency is confusing — the user expects tapping a grouped card to select it, like it works for individual cards.

Additionally, grouped item children in the picker **don't have the individual "Add" button** (`headerAction`) that ungrouped items do, making it impossible to quick-add a single item from within a group.

### Where SharedItemPicker Is Used

| Screen | Component | Config |
|--------|-----------|--------|
| Space detail → "Add Existing Items" | `SpaceDetailContent` line 1127 | 2 tabs (current/outside), eligibility by spaceId/transactionId |
| Transaction detail → "Add Items" | Likely similar pattern (need to verify) | — |

### Where SharedItemsList Is Used

- **Standalone mode**: Main items list screens (business inventory, project items)
- **Embedded mode**: Space detail items section, transaction detail items section

## Proposed Fix

### Approach: Extend SharedItemsList with Picker Mode

Rather than maintaining two components, add a `picker` mode to `SharedItemsList` that enables picker-specific features. This ensures all selection logic (individual, group, bulk) flows through the same code path.

### Step 1: Add Picker Props to SharedItemsList

```typescript
// New optional props on SharedItemsList
type SharedItemsListProps = {
  // ... existing props ...

  /** Picker mode: items are selectable, body tap toggles selection instead of navigating */
  picker?: boolean;

  /** Eligibility check for picker mode */
  eligibilityCheck?: {
    isEligible: (item: ScopedItem) => boolean;
    getStatusLabel?: (item: ScopedItem) => string | undefined;
  };

  /** Callback for individual item quick-add (renders "Add" button per item) */
  onAddSingle?: (item: ScopedItem) => void;

  /** Set of IDs already added (shows "Added" badge) */
  addedIds?: Set<string>;
};
```

### Step 2: Modify Rendering Behavior in Picker Mode

When `picker={true}`:
1. **Body tap** on both individual and grouped items toggles selection (not navigation)
2. **Grouped items (collapsed)**: Selector circle selects group; body tap ALSO selects group (consistent with individual items)
3. **`headerAction`** with Add button renders on ALL items (grouped children included)
4. **Locked items** (ineligible): `onSelectedChange` undefined, `onPress` undefined, reduced opacity
5. **No bookmark/status/menu** actions rendered (picker context doesn't need them)

### Step 3: Add Tabs Support (Optional/Later)

The picker needs tabs (e.g., "In Project" / "Outside"). Two approaches:
- **Option A**: Lift tabs into the parent (SpaceDetailContent) and swap `items` prop — SharedItemsList stays tab-unaware
- **Option B**: Add a `tabs` prop to SharedItemsList

**Recommendation**: Option A — keep SharedItemsList focused on the list. Tabs belong to the parent layout.

### Step 4: Replace SharedItemPicker Usage

In `SpaceDetailContent`, replace:
```typescript
<SharedItemPicker
  tabs={...}
  items={activePickerItems}
  selectedIds={pickerSelectedIds}
  onSelectionChange={setPickerSelectedIds}
  ...
/>
```

With tabs in the parent + SharedItemsList:
```typescript
{/* Tab bar rendered directly */}
<TabBar tabs={...} selected={pickerTab} onChange={setPickerTab} />
<SharedItemsList
  embedded={true}
  picker={true}
  items={activePickerItems}
  manager={pickerManager}
  eligibilityCheck={...}
  onAddSingle={handleAddSingleItem}
  addedIds={spaceItemIds}
  bulkActions={[{ id: 'add', label: 'Add Selected', onPress: handleAddSelectedItems }]}
/>
```

### Step 5: Deprecate SharedItemPicker

Once all usages are migrated, remove `SharedItemPicker` and `ItemPickerControlBar`.

## Quick Fix (If Normalization Is Deferred)

If the full normalization is too large for now, fix the immediate bugs in SharedItemPicker:

1. **Pass `headerAction` to grouped item children** — add the "Add" button to each child in the group map (SharedItemPicker line 352-380)
2. **Add `onPress` to GroupedItemCard** in picker context — make collapsed group body tap toggle group selection instead of just expanding

```typescript
// SharedItemPicker ~line 342
<GroupedItemCard
  ...
  onPress={groupEligibleIds.length > 0 ? () => {
    handleGroupToggle(groupEligibleIds, !groupAllSelected);
  } : undefined}
  ...
/>
```

## Files Affected

### Normalization (full approach)
- `src/components/SharedItemsList.tsx` — add picker mode props and rendering
- `src/components/SpaceDetailContent.tsx` — replace SharedItemPicker with SharedItemsList
- `src/components/SharedItemPicker.tsx` — deprecate/delete
- `src/components/ItemPickerControlBar.tsx` — deprecate/delete (merge into ItemsListControlBar if needed)

### Quick fix (minimal)
- `src/components/SharedItemPicker.tsx` — add `headerAction` to grouped children, add `onPress` to GroupedItemCard

## Recommendation

**Go with the quick fix first**, then schedule normalization. The quick fix is 2 small changes in one file. The full normalization touches 4+ files and needs thorough testing across all list screens.
