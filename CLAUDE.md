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

## Modal & Sheet Presentation

The RN app established a "bottom sheet first" convention — all forms, pickers, action menus, and multi-step flows present as bottom sheets. The SwiftUI app must maintain this UX.

**Default: `.sheet()` with `.presentationDetents()`.**
All modals, pickers, form inputs, and action menus use `.sheet()` configured as a bottom sheet. Include `.presentationDragIndicator(.visible)` for discoverability.

```swift
.sheet(isPresented: $showingForm) {
    FormContentView(...)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

**`.confirmationDialog()` — destructive confirmations only.** Maps to RN's `Alert.alert()`. Use for simple "Delete? Cancel / Confirm" prompts, not for action menus or pickers.

**Never use:** `.popover()` (floats on iPad, inconsistent with bottom-sheet convention) or `.fullScreenCover()` (unless explicitly justified — e.g., image gallery, camera).

**Extract reusable sheet components.** Don't inline sheet content. Mirror the RN pattern of extracted modal components (`FormBottomSheet`, `SetSpaceModal`, etc.) by creating SwiftUI equivalents as the app grows.

**Sheet-on-sheet sequencing.** When an action inside a sheet needs to open another sheet, dismiss the first sheet and use an `onDismiss` callback or `.onChange(of:)` to trigger the next presentation. Don't attempt to stack sheets.

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

## Feature Documentation

Each feature area gets a doc file at `docs/features/[name].md`. These capture what's specific to that feature — what the root CLAUDE.md doesn't already cover. The template is at `docs/features/_template.md`.

**When to create one:** When a feature spans 3+ files across layers (Views, Services, Logic, State) and has domain-specific patterns worth preserving. Create it during the first implementation session, not retroactively.

**When to update one:** When the feature's shape changes — new state, new sheet flows, new Firestore paths, new architectural decisions. Bug fixes and minor UI tweaks don't require doc updates.

**Updating docs is part of "done."** After completing feature work that changes the feature's shape, update the relevant doc. Specifically:

- New `@Observable` store added → document its purpose, what state it owns, and what creates it
- New sheet flow → document the trigger, dismissal pattern, and any sequencing with other sheets
- New Firestore collection or subcollection read/written → add it to the feature's Data section
- Architectural decision made → record it and the reason, so future work doesn't re-litigate it

## Shared Components

Reusable components in `Components/` that have a non-obvious usage contract.

| Component | Purpose | Key Props / Notes |
|-----------|---------|-------------------|
| `FormSheet` | Standard bottom sheet wrapper for forms | Handles detents, drag indicator, dismiss |
| `MultiStepFormSheet` | Multi-step form flow in a sheet | Step navigation, back/next/done |
| `ActionMenuSheet` | Action menu presented as bottom sheet | Takes `[ActionMenuItem]` |
| `ListStateControls` | Filter/sort/bulk-select toolbar for lists | Combines FilterMenu, SortMenu, BulkSelectionBar |
