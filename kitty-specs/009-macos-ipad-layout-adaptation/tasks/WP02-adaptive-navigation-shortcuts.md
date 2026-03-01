---
work_package_id: WP02
title: Adaptive Navigation & Keyboard Shortcuts
lane: planned
dependencies: []
subtasks: [T008, T009, T010, T011, T012, T013]
history:
- date: '2026-02-28'
  event: Created
---

# WP02: Adaptive Navigation & Keyboard Shortcuts

## Implementation Command

```bash
spec-kitty implement WP02 --base WP01
```

## Objective

Refactor the root navigation from the old `TabView` + `.tabItem` pattern to iOS 18+ `Tab` syntax with `.tabViewStyle(.sidebarAdaptable)`, producing a sidebar on Mac/iPad and tabs on iPhone — from a single declaration. Add a Mac menu bar with keyboard shortcuts for common actions.

## Context

- **Current state**: `MainTabView.swift` uses `TabView(selection:)` with `.tabItem` + `.tag(rawValue)` pattern. No keyboard shortcuts. No menu bar.
- **Target state**: iOS 18+ `Tab("Label", systemImage:) { }` syntax with `.tabViewStyle(.sidebarAdaptable)`. `LedgerCommands` struct providing Cmd+N, Cmd+F, Cmd+, shortcuts via `.commands {}`.
- **Key constraint**: iPhone must show bottom tab bar exactly as before. iPad shows adaptable sidebar/tabs. macOS shows permanent sidebar.

### Files to modify

| File | Change |
|------|--------|
| `LedgeriOS/Views/MainTabView.swift` | Full rewrite of body — Tab syntax, .sidebarAdaptable, enum rename |
| `LedgeriOS/LedgerApp.swift` | Add .commands { LedgerCommands() } to WindowGroup |
| `LedgeriOS/Views/Projects/ProjectsListView.swift` | Add .onReceive for Cmd+N notification |
| `LedgeriOS/Views/Inventory/InventoryView.swift` | Add .onReceive for Cmd+N notification |

### Files to create

| File | Purpose |
|------|---------|
| `LedgeriOS/LedgerCommands.swift` | Mac menu bar commands |
| `LedgeriOS/Notifications+Keyboard.swift` | Notification.Name extensions for keyboard dispatch |

---

## Subtasks

### T008: Refactor MainTabView to iOS 18+ Tab Syntax

**Purpose**: Replace the deprecated `.tabItem` + `.tag()` pattern with the iOS 18+ `Tab` content builder API and add `.tabViewStyle(.sidebarAdaptable)` for automatic sidebar/tab adaptation.

**Current code** (`MainTabView.swift`):
```swift
struct MainTabView: View {
    @SceneStorage("selectedTab") private var selectedTab = Tab.projects.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ProjectsListView()
                    .navigationDestination(for: Project.self) { ... }
            }
            .tabItem { Label("Projects", systemImage: "house") }
            .tag(Tab.projects.rawValue)
            // ... 3 more tabs
        }
        .tint(BrandColors.primary)
    }
}

extension MainTabView {
    enum Tab: String {
        case projects, inventory, search, settings
    }
}
```

**Target code**:
```swift
struct MainTabView: View {
    @SceneStorage("selectedTab") private var selectedTab: AppSection = .projects

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Projects", systemImage: "folder", value: .projects) {
                NavigationStack {
                    ProjectsListView()
                        .navigationDestination(for: Project.self) { project in
                            ProjectDetailView(project: project)
                        }
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
                        .navigationDestination(for: Item.self) { item in
                            ItemDetailView(item: item)
                        }
                        .navigationDestination(for: Transaction.self) { transaction in
                            TransactionDetailView(transaction: transaction)
                        }
                        .navigationDestination(for: Space.self) { space in
                            SpaceSearchDetailView(space: space)
                        }
                }
            }

            Tab("Settings", systemImage: "gear", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(BrandColors.primary)
    }
}
```

