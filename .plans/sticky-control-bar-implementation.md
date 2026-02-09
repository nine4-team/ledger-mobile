# Sticky Control Bar Implementation Plan

## Problem
The `ItemsListControlBar` on three screens (transaction detail, business inventory space, project space) scrolls away when the user scrolls through long item lists. It should stick to the top of the viewport so sort/filter/search/add actions remain accessible.

## Recommended Approach: `stickyHeaderIndices` on ScrollView

**Why this approach:**
- Built into React Native's `ScrollView` — zero new dependencies
- Native performance on both iOS and Android (60fps guaranteed, runs on the UI thread)
- Already supported by `AppScrollView` (props pass through via spread)
- Handles keyboard, orientation changes, and pull-to-refresh automatically
- Battle-tested — this is the standard RN pattern for sticky headers

**Why NOT the alternatives:**
- `react-native-reanimated`: Not installed, large dependency to add for one feature
- Animated overlay: Requires duplicate rendering of control bar, complex JS-thread scroll tracking
- Split scroll regions: Breaks unified scroll experience, pull-to-refresh coordination issues
- Third-party library: Unnecessary when built-in API exists

## Architecture Changes

### New: `StickyHeader` marker component
A thin `View` wrapper that:
1. Serves as a **marker** for automatic sticky index detection
2. Provides an **opaque background** so content doesn't show through when sticky

```tsx
// src/components/StickyHeader.tsx
import React from 'react';
import { View, ViewProps, StyleSheet } from 'react-native';
import { useTheme } from '../theme/useTheme';

export function StickyHeader({ children, style, ...props }: ViewProps) {
  const theme = useTheme();
  return (
    <View
      style={[styles.container, { backgroundColor: theme.colors.background }, style]}
      {...props}
    >
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    zIndex: 1, // Ensure sticky header renders above content on Android
  },
});
```

### Modified: `AppScrollView` — auto-detect sticky headers
Enhance to scan children for `StickyHeader` instances and compute `stickyHeaderIndices` automatically.

```tsx
// src/components/AppScrollView.tsx
import React from 'react';
import { ScrollView, ScrollViewProps } from 'react-native';
import { StickyHeader } from './StickyHeader';

export const AppScrollView = React.forwardRef<ScrollView, ScrollViewProps>(
  ({
    children,
    showsVerticalScrollIndicator = false,
    showsHorizontalScrollIndicator = false,
    stickyHeaderIndices: externalIndices,
    ...props
  }, ref) => {
    // Auto-detect StickyHeader markers if no explicit indices provided
    const resolvedIndices = externalIndices ?? (() => {
      const flat = React.Children.toArray(children);
      const indices: number[] = [];
      flat.forEach((child, i) => {
        if (React.isValidElement(child) && child.type === StickyHeader) {
          indices.push(i);
        }
      });
      return indices.length > 0 ? indices : undefined;
    })();

    return (
      <ScrollView
        ref={ref}
        showsVerticalScrollIndicator={showsVerticalScrollIndicator}
        showsHorizontalScrollIndicator={showsHorizontalScrollIndicator}
        stickyHeaderIndices={resolvedIndices}
        {...props}
      >
        {children}
      </ScrollView>
    );
  }
);
```

### Per-screen changes
Each screen needs its items section **flattened** so the control bar is a **direct child** of the ScrollView (required for `stickyHeaderIndices`).

**Before (nested):**
```tsx
<AppScrollView>
  ...
  <View style={styles.itemsSection}>
    <AppText variant="caption">TRANSACTION ITEMS</AppText>
    <ItemsListControlBar ... />
    <View style={styles.list}>
      {items.map(...)}
    </View>
  </View>
  ...
</AppScrollView>
```

**After (flattened with StickyHeader):**
```tsx
<AppScrollView>
  ...
  <AppText variant="caption" style={styles.sectionHeader}>
    TRANSACTION ITEMS
  </AppText>
  <StickyHeader>
    <ItemsListControlBar ... />
  </StickyHeader>
  <View style={styles.list}>
    {items.map(...)}
  </View>
  ...
</AppScrollView>
```

### How `React.Children.toArray` handles conditionals
`React.Children.toArray` filters out `null`, `false`, and `undefined` values — matching how ScrollView internally counts children for `stickyHeaderIndices`. This means conditional rendering like `{showTaxInfo && <TitledCard />}` is handled automatically. The computed index is always correct regardless of which conditional sections are visible.

### CRITICAL: Fragment flattening required
**Bug discovered 2026-02-08**: `React.Children.toArray` does NOT flatten Fragment elements. It treats `<>...</>` as a single opaque React element with `type === React.Fragment`. This broke auto-detection in screens using ternary operators that wrap content in Fragments.

