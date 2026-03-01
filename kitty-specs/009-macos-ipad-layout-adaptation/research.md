# Research: macOS + iPad Layout Adaptation

**Feature**: 009-macos-ipad-layout-adaptation
**Date**: 2026-02-28

---

## 1. Multi-Platform Target Strategy

**Decision**: Single multi-platform target (rename `LedgeriOS` → `Ledger`), add macOS as a supported destination in Xcode.

**Rationale**: Apple's recommended approach for SwiftUI apps. One target, one set of build settings, all source files shared by default. Platform-specific code uses `#if os(iOS)` / `#if os(macOS)` or `#if canImport(UIKit)` / `#if canImport(AppKit)`.

**Alternatives considered**:
- Separate macOS target: More control over build settings but doubles maintenance burden (every new file must be added to both targets, SPM deps linked separately, two sets of build settings). Rejected — overhead not justified given shared codebase goal.
- Mac Catalyst: Runs iOS binary on Mac via translation layer. Rejected — spec explicitly requires native SwiftUI macOS, not Catalyst.

**What changes when adding macOS destination**:
- `SUPPORTED_PLATFORMS` expands to include `macosx`
- App Sandbox entitlement required for Mac App Store (must enable Outgoing Connections for Firebase/GoogleSignIn)
- `LSApplicationCategoryType` key needed in Info.plist for macOS
- Any UIKit references must be wrapped in `#if canImport(UIKit)`
- "Designed for iPad" Mac App Store listing is automatically removed when native Mac app is published

