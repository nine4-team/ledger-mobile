# Items

## Overview

Items are the individual physical products tracked in Ledger. Each item represents a real-world object (a piece of furniture, a decor piece, a rug, etc.) that belongs to either a project or business inventory. Items are linked to transactions, assigned to spaces, and carry pricing, status, and media data.

Items are a shared domain module — the same `Item` entity and UI components are used across both project and business inventory scopes.

## Proto Items Are Separate

Photo-first captures that are not ready to become real items are stored as `ProtoItem` records, not incomplete `Item` records. See [proto-item-capture.md](proto-item-capture.md).

This keeps the `Item` entity reserved for physical products that are ready to participate in item lists, inventory operations, transaction membership, reporting, billing, and project budget behavior. A proto item can later create a new item or merge photos into an existing item, but unresolved proto items do not appear in normal item lists and do not affect item counts.

## Item Entity

**Firestore path:** `accounts/{accountId}/items/{itemId}`

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | auto | Document ID |
| `accountId` | string | yes | Owning account |
| `projectId` | string | no | Project this item belongs to. Null = business inventory. |
| `spaceId` | string | no | Space assignment within project or inventory |
| `name` | string | no | Item name (display name prefers `name`, falls back to `description`) |
| `description` | string | no | Item description (legacy field, used as fallback display name) |
| `notes` | string | no | Free text notes |
| `status` | string | no | Item lifecycle status (see Status section) |
| `source` | string | no | Vendor/source where item was acquired |
| `sku` | string | no | Barcode or SKU number |
| `transactionId` | string | no | Linked transaction ID |
| `purchasePriceCents` | int | no | What was paid for the item (in cents) |
| `projectPriceCents` | int | no | Price charged to the project/client (in cents) |
| `marketValueCents` | int | no | Estimated market/retail value (in cents) |
| `purchasedBy` | string | no | Who purchased the item |
| `bookmark` | bool | no | Whether the item is bookmarked |
| `budgetCategoryId` | string | no | Budget category attribution for this item |
| `quantity` | int | no | Quantity (only set when > 1; nil means 1) |
| `images` | array | no | Array of `AttachmentRef` objects |
| `createdBy` | string | no | User who created the item |
| `updatedBy` | string | no | User who last updated the item |
| `createdAt` | timestamp | auto | Server timestamp |
| `updatedAt` | timestamp | auto | Server timestamp |

### Price Invariant

Every persisted `Item` uses one canonical price floor:

```text
projectPriceCents = max(projectPriceCents ?? 0, purchasePriceCents ?? 0)
```

This invariant applies to project items and business-inventory items alike, on every create and update path—not only when an item is first created or sold. Consequently:

- a missing or zero project price is initialized from a positive purchase price;
- increasing the purchase price above the project price raises the project price to match;
- decreasing the purchase price does not reduce an already higher project price;
- an attempted project price below the purchase price is normalized up to the purchase price; and
- a project price above the purchase price is preserved as the client-facing markup.

The iOS and MCP item write boundaries must apply the same shared normalization before persisting a write. A server-side write guard is the final safety net for writers that bypass those boundaries. Import, bulk-create, copy, quick-draft promotion, and inventory-movement paths are not exceptions.

For a partial update, normalization is computed from the merged post-update state. A write that changes only `purchasePriceCents` must compare it with the stored project price; a write that changes only `projectPriceCents` must compare it with the stored purchase price. Callers may omit an unchanged field, but they may not bypass the invariant by doing so.

Readers should defensively use the same `max` rule while legacy documents are being repaired, so a stale zero or lower project price can never hide a positive purchase price. This rule governs current item state. For a sold item that remains attached to an unpaid project-side Purchase-from-Inventory, changing the effective project price automatically adjusts that transaction's subtotal and amount. Original vendor purchases, departed movement history, and paid invoice snapshots do not change.

### Display Name

The canonical display name is `name ?? description ?? ""`. The `description` field is a legacy fallback — new items always use `name`.

## Scoping

Items live in a single flat collection (`accounts/{accountId}/items`). Scope is determined by the `projectId` field:

- **Project item:** `projectId` is set → belongs to that project
- **Inventory item:** `projectId` is null → belongs to business inventory

Project items attached to a transaction use the same `budgetCategoryId` as that transaction. For an eligible uncollected Purchase from Business Inventory, changing the Purchase category is a whole-transaction correction: the trusted operation atomically updates every currently attached item to the selected active, non-system, project-enabled itemized category. Direct transaction-only or item-only category writes must not create a mismatch. Departed items retain their current scope/category.

The `ListScope` enum controls query filtering:

| Scope | Query |
|-------|-------|
| `.project(projectId)` | `where projectId == projectId` |
| `.inventory` | `where projectId == null` |
| `.all` | No filter (all items in account) |

## Statuses

