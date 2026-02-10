# Vendor Rename Debug Logging - Complete Documentation

## Quick Start

1. **Reload the app** to load the new console.log statements
2. **Open DevTools Console** (Cmd+I on Mac, F12 on others)
3. **Filter by:** `[VENDOR_RENAME]`
4. **Reproduce the issue:** Try to rename a vendor
5. **Check the logs** to trace where it breaks

---

## Documents in This Plan

### 1. **CONSOLE_LOG_SUMMARY.txt** (START HERE)
   - Quick overview of all 48 console.log statements
   - File-by-file breakdown
   - Line numbers for each logging point
   - Error handling findings
   - Cleanup instructions

### 2. **vendor-rename-debug-logging.md**
   - Detailed documentation of each logging point
   - Expected log flow for successful rename
   - Logging prefix and filtering info
   - Common issue points and what logs to check

### 3. **vendor-rename-test-steps.md**
   - Step-by-step testing procedure
   - What logs to expect at each step
   - Troubleshooting guide with console filters
   - Test scenarios (rename existing, set new)

### 4. **LOG_FLOW_DIAGRAM.txt**
   - Visual ASCII flow diagram of complete execution
   - Layer breakdown (UI, Component, Service)
   - Error paths and debugging checklist
   - Shows exactly what logs appear at each step

---

## Files Modified

All debug logs are in these 3 files:

```
app/(tabs)/settings.tsx
  ✓ handleOpenVendorEdit (line 643) - 6 logs
  ✓ handleSaveVendorEdit (line 657) - 15 logs
  ✓ getMenuItems callback (line 1285) - 9 logs
  ✓ handleSaveVendorSlot (line 591) - 4 logs

src/components/BottomSheetMenuList.tsx
  ✓ onPress handler (line 244) - 4 logs

src/data/vendorDefaultsService.ts
  ✓ replaceVendorSlots (line 73) - 4 logs
  ✓ saveVendorDefaults (line 49) - 6 logs
```

**Total: 48 console.log statements, all prefixed with `[VENDOR_RENAME]`**

---

## How to Use the Logs

### Filter in DevTools
```
Type in console filter box: [VENDOR_RENAME]
```

This shows only the vendor rename flow, hiding all other logs.

### Expected Log Sequence (Successful Rename)

```
1. User taps vendor menu
   [VENDOR_RENAME] getMenuItems called...

2. Menu appears, user taps "Rename"
   [VENDOR_RENAME] BottomSheetMenuList.onPress fired...
   [VENDOR_RENAME] handleOpenVendorEdit called...

3. Dialog opens, user edits and saves
   [VENDOR_RENAME] handleSaveVendorEdit called...
   [VENDOR_RENAME] Called setVendorSlots
   [VENDOR_RENAME] Called handleSaveVendorSlot

4. Firebase sync
   [VENDOR_RENAME] replaceVendorSlots called...
   [VENDOR_RENAME] saveVendorDefaults called...
   [VENDOR_RENAME] setDoc initiated...
   [VENDOR_RENAME] saveVendorDefaults complete

5. Result
   - Dialog closes
   - Vendor list updates with new name
   - Firebase queues sync (offline-first)
```

---

## Troubleshooting Quick Guide

### "Menu doesn't appear"
- Check if `[VENDOR_RENAME] getMenuItems called` log appears
- If NOT: vendor data might be missing
- If YES but no subsequent logs: menu generation issue

### "Dialog doesn't open"
- Look for `[VENDOR_RENAME] handleOpenVendorEdit called`
- If NOT: menu item click didn't work
- Check: `[VENDOR_RENAME] BottomSheetMenuList.onPress fired`

### "Save doesn't work"
- Look for `[VENDOR_RENAME] handleSaveVendorEdit called`
- Check: `[VENDOR_RENAME] Called setVendorSlots` (must appear)
- Check: `[VENDOR_RENAME] Called handleSaveVendorSlot` (must appear)
- If missing: dialog Save button not triggering

### "Name doesn't update"
- Check: `[VENDOR_RENAME] saveVendorDefaults called`
- Check: `[VENDOR_RENAME] setDoc initiated`
- Check: `[VENDOR_RENAME] saveVendorDefaults complete`
- If any missing: Firebase write didn't complete

### "Firebase error appears"
- Look for: `[VENDOR_RENAME] saveVendorDefaults failed`
- Check: error.message and error.code in the log
- Common causes:
  - Offline (no internet)
  - Firebase permissions
  - Firebase quota exceeded
  - Account context not loaded

---

## Error Handling Summary

✓ **No error boundaries** were found in the app
  - Errors won't be swallowed by React
  - They'll appear in console normally

✓ **Firebase errors are caught and logged** in saveVendorDefaults
  - Error message and code are logged
  - Write failure doesn't crash the app

✓ **UI layer is fire-and-forget** (offline-first pattern)
  - No try-catch blocks in UI handlers
  - This is intentional and correct

---

## Before Committing

These console.log statements should be removed before pushing to main:

```bash
# Option 1: Use git to revert files
git checkout app/(tabs)/settings.tsx
git checkout src/components/BottomSheetMenuList.tsx
git checkout src/data/vendorDefaultsService.ts

# Option 2: Manually remove all [VENDOR_RENAME] logs
# (search for console.log statements with [VENDOR_RENAME] prefix)
```

---

## Testing Checklist

```
□ Open DevTools console
□ Filter by: [VENDOR_RENAME]
□ Navigate to Settings > Presets > Vendors
□ Tap menu on a vendor with a name
□ Tap "Rename"
□ Edit the name and save
□ Check that all logs appear in sequence
□ Verify no red error logs
□ Check that UI updates with new name
```

---

## Log Format

All logs follow this format:
```
[VENDOR_RENAME] <location>: <description with data>
```

Example:
```
[VENDOR_RENAME] handleOpenVendorEdit called with index: 2
[VENDOR_RENAME] Current vendorSlots: [...]
[VENDOR_RENAME] Vendor at index: { id: 'slot-2', value: 'Costco' }
```

---

## Support

If the issue is unclear after reviewing logs:

1. **Check LOG_FLOW_DIAGRAM.txt** for visual flow
2. **Check vendor-rename-test-steps.md** for exact steps
3. **Look for error logs** in the sequence
4. **Check Firebase console** for write errors
5. **Verify network connectivity** for offline scenarios

---

## Summary

✓ 48 console.log statements added across 3 files
✓ All tagged with [VENDOR_RENAME] for easy filtering
✓ Complete execution flow traced from UI to Firebase
✓ Error handling visible at each layer
✓ Ready to test and debug vendor rename issue
