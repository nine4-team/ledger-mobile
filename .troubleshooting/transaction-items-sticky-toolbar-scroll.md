# Issue: Transaction Items Sticky Toolbar Scroll Behavior

**Status:** Active
**Opened:** 2026-02-08
**Resolved:** _pending_

## Context
- **Symptom:** When scrolling down in a transaction view to the transaction items section, the toolbar (which should stick just below the header) scrolls past the header and disappears behind it. Scroll sometimes stops before reaching the bottom of the page, with inconsistent behavior - sometimes can continue scrolling, sometimes gets stuck. User can still interact with menus and items.
- **Affected area:** Transaction detail view, transaction items section, sticky toolbar
- **Severity:** Degraded - affects UX but doesn't block core functionality
- **Reproduction steps:**
  1. Open a transaction
  2. Scroll down to transaction items section
  3. Observe toolbar scrolling behavior past header
  4. Try to scroll to bottom - may get stuck inconsistently
- **Environment:**
  - Branch: docs/update-budget-category-terminology
  - React Native mobile app

## Root Cause
**FlatList gesture capture inside ScrollView with stickyHeaderIndices:**

The FlatList (introduced in commit `33063da` for card spacing) creates an internal VirtualizedList that captures touch/scroll gestures even with `scrollEnabled={false}`. When combined with `stickyHeaderIndices` on the parent ScrollView:

1. The StickyHeader toolbar pins correctly at the ScrollView top
2. The FlatList below it intercepts scroll gestures in the items area
3. Since `scrollEnabled={false}`, the FlatList doesn't scroll, but it also doesn't pass gestures back to the parent ScrollView
4. This makes the entire items section (toolbar + items list) appear "frozen" while content above scrolls behind it
5. The inconsistent "sometimes can scroll, sometimes stuck" behavior depends on WHERE the user touches — touching the toolbar area works, touching the items area is captured by FlatList

**Fix:** Replace FlatList with View + map (the original pattern before `33063da`). The FlatList was only added for gap spacing, which can be achieved with `gap` style on a View.

## Investigation Log

