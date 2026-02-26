# Work Packages: SwiftUI Component Library

**Inputs**: Design documents from `/kitty-specs/007-swiftui-component-library/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, component-parity-audit (`.plans/component-parity-audit.md`)

**Tests**: Required for all pure Logic functions. Components tested via SwiftUI previews only.

**Organization**: 76 fine-grained subtasks (`T001`–`T076`) roll up into 10 work packages (`WP01`–`WP10`). Organized by tier (topological dependency order) with tiers split by domain for manageable WP sizes. Each WP is independently deliverable and testable.

**Prompt Files**: Each work package references a matching prompt file in `tasks/`.

## Subtask Format: `[Txxx] [P?] Description`
- **[P]** indicates the subtask can proceed in parallel (different files/components).
- All component files live in `LedgeriOS/LedgeriOS/Components/`.
- All logic files live in `LedgeriOS/LedgeriOS/Logic/`.
- All test files live in `LedgeriOS/LedgeriOSTests/`.
- All model/enum types live in `LedgeriOS/LedgeriOS/Models/Shared/`.

---

## Work Package WP01: Shared Types & Currency Formatting (Priority: P0)

**Goal**: Define all new shared types (ActionMenuItem, ControlAction, FormSheetAction, StatusBannerVariant, ItemFilterOption, ItemSortOption, ItemsListMode) and extract shared CurrencyFormatting utilities with tests.
**Independent Test**: All new types compile; CurrencyFormatting tests pass.
**Prompt**: `tasks/WP01-shared-types-and-currency.md`

### Included Subtasks
- [x] T001 [P] Create `ActionMenuItem` and `ActionMenuSubitem` structs in `Models/Shared/ActionMenuItem.swift`
- [x] T002 [P] Create `ControlAction` struct and `ControlActionAppearance` enum in `Models/Shared/ControlAction.swift`
- [x] T003 [P] Create `FormSheetAction` struct in `Models/Shared/FormSheetAction.swift`
- [x] T004 [P] Create `StatusBannerVariant` enum in `Models/Shared/StatusBannerVariant.swift`
- [x] T005 [P] Create `ItemFilterOption` and `ItemSortOption` enums in `Models/Shared/ItemListEnums.swift`
- [x] T006 [P] Create `ItemsListMode` enum in `Models/Shared/ItemsListMode.swift`
- [x] T007 Create `CurrencyFormatting.swift` in `Logic/` — shared `formatCents()` helper (check existing `BudgetDisplayCalculations.formatCentsAsDollars` to avoid duplication)
- [x] T008 Create `CurrencyFormattingTests.swift` — tests for locale-aware formatting, edge cases (zero, negative, large amounts)

### Implementation Notes
- Check if `BudgetDisplayCalculations.formatCentsAsDollars` already covers enough; if so, just re-export or delegate. If budget-specific, create a general-purpose `CurrencyFormatting` enum.
- All types must be `Identifiable` where required for SwiftUI `ForEach`.
- `ActionMenuItem.onPress` is optional (items with subactions may not have a direct press handler).

### Parallel Opportunities
- T001–T006 are all independent file creations — fully parallel.
- T007 depends on reading existing BudgetDisplayCalculations first.
- T008 depends on T007.

### Dependencies
- None (starting package).

### Risks & Mitigations
- Duplication with existing formatting — inspect `BudgetDisplayCalculations` first.

---

## Work Package WP02: Tier 1 — Budget & Data Display Components (Priority: P0)

**Goal**: Build budget components (BudgetCategoryTracker, BudgetProgressPreview, CategoryRow) and data display components (ImageCard, SpaceCard, InfoCard, DraggableCard) with their logic functions and tests.
**Independent Test**: All 7 components render in SwiftUI previews; BudgetTrackerCalculation tests pass.
**Prompt**: `tasks/WP02-tier1-budget-and-display.md`

### Included Subtasks
- [ ] T009 Create `BudgetTrackerCalculations.swift` in `Logic/` — formatting for category tracker (display name, spent/remaining labels, percentage, overflow detection, fee-type support)
- [ ] T010 Create `BudgetTrackerCalculationTests.swift` — tests for spent/remaining formatting, overflow, fee categories, zero budget edge cases (~15 tests)
- [ ] T011 [P] Create `BudgetCategoryTracker.swift` — category name, spent/remaining labels, ProgressBar with overflow, fee support
- [ ] T012 [P] Create `BudgetProgressPreview.swift` — compact single-category preview for ProjectCard
- [ ] T013 [P] Create `CategoryRow.swift` — single category row for settings screens
- [ ] T014 [P] Create `ImageCard.swift` — async image with placeholder, configurable aspect ratio, loading/error states
- [ ] T015 [P] Create `SpaceCard.swift` — space name, item count, checklist progress via ProgressBar, hero image via ImageCard, menu button
- [ ] T016 [P] Create `InfoCard.swift` — information display card for contextual help/tips
- [ ] T017 [P] Create `DraggableCard.swift` — card with drag handle, disabled/active states

### Implementation Notes
- BudgetCategoryTracker and BudgetProgressPreview share logic via BudgetTrackerCalculations.
- ImageCard uses AsyncImage (no third-party libs). Provide placeholder view when URL is nil.
- SpaceCard composes ImageCard + ProgressBar (both available after this WP).
- Follow existing Card.swift pattern: generic ViewBuilder, theme tokens only.

### Parallel Opportunities
- T011–T017 are all independent components — fully parallel after T009–T010.

### Dependencies
- Depends on WP01 (CurrencyFormatting for budget labels).

### Risks & Mitigations
- AsyncImage caching behavior — rely on URLSession defaults; no custom cache layer.

---

## Work Package WP03: Tier 1 — Form Sheets & Feedback Components (Priority: P0)

**Goal**: Build form sheet scaffolds (FormSheet, MultiStepFormSheet) and all feedback/status components (StatusBanner, ErrorRetryView, LoadingScreen).
**Independent Test**: All 5 components render in SwiftUI previews with all state variants.
**Prompt**: `tasks/WP03-tier1-forms-and-feedback.md`

### Included Subtasks
- [x] T018 [P] Create `FormSheet.swift` — reusable sheet scaffold (title, description, scrollable content, primary/secondary buttons with loading states, error display area)
- [x] T019 [P] Create `MultiStepFormSheet.swift` — extends FormSheet with step indicator ("Step X of Y")
- [x] T020 [P] Create `StatusBanner.swift` — error/warning/info variants, optional action buttons, auto-dismiss or manual dismiss
- [x] T021 [P] Create `ErrorRetryView.swift` — error message, retry button, offline indicator
- [x] T022 [P] Create `LoadingScreen.swift` — full-screen ProgressView with optional message text

### Implementation Notes
- FormSheet uses `.sheet()` + `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)` per CLAUDE.md convention.
- FormSheet primary button uses AppButton with loading/disabled states.
- StatusBanner: auto-dismiss via `.task { try? await Task.sleep(...) }` when configured.
- ErrorRetryView: simple VStack with retry callback — no network monitoring (Firestore handles offline).
- LoadingScreen: centered ProgressView with optional Text below.

### Parallel Opportunities
- All 5 components are fully independent — can be built in parallel.

### Dependencies
- Depends on WP01 (FormSheetAction type).

### Risks & Mitigations
- Keyboard avoidance in FormSheet — SwiftUI handles this automatically for TextField inside ScrollView. Test with real keyboard.

---

## Work Package WP04: Tier 1 — Selection, Controls & Media Components (Priority: P0)

**Goal**: Build selection controls (BulkSelectionBar, ListStateControls), media components (ThumbnailGrid, ImageGallery), and their logic functions with tests.
**Independent Test**: All 4 components render in previews; MediaGalleryCalculation tests pass.
**Prompt**: `tasks/WP04-tier1-selection-and-media.md`

### Included Subtasks
- [ ] T023 Create `MediaGalleryCalculations.swift` in `Logic/` — attachment validation (max count, allowed kinds), grid column calculation, primary image detection
- [ ] T024 Create `MediaGalleryCalculationTests.swift` — tests for validation, column calc, primary detection (~10 tests)
- [ ] T025 [P] Create `BulkSelectionBar.swift` — fixed bottom bar via `.safeAreaInset(edge: .bottom)`, selected count, optional total amount, bulk action button, clear button
- [ ] T026 [P] Create `ListStateControls.swift` — search input field with toggleable visibility and smooth animation
- [ ] T027 [P] Create `ThumbnailGrid.swift` — configurable column grid of image thumbnails, overlay badges (primary indicator, count), tappable
- [ ] T028 Create `ImageGallery.swift` — full-screen image viewer via `.fullScreenCover()`, TabView with page style, pinch-to-zoom (MagnificationGesture), pan (DragGesture), double-tap toggle

### Implementation Notes
- BulkSelectionBar uses `.safeAreaInset(edge: .bottom)` with transition animation (per R4 research).
- ImageGallery is the justified `.fullScreenCover()` exception. Create internal `ZoomableImage` view with gesture state management (per R3 research).
- ThumbnailGrid uses LazyVGrid with configurable GridItem columns.
- ListStateControls: TextField with search icon, animated show/hide.

### Parallel Opportunities
- T025–T027 are independent. T028 is more complex but independent of others.

### Dependencies
- Depends on WP01 (CurrencyFormatting for BulkSelectionBar total amount display).

### Risks & Mitigations
- ImageGallery gesture complexity — keep gestures simple initially (MagnificationGesture + DragGesture), can refine later.

---

## Work Package WP05: Tier 2 — ActionMenuSheet (Priority: P1)

**Goal**: Build the ActionMenuSheet component with its logic functions, tests, and replace all existing `.confirmationDialog()` usage.
**Independent Test**: ActionMenuSheet presents correctly; deferred action pattern works; `.confirmationDialog()` replaced in 3 views.
**Prompt**: `tasks/WP05-tier2-action-menu-sheet.md`

### Included Subtasks
- [x] T029 Create `ActionMenuCalculations.swift` in `Logic/` — `resolveMenuSelection()`, expansion state logic, deferred action helpers
- [x] T030 Create `ActionMenuCalculationTests.swift` — tests for selection resolution, expansion toggle, destructive item detection (~12 tests)
- [x] T031 Create `ActionMenuSheet.swift` — hierarchical menu in `.sheet()`, inline submenu expansion with checkmark selection, destructive styling, multi-select mode, deferred action execution via `.onDismiss`
- [x] T032 Replace `.confirmationDialog()` in `ProjectsPlaceholderView.swift` with ActionMenuSheet
- [x] T033 Replace `.confirmationDialog()` in `InventoryPlaceholderView.swift` with ActionMenuSheet
- [x] T034 Replace `.confirmationDialog()` in `ProjectDetailView.swift` with ActionMenuSheet (keep destructive delete as `.confirmationDialog()`)

### Implementation Notes
- ActionMenuSheet uses deferred action pattern (R1): `@State pendingAction`, dismiss sheet, execute in `.onDismiss`.
- Submenu expansion: `@State expandedItemKey: String?` — only one submenu open at a time (R5).
- Multi-select mode: `closeOnItemPress: Bool` parameter — when false, sheet stays open after selection.
- For ProjectDetailView T034: "Delete Project" should remain as `.confirmationDialog()` since it's a destructive confirmation — per CLAUDE.md convention.

### Parallel Opportunities
- T032–T034 are independent replacements (can run in parallel after T031).

### Dependencies
- Depends on WP01 (ActionMenuItem type).

### Risks & Mitigations
- Deferred action timing — `.onDismiss` fires after animation completes. Test with real sheet presentation.
- Sheet-on-sheet prevention — if an action inside ActionMenuSheet opens another sheet, dismiss first.

---

## Work Package WP06: Tier 2 — ListControlBar, BudgetProgressDisplay & ItemCard (Priority: P1)

**Goal**: Build remaining Tier 2 components: ListControlBar, BudgetProgressDisplay, and ItemCard with logic and tests.
**Independent Test**: All 3 components render in previews; ItemCardCalculation tests pass.
**Prompt**: `tasks/WP06-tier2-list-controls-and-itemcard.md`

### Included Subtasks
- [ ] T035 Create `ItemCardCalculations.swift` in `Logic/` — badge computation (status, category, index), metadata line formatting, controlled/uncontrolled selection state helpers
- [ ] T036 Create `ItemCardCalculationTests.swift` — tests for badge logic, metadata formatting, selection state (~15 tests)
- [ ] T037 [P] Create `ListControlBar.swift` — generic search bar + configurable action buttons (standard, icon-only, tile variants), horizontal layout
- [ ] T038 [P] Create `BudgetProgressDisplay.swift` — composes multiple BudgetCategoryTracker rows + action button for budget management
- [ ] T039 Create `ItemCard.swift` — thumbnail, metadata lines (name, SKU, source, location, price), badge header, SelectorCircle, bookmark toggle, menu button triggering ActionMenuSheet, controlled/uncontrolled selection, expandable

### Implementation Notes
- ItemCard uses the controlled/uncontrolled selection pattern (R2): optional `Binding<Bool>?` with `@State` fallback.
- ListControlBar uses ControlAction struct for button configuration. ScrollView horizontal for overflow.
- BudgetProgressDisplay composes BudgetCategoryTracker rows from WP02 in a VStack with dividers.
- ItemCard menu button triggers ActionMenuSheet from WP05 using the deferred action pattern.

### Parallel Opportunities
- T037 and T038 are independent. T039 depends on T035 logic being ready.

### Dependencies
- Depends on WP02 (BudgetCategoryTracker), WP04 (ListStateControls), WP05 (ActionMenuSheet).
- Depends on WP01 (ControlAction, ActionMenuItem types).

### Risks & Mitigations
- ItemCard complexity — it's the most prop-heavy component. Follow the RN props interface closely but use Swift conventions (labeled parameters, optional bindings).

---

## Work Package WP07: Tier 3 — TransactionCard & Transaction Logic (Priority: P1)

**Goal**: Build TransactionCard with its calculation logic, tests, and transaction badge color extensions to StatusColors.
**Independent Test**: TransactionCard renders all badge variants in preview; TransactionCardCalculation tests pass.
**Prompt**: `tasks/WP07-tier3-transaction-card.md`

### Included Subtasks
- [ ] T040 Check existing `StatusColors.swift` for transaction badge colors; add missing ones (transactionPurchase, transactionSale, transactionReturn, transactionToInventory, reimbursement, needsReview, emailReceipt) with asset catalog colorsets if needed
- [ ] T041 Create `TransactionCardCalculations.swift` in `Logic/` — type-based badge color mapping, amount formatting with sign, date formatting, notes truncation
- [ ] T042 Create `TransactionCardCalculationTests.swift` — tests for badge color selection, amount formatting, date formatting (~15 tests)
- [ ] T043 Create `TransactionCard.swift` — source, amount, date, badge row (type/reimbursement/receipt/review/category), SelectorCircle for multi-select, menu button, notes preview (italic, 2-line limit), controlled/uncontrolled selection

### Implementation Notes
- Transaction badge colors: check StatusColors first. R7 research identified potentially missing colors. Add only what's missing.
- Badge row: horizontal ScrollView of Badge components for each applicable attribute.
- Same controlled/uncontrolled selection pattern as ItemCard (R2).
- Notes preview: italic Text with `.lineLimit(2)`.
- Amount: display with sign prefix (+/-) based on transaction type.

### Parallel Opportunities
- T040 (StatusColors) can run in parallel with T041–T042 (logic).

### Dependencies
- Depends on WP05 (ActionMenuSheet for menu button).
- Depends on WP01 (CurrencyFormatting, ActionMenuItem).

### Risks & Mitigations
- Asset catalog color additions — need to create colorsets in `Assets.xcassets/Colors/` for new StatusColors.

---

## Work Package WP08: Tier 3 — GroupedItemCard, MediaGallerySection & List Helpers (Priority: P1)

**Goal**: Build remaining Tier 3 components: GroupedItemCard, MediaGallerySection, ItemsListControlBar, FilterMenu, SortMenu, ListSelectAllRow, ListSelectionInfo, and selection logic.
**Independent Test**: All 7 components render in previews; SelectionCalculation tests pass.
**Prompt**: `tasks/WP08-tier3-composite-components.md`

### Included Subtasks
- [ ] T044 Create `SelectionCalculations.swift` in `Logic/` — select-all toggle logic, selection count, total amount computation from selected items
- [ ] T045 Create `SelectionCalculationTests.swift` — tests for toggle, count, total computation (~10 tests)
- [ ] T046 [P] Create `GroupedItemCard.swift` — collapsible card grouping multiple ItemCards, summary row (name, count, total) when collapsed, expand to show ItemCards, group-level selection via SelectorCircle
- [ ] T047 [P] Create `MediaGallerySection.swift` — ThumbnailGrid display + ActionMenuSheet for add/remove/set-primary actions + ImageGallery for full-screen viewing, configurable max attachments and allowed file types
- [ ] T048 [P] Create `ItemsListControlBar.swift` — pre-configured ListControlBar with search, sort, filter, and add actions
- [ ] T049 [P] Create `FilterMenu.swift` — thin wrapper around ActionMenuSheet for filter-specific usage with filter state
- [ ] T050 [P] Create `SortMenu.swift` — thin wrapper around ActionMenuSheet for sort-specific usage, shows active sort option
- [ ] T051 [P] Create `ListSelectAllRow.swift` — row with select-all checkbox (SelectorCircle) and label, disabled state
- [ ] T052 [P] Create `ListSelectionInfo.swift` — text display of current selection state, tappable for selection actions

### Implementation Notes
- GroupedItemCard: controlled/uncontrolled expansion pattern (same as selection — optional Binding with State fallback).
- MediaGallerySection composes ThumbnailGrid (WP04) + ActionMenuSheet (WP05) + ImageGallery (WP04). TitledCard wrapper from existing components.
- FilterMenu/SortMenu are thin wrappers — present ActionMenuSheet with pre-configured items. Maintain internal `@State` for active filter/sort.
- ItemsListControlBar pre-configures ListControlBar (WP06) with 4 standard actions.

### Parallel Opportunities
- T046–T052 are all independent — fully parallel after T044–T045.

### Dependencies
- Depends on WP05 (ActionMenuSheet), WP06 (ListControlBar, ItemCard).
- Depends on WP04 (ThumbnailGrid, ImageGallery).
- Depends on WP01 (types).

### Risks & Mitigations
- MediaGallerySection image picker integration — for now, define the `onAddAttachment` callback interface but actual camera/photo picker is out of scope (handled by consuming screens).

---

## Work Package WP09: Tier 3 — List Filter/Sort Logic (Priority: P1)

**Goal**: Build the filter, sort, and grouping logic that SharedItemsList and SharedTransactionsList will consume.
**Independent Test**: All ListFilterSort tests pass.
**Prompt**: `tasks/WP09-tier3-filter-sort-logic.md`

### Included Subtasks
- [ ] T053 Create `ListFilterSortCalculations.swift` in `Logic/` — item filter predicates (bookmarked, from-inventory, to-return, returned, no-sku, no-name, no-project-price, no-image, no-transaction), item sort comparators (created-desc/asc, alphabetical-asc/desc), transaction filter/sort equivalents
- [ ] T054 Create item grouping logic in `ListFilterSortCalculations.swift` — group items by name+SKU for GroupedItemCard, compute group summary (count, total)
- [ ] T055 Create `ListFilterSortCalculationTests.swift` — tests for each filter predicate, each sort comparator, grouping logic, empty input edge cases (~25 tests)

### Implementation Notes
- Filter predicates: pure functions `(ScopedItem) -> Bool` for each ItemFilterOption case.
- Sort comparators: return `[ScopedItem]` sorted by the given ItemSortOption.
- Grouping: returns `[(key: String, items: [ScopedItem])]` grouped by name+SKU match.
- Transaction filters/sorts follow the same pattern but for Transaction type.
- All functions are static methods on `enum ListFilterSortCalculations`.

### Parallel Opportunities
- T053 and T054 can be developed together (same file).

### Dependencies
- Depends on WP01 (ItemFilterOption, ItemSortOption enums).

### Risks & Mitigations
- ScopedItem type — verify it exists in the codebase or if items need scoping. The RN app uses `ScopedItem` which enriches Item with project context.

---

## Work Package WP10: Tier 4 — List Containers (Priority: P2)

**Goal**: Build the three list container components: SharedItemsList (3 modes), SharedTransactionsList, and DraggableCardList.
**Independent Test**: SharedItemsList renders in all 3 modes; SharedTransactionsList renders with filter/sort; DraggableCardList supports drag-to-reorder.
**Prompt**: `tasks/WP10-tier4-list-containers.md`

### Included Subtasks
- [ ] T056 Create `SharedItemsList.swift` — standalone mode: Firestore listener, pull-to-refresh via `.refreshable()`, empty state
- [ ] T057 Extend `SharedItemsList.swift` — embedded mode: receives items array, custom item press, custom menu items
- [ ] T058 Extend `SharedItemsList.swift` — picker mode: eligibility check, add single/multiple, added IDs tracking, add button
- [ ] T059 Wire SharedItemsList integration: ListControlBar + ItemsListControlBar (search/sort/filter/add), GroupedItemCard + ItemCard rendering, FilterMenu + SortMenu, BulkSelectionBar, ActionMenuSheet context menus
- [ ] T060 Create `SharedTransactionsList.swift` — filtering, sorting, selection, bulk actions, ListControlBar, FilterMenu, SortMenu, TransactionCard, ActionMenuSheet
- [ ] T061 Create `DraggableCardList.swift` — generic drag-to-reorder list using SwiftUI List + `.onMove(perform:)`, used for category and template reordering
- [ ] T062 Build verification — compile all components, run all tests, verify previews for SharedItemsList (3 modes), SharedTransactionsList, DraggableCardList

### Implementation Notes
- SharedItemsList uses `ItemsListMode` enum (WP01) to switch behavior at key decision points (R6 research).
- Standalone mode: Firestore snapshot listener via existing ProjectContext pattern. `.refreshable()` for pull-to-refresh.
- Embedded mode: items passed as parameter. No Firestore dependency.
- Picker mode: eligibility check callback, `addedIds: Set<String>` for already-added items, disabled state for ineligible items.
- SharedTransactionsList follows the same patterns as SharedItemsList but simpler (no grouping, no picker mode initially).
- DraggableCardList: SwiftUI `List` with `.onMove(perform:)` and `EditButton()`. Each row is a DraggableCard (WP02).

### Parallel Opportunities
- T060 (SharedTransactionsList) and T061 (DraggableCardList) are independent of T056–T059 (SharedItemsList).

### Dependencies
- Depends on ALL prior WPs — this is the capstone package.
- Key dependencies: WP06 (ItemCard, ListControlBar), WP07 (TransactionCard), WP08 (GroupedItemCard, MediaGallerySection, FilterMenu, SortMenu, ItemsListControlBar, BulkSelectionBar, ListSelectAllRow, ListSelectionInfo), WP09 (filter/sort/grouping logic).

### Risks & Mitigations
- SharedItemsList complexity — it's the most complex component. Follow the mode enum pattern strictly (R6).
- Firestore listener setup for standalone mode — follow existing ProjectContext.activate() pattern for subscription management.
- Performance — use LazyVStack for large lists. Test with 100+ items.

---

## Dependency & Execution Summary

```
WP01 (Shared Types) ─────────────────────────────────────────────┐
  │                                                                │
  ├── WP02 (Budget & Display) ─────────────────┐                  │
  ├── WP03 (Forms & Feedback) ──────────────── │ ──── (parallel)  │
  ├── WP04 (Selection & Media) ────────────────┤                  │
  │                                             │                  │
  ├── WP05 (ActionMenuSheet) ──────────────────┤                  │
  │                                             │                  │
  ├── WP09 (Filter/Sort Logic) ────────────────┤                  │
  │                                             │                  │
  ├── WP06 (ListControlBar, ItemCard) ─────────┤ ← needs WP02,04,05
  │                                             │
  ├── WP07 (TransactionCard) ──────────────────┤ ← needs WP05
  │                                             │
  ├── WP08 (Composite Components) ─────────────┤ ← needs WP04,05,06
  │                                             │
  └── WP10 (List Containers) ──────────────────┘ ← needs ALL above
