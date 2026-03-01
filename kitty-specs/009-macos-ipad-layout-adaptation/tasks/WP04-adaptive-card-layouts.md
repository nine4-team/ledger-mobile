---
work_package_id: WP04
title: Adaptive Card Layouts
lane: planned
dependencies: []
subtasks: [T019, T020, T021, T022, T023, T024]
history:
- date: '2026-02-28'
  event: Created
---

# WP04: Adaptive Card Layouts

## Implementation Command

```bash
spec-kitty implement WP04 --base WP01
```

## Objective

Ensure all views render at readable widths on wide screens (Mac, iPad landscape). Cards and content should be centered with a maximum width, not stretched edge-to-edge across a 2560px display. Add responsive grid columns for card-heavy views.

## Context

- **Current state**: All views use `.frame(maxWidth: .infinity)` — content stretches to fill available width. This looks fine on iPhone but produces uncomfortably wide layouts on Mac/iPad.
- **Target state**: Content constrained to `contentMaxWidth` (720pt) and centered. Form sheets constrained to `formMaxWidth` (560pt). Card grids adapt column count to container width.
- **Anti-patterns to avoid**: `UIDevice.idiom`, `UIScreen.main.bounds`, unconstrained `GeometryReader`. All adaptation must be container-responsive.

### Files to modify

| File | Change |
|------|--------|
| `LedgeriOS/Theme/Dimensions.swift` | Add contentMaxWidth, formMaxWidth, cardMinWidth |
| `LedgeriOS/Views/Projects/ProjectsListView.swift` | Wrap content in AdaptiveContentWidth |
| `LedgeriOS/Views/Inventory/InventoryView.swift` | Wrap content in AdaptiveContentWidth |
| `LedgeriOS/Views/Search/UniversalSearchView.swift` | Wrap content in AdaptiveContentWidth |
| `LedgeriOS/Views/Projects/ProjectDetailView.swift` | Wrap content in AdaptiveContentWidth |
| `LedgeriOS/Views/Projects/ItemDetailView.swift` | Wrap content in AdaptiveContentWidth |
| `LedgeriOS/Views/Projects/TransactionDetailView.swift` | Wrap content in AdaptiveContentWidth |
| `LedgeriOS/Views/Projects/SpaceDetailView.swift` | Wrap content in AdaptiveContentWidth |
| `LedgeriOS/Views/Search/SpaceSearchDetailView.swift` | Wrap content in AdaptiveContentWidth |
| `LedgeriOS/Views/Creation/NewProjectView.swift` | Wrap in AdaptiveContentWidth(maxWidth: formMaxWidth) |
| `LedgeriOS/Views/Creation/NewTransactionView.swift` | Wrap in AdaptiveContentWidth(maxWidth: formMaxWidth) |
| `LedgeriOS/Views/Creation/NewItemView.swift` | Wrap in AdaptiveContentWidth(maxWidth: formMaxWidth) |
| `LedgeriOS/Views/Creation/NewSpaceView.swift` | Wrap in AdaptiveContentWidth(maxWidth: formMaxWidth) |
| `LedgeriOS/Views/Projects/BudgetTabView.swift` | Add onGeometryChange responsive grid |

### Files to create

| File | Purpose |
|------|---------|
| `LedgeriOS/Components/AdaptiveContentWidth.swift` | Reusable width-constraining wrapper |

---

## Subtasks

### T019: Add Layout Dimension Constants

**Purpose**: Centralize width constraints in the theme system so all views use consistent values.

**Steps**:
1. In `Dimensions.swift`, add a new section:

```swift
// MARK: - Content Width

/// Maximum width for content in list/detail views (prevents stretching on wide screens)
static let contentMaxWidth: CGFloat = 720

/// Maximum width for form sheets on macOS/iPad
static let formMaxWidth: CGFloat = 560

/// Minimum card width for responsive grid calculation
static let cardMinWidth: CGFloat = 320
```

**Validation**:
- [ ] Constants accessible from any view via `Dimensions.contentMaxWidth`

---

### T020: Create AdaptiveContentWidth Wrapper Component

