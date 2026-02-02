# Screen contract: `ItemForm` (shared module: create + edit; project + inventory scopes)

## Intent

Provide a single shared Item create/edit form used in:

- project scope (project items)
- inventory scope (business inventory items)

This screen must support offline-friendly image attachments and predictable validation.

Shared-module requirement:

- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`

## Inputs

- Route params:
  - `scope`: `'project' | 'inventory'`
  - `projectId` (required when `scope === 'project'`; absent when `scope === 'inventory'`)
  - `mode`: `'create' | 'edit'`
  - `itemId` (required when `mode === 'edit'`)
- Query params:
  - `returnTo` (optional back destination)

## Reads (local-first)

- Budget/vendor defaults (for “Source” options)
- Projects list (edit-only: optional “associate with project” correction path)
- Transactions list (optional “associate with transaction”)
- Spaces list (space selector)
- Existing item (edit-only)

Parity evidence (web):

- Project create: `ledger/src/pages/AddItem.tsx`
- Project edit: `ledger/src/pages/EditItem.tsx`
- Inventory create/edit parity sources (must reuse the same shared module in mobile):
  - `ledger/src/pages/AddBusinessInventoryItem.tsx`
  - `ledger/src/pages/EditBusinessInventoryItem.tsx`

## Writes (local-first)

- Create item(s) (create-only):
  - Supports “Quantity” create loop.
- Update item fields (edit-only).
- Optional association:
  - transactionId association
  - spaceId association
- Images:
  - upload images (may create `offline://` placeholders)
  - remove images (deletes local blob immediately when placeholder)
  - set primary image
  - Attachment contract (required; GAP B):
    - Persisted images are `AttachmentRef[]` on `item.images[]` (see `20_data/data_contracts.md`), with `kind: "image"`.
    - Upload state (`local_only | uploading | failed | uploaded`) is derived locally (see `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`), not stored on the Firestore item doc.

Offline media lifecycle (mobile target):

- `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
- `40_features/_cross_cutting/ui/shared_ui_contracts.md` → “Media UI surfaces”

## Validation (required; parity)

- The user must provide **either**:
  - a non-empty description, **or**
  - at least one image

Copy (parity):

- `Add a description or at least one image`

Parity evidence:

- `ledger/src/pages/AddItem.tsx` (`validateForm`)
- `ledger/src/pages/EditItem.tsx` (`validateForm`)

## UI structure (high level)

### Shared (create + edit)

- Back button (uses `returnTo` when present, otherwise scope fallback)
- SKU input (supports dictation / normalization)
- Description input (supports dictation)
- Images:
  - preview grid with remove (and set primary where supported)
  - max 5 images
  - add images from gallery/camera
  - offline banner when offline: images are stored locally and will sync later
- Optional “associate with transaction” picker
- Source picker:
  - preset vendor list + “Other” custom source input
- Payment method picker:
  - (parity) `Client Card`, `COMPANY_NAME` style options
- Prices:
  - purchase price, project price, market value
  - Save-time default: if project price is blank, set it to purchase price
- Space selector
- Notes input

### Create-only (project + inventory)

- Quantity selector:
  - create \(N\) items in a loop (minimum 1)
- Disposition/status selector (parity exists on create form):
  - e.g. `to purchase`, `purchased`, `to return`, `returned`

### Edit-only (project + inventory)

- Optional “associate with project” correction control (parity: edit screen supports changing project):
  - This is disabled when the item is tied to a transaction.
  - If tied to a canonical inventory transaction id, show a specialized helper message.

Parity evidence:

- Create form sections + quantity + transaction-selected behavior: `ledger/src/pages/AddItem.tsx`
- Edit form: project association disable reasons + “remove from transaction” confirm: `ledger/src/pages/EditItem.tsx`

## Behavior rules (required)

### 1) Max images = 5

- The UI must prevent adding more than 5 images.

Parity evidence:

- `ledger/src/pages/AddItem.tsx` (`ImagePreview maxImages={5}`)
- `ledger/src/pages/EditItem.tsx` (`ImagePreview maxImages={5}`)

### 2) Save-time project price defaulting

- Do not auto-fill project price while typing.
- On submit, if project price is blank, set it to purchase price.

Parity evidence:

- `ledger/src/pages/AddItem.tsx` (comment + `projectPrice: formData.projectPrice || formData.purchasePrice`)
- `ledger/src/pages/EditItem.tsx` (`projectPrice: formData.projectPrice || formData.purchasePrice`)

### 3) Associate with transaction (optional)

- User can select a transaction to associate the item with.
- Create-only parity: when a transaction is selected, source and purchased by are auto-filled and those fields are hidden; a small info banner is shown.

Parity evidence:

- `ledger/src/pages/AddItem.tsx` (`isTransactionSelected` banner + hide source/purchased by fields)

### 4) Remove from transaction (edit-only; parity)

- If the item is currently associated with a transaction, the edit form must provide a “Remove from transaction” affordance.
- Removal requires explicit confirmation and does not delete the item.

Parity evidence:

- `ledger/src/pages/EditItem.tsx` (`showRemoveFromTransactionConfirm`)

