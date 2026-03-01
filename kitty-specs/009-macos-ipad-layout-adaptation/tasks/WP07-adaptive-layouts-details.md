---
work_package_id: WP07
title: Adaptive Layouts — Detail Views, Forms & Grids
lane: planned
dependencies:
- WP06
subtasks:
- T035
- T036
- T037
- T038
- T039
- T040
- T041
phase: Phase 2 - Features
assignee: ''
agent: ''
shell_pid: ''
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-03-01T05:27:35Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP07 – Adaptive Layouts — Detail Views, Forms & Grids

## Important: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

> **Populated by `/spec-kitty.review`**

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP07 --base WP06
```

Depends on WP06 (`AdaptiveContentWidth` component created in T028).

---

## Objectives & Success Criteria

- All detail views (Project, Item, Transaction, Space) show centered, readable content on wide screens
- Budget/category card views use responsive multi-column grids via `onGeometryChange`
- `FormSheet` component constrains form width on macOS
- `.presentationDetents()` code remains unchanged (silently ignored on macOS)
- Grid columns animate smoothly when window is resized
- On iPhone, no visible change

## Context & Constraints

- **Spec**: FR-6 (Adaptive Card Layouts for Wider Screens) — "Detail views should use a readable maximum width with centered alignment on wide screens" and "Budget progress bars, category cards, and report views should use available width intelligently (e.g., multi-column category grids)"
- **Plan**: Phase D — `onGeometryChange` for responsive grid columns, `AdaptiveContentWidth` for detail views
- **Research**: §5 (Adaptive Card Layouts) — `onGeometryChange` pattern, anti-patterns to avoid
- **Axiom Guidance**: `axiom-swiftui-layout` Pattern 3 — `onGeometryChange` for responsive grids
- **Dependencies**: `AdaptiveContentWidth` from WP06 (T028), `Dimensions` constants from WP02 (T009)
- **Constraint**: Use `onGeometryChange(for: Int.self)` (not `GeometryReader`) for column count calculations
- **Constraint**: No `UIDevice.idiom` or `UIScreen.main.bounds` — respond to container size only

## Subtasks & Detailed Guidance

### Subtask T035 – Apply maxWidth to ProjectDetailView

- **Purpose**: Constrain project detail content to readable width on wide screens.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailView.swift`
  2. ProjectDetailView likely has a `ScrollView` with multiple sections (header, tabs, content)
  3. Wrap the main content (inside the ScrollView) with `AdaptiveContentWidth`:
     ```swift
     ScrollView {
         AdaptiveContentWidth {
             VStack(spacing: Spacing.sectionGap) {
                 // ... project header, tabs, content sections ...
             }
         }
     }
     ```
  4. If the view uses a tab bar (for switching between Transactions, Items, Spaces sub-views), the tab bar should still span the full width — only the content below it is constrained
  5. Test on macOS at various window widths: 800px, 1200px, 1800px
- **Files**: `LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailView.swift`
- **Parallel?**: Yes — independent of T036-T041.

### Subtask T036 – Apply maxWidth to ItemDetailView

- **Purpose**: Constrain item detail content to readable width.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift`
  2. This is one of the most complex views (11 sheets). Focus on the main scrollable content only — don't modify sheet content (that's T041)
  3. Wrap the main `ScrollView` content in `AdaptiveContentWidth`
  4. If there's an image gallery section, it may benefit from a wider constraint or no constraint (images look good at wider sizes)
  5. For the detail rows (key-value pairs), use `contentMaxWidth` (720pt)
- **Files**: `LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift`
- **Parallel?**: Yes — independent of other subtasks.

### Subtask T037 – Apply maxWidth to TransactionDetailView

- **Purpose**: Constrain transaction detail content to readable width.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift`
  2. Wrap the main content in `AdaptiveContentWidth`
  3. If the view has an items list section (associated items), that section should be within the constraint
- **Files**: `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift`
- **Parallel?**: Yes — independent of other subtasks.

### Subtask T038 – Apply maxWidth to SpaceDetailView