**Purpose**: Reusable view wrapper that constrains content to a maximum width and centers it within the available space. On iPhone, the content fills the width as before (720pt > iPhone width). On Mac/iPad, content is capped and centered.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/AdaptiveContentWidth.swift`:

```swift
import SwiftUI

/// Constrains content to a maximum width and centers it horizontally.
///
/// On narrow screens (iPhone), content fills available width naturally since
/// the maxWidth exceeds the screen width. On wide screens (Mac, iPad landscape),
/// content is capped and centered.
///
/// Usage:
/// ```swift
/// AdaptiveContentWidth {
///     List { ... }
/// }
///
/// // For forms with a narrower max:
/// AdaptiveContentWidth(maxWidth: Dimensions.formMaxWidth) {
///     Form { ... }
/// }
/// ```
struct AdaptiveContentWidth<Content: View>: View {
    let maxWidth: CGFloat
    let content: Content

    init(
        maxWidth: CGFloat = Dimensions.contentMaxWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity) // Centers within available space
    }
}
```

2. Add the file to the Xcode project

**How it works**: The inner `.frame(maxWidth: 720)` caps the content width. The outer `.frame(maxWidth: .infinity)` ensures the view takes full available width, which centers the capped content within it (SwiftUI centers by default when a fixed-width child is inside an infinite-width parent).

**Validation**:
- [ ] On iPhone (390pt wide): Content fills width (720 > 390, so no capping)
- [ ] On Mac (1200pt window): Content is 720pt wide, centered
- [ ] formMaxWidth variant: Content is 560pt wide

---

### T021: Apply AdaptiveContentWidth to List Views

**Purpose**: Constrain the main list views so cards don't stretch edge-to-edge on wide screens.

**Files to modify**:
- `ProjectsListView.swift`
- `InventoryView.swift`
- `UniversalSearchView.swift`

**Pattern**: Wrap the scrollable content (List, ScrollView, or LazyVStack) inside `AdaptiveContentWidth`:

```swift
// Before:
var body: some View {
    List {
        ForEach(projects) { project in
            ProjectCard(project: project)
        }
    }
    .navigationTitle("Projects")
}

// After:
var body: some View {
    AdaptiveContentWidth {
        List {
            ForEach(projects) { project in
                ProjectCard(project: project)
            }
        }
    }
    .navigationTitle("Projects")
}
```

**Important notes**:
- Read each file first to understand its structure before wrapping
- Keep `.navigationTitle()`, `.toolbar()`, `.searchable()` and other modifiers outside `AdaptiveContentWidth` — they should be on the NavigationStack content, not on the wrapper
- If the view uses a `ScrollView` + `LazyVStack` instead of `List`, wrap the same way
- The wrapper goes around the scrollable container, not inside it

**Validation**:
- [ ] ProjectsListView: Cards centered on wide screens
- [ ] InventoryView: Content centered on wide screens
- [ ] UniversalSearchView: Content centered on wide screens
- [ ] All three: iPhone layout unchanged

---

### T022: Apply AdaptiveContentWidth to Detail Views

**Purpose**: Constrain detail views so long content (descriptions, fields, lists) stays at a readable width.

**Files to modify**:
- `ProjectDetailView.swift`
- `ItemDetailView.swift`
- `TransactionDetailView.swift`
- `SpaceDetailView.swift`
- `SpaceSearchDetailView.swift`

**Pattern**: Same as T021 — wrap the main scrollable content in `AdaptiveContentWidth`. Detail views typically use `ScrollView` or `List`:

```swift
// Wrap the scrollable content:
AdaptiveContentWidth {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // ... detail content
        }
        .padding(.horizontal, Spacing.screenPadding)
    }
}
```

**Important**: Read each detail view to identify the correct wrapping point. Some detail views have complex tab structures (e.g., ProjectDetailView has transaction/item/space tabs) — wrap the outer container, not individual tabs.

**Validation**:
- [ ] All 5 detail views: Content readable width on Mac
- [ ] iPhone: No layout changes

---

### T023: Apply AdaptiveContentWidth to Form Sheets

**Purpose**: Form sheets should be narrower than content views. Use `formMaxWidth` (560pt) instead of `contentMaxWidth` (720pt).

**Files to modify**:
- `NewProjectView.swift`
- `NewTransactionView.swift`
- `NewItemView.swift`
- `NewSpaceView.swift`

**Pattern**:
```swift
AdaptiveContentWidth(maxWidth: Dimensions.formMaxWidth) {
    Form {
        // ... form fields
    }
}
```

**Important notes**:
- These views are presented as sheets (`.sheet()` with `.presentationDetents()`)
- On macOS, sheets present as window-attached panels. The width constraint ensures form fields don't stretch across the full sheet width.
- On iPhone, `formMaxWidth` (560pt) exceeds the screen width, so the form fills naturally
- Keep `.presentationDetents()` and `.presentationDragIndicator()` on the sheet content — they're silently ignored on macOS

**Validation**:
- [ ] All 4 form sheets: Readable width on Mac
- [ ] iPhone: Form sheets unchanged (bottom sheets with detents)

---

### T024: Add Responsive Grid Columns via onGeometryChange

**Purpose**: Card-heavy views (like budget categories) should show multiple columns on wide screens instead of a single-column list.

**Target views**: `BudgetTabView.swift` (budget category cards), and any other view that displays a grid of cards.

**Pattern**:
```swift
struct BudgetTabView: View {
    @State private var columnCount: Int = 1

