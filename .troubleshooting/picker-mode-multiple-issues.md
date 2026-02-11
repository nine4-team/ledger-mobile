# Issue: SharedItemsList picker mode — multiple issues after 006 consolidation

**Status:** Active
**Opened:** 2026-02-11
**Resolved:** _pending_

## Info
- **Symptom:** Five issues in the space detail "Add Existing Items" picker (SharedItemsList in picker mode):
  1. **Bulk selection not working on grouped items** — tapping the group selector/body on grouped item cards does not select items
  2. **Confusing "Linked" badge** — a "Linked" badge appears in the status badge position for items that are NOT linked to the current space
  3. **Can't scroll** — items in the add existing items view are not scrollable
  4. **Long delays on tab switch** — clicking between project and outside tabs has noticeable lag
  5. **Expand/collapse broken on grouped items** — tapping a GroupedItemCard body selects the group instead of expanding/collapsing it

- **Affected area:**
  - `src/components/SharedItemsList.tsx` (picker mode rendering)
  - `src/hooks/usePickerMode.tsx` (picker logic hook)
  - `src/components/SpaceDetailContent.tsx` (consumer)
  - `src/components/GroupedItemCard.tsx` (group selection, expand/collapse)
  - `src/hooks/useItemsManager.ts` (memoization)

- **Context:** Feature 006 consolidated `SharedItemPicker` into `SharedItemsList` with a `picker` mode. All 4 work packages were merged.

## Research

### Group Selection Flow (Issue 1)
Traced the full selection chain:
1. `getPickerGroupProps` (`usePickerMode.tsx:193-221`) returns `{ selected, onSelectedChange, onPress: undefined }`
2. These are spread onto GroupedItemCard at `SharedItemsList.tsx:1138-1145`
3. GroupedItemCard selector circle (`GroupedItemCard.tsx:184-198`) renders when `onSelectedChange || typeof selected === 'boolean'`
4. Clicking selector calls `setSelected(!isSelected)` → `onSelectedChange(next)` → `setGroupSelection(groupEligibleIds, next)`

**Two problems found:**
- **`onPress: undefined` (hardcoded)** at `usePickerMode.tsx:217`. Spec FR-2.2 says collapsed group body tap should toggle selection, but since `onPress` is undefined, body tap just expands/collapses the group.
- **Selector circle shows on fully-ineligible groups** — `selected` is always returned as a boolean (even `false` when no eligible items), so the selector circle renders. But `onSelectedChange` is `undefined` when `groupEligibleIds.length === 0`, so clicking falls through to GroupedItemCard's fallback (propagate to children), but children are also ineligible (no handlers). Net effect: selector looks clickable but does nothing.

### "Linked" Badge Flow (Issue 2)
Traced the full rendering chain:
1. `SpaceDetailContent.tsx:1222-1229`: eligibility check config
   - `isEligible: (item) => item.spaceId !== spaceId && !item.transactionId`
   - `getStatusLabel: (item) => item.transactionId ? 'Linked' : undefined`
2. `usePickerMode.tsx:167,184`: `getPickerItemProps` calls `getStatusLabel(item)` and returns `statusLabel: statusLabel || undefined`
3. `SharedItemsList.tsx:1129`: `statusLabel: pickerProps.statusLabel ?? baseCardProps.statusLabel`
4. `ItemCard.tsx:197-217`: Renders `statusLabel` as a pill badge in the header

**Result:** ANY item with a `transactionId` (even one completely unrelated to the current space) shows "Linked" badge AND has its actual status label (e.g., "Bought", "Sold") replaced. The label describes the item's global state, not its relationship to the current space.

Additionally: The `getStatusLabel` is called for ALL items (eligible or not) — it's not gated behind `!eligible`. So eligible items with a `transactionId` shouldn't exist (the `isEligible` check rejects them), but the label/status replacement path runs unconditionally.

### Scroll Issue (Issue 3)
The rendering chain has no scrollable container:
1. `SpaceDetailContent.tsx:1147-1149`: picker is inside `BottomSheet` → `View style={styles.pickerContent}`
2. `BottomSheet.tsx:96-98`: just renders `{children}` inside an `Animated.View` — no ScrollView
3. `SharedItemsList.tsx:1035-1036`: with `embedded={true}`, renders items using `View + map` (comment: "no scroll, parent handles it")
4. `pickerContent` style (`SpaceDetailContent.tsx:1328-1333`): `flex: 1, paddingHorizontal: 16` — no scrollability

**The old SharedItemPicker had its own internal FlatList for scrolling.** When it was absorbed into SharedItemsList, the picker uses `embedded={true}` which assumes the parent provides scrolling. But the BottomSheet parent doesn't.

### Tab Delay (Issue 4)
Two contributing factors:
1. **Repeated reload loop** (`SpaceDetailContent.tsx:324-327`):
   ```typescript
   useEffect(() => {
     if (!isPickingItems) return;
     void outsideItemsHook.reload();
   }, [isPickingItems, outsideItemsHook]);
   ```
   `outsideItemsHook` is a non-memoized object from `useOutsideItems`, so it's a new reference on every render. While `isPickingItems` is true, this effect re-runs every render, calling `reload()` repeatedly. Each `reload` does `Promise.all` of cache reads across all projects (`useOutsideItems.ts:54-64`).

2. **Items reprocessing** — `pickerManager = useItemsManager({ items: activePickerItems, ... })` at `SpaceDetailContent.tsx:296-302`. When `activePickerItems` changes on tab switch, the hook re-sorts/filters/groups all items.

## Experiments

