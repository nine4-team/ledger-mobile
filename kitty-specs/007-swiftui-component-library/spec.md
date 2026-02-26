# SwiftUI Component Library

## Overview

Build the complete shared component library for the Ledger iOS app, providing all reusable UI building blocks that screen implementations depend on. The React Native app has 84 components; 16 SwiftUI equivalents exist, 9 aren't needed in SwiftUI, and this feature covers the remaining ~45 shared components across Tiers 1–4 of the dependency graph.

Feature modals (Tier 5) — domain-specific forms like EditItemDetailsModal, SetSpaceModal, etc. — are excluded. They will be built alongside their respective screen sessions since they are tightly coupled to specific user flows. Tracking for those lives in `.plans/swiftui-migration.md`.

### Motivation

Every remaining Phase 4 screen session (Transactions, Items, Spaces, Inventory, Settings) is blocked on shared components that don't exist yet. Building the component library as a dedicated effort:

- Unblocks all screen sessions to run in parallel once components exist
- Prevents duplicated effort — multiple screen sessions would otherwise each build overlapping components
- Ensures consistent patterns (action menus, control bars, selection) across the app

### Actors

- **App user** — interacts with these components indirectly through screens
- **Developer** — consumes these components when building screens

### Reference

- Component parity audit: `.plans/component-parity-audit.md`
- RN source: `src/components/` (reference only)
- Dark mode screenshots: `reference/screenshots/dark/`
- Design tokens: `LedgeriOS/LedgeriOS/Theme/`

---

## User Scenarios & Testing

### Scenario 1: Data Display Components Render Correctly

A developer building the Items screen uses `ItemCard`, `GroupedItemCard`, `SpaceCard`, `ImageCard`, and `ThumbnailGrid`. Each component:

- Renders all visual states (empty data, partial data, full data)
- Matches the layout shown in reference screenshots
- Uses design tokens from Theme/ (no hardcoded colors, sizes, or fonts)
- Works in both light and dark mode without explicit color scheme branching
- Supports Dynamic Type accessibility scaling

**Acceptance criteria:**
- Each data display component has a SwiftUI preview showing all major states
- Visual output matches corresponding RN screenshot reference
- All text uses Typography constants; all colors use BrandColors/StatusColors

### Scenario 2: Action Menu Sheet Replaces confirmationDialog

A user long-presses or taps the menu button on an ItemCard. Instead of a plain iOS action sheet, they see a branded bottom sheet with:

- Item name as header
- Action rows with SF Symbol icons and labels
- Chevron indicators for actions with submenus
- Inline submenu expansion with checkmark selection state
- Destructive actions styled in red

**Acceptance criteria:**
- ActionMenuSheet presents via `.sheet()` with `.presentationDetents`
- Supports hierarchical menu items (parent → inline submenu)
- Supports multi-select mode (sheet stays open after selection)
- `.confirmationDialog()` usage in existing placeholder views is replaced

### Scenario 3: Form Sheet Scaffolding

A developer building the "Edit Item Details" modal wraps their form content in `FormSheet`. It provides:

- Title and optional description
- Scrollable content area
- Primary action button (with loading state)
- Optional secondary action button
- Error message display area

**Acceptance criteria:**
- FormSheet handles keyboard avoidance automatically
- Primary button shows loading indicator and disables during async operations
- Error messages appear below content, above action buttons

### Scenario 4: List Control and Bulk Selection

A user viewing the Items tab within a project sees a toolbar with search, sort, filter, and add actions. They can:

- Toggle search to filter items
- Enter bulk selection mode via the select-all control
- See a bottom bar showing selected count and bulk action button
- Clear selection with a single tap

**Acceptance criteria:**
- ListControlBar provides search field + configurable action buttons
- BulkSelectionBar shows at screen bottom with selected count and action trigger
- Selection state is managed by the parent view (components are controlled)

### Scenario 5: Budget Tracking Components

A user viewing the Budget tab sees category-level progress trackers with:

- Category name, spent and remaining amounts
- Progress bar with overflow indication for over-budget categories
- Fee categories showing "received" instead of "spent"
- Compact preview variant used inside ProjectCard

**Acceptance criteria:**
- BudgetCategoryTracker renders spent/remaining labels with correct formatting
- BudgetProgressDisplay aggregates multiple category trackers
- BudgetProgressPreview shows compact single-category view for cards

### Scenario 6: Feedback and Status Components

When the app encounters an error or loses connectivity, the user sees:

- A status banner (error/warning/info) with optional action buttons
- An error retry view with a retry button and offline indicator
- A loading screen during initial data fetches

**Acceptance criteria:**
- StatusBanner supports error, warning, and info variants with distinct styling
- ErrorRetryView provides retry callback and offline state display
- LoadingScreen shows activity indicator with optional message text

---

## Functional Requirements

### FR-1: Tier 1 — Leaf Components (no project dependencies beyond Tier 0)

Components that depend only on already-built Tier 0 components.

