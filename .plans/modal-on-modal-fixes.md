# Modal-on-Modal Conflict Fixes

## Context

After fixing a modal-on-modal iOS bug in `BottomSheetMenuList` (the `pendingActionRef` + `requestAnimationFrame` pattern), an audit found two remaining issues:
1. `AnchoredMenuList` has the same unprotected pattern (latent bug)
2. `SpaceDetailContent` has a now-redundant `setTimeout(300)` workaround

## Changes

### 1. Port `pendingActionRef` deferral to AnchoredMenuList

**File:** `src/components/AnchoredMenuList.tsx`

Add the same `pendingActionRef` + `useEffect` pattern from `BottomSheetMenuList`:
- Add `useEffect, useRef` to React imports (line 1)
- Add `pendingActionRef` and `prevVisibleRef` refs
- Add `useEffect` that watches `visible` transition `true → false`, then executes pending action via `requestAnimationFrame`
- **Subaction press** (line 213-220): store `sub.onPress` in `pendingActionRef`, call `onRequestClose()` (remove direct `sub.onPress()` call)
- **Item press** (line 269-271): store `item.onPress` in `pendingActionRef`, call `onRequestClose()` (remove direct `item.onPress?.()` call)

### 2. Remove redundant setTimeout in SpaceDetailContent

**File:** `src/components/SpaceDetailContent.tsx`

Simplify the `add-existing` menu item's `onPress` (lines 528-536):

```typescript
// Before
onPress: () => {
  setAddMenuVisible(false);
  setTimeout(() => {
    setIsPickingItems(true);
    setPickerTab('current');
    setPickerSelectedIds([]);
  }, 300);
},

// After
onPress: () => {
  setIsPickingItems(true);
  setPickerTab('current');
  setPickerSelectedIds([]);
},
```

The `setAddMenuVisible(false)` is redundant (BottomSheetMenuList calls `onRequestClose` before executing the deferred action). The `setTimeout` is redundant (the `pendingActionRef` mechanism already waits for modal dismissal).

## Verification

1. Open a space detail screen, tap "+" to open the add menu, tap "Add existing item" — the item picker should open cleanly without delay or flicker
2. Test any `AnchoredMenuList` consumer whose menu item opens a modal (currently none do, but the fix prevents future issues)
3. Run `npx tsc --noEmit` to verify no type errors introduced