    var body: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: Spacing.cardListGap),
            count: columnCount
        )

        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.cardListGap) {
                ForEach(categories) { category in
                    BudgetCategoryCard(category: category)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
        .onGeometryChange(for: Int.self) { proxy in
            max(1, Int(proxy.size.width / Dimensions.cardMinWidth))
        } action: { newCount in
            columnCount = newCount
        }
    }
}
```

**How it works**:
- `onGeometryChange` reads the container width (not the screen width)
- Divides by `cardMinWidth` (320pt) to calculate how many columns fit
- `max(1, ...)` ensures at least 1 column
- iPhone (~390pt): 1 column (390 / 320 = 1.2 → 1)
- iPad landscape (~1000pt content area): 3 columns
- Mac (1200pt window, minus sidebar): 2-3 columns

**Important**: Read each target view first. If a view already uses `LazyVStack` with `ForEach`, convert to `LazyVGrid`. If it uses `List`, the grid approach may not apply — `List` handles its own layout.

**Validation**:
- [ ] Budget cards: 1 column on iPhone, 2+ on iPad/Mac
- [ ] Column count updates live when window is resized (macOS)
- [ ] No layout jumps or animation glitches during resize

---

## Definition of Done

- [ ] Dimensions.swift has contentMaxWidth (720), formMaxWidth (560), cardMinWidth (320)
- [ ] AdaptiveContentWidth component created and working
- [ ] All list views wrapped — content centered on wide screens
- [ ] All detail views wrapped — readable width on wide screens
- [ ] All form sheets wrapped with formMaxWidth — narrow on wide screens
- [ ] Budget/card views use responsive grid columns
- [ ] iPhone layouts completely unchanged

## Risks

| Risk | Mitigation |
|------|------------|
| Wrapping breaks existing layout in specific views | Read each file before wrapping; test on iPhone after each change |
| List vs ScrollView: AdaptiveContentWidth may not work identically | Test both patterns; List may need the wrapper outside the NavigationStack |
| onGeometryChange not available on current deployment target | onGeometryChange requires iOS 18+ / macOS 15+ — matches our deployment targets |
| Column count animation during resize feels janky | Use `.animation(.default, value: columnCount)` if needed |

## Reviewer Guidance

1. Open each modified file on iPhone simulator — verify no layout regression
2. Open on Mac at various window widths (800, 1200, 1600, 2560) — content should be centered and readable
3. Verify form sheets are narrower than list views
4. Resize macOS window while viewing budget cards — columns should adapt smoothly
5. Check that `.navigationTitle()` and `.toolbar()` are NOT inside the AdaptiveContentWidth wrapper
