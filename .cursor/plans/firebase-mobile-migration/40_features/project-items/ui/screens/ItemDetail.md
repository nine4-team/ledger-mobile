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

## Canonical attribution + `budgetCategoryId` (Firebase migration deltas; required)

### Display of `budgetCategoryId`

Default: keep implicit (recommended):

- In v1 mobile, `budgetCategoryId` is an internal determinism field and does not need to be shown as a first-class UI field on Item Detail.
- If missing or invalid for a destination project, the UI resolves it via **prompt + persist** during Sell flows (below).

### Sell menu structure (required)

Item actions include a single **Sell** entrypoint whose submenu options depend on scope:

- **Project scope**:
  - `Sell → Sell to Business`
  - `Sell → Sell to Project`
- **Business Inventory scope**:
  - `Sell → Sell to Project`

### Project → Business (Sell to Business) — category prompt (required)

If `item.budgetCategoryId` is missing when the user initiates `Sell → Sell to Business`:
- Prompt the user to choose a budget category from the **source project’s enabled categories**.
- Persist the selection to `item.budgetCategoryId`.
- Then proceed with the canonical sale (`project_to_business`) request-doc workflow.

Inline messaging (recommended when prompting is needed):
- **Title**: `Choose a budget category`
- **Body**: `This sale is tracked by budget category. Pick a category to continue.`

### Business → Project (Sell to Project) — conditional category prompt (required)

When the user initiates `Sell → Sell to Project`, resolve a destination project category:
- If `item.budgetCategoryId` is enabled/available in the destination project, use it (no prompt).
- Otherwise prompt the user to choose a category from the destination project, persist it to `item.budgetCategoryId`, then proceed with the canonical sale (`business_to_project`) request-doc workflow.

Batch behavior (when invoked from list/bulk flows):
- One category selection applies to all items in the batch (fast path).

Notes:
- “Move to Design Business” (correction path) remains separate because it does not create canonical inventory sale transactions.
  It is still blocked when the item is transaction-attached (same parity behavior).

### Transaction linking rule (required)

- Linking an item to a **non-canonical** transaction with a category sets:
  - `item.budgetCategoryId = transaction.budgetCategoryId`
- When a sell/allocation prompt resolves a category, the chosen value is also persisted to `item.budgetCategoryId` (direct assignment).

### Canonical attribution note (required)

Item Detail does not attempt to “attribute” canonical rows.
Budgeting attribution for canonical inventory sale rows is transaction-driven (category-coded) and budget rollups apply sign based on direction.


