---
work_package_id: WP08
title: Tier 3 — Composite Components
lane: "done"
dependencies:
- WP01
- WP04
- WP05
base_branch: 007-swiftui-component-library-WP05
base_commit: 8e07d86861297bbc331368eb84d6587257e651ff
created_at: '2026-02-26T08:46:26.021262+00:00'
subtasks:
- T044
- T045
- T046
- T047
- T048
- T049
- T050
- T051
- T052
phase: Phase 3 - Tier 3 Components
assignee: ''
agent: "claude-opus"
shell_pid: "46374"
review_status: "approved"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-26T07:45:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP08 – Tier 3 — Composite Components

## IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP08 --base WP06
```

---

## Objectives & Success Criteria

- Build 7 Tier 3 components: GroupedItemCard, MediaGallerySection, ItemsListControlBar, FilterMenu, SortMenu, ListSelectAllRow, ListSelectionInfo
- Create SelectionCalculations logic with tests
- All components compose lower-tier components correctly

**Success criteria:**
1. GroupedItemCard collapses/expands with animation, showing summary when collapsed
2. MediaGallerySection integrates ThumbnailGrid + ActionMenuSheet + ImageGallery
3. FilterMenu/SortMenu wrap ActionMenuSheet with filter/sort state
4. ListSelectAllRow toggles select-all correctly
5. SelectionCalculation tests pass

---

## Context & Constraints

- **Reference screenshots**: `04a_project_detail_items.png` (GroupedItemCard), `09_item_detail.png` (MediaGallerySection with ThumbnailGrid)
- **RN source**: `src/components/GroupedItemCard.tsx`, `src/components/MediaGallerySection.tsx`, `src/components/ItemsListControlBar.tsx`, `src/components/FilterMenu.tsx`, `src/components/SortMenu.tsx`
- **Prerequisites**: ItemCard (WP06), ThumbnailGrid + ImageGallery (WP04), ActionMenuSheet (WP05), ListControlBar (WP06)
- **Existing components**: TitledCard, Card, SelectorCircle, AppButton

---

## Subtasks & Detailed Guidance

### Subtask T044 – Create SelectionCalculations logic

**Purpose**: Pure functions for bulk selection state management.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Logic/SelectionCalculations.swift`
2. Define `enum SelectionCalculations` with static functions:
   - `selectAllToggle(selectedIds: Set<String>, allIds: [String]) -> Set<String>`
     - If all selected → empty set (deselect all)
     - If not all selected → Set(allIds) (select all)
   - `isAllSelected(selectedIds: Set<String>, allIds: [String]) -> Bool`
     - True if allIds is non-empty and all are in selectedIds
   - `selectedCount(_ selectedIds: Set<String>) -> Int`
   - `totalCentsForSelected(selectedIds: Set<String>, items: [(id: String, cents: Int)]) -> Int`
     - Sum of cents for items whose id is in selectedIds
   - `selectionLabel(count: Int, total: Int) -> String`
     - "\(count) of \(total) selected"

**Files**: `LedgeriOS/LedgeriOS/Logic/SelectionCalculations.swift` (new, ~35 lines)
**Parallel?**: No — used by T046, T051.

### Subtask T045 – Create SelectionCalculation tests

**Purpose**: Verify selection toggle and count logic.

**Steps**:
1. Create `LedgeriOS/LedgeriOSTests/SelectionCalculationTests.swift`
2. Test cases (~10 tests):
   - `selectAllToggle`: none selected → all, all selected → none, partial → all
   - `isAllSelected`: all → true, partial → false, empty → false
   - `totalCentsForSelected`: 2 of 3 selected → sum of 2, none → 0, all → total sum
   - `selectionLabel`: "3 of 10 selected"

**Files**: `LedgeriOS/LedgeriOSTests/SelectionCalculationTests.swift` (new, ~60 lines)
**Parallel?**: No — depends on T044.

### Subtask T046 – Create GroupedItemCard component

**Purpose**: Collapsible card grouping multiple ItemCards with summary when collapsed.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/GroupedItemCard.swift`
2. Parameters:
   - `summary`: name, sku, sourceLabel, locationLabel, notes, thumbnailUri (for collapsed summary row)
   - `countLabel: String?` — e.g., "3 items"
   - `totalLabel: String?` — e.g., "$450"
   - `items: [ItemCardData]` — array of data for individual ItemCards (define lightweight struct or use tuples)
   - Expansion: `isExpanded: Binding<Bool>? = nil`, `defaultExpanded: Bool = false`
   - Selection: `isSelected: Binding<Bool>? = nil`, `onSelectedChange: ((Bool) -> Void)?`
   - `onPress: (() -> Void)?`
3. State:
   - `@State private var internalExpanded: Bool`
4. Layout (Card wrapper):
   - **Summary row** (always visible, tappable to toggle expansion):
     - HStack: SelectorCircle (if selection mode) | Thumbnail | VStack(name, countLabel, totalLabel) | Chevron (rotates on expand)
   - **Expanded content** (if expanded):
     - VStack of ItemCard instances for each item
     - Dividers between items
   - Animation: `.animation(.default, value: expanded)` with `DisclosureGroup`-like behavior
5. Add `#Preview` with: collapsed (2 items), expanded (3 items), with selection.

