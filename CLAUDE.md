# Ledger Mobile

Native SwiftUI iOS app, migrating from a React Native (Expo) codebase that lives in `src/`. The RN app runs in parallel until the SwiftUI version reaches feature parity. Migration plan: `.plans/swiftui-migration.md`.

## Project Structure

- **`LedgeriOS/`** — Xcode project (SwiftUI, iOS target). All new work goes here.
- **`src/`** — Legacy React Native app. Reference only — do not modify.
- **`reference/screenshots/dark/`** — Dark mode screenshots are the source of truth for visual parity.
- **Dependencies:** Swift Package Manager only. No CocoaPods, no Carthage.
  - Firebase Swift SDK (Auth, Firestore, Storage)
  - GoogleSignIn-iOS

## Architecture

### State Management

Use `@Observable` classes with `@MainActor` isolation. Inject via SwiftUI `.environment()`.

```swift
@MainActor
@Observable
final class SomeManager {
    // State properties — no @Published needed with @Observable
    var items: [Item] = []
}

// In App or parent view:
.environment(someManager)

// In child views:
@Environment(SomeManager.self) private var someManager
```

Reference: `LedgeriOS/LedgeriOS/Auth/AuthManager.swift`

### Firestore Models

All Firestore entities are Swift structs conforming to `Codable`. Use `CodingKeys` for field name mapping and custom `init(from:)` for legacy field migrations or default values.

```swift
struct Item: Codable, Identifiable {
    let id: String
    var name: String
    var status: ItemStatus

    enum CodingKeys: String, CodingKey {
        case id, name, status
        // Legacy: case description  (migrated to `name`)
    }
}
```

### Navigation

One `NavigationStack` per tab. Use `NavigationLink(value:)` with `.navigationDestination(for:)` — not the deprecated label-based `NavigationLink`.

```swift
NavigationStack {
    List(items) { item in
        NavigationLink(value: item) {
            ItemRow(item: item)
        }
    }
    .navigationDestination(for: Item.self) { item in
        ItemDetailView(item: item)
    }
}
```

### App Entry Point

`LedgerApp` (`@main`) → `RootView` (auth gate) → `MainTabView` (4 tabs: Projects, Inventory, Search, Settings).

## Offline-First Principles

The native Firestore SDK handles cache-first reads and offline persistence automatically — no workarounds needed. But these principles still apply:

1. **No spinners of doom.** Never block UI on server acknowledgment. If local/cached data exists, show it immediately.
2. **Optimistic UI.** Navigate and update state immediately after a write. Don't wait for server confirmation.
3. **Only block on connectivity for:** Firebase Storage uploads (actual bytes) and Firebase Auth operations. All Firestore reads/writes must work offline.

## Theming

All design tokens live in `LedgeriOS/LedgeriOS/Theme/`:

| File | Contents |
|------|----------|
| `BrandColors.swift` | Brand primary, adaptive light/dark colors (backgrounds, text, borders, buttons, inputs, destructive). Uses asset catalog colorsets in `Assets.xcassets/Colors/`. |
| `StatusColors.swift` | Budget status colors (met, in-progress, missed, overflow) and transaction badge colors. |
| `Spacing.swift` | Spacing scale (`xs` 4pt through `xxxl` 48pt) plus semantic aliases (`screenPadding`, `cardPadding`, `cardListGap`). |
| `Typography.swift` | Type scale (`h1`–`h3`, `body`, `small`, `caption`, `button`, `label`) plus `.sectionLabelStyle()` modifier. |
| `Dimensions.swift` | Corner radii (`cardRadius` 12, `buttonRadius` 8, `inputRadius` 8) and border widths. |

Use these constants instead of inline magic numbers. Adaptive colors auto-switch between light and dark mode via the asset catalog — no `@Environment(\.colorScheme)` branching needed in most cases.

## Axiom Skills

This is a SwiftUI/iOS project. **Use Axiom skills for architecture decisions and best practices before writing code.** Key domains:

- `axiom-ios-ui` — SwiftUI patterns, component structure, HIG compliance
- `axiom-ios-data` — Firestore/persistence patterns
- `axiom-swift-concurrency` — async/await, actor isolation, Sendable
- `axiom-ios-build` — build failures, SPM issues, Xcode problems
- `axiom-swift-testing` — Swift Testing framework (`@Test`, `#expect`, `@Suite`)
- `axiom-swiftui-nav` — navigation architecture (NavigationStack, deep linking)
- `axiom-codable` — Codable patterns for Firestore model serialization

## Testing

Use **Swift Testing** framework (not XCTest) for all new tests. The global CLAUDE.md test-first workflow applies — plan → write tests → implement → iterate.

For Firestore service testing, extract business logic into pure functions that can be tested without a live Firestore connection. Mock the Firestore layer at the boundary, not inside the logic.

## UI Copy

Button labels use title case with lowercase prepositions: `Save to Draft`, `Add New Item`.
