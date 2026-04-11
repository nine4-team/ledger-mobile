# Copy Entity ID

Status: **new** · Shipped: 2026-04-11

## Purpose

Give the user a one-or-two-tap way to copy the opaque Firestore document ID of an item or transaction. This is a power-user affordance for debugging, MCP cross-referencing, and support — not an everyday action.

## Scope

- **Items** (both project items and business-inventory items).
- **Transactions** (per-batch sales and regular transactions; suppressed on legacy canonical inventory sales that have no card menu at all).
- **Out of scope for this spec:** projects, spaces, budget categories. They can follow the same pattern later if a need emerges.

## Affordance

### Single entity

A `Copy ID` entry in the existing single-entity kebab action menu:

| Context | Where it appears |
|---|---|
| Item list card (Projects tab, Inventory tab, Search results, Space detail, Transaction detail) | Kebab menu, above Delete |
| Item detail | Toolbar kebab menu, above Delete |
| Transaction list card (Projects, Inventory, Search) | Kebab menu, above Delete |
| Transaction detail | Toolbar kebab menu, above Delete |

### Bulk selection

A `Copy IDs` entry (plural) in the bulk-selection action menu:

| Context | Where it appears |
|---|---|
| Bulk-selected items (Projects tab, Inventory tab, Search results) | Bulk menu, above Delete |
| Bulk-selected transactions (Projects tab, Inventory tab, Search results) | Bulk menu, above Delete |

**Icon:** `doc.on.clipboard` (the `doc.on.doc` symbol is already used for "Make Copies" on items, so we picked a distinct clipboard-flavored variant). Same icon for single and bulk — the label disambiguates.

**Label:** `Copy ID` for single, `Copy IDs` for bulk (title case, no trailing punctuation).

**Placement:** always the last non-destructive entry in the menu, sitting just above `Delete` / `Delete Transaction` / `Delete Transactions`. Keeps destructive actions anchored at the bottom and keeps Copy ID(s) discoverable without crowding the primary actions at the top.

## Behavior

- **Single:** copies the raw Firestore document ID to the platform clipboard, unchanged — no prefix, no formatting, no surrounding JSON.
- **Bulk:** copies the selected IDs as a newline-separated list, **sorted lexicographically** so the same selection always yields the same paste (deterministic output, easier to diff). No header, no trailing newline. Implemented via `Clipboard.copyLines(_:)`.
- Both paths use the shared `Clipboard` helper at `LedgeriOS/LedgeriOS/Platform/Clipboard.swift`, so iOS and macOS behave identically (UIKit `UIPasteboard` / AppKit `NSPasteboard`).
- **Single-entity fallback:** if an entity has no ID (e.g. a freshly-constructed local model whose `@DocumentID` has not yet been assigned), the menu entry is suppressed rather than shown-and-broken. Callers wire `onCopyID` via `id.map { id in { Clipboard.copy(id) } }`, so a nil `id` hides the action.
- **Bulk fallback:** bulk callers pass the current selection set directly. An empty selection is effectively unreachable because bulk menus only appear when at least one row is selected.

## Feedback

For now, rely on the action-menu-sheet's normal dismiss animation as the acknowledgement. No toast, no icon flip, no haptic.

**Parking lot:** once a shared toast/snackbar system exists (none today), revisit this and add a `ID copied` confirmation. Tracked here rather than in a separate ticket so it doesn't get lost.

## Non-goals

- **Not** displaying the ID inline in the detail view. The ID is opaque and noisy — showing it on-screen would clutter the hero without helping non-debug users.
- **Not** copying composed URLs (Firestore console links, `ledger://item/...` deep links, etc.). Those can land later if we decide we want them, but they need their own decisions about format.
- **Not** a generic `Copy Field` menu that copies names, amounts, etc. Out of scope here.

## Implementation

- Clipboard helper: [`LedgeriOS/LedgeriOS/Platform/Clipboard.swift`](../../LedgeriOS/LedgeriOS/Platform/Clipboard.swift) — exposes `copy(_:)` and `copyLines(_:)`.
- Item menu: `onCopyID` on `SingleItemMenuCallbacks`, `onCopyIDs` on `BulkItemMenuCallbacks` in [`LedgeriOS/LedgeriOS/Logic/ItemMenuBuilder.swift`](../../LedgeriOS/LedgeriOS/Logic/ItemMenuBuilder.swift)
- Transaction menu: `onCopyID` on `SingleTransactionMenuCallbacks`, `onCopyIDs` on `BulkTransactionMenuCallbacks` in [`LedgeriOS/LedgeriOS/Logic/TransactionMenuBuilder.swift`](../../LedgeriOS/LedgeriOS/Logic/TransactionMenuBuilder.swift)
- Item detail wiring: [`LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift`](../../LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift)
- Item list wiring: [`LedgeriOS/LedgeriOS/Logic/ItemActionsController.swift`](../../LedgeriOS/LedgeriOS/Logic/ItemActionsController.swift)
- Item bulk wiring: `ItemsTabView`, `InventoryItemsSubTab`, `UniversalSearchView`
- Transaction detail wiring: [`LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift`](../../LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift)
- Transaction list wiring: `TransactionsTabView`, `InventoryTransactionsSubTab`, `UniversalSearchView`
- Transaction bulk wiring: `TransactionsTabView`, `InventoryTransactionsSubTab`, `UniversalSearchView`

All menu-builder callbacks are optional; any new caller that doesn't wire `onCopyID` / `onCopyIDs` simply won't show the action.
