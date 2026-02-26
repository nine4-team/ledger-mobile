---
work_package_id: WP10
title: Tier 4 — List Containers
lane: "doing"
dependencies: []
base_branch: main
base_commit: 3a044626dd14f2950ac39d4df386bcd0c3018c1f
created_at: '2026-02-26T18:51:48.581904+00:00'
subtasks:
- T056
- T057
- T058
- T059
- T060
- T061
- T062
phase: Phase 4 - Capstone
assignee: ''
agent: "claude-opus"
shell_pid: "82809"
review_status: "has_feedback"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-26T07:45:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP10 – Tier 4 — List Containers

## IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.

---

## Review Feedback

**Reviewed by**: nine4-team
**Status**: ❌ Changes Requested
**Date**: 2026-02-26

## Review Feedback — WP10: Tier 4 List Containers

**Reviewer:** claude-opus
**Verdict:** Changes requested
**Build/Tests:** Confirmed — build succeeds, 260 tests pass.
**DraggableCardList:** Approved — clean, well-structured, no issues.

---

### CRITICAL — Must fix before merge

**Issue 1: Picker mode data setup is unreachable (SharedItemsList.swift:390-397)**

```swift
case .picker(_, _, _, _):
    if let accountId, case .standalone(let scope) = mode {  // ← NEVER TRUE
        await setupStandaloneListener(scope: scope)
    } else {
        isLoading = false  // ← picker with Firestore data shows empty
    }
```

The `case .standalone` pattern match will never succeed when already inside the `.picker` case. Picker mode that needs Firestore data will always fall through to `isLoading = false` with no items loaded.

**Fix:** Picker mode needs its own scope parameter or a shared data-fetch path. One approach:
```swift
case .picker(let scope, _, _, _):
    if let scope {
        await setupStandaloneListener(scope: scope)
    } else {
        isLoading = false
    }
```
This requires updating `ItemsListMode.picker` to include an optional `ListScope`.

---

**Issue 2: activeFilter vs activeFilters mismatch — BOTH list components**

Affects: `SharedItemsList.swift:17-19,453` AND `SharedTransactionsList.swift:135-137,398`

Both components have:
- `@State private var activeFilter` (single value, used in `processedItems`/`processedTransactions`)
- `@State private var activeFilters: Set<...>` (populated by `toggleFilter()`, shown in UI badge count)

`toggleFilter()` adds/removes from the Set, then does `activeFilter = activeFilters.first ?? .all` — so multi-select UI but only the first filter is ever applied. The filter badge shows "Filter (2)" but only one filter works.

