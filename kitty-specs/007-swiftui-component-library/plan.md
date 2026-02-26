# Implementation Plan: SwiftUI Component Library

**Branch**: `main` | **Date**: 2026-02-25 | **Spec**: [kitty-specs/007-swiftui-component-library/spec.md](kitty-specs/007-swiftui-component-library/spec.md)
**Input**: Feature specification from `/kitty-specs/007-swiftui-component-library/spec.md`

## Summary

Build ~31 shared SwiftUI components (Tiers 1–4) that all remaining Phase 4 screen sessions depend on. Components span data display cards, action menus, form scaffolds, budget trackers, list control bars, bulk selection, feedback/status, and full list containers. Each tier depends only on prior tiers. Pure calculation logic is extracted into `Logic/` with Swift Testing coverage. All components use the established design token system (Theme/) and follow the bottom-sheet-first convention.

## Technical Context

**Language/Version**: Swift 5.9+, SwiftUI
**Primary Dependencies**: Firebase Swift SDK (Auth, Firestore, Storage), GoogleSignIn-iOS — but only SharedItemsList/SharedTransactionsList touch Firestore; all other components are pure UI
**Storage**: Firestore (via existing service layer) — no new persistence work
**Testing**: Swift Testing framework (`@Suite`, `@Test`, `#expect`)
**Target Platform**: iOS 17+
**Project Type**: Mobile (native SwiftUI)
**Performance Goals**: 60 fps scrolling for list containers; lazy loading for image-heavy views
**Constraints**: Offline-capable (Firestore handles caching), no third-party image libraries (AsyncImage only), design tokens only (no hardcoded values)
**Scale/Scope**: ~31 components across 4 tiers, ~8 Logic files, ~8 test files

## Constitution Check

*No constitution file found. Section skipped.*

## Project Structure

### Documentation (this feature)

```
kitty-specs/007-swiftui-component-library/
├── plan.md              # This file
├── research.md          # Phase 0 output — SwiftUI adaptation patterns
├── data-model.md        # Phase 1 output — component interfaces
├── quickstart.md        # Phase 1 output — build verification steps
└── tasks.md             # Phase 2 output (NOT created by /spec-kitty.plan)
```

### Source Code (repository root)

```
LedgeriOS/LedgeriOS/
├── Components/              # All new component .swift files (existing: 13 files)
│   ├── ImageCard.swift
│   ├── SpaceCard.swift
│   ├── BudgetCategoryTracker.swift
│   ├── BudgetProgressPreview.swift
│   ├── FormSheet.swift
│   ├── MultiStepFormSheet.swift
│   ├── CategoryRow.swift
│   ├── BulkSelectionBar.swift
│   ├── ListStateControls.swift
│   ├── ThumbnailGrid.swift
│   ├── ImageGallery.swift
│   ├── StatusBanner.swift
│   ├── ErrorRetryView.swift
│   ├── LoadingScreen.swift
│   ├── DraggableCard.swift
│   ├── InfoCard.swift
│   ├── ActionMenuSheet.swift
│   ├── BudgetProgressDisplay.swift
│   ├── ListControlBar.swift
│   ├── ItemCard.swift
│   ├── TransactionCard.swift
│   ├── GroupedItemCard.swift
│   ├── MediaGallerySection.swift
│   ├── ItemsListControlBar.swift
│   ├── FilterMenu.swift
│   ├── SortMenu.swift
│   ├── ListSelectAllRow.swift
│   ├── ListSelectionInfo.swift
│   ├── SharedItemsList.swift
│   ├── SharedTransactionsList.swift
│   └── DraggableCardList.swift
├── Logic/                   # Pure calculation functions (existing: 5 files)
│   ├── ActionMenuCalculations.swift      # Menu selection resolution
│   ├── BudgetTrackerCalculations.swift   # Category tracker formatting
│   ├── ItemCardCalculations.swift        # Badge computation, metadata formatting
│   ├── TransactionCardCalculations.swift # Badge colors, amount formatting
│   ├── ListFilterSortCalculations.swift  # Filter/sort logic for shared lists
│   ├── MediaGalleryCalculations.swift    # Attachment validation, grid layout
│   ├── SelectionCalculations.swift       # Bulk selection state helpers
│   └── CurrencyFormatting.swift          # Shared cents→dollar formatting
├── Theme/                   # Design tokens (no changes expected)
└── Models/                  # Data models (no changes expected)

LedgeriOS/LedgeriOSTests/
├── ActionMenuCalculationTests.swift
├── BudgetTrackerCalculationTests.swift
├── ItemCardCalculationTests.swift
├── TransactionCardCalculationTests.swift
├── ListFilterSortCalculationTests.swift
├── MediaGalleryCalculationTests.swift
├── SelectionCalculationTests.swift
└── CurrencyFormattingTests.swift
```

