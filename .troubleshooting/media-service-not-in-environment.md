# Issue: MediaService missing from environment — crash on add button

**Status:** Resolved
**Opened:** 2026-03-03
**Resolved:** 2026-03-03

## Info
- **Symptom:** Tapping the "+" (add) button on the Projects tab crashes with: `Thread 1: Fatal error: No Observable object of type MediaService found. A View.environmentObject(_:) for MediaService may be missing as an ancestor of this view.`
- **Affected area:** `LedgerApp.swift`, `NewProjectView.swift`, `NewItemView.swift`, `SpaceDetailView.swift`

`MediaService` (`Services/MediaService.swift`) is an `@Observable` `@MainActor` class. Three views declare `@Environment(MediaService.self) private var mediaService`:
- `NewProjectView` (line 8) — presented from ProjectsListView "+" button
- `NewItemView` (line 16) — presented from ItemsTabView and InventoryPlaceholderView
- `SpaceDetailView` (line 8) — navigated to from project detail

`LedgerApp.swift` injects `authManager`, `accountContext`, `projectContext`, `inventoryContext` — but **not** `mediaService`. No other view injects it either.

The crash chain: LedgerApp → RootView → MainTabView → ProjectsListView → "+" button → `.sheet` presents `NewProjectView` → `@Environment(MediaService.self)` lookup fails → fatal error.

## Experiments

### H1: MediaService is never injected into the SwiftUI environment
- **Rationale:** Error message says no `MediaService` found in environment. Grep confirms no `.environment(mediaService)` call anywhere.
- **Experiment:** Search entire codebase for `.environment(` injection of MediaService.
- **Result:** Zero matches. `LedgerApp.swift` lines 73-76 inject 4 other objects, MediaService is absent.
- **Verdict:** Confirmed

## Resolution

- **Root cause:** `MediaService` was consumed by 3 views via `@Environment(MediaService.self)` but was never injected into the SwiftUI environment hierarchy.
- **Fix:** Added `@State private var mediaService = MediaService()` to `LedgerApp` and `.environment(mediaService)` to the root view chain.
- **Files changed:** `LedgeriOS/LedgeriOS/LedgerApp.swift`
- **Lessons:** When adding a new `@Observable` service that views consume via `@Environment`, always wire it up in `LedgerApp.swift` alongside the other context objects. The crash only surfaces at runtime when the consuming view is first presented.
