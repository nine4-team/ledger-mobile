# Ledger Mobile

Native SwiftUI iOS app for inventory and project ledger management.

## Project Structure

- **`LedgeriOS/`** — Xcode project (SwiftUI, iOS target).
- **`firebase/`** — Backend: Firestore rules, Cloud Functions, seed data.
- **`mcp-server/`** — Claude MCP server for Ledger data access.
- **`reference/screenshots/dark/`** — Dark mode design reference screenshots.
- **Dependencies:** Swift Package Manager only. No CocoaPods, no Carthage.
  - Firebase Swift SDK (Auth, Firestore, Storage)
  - GoogleSignIn-iOS

## Running the App

**The app runs against production Firebase by default.** Build and run from Xcode using the `LedgeriOS (Emulator)` scheme — despite the name, this is the day-to-day scheme and it talks to production Firestore/Auth/Storage unless `FirebaseEmulatorConfig` is explicitly toggled on. The "(Emulator)" suffix is vestigial from when emulator-first was the default.

### Build-Only Check

To verify code compiles, use xcodebuild directly:

```bash
cd LedgeriOS && xcodebuild build -scheme "LedgeriOS (Emulator)" -destination 'platform=iOS Simulator,name=iPhone 17e' -derivedDataPath DerivedData -quiet 2>&1 | tail -5
```

### Deploying Firestore Rules

After editing `firebase/firestore.rules`, deploy them to production:

```bash
firebase deploy --only firestore:rules
```

Local edits to the rules file have **no effect on the running app** until deployed. If you see "Missing or insufficient permissions" after adding or modifying a rule, the most likely cause is that the rules haven't been deployed yet.

## Release & Deployment

Before releasing, check `git status --short` and separate intentional release changes from unrelated dirty files. Run focused tests for the feature being shipped; for financial access / invite work, use:

```bash
xcodebuild -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:LedgeriOSTests/FinancialAccessPolicyTests
```

### TestFlight

Use Bundler-managed Fastlane from the repo root. The lane reads the App Store Connect API key from `~/.appstoreconnect/private_keys/AuthKey_X5SX4S7NW5.p8` by default, uses team `5VHL56HV63`, bundle id `apps.nine4.ledger`, project `LedgeriOS/LedgeriOS.xcodeproj`, scheme `LedgeriOS`, and version `1.0` unless overridden.

```bash
TESTFLIGHT_CHANGELOG='Short release note.' bundle exec fastlane ios upload_testflight
```

For external testers:

```bash
TESTFLIGHT_CHANGELOG='Short release note.' bundle exec fastlane ios external_testflight
```

`upload_testflight` uploads the build and distributes it to internal testers only. External testers do not get the build until it is explicitly attached to an external group. To distribute an already-uploaded build, use the wrapper script:

```bash
./scripts/distribute-testflight-external.sh <build-number> --groups "External Testing" --changelog "Short release note."
```

Fastlane checks App Store Connect and picks the next TestFlight build number for the current marketing version. If a duplicate build or signing error occurs, inspect the latest TestFlight build before rerunning with an explicit `BUILD_NUMBER`. External distribution may require Beta App Review; do not treat the build as available to external testers until Fastlane/App Store Connect reports that it was distributed to the external group.

### macOS Direct Distribution

Ledger's macOS build is direct-distributed and uses Sparkle for in-app updates. See `docs/macos-auto-updates.md` for the full notes.

For a first-install installer DMG:

```bash
./scripts/build-macos-dmg.sh
```

That archives the macOS build, exports with Developer ID signing, creates `/tmp/Ledger.dmg`, notarizes/staples it with the `ledger-notarize` notarytool profile, and copies it to `~/Desktop/Ledger.dmg`.

For Sparkle updates:

```bash
./scripts/build-macos-sparkle-update.sh
```

That archives/exports the macOS app, notarizes/staples it, creates `firebase/hosting/sparkle/Ledger-<version>-<build>.zip`, writes release notes if missing, and regenerates `firebase/hosting/sparkle/appcast.xml`.

Deploy the staged Sparkle update and appcast to Firebase Hosting with either:

```bash
DEPLOY=1 ./scripts/build-macos-sparkle-update.sh
```

or, if the Sparkle files are already staged:

```bash
firebase deploy --only hosting
```

The production appcast URL is `https://ledger-nine4.web.app/sparkle/appcast.xml`.

### Optional: Running Against the Local Emulator

