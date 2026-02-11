# Modal-on-Modal Conflict Audit Report

**Date:** 2026-02-10
**Context:** After fixing a bug in `BottomSheetMenuList` where tapping a menu item that opens another modal silently failed on iOS ("Attempt to present `<Modal>` on `<Modal>` whose view is not in the window hierarchy").

---

## How the Fix Works (Reference)

In `src/components/BottomSheetMenuList.tsx:61-74`:
- When `closeOnItemPress`/`closeOnSubactionPress` is `true` (the **default**), the item's `onPress` is stored in `pendingActionRef` and `onRequestClose()` is called
- A `useEffect` watches for `visible` transitioning `true → false`, then executes the stored action via `requestAnimationFrame`
- This guarantees the new modal only opens after the menu modal has fully torn down

---

## Findings Requiring Attention

### 1. AnchoredMenuList — Immediate Execution (UNPROTECTED)

**File:** `src/components/AnchoredMenuList.tsx:218-220, 270-271`

```typescript
// Subaction press (line 218-219)
onRequestClose();
sub.onPress();     // ← executes IMMEDIATELY, no deferral

// Item press (line 270-271)
onRequestClose();
item.onPress?.();  // ← executes IMMEDIATELY, no deferral
```

**Pattern:** Calls `onRequestClose()` then fires the action synchronously — the exact same bug pattern that was fixed in `BottomSheetMenuList`. Uses React Native `<Modal>` directly via `AnchoredMenu.tsx`.

**Risk:** Medium. Any consumer whose menu item opens a modal/sheet will hit the conflict. Currently no consumers appear to open modals from AnchoredMenuList items, but this is a latent bug waiting to happen.

**Recommendation:** Port the `pendingActionRef` + `requestAnimationFrame` pattern from BottomSheetMenuList.

---

### 2. SpaceDetailContent — setTimeout Workaround (PRE-FIX WORKAROUND)

**File:** `src/components/SpaceDetailContent.tsx:558-566`

```typescript
{
  key: 'add-existing',
  label: 'Add existing item',
  onPress: () => {
    setAddMenuVisible(false);
    setTimeout(() => {          // ← 300ms hardcoded delay
      setIsPickingItems(true);
      setPickerTab('current');
      setPickerSelectedIds([]);
    }, 300);
  },
}
```

**Pattern:** This menu item is passed to a `BottomSheetMenuList` (line 912), which already uses the `pendingActionRef` deferral by default. So the execution chain is now:
1. `pendingActionRef` stores the onPress
2. After modal dismisses → `requestAnimationFrame` fires the stored action
3. The stored action calls `setAddMenuVisible(false)` (redundant) + `setTimeout(300)`
4. 300ms later, the picker opens

**Risk:** Low (it works, just with unnecessary double-delay). The `setTimeout` was the pre-fix workaround for this exact problem. Now that `BottomSheetMenuList` handles timing natively, the `setTimeout` is redundant.

**Recommendation:** Remove the `setTimeout` wrapper and the redundant `setAddMenuVisible(false)`. The deferred mechanism already ensures the menu is dismissed before the action fires:

```typescript
onPress: () => {
  setIsPickingItems(true);
  setPickerTab('current');
  setPickerSelectedIds([]);
},
```

---

## Findings That Are Safe

### 3. FilterMenu — closeOnItemPress={false} / closeOnSubactionPress={false} (INTENTIONAL)

**File:** `src/components/FilterMenu.tsx:19-20`

```typescript
<BottomSheetMenuList
  closeOnSubactionPress={false}
  closeOnItemPress={false}
  ...
/>
```

This is the **only** consumer that disables close-on-press. It's intentional — FilterMenu is a multi-select filter picker where users toggle options without the sheet closing. The `onPress` handlers just toggle filter state; they never open modals. **SAFE.**

### 4. ProjectShell Menu Items (PROTECTED)

**File:** `src/screens/ProjectShell.tsx:270-297`

Menu items contain `setMenuVisible(false); router.push(...)` in their `onPress` handlers, but they're passed to `BottomSheetMenuList` with default `closeOnItemPress=true`. The entire `onPress` is deferred by the `pendingActionRef` mechanism — navigation only happens after modal dismissal. The inline `setMenuVisible(false)` is redundant but harmless. **PROTECTED.**

### 5. TransactionAttachmentPreview Menu Items (PROTECTED)

**File:** `src/components/TransactionAttachmentPreview.tsx:112-170`

Menu items call actions then `closeMenu()`. Passed to `BottomSheetMenuList` with default settings, so everything is deferred. **PROTECTED.**

### 6. All Other BottomSheetMenuList Consumers (PROTECTED)

All remaining consumers (ItemCard, ExpandableCard, TransactionCard, ThumbnailGrid, TemplateToggleListCard, TopHeader, SharedItemsList, SharedTransactionsList, MediaGallerySection, etc.) use `BottomSheetMenuList` with default `closeOnItemPress=true` / `closeOnSubactionPress=true`. **All protected by the deferred mechanism.**

### 7. Direct `<Modal>` Usage (NO CONFLICT)

Four files use React Native `<Modal>` directly:

| File | Purpose | Close-Then-Open? |
|------|---------|-----------------|
| `src/components/AnchoredMenu.tsx` | Low-level menu wrapper | No |
| `src/components/InfoButton.tsx` | Self-contained info dialog | No |
| `src/components/ImageGallery.tsx` | Full-screen image viewer | No |
| `src/components/BottomSheet.tsx` | Sheet wrapper (has `onDismiss` plumbing) | No |

None have close-then-open patterns. **SAFE.**

---

## Summary

| Finding | Location | Status | Action Needed |
|---------|----------|--------|---------------|
| AnchoredMenuList immediate execution | `AnchoredMenuList.tsx:218-220, 270-271` | **Unprotected** | Port `pendingActionRef` pattern |
| SpaceDetailContent setTimeout workaround | `SpaceDetailContent.tsx:558-566` | Redundant | Remove `setTimeout`, simplify onPress |
| FilterMenu close-on-press disabled | `FilterMenu.tsx:19-20` | Intentional | None |
| All other BottomSheetMenuList consumers | Various | Protected | None |
| Direct Modal usage (4 files) | Various | Safe | None |
