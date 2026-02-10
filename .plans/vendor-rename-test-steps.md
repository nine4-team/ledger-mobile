# Vendor Rename Debug Testing Steps

## Before Testing
1. Open DevTools console (Cmd+I on Mac or F12)
2. Filter console by typing: `[VENDOR_RENAME]` in the filter box
3. Clear previous logs

## Test Scenario: Rename an Existing Vendor

### Step 1: Open Settings
- Navigate to Settings > Presets > Vendors tab
- You should see vendor slots listed with existing names

### Step 2: Tap Menu on a Vendor
- Long-press or tap the menu icon on any vendor that has a name
- The bottom sheet menu should appear
- **Check Console:** You should see:
  ```
  [VENDOR_RENAME] getMenuItems called with item: { id: '...', name: 'Vendor Name' }
  [VENDOR_RENAME] Found index: 0 (or appropriate index)
  [VENDOR_RENAME] Vendor data at index 0: { id: '...', value: 'Vendor Name' }
  [VENDOR_RENAME] hasValue: true value: Vendor Name
  ```

### Step 3: Tap "Rename"
- Tap the "Rename" menu item
- The edit dialog should open
- **Check Console:** You should see:
  ```
  [VENDOR_RENAME] BottomSheetMenuList.onPress fired for item: Rename key: edit
  [VENDOR_RENAME] Before calling item.onPress?.()
  [VENDOR_RENAME] handleOpenVendorEdit called with index: 0
  [VENDOR_RENAME] Current vendorSlots: (array with all slots)
  [VENDOR_RENAME] Vendor at index: { id: '...', value: 'Vendor Name' }
  [VENDOR_RENAME] After state setters - editingVendorIndex: 0 editingVendorName: Vendor Name
  [VENDOR_RENAME] After calling item.onPress?.()
  [VENDOR_RENAME] Closing sheet (closeOnItemPress=true)
  ```

### Step 4: Edit the Vendor Name
- Clear the text field and type a new name (e.g., "New Vendor Name")
- Tap "Save"
- **Check Console:** You should see:
  ```
  [VENDOR_RENAME] handleSaveVendorEdit called
  [VENDOR_RENAME] editingVendorIndex: 0
  [VENDOR_RENAME] editingVendorName: New Vendor Name
  [VENDOR_RENAME] Original vendorSlots: (original array)
  [VENDOR_RENAME] Updated vendor at index 0 to: { id: '...', value: 'New Vendor Name' }
  [VENDOR_RENAME] New vendorSlots array: (updated array with new name)
  [VENDOR_RENAME] Called setVendorSlots
  [VENDOR_RENAME] Called handleCloseVendorEdit
  [VENDOR_RENAME] Called handleSaveVendorSlot
  ```

### Step 5: Verify Firebase Sync
- **Check Console:** You should see:
  ```
  [VENDOR_RENAME] handleSaveVendorSlot called with index: 0
  [VENDOR_RENAME] Calling replaceVendorSlots with: ['New Vendor Name', '', '', '', '', '', '', '', '', '']
  [VENDOR_RENAME] replaceVendorSlots called with accountId: (your account id) vendors: ['New Vendor Name', ...]
  [VENDOR_RENAME] After normalization: ['New Vendor Name', '', '', '', '', '', '', '', '', '']
  [VENDOR_RENAME] saveVendorDefaults called with accountId: (your account id) vendors: [...]
  [VENDOR_RENAME] Calling setDoc with normalized vendors
  [VENDOR_RENAME] setDoc initiated, calling trackPendingWrite
  [VENDOR_RENAME] saveVendorDefaults complete
  [VENDOR_RENAME] replaceVendorSlots call completed
  ```

### Step 6: Verify UI Update
- The dialog should close
- The vendor list should update with the new name
- The new name should be visible in the presets list

## Test Scenario 2: Set a Vendor Name (Empty Slot)

Same steps, but tap an empty vendor slot:
- Menu item should say "Set Vendor" instead of "Rename"
- Follow same flow - all logs should appear
- New name should appear in the slot

## Troubleshooting with Logs

### Issue: Menu doesn't open
- Check if `getMenuItems called` log appears
- If yes, check if index is -1 (not found)
- If index is -1, check vendorSlots array in the log

### Issue: Dialog doesn't open
- Check if `handleOpenVendorEdit called` log appears
- Check if the state setters logs show correct values
- Check if menu onPress log shows "After calling item.onPress"

### Issue: Save doesn't work
- Check if `handleSaveVendorEdit called` log appears
- Check if `Called setVendorSlots` log appears
- Check if `Called handleSaveVendorSlot` log appears
- Check Firebase error logs for any issues

### Issue: Firebase sync fails
- Look for `saveVendorDefaults failed` error log
- Check the error message and code in logs
- Error might be permissions, offline, or quota issues

## Log Search Tips

Filter console to show only:
- `[VENDOR_RENAME]` - All vendor rename logs
- `[VENDOR_RENAME] Error` - Only errors
- `[VENDOR_RENAME] Failed` - Only failures
- `[VENDOR_RENAME] getMenuItems` - Menu generation only
- `[VENDOR_RENAME] handleOpenVendorEdit` - Dialog opening only
- `[VENDOR_RENAME] handleSaveVendorEdit` - Save operation only
- `[VENDOR_RENAME] saveVendorDefaults` - Firebase operation only

## Expected Behavior

✓ Menu should open showing "Rename" or "Set Vendor"
✓ Dialog should open with current/empty name in text field
✓ Text input should be focused and keyboard visible
✓ Tapping Save should close dialog and update list
✓ All console logs should appear in sequence with no gaps
✓ No errors should appear in console

## Restoration

When debugging is complete, remove all `[VENDOR_RENAME]` console.log statements before committing.
