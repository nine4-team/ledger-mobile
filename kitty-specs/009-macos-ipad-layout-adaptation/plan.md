# Implementation Plan: macOS + iPad Layout Adaptation

**Branch**: `009-macos-ipad-layout-adaptation` | **Date**: 2026-02-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `kitty-specs/009-macos-ipad-layout-adaptation/spec.md`

---

## Summary

Add a native macOS destination to the existing Ledger iOS target and adapt all screens to work across iPhone, iPad, and Mac from a single shared codebase. The approach uses SwiftUI's built-in `.tabViewStyle(.sidebarAdaptable)` for adaptive navigation (sidebar on Mac/iPad, tabs on iPhone), `onGeometryChange` for responsive card layouts, and `WindowGroup` for multi-window support on macOS. No new data entities — this is purely a UI/navigation layer change.

## Technical Context

**Language/Version**: Swift 6.0 (strict concurrency enabled)
**Primary Dependencies**: Firebase Swift SDK (Auth, Firestore, Storage), GoogleSignIn-iOS v7+ — both support macOS natively
**Storage**: Firestore (unchanged)
**Testing**: Swift Testing framework (`@Test`, `#expect`, `@Suite`)
**Target Platform**: iOS 18+ (iPhone/iPad), macOS 15+ (native SwiftUI, not Catalyst)
**Project Type**: Multi-platform single target (rename `LedgeriOS` → `Ledger`)
**Performance Goals**: macOS app launches to main screen within 5 seconds. No frame drops during navigation/layout transitions.
**Constraints**: ~90% shared code. iPhone behavior must be identical to pre-Phase 6. Offline-first preserved on all platforms.
**Scale/Scope**: 233 Swift files. ~44 views, ~48 components, ~18 modals. 4 tabs.

## Constitution Check

*No constitution file found. Section skipped.*

## Project Structure

### Documentation (this feature)

```
kitty-specs/009-macos-ipad-layout-adaptation/
├── plan.md              # This file
├── research.md          # Phase 0 output — tech decisions with sources
├── data-model.md        # Phase 1 output — UI-level state model (no new Firestore entities)
└── tasks.md             # Phase 2 output (NOT created by /spec-kitty.plan)
```

### Source Code (repository root)

```
LedgeriOS/LedgeriOS/
├── LedgerApp.swift              # @main — WindowGroup, .commands{}, .defaultSize()
├── Auth/
│   └── AuthManager.swift        # #if os() for GoogleSignIn presentation
├── Views/
│   ├── RootView.swift           # Auth gate (unchanged logic)
│   ├── MainTabView.swift        # Refactor → Tab syntax + .sidebarAdaptable
│   ├── AccountGateView.swift    # Layout adaptation for wider screens
│   └── [all other views]        # maxWidth constraints, responsive grids
├── Components/
│   ├── AdaptiveContentWidth.swift  # NEW — reusable maxWidth wrapper
│   └── [existing components]       # Card components get maxWidth
├── Theme/
│   └── Dimensions.swift         # Add contentMaxWidth, sidebarWidth constants
└── Platform/                    # NEW — platform-specific utilities
    └── PlatformPresenting.swift # GoogleSignIn platform abstraction
```

**Structure Decision**: Single multi-platform target. All files shared. Platform differences isolated via `#if os()` conditionals and a thin `Platform/` utilities folder. No separate macOS target.

---

## Engineering Alignment

### Confirmed Decisions

| Decision | Choice | Source |
|----------|--------|--------|
| Target strategy | Multi-platform single target, rename to `Ledger` | Planning Q1 |
| Navigation | `.tabViewStyle(.sidebarAdaptable)` | Axiom `axiom-swiftui-nav` Pattern 5 |
| Layout adaptation | `onGeometryChange` + `frame(maxWidth:)` | Axiom `axiom-swiftui-layout` |
| Multi-window | `WindowGroup` + `@SceneStorage` (built-in) | Axiom `axiom-app-composition` |
| GoogleSignIn macOS | `#if os()` conditional in AuthManager | Research §3 |
| Window management | `.defaultSize()` + `.windowResizability(.contentMinSize)` | Research §6 |
| Sheets on macOS | No changes — detents silently ignored | Research §8 |

