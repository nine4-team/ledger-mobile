# Strategy: Make Only Items Toolbar Sticky

## Current State
`stickySectionHeadersEnabled={true}` makes ALL section headers sticky (including Receipts, Notes, Details, Audit, etc.) when scrolling.

## Goal
Only the items toolbar (with search/sort/filter/select controls) should stick to the top when scrolling past it. Other section headers should scroll away normally.

## Recommended Approach

**Use `Animated.View` with scroll position tracking:**

1. Keep `stickySectionHeadersEnabled={false}`
2. Add `onScroll` handler to `SectionList` with `Animated.event` to track scroll Y position
3. Calculate the Y position where the items section header appears using section heights
4. When `scrollY >= itemsSectionHeaderY`, render a clone of the toolbar in an absolutely-positioned `Animated.View` at the top
5. Original toolbar in section header remains in place (invisible when clone is shown)

## Key Implementation Points

- Use `onLayout` on items section header to capture its Y position
- Animated interpolation: `opacity` from 0→1 when scroll crosses threshold
- Clone must match exact styling and state of original toolbar
- Consider using `react-native-reanimated` for better performance

## Alternative: Replace SectionList
Use `FlatList` with manual section rendering and `stickyHeaderIndices={[itemsToolbarIndex]}` for precise control over which elements stick.