There is a `scripts/dev-native.mjs` workflow that boots Firebase emulators (Auth, Firestore, Storage) with seeded data. This is **not** the day-to-day workflow — only use it when you specifically want to test against an isolated local environment (e.g., destructive integration tests). See `LedgeriOSTests/CLAUDE.md` for the integration-test setup that requires it.

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

### Entity Relationships

Cross-entity lookups use the **owner's ID array**, not a back-reference on the child. The canonical direction is documented in `docs/specs/data-model.md`.

| Relationship | Canonical lookup | Field |
|---|---|---|
| Transaction → Items | Transaction owns the IDs | `transaction.itemIds: [String]` |

When resolving a transaction's items, filter from the items collection using the transaction's `itemIds` array — **not** by matching `item.transactionId`. The `transactionId` field on Item exists but is a cache back-reference, not the source of truth.

### Inventory Movements

The system uses a **per-batch inventory movement transaction** model. See [docs/specs/sale-transactions.md](docs/specs/sale-transactions.md) for the active spec, [docs/specs/inventory-as-store.md](docs/specs/inventory-as-store.md) for the conceptual model, and [docs/specs/canonical-sales.md](docs/specs/canonical-sales.md) for the legacy model preserved for historical reads.

Key invariants:
- **Each inventory movement is a new immutable transaction.** No long-lived aggregators. Inventory → project writes a `Purchase` from inventory. Project → inventory writes either a `Return` when the item came from inventory, or a `Sale` only when the business is acquiring a project-originated item into inventory. Shape fields (`amountCents`, `itemIds`, `budgetCategoryId`, `type`, `source`, `projectId`) are locked after creation by Firestore security rules. Mutable fields: `notes`, `status`, `updatedAt`.
- **Project → inventory is origin-aware.** Items that came from inventory go home via a Return transaction with `source: "Business Inventory"`. Items that originated in the project use the Sale-to-Inventory path.
- **Inventory movement price basis is directional.** Every inventory → project hop uses project price. Every project → business inventory hop uses purchase price. In project → project two-hop moves, the source exit uses purchase price and the destination purchase uses project price.
- **Project price is required for destination project sales.** If inventory → project or project → project is initiated for an item without `projectPriceCents`, user-facing flows must ask what to sell it for and persist that value before writing the movement. Non-interactive tools reject instead of falling back to purchase price.
- **Items in business inventory have no budget category.** Invariant: `(item.projectId == null) ↔ (item.budgetCategoryId == null)`. Categories are wiped on return-to-inventory and re-resolved at sell-from-inventory time.
- **Project items must have a transaction.** Invariant: `(item.projectId != null) → (item.transactionId != null)`. Enforced at the iOS and MCP write layers, not in Firestore rules. Legacy orphans (pre-invariant) are repaired manually via the Bulk Reassign UI.
- **One category per inventory-to-project batch.** When moving inventory into a project, the user picks one category that applies to every item in the batch.

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

All sheets use the `SheetStyle` system — never set detents inline. Full spec: `docs/specs/ui/sheet-styles.md`. Implementation: `LedgeriOS/LedgeriOS/Theme/SheetStyle.swift`.

## Problem-Solving Discipline

Think before acting. Consider multiple approaches and propose the most appropriate one — not just the first one that comes to mind.

Do the right thing, not the easy thing. Never rationalize a shortcut as a pragmatic decision. If the correct approach requires more work, that's the work. Before proposing any fix, ask yourself: "is this the best practice, or a workaround?" If you'd change your answer when challenged, change it now.

## Check the Specs First

Before answering questions about how a feature works, or proposing changes to one, read the relevant spec in `docs/specs/`. The specs are the source of truth — not the current UI, not the current code, not your model from prior conversation. Code may have drifted; UI may be wrong; conversation memory is unreliable.

Key specs and what they cover:

- `reassign-vs-sell.md` — Correct/Move vs Sell vs Return semantics, menu visibility rules
- `return-and-sale-tracking.md` — Return flow (vendor and inventory), disposition lifecycle, incomplete-return detection
- `sale-transactions.md` — per-batch inventory movement model, immutability rules
- `inventory-as-store.md` — why inventory → project is a Purchase, and why project → inventory is origin-aware
- `canonical-sales.md` — legacy model, historical reads only
- `data-model.md` — entity relationships, canonical lookup directions
- `lineage-tracking.md` — intent edges vs audit edges

If a question or task touches sales, returns, inventory, item movement, transaction shape, or budget impact, read the relevant spec before responding. "I think it works like…" is not acceptable — look it up.