### Key Architectural Decisions

#### 1. Navigation: `.tabViewStyle(.sidebarAdaptable)` (not manual split/tab switching)

The existing `MainTabView` will be refactored from the current `TabView` + `.tabItem` pattern to the iOS 18+ `Tab` syntax with `.tabViewStyle(.sidebarAdaptable)`. This single declaration produces:
- Bottom tab bar on iPhone
- Adaptable tab bar / sidebar on iPad (user-toggleable)
- Permanent sidebar on macOS

No manual `@Environment(\.horizontalSizeClass)` switching needed.

```swift
// Before (current)
TabView(selection: $selectedTab) {
    NavigationStack { ProjectsListView() }
        .tabItem { Label("Projects", systemImage: "house") }
    // ...
}

// After
TabView {
    Tab("Projects", systemImage: "folder") {
        NavigationStack { ProjectsListView() }
    }
    Tab("Inventory", systemImage: "archivebox") {
        NavigationStack { InventoryView() }
    }
    Tab("Search", systemImage: "magnifyingglass") {
        NavigationStack { UniversalSearchView() }
    }
    Tab("Settings", systemImage: "gear") {
        NavigationStack { SettingsView() }
    }
}
.tabViewStyle(.sidebarAdaptable)
```

#### 2. Responsive Layouts: Container-Responsive, Not Device-Specific

All card lists and detail views will use container-responsive width constraints:

```swift
// Reusable wrapper for readable content width
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

For responsive grids (e.g., budget category cards, project cards on wide screens):

```swift
.onGeometryChange(for: Int.self) { proxy in
    max(1, Int(proxy.size.width / 360))  // ~360pt per column
} action: { newCount in
    columnCount = newCount
}
```

**Anti-patterns prohibited**: `UIDevice.idiom`, `UIScreen.main.bounds`, unconstrained `GeometryReader`.

#### 3. macOS Window Setup

```swift
@main
struct LedgerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 800, minHeight: 600)
                .environment(authManager)
                .environment(accountContext)
                .environment(projectContext)
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            LedgerCommands()
        }
    }
}
```

Window constraints and `.commands {}` are silently ignored on iOS — safe to include unconditionally.

#### 4. Keyboard Shortcuts & Menu Bar

```swift
struct LedgerCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Project") { NotificationCenter.default.post(name: .createProject, object: nil) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Transaction") { NotificationCenter.default.post(name: .createTransaction, object: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("Search") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                .keyboardShortcut("f", modifiers: .command)
        }
    }
}
```

Context-sensitive Cmd+N: The menu bar command posts a notification. The currently active list view observes it and triggers the appropriate creation sheet. This avoids tight coupling between the menu bar and specific views.

#### 5. macOS Toolbar Account Selector (FR-3)

On macOS only, the window toolbar includes an account switcher:

```swift
.toolbar {
    #if os(macOS)
    ToolbarItem(placement: .automatic) {
        AccountToolbarMenu(accountContext: accountContext)
    }
    #endif
}
```

`AccountToolbarMenu` renders the current account name with a dropdown listing all accounts. Selecting one triggers the same account-switching logic as `AccountGateView`.

#### 6. GoogleSignIn Platform Abstraction

```swift
// Platform/PlatformPresenting.swift
#if os(iOS)
import UIKit
func platformSignIn() async throws -> GIDSignInResult {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let rootVC = windowScene.windows.first?.rootViewController else {
        throw AuthError.noPresentingContext
    }
    return try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
}
#elseif os(macOS)
import AppKit
func platformSignIn() async throws -> GIDSignInResult {
    guard let window = NSApplication.shared.keyWindow else {
        throw AuthError.noPresentingContext
    }
    return try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
}
#endif
```

`AuthManager.signInWithGoogle()` calls `platformSignIn()` instead of directly referencing UIViewController.

#### 7. Multi-Window (macOS)

No custom state management needed. SwiftUI's `WindowGroup` automatically:
- Allocates independent `@State` / `@StateObject` per window
- Shares `@Observable` objects from `.environment()` across all windows
- Provides `@SceneStorage` for per-window state restoration

Firestore real-time listeners in shared managers (ProjectContext, AccountContext) propagate updates to all windows automatically.

---

## Implementation Phases

### Phase A: Project Setup & Platform Foundation

**Goal**: macOS builds and launches with existing UI (even if layout isn't optimized yet).

1. Rename target `LedgeriOS` → `Ledger`
2. Add macOS as supported destination in Xcode
3. Add macOS App Sandbox entitlement with Outgoing Connections
4. Register macOS app in Firebase Console, add macOS `GoogleService-Info.plist`
5. Wrap all UIKit references in `#if canImport(UIKit)` (primarily `AuthManager.swift`)
6. Create `Platform/PlatformPresenting.swift` for GoogleSignIn abstraction
7. Build and launch on macOS — verify auth flow works

