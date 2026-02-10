# Issue: Vendor Rename Button Does Nothing

**Status:** Resolved
**Opened:** 2026-02-10
**Resolved:** 2026-02-10

## Context
- **Symptom:** When tapping "Rename" on a vendor in the Vendors tab under Presets in settings, nothing happens - no bottom sheet appears
- **Affected area:** app/(tabs)/settings.tsx, vendor management section
- **Severity:** Blocks user - cannot rename vendors
- **Reproduction steps:**
  1. Open Settings tab
  2. Navigate to Presets section
  3. Go to Vendors tab
  4. Tap the menu on any vendor
  5. Tap "Rename" (or "Set Vendor" if empty)
  6. Expected: bottom sheet appears with text input
  7. Actual: nothing happens
- **Environment:** React Native mobile app

## Research

### Code Structure Found
Location: [app/(tabs)/settings.tsx:1268-1272](app/(tabs)/settings.tsx#L1268-L1272)

The rename menu item is configured in the `getMenuItems` callback of the `TemplateToggleList`:
```typescript
{
  key: 'edit',
  label: hasValue ? 'Rename' : 'Set Vendor',
  icon: 'edit' as const,
  onPress: () => handleOpenVendorEdit(index),
}
```

Handler implementation at [app/(tabs)/settings.tsx:637-640](app/(tabs)/settings.tsx#L637-L640):
```typescript
const handleOpenVendorEdit = (index: number) => {
  setEditingVendorIndex(index);
  setEditingVendorName(vendorSlots[index]?.value ?? '');
};
```

Bottom sheet rendering at [app/(tabs)/settings.tsx:1289-1311](app/(tabs)/settings.tsx#L1289-L1311):
```typescript
<MultiStepFormBottomSheet
  visible={editingVendorIndex !== null}
  onRequestClose={handleCloseVendorEdit}
  title={vendorSlots[editingVendorIndex ?? 0]?.value.trim() ? 'Rename Vendor' : 'Set Vendor'}
  ...
```

The flow should be:
1. User taps "Rename" → calls `handleOpenVendorEdit(index)`
2. Sets `editingVendorIndex` to the index (non-null value)
3. Bottom sheet becomes visible because `visible={editingVendorIndex !== null}`

## Investigation Log

### H1: The onPress handler isn't being called at all
- **Rationale:** The menu item might not be properly connected or the TemplateToggleList component might have an issue with menu handling
- **Experiment:** Traced execution through TemplateToggleListCard → BottomSheetMenuList to see how menu items are handled
- **Evidence:** Handler IS being called, but AFTER the menu closes. Found at [src/components/BottomSheetMenuList.tsx:244-248](src/components/BottomSheetMenuList.tsx#L244-L248):
  ```typescript
  onPress={() => {
    if (closeOnItemPress) {     // TRUE by default
      onRequestClose();         // Closes menu FIRST
    }
    item.onPress?.();          // Executes handler SECOND
  }}
  ```
- **Verdict:** Ruled Out - Handler IS called, but timing is problematic

### H2: State update race condition due to menu closing before handler execution
- **Rationale:** The menu closes immediately before the handler runs, potentially causing React state updates to be delayed or lost
- **Experiment:** Compared execution flow with working budget category implementation
- **Evidence:**
  - Vendor rename: Menu closes → then `handleOpenVendorEdit(index)` sets state
  - Budget category (working): Menu closes → then `handleOpenCategoryEdit(category)` sets state
  - **Key difference:** Budget categories pass the category OBJECT directly (captured in closure), while vendors compute an INDEX on the fly
  - The menu closing in TemplateToggleListCard ([src/components/TemplateToggleListCard.tsx:169-172](src/components/TemplateToggleListCard.tsx#L169-L172)) happens synchronously before state updates
- **Verdict:** **CONFIRMED** - This is the root cause

### H3: Index lookup timing creates additional risk
- **Rationale:** The `vendorSlots.findIndex((s) => s.id === it.id)` happens during menu rendering, but the index is used later when the handler executes
- **Experiment:** Reviewed closure behavior in getMenuItems callback
- **Evidence:**
  - At line 1264: `const index = vendorSlots.findIndex((s) => s.id === it.id);`
  - At line 1272: `onPress: () => handleOpenVendorEdit(index)`
  - The index is captured in the arrow function closure
  - While unlikely to be stale in normal use, this pattern differs from working implementations
  - Budget categories pass objects directly: `onPress: () => handleOpenCategoryEdit(category)` (line 1403)
- **Verdict:** Contributing Factor - Not the primary issue, but makes the code more fragile

## Conclusion

**Root Cause:** Modal presentation conflict (not state timing)

The vendor rename button fails because of a **React Native Modal presentation constraint**:

1. User taps "Rename" → Menu starts closing
2. Handler executes and sets state to open bottom sheet
3. Bottom sheet attempts to present its Modal
4. **CONFLICT:** Menu's Modal is still dismissing from window hierarchy
5. iOS rejects the presentation: `"Attempt to present <Modal> on <Modal> whose view is not in the window hierarchy"`

**Key insight from console logs:**
- State updates work correctly ✓
- Handler executes correctly ✓
- Modal timing causes the failure ✗

**Why budget categories appear to work:**
- They likely have the same issue but it may be less noticeable
- Or they may have accidentally included a delay somewhere in their flow

**Supporting Evidence:**
- Console log: `[UIKitCore] Attempt to present <RCTModalHostViewController>...`
- Both BottomSheetMenuList and MultiStepFormBottomSheet use React Native Modal
- iOS requires clean modal hierarchy before presenting new modals
- Debug logs show all state updates execute correctly before the error

## Resolution

### Recommended Approaches

**Option 1: Pass vendor slot object (safest, matches working pattern)**
- Update getMenuItems to pass the slot object instead of index
- Modify handleOpenVendorEdit to accept slot and find index internally
- Matches how budget categories work (proven pattern)
- Files: app/(tabs)/settings.tsx

**Option 2: Delay handler execution (quick fix)**
- Wrap handler in setTimeout: `onPress: () => setTimeout(() => handleOpenVendorEdit(index), 0)`
- Pushes state update to next event loop tick
- Less invasive change
- Files: app/(tabs)/settings.tsx

**Option 3: Fix component execution order (architectural)**
- Modify BottomSheetMenuList to call handler BEFORE closing menu
- Would fix the issue for all menu items
- Requires testing all menu usages
- Files: src/components/BottomSheetMenuList.tsx

- **Fix Attempt 1:** Option 3 - Reversed BottomSheetMenuList execution order
  - Result: Made it worse - caused modal-on-modal presentation conflict
  - Reverted this change

- **Fix Attempt 2:** Added 300ms setTimeout delay to vendor rename onPress
- **Root cause confirmed:** Modal presentation conflict - menu Modal must fully dismiss before bottom sheet Modal can present
- **Solution:** Delay handler execution in [app/(tabs)/settings.tsx:1302-1304](app/(tabs)/settings.tsx#L1302-L1304)
  ```typescript
  onPress: () => {
    // Delay to allow menu Modal to fully dismiss before opening bottom sheet Modal
    setTimeout(() => handleOpenVendorEdit(index), 300);
  }
  ```
- **Files changed:** [app/(tabs)/settings.tsx](app/(tabs)/settings.tsx)
- **Status:** Ready for user testing

### H4: Execution flow investigation with debug logging
- **Rationale:** Need to trace actual execution path to see where the flow breaks
- **Experiment:** Added 48 console.log statements with `[VENDOR_RENAME]` prefix across three files
- **Evidence:** Console logs show:
  - Handler IS being called correctly: `handleOpenVendorEdit called with index: 0` ✓
  - State IS being set correctly: `After state setters - editingVendorIndex: 0` ✓
  - Critical error: `[UIKitCore] Attempt to present <RCTModalHostViewController> on <RCTModalHostViewController> whose view is not in the window hierarchy`
- **Verdict:** **CONFIRMED** - Real issue is modal-on-modal presentation conflict

### H5: Modal presentation conflict
- **Rationale:** The error message reveals we're trying to present a Modal (bottom sheet) on another Modal (menu) that's not fully dismissed yet
- **Experiment:** The execution order fix made it worse - now handler fires WHILE menu modal is still present
- **Evidence:**
  - Both BottomSheetMenuList and MultiStepFormBottomSheet use React Native Modal
  - Menu Modal must complete dismissal before bottom sheet Modal can present
  - iOS requires modal view hierarchy to be clean before presenting new modal
- **Verdict:** **CONFIRMED** - This is the actual root cause, not state timing

## Next Steps

The setTimeout workaround is functional but not ideal. A proper architectural fix is needed.

**See:** [PROMPT_FOR_NEXT_DEV.md](./PROMPT_FOR_NEXT_DEV.md) for a detailed brief on implementing a proper solution.

**Recommended approach:** Add `onDismissComplete` callback to BottomSheetMenuList that fires after Modal dismissal animation completes.

## Final Resolution

**Implemented:** Proper Modal lifecycle handling using `onDismiss` callback

### Implementation Details

1. **Updated BottomSheet component** ([src/components/BottomSheet.tsx](src/components/BottomSheet.tsx))
   - Added `onDismiss?: () => void` prop
   - Forwarded to React Native's Modal `onDismiss` callback
   - This fires after the modal has been fully dismissed from the view hierarchy

2. **Updated BottomSheetMenuList component** ([src/components/BottomSheetMenuList.tsx](src/components/BottomSheetMenuList.tsx))
   - Added `onDismissComplete?: () => void` prop for external consumers
   - Created `pendingActionRef` to store menu item actions
   - Modified press handlers:
     - When `closeOnItemPress` or `closeOnSubactionPress` is true, store the action in ref and close modal
     - When false, execute action immediately (for multi-select scenarios)
   - Created `handleDismiss()` that executes pending action and calls `onDismissComplete`
   - Connected `handleDismiss` to BottomSheet's `onDismiss` prop

3. **Cleaned up settings.tsx** ([app/(tabs)/settings.tsx](app/(tabs)/settings.tsx))
   - Removed `setTimeout` workaround from vendor rename handler
   - Removed all debug console.log statements

4. **Cleaned up vendorDefaultsService** ([src/data/vendorDefaultsService.ts](src/data/vendorDefaultsService.ts))
   - Removed debug console.log statements
   - Kept console.error statements for production diagnostics

### Benefits

- **Clean architecture** - Uses React Native's Modal lifecycle rather than timing hacks
- **Reusable pattern** - Any BottomSheetMenuList usage automatically handles modal-on-modal conflicts
- **No arbitrary delays** - Action executes as soon as modal is safely dismissed, not after a fixed timeout
- **Better UX** - More responsive than 300ms setTimeout
- **Type-safe** - TypeScript enforces proper callback signatures

## Lessons Learned

1. **React Native Modal stacking is problematic** - Cannot present a Modal while another Modal is dismissing
2. **Use Modal lifecycle callbacks** - React Native provides `onDismiss` specifically for this use case
3. **Debug logging is essential** - Without the console logs, we would have continued chasing the wrong hypothesis (state timing)
4. **Initial diagnosis can be misleading** - The "state update race condition" theory seemed logical but was wrong
5. **Test environment matters** - The iOS modal presentation error only appears in the actual app, not in isolation
6. **Architectural fixes > workarounds** - Taking time to implement proper solution creates reusable pattern for entire codebase