#### FR-1.1: ImageCard
- Display an image area with configurable aspect ratio and a content area below
- Show placeholder when no image URL is provided
- Support async image loading with loading/error states
- **Used by:** ProjectCard, SpaceCard

#### FR-1.2: SpaceCard
- Display space name, item count, checklist progress, and optional notes
- Include hero image via ImageCard
- Show checklist completion progress via ProgressBar
- Tappable with menu button

#### FR-1.3: BudgetCategoryTracker
- Display category name, spent amount label, remaining/over amount label
- Show ProgressBar with overflow indication for over-budget
- Support fee-type categories ("received" instead of "spent")

#### FR-1.4: BudgetProgressPreview
- Compact budget preview showing pinned category name, spent/remaining, and progress bar
- Used inside ProjectCard on the projects list

#### FR-1.5: FormSheet
- Reusable sheet scaffold with title, optional description, scrollable content area
- Primary action button with loading and disabled states
- Optional secondary action button
- Error message display area
- Presented via `.sheet()` with `.presentationDetents` and `.presentationDragIndicator(.visible)`

#### FR-1.6: MultiStepFormSheet
- Extends FormSheet with step indicator ("Step 2 of 3")
- Same layout as FormSheet plus current step and total steps display

#### FR-1.7: CategoryRow
- Single budget category row for settings/management screens
- Displays category name and type indicator

#### FR-1.8: BulkSelectionBar
- Fixed bottom bar showing selected item count and optional total amount
- Bulk action button and clear selection button
- Presented via `.safeAreaInset(edge: .bottom)` or toolbar placement

#### FR-1.9: ListStateControls
- Search input field portion of control bars
- Toggleable visibility with smooth animation

#### FR-1.10: ThumbnailGrid
- Grid of image thumbnails with configurable column count
- Support overlay badges (primary indicator, count)
- Tappable thumbnails for full-screen viewing

#### FR-1.11: ImageGallery
- Full-screen image viewer with swipe navigation between images
- Pinch-to-zoom and pan gestures
- Presented via `.fullScreenCover()` (justified exception to bottom-sheet convention)

#### FR-1.12: StatusBanner
- Sticky banner in error, warning, or info variant
- Optional action buttons
- Auto-dismiss or manual dismiss

#### FR-1.13: ErrorRetryView
- Error message display with retry button
- Offline indicator when device has no connectivity

#### FR-1.14: LoadingScreen
- Full-screen loading indicator with optional message text
- Uses system ProgressView

#### FR-1.15: DraggableCard
- Card with drag handle for reorder operations
- Supports disabled state and active (dragging) state

#### FR-1.16: InfoCard
- Information display card for contextual help/tips

### FR-2: Tier 2 — Intermediate Components

Components that depend on Tier 0–1.

#### FR-2.1: ActionMenuSheet
- Bottom sheet presenting hierarchical action menu items
- Each item has icon (SF Symbol), label, optional chevron for submenus
- Submenus expand inline with checkmark selection state
- Support destructive item styling (red text)
- Support multi-select mode (closeOnItemPress=false keeps sheet open)
- Optional title/header
- Replaces all `.confirmationDialog()` usage for action menus

#### FR-2.2: BudgetProgressDisplay
- Full budget progress summary composing multiple BudgetCategoryTracker rows
- Action button for budget management

#### FR-2.3: ListControlBar
- Generic search bar + configurable action buttons
- Horizontally scrollable when actions overflow
- Search field toggle with animation

#### FR-2.4: ItemCard
- Item card with thumbnail, metadata lines (name, SKU, source, location, price)
- SelectorCircle for multi-select
- Bookmark toggle
- Menu button triggering ActionMenuSheet
- Optional warning message display
- Expandable/tappable

### FR-3: Tier 3 — Composite Components

Components that depend on Tier 0–2.

#### FR-3.1: TransactionCard
- Transaction list item with source, amount, date
- Badge row (transaction type, reimbursement type, receipt, needs review, category)
- SelectorCircle for multi-select
- Menu button for context actions
- Notes preview (italic, 2-line limit)

#### FR-3.2: GroupedItemCard
- Collapsible card grouping multiple ItemCards
- Summary row (name, count, total) when collapsed
- Expands to show individual ItemCards
- Group-level selection via SelectorCircle

#### FR-3.3: MediaGallerySection
- Section managing image/PDF attachments
- Add, remove, and set-primary actions via ActionMenuSheet
- ThumbnailGrid display with full-screen viewer via ImageGallery
- Configurable max attachments and allowed file types

#### FR-3.4: ItemsListControlBar
- Items-specific control bar extending ListControlBar
- Pre-configured with search, sort, filter, and add actions

#### FR-3.5: FilterMenu
- Thin wrapper around ActionMenuSheet for filter-specific usage
- Maintains filter selection state

#### FR-3.6: SortMenu
- Thin wrapper around ActionMenuSheet for sort-specific usage
- Shows active sort option

#### FR-3.7: ListSelectAllRow
- Row with select-all checkbox and label
- Supports disabled state

