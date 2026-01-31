# Project Transactions — Feature spec (Firebase mobile migration)

## Intent
Provide an offline-ready Transactions experience inside a project: users can browse/search/filter/sort transactions, export to CSV, and create/edit/view transactions (including receipts and “itemization”) with predictable offline behavior.

Architecture baseline (mobile):
- **Firestore-native offline persistence** is the default (Firestore is canonical).
- “Freshness” while foregrounded is achieved via **scoped listeners** on bounded queries (never unbounded “listen to everything”).
- Any multi-doc/invariant operations use **request-doc workflows** (Cloud Function applies changes in a transaction).

## Shared module requirement (Project + Business Inventory)

Transactions must be implemented as a **shared domain module + shared UI primitives** reused across:

- Project workspace context
- Business inventory workspace context

This is a hard requirement to avoid the current web app failure mode where project vs inventory transaction UIs drift because they are implemented separately.

Source of truth:

- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`

## Canonical vs non-canonical budget category semantics (new model; required)

This feature must align with:

- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`
- The item field + guardrails in `40_features/project-items/feature_spec.md`

Definitions:

- **Non-canonical (user-facing) transaction**: a normal user-entered transaction where budget category attribution is **transaction-driven** via `transaction.budgetCategoryId`.
  - Legacy naming notes: web/SQL docs may refer to this as `category_id`; the canonical SQLite column name is `budget_category_id` (see `20_data/data_contracts.md`).
- **Canonical inventory transaction**: a system-generated row with id `INV_PURCHASE_<projectId>`, `INV_SALE_<projectId>`, or `INV_TRANSFER_*`.

Rules (required):

- **Non-canonical**: budget category attribution comes from `transaction.budgetCategoryId`.
- **Canonical inventory**: must be treated as **uncategorized** on the transaction row (recommend `budgetCategoryId = null`) and category attribution is **item-driven** by grouping linked items by `item.inheritedBudgetCategoryId`.

Implications for this feature:

- “Budget category” UI (badges, filters, exports) must not assume canonical rows have a meaningful `budgetCategoryId`.
- Any “budget category filter” must include canonical rows via linked items’ `inheritedBudgetCategoryId` rather than `transaction.budgetCategoryId`.

## Owned screens / routes
- **Transactions list**: `ProjectTransactionsPage` → `TransactionsList` (shared screen; business-inventory wrapper composes the same list component with `scope='inventory'`)
  - Web parity sources: `src/pages/ProjectTransactionsPage.tsx`, `src/pages/TransactionsList.tsx`
- **Create transaction**: `AddTransaction` (shared form screen; wrapper may differ by scope)
  - Web parity source: `src/pages/AddTransaction.tsx`
- **Edit transaction**: `EditTransaction` (shared form screen; wrapper may differ by scope)
  - Web parity source: `src/pages/EditTransaction.tsx`
- **Transaction detail**: `TransactionDetail` (shared screen; routable from both project and business-inventory contexts)
  - Web parity source: `src/pages/TransactionDetail.tsx`

Screen contracts:
- `ui/screens/TransactionsList.md`
- `ui/screens/TransactionForm.md`
- `ui/screens/TransactionDetail.md`

## Primary flows

### 1) Browse transactions (list/search/sort/filter)
Summary:
- Transactions render as a list of preview cards with title, amount, payment method, date, notes preview, and badges (category/type + needs-review/missing-items).
- List state (search, filters, sort) is persisted and restored when navigating to detail and back.
  - Web parity mechanism: URL params + `restoreScrollY`.
  - Mobile (Expo Router) mechanism: shared Transactions list module persists state via `ListStateStore[listStateKey]` and restores scroll best-effort (anchor-first).

Filters/sorts/search (web parity):
- Sort modes: date, created, source, amount.
- Filters: reimbursement status, email receipt, purchase method, transaction type, budget category, completeness.
- Search matches title/source/type/notes and amount-ish queries.

Canonical transaction display:
- Canonical sale/purchase transaction IDs are displayed with special titles (“Company Inventory Sale/Purchase” style titles).
- Canonical totals may be recomputed from linked items and (in web) the list self-heals stale amounts by updating the stored transaction amount.

Budget category filter behavior (required; intentional delta vs web):

- For **non-canonical** transactions, the “budget category” filter matches `transaction.budgetCategoryId`.
- For **canonical inventory** transactions, the “budget category” filter matches if the transaction has **at least one linked item** with `item.inheritedBudgetCategoryId === <selectedCategoryId>`.
  - This requires local DB support for joining items by `transactionId` and filtering by `inheritedBudgetCategoryId`.

