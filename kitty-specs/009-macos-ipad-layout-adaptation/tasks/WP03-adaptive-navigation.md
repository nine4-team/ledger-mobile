---
work_package_id: WP03
title: Adaptive Navigation — Tab/Sidebar
lane: planned
dependencies:
- WP02
subtasks:
- T011
- T012
- T013
- T014
- T015
- T016
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

# Work Package Prompt: WP03 – Adaptive Navigation — Tab/Sidebar

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
spec-kitty implement WP03 --base WP02
```

Depends on WP02 (macOS must build before navigation can be tested cross-platform).

---

## Objectives & Success Criteria

- MainTabView uses iOS 18+ `Tab` syntax instead of legacy `TabView` + `.tabItem` pattern
- `.tabViewStyle(.sidebarAdaptable)` is applied, giving:
  - **iPhone**: Bottom tab bar (unchanged from current behavior)
  - **iPad**: Adaptable tab bar / sidebar (user-toggleable)
  - **macOS**: Permanent sidebar
- Type-safe `AppSection` enum replaces integer tab indices
- `@SceneStorage` preserves selected tab per window
- Each tab's `NavigationStack` works independently in sidebar mode
- **Zero regressions on iPhone** — existing tab navigation works identically

## Context & Constraints

- **Spec**: FR-2 (Adaptive Navigation — Sidebar on Mac/iPad, Tabs on iPhone)
- **Plan**: Phase B (Adaptive Navigation) — Key decision: `.tabViewStyle(.sidebarAdaptable)` (not manual split/tab switching)
- **Research**: §2 (Adaptive Navigation) — Confirmed `.sidebarAdaptable` behavior on all platforms
- **Axiom Guidance**: `axiom-swiftui-nav` Pattern 5 — Sidebar-Adaptable TabView
- **Current architecture**: `MainTabView.swift` uses `TabView(selection:)` with 4 tabs, each wrapping a `NavigationStack`. Selection persisted via `@SceneStorage("selectedTab")` as `Int`.
- **Constraint**: The existing `.navigationDestination(for:)` modifiers inside each tab MUST remain unchanged.
- **Constraint**: iOS 18+ deployment target confirmed — safe to use `Tab` syntax.

## Subtasks & Detailed Guidance

### Subtask T011 – Create AppSection Enum

- **Purpose**: Replace the integer-based tab selection with a type-safe enum. Required for `@SceneStorage` with `String` raw value and for readable code.
- **Steps**:
  1. Define the enum (can be placed at the top of `MainTabView.swift` or in a separate file):
     ```swift
     enum AppSection: String, CaseIterable {
         case projects
         case inventory
         case search
         case settings
     }
     ```
  2. The `String` raw value enables `@SceneStorage` compatibility (SceneStorage needs `RawRepresentable`)
  3. `CaseIterable` is useful for iteration if needed later
  4. This enum maps 1:1 to the existing 4 tabs
- **Files**: `LedgeriOS/LedgeriOS/Views/MainTabView.swift` (or new file if preferred)
- **Parallel?**: No — needed by T012.
- **Notes**: This is the `AppSection` enum from data-model.md.

### Subtask T012 – Refactor MainTabView to iOS 18+ Tab Syntax

- **Purpose**: Replace the deprecated `.tabItem` pattern with the modern `Tab("Label", systemImage:)` syntax. This is required for `.sidebarAdaptable` to work properly.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/MainTabView.swift` in full
  2. Replace the current structure:
     ```swift
     // BEFORE (current):
     TabView(selection: $selectedTab) {
         NavigationStack { ProjectsListView() }
             .tabItem { Label("Projects", systemImage: "folder") }
             .tag(0)
         // ... more tabs with .tabItem and .tag
     }

     // AFTER:
     TabView(selection: $selectedTab) {
         Tab("Projects", systemImage: "folder", value: .projects) {
             NavigationStack {
                 ProjectsListView()
                     .navigationDestination(for: ...) { ... }
             }
         }

         Tab("Inventory", systemImage: "archivebox", value: .inventory) {
             NavigationStack {
                 InventoryView()
             }
         }

         Tab("Search", systemImage: "magnifyingglass", value: .search) {
             NavigationStack {
                 UniversalSearchView()
                     .navigationDestination(for: ...) { ... }
             }
         }

         Tab("Settings", systemImage: "gear", value: .settings) {
             NavigationStack {
                 SettingsView()
             }
         }
     }
     ```
  3. The `value:` parameter on each `Tab` connects to the `selection: $selectedTab` binding using `AppSection`
  4. Keep ALL existing `.navigationDestination(for:)` modifiers exactly as they are
  5. Keep ALL existing `.toolbar` modifiers on NavigationStacks
  6. Remove old `.tabItem` and `.tag()` modifiers
  7. Check the current SF Symbol names — keep them or update to match the plan (plan.md says: "folder", "archivebox", "magnifyingglass", "gear")
- **Files**: `LedgeriOS/LedgeriOS/Views/MainTabView.swift`
- **Parallel?**: No — sequential with T011.
- **Notes**: The `Tab` initializer with `value:` parameter requires iOS 18+. The `.tint(BrandColors.primary)` modifier on the TabView should be kept.

### Subtask T013 – Apply .tabViewStyle(.sidebarAdaptable)

