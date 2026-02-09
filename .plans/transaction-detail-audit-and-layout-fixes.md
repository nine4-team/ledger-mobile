# Transaction Detail Screen - Audit Badge and Layout Fixes

**Status**: ✅ Implemented
**Date**: 2026-02-09

## Context

The transaction detail screen ([app/transactions/[id]/index.tsx](../app/transactions/[id]/index.tsx)) needed three improvements:

1. ✅ **Replace warning icon with "Needs Review" badge** - Match the badge style from TransactionCard
2. ✅ **Fix sticky section behavior** - Only the items toolbar should stick, not section headers
3. ✅ **Fix section spacing** - Reduce gap between section titles and content

## Implementation Summary

All three changes have been implemented:

1. **Needs Review Badge** - Replaced `MaterialIcons` warning icon with styled badge matching `TransactionCard` design
   - Badge background: `#b9452014` (reddish-orange with low opacity)
   - Badge border: `#b9452033` with 1px border width
   - Text color: `#b94520` (solid reddish-orange)
   - Text: "Needs Review"
   - Positioned on right with `marginLeft: 'auto'`

2. **Sticky Headers Fixed** - Changed `stickySectionHeadersEnabled` from `true` to `false` (line 1290)
   - Section titles no longer stick when scrolling
   - Note: Items toolbar currently does not stick either. If sticky toolbar is needed, will need to refactor to use `StickyHeader` component with `AppScrollView`

3. **Section Spacing Reduced** - Changed `gap` in `styles.content` from `18` to `10` (line 1520)
   - Reduces vertical space between section titles and their content
   - Sections now feel more cohesive as a unit

## Current State

### Audit Section (Lines 1151-1183)
Currently displays a red warning icon when `transaction.needsReview === true`:
```tsx
{showWarning && (
  <MaterialIcons
    name="warning"
    size={20}
    color="#FF3B30"
    style={styles.warningIcon}
  />
)}
```

### Sticky Behavior
- All collapsible section headers can become sticky when scrolling
- This happens because sections are rendered inside a `SectionList` with `stickySectionHeadersEnabled={true}` (line 1247)
- User reports: section titles stick and other content scrolls underneath them

### Spacing Issue
- SectionList uses `contentContainerStyle={styles.content}` (line 1249)
- `styles.content` has `gap: 18` (line 1520)
- This creates too much vertical space between section titles and their content

## Required Changes

### 1. Replace Warning Icon with "Needs Review" Badge

**Goal**: Match the badge style used in [TransactionCard.tsx](../src/components/TransactionCard.tsx) (lines 304-318).

**Implementation**:
- Remove the MaterialIcons warning icon (lines 1172-1179)
- Add a badge View with Text child positioned on the right using `marginLeft: 'auto'`
- Use these exact styles from TransactionCard:

```tsx
badge: {
  paddingHorizontal: 10,
  paddingVertical: 5,
  borderRadius: 999,
  borderWidth: 1,
  maxWidth: 160,
}

// Colors:
backgroundColor: '#b9452014',  // reddish-orange with low opacity
borderColor: '#b9452033',      // same color with higher opacity
textColor: '#b94520',          // solid reddish-orange
```

- Badge text should say: **"Needs Review"**
- Use a regular `Text` component (not `AppText`) with `numberOfLines={1}` like TransactionCard does
- Text style should include:
  - `fontSize: 12`
  - `fontWeight: '600'`
  - `lineHeight: 16`
  - `color: '#b94520'`

**Files to modify**:
- `app/transactions/[id]/index.tsx`: Update audit section header rendering (lines 1151-1183)
- Add `reviewBadge` and `reviewBadgeText` styles to StyleSheet (around line 1561)

### 2. Fix Sticky Section Behavior

**Current Problem**:
- The `SectionList` component has `stickySectionHeadersEnabled={true}` (line 1247)
- This makes ALL section headers stick, which is not desired
- Only the transaction items toolbar should stick

**Two Possible Approaches**:

#### Option A: Disable SectionList Sticky Headers (Recommended)
1. Change `stickySectionHeadersEnabled={true}` to `stickySectionHeadersEnabled={false}` (line 1247)
2. Keep the existing `StickyHeader` wrapper around `ItemsListControlBar` (removed in transaction detail, but present in other screens)
3. Verify that items section header behavior is acceptable (title can scroll away, toolbar stays)