**Fix:** Either:
- (a) Remove `activeFilters` Set entirely and make filter single-select (simpler, matches the RN app's behavior for most filter types), or
- (b) Update `applyAllFilters()`/`applyAll()` to accept `Set<FilterOption>` and apply all selected filters with AND logic.

Option (a) is recommended — the RN app uses single-select for the primary filter dimension.

---

**Issue 3: Picker "Add Selected" doesn't clear selection (SharedItemsList.swift:365-367)**

After tapping "Add Selected", `onAddSelected?()` fires but `selectedIds` is not cleared. The UI continues showing items as selected after they've been added.

**Fix:** Add `selectedIds.removeAll()` after the callback:
```swift
AppButton(title: "Add Selected") {
    onAddSelected?()
    selectedIds.removeAll()
}
```

---

### MODERATE — Should fix, but non-blocking individually

**Issue 4: Unstable UUID fallback in grouped cards (SharedItemsList.swift:321)**

`id: item.id ?? UUID().uuidString` generates a new ID on every render, causing SwiftUI to treat each render as a new item (broken list diffing, lost scroll position, unnecessary re-renders).

**Fix:** Guard against nil IDs upstream, or use a deterministic fallback like `"item-\(index)"`.

---

**Issue 5: Empty string IDs in selection system (SharedItemsList.swift:210, SharedTransactionsList.swift:302)**

`item.id ?? ""` / `transaction.id ?? ""` creates ghost entries in `selectedIds`. A nil-ID item becomes selectable with empty string key, which could conflict across items.

**Fix:** Skip rendering items/transactions with nil IDs, or guard before adding to selection:
```swift
guard let itemId = item.id else { continue }
```

---

**Issue 6: Bulk actions menu not extensible (SharedTransactionsList.swift:207-214)**

The bulk action menu is hardcoded to only "Clear Selection". The RN reference has export CSV + other context-aware bulk actions. The component should accept bulk action items as a parameter (matching how `getMenuItems` works for individual items).

**Fix:** Add parameter: `var getBulkMenuItems: (() -> [ActionMenuItem])?` and merge with the default clear-selection item.

---

### Summary

| Component | Verdict | Issues |
|-----------|---------|--------|
| SharedItemsList | Changes requested | 3 critical, 2 moderate |
| SharedTransactionsList | Changes requested | 1 critical (shared pattern), 2 moderate |
| DraggableCardList | Approved | Clean |

Focus on Issues 1-3 (critical). Issues 4-6 should also be fixed but are lower priority.


## Implementation Command

```bash
spec-kitty implement WP10 --base WP08
```

(WP08 is the latest in the dependency chain, incorporating WP01–WP06 changes.)

---

## Objectives & Success Criteria

- Build 3 Tier 4 list container components: SharedItemsList, SharedTransactionsList, DraggableCardList
- SharedItemsList supports 3 operating modes (standalone, embedded, picker)
- Full build verification — all components compile, all tests pass

**Success criteria:**
1. SharedItemsList renders in all 3 modes with correct behavior
2. SharedTransactionsList renders with filtering, sorting, selection, bulk actions
3. DraggableCardList supports drag-to-reorder
4. Full test suite passes (all Logic tests from WP01–WP09)
5. All component previews render without errors

---

## Context & Constraints

- **RN reference**: `src/components/SharedItemsList.tsx` (~500 lines — most complex component), `src/components/SharedTransactionsList.tsx`, `src/components/DraggableCardList.tsx`
- **Research**: R6 (SharedItemsList mode architecture — single view with `ItemsListMode` enum)
- **Prerequisites**: ALL prior WPs — this is the capstone package
  - WP01: types (ItemsListMode, ActionMenuItem, ControlAction, filter/sort enums)
  - WP04: BulkSelectionBar
  - WP05: ActionMenuSheet
  - WP06: ItemCard, ListControlBar
  - WP07: TransactionCard
  - WP08: GroupedItemCard, ItemsListControlBar, FilterMenu, SortMenu, ListSelectAllRow, ListSelectionInfo, MediaGallerySection
  - WP09: ListFilterSortCalculations (filter, sort, grouping logic)
- **State management**: Standalone mode needs Firestore listener — follow existing `ProjectContext.activate()` pattern
- **Performance**: Use `LazyVStack` for large lists; test with 100+ items

---

## Subtasks & Detailed Guidance

### Subtask T056 – Create SharedItemsList — standalone mode

**Purpose**: SharedItemsList that fetches its own data from Firestore for a given scope.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/SharedItemsList.swift`
2. Parameters:
   - `mode: ItemsListMode`
   - `onItemPress: ((String) -> Void)?` — default navigation handler
   - `getMenuItems: ((Item) -> [ActionMenuItem])?` — menu items per item
   - `emptyMessage: String = "No items yet"`
3. State:
   - `@State private var items: [Item] = []`
   - `@State private var searchText = ""`
   - `@State private var isSearchVisible = false`
   - `@State private var activeFilter: ItemFilterOption = .all`
   - `@State private var activeSort: ItemSortOption = .createdDesc`
   - `@State private var selectedIds: Set<String> = []`
   - `@State private var showFilterMenu = false`
   - `@State private var showSortMenu = false`
   - `@State private var showBulkActionMenu = false`
   - `@State private var isLoading = true`
   - `@State private var error: String?`
   - `@State private var listener: ListenerRegistration?`
4. Standalone mode implementation:
   - On `.task {}`: Start Firestore snapshot listener based on scope
   - Extract scope from `ItemsListMode.standalone(scopeConfig:)`:
     - Use `ListScope` to determine collection path (project items vs inventory vs all)
   - Set items from snapshot; handle errors
   - `.refreshable {}`: Re-query Firestore
   - `.onDisappear {}`: Remove listener
5. Layout (VStack):
   - ItemsListControlBar (search, sort, filter, add)
   - ListSelectAllRow (if items exist)
   - Content:
     - If isLoading: LoadingScreen
     - If error: ErrorRetryView
     - If items empty: empty state message
     - Else: LazyVStack of ItemCard / GroupedItemCard rows
       - Use ListFilterSortCalculations.applyAllFilters() for filtering/sorting
       - Use ListFilterSortCalculations.groupItems() for grouping decision
   - BulkSelectionBar (via .safeAreaInset) when selectedIds is non-empty
6. FilterMenu / SortMenu presented as sheets
7. BulkActionMenu: ActionMenuSheet with bulk operations

**Files**: `LedgeriOS/LedgeriOS/Components/SharedItemsList.swift` (new, starts at ~200 lines)
**Parallel?**: No — sequential build-up.

**Notes**:
- This is the most complex component. Build incrementally: layout first, then data flow, then interactions.
- Firestore listener: follow the pattern in `ProjectContext.swift` for snapshot listeners.
- Import FirebaseFirestore for standalone mode's snapshot listener.

### Subtask T057 – Extend SharedItemsList — embedded mode

**Purpose**: Mode where items are passed as a parameter (no Firestore dependency).

**Steps**:
1. Extend `SharedItemsList.swift`
2. Embedded mode behavior:
   - Items come from `ItemsListMode.embedded(items:onItemPress:)` parameter
   - No Firestore listener (skip `.task {}` listener setup)
   - `onItemPress` comes from mode parameters
   - Filtering, sorting, selection, bulk actions still work (same UI)
3. Add mode switch in the view body:
   ```swift
   switch mode {
   case .standalone(let scopeConfig):
       // Firestore listener setup
   case .embedded(let items, let onItemPress):
       // Use provided items directly
       self.items = items // Set in .onChange or .task
   case .picker(...):
       // Handled in T058
   }
   ```
4. Ensure filter/sort/search still work on embedded items.

**Files**: `LedgeriOS/LedgeriOS/Components/SharedItemsList.swift` (extend)
**Parallel?**: No — extends T056.

### Subtask T058 – Extend SharedItemsList — picker mode

**Purpose**: Item selection mode for linking items to transactions/spaces.

**Steps**:
1. Extend `SharedItemsList.swift`
2. Picker mode behavior:
   - Items come from Firestore (like standalone) or can be embedded
   - `eligibilityCheck`: function that determines if an item can be selected
   - `addedIds`: Set of already-added item IDs (shown as disabled/checked)
   - `onAddSingle`: callback when single item is selected
   - `onAddSelected`: callback for bulk add of selected items
3. UI differences:
   - Each item shows:
     - Green check if in addedIds (already added)
     - Selectable if eligible (pass eligibilityCheck)
     - Disabled if not eligible
   - Bottom bar: "Add X Selected" button (instead of bulk action menu)
   - Tapping item: if `onAddSingle`, call it immediately. If not, toggle selection.
4. Hide irrelevant controls (sort may be simplified, filter may be hidden).

**Files**: `LedgeriOS/LedgeriOS/Components/SharedItemsList.swift` (extend)
**Parallel?**: No — extends T057.

### Subtask T059 – Wire SharedItemsList integration

**Purpose**: Connect all sub-components and verify the full interaction flow.

**Steps**:
1. Wire FilterMenu presentation:
   - Build filter menu items from ItemFilterOption.allCases
   - Show active filter count on ItemsListControlBar
2. Wire SortMenu presentation:
   - Build sort menu items from ItemSortOption.allCases
   - Show active sort label
3. Wire BulkSelectionBar:
   - Show when selectedIds is non-empty
   - Display count and optional total cents
   - "Actions" button → ActionMenuSheet with bulk operations (placeholder — actual bulk operations defined by consuming views)
4. Wire ListSelectAllRow:
   - Toggle all visible (filtered) items
   - Use SelectionCalculations.selectAllToggle()
5. Wire search:
   - SearchText → ListFilterSortCalculations.applySearch()
   - Toggle search visibility via ItemsListControlBar
6. Add comprehensive `#Preview` blocks:
   - Standalone mode with mock items
   - Embedded mode with provided items
   - Picker mode with eligibility check
   - Empty state
   - Loading state
   - Error state

**Files**: `LedgeriOS/LedgeriOS/Components/SharedItemsList.swift` (extend/finalize)
**Parallel?**: No — integration step.

### Subtask T060 – Create SharedTransactionsList component

**Purpose**: Transaction list with filtering, sorting, selection, and bulk actions.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/SharedTransactionsList.swift`
2. Parameters:
   - `transactions: [Transaction]`
   - `onTransactionPress: ((String) -> Void)?`
   - `getMenuItems: ((Transaction) -> [ActionMenuItem])?`
   - `emptyMessage: String = "No transactions yet"`
3. State: Similar to SharedItemsList but simpler (no grouping, no picker mode)
   - `searchText`, `isSearchVisible`, `activeFilter`, `activeSort`, `selectedIds`
   - `showFilterMenu`, `showSortMenu`, `showBulkActionMenu`
4. Layout:
   - ListControlBar (generic, not ItemsListControlBar) with search + sort + filter actions
   - LazyVStack of TransactionCard instances
   - FilterMenu / SortMenu for transaction-specific options
   - BulkSelectionBar when selection active
5. Filtering: Add transaction filter/sort functions to ListFilterSortCalculations (or create `TransactionFilterSortCalculations`):
   - Filters: all, needs-review, has-receipt, by-type (purchase/sale/return)
   - Sorts: date-desc, date-asc, amount-desc, amount-asc
6. Add `#Preview` with: populated list, empty, with selection.

**Files**: `LedgeriOS/LedgeriOS/Components/SharedTransactionsList.swift` (new, ~150 lines)
**Parallel?**: Yes — independent of T056–T059.

**Notes**: Simpler than SharedItemsList. No grouping, no picker mode. Follow the same patterns.

### Subtask T061 – Create DraggableCardList component

**Purpose**: Generic drag-to-reorder list for settings screens (category reordering, template reordering).

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/DraggableCardList.swift`
2. Parameters:
   - `items: Binding<[T]>` where T: Identifiable
   - `content: (T) -> DraggableCard` or `@ViewBuilder` per item
   - `onReorder: (([T]) -> Void)?`
3. Implementation:
   - `List` with `ForEach` over items
   - `.onMove(perform:)` handler that:
     - Updates the binding
     - Calls onReorder with new order
   - `EditButton()` in toolbar or auto-edit mode
   - Each row uses DraggableCard (from WP02) for consistent styling
4. Alternative: Simply use `List` + `.onMove` directly, making this a convenience wrapper.
5. Add `#Preview` with: 5 items, reorderable.

**Files**: `LedgeriOS/LedgeriOS/Components/DraggableCardList.swift` (new, ~50 lines)
**Parallel?**: Yes — independent of T056–T059.

### Subtask T062 – Build verification

**Purpose**: Full build + test verification for the entire component library.

**Steps**:
1. Run full build: `xcodebuild build -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e'`
2. Run all tests: `xcodebuild test -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e'`
3. Verify all tests pass:
   - CurrencyFormattingTests (WP01)
   - BudgetTrackerCalculationTests (WP02)
   - MediaGalleryCalculationTests (WP04)
   - ActionMenuCalculationTests (WP05)
   - ItemCardCalculationTests (WP06)
   - TransactionCardCalculationTests (WP07)
   - SelectionCalculationTests (WP08)
   - ListFilterSortCalculationTests (WP09)
4. Verify all component previews render:
   - Open each component file and confirm `#Preview` renders
5. Check for any compiler warnings or deprecation notices.

**Files**: No new files — verification only.
**Parallel?**: No — final step.

---

## Test Strategy

- **Full test run**: `xcodebuild test -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e'`
- **Expected**: All ~100+ tests pass across all test files
- **Manual verification**: SharedItemsList in simulator with all 3 modes
- **Performance**: Test SharedItemsList with 100+ items — verify smooth scrolling

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| SharedItemsList complexity (500+ lines) | Build incrementally: layout → data → interactions |
| Firestore listener setup in standalone mode | Follow ProjectContext.activate() pattern exactly |
| Performance with large lists | Use LazyVStack; avoid re-rendering full list on selection change |
| Picker mode eligibility logic | Keep eligibility check as a simple callback; consuming view owns the logic |

---

## Review Guidance

- Test SharedItemsList in all 3 modes (standalone, embedded, picker)
- Verify filtering/sorting works correctly with all options
- Check bulk selection flow: select → bulk actions menu → execute action
- Test DraggableCardList reorder in simulator (drag handle + move)
- Verify full test suite passes (T062)
- Check for memory leaks: Firestore listener cleanup in standalone mode

---

## Activity Log

- 2026-02-26T07:45:42Z – system – lane=planned – Prompt created.
- 2026-02-26T18:51:48Z – claude-opus – shell_pid=51830 – lane=doing – Assigned agent via workflow command
- 2026-02-26T19:12:26Z – claude-opus – shell_pid=51830 – lane=for_review – Ready for review: SharedItemsList (3 modes), SharedTransactionsList, DraggableCardList. Build succeeds, 260 tests pass across 16 suites.
- 2026-02-26T19:14:01Z – claude-opus – shell_pid=78353 – lane=doing – Started review via workflow command
- 2026-02-26T19:17:05Z – claude-opus – shell_pid=78353 – lane=planned – Moved to planned
- 2026-02-26T19:17:53Z – claude-opus – shell_pid=82809 – lane=doing – Started implementation via workflow command