- **Purpose**: Enable the adaptive sidebar/tab behavior with a single line.
- **Steps**:
  1. Add `.tabViewStyle(.sidebarAdaptable)` to the `TabView` in `MainTabView.swift`
  2. This single modifier produces:
     - Bottom tab bar on iPhone (compact width)
     - Adaptable tab bar / sidebar on iPad (user can toggle)
     - Permanent sidebar on macOS
  3. No `@Environment(\.horizontalSizeClass)` checking needed
  4. No manual `NavigationSplitView` needed
  5. Place the modifier after the closing brace of `TabView`:
     ```swift
     TabView(selection: $selectedTab) {
         // ... tabs ...
     }
     .tabViewStyle(.sidebarAdaptable)
     .tint(BrandColors.primary)
     ```
- **Files**: `LedgeriOS/LedgeriOS/Views/MainTabView.swift`
- **Parallel?**: No — sequential with T012.
- **Notes**: Per Axiom `axiom-swiftui-nav` Pattern 5, `.sidebarAdaptable` works well with `Tab` syntax. `TabSection` can be used for grouping but is not needed for our 4 simple sections.

### Subtask T014 – Update @SceneStorage to AppSection Type

- **Purpose**: The current `@SceneStorage("selectedTab")` stores an `Int`. Update it to use `AppSection` for type safety and readability.
- **Steps**:
  1. Change the declaration:
     ```swift
     // BEFORE:
     @SceneStorage("selectedTab") private var selectedTab: Int = 0

     // AFTER:
     @SceneStorage("selectedTab") private var selectedTab: AppSection = .projects
     ```
  2. `AppSection` conforms to `String` (RawRepresentable) so `@SceneStorage` can serialize it
  3. Remove any integer-based `.tag()` references if they still exist
  4. The `selectedTab` binding is used by `TabView(selection:)` — verify it connects correctly
- **Files**: `LedgeriOS/LedgeriOS/Views/MainTabView.swift`
- **Parallel?**: No — sequential with T012.
- **Notes**: `@SceneStorage` automatically provides per-window tab restoration. Each window remembers its own selected tab.

### Subtask T015 – Verify NavigationStack in Sidebar Mode

- **Purpose**: Ensure each tab's `NavigationStack` works correctly when the TabView renders as a sidebar (iPad/macOS).
- **Steps**:
  1. Build and run on macOS
  2. Click each sidebar item and verify the content area shows the correct view
  3. Navigate into a detail view (e.g., Projects → Project Detail) and verify:
     - The sidebar remains visible
     - The detail view shows in the content area
     - The back button works to return to the list
  4. Switch between sidebar items while a detail view is open — verify the navigation resets for the new section
  5. Build and run on iPad simulator in landscape — verify sidebar is toggleable
  6. Test: Open Search, perform a search, navigate to a result detail, switch to Projects sidebar item, then back to Search — verify search state is preserved
- **Files**: N/A (testing)
- **Parallel?**: Yes — independent of T016.
- **Notes**: If NavigationStack state is lost when switching sidebar items, this is expected behavior (each tab gets fresh state). Document if this differs from the current tab behavior.

### Subtask T016 – Verify iPhone Tabs Unchanged

- **Purpose**: Confirm that the Tab syntax refactor produces identical behavior on iPhone.
- **Steps**:
  1. Build and run on iPhone 16e simulator (preferred per memory)
  2. Verify: 4 tabs visible at bottom, correct icons and labels
  3. Navigate through each tab — verify all existing navigation works
  4. Test deep navigation: Projects → Project → Transaction Detail → back → back
  5. Switch tabs while deep in navigation — verify navigation state is preserved per tab
  6. Verify: `.tint(BrandColors.primary)` still applies to selected tab icon
  7. Also test on iPhone SE simulator (smallest screen) to verify no layout issues
- **Files**: N/A (testing)
- **Parallel?**: Yes — independent of T015.
- **Notes**: This is the most critical verification. The spec says "All existing iPhone screens must continue to work exactly as they do today." Any regression here blocks the release.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `.sidebarAdaptable` renders differently than expected on iPad | Research §2 confirms behavior; test on iPad simulator |
| Tab switching animation differs from current behavior | Acceptable if functionally identical; document visual differences |
| Sidebar doesn't show on macOS first launch | Verify `.tabViewStyle(.sidebarAdaptable)` is applied; check WindowGroup scene setup |
| `@SceneStorage` with String enum causes serialization issues | Test by killing and relaunching app; verify selected tab is restored |

## Review Guidance

- **Critical**: iPhone must show identical tab bar to pre-refactor
- Compare before/after screenshots on iPhone if possible
- Sidebar must be visible and functional on macOS
- iPad must support both tab bar and sidebar modes
- All `.navigationDestination` modifiers must be preserved unchanged

## Activity Log

- 2026-03-01T05:27:35Z – system – lane=planned – Prompt created.

---

### Updating Lane Status

To change a work package's lane, either:
1. **Edit directly**: Change the `lane:` field in frontmatter AND append activity log entry
2. **Use CLI**: `spec-kitty agent tasks move-task WP03 --to <lane> --note "message"`

**Valid lanes**: `planned`, `doing`, `for_review`, `done`
