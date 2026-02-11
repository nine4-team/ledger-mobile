# Fix SharedItemsList Embedded Mode Regressions

## Context

The recent 005-detail-screen-polish feature (WP01-WP04) refactored transaction detail and space detail screens to use `SharedItemsList` in embedded mode instead of the old `ItemsSection` component and direct SectionList item rendering. This introduced four regressions:

1. **No gap between item cards** - Cards are touching with 0px spacing
2. **Bulk actions bar not sticking to screen bottom** - Bar is below the fold, not sticky
3. **Add button lost** - Previously always-visible dual-purpose button is gone during selection
4. **Select-all only selects, never deselects** - Toggle behavior missing

All four issues share a root cause: nesting SharedItemsList (which contains its own FlatList and absolutely-positioned BulkSelectionBar) inside a parent SectionList.

---

## Fix 1: Restore 10px gap between item cards

**Root cause**: Old code put individual items in the SectionList data array, with `ItemSeparatorComponent` providing `height: 10` gaps. New code puts a single `SharedItemsList` (with its own FlatList) as one SectionList item. The nested FlatList's `gap: 10` doesn't render correctly inside a VirtualizedList parent.

**Fix in `src/components/SharedItemsList.tsx`**:
- In embedded mode, replace the `<FlatList>` with a `<View style={{ gap: 10 }}>` + `.map()` to render items
- This matches what the old `ItemsSection` did (line 128-148 of `ItemsSection.tsx`: `styles.list: { gap: 10 }`)
- The parent SectionList handles scrolling; no inner scroll view needed

---

## Fix 2: Make bulk actions bar stick to screen bottom

**Root cause**: `BulkSelectionBar` uses `position: 'absolute', bottom: 0` relative to SharedItemsList's container. Since that container is a SectionList item, the bar scrolls with content instead of sticking to the viewport bottom.

**Fix**:
- **`src/components/SharedItemsList.tsx`**: In embedded mode, do NOT render `BulkSelectionBar`. The parent screen handles it.
- **`app/transactions/[id]/index.tsx`**: Render `BulkSelectionBar` as a sibling to `SectionList` (outside scrollable content), wired to `itemsManager`:
  - `selectedCount={itemsManager.selectionCount}`
  - `onClearSelection={itemsManager.clearSelection}`
  - `onBulkActionsPress` → opens bulk actions BottomSheet
- **`src/components/SpaceDetailContent.tsx`**: Same pattern — render BulkSelectionBar outside the SectionList

The bulk actions BottomSheet can remain inside SharedItemsList (it uses `Modal` internally, works regardless of nesting).

---

## Fix 3: Restore always-visible add button

**Root cause**: Old code (commit 711b362) had a dual-purpose "Add" button in the section header:
```tsx
// OLD - always present, changes behavior based on selection
onAdd={itemsManager.hasSelection ? () => setBulkMenuVisible(true) : () => setAddMenuVisible(true)}
```
New code hides the button during selection:
```tsx
// NEW - disappears when items selected
onAdd={!itemsManager.hasSelection ? () => setAddMenuVisible(true) : undefined}
```

**Fix in `app/transactions/[id]/index.tsx`** (section header, ~line 1035):
- Restore dual-purpose: always provide `onAdd`
- No selection → opens add menu (create new / add existing)
- With selection → opens bulk actions BottomSheet
- Same fix in `src/components/SpaceDetailContent.tsx` (~line 571)

---

## Fix 4: Make select-all button toggle (select/deselect)

**Root cause**: The section header's select-all button calls `itemsManager.selectAll` directly, which always selects. SharedItemsList's standalone mode has proper toggle logic in `handleSelectAll` (line 772-782) that checks if all are selected and clears if so.

**Fix in `app/transactions/[id]/index.tsx`** (section header, ~line 1038):
- Replace `onPress={itemsManager.selectAll}` with toggle logic:
  ```tsx
  onPress={() => {
    if (itemsManager.allSelected) {
      itemsManager.clearSelection();
    } else {
      itemsManager.selectAll();
    }
  }}
  ```
- Same fix in `src/components/SpaceDetailContent.tsx` (~line 707)
- Note: The adapter's `selectAll` in transaction detail (line 1169-1178) already has toggle logic, but it's not called by the section header — the section header calls `itemsManager.selectAll` directly

---

## Files to modify

| File | Changes |
|------|---------|
| `src/components/SharedItemsList.tsx` | Embedded mode: View+map instead of FlatList; skip BulkSelectionBar |
| `app/transactions/[id]/index.tsx` | Screen-level BulkSelectionBar; fix onAdd; fix select-all toggle |
| `src/components/SpaceDetailContent.tsx` | Screen-level BulkSelectionBar; fix onAdd; fix select-all toggle |

## Existing code to reuse

- `ItemsSection.tsx` lines 128-148: Reference for View+map pattern with `gap: 10`
- `SharedItemsList.tsx` lines 772-782: `handleSelectAll` toggle logic
- `BulkSelectionBar.tsx`: Already extracted as reusable component, just needs repositioning
- Old transaction detail (commit 711b362): Reference for dual-purpose Add button pattern

## Verification

1. **Gap**: Open transaction detail with items → cards should have 10px spacing
2. **Sticky bar**: Select items → BulkSelectionBar should appear at screen bottom, visible without scrolling
3. **Add button**: With items selected, add button still visible in toolbar. Tap opens bulk actions. Deselect → tap opens add menu.
4. **Select-all toggle**: Tap select-all → all items selected. Tap again → all items deselected.
5. **Space detail**: Repeat checks 1-4 in space detail screen
6. **Standalone mode**: Project items tab (screen-two) still works correctly (no changes to standalone mode)