**Note**: Currently the transaction detail screen does NOT use `StickyHeader` component. Other screens do (see `app/project/[projectId]/spaces/[spaceId].tsx` and `app/business-inventory/spaces/[spaceId].tsx`).

If the items toolbar needs to stick:
- Import `StickyHeader` from `src/components/StickyHeader`
- Wrap the ItemsListControlBar + its container View in `<StickyHeader>`
- But this may not work with SectionList - test carefully

#### Option B: Convert from SectionList to ScrollView
This is a larger refactor but gives more control:
1. Replace `SectionList` with `AppScrollView` (imports already in place)
2. Manually render each section in order
3. Wrap ONLY the ItemsListControlBar View in `<StickyHeader>` component
4. `AppScrollView` auto-detects `StickyHeader` children and applies `stickyHeaderIndices`

**Files to modify**:
- `app/transactions/[id]/index.tsx`: Main render method (lines 1230-1254)

### 3. Fix Section Spacing

**Problem**:
- `gap: 18` in SectionList `contentContainerStyle` creates too much space between section titles and their content
- This affects all sections (receipts, other images, notes, details, taxes, audit)
- Transaction items section spacing is fine because the toolbar has custom styling

**Solution**:
- Reduce `gap` in `styles.content` from `18` to a smaller value (suggest `8` or `10`)
- Test to ensure items section spacing still looks good with its custom toolbar border/padding
- OR: Remove `gap` entirely and add explicit `marginBottom` to each section's container View

**Files to modify**:
- `app/transactions/[id]/index.tsx`: Update `styles.content` (line 1520)

## Testing Checklist

After implementing these changes, verify:

- [ ] Audit section displays "Needs Review" badge (not warning icon) when `transaction.needsReview === true`
- [ ] Badge styling matches TransactionCard exactly (colors, padding, border, max-width)
- [ ] Badge is positioned on the right side of the section header
- [ ] Badge does not appear when `transaction.needsReview === false` or `null`
- [ ] Section titles no longer stick when scrolling (except items toolbar if using StickyHeader)
- [ ] Items toolbar still functions correctly and stays visible when scrolling through items
- [ ] Vertical spacing between section titles and content is reduced and looks better
- [ ] No layout breaks in any section (receipts, images, notes, details, taxes, audit, items)
- [ ] Dark mode colors still work correctly (theme.colors.background for section backgrounds)

## Related Files

**Key files to review**:
- [app/transactions/[id]/index.tsx](../app/transactions/[id]/index.tsx) - Main file to modify
- [src/components/TransactionCard.tsx](../src/components/TransactionCard.tsx) - Reference for badge styles
- [src/components/StickyHeader.tsx](../src/components/StickyHeader.tsx) - If using Option B for sticky behavior
- [src/components/AppScrollView.tsx](../src/components/AppScrollView.tsx) - If converting to ScrollView
- [.troubleshooting/transaction-items-sticky-toolbar-scroll.md](../.troubleshooting/transaction-items-sticky-toolbar-scroll.md) - Previous sticky header issues and lessons learned

**Transaction data model**:
- [src/data/transactionsService.ts](../src/data/transactionsService.ts) - Transaction type definition (line 15-42)
- `needsReview?: boolean | null` field (line 37)

## Design Notes

**Badge Colors Explained**:
- The "Needs Review" badge uses a reddish-orange color (`#b94520`) to indicate attention required
- This is distinct from error red (`#FF3B30`) and warning orange (`#f59e0b`)
- The color choice matches the existing TransactionCard implementation for consistency
- The low opacity background (`#b9452014`) provides subtle visual weight without overwhelming the UI

**Sticky Behavior Rationale**:
- Users need the items toolbar controls (search, sort, filter, add) to remain accessible when scrolling through a long list of items
- Section titles (RECEIPTS, NOTES, etc.) don't need to stick because they're just labels
- This reduces visual clutter and makes the scroll behavior more predictable

**Spacing Rationale**:
- The original `gap: 18` was appropriate for spacing between discrete cards/sections
- But for collapsible sections, the title and content feel like a single unit and should be closer together
- The items section has custom styling (bottom border + padding) that already creates appropriate spacing