**Steps**:
1. Rename the `Tab` enum to `AppSection` (avoid collision with SwiftUI's `Tab` type)
2. Make `AppSection` conform to `CaseIterable` and keep `String` raw value and `Codable` conformance (needed for `@SceneStorage`)
3. Change `@SceneStorage("selectedTab")` type from `String` to `AppSection`
4. Replace each `NavigationStack { ... }.tabItem { }.tag()` block with `Tab("Label", systemImage:, value:) { NavigationStack { ... } }`
5. Add `.tabViewStyle(.sidebarAdaptable)` after the TabView
6. Keep `.tint(BrandColors.primary)`
7. Update tab icons: "house" → "folder" for Projects (sidebar icon convention)

**Important notes**:
- The `Tab` initializer requires the `value:` parameter when using `TabView(selection:)` binding
- `@SceneStorage` with a custom enum works if the enum is `RawRepresentable` with `String` raw value
- All `.navigationDestination(for:)` modifiers stay inside their respective `NavigationStack` — unchanged
- The Preview at the bottom of the file needs updating to match the new API

**Validation**:
- [ ] iPhone: Bottom tab bar with 4 tabs, identical to before
- [ ] iPad: Adaptive — user can toggle between floating tab bar and sidebar
- [ ] macOS: Permanent sidebar with 4 sections
- [ ] Tab selection persists across app restarts via @SceneStorage

---

### T009: Create LedgerCommands Struct

**Purpose**: Provide a Mac menu bar with keyboard shortcuts. `.commands {}` is silently ignored on iOS, so this is safe to include unconditionally.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/LedgerCommands.swift`:

```swift
import SwiftUI

struct LedgerCommands: Commands {
    var body: some Commands {
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
        }

        CommandGroup(after: .toolbar) {
            Button("Search") {
                NotificationCenter.default.post(name: .focusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
```

2. Add the file to the Xcode project

**Design decision**: Commands post notifications rather than directly manipulating state. This avoids tight coupling between the menu bar and specific views. The currently active view decides how to respond.

**Validation**:
- [ ] File compiles on both platforms
- [ ] On macOS, menu bar shows File → New Project, New Transaction, New Item
- [ ] Keyboard shortcuts appear in menu items

---

### T010: Add .commands {} to LedgerApp

**Purpose**: Wire the menu bar commands into the app's scene.

**Steps**:
1. In `LedgerApp.swift`, add `.commands { LedgerCommands() }` to the `WindowGroup`:

```swift
var body: some Scene {
    WindowGroup {
        RootView()
            .environment(authManager)
            .environment(accountContext)
            .environment(projectContext)
            .preferredColorScheme(resolvedColorScheme)
            // ... existing modifiers
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
    }
    .commands {
        LedgerCommands()
    }
}
```

**Note**: `.commands {}` is a Scene modifier (on WindowGroup), not a View modifier.

**Validation**:
- [ ] On macOS, menu bar includes custom commands
- [ ] On iOS, no visible change (commands silently ignored)

---

### T011: Define Notification.Name Extensions

**Purpose**: Create the notification names used by LedgerCommands and observed by list views.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Notifications+Keyboard.swift`:

```swift
import Foundation

extension Notification.Name {
    /// Cmd+N — create a new project
    static let createProject = Notification.Name("createProject")
    /// Cmd+Shift+N — create a new transaction
    static let createTransaction = Notification.Name("createTransaction")
    /// Cmd+Option+N — create a new item
    static let createItem = Notification.Name("createItem")
    /// Cmd+F — focus the search field
    static let focusSearch = Notification.Name("focusSearch")
    /// Cmd+, — open settings
    static let openSettings = Notification.Name("openSettings")
}
```

2. Add the file to the Xcode project

**Validation**:
- [ ] Notification names are accessible from both LedgerCommands and list views

---

### T012: Add Notification Observers to List Views

**Purpose**: List views respond to keyboard shortcut notifications by triggering their creation sheets.

**Steps**:
1. In `ProjectsListView.swift`, add an `.onReceive` modifier that listens for `.createProject` and sets the sheet-presenting state to `true`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .createProject)) { _ in
    showNewProject = true  // or whatever the @State var is named
}
```

2. In `InventoryView.swift` (or the relevant items list), add `.onReceive` for `.createItem`

3. For `.focusSearch`, the `UniversalSearchView` should focus its search field. Use `@FocusState` and set it on receiving the notification:

```swift
@FocusState private var isSearchFocused: Bool

// On the search field:
.focused($isSearchFocused)

// Observer:
.onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
    isSearchFocused = true
}
```

4. For `.openSettings`, the MainTabView can observe and switch tabs:

```swift
// In MainTabView:
.onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
    selectedTab = .settings
}
```

**Important**: Only add observers where the view already has the creation sheet flow. Don't add observers for flows that don't exist yet.

**Validation**:
- [ ] Cmd+N in Projects tab opens New Project sheet (macOS)
- [ ] Cmd+F focuses search field (macOS)
- [ ] Cmd+, switches to Settings tab (macOS)
- [ ] On iOS, no change (notifications not posted)

---

### T013: Verify Platform Behavior

**Purpose**: Confirm the navigation works correctly on all three platforms.

**Steps**:
1. **iPhone** (any simulator): Verify bottom tab bar with 4 tabs. Tap each tab. Navigate into a detail view. Switch tabs. Navigate back. Confirm behavior is identical to before.
2. **iPad** (simulator, landscape): Verify sidebar appears. Select each section. Toggle between sidebar and floating tab bar (if available).
3. **iPad** (simulator, portrait): Verify tab bar appears at bottom OR sidebar collapses appropriately.
4. **macOS**: Verify permanent sidebar. Click each section. Verify keyboard shortcuts work.
5. Verify `@SceneStorage("selectedTab")` persists selected tab across app launches.

**Validation**:
- [ ] iPhone: Tabs work identically to pre-change
- [ ] iPad landscape: Sidebar visible with all 4 sections
- [ ] iPad portrait: Tabs or collapsed sidebar (SwiftUI default behavior)
- [ ] macOS: Permanent sidebar, keyboard shortcuts functional
- [ ] Tab selection persists across launches

---

## Definition of Done

- [ ] MainTabView uses iOS 18+ Tab syntax with .tabViewStyle(.sidebarAdaptable)
- [ ] Tab enum renamed to AppSection
- [ ] LedgerCommands provides Cmd+N, Cmd+Shift+N, Cmd+Option+N, Cmd+F, Cmd+,
- [ ] .commands {} added to LedgerApp WindowGroup
- [ ] Notification-based dispatch wired to list views
- [ ] iPhone behavior identical to pre-change
- [ ] iPad shows sidebar in regular width, tabs in compact
- [ ] macOS shows permanent sidebar

## Risks

| Risk | Mitigation |
|------|------------|
| AppSection enum not compatible with @SceneStorage | Ensure String RawRepresentable conformance. Test persistence. |
| .sidebarAdaptable behavior unexpected on iPad | This is Apple's built-in behavior — accept defaults. File radars if needed. |
| Cmd+N conflicts with system "New Window" | Use CommandGroup(after: .newItem) to add alongside, not replace |
| Notification observers fire in wrong view | Notifications are broadcast — only views with the creation sheet should observe |

## Reviewer Guidance

1. Compare iPhone tab bar before/after — should be pixel-identical
2. Verify all 4 NavigationStack instances work independently in sidebar mode
3. Check that .navigationDestination modifiers are inside NavigationStack (not on Tab)
4. Confirm Cmd shortcuts appear in macOS menu bar
