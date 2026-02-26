---
work_package_id: WP06
title: Tier 2 — ListControlBar, BudgetProgressDisplay & ItemCard
lane: "doing"
dependencies:
- WP01
- WP02
base_branch: 007-swiftui-component-library-WP06-merge-base
base_commit: 015640ed825f3e34b778751239a6d4950da33aac
created_at: '2026-02-26T08:44:37.381814+00:00'
subtasks:
- T035
- T036
- T037
- T038
- T039
phase: Phase 3 - Tier 2 Remaining
assignee: ''
agent: ''
shell_pid: "26369"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T07:45:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP06 – Tier 2 — ListControlBar, BudgetProgressDisplay & ItemCard

## IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP06 --base WP05
```

(WP05 is the latest dependency in the chain; it includes WP01's changes.)

---

## Objectives & Success Criteria

- Build 3 remaining Tier 2 components: ListControlBar, BudgetProgressDisplay, ItemCard
- Create ItemCardCalculations logic with tests
- ItemCard supports controlled/uncontrolled selection, bookmark toggle, and menu via ActionMenuSheet

**Success criteria:**
1. ListControlBar renders search + action buttons with horizontal scrolling
2. BudgetProgressDisplay composes multiple BudgetCategoryTracker rows
3. ItemCard matches `inventory_screen.png` and `04a_project_detail_items.png` screenshots
4. ItemCardCalculation tests pass

---

## Context & Constraints

- **Reference screenshots**: `reference/screenshots/dark/inventory_screen.png` (ItemCard layout), `04a_project_detail_items.png` (ItemCard in project context), `03_project_detail_budget.png` (BudgetProgressDisplay)
- **RN source**: `src/components/ItemCard.tsx` (most complex — ~300 lines), `src/components/ListControlBar.tsx`, `src/components/budget/BudgetProgressDisplay.tsx`
- **Research**: R2 (controlled/uncontrolled selection pattern with optional `Binding<Bool>?`)
- **Prerequisites**: BudgetCategoryTracker (WP02), ListStateControls (WP04), ActionMenuSheet (WP05), ControlAction type (WP01)
- **Existing components**: SelectorCircle, AppButton, Badge, Card

---

## Subtasks & Detailed Guidance

### Subtask T035 – Create ItemCardCalculations logic

**Purpose**: Pure functions for ItemCard badge computation, metadata line formatting, and selection state.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Logic/ItemCardCalculations.swift`
2. Define `enum ItemCardCalculations` with static functions:
   - `badgeItems(statusLabel: String?, budgetCategoryName: String?, indexLabel: String?) -> [(text: String, color: Color)]`
     - Returns array of (text, color) tuples for Badge components
     - Status: uses StatusColors based on status value
     - Category: brand primary color
     - Index: secondary color
   - `metadataLines(name: String?, sku: String?, sourceLabel: String?, locationLabel: String?, priceLabel: String?, stackSkuAndSource: Bool) -> [String]`
     - Returns formatted metadata strings, filtering out nils
     - If stackSkuAndSource: combine SKU and source on one line
   - `thumbnailUrl(from urlString: String?) -> URL?`
     - Safe URL construction from optional string
   - `selectedState(isSelected: Binding<Bool>?, internalSelected: Bool) -> Bool`
     - Returns binding value if provided, else internal state

**Files**: `LedgeriOS/LedgeriOS/Logic/ItemCardCalculations.swift` (new, ~50 lines)
**Parallel?**: No — used by T039.

### Subtask T036 – Create ItemCardCalculation tests

**Purpose**: Verify badge computation and metadata formatting.

**Steps**:
1. Create `LedgeriOS/LedgeriOSTests/ItemCardCalculationTests.swift`
2. Test cases (~15 tests):
   - `badgeItems`: all present → 3 badges, only status → 1 badge, all nil → empty
   - `metadataLines`: all fields → 5 lines, some nil → filtered, stackSkuAndSource → combined
   - `thumbnailUrl`: valid URL string → URL, nil → nil, empty string → nil
   - `selectedState`: with binding → binding value, without binding → internal value

**Files**: `LedgeriOS/LedgeriOSTests/ItemCardCalculationTests.swift` (new, ~80 lines)
**Parallel?**: No — depends on T035.

### Subtask T037 – Create ListControlBar component

**Purpose**: Generic search bar + configurable action buttons. Used by ItemsListControlBar and SharedTransactionsList.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ListControlBar.swift`
2. Parameters:
   - `searchText: Binding<String>`
   - `isSearchVisible: Binding<Bool>`
   - `actions: [ControlAction]`
   - `searchPlaceholder: String = "Search..."`
3. Layout (VStack, spacing: Spacing.sm):
   - **Search row**: ListStateControls (from WP04) — visible when isSearchVisible is true
   - **Action row**: ScrollView(.horizontal) > HStack of action buttons:
     - `.standard` appearance: AppButton with title + icon
     - `.iconOnly` appearance: fixed 44pt square, icon only, secondary background
     - `.tile` appearance: dashed border square with icon
     - Each button: tap → action.action(), isDisabled, isActive styling
4. Hide action row when search is visible and screen is compact (optional — depends on design).
5. Add `#Preview` block with: 2 actions, 4+ actions (scrollable), with search visible.