#### FR-3.8: ListSelectionInfo
- Text display of current selection state
- Tappable for selection actions

### FR-4: Tier 4 — List Containers

Components that compose Tier 0–3 components into full list experiences.

#### FR-4.1: SharedItemsList
- Reusable items list supporting three modes:
  - **Standalone**: fetches its own data from Firestore
  - **Embedded**: receives items array from parent
  - **Picker**: item selection for linking flows
- Handles grouping, selection, filtering, sorting, bulk actions
- Integrates ItemsListControlBar, GroupedItemCard, ItemCard, FilterMenu, SortMenu, BulkSelectionBar, ActionMenuSheet

#### FR-4.2: SharedTransactionsList
- Reusable transaction list with same patterns as SharedItemsList
- Filtering, sorting, selection, bulk actions
- Integrates ListControlBar, FilterMenu, SortMenu, TransactionCard, ActionMenuSheet

#### FR-4.3: DraggableCardList
- Generic drag-to-reorder list using SwiftUI List with `.onMove(perform:)`
- Used for category and template reordering in settings

---

## Success Criteria

1. All components build without errors and have SwiftUI previews showing representative states
2. Components use design tokens exclusively — no hardcoded colors, fonts, spacing, or dimensions
3. All data display components match their corresponding RN reference screenshots in layout and visual hierarchy
4. ActionMenuSheet fully replaces `.confirmationDialog()` for action menus across the app
5. SharedItemsList and SharedTransactionsList support all three modes (standalone, embedded, picker)
6. Components follow the bottom-sheet-first convention documented in CLAUDE.md
7. Every component with non-trivial logic has pure calculation functions extracted into `Logic/` with test coverage
8. Light and dark mode render correctly via adaptive asset catalog colors without `@Environment(\.colorScheme)` branching
9. All components are accessible — support VoiceOver labels, Dynamic Type, and sufficient contrast

---

## Key Entities

### ActionMenuItem
Represents a single action in ActionMenuSheet:
- `key`: unique identifier
- `label`: display text
- `icon`: SF Symbol name (optional)
- `subactions`: child menu items (optional)
- `selectedSubactionKey`: currently selected child (optional)
- `destructive`: whether to style as destructive action
- `onPress`: action handler

### AttachmentRef
Already defined in data models — represents an image/PDF attachment with URL, kind, and metadata. Used by MediaGallerySection and ThumbnailGrid.

---

## Assumptions

1. All Tier 0 components (Card, TitledCard, Badge, DetailRow, ProgressBar, SelectorCircle, AppButton, FormField, SegmentedControl, CollapsibleSection, BudgetProgressView) are already built and stable
2. Design tokens in Theme/ are complete and won't change during this work
3. Components will be consumed by screen implementations in Phase 4 sessions 2–7
4. Firebase/Firestore dependencies are limited to SharedItemsList and SharedTransactionsList standalone mode — all other components are pure UI
5. Tier 5 feature modals (EditItemDetailsModal, SetSpaceModal, ReassignToProjectModal, etc.) will be built during their respective screen sessions, not as part of this feature

---

## Scope Boundaries

### In Scope
- All Tier 1–4 components from the parity audit (~45 components)
- Pure logic functions for component calculations (extracted to `Logic/`)
- Unit tests for all pure logic functions
- SwiftUI previews for all components
- Replacing `.confirmationDialog()` with ActionMenuSheet in existing views

### Out of Scope
- Tier 5 feature modals (14 domain-specific modals — tracked separately in migration plan)
- Screen implementations (Phase 4 sessions)
- Creation flows (new project/transaction/item/space forms)
- Navigation wiring between screens
- Firestore service layer changes
- Settings screens

---

## Dependencies

- **Tier 0 components** — already built (Card, Badge, AppButton, etc.)
- **Design tokens** — Theme/ directory (BrandColors, StatusColors, Spacing, Typography, Dimensions)
- **Data models** — Project, Transaction, Item, Space, BudgetCategory, AttachmentRef (all built in Phase 2)
- **State managers** — ProjectContext, AccountContext (built in Phase 2/3)

---

## Build Order

Components must be built in dependency order. Each tier depends only on prior tiers.

**Tier 1** (16 components — all buildable in parallel):
ImageCard, SpaceCard, BudgetCategoryTracker, BudgetProgressPreview, FormSheet, MultiStepFormSheet, CategoryRow, BulkSelectionBar, ListStateControls, ThumbnailGrid, ImageGallery, StatusBanner, ErrorRetryView, LoadingScreen, DraggableCard, InfoCard

**Tier 2** (4 components — buildable in parallel after Tier 1):
ActionMenuSheet, BudgetProgressDisplay, ListControlBar, ItemCard

**Tier 3** (8 components — buildable in parallel after Tier 2):
TransactionCard, GroupedItemCard, MediaGallerySection, ItemsListControlBar, FilterMenu, SortMenu, ListSelectAllRow, ListSelectionInfo

**Tier 4** (3 components — after Tier 3):
SharedItemsList, SharedTransactionsList, DraggableCardList