### H1: `onPress: undefined` prevents group body-tap selection
- **Rationale:** Spec FR-2.2 requires collapsed group body tap to toggle selection. `getPickerGroupProps` returns `onPress: undefined` at `usePickerMode.tsx:217`.
- **Experiment:** Read GroupedItemCard.tsx `handlePress` — confirm it falls through to expand/collapse when `onPress` is undefined.
- **Result:** `GroupedItemCard.tsx:143-149`: `handlePress()` checks `if (onPress) { onPress(); return; }` then calls `setExpanded(!isExpanded)`. Confirmed: body tap expands instead of selecting.
- **Verdict:** Confirmed

### H2: Fully-ineligible groups show non-functional selector
- **Rationale:** `getPickerGroupProps` returns `selected: false` (boolean) even when `groupEligibleIds.length === 0`, causing selector circle to render. But `onSelectedChange` is `undefined`, so click is a no-op.
- **Experiment:** Check GroupedItemCard selector rendering condition and fallback behavior.
- **Result:** `GroupedItemCard.tsx:184`: renders selector when `typeof selected === 'boolean'` (always true from picker). `setSelected` at line 126-141: falls through to child propagation when `onSelectedChange` is undefined, but children in picker mode also have `onSelectedChange: undefined` for ineligible items.
- **Verdict:** Confirmed

### H3: "Linked" label replaces actual item status
- **Rationale:** `getStatusLabel` returns "Linked" for any item with `transactionId`. `usePickerMode` puts this in `statusLabel`. SharedItemsList uses `pickerProps.statusLabel ?? baseCardProps.statusLabel`.
- **Experiment:** Trace statusLabel from SpaceDetailContent → usePickerMode → SharedItemsList → ItemCard.
- **Result:** Confirmed at every step. `SpaceDetailContent.tsx:1226` returns "Linked", `usePickerMode.tsx:184` returns it as `statusLabel`, `SharedItemsList.tsx:1129` applies it with `??` fallback, `ItemCard.tsx:197-217` renders it as a pill.
- **Verdict:** Confirmed

### H4: No scrollable container for embedded picker
- **Rationale:** `embedded={true}` uses `View + map` assuming parent scrolls. BottomSheet has no ScrollView.
- **Experiment:** Trace View hierarchy from BottomSheet → pickerContent → SharedItemsList → items rendering.
- **Result:** `BottomSheet.tsx:96-98`: no ScrollView. `SpaceDetailContent.tsx:1149`: `<View style={styles.pickerContent}>` (plain View). `SharedItemsList.tsx:1054`: `<View style={styles.list}>` (plain View). No scrollable container in the chain.
- **Verdict:** Confirmed

### H5: `outsideItemsHook` dependency causes reload loop
- **Rationale:** `outsideItemsHook` is a non-memoized object, so the useEffect dependency triggers on every render.
- **Experiment:** Check `useOutsideItems` return value — is it memoized? Check effect dependency.
- **Result:** `useOutsideItems.ts:78-84` returns `{ items, loading, error, reload: loadItems }` — a new object literal on every render, NOT memoized. Effect at `SpaceDetailContent.tsx:324-327` depends on this object reference. When `isPickingItems` is true, every re-render re-triggers `reload()`.
- **Verdict:** Confirmed

## Resolution (partial)

### Issue 1: Group selection — FIXED (`usePickerMode.tsx`)
- `getPickerGroupProps` now returns `onPress` handler that toggles group selection (was `undefined`)
- Fully-ineligible groups (no eligible items) return `selected: undefined` instead of `false`, hiding the selector circle entirely
- Type signature updated: `selected` and `onPress` are now optional

### Issue 2: "Linked" badge — FIXED (`SpaceDetailContent.tsx:1222-1228`)
- Removed `if (item.transactionId) return 'Linked'` from `getStatusLabel` ✓
- Removed `!item.transactionId` from `isEligible` check ✓ — items with a transactionId are now eligible for selection

### Issue 3: Scroll — FIXED (`SharedItemsList.tsx`)
- When `picker && embedded`, items now render inside `ScrollView` instead of plain `View`
- Non-picker embedded mode still uses `View` (parent handles scroll)
- Added `pickerScroll` style (`flex: 1`) for the ScrollView

### Issue 4: Tab switch delay — UNRESOLVED (`useItemsManager.ts`, `SpaceDetailContent.tsx:324-328`)
- Changed useEffect dependency from `outsideItemsHook` (new object every render) to `outsideItemsHook.reload` (stable `useCallback` ref) ✓
- Wrapped `useItemsManager` return value in `useMemo` to stabilize object reference ✓
- **Delay still persists per user testing.** The `useMemo` fix prevents unnecessary re-renders from unrelated state updates, but does not help the legitimate recomputation when `activePickerItems` changes on tab switch (sort + filter + grouping chain runs synchronously). Root cause may be deeper — needs further diagnosis.

### Issue 5: Expand/collapse broken on grouped items — NEW
- **Symptom:** Tapping GroupedItemCard body selects the group instead of expanding/collapsing it
- **Likely cause:** The Issue 1 fix made `getPickerGroupProps` return an `onPress` handler that toggles selection. `GroupedItemCard.handlePress` checks `if (onPress) { onPress(); return; }` before falling through to expand/collapse (`setExpanded(!isExpanded)`). Since `onPress` is now defined (for selection), the expand/collapse path is never reached.
- **Conflict:** Issue 1 wanted body-tap to select; but users also need a way to expand/collapse groups. The selection-on-body-tap behavior from the Issue 1 fix conflicts with expand/collapse. Needs a UX decision — e.g., use selector circle for selection and body tap for expand/collapse, or provide a separate expand affordance.
