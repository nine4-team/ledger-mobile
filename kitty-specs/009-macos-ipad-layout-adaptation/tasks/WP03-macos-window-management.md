---
work_package_id: WP03
title: macOS Window Management & Toolbar
lane: planned
dependencies: []
subtasks: [T014, T015, T016, T017, T018]
history:
- date: '2026-02-28'
  event: Created
---

# WP03: macOS Window Management & Toolbar

## Implementation Command

```bash
spec-kitty implement WP03 --base WP01
```

## Objective

Configure proper macOS window behavior: minimum/default sizes, unified toolbar style, and an account selector in the toolbar. Verify multi-window support works with independent navigation and shared data.

## Context

- **Current state**: `LedgerApp.swift` has a plain `WindowGroup` with no window sizing, no toolbar style, no `.commands {}`.
- **Target state**: WindowGroup with `.defaultSize()`, `.windowResizability(.contentMinSize)`, `.windowToolbarStyle(.unified)`. AccountToolbarMenu in the toolbar on macOS.
- **Key principle**: Window modifiers like `.defaultSize()` and `.windowToolbarStyle()` are silently ignored on iOS — safe to include unconditionally.

### Files to modify

| File | Change |
|------|--------|
| `LedgeriOS/LedgerApp.swift` | Add window scene modifiers |
| `LedgeriOS/Views/RootView.swift` | Add .frame(minWidth:minHeight:) |
| `LedgeriOS/Views/MainTabView.swift` | Add .toolbar { AccountToolbarMenu } with #if os(macOS) |

### Files to create

| File | Purpose |
|------|---------|
| `LedgeriOS/Components/AccountToolbarMenu.swift` | macOS-only toolbar account selector |

---

## Subtasks

### T014: Add Window Sizing Constraints

**Purpose**: Ensure the macOS window has a sensible default size and minimum size so layouts don't break when the window is too small.

**Steps**:
1. In `LedgerApp.swift`, add scene modifiers to `WindowGroup`:

```swift
var body: some Scene {
    WindowGroup {
        RootView()
            .environment(authManager)
            .environment(accountContext)
            .environment(projectContext)
            .preferredColorScheme(resolvedColorScheme)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
    }
    .defaultSize(width: 1000, height: 700)
    .windowResizability(.contentMinSize)
}
```

2. In `RootView.swift`, add a minimum frame:

```swift
var body: some View {
    // existing content...
    .frame(minWidth: 800, minHeight: 600)
}
```

**Why both**: `.defaultSize()` sets the initial window size on first launch. `.frame(minWidth:minHeight:)` prevents the user from shrinking below usable dimensions. `.windowResizability(.contentMinSize)` tells the system to respect the content's minimum size.

**These modifiers are silently ignored on iOS** — no conditional compilation needed.

**Validation**:
- [ ] macOS: New window opens at 1000x700
- [ ] macOS: Window cannot be resized below 800x600
- [ ] iOS: No visible change

---

### T015: Add Unified Toolbar Style

**Purpose**: Use the `.unified` toolbar style on macOS for a modern, compact toolbar appearance.

**Steps**:
1. In `LedgerApp.swift`, add `.windowToolbarStyle(.unified)` to WindowGroup:

```swift
WindowGroup {
    // ...
}
.defaultSize(width: 1000, height: 700)
.windowResizability(.contentMinSize)
.windowToolbarStyle(.unified)
```

**Note**: `.windowToolbarStyle()` is a macOS-only API but is available on WindowGroup which is cross-platform. On iOS, it's silently ignored. If the compiler requires a platform check, wrap in `#if os(macOS)` using a modifier extension.

**Validation**:
- [ ] macOS: Window shows unified toolbar (title + toolbar in one row)
- [ ] iOS: No visible change

---

### T016: Create AccountToolbarMenu Component

**Purpose**: On macOS, the window toolbar should include an account switcher showing the current account name with a dropdown of all accounts.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/AccountToolbarMenu.swift`:

```swift
import SwiftUI

#if os(macOS)
struct AccountToolbarMenu: View {
    @Environment(AccountContext.self) private var accountContext