Parity evidence:
- Filters/sorts/search state + URL params: `src/pages/TransactionsList.tsx` (searchParams `txSearch`, `txFilter`, `txSource`, `txReceipt`, `txType`, `txPurchaseMethod`, `txCategory`, `txCompleteness`, `txSort`)
- Scroll restoration (web): `src/pages/TransactionsList.tsx` (`restoreScrollY`)

Mobile requirement (Expo Router; shared-module):
- Do not re-implement “state persistence + scroll restoration” per scope.
- Implement once in the shared Transactions list module, keyed by:
  - `listStateKey = project:${projectId}:transactions` (project scope)
  - `listStateKey = inventory:transactions` (inventory scope)
- Restore behavior: anchor-id restore preferred (`anchorId = <opened transactionId>`), optional scroll-offset fallback.
- Canonical title + computed totals + self-heal: `src/pages/TransactionsList.tsx` (`getCanonicalTransactionTitle`, `computeCanonicalTransactionTotal`, `transactionService.updateTransaction`)

Firebase migration constraint:
- Do not implement unbounded listeners on `transactions`; use **scoped listeners** + pagination/limits per `OFFLINE_FIRST_V2_SPEC.md`.

### 2) Export transactions to CSV
Summary:
- The list view can export a CSV of transactions (web exports “all transactions” for the project, sorted by current sort mode).
- CSV includes both legacy and new category fields (category name + `budgetCategoryId`) **for non-canonical transactions**.
- Canonical inventory transactions should export with `budgetCategoryId` empty and `categoryName` empty/“Uncategorized” (pick one and keep consistent).
  - Optional (recommended): include an additional column like `attributedCategoryIds` or `attributedCategorySummary` derived from linked items’ `inheritedBudgetCategoryId` values so exports remain useful without introducing a “canonical category”.

Parity evidence:
- CSV builder + download: `src/pages/TransactionsList.tsx` (`buildTransactionsCsv`, `handleExportCsv`)

Mobile adaptation:
- Export should be generated from the local DB and shared via native share sheet (not browser download links).

### 3) Create a transaction (manual)
Summary:
- Create is launched from the Transactions list “Add” menu → “Create Manually”.
- The form requires offline prerequisites (categories/vendors/account defaults) to be warm; otherwise submission is blocked and a prerequisite banner is shown.
- User can attach:
  - receipts (images + PDFs)
  - other images (images)
- Itemization (transaction items) is shown only when enabled for the selected category.

Parity evidence:
- Offline prerequisite gate + banner: `src/pages/AddTransaction.tsx` (`useOfflinePrerequisiteGate`, `OfflinePrerequisiteBanner`)
- Vendor defaults + cached offline behavior: `src/pages/AddTransaction.tsx` (`getAvailableVendors`, `getCachedVendorDefaults`)
- Default category (online vs cached): `src/pages/AddTransaction.tsx` (`getDefaultCategory`, `getCachedDefaultCategory`)
- Itemization enablement by category: `src/pages/AddTransaction.tsx` (`getItemizationEnabled`)
- Offline-aware image upload placeholder behavior: `src/pages/AddTransaction.tsx` (`OfflineAwareImageService.uploadReceiptAttachment`, `.uploadOtherAttachment`)

Tax model note (intentional delta):
- **Tax presets are removed**. Transactions capture tax via inline fields (none / tax rate / calculate from subtotal, plus optional tax amount input). See `ui/screens/TransactionForm.md`.

Canonical transaction note:
- Canonical inventory transactions are system-generated (not created through this form).
- Canonical inventory transactions should be treated as **read-only** from the user’s perspective (recommended): the edit action should be disabled/hidden for canonical `INV_*` rows to avoid “assigning a category” or mutating system-owned mechanics.

### 4) Edit a transaction
Summary:
- Edit loads the current transaction and allows updating fields, adding/removing images, and managing itemization.
- Existing receipts/other images are displayed with controls to remove them.
- Business rule coupling status ↔ reimbursement:
  - Setting status to `completed` clears reimbursement type (if set).
  - Setting reimbursement type while status is `completed` forces status to `pending`.

Parity evidence:
- Transaction hydration (cache + fetch): `src/pages/EditTransaction.tsx` (`hydrateTransactionCache`, `transactionService.getTransaction`)
- Existing image preview + removal: `src/pages/EditTransaction.tsx` (`TransactionImagePreview`, `handleRemoveExistingReceiptImage`, `handleRemoveExistingOtherImage`)
- Status ↔ reimbursement coupling: `src/pages/EditTransaction.tsx` (`handleInputChange` rule block)