**Structure Decision**: All new components go into the existing flat `Components/` directory. Logic functions go into the existing `Logic/` directory. Tests go into the existing `LedgeriOSTests/` directory. No new directories needed — follows the established project convention.

## Complexity Tracking

*No constitution violations to justify.*

---

## Work Package Strategy

**Organization**: By tier (topological dependency order)
**Rationale**: Maximizes parallelism within each tier; clear dependency gates between tiers. Mirrors the build order from the spec and parity audit.

Each WP follows the same internal structure (matching the phase 4 pattern):
1. **Step 1 (parallel):** Logic files + tests — extract pure functions, run tests
2. **Step 2 (parallel after Step 1):** Components — create SwiftUI views with previews
3. **Step 3:** Build verification — compile, run all tests, verify previews

### WP1: Tier 1 — Leaf Components (16 components)

All Tier 1 components depend only on already-built Tier 0 components. They can all be built in parallel within this WP.

**Step 1 — Logic + Tests:**
- `BudgetTrackerCalculations.swift` — formatting for BudgetCategoryTracker + BudgetProgressPreview (display name, spent/remaining labels, percentage, overflow)
- `MediaGalleryCalculations.swift` — attachment validation, grid column calculation
- `CurrencyFormatting.swift` — shared `formatCents()` helper (extract from existing BudgetDisplayCalculations if duplicated, or create new)
- Tests for all above (~25 tests)

**Step 2 — Components (parallel, grouped by domain):**

*Data Display:*
- `ImageCard` — async image with placeholder, configurable aspect ratio, loading/error states
- `SpaceCard` — space name, item count, checklist progress via ProgressBar, hero image via ImageCard
- `ThumbnailGrid` — configurable column grid, overlay badges, tappable thumbnails
- `DraggableCard` — card with drag handle, disabled/active states
- `InfoCard` — information display card

*Budget:*
- `BudgetCategoryTracker` — category name, spent/remaining labels, ProgressBar with overflow, fee support
- `BudgetProgressPreview` — compact single-category preview for ProjectCard
- `CategoryRow` — single category row for settings screens

*Sheets/Forms:*
- `FormSheet` — reusable sheet scaffold (title, description, content, primary/secondary buttons, error)
- `MultiStepFormSheet` — FormSheet + step indicator

*Controls/Selection:*
- `BulkSelectionBar` — fixed bottom bar via `.safeAreaInset()`, selected count, clear/action buttons
- `ListStateControls` — search input with toggle animation

*Feedback:*
- `StatusBanner` — error/warning/info variants, optional actions, auto/manual dismiss
- `ErrorRetryView` — error message, retry button, offline indicator
- `LoadingScreen` — ProgressView with optional message

*Media:*
- `ImageGallery` — full-screen image viewer via `.fullScreenCover()`, pinch-to-zoom, swipe navigation

**Step 3 — Build verification**

### WP2: Tier 2 — Intermediate Components (4 components)

Depends on WP1 completion. All Tier 2 components can be built in parallel.

**Step 1 — Logic + Tests:**
- `ActionMenuCalculations.swift` — `resolveMenuSelection()`, deferred action helpers, expansion state logic
- `ItemCardCalculations.swift` — badge computation (status, category, index), metadata line formatting, controlled/uncontrolled selection state
- Tests for all above (~20 tests)