**Files**: `LedgeriOS/LedgeriOS/Components/GroupedItemCard.swift` (new, ~100 lines)
**Parallel?**: Yes — after T044.

**Notes**: `ItemCardData` — consider accepting the same flat parameters as ItemCard props, or accept an array of ItemCard view builders. The simplest approach: accept a `@ViewBuilder` for expanded content.

### Subtask T047 – Create MediaGallerySection component

**Purpose**: Section for managing image/PDF attachments with add/remove/set-primary actions.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/MediaGallerySection.swift`
2. Parameters:
   - `title: String`
   - `attachments: [AttachmentRef]`
   - `maxAttachments: Int = 10`
   - `allowedKinds: [AttachmentKind] = [.image]`
   - `onAddAttachment: (() -> Void)?`
   - `onRemoveAttachment: ((AttachmentRef) -> Void)?`
   - `onSetPrimary: ((AttachmentRef) -> Void)?`
   - `emptyStateMessage: String = "No images yet"`
3. State:
   - `@State private var showGallery = false`
   - `@State private var galleryIndex: Int = 0`
   - `@State private var showAttachmentMenu = false`
   - `@State private var selectedAttachment: AttachmentRef?`
   - `@State private var menuPendingAction: (() -> Void)?`
4. Layout (TitledCard wrapper):
   - Title with "Add" button (if can add — use MediaGalleryCalculations.canAddAttachment())
   - If empty: empty state message (Typography.small, secondary, centered)
   - If has attachments: ThumbnailGrid (from WP04)
     - onThumbnailTap: open ImageGallery at tapped index
     - Long press thumbnail: show ActionMenuSheet with "Set as Primary" / "Remove"
   - ImageGallery (via .fullScreenCover)
5. **ActionMenuSheet for attachment actions**:
   - "Set as Primary" (if not already primary)
   - "Remove" (destructive)
   - Use deferred action pattern
6. Add `#Preview` with: empty, 3 images, at max limit.

**Files**: `LedgeriOS/LedgeriOS/Components/MediaGallerySection.swift` (new, ~100 lines)
**Parallel?**: Yes — after T044.

### Subtask T048 – Create ItemsListControlBar component

**Purpose**: Pre-configured ListControlBar with standard items list actions.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ItemsListControlBar.swift`
2. Parameters:
   - `searchText: Binding<String>`
   - `isSearchVisible: Binding<Bool>`
   - `onSort: () -> Void`
   - `onFilter: () -> Void`
   - `onAdd: () -> Void`
   - `activeFilterCount: Int = 0` — badge on filter button
   - `activeSortLabel: String?` — label on sort button
3. Implementation:
   - Create `[ControlAction]` array with 4 actions:
     1. Search toggle (magnifyingglass icon, iconOnly)
     2. Sort (arrow.up.arrow.down icon, standard, shows activeSortLabel)
     3. Filter (line.3.horizontal.decrease icon, standard, shows activeFilterCount badge)
     4. Add (plus icon, primary variant)
   - Pass to ListControlBar (from WP06)
4. Add `#Preview` block.

**Files**: `LedgeriOS/LedgeriOS/Components/ItemsListControlBar.swift` (new, ~50 lines)
**Parallel?**: Yes.

### Subtask T049 – Create FilterMenu component

**Purpose**: Thin wrapper around ActionMenuSheet for filter-specific usage.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/FilterMenu.swift`
2. Parameters:
   - `isPresented: Binding<Bool>`
   - `filters: [ActionMenuItem]` — pre-built filter menu items
   - `title: String = "Filter"`
3. Implementation:
   - Present ActionMenuSheet with `closeOnItemPress: false` (multi-select for filters)
   - Wrap in `.sheet()` with `.presentationDetents([.medium])`
4. Or: simply expose a static factory function that builds `[ActionMenuItem]` from `ItemFilterOption`:
   ```swift
   static func filterMenuItems(activeFilters: Set<ItemFilterOption>, onToggle: @escaping (ItemFilterOption) -> Void) -> [ActionMenuItem]
   ```
5. Add `#Preview` block.

**Files**: `LedgeriOS/LedgeriOS/Components/FilterMenu.swift` (new, ~40 lines)
**Parallel?**: Yes.

