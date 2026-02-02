# Screen contract: `ItemDetail` (shared module: project + business inventory scopes)

## Intent

Display and manage a single Item: core fields, images (upload/preview/set primary), lineage breadcrumb, and the shared action menu (move/sell/assign to transaction/space/status/delete) with predictable offline behavior.

Shared-module requirement:

- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`

## Inputs

- Route params:
  - `scope`: `'project' | 'inventory'`
  - `projectId` (required when `scope === 'project'`; absent when `scope === 'inventory'`)
  - `itemId`
- Query params:
  - `returnTo` (optional back destination)
  - list params (web parity uses these; mobile uses `ListStateStore[listStateKey]`):
    - `itemSearch`, `itemFilter`, `itemSort`

## Reads (local-first)

- Item by `itemId`
- Project by `projectId` (project scope only; used for title/routing)
- Projects list (for move/sell dialogs)
- Transactions list (for “assign to transaction” dialog)
- Spaces list (for set-space dialog)
- Optional: lineage edges / derived lineage breadcrumb state

Parity evidence (web):

- Item detail + dialogs + next/prev nav: `ledger/src/pages/ItemDetail.tsx`
- Item actions menu surface + disable reasons: `ledger/src/components/items/ItemActionsMenu.tsx`
- Lineage breadcrumb: `ledger/src/components/ui/ItemLineageBreadcrumb.tsx`

## Writes (local-first)

- Update item fields: `unifiedItemsService.updateItem(...)`
- Transaction association:
  - assign: `unifiedItemsService.assignItemToTransaction(...)`
  - remove: `unifiedItemsService.unlinkItemFromTransaction(...)`
- Space association: update item `spaceId`
- Images:
  - upload image → append to `item.images[]` (may create `offline://` placeholders)
  - remove image → remove from `item.images[]`; if `offline://`, delete local blob immediately
  - set primary image → set `isPrimary` in `item.images[]`
  - Attachment contract (required; GAP B):
    - Persisted images are `AttachmentRef[]` on `item.images[]` (see `20_data/data_contracts.md`), with `kind: "image"`.
    - Upload state (`local_only | uploading | failed | uploaded`) is derived locally (see `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`), not stored on the Firestore item doc.
- Cross-scope operations:
  - sell to business inventory (deallocation): `integrationService.handleItemDeallocation(...)`
  - move to business inventory (correction): `integrationService.moveItemToBusinessInventory(...)`
  - sell to project: `integrationService.sellItemToProject(...)`
  - move to project (simple association change, only when not tied to transaction): update item `projectId`
- Delete item: `unifiedItemsService.deleteItem(...)`

Offline media lifecycle (mobile target):

- `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
- `40_features/_cross_cutting/ui/shared_ui_contracts.md` → “Media UI surfaces”

## UI structure (high level)

- Header row:
  - Back
  - Optional refresh
  - Optional next/previous navigation (project scope; preserves list params)
- Core item fields:
  - description, sku, source, purchased by, prices, notes, status/disposition, space
  - transaction association summary (if present) with link to transaction detail
- Lineage breadcrumb (when available)
- Images section:
  - add images (gallery/camera)
  - preview grid with remove and “set primary”
  - max 5 images
- Actions menu (“…”):
  - edit, duplicate, add/remove transaction, set space, sell/move, change status, delete

## User actions → behavior (the contract)

### 1) Next/previous navigation (project scope; parity)

- ItemDetail must preserve the list’s search/filter/sort parameters and compute next/previous within the same filtered+sorted list.
- “Next/Prev” navigation must use `replace: true` so Back returns to the list, not through a chain of items.

Parity evidence:

- `ledger/src/pages/ItemDetail.tsx` (parses `itemFilter/itemSort/itemSearch`, computes `filteredAndSortedItems`, uses `replace: true`).

### 2) Transaction assignment dialog (parity)

- “Assign to / Change transaction” opens a picker for transactions in the current scope.
- Selecting a transaction assigns the item to that transaction and refreshes the item.
- “Remove from transaction” requires explicit confirmation and does not delete the item.

Parity evidence:

- Assign: `ledger/src/pages/ItemDetail.tsx` (`assignItemToTransaction`)
- Remove: `ledger/src/pages/ItemDetail.tsx` (`unlinkItemFromTransaction`)

### 3) Space selection dialog (parity)

- “Set space” opens a space picker and persists `spaceId` on save.

Parity evidence:

- `ledger/src/pages/ItemDetail.tsx` (`showSpaceDialog`, `SpaceSelector`, update item `spaceId`)

### 4) Images (parity + offline)

- Add images from gallery/camera (multi-select supported).
- Each upload may create an `offline://<mediaId>` placeholder until remote URL is available.
- Removing an `offline://` image deletes the local blob immediately.
- Max images per item: 5.

Parity evidence:

- Upload: `ledger/src/pages/ItemDetail.tsx` (`OfflineAwareImageService.uploadItemImage`, `offline://` metadata)
- Remove: `ledger/src/pages/ItemDetail.tsx` (deletes via `offlineMediaService.deleteMediaFile`)

---

## Canonical attribution + `inheritedBudgetCategoryId` (Firebase migration deltas; required)

### Display of `inheritedBudgetCategoryId`

Default: keep implicit (recommended):

- In v1 mobile, `inheritedBudgetCategoryId` is an internal determinism field and does not need to be shown as a first-class UI field on Item Detail.
- If missing, the UI must surface actionable guidance via disabled actions + messaging below.

### Project → Business Inventory guardrail (missing `inheritedBudgetCategoryId`)

If `item.inheritedBudgetCategoryId` is missing, disable:

- **Sell → Sell to Design Business**

Required disable reason:

`Link this item to a categorized transaction before moving it to Design Business Inventory.`

Attempted operation (race / stale UI):

`Can’t move to Design Business Inventory yet. Link this item to a categorized transaction first.`

Inline messaging (recommended):

- **Title**: `Action required`
- **Body**: `To move this item to Design Business Inventory, first link it to a categorized transaction so the budget category is known.`

Notes:

- This is an intentional Firebase-migration delta; web doesn’t have the field yet.
- “Move to Design Business” (correction path) may remain enabled because it does not create canonical inventory transactions in current web behavior.

### Transaction linking rule (required)

- Linking an item to a **non-canonical** transaction with a category sets:
  - `item.inheritedBudgetCategoryId = transaction.budgetCategoryId`
- Linking/unlinking to a **canonical inventory** transaction (`INV_*`) must not overwrite it.

### Canonical attribution note (required)

Item Detail does not display canonical transaction category attribution. Budgeting attribution for canonical inventory rows is computed by grouping linked items by `inheritedBudgetCategoryId`.


