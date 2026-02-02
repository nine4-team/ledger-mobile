# Screen contract: `TransactionForm` (create + edit)

## Intent
Create or edit a transaction in the current workspace scope (project or business inventory) with predictable validation, explicit offline prerequisites gating, and offline-safe media attachment behavior.

Shared-module requirement:

- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`

## Canonical vs non-canonical constraint (new model; required)

Source of truth:

- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`

Rules:

- This form is for **user-facing (non-canonical)** transactions.
- **Canonical inventory transactions** (`INV_PURCHASE_*`, `INV_SALE_*`) are system-generated and should be treated as **read-only** (recommended: hide/disable “Edit” entrypoint for canonical rows).

## Inputs
- Route params:
  - `scope`: `'project' | 'inventory'`
  - `projectId` (required when `scope === 'project'`; absent when `scope === 'inventory'`)
  - `transactionId` (edit only)
- Query params:
  - `returnTo` (optional back destination)
- Entry points:
  - Transactions list → “Create Manually” (`AddTransaction`)
  - Transaction detail → “Edit” (`EditTransaction`)

## Reads (local-first)
- Local DB queries:
  - Project name (for labeling and media path hints; only when `scope === 'project'`)
  - Budget categories (for category picker)
  - Vendor defaults (for source picker)
  - Transaction (edit only)
  - Transaction items (edit only; and optionally create form if itemization enabled)
- Derived view models:
  - `itemizationEnabled` derived from selected category
    - Recommended: `itemizationEnabled = (budgetCategory.metadata.categoryType === "itemized")`
    - Mutual exclusivity: a category cannot be both `fee` and `itemized` because `categoryType` is a single field (see `20_data/data_contracts.md`).
- Cached metadata dependencies:
  - Budget categories, vendor defaults

## Writes (local-first)

### Create (submit)
- Firestore mutation(s) (queued offline by Firestore-native persistence):
  - Create/update the `transactions/{transactionId}` doc (prefer a client-generated `transactionId` for idempotency).
  - If itemization is enabled, create/update transaction items (either as docs in a subcollection or separate collection, per data model), ideally via a batched write when possible.
  - Persist media attachment refs on the transaction doc as `AttachmentRef[]` (see `20_data/data_contracts.md`):
    - `receiptImages[]` (accepts `kind: "image" | "pdf"`)
    - `otherImages[]` (image-only; `kind: "image"`)
    - (legacy compat) `transactionImages[]` may mirror receipts
- Media uploads:
  - Uploads are handled by an upload queue that can create `offline://<mediaId>` placeholders while offline.
  - After upload succeeds, patch the transaction doc to replace placeholders with Cloud Storage URLs.
  - Upload state (`local_only | uploading | failed | uploaded`) is derived locally; do not persist it on the transaction doc.

### Edit (submit)
- Firestore mutation(s) (queued offline by Firestore-native persistence):
  - Update `transactions/{transactionId}` fields + attachments arrays.
  - Update/create/unlink transaction items as needed (prefer batched writes for multi-doc updates that must stay consistent).
  - Queue media uploads for newly added files (offline placeholders).

## UI structure (high level)
- Header:
  - Back (returnTo/stacked back)
  - Retry sync button when sync error is present
- Form sections:
  - Source/vendor selection (vendor slots + custom “Other”)
  - Budget category picker (required)
  - Transaction type (Purchase/Return)
  - Payment method (Client Card / Company)
  - Status (edit only: pending/completed/canceled)
  - Reimbursement type (None / owed-to-company / owed-to-client)
  - Amount (required)
  - Tax (conditional; see rules below)
  - Transaction date
  - Notes
  - Transaction items (only when itemization enabled; edit also shows if existing items exist)
  - Receipts upload
  - Receipt emailed toggle
  - Other images upload
- Footer actions:
  - Cancel
  - Save/Create with disabled state when submitting or prerequisites not ready

## User actions → behavior (the contract)
- **Offline prerequisites not ready**:
  - Show a banner and disable submit.
  - On submit attempt, show an error explaining prerequisites must be synced.
- **Source selection**:
  - Choosing a vendor radio sets `source`.
  - Choosing “Other” clears source and shows a text input.
