# Vendor Rename Debug Logging

## Summary
Comprehensive console.log statements added to trace the complete vendor rename flow from UI interaction through Firebase sync.

## Logging Points Added

### 1. **UI Layer - Vendor Edit Dialog (settings.tsx)**

#### `handleOpenVendorEdit` (Line ~643)
```
- Logs when called with index parameter
- Logs current vendorSlots state
- Logs the specific vendor being edited
- Logs after state setters with new values
```

#### `handleSaveVendorEdit` (Line ~657)
```
- Logs when save is initiated
- Logs editingVendorIndex and editingVendorName values
- Logs if exiting early (null index)
- Logs original vendorSlots before mutation
- Logs updated vendor at the specific index
- Logs new vendorSlots array
- Logs each function call in sequence:
  * setVendorSlots
  * handleCloseVendorEdit
  * handleSaveVendorSlot
```

### 2. **Menu Interaction Layer - BottomSheetMenuList (src/components/BottomSheetMenuList.tsx)**

#### Menu Item onPress Handler (Line ~244)
```
- Logs when menu item is pressed with item label and key
- Logs before calling item.onPress?.()
- Logs after calling item.onPress?.()
- Logs when sheet closes (closeOnItemPress=true)
```

### 3. **Menu Items Generation (settings.tsx getMenuItems callback)**

#### getMenuItems for Vendor Slots (Line ~1285)
```
- Logs when getMenuItems is called with the item data
- Logs the index found for the item.id
- Logs "Index not found" if item not in vendorSlots
- Logs the vendor data at the found index
- Logs hasValue boolean and actual value
```

### 4. **Service Layer - Vendor Defaults (src/data/vendorDefaultsService.ts)**

#### `handleSaveVendorSlot` (Line ~591)
```
- Logs when called with index
- Logs if no accountId (early return)
- Logs the full array being sent to replaceVendorSlots
- Logs completion
```

#### `replaceVendorSlots` (Line ~73)
```
- Logs accountId and raw vendors array
- Logs normalized array (after padding to 10 slots)
```

#### `saveVendorDefaults` (Line ~49)
```
- Logs accountId and vendors array
- Logs if Firebase not configured (error)
- Logs before setDoc call
- Logs detailed error info if write fails (message and code)
- Logs after trackPendingWrite
- Logs completion
```

## Log Prefix
All console.log statements use the prefix **`[VENDOR_RENAME]`** for easy filtering in DevTools console.

## Expected Log Flow for Successful Rename

```
1. User taps "Rename" menu item
   [VENDOR_RENAME] BottomSheetMenuList.onPress fired for item: Rename key: edit
   [VENDOR_RENAME] Before calling item.onPress?.()

2. handleOpenVendorEdit is triggered
   [VENDOR_RENAME] handleOpenVendorEdit called with index: 2
   [VENDOR_RENAME] Current vendorSlots: [...]
   [VENDOR_RENAME] Vendor at index: { id: '...', value: 'Old Name' }
   [VENDOR_RENAME] After state setters - editingVendorIndex: 2 editingVendorName: Old Name

   [VENDOR_RENAME] After calling item.onPress?.()
   [VENDOR_RENAME] Closing sheet (closeOnItemPress=true)

3. Dialog opens, user types new name, taps Save
   [VENDOR_RENAME] handleSaveVendorEdit called
   [VENDOR_RENAME] editingVendorIndex: 2
   [VENDOR_RENAME] editingVendorName: New Name
   [VENDOR_RENAME] Original vendorSlots: [...]
   [VENDOR_RENAME] Updated vendor at index 2 to: { id: '...', value: 'New Name' }
   [VENDOR_RENAME] New vendorSlots array: [...]
   [VENDOR_RENAME] Called setVendorSlots
   [VENDOR_RENAME] Called handleCloseVendorEdit
   [VENDOR_RENAME] Called handleSaveVendorSlot

4. Save to Firebase
   [VENDOR_RENAME] handleSaveVendorSlot called with index: 2
   [VENDOR_RENAME] Calling replaceVendorSlots with: ['slot1', 'slot2', 'New Name', ...]
   [VENDOR_RENAME] replaceVendorSlots called with accountId: ... vendors: [...]
   [VENDOR_RENAME] After normalization: ['slot1', 'slot2', 'New Name', '', '', '', '', '', '', '']
   [VENDOR_RENAME] saveVendorDefaults called with accountId: ... vendors: [...]
   [VENDOR_RENAME] Calling setDoc with normalized vendors
   [VENDOR_RENAME] setDoc initiated, calling trackPendingWrite
   [VENDOR_RENAME] saveVendorDefaults complete
   [VENDOR_RENAME] replaceVendorSlots call completed
```

## Error Handling Notes

### No React Error Boundaries Found
- Searched app/_layout.tsx, app/(tabs)/_layout.tsx, app/(auth)/_layout.tsx
- No componentDidCatch or getDerivedStateFromError implementations
- Errors will propagate to console normally (not swallowed)

### Error Logging in Service Layer
- Firebase write errors are caught and logged with full error details:
  - `error.message`
  - `error.code` (Firebase error code)
- No try-catch blocks in UI layer (fire-and-forget pattern)

## Debugging Guide

1. **Tap the menu to rename a vendor**
2. **Open DevTools console** (Cmd+I or F12)
3. **Filter by "[VENDOR_RENAME]"** to see only relevant logs
4. **Watch the sequence** to identify where the flow breaks

### Common Issue Points
- Menu not opening? Check first `getMenuItems` log
- Dialog not opening? Check `handleOpenVendorEdit` logs
- Save not triggering? Check `handleSaveVendorEdit` logs
- Firebase error? Check `saveVendorDefaults` error logs

## Files Modified
1. `/Users/benjaminmackenzie/Dev/ledger_mobile/app/(tabs)/settings.tsx`
   - handleOpenVendorEdit (6 console.log statements)
   - handleSaveVendorEdit (15 console.log statements)
   - getMenuItems callback (9 console.log statements)
   - handleSaveVendorSlot (4 console.log statements)

2. `/Users/benjaminmackenzie/Dev/ledger_mobile/src/components/BottomSheetMenuList.tsx`
   - onPress handler (4 console.log statements)

3. `/Users/benjaminmackenzie/Dev/ledger_mobile/src/data/vendorDefaultsService.ts`
   - saveVendorDefaults (6 console.log statements)
   - replaceVendorSlots (4 console.log statements)

**Total: 48 console.log statements added**
