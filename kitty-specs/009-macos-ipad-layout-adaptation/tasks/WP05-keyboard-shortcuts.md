---
work_package_id: WP05
title: Keyboard Shortcuts & Menu Bar
lane: planned
dependencies:
- WP03
subtasks:
- T023
- T024
- T025
- T026
- T027
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

# Work Package Prompt: WP05 – Keyboard Shortcuts & Menu Bar

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
spec-kitty implement WP05 --base WP03
```

Depends on WP03 (navigation must be refactored for context-sensitive creation to target correct views).

---

## Objectives & Success Criteria

- macOS menu bar includes File menu with creation commands
- Cmd+N triggers context-sensitive creation (new project from Projects, new transaction from Transactions, etc.)
- Cmd+F focuses the search field in UniversalSearchView
- Cmd+, navigates to the Settings tab
- Standard system shortcuts (Cmd+C/V/X, Cmd+Z, Cmd+W, Cmd+Q) work automatically
- `.commands {}` is silently ignored on iOS — no regressions

## Context & Constraints

- **Spec**: FR-5 (Keyboard Shortcuts)
- **Plan**: Phase B — Key decision: Menu bar commands post `NotificationCenter` notifications. Active list views observe and trigger creation sheets. This avoids coupling between menu bar and specific views.
- **Data Model**: `data-model.md` §3 (Keyboard Shortcut Notifications) — defines Notification.Name extensions
- **Axiom Guidance**: `axiom-app-composition` — `.commands {}` pattern
- **Constraint**: `.commands {}` is silently ignored on iOS — safe to include unconditionally
- **Constraint**: Standard system shortcuts work automatically — no custom code needed for Cmd+C/V/X/Z/W/Q
- **Current architecture**: List views already have `@State` variables controlling `.sheet()` presentation (e.g., `showingNewProject`, `showingNewTransaction`). The notification just toggles these.

## Subtasks & Detailed Guidance

### Subtask T023 – Define Notification.Name Extensions

- **Purpose**: Create centralized notification names for keyboard shortcut dispatching. Menu bar commands post these; active views observe them.
- **Steps**:
  1. Create a new file or add to an existing utilities file. Suggested: `LedgeriOS/LedgeriOS/Platform/KeyboardShortcutNotifications.swift`
  2. Define all notification names:
     ```swift
     extension Notification.Name {
         static let createProject = Notification.Name("ledger.createProject")
         static let createTransaction = Notification.Name("ledger.createTransaction")
         static let createItem = Notification.Name("ledger.createItem")
         static let createSpace = Notification.Name("ledger.createSpace")
         static let focusSearch = Notification.Name("ledger.focusSearch")
         static let showSettings = Notification.Name("ledger.showSettings")
     }
     ```
  3. Use namespaced names (prefixed with `ledger.`) to avoid conflicts with system notifications
- **Files**: `LedgeriOS/LedgeriOS/Platform/KeyboardShortcutNotifications.swift` (new file)
- **Parallel?**: No — needed by T024 and T026.
- **Notes**: These are the notification names from data-model.md §3.

### Subtask T024 – Create LedgerCommands Struct

- **Purpose**: Define the macOS menu bar commands with keyboard shortcuts.
- **Steps**:
  1. Create new file: `LedgeriOS/LedgeriOS/Platform/LedgerCommands.swift`
  2. Implementation:
     ```swift
     import SwiftUI

     struct LedgerCommands: Commands {
         var body: some Commands {
             // Replace the default "New Window" with our creation commands
             CommandGroup(after: .newItem) {
                 Button("New Project") {
                     NotificationCenter.default.post(name: .createProject, object: nil)
                 }
                 .keyboardShortcut("n", modifiers: .command)

                 Button("New Transaction") {
                     NotificationCenter.default.post(name: .createTransaction, object: nil)
                 }
                 .keyboardShortcut("n", modifiers: [.command, .shift])

                 Button("New Item") {
                     NotificationCenter.default.post(name: .createItem, object: nil)
                 }
                 .keyboardShortcut("n", modifiers: [.command, .option])

                 Button("New Space") {
                     NotificationCenter.default.post(name: .createSpace, object: nil)
                 }
                 .keyboardShortcut("n", modifiers: [.command, .option, .shift])
             }

             CommandGroup(after: .toolbar) {
                 Button("Search") {
                     NotificationCenter.default.post(name: .focusSearch, object: nil)
                 }
                 .keyboardShortcut("f", modifiers: .command)
             }

             CommandGroup(after: .appSettings) {
                 Button("Settings") {
                     NotificationCenter.default.post(name: .showSettings, object: nil)
                 }
                 .keyboardShortcut(",", modifiers: .command)
             }
         }
     }
     ```
  3. Note: Cmd+N is the most common shortcut. Use modifier combos for less common creation commands.
  4. The `.appSettings` command group placement puts Settings in the standard location (app name menu)
- **Files**: `LedgeriOS/LedgeriOS/Platform/LedgerCommands.swift` (new file)
- **Parallel?**: No — needs T023 notification names.
- **Notes**: Per plan.md, context-sensitive Cmd+N means whichever list view is active responds. If the user is in Projects, Cmd+N creates a project. If in Transactions, Cmd+N creates a transaction. The notification-based approach achieves this because only the active view's observer triggers.

### Subtask T025 – Add .commands to LedgerApp

- **Purpose**: Wire the `LedgerCommands` into the app's scene.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/LedgerApp.swift`
  2. Add `.commands` to the `WindowGroup`:
     ```swift
     WindowGroup {
         RootView()
         // ... existing environment injections ...
     }
     .defaultSize(width: 1000, height: 700)
     .windowResizability(.contentMinSize)
     .windowToolbarStyle(.unified)
     .commands {
         LedgerCommands()
     }
     ```
  3. `.commands {}` is silently ignored on iOS — no `#if os(macOS)` needed
  4. Verify the menu bar appears on macOS with the custom commands