| Status Key | Display Label |
|-----------|--------------|
| `to-purchase` | To Purchase |
| `purchased` | Purchased |
| `to return` | To Return |
| `returned` | Returned |

All statuses allow the full action menu. No status is terminal — users must be able to correct mistakes.

Default status for new items: `purchased`.

## Validation

An item requires **either** a non-empty name **or** at least one image to be created. Both can be empty in combination — this is the only hard validation rule.

Price fields must be zero or greater (negative values are invalid), and `projectPriceCents` must never be less than `purchasePriceCents` after normalization.

## Creation Flow

Item creation uses a 2-step sheet form.

This flow remains the full-detail item creation path. For field capture where the designer only has photos and lightweight context, use proto item capture first and resolve later.

### Step 1: Essentials

- Images (optional — camera or photo library via image source menu)
- Name (optional if images provided)
- SKU (optional)
- Source/Vendor (via vendor picker)
- Notes (optional)

### Step 2: Details

- Transaction picker (project scope only — links item to an existing transaction)
- Space picker (project scope only)
- Purchase price (currency input)
- Project price (currency input)
- Market value (currency input)
- Quantity (stepper, 1–9999, default 1)
- Status (picker, default "purchased")

### Creation Context

The creation form accepts a context that determines behavior:

| Context | `projectId` | Transaction/Space Pickers |
|---------|-------------|---------------------------|
| `.project(id, spaceId:)` | Set to project ID | Shown (space pre-selected if provided) |
| `.inventory` | Null | Hidden |

### On Create

1. Item document created (fire-and-forget) — sheet dismissed immediately (optimistic UI)
2. Background: images uploaded to Firebase Storage, then `images` array updated on the item document
3. First image is automatically set as primary (`isPrimary: true`)

Quantity > 1 creates a **single item document** with the `quantity` field set — it does not create multiple documents.

## Editing

Editing is split across multiple modals, each accessible from the item's action menu:

### Edit Details Modal

Editable fields: name, source (vendor picker), SKU, purchase price, project price, market value. Presented as a single-step form sheet.

### Other Edit Actions (via action menu)

| Action | Modal |
|--------|-------|
| Edit Notes | `EditNotesModal` |
| Change Status | `StatusPickerModal` |
| Set/Clear Transaction | `TransactionPickerModal` |
| Set/Clear Space | `SetSpaceModal` |

## Item Detail View

### Layout

- **Hero card:** Display name, budget category label, linked transaction (navigable link), linked space (navigable link)
- **Collapsible sections** (in a card):
  - **Media** (expanded by default) — image gallery with upload, remove, set primary
  - **Notes** (collapsed by default) — free text with edit button
  - **Details** (collapsed by default) — status, space, source, SKU, purchase price, project price, market value, created date

### Toolbar

- Status pill button (tappable → opens status picker)
- Bookmark toggle
- Kebab menu (ellipsis → opens action menu sheet)

### Live Data

The detail view subscribes to the individual item document via `subscribeToItem` for real-time updates. This is separate from the project context's item list subscription.

## Action Menu

Actions are built by `ItemMenuBuilder`, which adapts the menu based on **context** (where the menu appears) and **scope** (project vs inventory).

### Menu Contexts

| Context | Available In | Notes |
|---------|-------------|-------|
| `.list` | Item card in list view | Includes Open, Select |
| `.detail` | Item detail toolbar | Includes Make Copies |
| `.space` | Item within space detail | Includes Open |
| `.transaction` | Item within transaction detail | Includes Open Item, Make Copies; transaction actions are clear/move only |

### Single-Item Actions

| Action | Project Scope | Inventory Scope | Notes |
|--------|--------------|-----------------|-------|
| Status submenu | yes | yes | All 4 statuses; clear status available in detail/transaction context |
| Set Transaction | yes | yes | Opens transaction picker |
| Clear Transaction | yes | yes | Only shown if item has a transaction |
| Move to Return Transaction | yes | yes | Only shown for return statuses |
| Set Space | yes | yes | |
| Clear Space | yes | yes | Only shown if item has a space |
| Sell | yes | yes | Opens destination choice; project-originated project items can sell to business inventory, all eligible items can sell into a project |
| Reassign to Inventory | yes | no | Moves item from project to business inventory without sale |
| Reassign to Project | yes | yes | Moves item to a different project |
| Make Copies | yes | yes | Creates duplicate item(s) — detail and transaction context only |
| Delete | yes | yes | Confirmation dialog, then deletes |

### Bulk Actions

When items are selected via checkboxes, a `BulkSelectionBar` appears at the bottom showing count, total price of selected items, and a "Bulk Actions" button. Bulk actions mirror single-item actions: status change, set/clear transaction, set/clear space, sell, reassign, delete. Selection is cleared after any bulk action completes.

## Item List

Items are displayed using the shared `SharedItemsList` component, which operates in three modes:

| Mode | Usage |
|------|-------|
| `.standalone(scope:)` | Manages its own Firestore subscription |
| `.embedded(items:, onItemPress:)` | Receives items from parent (project/inventory context) |
| `.picker(scope:, ...)` | Selection-only mode for picking items |

### List Controls

- **Search:** Client-side text filtering across item fields
- **Sort:** Created date (desc/asc), alphabetical (asc/desc). Default: created descending
- **Filter:** Multi-select filter options (see below)
- **Select all:** Toggle to select/deselect all visible items

### Filter Facets

Item filters use grouped multi-select facets. Values within one facet use OR logic;
active facets combine with AND logic. Every facet supports both **All except**
(start with All and deselect values) and **Only** (start with None and select values).

| Facet | Values | Scope Notes |
|-------|--------|-------------|
| Status | To Purchase, Purchased, To Return, Returned, Sold, Not Set | All item lists |
| Space | No Space plus the current scope's named spaces | Hidden in Space Detail; referenced archived spaces remain available |
| Source | No Source plus sources derived from current items | Uses `currentSource ?? source`, matching item-card display and inventory masking |
| Budget Category | Uncategorized plus available categories | Hidden in inventory, where items cannot have a category |
| Purchased By | Client, Design Business, Not Set, plus encountered legacy values | All item lists |
| Transaction | Has Transaction, No Transaction | All item lists |
| Bookmark | Bookmarked, Not Bookmarked | All item lists |
| Image | Has Image, No Image | All item lists |
| SKU | Has SKU, No SKU | All item lists |
| Name | Has Name, No Name | All item lists |
| Project Price | Has Project Price, No Project Price | A meaningful price is a positive normalized project price |

Examples: deselecting Purchased from Status shows every other status; deselecting
the account's inventory label from Source shows direct-source and no-source items.
When filters change, bulk selection is intersected with the visible results so a
bulk action cannot affect hidden items. Quick drafts rendered inside the shared item
list (currently inventory) are hidden while persisted-item filters are active because
draft statuses and fields use a different schema. Project quick drafts remain in their
separate section and are not governed by the Items-section filter.

### Duplicate Grouping

Items with matching names are automatically grouped into `GroupedItemCard` which shows:

- Group name and count (e.g., "×4")
- Summary thumbnail (first item with an image)
- Total price across group
- SKU and source from representative item
- Expandable: reveals individual `ItemCard` entries with index labels ("1/4", "2/4", etc.)
- Group-level selection: selects/deselects all items in the group

Grouping is only shown when at least one group has more than one item.

## Item Card

Each card displays:

- **Header:** Selection circle, badges (status, budget category, index label), bookmark toggle, kebab menu
- **Content:** Display name, thumbnail image (108×108, or placeholder), price, source, SKU
- **Optional:** Warning message (e.g., "Price exceeds budget allocation")

### Price Display Priority

Item cards display the normalized project price. During the legacy-data transition, readers compute `max(projectPriceCents ?? 0, purchasePriceCents ?? 0)` defensively rather than allowing a stale zero or lower project price to win.

## Image Management

### On Detail View

- **Upload:** Camera capture or photo library picker. Placeholder-first pattern — a Firestore record with empty URL is written before upload begins, then updated with the real URL on completion.
- **Remove:** Deletes from Firestore array, then background-deletes from Firebase Storage.
- **Set Primary:** Updates `isPrimary` flag across the images array.

### On Creation

Images selected during creation are uploaded in background after the item document is created. First image is set as primary.

## Bulk Creation from Receipt Text

`CreateItemsFromListModal` provides a 2-step flow for creating multiple items from pasted receipt text:

1. **Paste:** User pastes receipt text (e.g., HomeGoods format)
2. **Preview:** Parser extracts item name, SKU, and price per line. Shows parsed items and skipped/unparseable lines.
3. **Create All:** Creates all parsed items linked to the specified transaction.

## Cross-Scope Operations

Items can move between scopes via sell and reassign operations (see separate specs for sell and reassign features). These operations update the item's `projectId` and may create lineage edges and canonical transactions.

## Edge Cases

1. **Item with no name and no image** — cannot be created (validation prevents it)
2. **Item with quantity > 1** — single document with quantity field, not multiple documents
3. **Orphaned items** — items whose `projectId` references a deleted project remain in Firestore but don't appear in any project view
4. **Image upload failure** — item is created without images; placeholder record may remain with empty URL and `isUploading: true`
5. **Returned status** — no special restrictions; all actions remain available so mistakes can be corrected
6. **Grouped items with mixed prices** — group card shows total; individual cards show per-item price
7. **Item in transaction context** — kebab menu adapts: no "Set Transaction" (already linked), offers "Clear Transaction" and "Move to Return Transaction" instead
8. **Selection mode vs navigation** — when items are selected, tapping a card toggles selection instead of navigating to detail
