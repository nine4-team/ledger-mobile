# Copy Entity ID

Status: **new** · Shipped: 2026-04-11

## Purpose

Give the user a one-or-two-tap way to copy the opaque Firestore document ID of an item or transaction. This is a power-user affordance for debugging, MCP cross-referencing, and support — not an everyday action.

## Scope

- **Items** (both project items and business-inventory items).
- **Transactions** (per-batch sales and regular transactions; suppressed on legacy canonical inventory sales that have no card menu at all).
- **Out of scope for this spec:** projects, spaces, budget categories. They can follow the same pattern later if a need emerges.

## Affordance

A `Copy ID` entry in the existing kebab action menu:

| Context | Where it appears |
|---|---|
| Item list card (Projects tab, Inventory tab, Search results, Space detail, Transaction detail) | Kebab menu, above Delete |
| Item detail | Toolbar kebab menu, above Delete |
| Transaction list card (Projects, Inventory, Search) | Kebab menu, above Delete |
| Transaction detail | Toolbar kebab menu, above Delete |

**Icon:** `doc.on.clipboard` (the `doc.on.doc` symbol is already used for "Make Copies" on items, so we picked a distinct clipboard-flavored variant).

**Label:** `Copy ID` (title case, no trailing punctuation).

**Placement:** always the last non-destructive entry in the menu, sitting just above `Delete` / `Delete Transaction`. Keeps destructive actions anchored at the bottom and keeps `Copy ID` discoverable without crowding the primary actions at the top.

## Behavior

- Copies the raw Firestore document ID to the platform clipboard, unchanged — no prefix, no formatting, no surrounding JSON.
- Uses the shared `Clipboard.copy(_:)` helper at `LedgeriOS/LedgeriOS/Platform/Clipboard.swift`, so iOS and macOS behave identically (UIKit `UIPasteboard` / AppKit `NSPasteboard`).
- If an entity has no ID (e.g. a freshly-constructed local model whose `@DocumentID` has not yet been assigned), the menu entry is suppressed rather than shown-and-broken. Callers wire `onCopyID` via `id.map { id in { Clipboard.copy(id) } }`, so a nil `id` hides the action.

## Feedback

For now, rely on the action-menu-sheet's normal dismiss animation as the acknowledgement. No toast, no icon flip, no haptic.

**Parking lot:** once a shared toast/snackbar system exists (none today), revisit this and add a `ID copied` confirmation. Tracked here rather than in a separate ticket so it doesn't get lost.

## Non-goals

- **Not** displaying the ID inline in the detail view. The ID is opaque and noisy — showing it on-screen would clutter the hero without helping non-debug users.
- **Not** copying composed URLs (Firestore console links, `ledger://item/...` deep links, etc.). Those can land later if we decide we want them, but they need their own decisions about format.
- **Not** a generic `Copy Field` menu that copies names, amounts, etc. Out of scope here.

## Implementation

- Clipboard helper: [`LedgeriOS/LedgeriOS/Platform/Clipboard.swift`](../../LedgeriOS/LedgeriOS/Platform/Clipboard.swift)
- Item menu: `onCopyID` on `SingleItemMenuCallbacks` in [`LedgeriOS/LedgeriOS/Logic/ItemMenuBuilder.swift`](../../LedgeriOS/LedgeriOS/Logic/ItemMenuBuilder.swift)
- Transaction menu: `onCopyID` on `SingleTransactionMenuCallbacks` in [`LedgeriOS/LedgeriOS/Logic/TransactionMenuBuilder.swift`](../../LedgeriOS/LedgeriOS/Logic/TransactionMenuBuilder.swift)
- Item detail wiring: [`LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift`](../../LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift)
- Item list wiring: [`LedgeriOS/LedgeriOS/Logic/ItemActionsController.swift`](../../LedgeriOS/LedgeriOS/Logic/ItemActionsController.swift)
- Transaction detail wiring: [`LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift`](../../LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift)
- Transaction list wiring: `TransactionsTabView`, `InventoryTransactionsSubTab`, `UniversalSearchView`

All menu-builder callbacks are optional; any new caller that doesn't wire `onCopyID` simply won't show the action.
