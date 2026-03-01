# Data Model: macOS + iPad Layout Adaptation

**Feature**: 009-macos-ipad-layout-adaptation
**Date**: 2026-02-28

---

## Overview

No new Firestore entities are introduced. All existing data models (Project, Transaction, Item, Space, Account, BudgetCategory, etc.) are shared across platforms unchanged.

This document covers **UI-level state** introduced for adaptive navigation, multi-window support, and platform-specific behavior.

---

## New UI State

### 1. Tab/Sidebar Selection

**Location**: `MainTabView.swift`

```swift
enum AppSection: String, CaseIterable {
    case projects
    case inventory
    case search
    case settings
}
```

**Current**: `selectedTab: Int` (0-3 via `.tag()`)
**After**: `selectedTab: AppSection` — used as `TabView(selection:)` binding. Stored via `@SceneStorage("selectedTab")` for per-window restoration.

### 2. Per-Window Navigation State

**Location**: Each tab's `NavigationStack`

Each window maintains its own navigation state via `@State` (automatically independent per window thanks to `WindowGroup`). No custom state management needed.

For state restoration across app launches, `@SceneStorage` stores the selected tab per window:

```swift
@SceneStorage("selectedTab") private var selectedTab: AppSection = .projects
```

### 3. Keyboard Shortcut Notifications

**Location**: `LedgerApp.swift` + individual list views

Custom notification names for menu bar → view communication:

```swift
extension Notification.Name {
    static let createProject = Notification.Name("createProject")
    static let createTransaction = Notification.Name("createTransaction")
    static let createItem = Notification.Name("createItem")
    static let createSpace = Notification.Name("createSpace")
    static let focusSearch = Notification.Name("focusSearch")
}
```

List views observe these and trigger their creation sheets. This is a pub/sub pattern — no shared mutable state.

### 4. Responsive Grid Column Count

**Location**: Views with grid layouts (budget categories, card grids on wide screens)

```swift
@State private var columnCount: Int = 1
```

Derived from container width via `onGeometryChange`. Not persisted — recalculated on layout.

### 5. Account Toolbar State (macOS only)

**Location**: `AccountToolbarMenu.swift`

No new state — reads from existing `AccountContext` environment object:
- `accountContext.currentAccount` — displayed in toolbar
- `accountContext.discoveredAccounts` — listed in dropdown
- `accountContext.selectAccount(_:)` — triggers switch

---

## Theme Constants Added

**Location**: `LedgeriOS/LedgeriOS/Theme/Dimensions.swift`

```swift
extension Dimensions {
    /// Maximum width for content in list/detail views (prevents stretching on wide screens)
    static let contentMaxWidth: CGFloat = 720

    /// Maximum width for form sheets on macOS
    static let formMaxWidth: CGFloat = 560

    /// Minimum card width for responsive grid calculation
    static let cardMinWidth: CGFloat = 320
}
```

---

## Entities Unchanged

The following Firestore entities are shared across all platforms with zero modifications:

- `Project` — projects collection
- `Transaction` — transactions subcollection
- `Item` — items subcollection
- `Space` — spaces subcollection
- `Account` — accounts collection
- `BudgetCategory` — budgetCategories subcollection
- `SpaceTemplate` — spaceTemplates subcollection
- `VendorDefaults` — vendorDefaults subcollection

All Codable conformances, CodingKeys, and field mappings remain identical.

---

## Platform Configuration (New Files)

### GoogleService-Info.plist (macOS)

A separate `GoogleService-Info.plist` is required for the macOS bundle identifier. Placed at:

```
LedgeriOS/LedgeriOS/Resources/macOS/GoogleService-Info.plist
```

Selected for macOS destination only in Xcode file membership.

### Entitlements

macOS requires App Sandbox entitlement:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

Added to shared entitlements file with platform-conditional build settings if needed.
