# Sticky Control Bar Implementation - Planning Brief

## Context

We've redesigned the transaction items section across three screens to remove card wrappers and add breathing room. However, the sticky control bar functionality is still needed.

### What's Already Done
- ✅ Removed `TitledCard` wrappers from items sections
- ✅ Added uppercase caption section headers for visual separation
- ✅ Consistent spacing and layout across all three screens
- ✅ All existing functionality preserved (bulk select, sort, filter, search)

### What's Needed
**Sticky control bar** that stays at the top of the viewport when scrolling through the items section on:
1. `app/transactions/[id]/index.tsx` - Transaction detail screen
2. `app/business-inventory/spaces/[spaceId].tsx` - Business inventory space screen
3. `app/project/[projectId]/spaces/[spaceId].tsx` - Project inventory space screen

## Technical Environment

### Current Scroll Implementation
All three screens use:
- **`AppScrollView`** component (wrapper around React Native's `ScrollView`)
  - Location: `src/components/AppScrollView.tsx`
  - Provides consistent scroll behavior with pull-to-refresh support
- **Screen component** with nested scroll views
  - The items section is part of a larger scroll view containing other sections (receipts, details, images, etc.)

### The Control Bar Component
- **`ItemsListControlBar`** (`src/components/ItemsListControlBar.tsx`)
  - Wraps **`ListControlBar`** (`src/components/ListControlBar.tsx`)
  - Contains: search input, sort button, filter button, add button, optional left element (bulk select)
  - Current height: ~40-60px depending on search visibility

### Key Files Structure

**Transaction Detail** (`app/transactions/[id]/index.tsx`):
```tsx
<Screen>
  <AppScrollView>
    <HeroCard />
    <MediaGallerySection title="Receipts" />
    <MediaGallerySection title="Other Images" />
    <NotesSection />
    <TitledCard title="Details" />
    <TitledCard title="Tax & Itemization" /> {/* conditional */}

    {/* ITEMS SECTION - needs sticky control bar */}
    <View style={styles.itemsSection}>
      <AppText variant="caption" style={styles.sectionHeader}>
        TRANSACTION ITEMS
      </AppText>
      <ItemsListControlBar ... />  {/* <-- This needs to stick */}
      <View style={styles.list}>
        {items.map(item => <ItemCard ... />)}
      </View>
    </View>

    <TitledCard title="Transaction Audit" />
  </AppScrollView>
</Screen>
```

**Business/Project Inventory Spaces**: Similar structure with Images → Checklists → Items sections.

## Technical Constraints & Considerations

### React Native Limitations
- `position: 'sticky'` is **not reliably supported** in React Native (iOS/Android)
- Must work on both iOS and Android
- Must maintain smooth 60fps scroll performance
- Must work with pull-to-refresh functionality

### User Requirements
- Control bar should stick **within the main screen scroll** (not a separate scroll region)
- Control bar sticks when user scrolls past it
- When scrolling back up, control bar returns to its normal position
- Must work with existing search toggle, sort/filter menus, bulk selection

### Known Approaches (Pros/Cons)

1. **Animated.ScrollView with onScroll + Animated.View**
   - Listen to scroll events, calculate when control bar reaches top
   - Use Animated.View with position: 'absolute' for the sticky bar
   - Pros: Full control, works cross-platform
   - Cons: Complex math, need to handle keyboard, resize events, layout changes

2. **FlatList with stickyHeaderIndices**
   - Replace items list with FlatList, use built-in sticky header support
   - Pros: Native sticky behavior, performant
   - Cons: Would need to refactor items rendering, may conflict with AppScrollView, only sticks items within FlatList (not across whole page)

3. **react-native-sticky-header or similar library**
   - Use a proven library for sticky headers
   - Pros: Battle-tested, handles edge cases
   - Cons: Additional dependency, may conflict with existing scroll architecture

4. **Split scroll regions (separate ScrollView for items)**
   - Make items section its own flex: 1 ScrollView with control bar at top
   - Pros: Simple to implement, reliable sticky behavior
   - Cons: Loses unified scroll experience, harder to coordinate with pull-to-refresh

5. **Reanimated + ScrollView integration**
   - Use react-native-reanimated for performant scroll-based animations
   - Pros: High performance, smooth animations
   - Cons: Complex setup, additional dependency (though likely already in use)

## Success Criteria

The implementation must:
1. ✅ Make `ItemsListControlBar` sticky when scrolling through items section
2. ✅ Work on both iOS and Android
3. ✅ Maintain 60fps scroll performance (no janky scroll)
4. ✅ Not break existing functionality:
   - Pull-to-refresh on Screen component
   - Search input keyboard handling
   - Sort/filter bottom sheet menus
   - Bulk selection with checkboxes
   - Item card press/menu interactions
5. ✅ Handle edge cases:
   - Screen resize / orientation changes
   - Keyboard showing/hiding
   - Items list empty state
   - Items list very long (100+ items)
6. ✅ Apply consistently to all three screens
7. ✅ Maintain offline-first patterns (no blocking on data loads)

## Your Task

**Propose a detailed implementation plan** that:

1. **Analyzes the codebase** to understand:
   - How AppScrollView works
   - Whether react-native-reanimated is already installed
   - Current scroll event handling
   - Layout structure and constraints

2. **Recommends a specific approach** (from above or propose new) with:
   - Clear rationale for why this approach is best
   - How it handles all success criteria
   - Tradeoffs and risks

3. **Provides a step-by-step implementation plan** including:
   - Which files need to be modified/created
   - Code structure/architecture changes
   - How to handle each screen's specific layout
   - Testing strategy (what to verify works)
   - Fallback plan if approach doesn't work

4. **Identifies potential blockers** and how to mitigate them

5. **Estimates complexity** (simple/moderate/complex) and why

## Helpful Context

- Check if `react-native-reanimated` is in `package.json`
- Look at `AppScrollView.tsx` implementation
- Check if there are existing scroll event handlers in the three screens
- Review `Screen.tsx` component to understand header/content structure
- The app uses Expo Router for navigation

## Output Format

Your plan should be written in markdown and include:
- **Recommended Approach**: [Name] with clear justification
- **Architecture Changes**: What components/hooks need to be created/modified
- **Implementation Steps**: Detailed numbered steps
- **Code Examples**: Key snippets showing the pattern
- **Testing Checklist**: What to verify works
- **Risks & Mitigations**: What could go wrong and how to handle it
- **Complexity Assessment**: [Simple|Moderate|Complex] with explanation
