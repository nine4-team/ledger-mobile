# Create Items from Images

## Purpose
Lets designers bulk-create items by grouping transaction photos into items — capture images at the store, group them later, fill in details after.

## Files

- `Modals/ImageGroupingState.swift` — `@Observable` state class + `ImageGroup` model. Selection, grouping/ungrouping logic, URL deduplication.
- `Modals/CreateItemsFromImagesModal.swift` — Full sheet UI: grouped item cards, ungrouped image pool, bottom bar with selection/create actions.
- `Components/SelectableImageGrid.swift` — 3-column `LazyVGrid` with multi-select checkmark overlays. Reusable outside this feature.
- `Views/Projects/TransactionDetailView.swift` — Integration: menu item in "Add Items" menu, sheet presentation, `createItemsFromImageGroups()` batch write, and an optimistic local item mirror so created items appear in the open transaction immediately.

## State

`ImageGroupingState` is `@Observable` but **view-local** — created as `@State` inside `CreateItemsFromImagesModal`. Not injected via environment, not persisted. All state is lost on dismiss.

`TransactionDetailView` also keeps `locallyCreatedItems: [Item]` for items created while the detail screen is open. The transaction view overlays those ids onto `currentTransaction.itemIds` until the project item listener receives the real documents, then prunes the local copies. This prevents the items section from showing stale "No items yet" state after the create sheet dismisses.

| Property | Type | Purpose |
|---|---|---|
| `allImages` | `[AttachmentRef]` | Deduplicated union of all transaction image arrays |
| `groups` | `[ImageGroup]` | Created item groupings |
| `selectedUrls` | `Set<String>` | Currently selected images in the ungrouped pool |
| `ungroupedImages` | `[AttachmentRef]` (computed) | `allImages` minus any image in a group |
| `canGroup` | `Bool` (computed) | True when selection is non-empty |
| `canCreate` | `Bool` (computed) | True when at least one group exists |

## Data

**Reads:** `transaction.receiptImages`, `transaction.otherImages`, `transaction.transactionImages` — flattened and deduplicated by URL.

**Writes (atomic `WriteBatch`):**
- Creates item documents at `accounts/{accountId}/items/{auto}` with: `accountId`, `projectId`, `status: "purchased"`, `transactionId`, `budgetCategoryId` (from transaction), `images` (group's images, first set as primary). No `name` — valid per item validation (requires name OR image).
- Updates transaction at `accounts/{accountId}/transactions/{transactionId}` with `itemIds: FieldValue.arrayUnion(newIds)`.

## Sheets & Navigation

**Entry point:** Transaction detail → "Add Items" button → ActionMenuSheet → "Create from Images" (only visible when transaction has images).

**Sheet:** `.sheetStyle(.fullSheet)` wrapping a `NavigationStack`. Cancel button in toolbar. Dismisses on cancel or after item creation.

**No sheet sequencing.** The "Add Items" ActionMenuSheet dismisses first (via `menuPendingAction` pattern), then this sheet opens.

## Gotchas

- **URL deduplication:** Images are deduplicated by `url` string on init. If the same image appears in both `receiptImages` and `otherImages`, it shows once in the pool.
- **No ordering assumptions:** Images are shown in the order they appear in the transaction arrays (receipts → other → transaction). No time-based grouping — designers may upload from camera roll in any order.
- **Items created without names:** Created items have images but no name. This is intentional — designers fill in details later from the item detail view. The item validation rule (name OR image) allows this.
- **First image is primary:** The first image in each group gets `isPrimary = true` automatically. Users can change this later from the item detail view.
- **Ephemeral state:** Dismissing the sheet loses all grouping progress. There's no draft/save concept.