**Files**: `LedgeriOS/LedgeriOS/Components/ListControlBar.swift` (new, ~80 lines)
**Parallel?**: Yes.

### Subtask T038 – Create BudgetProgressDisplay component

**Purpose**: Full budget progress summary composing multiple BudgetCategoryTracker rows.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/BudgetProgressDisplay.swift`
2. Parameters:
   - `categories: [BudgetProgress.CategoryProgress]`
   - `onManageBudget: (() -> Void)?`
3. Layout (VStack, spacing: Spacing.md):
   - For each category: BudgetCategoryTracker (from WP02) with:
     - name, spentCents, budgetCents, categoryType
   - Dividers between categories
   - Optional "Manage Budget" button (AppButton, secondary) at bottom
4. Add `#Preview` block with: 2 categories, over-budget category, empty categories.

**Files**: `LedgeriOS/LedgeriOS/Components/BudgetProgressDisplay.swift` (new, ~45 lines)
**Parallel?**: Yes.

### Subtask T039 – Create ItemCard component

**Purpose**: The most important data display component — item card with thumbnail, metadata, badges, selection, bookmark, and context menu. Used throughout the app.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ItemCard.swift`
2. Parameters (following RN props closely):
   - `name: String`
   - `sku: String?`
   - `sourceLabel: String?`
   - `locationLabel: String?`
   - `notes: String?`
   - `priceLabel: String?`
   - `indexLabel: String?`
   - `statusLabel: String?`
   - `budgetCategoryName: String?`
   - `thumbnailUri: String?`
   - `stackSkuAndSource: Bool = false`
   - Selection: `isSelected: Binding<Bool>? = nil`, `defaultSelected: Bool = false`
   - `bookmarked: Bool = false`
   - `onBookmarkPress: (() -> Void)?`
   - `onPress: (() -> Void)?`
   - `menuItems: [ActionMenuItem] = []`
   - `warningMessage: String?`
3. State:
   - `@State private var internalSelected: Bool` (initialized from defaultSelected)
   - `@State private var showMenu = false`
   - `@State private var menuPendingAction: (() -> Void)?`
4. Layout (Card wrapper):
   - **Badge header** (if any badges): HStack of Badge components from ItemCardCalculations.badgeItems()
   - **Main content** (HStack):
     - **Left**: SelectorCircle (if in selection mode — determined by parent providing isSelected binding)
     - **Thumbnail** (if thumbnailUri): AsyncImage, square, 60x60, clipped with corner radius
     - **Metadata** (VStack, flex):
       - Name (Typography.body, bold)
       - Each metadata line from ItemCardCalculations.metadataLines() (Typography.small, secondary)
       - Notes (Typography.small, italic, lineLimit: 2) if present
     - **Right actions** (VStack):
       - Bookmark toggle (heart icon, filled if bookmarked)
       - Menu button ("ellipsis") → opens ActionMenuSheet
   - **Warning** (if warningMessage): orange text below main content
5. **Selection behavior**: Tap card → if onPress, call onPress. Long press or SelectorCircle tap → toggle selection.
6. **Menu**: Use deferred action pattern with ActionMenuSheet:
   ```swift
   .sheet(isPresented: $showMenu, onDismiss: {
       menuPendingAction?()
       menuPendingAction = nil
   }) {
       ActionMenuSheet(items: menuItems) { action in
           menuPendingAction = action
           showMenu = false
       }
       .presentationDetents([.medium])
       .presentationDragIndicator(.visible)
   }
   ```
7. Add `#Preview` block with:
   - Minimal (name only)
   - Full (all metadata, thumbnail, badges, bookmark)
   - Selected state
   - With warning message
   - With menu items

**Files**: `LedgeriOS/LedgeriOS/Components/ItemCard.swift` (new, ~160 lines)
**Parallel?**: No — depends on T035 logic, T037 (ListControlBar pattern reference).

**Notes**:
- This is the most complex component so far. Match `inventory_screen.png` closely.
- The controlled/uncontrolled selection duality (R2) is critical — test both paths.
- Menu items come from the consuming view. ItemCard just presents them.

---

## Test Strategy

- **Framework**: Swift Testing
- **Test file**: `LedgeriOS/LedgeriOSTests/ItemCardCalculationTests.swift`
- **Run command**: `xcodebuild test -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:LedgeriOSTests/ItemCardCalculationTests`
- **Expected**: ~15 tests, all passing

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| ItemCard prop explosion | Keep parameters flat; use defaults for optionals |
| Controlled/uncontrolled selection confusion | Document clearly; test both paths in preview |
| ListControlBar horizontal overflow | Use ScrollView(.horizontal) with showsIndicators: false |

---

## Review Guidance

- Compare ItemCard with `inventory_screen.png` and `04a_project_detail_items.png`
- Test selection toggling in both controlled (binding) and uncontrolled (default) modes
- Verify ActionMenuSheet integration works with deferred action pattern
- Check that ListControlBar action buttons handle all 3 appearance variants

---

## Activity Log

- 2026-02-26T07:45:42Z – system – lane=planned – Prompt created.