### H1: Sticky positioning conflict between header and toolbar
- **Rationale:** The toolbar is described as "supposed to stick just below the header" but is scrolling past it, suggesting a z-index or positioning issue
- **Experiment:** Located transaction detail screen and examined scroll view structure, sticky header implementation, and z-index values across components
- **Evidence:**
  - [app/transactions/[id]/index.tsx:1224-1266](app/transactions/[id]/index.tsx#L1224-L1266) - StickyHeader wrapping ItemsListControlBar
  - [src/components/StickyHeader.tsx:20](src/components/StickyHeader.tsx#L20) - `zIndex: 1`
  - [src/components/TopHeader.tsx:210](src/components/TopHeader.tsx#L210) - `zIndex: 1` (conflict!)
  - [src/components/Screen.tsx:178](src/components/Screen.tsx#L178) - `paddingHorizontal: SCREEN_PADDING` creates coordinate space offset
  - [src/components/AppScrollView.tsx:35-54](src/components/AppScrollView.tsx#L35-L54) - Auto-detects StickyHeader children and computes `stickyHeaderIndices`
- **Verdict:** **Confirmed** - Multiple issues identified:
  - Equal z-index values create ambiguous stacking
  - Screen padding creates offset between ScrollView coordinate space and viewport
  - Background colors don't match between sticky and header components
  - Scroll boundary calculation affected by sticky indices

### H2: Recent commit introduced sticky control bar feature
- **Rationale:** Git log shows commit `b16311d` "feat: add sticky control bar to items sections" which likely introduced or modified this behavior
- **Experiment:** Examined commit context and implementation approach
- **Evidence:**
  - Used React Native's native `stickyHeaderIndices` for performance
  - Made control bars direct children of ScrollView for sticky behavior
  - But didn't account for Screen wrapper padding introducing coordinate space offset
- **Verdict:** **Confirmed** - This feature is new and the architectural issues weren't caught during implementation

### H3: Initial fix attempt - z-index and background color
- **Rationale:** Assumed the issue was z-index conflict and background mismatch
- **Experiment:** Changed StickyHeader z-index from 1 to 10 and background to chrome color
- **Evidence:** User reports fix did NOT work - "the whole container that contains the list of items and the toolbar, that's all sticking. I can see the page scrolling behind the list of items."
- **Verdict:** **Ruled Out** - The problem is not z-index/background. The ENTIRE items section (toolbar + list) is becoming sticky, not just the toolbar.

### H4: StickyHeader is wrapping too much content
- **Rationale:** User sees entire items list sticking, not just the toolbar. StickyHeader may be wrapping both the toolbar AND the items list.
- **Experiment:** Examined transaction detail screen structure
- **Evidence:**
  - Lines 1235-1266: StickyHeader wraps ONLY ItemsListControlBar
  - Lines 1268-1295: FlatList is a SIBLING of StickyHeader, not a child
  - FlatList has `scrollEnabled={false}` so it renders all items in parent scroll
  - AppScrollView correctly detects StickyHeader via flattenFragments logic
- **Verdict:** **Ruled Out** - Only the toolbar is wrapped in StickyHeader. The FlatList is separate.

### H5: Visual perception issue - need clarification from user
- **Rationale:** Code shows only toolbar is sticky, but user sees items list also sticking. Need to clarify what "sticking" means in this context.
- **Experiment:** Ask user to clarify what content is staying fixed vs scrolling
- **Evidence:** User confirmed: the items list below the toolbar ALSO appears frozen/stuck (answer "2")
- **Verdict:** **Confirmed** - Both toolbar and items list appear stuck, not just the toolbar

### H6: FlatList (VirtualizedList) captures touch gestures even with scrollEnabled={false}
- **Rationale:** FlatList creates an internal VirtualizedList that has its own gesture handler. Even with `scrollEnabled={false}`, it captures touch events in its area, preventing the parent ScrollView from receiving them. This is a known React Native issue with nested scrollable components.
- **Experiment:** Traced the FlatList introduction to commit `33063da` ("fix: convert transaction items list to FlatList for proper spacing"). The original pattern was View + map. FlatList was only added for gap spacing (8→10px).
- **Evidence:**
  - `app/transactions/[id]/index.tsx:1268-1295` — FlatList with `scrollEnabled={false}` inside AppScrollView
  - Commit `33063da` — converted from View+map to FlatList purely for card spacing
  - AppScrollView uses `stickyHeaderIndices` — when StickyHeader pins, the FlatList below it fills the viewport and captures all gestures in that area
  - Inconsistent scroll behavior matches: touching toolbar area (StickyHeader) passes events to parent, touching items area (FlatList) does not
- **Verdict:** **Confirmed** — FlatList gesture capture is the primary cause of the "frozen items section" behavior

### H7: First fix attempt - replaced FlatList with View but kept modified styles
- **Rationale:** Replace FlatList with original View + map pattern to eliminate gesture capture
- **Experiment:** Changed FlatList back to View + map, but kept the modified `styles.list` (gap: 10, flexDirection: 'column')
- **Evidence:** User reports cards are touching again and scrolling still not working
- **Verdict:** **Ruled Out** — FlatList was a red herring. Real issue is architectural.

### H8: The stickyHeaderIndices pattern itself causes layout conflicts
- **Rationale:** Maybe the sticky positioning feature itself is broken, not FlatList
- **Experiment:** Deep investigation of StickyHeader, AppScrollView, architectural comparison with SharedItemsList
- **Evidence:**
  - StickyHeader has no gesture handlers (pure View wrapper)
  - SharedItemsList uses FlatList at ROOT (no parent ScrollView), works fine
  - Transaction detail: AppScrollView > StickyHeader > View+map creates layout conflict
  - When StickyHeader pins, View below can't scroll properly
  - Gap needs `flexGrow: 1` (seen in SharedItemsList) but that breaks in this nested context
- **Verdict:** **Confirmed** — The stickyHeaderIndices + View+map architecture is fundamentally broken

### H9: Try removing flexDirection and adding collapsable={false}
- **Rationale:** The `flexDirection: 'column'` was added by FlatList commit but Views are column by default. Adding `collapsable={false}` forces React Native to create a real native view instead of flattening it.
- **Experiment:**
  - Removed `flexDirection: 'column'` from `styles.list`
  - Added `collapsable={false}` to the View wrapping the items
- **Evidence:** _pending user testing_
- **Verdict:** _pending_

## Resolution
- **Fix:** _in progress - trying collapsable={false} and removed flexDirection_
- **Files changed:** `app/transactions/[id]/index.tsx` (line 1269, lines 1619-1622)
- **Commit:** _pending_
- **Verified:** _pending user testing_

## Handoff Notes

**What we know:**
1. The sticky toolbar feature (commit `b16311d`) uses React Native's `stickyHeaderIndices` via StickyHeader + AppScrollView
2. The items list was FlatList (commit `33063da`), which captured gestures even with `scrollEnabled={false}`
3. Replaced FlatList with View + map, but cards are now touching and scrolling still broken
4. Original working state (before `33063da`) had View + map with `styles.list: { gap: 8, marginTop: 12 }`
5. The sticky toolbar SHOULD work — other apps do this successfully

**What needs investigation:**
1. Why is `gap: 10` not working on the View? Does it need `flexGrow: 1` or different container properties?
2. Why is scrolling still broken after removing FlatList? Is there a layout issue with how the View is positioned relative to StickyHeader?
3. Check if there's a React Native pattern for sticky headers with non-FlatList content below that actually works
4. Look at how other sections in the app handle similar patterns (sticky controls + scrolling content)

**What to try next:**
1. Add `flexGrow: 1` to `styles.list` and see if gap works (but watch for layout breaking)
2. Check if wrapping the View in a Fragment or different container helps with scroll gesture propagation
3. Try using `collapsable={false}` on the View to force it to be a real native view
4. Look for `pointerEvents` or other gesture handling props that might help
5. Check if the issue is actually in AppScrollView's `flattenFragments` logic interfering with the View

**DO NOT suggest removing the sticky feature. The user wants this working.**

## Lessons Learned
1. **Never use FlatList with `scrollEnabled={false}` inside ScrollView:** Even with `scrollEnabled={false}`, FlatList's internal VirtualizedList captures touch/scroll gestures and doesn't propagate them to the parent ScrollView. This causes the list area to appear "frozen" when combined with sticky headers. Use View + .map() instead for non-scrolling lists.

2. **VirtualizedList gesture capture is a known React Native footgun:** FlatList, SectionList, and VirtualizedList all have gesture handlers that intercept touches even when scrolling is disabled. When nesting inside another ScrollView, this creates unpredictable scroll behavior.

3. **Only use FlatList for truly long lists needing virtualization:** The performance benefit of FlatList only matters for 100+ items. For small lists (< 50 items), View + .map() is simpler, more predictable, and avoids gesture conflicts.

4. **Test scroll behavior in all screen regions after implementing sticky headers:** When using `stickyHeaderIndices`, test scrolling by touching different areas of the screen (above sticky, on sticky, below sticky) to catch gesture capture issues early.

5. **Systematic debugging pays off:** Initial hypotheses about z-index and coordinate spaces were plausible but wrong. Methodical investigation (git history, component structure, gesture handling) led to the actual root cause.