    var body: some View {
        Menu {
            if let accounts = accountContext.discoveredAccounts {
                ForEach(accounts) { account in
                    Button {
                        Task {
                            await accountContext.selectAccount(account)
                        }
                    } label: {
                        HStack {
                            Text(account.name)
                            if account.id == accountContext.currentAccount?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Label(
                accountContext.currentAccount?.name ?? "No Account",
                systemImage: "person.crop.circle"
            )
        }
    }
}
#endif
```

2. Add the file to the Xcode project

**Important**: Check `AccountContext` for the actual property names — the code above uses `discoveredAccounts`, `currentAccount`, and `selectAccount()` as placeholders. Adjust to match the real API:
- Look for how `AccountGateView` reads available accounts
- Look for the account switching mechanism in the existing code

**Validation**:
- [ ] Component compiles on macOS
- [ ] Shows current account name
- [ ] Dropdown lists all discovered accounts
- [ ] Selecting an account triggers context switch

---

### T017: Add AccountToolbarMenu to MainTabView Toolbar

**Purpose**: Wire the account toolbar menu into the navigation toolbar on macOS only.

**Steps**:
1. In `MainTabView.swift`, add a `.toolbar` modifier (inside the TabView or on the outer container):

```swift
TabView(selection: $selectedTab) {
    // ... tabs ...
}
.tabViewStyle(.sidebarAdaptable)
.tint(BrandColors.primary)
#if os(macOS)
.toolbar {
    ToolbarItem(placement: .automatic) {
        AccountToolbarMenu()
    }
}
#endif
```

**Note**: The `#if os(macOS)` wraps the entire `.toolbar` modifier since `AccountToolbarMenu` only exists on macOS.

**Placement options**: `.automatic` lets the system decide. On macOS with unified toolbar, this typically places the item in the trailing area of the toolbar. If it doesn't look right, try `.primaryAction` or `.navigation`.

**Validation**:
- [ ] macOS: Account selector visible in window toolbar
- [ ] macOS: Clicking it shows dropdown of accounts
- [ ] iOS: No toolbar item visible (wrapped in #if os(macOS))

---

### T018: Verify Multi-Window Behavior

**Purpose**: Confirm that multiple macOS windows work correctly — independent navigation, shared data.

**Steps**:
1. Build and launch on macOS
2. Open a second window (File → New Window or Cmd+N if no creation context)
3. In window 1: navigate to a project detail view
4. In window 2: navigate to a different section (e.g., Inventory)
5. Verify: Each window has its own navigation state
6. Verify: Creating/editing data in one window is reflected in the other (via Firestore real-time listeners)
7. Verify: Account selector in both windows shows the same account
8. Verify: Switching account in one window switches in all windows (shared AccountContext)

**Why this works automatically**: SwiftUI's `WindowGroup` allocates independent `@State` per window. `@Observable` objects injected via `.environment()` are shared. Firestore listeners propagate changes.

**Validation**:
- [ ] Two windows can navigate independently
- [ ] Data changes propagate between windows
- [ ] Account context is shared across windows
- [ ] Closing one window doesn't affect the other

---

## Definition of Done

- [ ] macOS window opens at 1000x700 default size
- [ ] macOS window enforces 800x600 minimum
- [ ] Unified toolbar style applied
- [ ] AccountToolbarMenu visible in macOS toolbar
- [ ] Account switching works from toolbar
- [ ] Multi-window support verified
- [ ] iOS behavior unchanged

## Risks

| Risk | Mitigation |
|------|------------|
| AccountContext API doesn't match expected interface | Read AccountContext/AccountGateView before implementing AccountToolbarMenu |
| .windowToolbarStyle requires #if os(macOS) | Test compilation; if needed, use conditional extension |
| Multi-window state isolation issues | SwiftUI handles this automatically via WindowGroup; test to confirm |

## Reviewer Guidance

1. Verify window sizing constraints work (try resizing below 800x600 on macOS)
2. Verify AccountToolbarMenu reads from the real AccountContext properties
3. Verify multi-window navigation is truly independent
4. Check iOS is completely unaffected
