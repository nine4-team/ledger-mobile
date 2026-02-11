# Fix BulkSelectionBar — Normalize Position Across Screens

## Problem

The BulkSelectionBar appears in a **different vertical position** depending on which screen you're on. Transaction detail, space detail, and the standalone items tab each render the bar inside a different parent container hierarchy, so `position: absolute, bottom: 0` resolves to a different spot on each screen.

The goal is to make the bar look and behave identically everywhere — flush at the screen bottom, buttons above the home indicator.

## Why It's Inconsistent

The bar uses `position: absolute, bottom: 0`. That positions it at the bottom of its **nearest parent** — but that parent is different in each context:

### Context A — Transaction Detail (`app/transactions/[id]/index.tsx`)

```
Screen (outer container, flex: 1)
  TopHeader
  Screen.content View (flex: 1, paddingBottom: insets.bottom ~34px)
    ├─ SectionList
    └─ BulkSelectionBar ← absolute parent is Screen.content View
```

Bar's absolute parent = **Screen.content View**, which has ~34px paddingBottom from safe area. In Yoga, `bottom: 0` resolves inside the content box (padding inset), so the bar sits ~34px above the actual screen edge.

### Context B — Space Detail (`src/components/SpaceDetailContent.tsx` inside `app/project/.../[spaceId].tsx`)

```
Screen (outer container, flex: 1)
  TopHeader
  Screen.content View (flex: 1, paddingBottom: insets.bottom ~34px)
    └─ SpaceDetailContent
       └─ View style={{ flex: 1 }}   ← EXTRA WRAPPER
          ├─ SectionList
          └─ BulkSelectionBar ← absolute parent is SpaceDetailContent.container
```

Bar's absolute parent = **SpaceDetailContent's container View** (flex: 1, no padding). This View is a flex child of Screen.content, so its height is Screen.content's content box height (already reduced by 34px padding). The bar ends up 34px above screen bottom — same as Context A in theory — but the intermediate wrapper changes how the remaining space is distributed, and the SectionList has different base paddingBottom (0 vs 24), leading to visually different results.

### Context C — SharedItemsList standalone (`src/components/SharedItemsList.tsx`)

```
Screen (from whatever parent page)
  Screen.content View (flex: 1, paddingBottom: varies)
    └─ SharedItemsList
       └─ View style={{ flex: 1 }}
          ├─ Control bar (search/sort/filter)
          ├─ FlatList
          └─ BulkSelectionBar ← absolute parent is SharedItemsList.container
```

Bar's absolute parent = **SharedItemsList's container**. Whether this is inside a Screen with `includeBottomInset` or not depends on the calling page.

### The Core Problem

Each context has a **different number of wrapper Views** between the bar and the Screen, and each wrapper inherits different padding/flex behavior. So the bar ends up at a different visual position on each screen.

## Current Code State

### BulkSelectionBar (`src/components/BulkSelectionBar.tsx`)
- `position: 'absolute', bottom: 0, left: 0, right: 0`
- `paddingVertical: 6` (no safe area handling)
- No imports of safe area insets

### Screen (`src/components/Screen.tsx`, lines 173-187)
- Content View: `flex: 1, paddingBottom: appTokens.screen.contentPaddingBottom + (includeBottomInset ? insets.bottom : 0)`
- `appTokens.screen.contentPaddingBottom` = 0
- `includeBottomInset` defaults to `true` → paddingBottom = `insets.bottom` (~34px)

### Scroll clearance padding (`src/ui/tokens.ts`)
- `getBulkSelectionBarContentPadding()` returns `BULK_SELECTION_BAR.BASE_HEIGHT` (50)
- Used in all SectionList/FlatList contentContainerStyle to prevent last items from hiding behind bar

### Screen wrappers
- `app/transactions/[id]/index.tsx` — no `includeBottomInset` override (defaults true)
- `app/project/[projectId]/spaces/[spaceId].tsx` — no override (defaults true)
- `app/business-inventory/spaces/[spaceId].tsx` — no override (defaults true)

## What Was Already Tried (and failed)

1. **Set `includeBottomInset={false}` + safe area padding inside bar**: Removed the invisible gap below the bar, but created a visible 34px gap inside the bar (between buttons and bar bottom edge).
2. **Reverted bar to simple `paddingVertical: 6` + default `includeBottomInset`**: The "original" state. Bar is positioned differently per-screen because the parent hierarchy differs.
3. **Adjusted `getBulkSelectionBarContentPadding` calculation**: Only affects scroll content padding, not bar position.

None of these work because they all assume `bottom: 0` resolves to the same spot in every context — it doesn't.

## Recommended Fix: Drop Absolute Positioning

Switch the bar to **static flex layout** so it participates in normal flow. This is what `SharedTransactionsList` already does (and it's the only context that works correctly).

**Pattern:**
```tsx
<View style={{ flex: 1 }}>
  <SectionList style={{ flex: 1 }} ... />
  {selectionCount > 0 && <BulkSelectionBar />}
</View>
```

- SectionList gets `flex: 1` → fills space above the bar
- Bar is a normal flex child → sits at the bottom of its container, no positioning math
- Screen's default `includeBottomInset` handles safe area below the bar
- No need for `getBulkSelectionBarContentPadding` or dynamic contentContainerStyle padding
- The bar's position is determined by flex layout, which is the same regardless of how many wrappers exist

### Changes:

**`src/components/BulkSelectionBar.tsx`**:
- Remove `position: 'absolute'`, `bottom: 0`, `left: 0`, `right: 0`

**`app/transactions/[id]/index.tsx`**:
- Add `style={{ flex: 1 }}` to SectionList (so it fills space above bar)
- Remove dynamic `paddingBottom: getBulkSelectionBarContentPadding()` from contentContainerStyle
- Clean up `getBulkSelectionBarContentPadding` import

**`src/components/SpaceDetailContent.tsx`**:
- Add `style={{ flex: 1 }}` to SectionList
- Remove dynamic contentContainerStyle padding
- Clean up import

**`src/components/SharedItemsList.tsx`**:
- Add `style={{ flex: 1 }}` to FlatList
- Remove dynamic contentContainerStyle padding
- Clean up import

**`src/ui/tokens.ts` + `src/ui/index.ts`**:
- Remove `BULK_SELECTION_BAR`, `getBulkSelectionBarContentPadding` (now unused)

**Screen wrappers** (`app/transactions/[id]/index.tsx`, `app/project/.../[spaceId].tsx`, `app/business-inventory/.../[spaceId].tsx`):
- Keep default `includeBottomInset` (true) — do NOT set false

## Edge Cases to Verify

1. **Bar appears/disappears**: When selection changes from 0 → N or N → 0, the SectionList height changes. Scroll position may jump slightly. This is acceptable (standard iOS pattern) but verify it's not jarring.
2. **Safe area on notchless devices**: With static layout and `includeBottomInset={true}`, the Screen adds 0px padding on devices with no home indicator. The bar should still sit at the bottom with just its `paddingVertical: 6`.
3. **SharedTransactionsList**: Already uses static layout with a custom bar View. Verify no regression.
4. **Embedded mode**: SharedItemsList with `embedded={true}` doesn't render BulkSelectionBar (the parent detail screen does). Verify the parent screen's bar still works.

## Success Criteria
- [ ] Bar sits at same visual position across all screens
- [ ] No gap below bar background
- [ ] Buttons above home indicator
- [ ] Last list item not hidden behind bar
- [ ] Works on devices with and without home indicators