**Step 2 — Components:**
- `ActionMenuSheet` — hierarchical menu in `.sheet()`, inline submenu expansion, checkmark selection, destructive styling, multi-select mode, deferred action execution via `.onDismiss`
- `BudgetProgressDisplay` — composes multiple BudgetCategoryTracker rows + action button
- `ListControlBar` — search field + configurable action buttons (standard, icon-only, tile), horizontal layout
- `ItemCard` — thumbnail, metadata lines, badge header, SelectorCircle, bookmark toggle, menu via ActionMenuSheet

**Step 3 — Build verification + replace `.confirmationDialog()` in existing placeholder views**

### WP3: Tier 3 — Composite Components (8 components)

Depends on WP2 completion. All Tier 3 components can be built in parallel.

**Step 1 — Logic + Tests:**
- `TransactionCardCalculations.swift` — type-based badge color mapping, amount formatting, date formatting
- `ListFilterSortCalculations.swift` — filter predicate functions, sort comparators, group-by logic
- `SelectionCalculations.swift` — select-all toggle, selection count, total amount computation
- Tests for all above (~25 tests)

**Step 2 — Components:**
- `TransactionCard` — source, amount, date, badge row (type/reimbursement/receipt/review/category), selection, menu
- `GroupedItemCard` — collapsible card grouping ItemCards, summary row, group-level selection
- `MediaGallerySection` — ThumbnailGrid + ActionMenuSheet for add/remove/set-primary, ImageGallery for full-screen
- `ItemsListControlBar` — pre-configured ListControlBar with search/sort/filter/add actions
- `FilterMenu` — thin wrapper around ActionMenuSheet for filter usage
- `SortMenu` — thin wrapper around ActionMenuSheet for sort usage
- `ListSelectAllRow` — select-all checkbox row
- `ListSelectionInfo` — selection state text display

**Step 3 — Build verification**

### WP4: Tier 4 — List Containers (3 components)

Depends on WP3 completion. These are the most complex components.

**Step 1 — Logic + Tests:**
- Extend `ListFilterSortCalculations.swift` with list-specific grouping and eligibility logic
- Tests for standalone/embedded/picker mode state transitions (~15 tests)

**Step 2 — Components:**
- `SharedItemsList` — three modes (standalone, embedded, picker), grouping, filtering, sorting, bulk selection, pull-to-refresh via `.refreshable()`
- `SharedTransactionsList` — same patterns as SharedItemsList for transactions
- `DraggableCardList` — generic drag-to-reorder list via SwiftUI `List` + `.onMove(perform:)`

**Step 3 — Full build verification + integration test with existing screens**

---

## Key Design Decisions

### 1. AsyncImage over third-party libraries
All async image loading uses SwiftUI's built-in `AsyncImage`. Firebase Storage URLs work directly. URLSession caching handles most cases. No new SPM dependencies.

### 2. Deferred action execution pattern
The RN app uses a `pendingActionRef` to execute callbacks after sheet dismissal animation. SwiftUI equivalent: store the pending action closure, dismiss the sheet, execute in `.onDismiss` or `.onChange(of: isPresented)`.

### 3. Controlled/uncontrolled selection duality
ItemCard and TransactionCard support both modes — parent provides `Binding<Bool>` for controlled, or component manages internal `@State` with `defaultSelected`. SwiftUI pattern: accept optional `Binding<Bool>?` and fall back to `@State`.

### 4. `.safeAreaInset(edge: .bottom)` for BulkSelectionBar
Follows the established pattern for fixed bottom bars. Pushes list content up when bar appears, avoiding scroll overlap.

### 5. ActionMenuSheet replaces `.confirmationDialog()`
All action menus use the new ActionMenuSheet component. `.confirmationDialog()` is reserved for simple destructive confirmations only (per CLAUDE.md convention).

### 6. No new asset catalog colors needed
All components use existing BrandColors/StatusColors. Transaction badge colors (purchase=green, sale=blue, return=red) may need new StatusColors entries — verify during WP3.

### 7. Logic extraction pattern
Follow the established `enum XxxCalculations` pattern with static functions. Components call these functions; tests call them directly. No SwiftUI import needed in Logic files.