### Subtask T050 – Create SortMenu component

**Purpose**: Thin wrapper around ActionMenuSheet for sort-specific usage.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/SortMenu.swift`
2. Parameters:
   - `isPresented: Binding<Bool>`
   - `sortOptions: [ActionMenuItem]`
   - `title: String = "Sort By"`
3. Implementation:
   - Present ActionMenuSheet with `closeOnItemPress: true` (single-select for sort)
   - Show checkmark on active sort option
4. Or: static factory function:
   ```swift
   static func sortMenuItems(activeSort: ItemSortOption, onSelect: @escaping (ItemSortOption) -> Void) -> [ActionMenuItem]
   ```
5. Add `#Preview` block.

**Files**: `LedgeriOS/LedgeriOS/Components/SortMenu.swift` (new, ~40 lines)
**Parallel?**: Yes.

### Subtask T051 – Create ListSelectAllRow component

**Purpose**: Row with select-all checkbox and label.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ListSelectAllRow.swift`
2. Parameters:
   - `isChecked: Bool`
   - `label: String = "Select All"`
   - `isDisabled: Bool = false`
   - `onToggle: () -> Void`
3. Layout:
   - HStack: SelectorCircle(isSelected: isChecked, indicator: .check) | label (Typography.body) | Spacer
   - Full-width tap target → onToggle()
   - Disabled state: opacity 0.5, tap disabled
4. Add `#Preview` block with: unchecked, checked, disabled.

**Files**: `LedgeriOS/LedgeriOS/Components/ListSelectAllRow.swift` (new, ~30 lines)
**Parallel?**: Yes.

### Subtask T052 – Create ListSelectionInfo component

**Purpose**: Text display of current selection state.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ListSelectionInfo.swift`
2. Parameters:
   - `text: String` — e.g., "3 of 10 selected"
   - `onPress: (() -> Void)?`
3. Layout:
   - Text (Typography.small, secondary) — tappable if onPress provided
   - If tappable: underline or link-style appearance
4. Add `#Preview` block.

**Files**: `LedgeriOS/LedgeriOS/Components/ListSelectionInfo.swift` (new, ~20 lines)
**Parallel?**: Yes.

---

## Test Strategy

- **Framework**: Swift Testing
- **Test file**: `LedgeriOS/LedgeriOSTests/SelectionCalculationTests.swift`
- **Run command**: `xcodebuild test -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:LedgeriOSTests/SelectionCalculationTests`
- **Expected**: ~10 tests, all passing

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| GroupedItemCard expansion animation jank | Use `withAnimation` and `.animation` modifier; test in simulator |
| MediaGallerySection sheet-on-sheet (menu → gallery) | Use deferred action pattern; dismiss menu first |
| FilterMenu multi-select state management | Keep state in consuming view; FilterMenu just presents options |

---

## Review Guidance

- Compare GroupedItemCard with `04a_project_detail_items.png`
- Compare MediaGallerySection with `09_item_detail.png`
- Verify FilterMenu/SortMenu correctly wrap ActionMenuSheet
- Test select-all toggle in ListSelectAllRow

---

## Activity Log

- 2026-02-26T07:45:42Z – system – lane=planned – Prompt created.
- 2026-02-26T08:46:26Z – claude-opus – shell_pid=29743 – lane=doing – Assigned agent via workflow command
- 2026-02-26T18:17:13Z – claude-opus – shell_pid=29743 – lane=for_review – Ready for review: All 7 Tier 3 composite components implemented with SelectionCalculations logic and 15 passing tests. Build compiles cleanly.
- 2026-02-26T18:33:44Z – claude-opus – shell_pid=29743 – lane=doing – Review failed: ItemsListControlBar must wrap ListControlBar (WP06) instead of standalone implementation to prevent design drift. GroupedItemCard must accept typed ItemCard data instead of generic @ViewBuilder to maintain coupling with ItemCard component.
- 2026-02-26T18:44:31Z – claude-opus – shell_pid=29743 – lane=for_review – Review fixes applied: ItemsListControlBar now wraps ListControlBar (WP06), GroupedItemCard accepts typed ItemCardData instead of @ViewBuilder. Merged WP06 for ItemCard+ListControlBar. Build compiles, 205 tests pass.
- 2026-02-26T18:47:00Z – claude-opus – shell_pid=46374 – lane=doing – Started review via workflow command
- 2026-02-26T18:49:13Z – claude-opus – shell_pid=46374 – lane=done – Review passed: All 7 Tier 3 components + SelectionCalculations verified. Prior feedback addressed (ItemsListControlBar wraps ListControlBar, GroupedItemCard uses typed ItemCardData). 15 tests passing. Clean composition of lower-tier components.