- **Files**: `LedgeriOS/LedgeriOS/LedgerApp.swift`
- **Parallel?**: No — requires T024.
- **Notes**: The `.commands` modifier applies to all windows in the group.

### Subtask T026 – Wire Context-Sensitive Cmd+N in List Views

- **Purpose**: Make list views respond to creation notifications by opening their creation sheets.
- **Steps**:
  1. Read the following files to understand their sheet-triggering state variables:
     - `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift` — likely has `@State private var showingNewProject = false`
     - `LedgeriOS/LedgeriOS/Views/Projects/ItemsTabView.swift` — `showingNewItem`
     - `LedgeriOS/LedgeriOS/Views/Projects/TransactionsTabView.swift` — `showingNewTransaction`
     - `LedgeriOS/LedgeriOS/Views/Projects/SpacesTabView.swift` — `showingNewSpace`
  2. Add `.onReceive` to each view:
     ```swift
     // In ProjectsListView:
     .onReceive(NotificationCenter.default.publisher(for: .createProject)) { _ in
         showingNewProject = true
     }

     // In ItemsTabView:
     .onReceive(NotificationCenter.default.publisher(for: .createItem)) { _ in
         showingNewItem = true
     }

     // In TransactionsTabView:
     .onReceive(NotificationCenter.default.publisher(for: .createTransaction)) { _ in
         showingNewTransaction = true
     }

     // In SpacesTabView:
     .onReceive(NotificationCenter.default.publisher(for: .createSpace)) { _ in
         showingNewSpace = true
     }
     ```
  3. Place `.onReceive` at the view level (on the List or ScrollView), not on individual items
  4. For Cmd+, (Settings), wire it in MainTabView:
     ```swift
     .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
         selectedTab = .settings
     }
     ```
  5. **Important for multi-window**: On macOS, multiple windows may all observe the same notification. To ensure only the active (key) window responds, you can check `@Environment(\.controlActiveState)`:
     ```swift
     @Environment(\.controlActiveState) private var controlActiveState

     .onReceive(NotificationCenter.default.publisher(for: .createProject)) { _ in
         guard controlActiveState == .key else { return }
         showingNewProject = true
     }
     ```
     Note: `controlActiveState` is macOS-only. Wrap in `#if os(macOS)` or just skip the guard on iOS (where there's only one window anyway).
- **Files**:
  - `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift`
  - `LedgeriOS/LedgeriOS/Views/Projects/ItemsTabView.swift`
  - `LedgeriOS/LedgeriOS/Views/Projects/TransactionsTabView.swift`
  - `LedgeriOS/LedgeriOS/Views/Projects/SpacesTabView.swift`
  - `LedgeriOS/LedgeriOS/Views/MainTabView.swift`
- **Parallel?**: Yes — different files, same pattern. Can be split across engineers.
- **Notes**: Read each file first to find the exact `@State` variable names for sheet presentation. The names above are approximations.

### Subtask T027 – Wire Cmd+F to Focus Search

- **Purpose**: Make Cmd+F focus the search field in UniversalSearchView.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Search/UniversalSearchView.swift`
  2. If the view already uses `@FocusState` for the search field, wire the notification to set focus:
     ```swift
     @FocusState private var isSearchFocused: Bool

     // On the search TextField:
     .focused($isSearchFocused)

     // Observe notification:
     .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
         isSearchFocused = true
     }
     ```
  3. If the view uses `.searchable()`, focusing may require switching to the Search tab first:
     ```swift
     // In MainTabView:
     .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
         selectedTab = .search
         // The search view will auto-focus when it appears
     }
     ```
  4. If `.searchable()` doesn't expose focus control, selecting the Search tab is sufficient
- **Files**:
  - `LedgeriOS/LedgeriOS/Views/Search/UniversalSearchView.swift`
  - `LedgeriOS/LedgeriOS/Views/MainTabView.swift` (for tab switching)
- **Parallel?**: Yes — independent of T026.
- **Notes**: Read the search view to determine how the search field is implemented (TextField vs .searchable) before choosing the approach.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Multiple windows respond to same Cmd+N | Use `controlActiveState` guard (macOS only) to filter to key window |
| Cmd+N conflicts with system "New Window" shortcut | Place in `CommandGroup(after: .newItem)` — system adds "New Window" separately |
| `.searchable()` doesn't expose focus control | Fall back to switching to Search tab (still useful) |
| Notification observers persist when view is not visible | `.onReceive` on SwiftUI views automatically subscribes/unsubscribes with view lifecycle |

## Review Guidance

- On macOS: Cmd+N from Projects list opens new project sheet
- On macOS: Cmd+F switches to Search tab (or focuses search field)
- On macOS: Cmd+, switches to Settings tab
- On macOS: Menu bar shows custom commands under File
- On iOS: No behavior change — `.commands` silently ignored
- Multi-window: Only the key (frontmost) window responds to shortcuts

## Activity Log

- 2026-03-01T05:27:35Z – system – lane=planned – Prompt created.

---

### Updating Lane Status

To change a work package's lane, either:
1. **Edit directly**: Change the `lane:` field in frontmatter AND append activity log entry
2. **Use CLI**: `spec-kitty agent tasks move-task WP05 --to <lane> --note "message"`

**Valid lanes**: `planned`, `doing`, `for_review`, `done`
