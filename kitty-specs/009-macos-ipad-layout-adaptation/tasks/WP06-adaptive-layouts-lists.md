---
work_package_id: WP06
title: Adaptive Layouts — List Views & Auth Screens
lane: planned
dependencies:
- WP02
subtasks:
- T028
- T029
- T030
- T031
- T032
- T033
- T034
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

# Work Package Prompt: WP06 – Adaptive Layouts — List Views & Auth Screens

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
spec-kitty implement WP06 --base WP02
```

Depends on WP02 (needs `Dimensions.contentMaxWidth` constant from T009).

---

## Objectives & Success Criteria

- A reusable `AdaptiveContentWidth` wrapper component exists
- All list views (Projects, Inventory, Search, Settings) are wrapped so cards don't stretch beyond 720pt
- Auth screens (SignIn, SignUp) and AccountGateView are centered with constrained width
- Content is centered horizontally within available space on wide screens
- On iPhone, no visible change (720pt is wider than any iPhone screen)
- No `UIDevice.idiom` or `UIScreen.main.bounds` checks anywhere

## Context & Constraints

- **Spec**: FR-6 (Adaptive Card Layouts for Wider Screens)
- **Plan**: Phase D — Key decision: Container-responsive design using `frame(maxWidth:)` and `onGeometryChange`
- **Research**: §5 (Adaptive Card Layouts) — Anti-patterns to avoid
- **Axiom Guidance**: `axiom-swiftui-layout` — Respond to container size, not device identity
- **Data Model**: `data-model.md` — `Dimensions.contentMaxWidth = 720`, `Dimensions.formMaxWidth = 560`, `Dimensions.cardMinWidth = 320`
- **Codebase Findings**: 23 files use `.frame(maxWidth: .infinity)` — all expand to fill available space. No existing maxWidth caps.
- **Constraint**: Apply width constraint at the scroll view / list level, NOT on individual cards. Cards should fill the constrained container width.
- **Constraint**: On iPhone, `maxWidth: 720` has no visible effect since screen width < 720pt. This is by design.

## Subtasks & Detailed Guidance

### Subtask T028 – Create AdaptiveContentWidth Wrapper Component

- **Purpose**: Provide a reusable SwiftUI view that constrains content to a maximum readable width and centers it within available space.
- **Steps**:
  1. Create file: `LedgeriOS/LedgeriOS/Components/AdaptiveContentWidth.swift`
  2. Implementation:
     ```swift
     import SwiftUI

     struct AdaptiveContentWidth<Content: View>: View {
         let maxWidth: CGFloat
         let content: Content

         init(maxWidth: CGFloat = Dimensions.contentMaxWidth, @ViewBuilder content: () -> Content) {
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
  3. The pattern: Inner `frame(maxWidth: 720)` constrains the content. Outer `frame(maxWidth: .infinity)` ensures the constrained content is centered (not left-aligned) in a wider container.
  4. Default maxWidth uses `Dimensions.contentMaxWidth` (720pt), but can be overridden for specific views (e.g., forms use `Dimensions.formMaxWidth`)
- **Files**: `LedgeriOS/LedgeriOS/Components/AdaptiveContentWidth.swift` (new file)
- **Parallel?**: No — needed by T029-T034.
- **Notes**: This is the component from plan.md §2 (Responsive Layouts).

### Subtask T029 – Apply AdaptiveContentWidth to ProjectsListView

- **Purpose**: Prevent project cards from stretching edge-to-edge on wide screens.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift`
  2. Identify the main content container (likely a `ScrollView` or `List` with `LazyVStack`)
  3. Wrap the content in `AdaptiveContentWidth`:
     ```swift
     // Option A: Wrap the ScrollView's content
     ScrollView {
         AdaptiveContentWidth {
             LazyVStack(spacing: Spacing.cardListGap) {
                 ForEach(projects) { project in
                     ProjectCard(project: project)
                 }
             }
         }
     }

     // Option B: Apply as a modifier on the list
     ScrollView {
         LazyVStack(spacing: Spacing.cardListGap) {
             ForEach(projects) { project in
                 ProjectCard(project: project)
             }
         }
         .frame(maxWidth: Dimensions.contentMaxWidth)
         .frame(maxWidth: .infinity)
     }
     ```
  4. Choose the approach that requires minimal restructuring of existing code
  5. Preserve all existing padding, spacing, and scroll behavior
  6. Test on iPhone SE — verify no visual change
  7. Test on macOS at 1440px+ width — cards should be centered with readable width
- **Files**: `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift`
- **Parallel?**: Yes — independent of T030-T034.

### Subtask T030 – Apply AdaptiveContentWidth to InventoryView and Sub-tabs

- **Purpose**: Constrain inventory content on wide screens. InventoryView has sub-tabs (Items, Spaces, Transactions), each with its own list.
- **Steps**:
  1. Read the following files:
     - `LedgeriOS/LedgeriOS/Views/Inventory/InventoryView.swift`
     - `LedgeriOS/LedgeriOS/Views/Inventory/InventoryItemsSubTab.swift`
     - `LedgeriOS/LedgeriOS/Views/Inventory/InventorySpacesSubTab.swift`
     - `LedgeriOS/LedgeriOS/Views/Inventory/InventoryTransactionsSubTab.swift`
  2. Apply `AdaptiveContentWidth` to each sub-tab's content container (the ScrollView or LazyVStack within each sub-tab)
  3. If `InventoryView` has its own content wrapper, apply there instead (to avoid redundancy)
  4. Apply to each sub-tab individually if they each have their own scroll containers
  5. Preserve the `ScrollableTabBar` or segmented control layout — it should still span the full width (only the card content below is constrained)
- **Files**:
  - `LedgeriOS/LedgeriOS/Views/Inventory/InventoryView.swift`
  - `LedgeriOS/LedgeriOS/Views/Inventory/InventoryItemsSubTab.swift`
  - `LedgeriOS/LedgeriOS/Views/Inventory/InventorySpacesSubTab.swift`
  - `LedgeriOS/LedgeriOS/Views/Inventory/InventoryTransactionsSubTab.swift`
- **Parallel?**: Yes — independent of other subtasks.
- **Notes**: The tab bar itself should NOT be constrained — only the list content below it.

### Subtask T031 – Apply AdaptiveContentWidth to UniversalSearchView

- **Purpose**: Constrain search results on wide screens.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Search/UniversalSearchView.swift`
  2. Apply `AdaptiveContentWidth` to the search results container
  3. The search field itself may or may not need constraining — if it uses `.searchable()`, it's handled by the navigation bar and doesn't need width constraints
  4. If search results are displayed in a `LazyVStack` or `List`, wrap that container
- **Files**: `LedgeriOS/LedgeriOS/Views/Search/UniversalSearchView.swift`
- **Parallel?**: Yes — independent of other subtasks.

### Subtask T032 – Apply AdaptiveContentWidth to SettingsView

- **Purpose**: Constrain settings content on wide screens.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Settings/SettingsView.swift`
  2. Apply `AdaptiveContentWidth` to the main content (likely a `List` or `Form`)
  3. If SettingsView uses SwiftUI `Form`, wrapping the Form itself should work:
     ```swift
     AdaptiveContentWidth {
         Form {
             // ... existing settings sections ...
         }
     }
     ```
  4. If the Form already has system-provided insets, the constraint may need to be on the Form's content rather than the Form itself — test both approaches
- **Files**: `LedgeriOS/LedgeriOS/Views/Settings/SettingsView.swift`
- **Parallel?**: Yes — independent of other subtasks.

### Subtask T033 – Apply AdaptiveContentWidth to AccountGateView

- **Purpose**: Center the account selection interface on wide screens (currently stretches with `.frame(maxWidth: .infinity)`).
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/AccountGateView.swift`
  2. The account picker is a `LazyVStack` of account cards — wrap it:
     ```swift
     AdaptiveContentWidth(maxWidth: Dimensions.formMaxWidth) {
         LazyVStack(spacing: Spacing.cardListGap) {
             ForEach(accounts) { account in
                 // account card ...
             }
         }
     }
     ```
  3. Use `formMaxWidth` (560pt) instead of `contentMaxWidth` (720pt) since this is more of a selection form than a content list
  4. Also constrain the loading and empty states
- **Files**: `LedgeriOS/LedgeriOS/Views/AccountGateView.swift`
- **Parallel?**: Yes — independent of other subtasks.

### Subtask T034 – Apply AdaptiveContentWidth to Auth Screens

- **Purpose**: Center auth forms (sign in, sign up) on wide screens so they don't stretch to fill a Mac window.
- **Steps**:
  1. Read these files:
     - `LedgeriOS/LedgeriOS/Auth/AuthView.swift`
     - `LedgeriOS/LedgeriOS/Auth/SignInView.swift`
     - `LedgeriOS/LedgeriOS/Auth/SignUpView.swift`
  2. Apply `AdaptiveContentWidth(maxWidth: Dimensions.formMaxWidth)` to the main content of each
  3. Auth forms should use the narrower `formMaxWidth` (560pt) for a comfortable centered form
  4. The logo/header area may need separate treatment — center it within the full width, then constrain the form fields below
  5. Test: On macOS, auth screens should look like centered login forms, not stretched to window width
- **Files**:
  - `LedgeriOS/LedgeriOS/Auth/AuthView.swift`
  - `LedgeriOS/LedgeriOS/Auth/SignInView.swift`
  - `LedgeriOS/LedgeriOS/Auth/SignUpView.swift`
- **Parallel?**: Yes — independent of other subtasks.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Constraining width breaks existing `.frame(maxWidth: .infinity)` patterns | iPhone is always < 720pt so maxWidth has no effect; test on iPhone SE |
| ScrollView content doesn't center correctly | The double-frame pattern (`maxWidth: 720` + `maxWidth: .infinity`) handles centering |
| Some views have nested scroll containers | Apply constraint at outermost content level only |
| `List` vs `ScrollView` + `LazyVStack` behave differently with frame constraints | Test both; `List` may need the constraint on its row content rather than the List itself |

## Review Guidance

- On macOS at 1440px+ width: All list views show centered, constrained card content
- On iPhone SE: No visual change whatsoever
- No `UIDevice.idiom`, `UIScreen.main.bounds`, or `horizontalSizeClass` used anywhere
- `AdaptiveContentWidth` component is clean and reusable
- Tab bars, navigation bars, and toolbars still span full width (only content is constrained)

## Activity Log

- 2026-03-01T05:27:35Z – system – lane=planned – Prompt created.

---

### Updating Lane Status

To change a work package's lane, either:
1. **Edit directly**: Change the `lane:` field in frontmatter AND append activity log entry
2. **Use CLI**: `spec-kitty agent tasks move-task WP06 --to <lane> --note "message"`

**Valid lanes**: `planned`, `doing`, `for_review`, `done`