## Communication

Never use the AskUserQuestion tool. Ask questions as plain text in your response and wait for the user to reply.

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

Full test suite documentation (unit tests, integration tests, emulator setup, helpers): `LedgeriOS/LedgeriOSTests/CLAUDE.md`.

## Verification After Delegation

Sub-agents fabricate plausible details. Their summaries describe what they intended to find or do, not necessarily what is true. Never act on a sub-agent's description of something verifiable — read the source yourself before using it, and read the diff rather than trusting a "done" summary.

## UI Copy

Button labels use title case with lowercase prepositions: `Save to Draft`, `Add New Item`.

## Implementation Documents

Implementation docs are separate from specs and feature docs. They are **delegation documents** — self-contained documents that a managing agent (senior dev / PM) uses to execute a piece of work end-to-end: break it into tasks, spin up junior dev agents, and review their output.

They may reference specs and feature docs as context, but they are not those things.

**Audience model:**
- **The document is for the managing agent.** Structure, scope, and acceptance criteria are written for a senior dev/PM who delegates and reviews. They should be able to scan the doc, understand the full scope, and know what "done" looks like.
- **Task-level detail is for junior agents.** Every task the managing agent would hand off should be described at a level where a junior dev agent can execute without asking clarifying questions — explicit file paths, function signatures, which patterns to follow, where to find examples. No assumed familiarity with the codebase or SwiftUI idioms.

## Feature Documentation

Each feature area gets a doc file at `docs/features/[name].md`. These capture what's specific to that feature — what the root CLAUDE.md doesn't already cover. The template is at `docs/features/_template.md`.

**When to create one:** When a feature spans 3+ files across layers (Views, Services, Logic, State) and has domain-specific patterns worth preserving. Create it during the first implementation session, not retroactively.

**When to update one:** When the feature's shape changes — new state, new sheet flows, new Firestore paths, new architectural decisions. Bug fixes and minor UI tweaks don't require doc updates.

**Updating docs is part of "done."** After completing feature work that changes the feature's shape, update the relevant doc. Specifically:

- New `@Observable` store added → document its purpose, what state it owns, and what creates it
- New sheet flow → document the trigger, dismissal pattern, and any sequencing with other sheets
- New Firestore collection or subcollection read/written → add it to the feature's Data section
- Architectural decision made → record it and the reason, so future work doesn't re-litigate it

## System Design Specs

Platform-agnostic design specs live in `docs/specs/`. These document business rules, entity relationships, data flows, and invariants — not implementation details. They are the source of truth for how the system works, shared across all client platforms.

**When to update a spec:** When a design decision changes — new entity relationships, new business rules, changed data flows, new edge cases. Implementation changes (refactoring, new UI components) don't require spec updates unless the underlying system behavior changes.

**When to create a new spec:** When a new system-level concept is introduced that spans multiple features or affects data model invariants. If it's feature-specific implementation detail, it belongs in `docs/features/` instead.

**Spec vs feature doc:** Specs describe *what the system does* (business rules, data model, invariants). Feature docs describe *how a specific screen/flow is built* (state management, sheet flows, component structure). A feature doc may reference specs but should not duplicate them.

## Shared Components

Reusable components in `Components/` that have a non-obvious usage contract.

| Component | Purpose | Key Props / Notes |
|-----------|---------|-------------------|
| `FormSheet` | Standard bottom sheet wrapper for forms | Handles detents, drag indicator, dismiss |
| `MultiStepFormSheet` | Multi-step form flow in a sheet | Step navigation, back/next/done |
| `ActionMenuSheet` | Action menu presented as bottom sheet | Takes `[ActionMenuItem]` |
| `ListStateControls` | Filter/sort/bulk-select toolbar for lists | Combines FilterMenu, SortMenu, BulkSelectionBar |
| `CardHeader` | Shared card header with badges, selector, bookmark, kebab menu | Owns menu sheet state. Takes `isSelected`, `badges: [CardBadge]`, `menuItems` |
| `CardKebabButton` | Vertical ellipsis menu button | 18pt rotated 90°, `.contentShape(Rectangle())`, a11y label |
| `CardBookmarkButton` | Bookmark toggle button | 18pt, red when filled, a11y label |
| `CardSelectorButton` | Selection circle button | Wraps `SelectorCircle(indicator: .dot)` with Button + a11y |
| `CardBadge` | Badge data type for card headers | `text`, `color`, `backgroundOpacity`, `borderOpacity` |