```

- **Phase 1 (parallel)**: WP01
- **Phase 2 (parallel after WP01)**: WP02, WP03, WP04, WP05, WP09
- **Phase 3 (parallel after Phase 2)**: WP06, WP07, WP08
- **Phase 4 (after Phase 3)**: WP10

**MVP Scope**: WP01–WP06 (types, Tier 1 components, ActionMenuSheet, ListControlBar, ItemCard). This unlocks the Items tab implementation in Phase 4.

---

## Subtask Index (Reference)

| Subtask | Summary | WP | Priority | Parallel? |
|---------|---------|-----|----------|-----------|
| T001 | ActionMenuItem + ActionMenuSubitem types | WP01 | P0 | Yes |
| T002 | ControlAction + ControlActionAppearance types | WP01 | P0 | Yes |
| T003 | FormSheetAction type | WP01 | P0 | Yes |
| T004 | StatusBannerVariant enum | WP01 | P0 | Yes |
| T005 | ItemFilterOption + ItemSortOption enums | WP01 | P0 | Yes |
| T006 | ItemsListMode enum | WP01 | P0 | Yes |
| T007 | CurrencyFormatting logic | WP01 | P0 | No |
| T008 | CurrencyFormatting tests | WP01 | P0 | No |
| T009 | BudgetTrackerCalculations logic | WP02 | P0 | No |
| T010 | BudgetTrackerCalculation tests | WP02 | P0 | No |
| T011 | BudgetCategoryTracker component | WP02 | P0 | Yes |
| T012 | BudgetProgressPreview component | WP02 | P0 | Yes |
| T013 | CategoryRow component | WP02 | P0 | Yes |
| T014 | ImageCard component | WP02 | P0 | Yes |
| T015 | SpaceCard component | WP02 | P0 | Yes |
| T016 | InfoCard component | WP02 | P0 | Yes |
| T017 | DraggableCard component | WP02 | P0 | Yes |
| T018 | FormSheet component | WP03 | P0 | Yes |
| T019 | MultiStepFormSheet component | WP03 | P0 | Yes |
| T020 | StatusBanner component | WP03 | P0 | Yes |
| T021 | ErrorRetryView component | WP03 | P0 | Yes |
| T022 | LoadingScreen component | WP03 | P0 | Yes |
| T023 | MediaGalleryCalculations logic | WP04 | P0 | No |
| T024 | MediaGalleryCalculation tests | WP04 | P0 | No |
| T025 | BulkSelectionBar component | WP04 | P0 | Yes |
| T026 | ListStateControls component | WP04 | P0 | Yes |
| T027 | ThumbnailGrid component | WP04 | P0 | Yes |
| T028 | ImageGallery component | WP04 | P0 | Yes |
| T029 | ActionMenuCalculations logic | WP05 | P1 | No |
| T030 | ActionMenuCalculation tests | WP05 | P1 | No |
| T031 | ActionMenuSheet component | WP05 | P1 | No |
| T032 | Replace confirmationDialog in ProjectsPlaceholderView | WP05 | P1 | Yes |
| T033 | Replace confirmationDialog in InventoryPlaceholderView | WP05 | P1 | Yes |
| T034 | Replace confirmationDialog in ProjectDetailView | WP05 | P1 | Yes |
| T035 | ItemCardCalculations logic | WP06 | P1 | No |
| T036 | ItemCardCalculation tests | WP06 | P1 | No |
| T037 | ListControlBar component | WP06 | P1 | Yes |
| T038 | BudgetProgressDisplay component | WP06 | P1 | Yes |
| T039 | ItemCard component | WP06 | P1 | No |
| T040 | Transaction badge StatusColors additions | WP07 | P1 | Yes |
| T041 | TransactionCardCalculations logic | WP07 | P1 | No |
| T042 | TransactionCardCalculation tests | WP07 | P1 | No |
| T043 | TransactionCard component | WP07 | P1 | No |
| T044 | SelectionCalculations logic | WP08 | P1 | No |
| T045 | SelectionCalculation tests | WP08 | P1 | No |
| T046 | GroupedItemCard component | WP08 | P1 | Yes |
| T047 | MediaGallerySection component | WP08 | P1 | Yes |
| T048 | ItemsListControlBar component | WP08 | P1 | Yes |
| T049 | FilterMenu component | WP08 | P1 | Yes |
| T050 | SortMenu component | WP08 | P1 | Yes |
| T051 | ListSelectAllRow component | WP08 | P1 | Yes |
| T052 | ListSelectionInfo component | WP08 | P1 | Yes |
| T053 | Item filter predicates + sort comparators | WP09 | P1 | No |
| T054 | Item grouping logic | WP09 | P1 | No |
| T055 | ListFilterSort tests | WP09 | P1 | No |
| T056 | SharedItemsList — standalone mode | WP10 | P2 | No |
| T057 | SharedItemsList — embedded mode | WP10 | P2 | No |
| T058 | SharedItemsList — picker mode | WP10 | P2 | No |
| T059 | SharedItemsList integration wiring | WP10 | P2 | No |
| T060 | SharedTransactionsList | WP10 | P2 | Yes |
| T061 | DraggableCardList | WP10 | P2 | Yes |
| T062 | Build verification — all components | WP10 | P2 | No |