- **Purpose**: Constrain space detail content to readable width.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Projects/SpaceDetailView.swift`
  2. Wrap the main content in `AdaptiveContentWidth`
  3. If the space has an items list section, it should be within the constraint
- **Files**: `LedgeriOS/LedgeriOS/Views/Projects/SpaceDetailView.swift`
- **Parallel?**: Yes — independent of other subtasks.

### Subtask T039 – Responsive Grid in BudgetTabView

- **Purpose**: Make budget category cards use multi-column layout on wide screens instead of a single-column list.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Projects/BudgetTabView.swift`
  2. Identify the section that displays budget category cards (likely `ForEach(categories)` with `BudgetCategoryTracker` or similar cards)
  3. Add responsive column count via `onGeometryChange`:
     ```swift
     @State private var columnCount: Int = 1

     // In body:
     LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.cardListGap), count: columnCount), spacing: Spacing.cardListGap) {
         ForEach(categories) { category in
             BudgetCategoryTracker(category: category)
         }
     }
     .onGeometryChange(for: Int.self) { proxy in
         max(1, Int(proxy.size.width / Dimensions.cardMinWidth))
     } action: { newCount in
         columnCount = newCount
     }
     .animation(.default, value: columnCount)
     ```
  4. `Dimensions.cardMinWidth` (320pt) determines column thresholds:
     - < 640pt: 1 column (iPhone)
     - 640-959pt: 2 columns (iPad portrait, small Mac window)
     - 960-1279pt: 3 columns (iPad landscape, medium Mac window)
     - 1280pt+: 4 columns (wide Mac window)
  5. Wrap the grid in `AdaptiveContentWidth` if desired, or let the grid span the full content area (grids benefit from using available width)
  6. If budget cards are currently in a `List` or `LazyVStack`, convert to `LazyVGrid`
- **Files**: `LedgeriOS/LedgeriOS/Views/Projects/BudgetTabView.swift`
- **Parallel?**: Yes — independent of T040.
- **Notes**: If BudgetTabView doesn't have category cards (check by reading the file), apply the grid pattern to whatever grid-appropriate content exists. If the view is purely linear (progress bars, text), `AdaptiveContentWidth` alone is sufficient.

### Subtask T040 – Responsive Grid in AccountingTabView

- **Purpose**: Make accounting/budget overview use multi-column layout on wide screens.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift`
  2. Identify card-like content that would benefit from grid layout
  3. Apply the same `onGeometryChange` + `LazyVGrid` pattern as T039
  4. If the view is primarily text/progress bars (not cards), use `AdaptiveContentWidth` instead
- **Files**: `LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift`
- **Parallel?**: Yes — independent of T039.

### Subtask T041 – Constrain FormSheet Width on macOS

- **Purpose**: On macOS, sheets present as window-attached panels that can be wide. Constrain form content to a comfortable reading/input width.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Components/FormSheet.swift`
  2. `FormSheet` is the reusable wrapper for form-presenting sheets
  3. Add a width constraint to the sheet content:
     ```swift
     struct FormSheet<Content: View>: View {
         // ... existing properties ...

         var body: some View {
             // Existing content...
             content
                 .frame(maxWidth: Dimensions.formMaxWidth) // 560pt
                 .frame(maxWidth: .infinity) // Center within sheet
                 // ... existing modifiers (presentationDetents, dragIndicator) ...
         }
     }
     ```
  4. `Dimensions.formMaxWidth` (560pt) keeps forms narrow enough for comfortable text entry
  5. On iOS, 560pt is wider than most iPhone screens, so this has no visible effect
  6. `.presentationDetents()` and `.presentationDragIndicator()` are silently ignored on macOS — no changes needed
  7. Also check `MultiStepFormSheet.swift` — apply the same constraint if it exists
  8. If individual form views (NewProjectView, NewTransactionView, etc.) have their own width handling, the FormSheet-level constraint should cascade naturally
- **Files**:
  - `LedgeriOS/LedgeriOS/Components/FormSheet.swift`
  - `LedgeriOS/LedgeriOS/Components/MultiStepFormSheet.swift` (if exists)
- **Parallel?**: Yes — independent of other subtasks.
- **Notes**: On macOS, sheets are attached to the parent window and can be quite wide. Without this constraint, form fields would stretch across the full window width — poor UX.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| onGeometryChange column recalculation causes flicker | Add `.animation(.default, value: columnCount)` |
| Detail views with many sections need per-section constraints | Apply to outermost ScrollView content; test with long content |
| FormSheet constraint conflicts with existing presentationDetents | Detents are silently ignored on macOS; on iOS, frame constraint has no effect |
| LazyVGrid conversion breaks existing list behavior | Only convert views that currently show card-like content; keep linear views as-is |
| Budget views may not have card-like content suitable for grids | Read files first; fall back to AdaptiveContentWidth if content is linear |

## Review Guidance

- Detail views: Content centered and constrained on wide macOS windows
- Budget views: Multiple columns on wide screens, single column on iPhone
- FormSheet: Narrow centered form on macOS, unchanged on iPhone
- Grid column count adjusts smoothly when window is resized
- No hardcoded device checks anywhere

## Activity Log

- 2026-03-01T05:27:35Z – system – lane=planned – Prompt created.

---

### Updating Lane Status

To change a work package's lane, either:
1. **Edit directly**: Change the `lane:` field in frontmatter AND append activity log entry
2. **Use CLI**: `spec-kitty agent tasks move-task WP07 --to <lane> --note "message"`

**Valid lanes**: `planned`, `doing`, `for_review`, `done`