**Fix**: Added `flattenFragments()` helper to `AppScrollView` that recursively unwraps Fragment children before both:
1. Scanning for `StickyHeader` indices
2. Rendering children to `ScrollView`

This ensures the flattened array matches ScrollView's internal child indexing for `stickyHeaderIndices`.

## Implementation Steps

### Step 1: Create `StickyHeader` component
- File: `src/components/StickyHeader.tsx`
- Simple View wrapper with opaque background + zIndex
- Uses `useTheme()` for background color

### Step 2: Enhance `AppScrollView` with auto-detection
- File: `src/components/AppScrollView.tsx`
- Add child scanning for `StickyHeader` type
- Preserve backward compatibility (explicit `stickyHeaderIndices` prop takes precedence)
- No breaking changes to existing consumers

### Step 3: Switch space screens from native `ScrollView` to `AppScrollView`
- `app/business-inventory/spaces/[spaceId].tsx` — currently uses native `ScrollView`
- `app/project/[projectId]/spaces/[spaceId].tsx` — currently uses native `ScrollView`
- Transaction detail already uses `AppScrollView`

### Step 4: Restructure transaction detail screen items section
- File: `app/transactions/[id]/index.tsx`
- Break `itemsSection` View into direct children of AppScrollView
- Wrap `ItemsListControlBar` in `<StickyHeader>`
- Adjust spacing (the `itemsSection` gap → use margins on individual elements)

### Step 5: Restructure business inventory space screen items section
- File: `app/business-inventory/spaces/[spaceId].tsx`
- Same flattening pattern as Step 4
- Handle the inline bulk mode panel positioning

### Step 6: Restructure project space screen items section
- File: `app/project/[projectId]/spaces/[spaceId].tsx`
- Same pattern (nearly identical to business inventory)

### Step 7: Visual polish
- Verify the control bar looks correct when sticky (opaque background, no content bleed-through)
- Consider adding a subtle bottom border or shadow to the sticky header for visual separation
- Test with both light and dark themes

## Spacing Adjustments

Current gap structure:
- ScrollView content container: `gap: 18` (transaction) / `gap: 20` (spaces)
- Items section internal: `gap: 12`

After flattening, the section header, control bar, and list become siblings with the outer gap (18/20px). This is slightly more than the current 12px internal gap. Options:
1. **Accept the wider gap** — simpler, may look fine
2. **Use negative margins** — e.g., `marginTop: -6` on the StickyHeader to tighten spacing
3. **Wrap in a collapsing container** — keep a wrapper View for header + list (not the control bar)

Recommendation: Start with option 1 and adjust if visually necessary.

## Testing Checklist

### Functionality
- [ ] Control bar sticks at top when scrolling through items on all 3 screens
- [ ] Control bar returns to normal position when scrolling back up
- [ ] Search toggle works while sticky (expands/collapses)
- [ ] Sort button opens bottom sheet while sticky
- [ ] Filter button opens bottom sheet while sticky
- [ ] Add button works while sticky
- [ ] Bulk select (transaction detail) works while sticky

### Cross-platform
- [ ] Works on iOS
- [ ] Works on Android
- [ ] Pull-to-refresh still works on all screens

### Edge cases
- [ ] Empty items list (no items to scroll through)
- [ ] Very long items list (100+ items)
- [ ] Keyboard shows/hides while sticky
- [ ] Device rotation while sticky
- [ ] Dark mode renders correctly (opaque background matches theme)

### Regression
- [ ] All existing scroll behavior preserved
- [ ] No layout shifts or visual glitches
- [ ] Bottom sheet menus still work properly
- [ ] Navigation between screens works

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `React.Children.toArray` indices don't match ScrollView's internal child indexing | Low | Test with conditional sections. Fallback: use explicit `stickyHeaderIndices` prop with manual count. |
| Android z-index issues (content rendering over sticky header) | Medium | `StickyHeader` includes `zIndex: 1`. If needed, add `elevation` for Android. |
| Spacing looks wrong after flattening items section | Medium | Adjust with targeted margins. Can be fine-tuned per-screen. |
| Search input expansion changes sticky header height | Low | `stickyHeaderIndices` handles dynamic height natively. |
| Pull-to-refresh conflicts with sticky header | Low | `stickyHeaderIndices` is a first-party ScrollView feature; pull-to-refresh integrates natively. |

## Complexity Assessment

**Moderate**

The core mechanism (`stickyHeaderIndices`) is simple and built-in. The complexity comes from:
1. Restructuring three screens' JSX to flatten the items section
2. Adjusting spacing/margins after flattening
3. Ensuring the `StickyHeader` auto-detection in `AppScrollView` handles all edge cases
4. Visual polish (opaque background, theming, shadows)

Estimated file changes: 5 files (1 new component, 1 modified component, 3 screen modifications)
