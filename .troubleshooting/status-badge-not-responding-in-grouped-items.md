# Issue: Status badge not responding in GroupedItemCard subcards

**Status:** Active
**Opened:** 2026-02-10
**Resolved:** _pending_

## Context
- **Symptom:** When tapping the status badge in an ItemCard that's rendered as a subcard within GroupedItemCard, nothing happens. The badge appears with the chevron but is unresponsive.
- **Affected area:**
  - `src/components/ItemCard.tsx` (status badge rendering)
  - `src/components/GroupedItemCard.tsx` (renders child ItemCards)
- **Severity:** Blocks user - status change functionality unavailable in grouped items
- **Reproduction steps:**
  1. Navigate to a screen with GroupedItemCard (e.g., transaction detail with grouped items)
  2. Expand a grouped item to see subcards
  3. Tap the status badge (with chevron) on any subcard
  4. Nothing happens (expected: status picker should appear)
- **Environment:** React Native, iOS

## Recent Changes
1. Made chevron always visible on status badges (removed conditional rendering based on `onStatusPress`)
2. Removed `disabled={!onStatusPress}` from status badge Pressable (was causing taps to pass through to parent card)
3. Added `hitSlop={8}` to status badge Pressable

**Previous behavior:** Before these changes, tapping the status badge would navigate to the item detail screen (card's `onPress` was firing instead)

## Research

### Status Badge Implementation (ItemCard.tsx:197-217)
Current implementation:
- Status badge is a `Pressable` inside the card header
- Uses `e.stopPropagation()` to prevent parent card press
- Calls `onStatusPress?.()` with optional chaining
- Has `hitSlop={8}` for better touch capture
- No `disabled` prop

The card header is inside the main card `Pressable` (lines 142-155), which has an `onPress` handler.

### GroupedItemCard Child Rendering (GroupedItemCard.tsx:299-310)
```typescript
<ItemCard
  {...item}
  indexLabel={`${idx + 1}/${items.length}`}
  stackSkuAndSource
  style={[
    idx < items.length - 1 ? styles.itemRowSpacing : null,
  ]}
/>
```

The component spreads all props from the `items` array. If items don't have `onStatusPress` defined, the handler will be undefined.

## Investigation Log

### H1: Items passed to GroupedItemCard don't have `onStatusPress` defined
- **Rationale:** The status badge calls `onStatusPress?.()` with optional chaining. If this prop is undefined on the items, nothing happens when tapped.
- **Experiment:** Search for all GroupedItemCard usage and check if items include `onStatusPress` prop
- **Evidence:**
  - `SharedItemsList.tsx` has TWO rendering paths:
    1. **Embedded mode** (lines 1031-1065): INCLUDES `onStatusPress: () => handleStatusPress(item.id)` at line 1058 ✓
    2. **Standalone FlatList mode** (lines 1171-1200): MISSING `onStatusPress` entirely ✗
  - GroupedItemCard spreads item props at line 302: `<ItemCard {...item} />`
  - If item doesn't have `onStatusPress`, the prop is undefined on ItemCard
- **Verdict:** **CONFIRMED** - standalone mode is missing the handler

### H2: stopPropagation is working correctly
- **Rationale:** After our changes, tapping the status badge no longer navigates to item (previous behavior), suggesting stopPropagation works
- **Evidence:**
  - User reported: "now nothing happens" (not "still navigating")
  - This confirms stopPropagation is preventing parent card's onPress
  - The issue is the missing handler, not event propagation
- **Verdict:** **CONFIRMED** - stopPropagation fixed the navigation issue, handler is the problem

## Conclusion

**Root Cause:** `SharedItemsList.tsx` has two rendering modes. The standalone FlatList mode (lines 1171-1200) doesn't include `onStatusPress` when building item props for GroupedItemCard, while the embedded mode (lines 1031-1065) does. When items lack this prop, tapping the status badge calls `onStatusPress?.()` which does nothing.

**Why this affects GroupedItemCard specifically:** GroupedItemCard passes items through to child ItemCards via spread operator. If the source items don't include `onStatusPress`, neither will the rendered cards.

## Resolution
- **Fix:** Added `onStatusPress: () => handleStatusPress(item.id)` to standalone FlatList mode in SharedItemsList.tsx, mirroring the implementation already present in embedded mode
- **Files changed:**
  - `src/components/SharedItemsList.tsx` (line 1194: added onStatusPress handler)
  - `src/components/ItemCard.tsx` (removed `disabled` prop from status badge, added `hitSlop={8}`)
- **Commit:** _pending_
- **Verified by user:** Pending

## Lessons Learned
- When components have multiple rendering paths (embedded vs standalone), ensure all interactive props are consistent across both paths
- The `disabled` prop on Pressables causes touches to pass through to parent - use optional chaining on handlers instead
- Always show UI affordances (chevrons) even when handlers aren't wired up, to maintain consistency and avoid user confusion