- **Category selection**:
  - Required.
  - Changing category may enable/disable itemization; if disabling but there are existing items (edit), show warning and still allow managing existing items.
  - New requirement (item attribution determinism): if editing a non-canonical transaction and the category changes, update all linked items to keep attribution deterministic:
    - `item.inheritedBudgetCategoryId = transaction.budgetCategoryId` for each linked item
    - This ensures future canonical inventory transactions can attribute amounts by item category without asking the user to learn a “canonical category”.
- **Amount**:
  - Required and must be positive.
- **Tax (simplified; no presets)**:
  - **No tax presets exist**. Tax is captured inline on the transaction.
  - **Visibility rule**: tax inputs are shown only when the selected budget category is **itemized** (recommended: `budgetCategory.metadata.categoryType === "itemized"`). Otherwise, do **not** show tax inputs and treat tax as **None**.
  - When shown, tax has 3 selectable modes (plus an optional amount override):
    - **None (default)**: no tax is applied; tax fields are cleared.
    - **Tax rate**: user enters a tax rate percent. The UI derives:
      - `subtotal = total / (1 + rate)`
      - `taxAmount = total - subtotal`
    - **Calculate from subtotal**: user enters a subtotal. The UI derives:
      - `taxAmount = total - subtotal`
      - `taxRate = (taxAmount / subtotal)` (when `subtotal > 0`)
      - Validation: `subtotal > 0` and `subtotal <= total`.
  - **Tax amount input (optional)**: user may enter a tax amount directly; the UI back-calculates:
    - `subtotal = total - taxAmount`
    - `taxRate = (taxAmount / subtotal)` (when `subtotal > 0`)
    - Validation: `taxAmount >= 0` and `taxAmount < total`.
- **Receipts + other images**:
  - Adding files:
    - Online: upload and attach
    - Offline: create `offline://<mediaId>` placeholder and attach immediately; queued upload later
  - Removing files:
    - Removes from the attached array immediately.
    - If file is an `offline://` placeholder, also deletes the local media blob file.
- **Status ↔ reimbursement coupling (edit)**:
  - If status becomes `completed` while reimbursement is set, reimbursement is cleared.
  - If reimbursement is set while status is `completed`, status becomes `pending`.

## States
- Loading:
  - Edit shows “Loading transaction…” while hydrating/fetching.
- Error:
  - General error banner displays submission failures.
- Offline:
  - Form remains usable if prerequisites are warm; otherwise it is blocked.
- Pending sync:
  - After saving offline or with placeholder uploads, show “saved offline” feedback and allow user to navigate away.
- Permissions denied:
  - Create: deny when user lacks account context (unless system owner).
  - Edit: deny when user lacks required role.
- Quota/media blocked:
  - If the local media subsystem is full, media selection should be blocked with an explicit message (cross-cutting quota behavior).

## Media (if applicable)
- Receipt attachments accept images and PDFs.
- Other images accept images.
- Placeholder URLs use `offline://<mediaId>` and must render via local blob resolution in previews.

## Collaboration / realtime expectations
- Form does not require live collaboration; changes converge via Firestore listeners and queued writes (no bespoke outbox engine), per `OFFLINE_FIRST_V2_SPEC.md`.

## Performance notes
- Avoid per-item network calls during itemization edits; use Firestore cache and batched writes where needed.

## Parity evidence
- Create prerequisites gate + banner: Observed in `src/pages/AddTransaction.tsx` (`useOfflinePrerequisiteGate`, `OfflinePrerequisiteBanner`).
- Vendor defaults (online vs cached): Observed in `src/pages/AddTransaction.tsx` (`getAvailableVendors`, `getCachedVendorDefaults`).
- Tax (intentional delta): tax presets are removed; the form captures tax via inline fields (rate/subtotal/tax amount) instead of a preset picker.
- Edit permission gating: Observed in `src/pages/EditTransaction.tsx` (`hasRole(UserRole.USER)`).
- Edit status ↔ reimbursement coupling: Observed in `src/pages/EditTransaction.tsx` (`handleInputChange`).
- Existing image preview/removal: Observed in `src/pages/EditTransaction.tsx` (`TransactionImagePreview`, remove handlers).
- Offline placeholder upload path: Observed in `src/pages/AddTransaction.tsx`/`src/pages/EditTransaction.tsx` (`OfflineAwareImageService.upload*`).