### Phase B: Adaptive Navigation

**Goal**: Sidebar on Mac/iPad, tabs on iPhone. All 4 sections navigable.

1. Refactor `MainTabView` to iOS 18+ `Tab` syntax + `.tabViewStyle(.sidebarAdaptable)`
2. Verify each tab's `NavigationStack` works independently in sidebar mode
3. Add `.commands {}` with keyboard shortcuts to `LedgerApp`
4. Create notification-based Cmd+N dispatch for context-sensitive creation
5. Test: iPhone tabs unchanged, iPad sidebar toggleable, Mac sidebar permanent

### Phase C: Window Management (macOS)

**Goal**: Proper macOS window behavior with toolbar and multi-window.

1. Add `.defaultSize()`, `.windowResizability(.contentMinSize)`, `.frame(minWidth:minHeight:)`
2. Add `.windowToolbarStyle(.unified)`
3. Create `AccountToolbarMenu` for macOS toolbar
4. Test multi-window: open 2 windows, verify independent navigation, shared data updates

### Phase D: Adaptive Card Layouts

**Goal**: All views render at readable widths on wide screens.

1. Add `contentMaxWidth` constant to `Dimensions.swift`
2. Create `AdaptiveContentWidth` wrapper component
3. Apply to all list views (cards constrained, centered on wide screens)
4. Apply to all detail views (readable content width)
5. Add responsive grid columns to budget/category card views via `onGeometryChange`
6. Test at various window sizes: 800px, 1440px, 2560px

### Phase E: Polish & Testing

**Goal**: No regressions on iPhone. All scenarios from spec pass.

1. Test all 7 spec scenarios
2. Verify all sheet/modal flows work on macOS (detents silently ignored)
3. Test keyboard shortcuts (Cmd+N, Cmd+F, Cmd+,, Cmd+W, Cmd+Q)
4. Test iPad orientation transitions (landscape sidebar ↔ portrait tabs)
5. Verify offline-first behavior on macOS (Firestore cache-first)
6. Write Swift Testing tests for platform abstraction layer and navigation state

---

## Risk Mitigations

| Risk | Mitigation |
|------|------------|
| NavigationSplitView edge cases during iPad rotation | Using `.sidebarAdaptable` avoids manual split view — Apple handles transitions |
| Multi-window state isolation | SwiftUI's `WindowGroup` handles this automatically — no custom code |
| Sheets look different on macOS | Accepted — macOS sheets are window-attached. Detents silently ignored. |
| GoogleSignIn macOS API differences | Isolated in `Platform/PlatformPresenting.swift` with `#if os()` |
| UIKit references breaking macOS build | Audit complete — only `AuthManager.swift` imports UIKit. One file to fix. |
| App Sandbox blocking Firebase | Enable `com.apple.security.network.client` entitlement |
| Wide-screen card stretching | `AdaptiveContentWidth` wrapper with `contentMaxWidth` constant |

## Complexity Tracking

*No constitution violations to justify.*
