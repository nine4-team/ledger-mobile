# Fix: Transaction Items Sticky Toolbar Scroll Issues

**Status:** Complete - Pending User Verification
**Created:** 2026-02-08
**Troubleshooting Log:** `.troubleshooting/transaction-items-sticky-toolbar-scroll.md`

## Root Cause
Multiple layering and coordinate space issues:
1. Z-index conflict between StickyHeader (z:1) and TopHeader (z:1)
2. Background color mismatch causing visual bleed-through
3. Scroll boundary calculation issues with sticky indices

## Implementation Plan

### Step 1: Fix Z-Index Hierarchy ✓
- **File:** `src/components/StickyHeader.tsx:20`
- **Change:** Increase `zIndex` from `1` to `10` to ensure sticky header renders above TopHeader
- **Rationale:** TopHeader has `zIndex: 1`, so sticky content needs higher value

### Step 2: Fix Background Color Consistency ✓
- **File:** `src/components/StickyHeader.tsx:19`
- **Change:** Use `uiKitTheme.background.chrome` instead of `theme.colors.background`
- **Rationale:** Match TopHeader's background to prevent bleed-through when sticky

### Step 3: Verify Scroll Behavior 🔄 (User Testing Required)
- Test that toolbar no longer scrolls behind header
- Verify can scroll to bottom of items list
- Check that scroll doesn't get stuck

## Files to Modify
1. `src/components/StickyHeader.tsx` - z-index and background color fixes

## Testing
- Open transaction with multiple items
- Scroll to items section
- Verify toolbar sticks correctly below header
- Scroll to bottom and verify no stuck behavior