New requirement (canonical budget categories):

- Editing a transaction’s budget category has downstream effects on linked items:
  - When editing a **non-canonical** transaction and its `budgetCategoryId` changes, all linked items must have `item.inheritedBudgetCategoryId` updated to the new category id (to keep future canonical attribution deterministic).
  - When editing a **canonical inventory** transaction, do not allow category editing (recommended: disallow editing entirely for canonical `INV_*` rows).

### 5) View transaction detail
Summary:
- Transaction detail shows core fields and sections:
  - transaction metadata (category/source/amount/date/payment/status/reimbursement/receipt emailed/notes)
  - receipts section with add/remove, pin, and full-screen gallery
  - other images section (only shown when present) with add/remove, pin, and gallery
  - transaction items (itemization), including adding existing items, creating items, bulk actions, and cross-scope operations
  - audit section (when itemization enabled and not a canonical sale/purchase transaction)
  - delete transaction affordance

Parity evidence:
- Detail layout + sections: `src/pages/TransactionDetail.tsx`
- Receipts/other upload with offline placeholders + local update + queued remote mutation: `src/pages/TransactionDetail.tsx` (`handleReceiptsUpload`, `handleOtherImagesUpload`, `offlineTransactionService.updateTransaction`)
- Delete receipt/other with offline placeholder file cleanup: `src/pages/TransactionDetail.tsx` (`handleDeleteReceiptImage`, `handleDeleteOtherImage`, `offlineMediaService.deleteMediaFile`)
- Gallery integration + pin support: `src/pages/TransactionDetail.tsx` (renders `ImageGallery`, pins with `onPinToggle`)
- Transaction items list integration: `src/pages/TransactionDetail.tsx` (renders `TransactionItemsList` with many handlers)
- Actions menu constraints for canonical: `src/components/transactions/TransactionActionsMenu.tsx`

Out-of-scope linkage:
- Many TransactionDetail item actions (move/sell to project/business inventory) depend on `inventory-operations-and-lineage` semantics. This feature spec captures the **UI contract** and links the multi-entity invariants elsewhere.

New requirement (itemization ↔ `inheritedBudgetCategoryId`):

- When linking/assigning an item to a **non-canonical** transaction with a non-null `budgetCategoryId`, set:
  - `item.inheritedBudgetCategoryId = transaction.budgetCategoryId`
- Linking/unlinking items to a **canonical inventory** transaction must not overwrite `item.inheritedBudgetCategoryId`.

## Offline-first behavior (mobile target)

### Local source of truth
- UI reads from **Firestore’s local cache** via the native Firestore SDK (cache-first reads with server reconciliation when online).
- User writes are **direct Firestore writes** (queued offline by Firestore-native persistence).
- Attachments are represented locally immediately; uploads may create `offline://<mediaId>` placeholders until Cloud Storage URLs are available.

Parity evidence (web’s local-first approximation):
- Offline placeholders for images: `OfflineAwareImageService` usage in `AddTransaction`, `EditTransaction`, `TransactionDetail`
- Offline media preview resolution: `src/components/ui/ImagePreview.tsx` (`offlineMediaService.getMediaFile`)

### Offline prerequisites gate (metadata)
- Creating a transaction requires budget categories + vendor defaults + account default category metadata to be present locally (otherwise the form is blocked).
- The same gate should apply anywhere the user must pick from these lists; do not silently allow “unknown” writes that later conflict.

Parity evidence:
- Gate behavior: `src/pages/AddTransaction.tsx` (`useOfflinePrerequisiteGate`)

### Restart behavior
- On cold start, the Transactions list and Transaction detail should render from local cache if present, then converge via delta when online.

Parity evidence (web hydration):
- Transactions cache hydration: `src/pages/TransactionsList.tsx` (`hydrateProjectTransactionsCache`)
- Transaction cache hydration: `src/pages/EditTransaction.tsx` (`hydrateTransactionCache`)

### Reconnect behavior
-- When returning online, foregrounded screens should converge via Firestore listeners + queued-writes acknowledgement.

Canonical architecture source:
- `OFFLINE_FIRST_V2_SPEC.md`

## Collaboration / “realtime” expectations (mobile target)
- **Scoped listeners only (never unbounded)**:
  - Listen to the project’s transactions via bounded queries (e.g., a page/window of results) and rely on Firestore cache for offline.
  - For very large datasets, use pagination (limit + startAfter) and avoid keeping “all time” listeners attached.
  - Detach listeners on background; reattach on resume.

Canonical migration source:
- `OFFLINE_FIRST_V2_SPEC.md`
