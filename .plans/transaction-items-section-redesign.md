# Transaction Items Section Redesign

## Problem
Transaction items are currently wrapped in a `TitledCard`, which constrains them and doesn't give them enough breathing room. The control bar should also be sticky on scroll for better UX.

## Goals
1. Remove transaction items from card wrapper
2. Give items section more width/breathing room
3. Use alternative visual method to show it's a distinct section
4. Make control bar sticky on scroll
5. Apply to all contexts: transaction detail, project inventory, business inventory

## Affected Files
- `app/transactions/[id]/index.tsx` - transaction detail screen
- `app/project/[projectId]/spaces/[spaceId].tsx` - project inventory space
- `app/business-inventory/spaces/[spaceId].tsx` - business inventory space
- Potentially `src/components/ItemsListControlBar.tsx` if sticky behavior needs component changes

## Implementation Plan

### Phase 1: Transaction Detail Screen (app/transactions/[id]/index.tsx)
- [x] Remove `<TitledCard title="Transaction Items">` wrapper around items section (lines 1224-1294)
- [x] Replace with a section header using `AppText` variant="caption" with uppercase styling
- [x] Add top margin/padding to visually separate from previous section (marginTop: 24)
- [ ] Wrap control bar in a sticky positioning container (deferred - see notes below)
- [ ] Test scrolling behavior to ensure control bar sticks

### Phase 2: Business Inventory Space Screen
- [x] Items section already had no card wrapper, updated header style
- [x] Changed from h2 variant to uppercase caption style to match transaction detail
- [x] Fixed Checklists section View wrapper
- [ ] Make control bar sticky (deferred - see notes below)

### Phase 3: Project Inventory Space Screen
- [x] Items section already had no card wrapper, updated header style
- [x] Changed from h2 variant to uppercase caption style to match transaction detail
- [x] Fixed Checklists section View wrapper
- [ ] Make control bar sticky (deferred - see notes below)

## Design Approach

### Section Header Style
Instead of `TitledCard`, use:
```tsx
<View style={styles.itemsSection}>
  <AppText variant="caption" style={styles.sectionHeader}>
    TRANSACTION ITEMS
  </AppText>

  <ItemsListControlBar ... />

  {/* items list */}
</View>
```

### Sticky Control Bar
Use React Native's `Animated` or position styling to make control bar sticky. May need to refactor to use `Animated.ScrollView` with `onScroll` handler.

Alternative: Use `position: 'sticky'` in web, but for React Native may need different approach (e.g., separate scrollable region or FlatList with sticky header).

## Questions/Decisions
- [x] Should control bar be sticky within the screen scroll, or should items have their own scroll region?
  - **DECISION**: Control bar sticks within main screen scroll (simpler implementation)
- [ ] What spacing/margins should replace the card padding?
  - **Recommendation**: Use existing `layout.screenBodyTopMd` or similar token
- [ ] Should we update `ListControlBar` component to support sticky prop?
  - **Decision needed**: Could add sticky positioning to component itself

## Notes
- Maintain all existing functionality (bulk select, sort, filter, search)
- Keep offline-first patterns intact
- Ensure theme colors are properly applied
- Test in both light and dark modes

## Implementation Notes (2026-02-08)

### Completed Changes
1. **Transaction Detail Screen** (`app/transactions/[id]/index.tsx`)
   - Removed TitledCard wrapper from items section
   - Added uppercase caption section header: "TRANSACTION ITEMS"
   - Added `itemsSection` style with gap: 12 and marginTop: 24
   - Added `sectionHeader` style with uppercase, letterSpacing: 0.5, fontWeight: '600'

2. **Business Inventory Space Screen** (`app/business-inventory/spaces/[spaceId].tsx`)
   - Updated Items section header from h2 to uppercase caption style
   - Changed header text to "ITEMS"
   - Updated `sectionHeader` style from flex row layout to text styling (matching transaction detail)
   - Fixed Checklists section to use h2 directly (removed unnecessary View wrapper)

3. **Project Inventory Space Screen** (`app/project/[projectId]/spaces/[spaceId].tsx`)
   - Updated Items section header from h2 to uppercase caption style
   - Changed header text to "ITEMS"
   - Updated `sectionHeader` style from flex row layout to text styling (matching transaction detail)
   - Fixed Checklists section to use h2 directly (removed unnecessary View wrapper)

### Sticky Control Bar - Deferred
The sticky control bar functionality has been deferred for the following reasons:
- React Native's `position: 'sticky'` is not reliably supported across platforms
- Implementing sticky behavior requires significant refactoring:
  - Option 1: Use Animated.ScrollView with onScroll handler and position absolute
  - Option 2: Use FlatList with stickyHeaderIndices
  - Option 3: Split into separate scroll regions
- All options add complexity and may impact scroll performance
- The current implementation provides the primary UX improvement (more breathing room, clearer section separation)
- Sticky behavior can be added in a future iteration if user feedback indicates it's needed

### Design Consistency
All three screens now use consistent styling:
- Uppercase caption headers for items sections
- No card wrappers around items (more breathing room)
- Consistent spacing (gap: 12 within sections)
- Other sections (Images, Checklists) continue to use h2 headers as appropriate
