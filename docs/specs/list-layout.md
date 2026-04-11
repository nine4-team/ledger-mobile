# List Layout (Desktop)
Status: shipped (core shipped 2026-04-03; list/grid toggle deferred)
Last updated: 2026-04-10

> **Core shipped 2026-04-03** (commit 2358be7b) — macOS item and transaction lists default to single-column stacked rows via `Dimensions.listColumns` with `#if os(macOS)` branching (Theme/Dimensions.swift lines 39-45). Applied through `LazyVGrid(columns: Dimensions.listColumns)` in SharedItemsList.swift, SharedTransactionsList.swift, and TransactionsTabView.swift. iOS keeps its adaptive grid unchanged.
>
> The nice-to-have list/grid view toggle was not implemented and is deferred — the grid layout is not currently accessible via any toggle.

## Summary
Anywhere items or transactions are displayed in the desktop app, the default layout should use a single-column stacked list (one item per row) instead of the current tile/grid layout (multiple items per row). This brings the desktop app in line with how the web app already displays these lists.

## Scope
- **Desktop app only.** The mobile app already looks good and isn't changing.
- **Web app already correct.** The web app uses the desired single-column layout — no changes needed there.
- Applies to every screen in the desktop app where items or transactions are displayed in a list. Specific screens affected: [needs discovery — exact list of screens TBD once codebase or full app map is available]

## How It Works
When the user views a list of items or transactions — whether inside a project, a space, or any top-level view — each entry appears as a full-width horizontal row. One item per row, stacked vertically. This is how the web app currently presents these lists, and it becomes the default view in the desktop app.

The user can scan the list top-to-bottom, comparing entries sequentially. This makes it easier to track individual items and do before/after comparisons without needing to mentally map both row and column positions (as required by the tile/grid layout).

## What's Changing

### Staying the Same
- The data shown for each item/transaction (the content of each entry is not changing, just the container layout)
- The web app's list layout (already uses the desired single-column format)
- The mobile app (no changes)

### Changing
- **Desktop item lists**: tile/grid layout (multiple items per row in blocks) → single-column stacked list (one full-width item per row) as the default view
- **Desktop transaction lists**: tile/grid layout (multiple items per row in blocks) → single-column stacked list (one full-width item per row) as the default view

### Adding
- Nothing new required for the core change

### Removing
- Nothing removed — the grid layout would still be accessible via the toggle (see Nice to Have below)

## Nice to Have: List/Grid View Toggle
**Priority: Nice to have — not a must have.**

A small toggle control that lets the user switch between list view (single-column, one per row) and grid view (tiles, multiple per row). Inspired by Apple Finder's view switcher and similar patterns in macOS apps.

- **Default view**: List (single-column stacked rows)
- **Alternate view**: Grid/tiles (the current layout)
- **Behavior**: The user taps the toggle to switch. This is a personal preference setting — it should persist across sessions so the user doesn't have to switch every time.
- **Placement**: [needs discovery — likely in a toolbar or header area near the list, similar to Finder's icon/list/column/gallery buttons]

This makes it a user preference rather than a hard removal of the grid layout. If implementation effort is low, include it. If it adds significant complexity, skip it and just default to list view only.

## Open Questions
- What specific information is displayed per row in the web app's list layout? (fields, ordering, thumbnail presence, etc.) [needs discovery]
- Where exactly would the view toggle live in the UI? [needs discovery — only relevant if the toggle is implemented]