**Sources**: [Apple: Configuring a Multiplatform App Target](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target), [WWDC22-110371](https://developer.apple.com/videos/play/wwdc2022/110371/)

---

## 2. Adaptive Navigation — `.tabViewStyle(.sidebarAdaptable)`

**Decision**: Use `.tabViewStyle(.sidebarAdaptable)` on the root `TabView` instead of manual `NavigationSplitView` / `TabView` switching.

**Rationale**: Apple's built-in adaptive container (iOS 18+). Single declaration, platform-appropriate rendering with zero manual size class switching.

**Platform behavior**:

| Platform | Rendering |
|----------|-----------|
| iPhone (compact) | Standard bottom tab bar |
| iPad | Adaptive — user can toggle between floating top tab bar and sidebar |
| macOS | Always renders as sidebar (permanent) |

**Key APIs**:
- `Tab("Label", systemImage: "icon") { content }` — iOS 18+ tab syntax
- `TabSection("Group Name") { ... }` — collapsible groups in sidebar mode
- `Tab(role: .search)` — special placement in sidebar
- Each `Tab` wraps its own `NavigationStack` for per-tab navigation

**Alternatives considered**:
- Manual `NavigationSplitView` + `TabView` switching via `@Environment(\.horizontalSizeClass)`: More code, must sync selection state between two representations, easy to introduce bugs during orientation changes.
- Keeping `TabView` with no sidebar: Doesn't adapt to wider screens on Mac/iPad.

**Sources**: Axiom `axiom-swiftui-nav` Pattern 5, [Apple: Enhancing Your App Content with Tab Navigation](https://developer.apple.com/documentation/SwiftUI/Enhancing-your-app-content-with-tab-navigation)

---

## 3. GoogleSignIn-iOS — macOS Support

**Decision**: Use platform-conditional compilation in `AuthManager` for sign-in presentation.

**Confirmed**: `GoogleSignIn-iOS` SPM package supports macOS natively (`.macOS(.v10_15)` in Package.swift).

**API difference**:
- iOS: `GIDSignIn.sharedInstance.signIn(withPresenting: viewController)` — takes `UIViewController`
- macOS: `GIDSignIn.sharedInstance.signIn(withPresenting: window)` — takes `NSWindow`

**Implementation pattern**:
```swift
#if os(iOS)
    let rootVC = // get UIViewController from UIWindowScene
    GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { ... }
#elseif os(macOS)
    let window = NSApplication.shared.keyWindow!
    GIDSignIn.sharedInstance.signIn(withPresenting: window) { ... }
#endif
```

**macOS-specific requirement**: Add `$(AppIdentifierPrefix)$(CFBundleIdentifier)` as first item in keychain access group entitlement for credential storage.

**Alternatives considered**: None — GoogleSignIn-iOS is the only official SDK.

**Sources**: [GoogleSignIn-iOS GitHub](https://github.com/google/GoogleSignIn-iOS), [Google Sign-In Integration Guide](https://developers.google.com/identity/sign-in/ios/sign-in)

---

## 4. Firebase Swift SDK — macOS Support

**Decision**: No changes needed to SPM dependencies. Firebase Auth, Firestore, and Storage all support macOS natively.

**Confirmed**: Firebase `Package.swift` declares `.macOS(.v10_15)` as a supported platform (separate from `.macCatalyst(.v15)`).

**Known gotchas**:
1. **App Sandbox networking**: macOS sandbox requires `com.apple.security.network.client` entitlement for all Firebase network calls. Without it, sandboxed builds fail with "Host name resolution failed."
2. **Firestore binary distribution**: Works for macOS. Only visionOS requires source distribution.
3. **Firebase Analytics**: Distributed as closed-source binary but does support macOS.
4. **GoogleService-Info.plist**: Need a separate plist for the macOS bundle identifier. Register the macOS app in Firebase Console separately.

**Sources**: [Firebase iOS SDK GitHub](https://github.com/firebase/firebase-ios-sdk), [Firebase SPM Installation](https://firebase.google.com/docs/ios/installation-methods)

---

## 5. Adaptive Card Layouts — Container-Responsive Design

**Decision**: Use `onGeometryChange` for responsive column counts and `frame(maxWidth:)` for readable content widths. No device checks.

**Rationale**: Axiom `axiom-swiftui-layout` skill strongly recommends against device identity checks (`UIDevice.idiom`, `UIScreen.main.bounds`). Respond to container size, not device.

**Key patterns**:

| Need | Use | Not |
|------|-----|-----|
| Responsive grid columns | `onGeometryChange` | `UIDevice.idiom` |
| Max content width | `frame(maxWidth: 720)` | Device-specific branches |
| Pick between variants | `ViewThatFits` | `if width > X` |
| Animated H↔V switch | `AnyLayout` + condition | Conditional stacks |

**Anti-patterns to avoid**:
- `UIScreen.main.bounds` — reports full screen, not window size in multitasking
- `UIDevice.current.userInterfaceIdiom` — iPad in 1/3 Split View is narrower than iPhone 14 Pro Max
- Unconstrained `GeometryReader` — greedy, takes all available space

**Sources**: Axiom `axiom-swiftui-layout`, [WWDC 2025-208](https://developer.apple.com/videos/play/wwdc2025/208/)

---

## 6. macOS Window Management

**Decision**: Use `.defaultSize()`, `.windowResizability(.contentMinSize)`, and `.frame(minWidth:minHeight:)` for window constraints.

**Key APIs**:

```swift
WindowGroup {
    ContentView()
        .frame(minWidth: 800, minHeight: 600)
}
.defaultSize(width: 1000, height: 700)
.windowResizability(.contentMinSize)
.windowToolbarStyle(.unified)
```

**Window toolbar styles**: `.automatic`, `.unified` (title + toolbar in one row), `.unifiedCompact` (shorter), `.expanded` (toolbar below title).

**Menu bar via `.commands {}`**:
- `CommandMenu("Name") { ... }` — add new menu
- `CommandGroup(after: .newItem) { ... }` — insert into existing menu
- `CommandGroup(replacing: .newItem) { }` — remove system menu items
- `.commands {}` is silently ignored on iOS — safe to include unconditionally

**Sources**: [Apple: defaultSize](https://developer.apple.com/documentation/swiftui/scene/defaultsize(width:height:)), [Apple: WindowResizability](https://developer.apple.com/documentation/swiftui/windowresizability), [WWDC24-10149](https://developer.apple.com/videos/play/wwdc2024/10149/)

---

## 7. Multi-Window Support

**Decision**: Use `WindowGroup` (already in use). Each window automatically gets independent `@State`/`@StateObject`. Shared state via `.environment()`.

**Key behaviors**:
- SwiftUI allocates new storage for `@State` and `@StateObject` per window
- Shared `@Observable` objects injected via `.environment()` are shared across all windows
- `@SceneStorage` provides per-window state restoration
- `@Environment(\.openWindow)` opens additional windows
- `@Environment(\.dismiss)` closes the current window

**No custom state management needed**: Existing Firestore real-time listeners in shared `@Observable` managers (ProjectContext, AccountContext) will propagate updates to all windows automatically.

**Sources**: Axiom `axiom-app-composition`, [Apple: WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup)

---

## 8. Sheet Presentation on macOS

**Decision**: Existing `.sheet()` + `.presentationDetents()` code works on macOS — detents are silently ignored, sheets present as standard macOS window-attached sheets. No changes needed.

**Behavior**:
- iOS: Bottom sheet with drag handle and detent stops
- macOS: Standard sheet attached to parent window (no detents, no drag indicator)
- `.presentationDetents()` and `.presentationDragIndicator()` are silently ignored on macOS

**No macOS-specific adjustments required for sheets.**

---

## 9. Current Codebase Audit — Files Requiring Platform Adaptation

**UIKit dependencies (must be conditionally compiled)**:
- `AuthManager.swift` — imports UIKit, uses UIViewController for GoogleSignIn

**No existing size class or platform detection**: Zero usage of `horizontalSizeClass`, `verticalSizeClass`, or `#if os()` in the current 233 Swift files. Clean slate for adaptation.

**Sheet usage**: 71 uses of `.sheet()` across 29 files with `.presentationDetents()`. All work on macOS as-is.

**Layout patterns**: All views use `.frame(maxWidth: .infinity)` — will stretch on wide screens. Need `maxWidth` capping.

**Files most affected by navigation restructuring**:
- `LedgerApp.swift` — scene/window setup, `.commands {}`, `.defaultSize()`
- `MainTabView.swift` — refactor to iOS 18+ `Tab` syntax + `.tabViewStyle(.sidebarAdaptable)`
- `RootView.swift` — potential adjustments for window-level auth state
- `AuthManager.swift` — `#if os()` for GoogleSignIn presentation

**Files needing maxWidth constraints** (card lists, detail views):
- All list views: `ProjectsListView`, `InventoryView`, `UniversalSearchView`
- All detail views: `ProjectDetailView`, `ItemDetailView`, `TransactionDetailView`, `SpaceDetailView`
- All card components: `ProjectCard`, `ItemCard`, `TransactionCard`, `SpaceCard`
- Form sheets: `NewProjectView`, `NewTransactionView`, `NewItemView`, `NewSpaceView`
