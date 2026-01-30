# Data contracts (canonical entity shapes)

This document is the **single source of truth** for **domain entity contracts** in the Firebase mobile migration.

If there is a disagreement between:

- a feature spec under `40_features/**`
- `firebase_data_model.md` (Firestore)
- `local_sqlite_schema.md` (SQLite)

…this document wins. The other docs should **reference** these contracts rather than restating fields.

---

## Conventions (applies to all entities below)

### Naming

- **Canonical field names** are `camelCase` (TypeScript + Firestore documents).
- **SQLite columns** are `snake_case`.

### Money representation (decision)

We adopt **Option B (tightened)** for Items + Transactions:

- **All currency amounts are persisted as integer cents** in Firestore + SQLite.
- UI/services convert cents ↔ display decimals.
- Legacy imports (strings like `"123.45"`) must be parsed deterministically:
  - accept only finite numeric decimal strings
  - round to cents using a single documented strategy (recommended: half-away-from-zero)
  - invalid strings must not be silently stored; mark rows as `needsReview` and/or preserve raw input in a local-only migration log (not in canonical contracts)

Rationale:
- Budget + accounting rollups are correctness-critical and must not drift due to float parsing differences across platforms.
- Project budgets are already tightened to cents; Items + Transactions must be compatible with the same rollup arithmetic.

### Scopes (non-negotiable)

There are exactly **two collaboration scopes**:

- **Project scope**: `projectId = "<projectId>"` and docs live under `accounts/{accountId}/projects/{projectId}/...`
- **Business inventory scope**: `projectId = null` and docs live under `accounts/{accountId}/inventory/...`

Contract rule:
- `projectId: string | null` is always present on **scoped mutable entities** (items/transactions/spaces/attachments, etc.).
- `projectId = null` must mean **Business Inventory** (not “unknown project”).

### Sync fields (delta sync + outbox)

For every **scoped mutable entity doc** (including items, transactions, attachments, lineage edges), include:

- `updatedAt: Timestamp` (server timestamp; updated on every accepted change)
- `deletedAt: Timestamp | null` (tombstone)
- `version: number` (integer for conflict detection)
- `updatedBy?: string | null` (uid)
- `lastMutationId?: string` (outbox op id; required if you implement end-to-end idempotency)
- `schemaVersion?: number` (optional; recommended)

### Security fields (Roles v2)

Roles v2 requires **server-enforceable selectors**. At minimum:

- Entities that use “own uncategorized” behavior MUST include `createdBy: string` (uid).
  - Required for **Items** (see Roles v2 spec: uncategorized items visible only to creator).

---

## Entity: Project

### Canonical fields (TypeScript / Firestore doc shape)

Required:
- `id: string` (doc id)
- `accountId: string`
- `name: string`
- `clientName: string`

Optional / nullable:
- `description?: string | null`
- `budgetCents?: number | null`
  - Stored as integer cents.
- `designFeeCents?: number | null`
  - Stored as integer cents.
- `defaultCategoryId?: string | null`
- `mainImageUrl?: string | null`
  - Parity field: project cover image URL stored directly on the project.
- `mainImageAttachmentId?: string | null`
  - Optional optimization: points at an attachment doc (if/when attachment docs exist).
- `settings?: Record<string, any> | null`
- `metadata?: Record<string, any> | null`

Derived/denormalized (optional; must not be correctness-critical):
- `itemCount?: number`
- `transactionCount?: number`
- `totalValueCents?: number`

Sync fields (required): see “Sync fields” above.

### Firestore location

- `accounts/{accountId}/projects/{projectId}`

Project budgeting allocations (per-category budgets / enablement):

- See **Entity: ProjectBudgetCategory** (stored as one doc per preset category):
  - `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`

### SQLite mapping

Table: `projects`

Columns (recommended):
- **identity**: `id`, `account_id`
- **core**: `name`, `client_name`, `description`
- **budgeting**:
  - `budget_cents` (INTEGER)
  - `design_fee_cents` (INTEGER)
  - `default_category_id` (TEXT)
- **images**:
  - `main_image_url` (TEXT)
  - `main_image_attachment_id` (TEXT)
- **flex**:
  - `settings_json` (TEXT)
  - `metadata_json` (TEXT)
- **sync + local bookkeeping**: per `local_sqlite_schema.md` common columns

Notes:
- Keep both `main_image_url` and `main_image_attachment_id` available: lists want a cheap URL without joins; attachment docs are optional.

---

## Entity: BudgetCategory (account preset)

This is the account-wide **preset category definition** used by:

- transaction category pickers (`transaction.budgetCategoryId`)
- project budget setup (project-specific allocation docs reference these ids)

### Canonical fields (TypeScript / Firestore doc shape)

Required:

- `id: string` (doc id)
- `accountId: string`
- `projectId: null`
  - Kept as `null` for compatibility with the shared “two scope” domain model (project scope vs account-level scope).
- `name: string`
- `slug: string`
  - Stable identifier (recommended unique per account).
- `isArchived: boolean`

Optional / nullable:

- `metadata?: Record<string, any> | null`
  - Examples used by specs: `itemizationEnabled`, `systemTag` (e.g. `design_fee`), etc.

Sync fields (required): see “Sync fields” above.

### Firestore location

- `accounts/{accountId}/presets/budgetCategories/{budgetCategoryId}`

### SQLite mapping

Table: `budget_categories`

Key columns (recommended):

- `id` (TEXT PRIMARY KEY)
- `account_id` (TEXT NOT NULL)
- `project_id` (TEXT NULL; always NULL for presets)
- `name` (TEXT NOT NULL)
- `slug` (TEXT NOT NULL)
- `is_archived` (INTEGER NOT NULL DEFAULT 0)
- `metadata_json` (TEXT NULL)
- sync + local bookkeeping columns (per `local_sqlite_schema.md`)

---

## Entity: ProjectBudgetCategory (project allocation for a preset category)

This entity represents a project’s per-category budget allocation and enablement for a given **preset** budget category.

Key rule (anti-duplication):

- This doc MUST NOT duplicate `BudgetCategory.name`. Display name comes from the preset category doc.

### Canonical fields (TypeScript / Firestore doc shape)

Doc id:

- `id = budgetCategoryId` (the preset id)

Required:

- `budgetCents: number | null`
  - Integer cents.
  - `null` means “enabled but not budgeted” (UI can still show spend tracking).

Sync fields (required): see “Sync fields” above.

### Firestore location

- `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`

### SQLite mapping

Table: `project_budget_categories`

Key columns (recommended):

- `account_id` (TEXT NOT NULL)
- `project_id` (TEXT NOT NULL)
- `budget_category_id` (TEXT NOT NULL)
- `budget_cents` (INTEGER NULL)
- sync + local bookkeeping columns (per `local_sqlite_schema.md`)

Primary key:

- `(account_id, project_id, budget_category_id)`

---

## Entity: Item

This contract must satisfy:
- `40_features/project-items/feature_spec.md` (requires `inheritedBudgetCategoryId`)
- `40_features/budget-and-accounting/feature_spec.md` (canonical attribution uses item prices)
- `40_features/inventory-operations-and-lineage/feature_spec.md` + `flows/lineage_edges_and_pointers.md` (lineage pointers)
- `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md` (requires `createdBy` and selector semantics)

### Canonical fields

Required:
- `id: string` (doc id; stable across offline/online)
- `accountId: string`
- `projectId: string | null`
- `createdBy: string`
  - Roles v2: required to enforce “own uncategorized items” when `inheritedBudgetCategoryId == null`.
- `description: string`
  - Parity: items always have a description string (may be empty).

Optional / nullable:
- `name?: string | null`
- `source?: string | null`
- `sku?: string | null`
- `notes?: string | null`
- `bookmark?: boolean`
- `paymentMethod?: string | null`
- `disposition?: "to purchase" | "purchased" | "to return" | "returned" | "inventory" | null`

Relationships / selectors (nullable):
- `transactionId?: string | null`
- `spaceId?: string | null`
- `inheritedBudgetCategoryId?: string | null`
  - **Required field** (may be null): stable attribution selector for budgeting + Roles v2.
  - Set/update rules are defined in `40_features/project-items/feature_spec.md` and must be enforced by server-owned invariants for cross-scope ops.

Money fields (integer cents; nullable):
- `purchasePriceCents?: number | null`
- `projectPriceCents?: number | null`
- `marketValueCents?: number | null`

Tax fields (integer cents; nullable):
- `taxRatePct?: number | null`
- `taxAmountPurchasePriceCents?: number | null`
- `taxAmountProjectPriceCents?: number | null`

Inventory-state (nullable; shared module across project + business inventory):
- `inventoryStatus?: "available" | "allocated" | "sold" | null`
- `businessInventoryLocation?: string | null`

Lineage pointers (nullable):
- `originTransactionId?: string | null`
- `latestTransactionId?: string | null`

Sync fields (required): see “Sync fields” above.

### Scope semantics + Firestore locations

Project-scope item:
- `projectId = "<projectId>"`
- Firestore: `accounts/{accountId}/projects/{projectId}/items/{itemId}`

Business inventory item:
- `projectId = null`
- Firestore: `accounts/{accountId}/inventory/items/{itemId}`

### SQLite mapping

Table: `items`

Key columns:
- `id` (TEXT PRIMARY KEY)
- `account_id` (TEXT NOT NULL)
- `project_id` (TEXT NULL)

Selector columns:
- `created_by` (TEXT NOT NULL)
- `inherited_budget_category_id` (TEXT NULL)
- `transaction_id` (TEXT NULL)
- `space_id` (TEXT NULL)

Money columns:
- `purchase_price_cents` (INTEGER NULL)
- `project_price_cents` (INTEGER NULL)
- `market_value_cents` (INTEGER NULL)

Tax columns:
- `tax_rate_pct` (REAL NULL)
- `tax_amount_purchase_price_cents` (INTEGER NULL)
- `tax_amount_project_price_cents` (INTEGER NULL)

Lineage pointers:
- `origin_transaction_id` (TEXT NULL)
- `latest_transaction_id` (TEXT NULL)

Other columns:
- `name` (TEXT NULL)
- `description` (TEXT NOT NULL)
- `source` (TEXT NULL)
- `sku` (TEXT NULL)
- `notes` (TEXT NULL)
- `bookmark` (INTEGER NOT NULL DEFAULT 0)
- `payment_method` (TEXT NULL)
- `disposition` (TEXT NULL)
- `inventory_status` (TEXT NULL)
- `business_inventory_location` (TEXT NULL)

Sync + local bookkeeping: per `local_sqlite_schema.md` common columns.

---

## Entity: Transaction

This contract must satisfy:
- `40_features/project-transactions/feature_spec.md` (filters, canonical title/amount semantics, receipts/PDFs via attachments)
- `40_features/project-items/feature_spec.md` + `40_features/budget-and-accounting/feature_spec.md` (canonical attribution rules)
- `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md` (server-enforceable visibility for canonical rows)

### Canonical fields

Required:
- `id: string` (doc id; stable across offline/online)
- `accountId: string`
- `projectId: string | null`
- `transactionDate: string`
  - Stored as string for parity with existing flows; treat as an ISO-like date/time string.
- `amountCents: number`
  - **Authoritative** for non-canonical transactions.
  - For canonical inventory transactions, this may be **derived/cache** (see “INV_* semantics” below).

Optional / nullable:
- `source?: string | null`
- `transactionType?: string | null`
- `paymentMethod?: string | null`
- `notes?: string | null`
- `status?: "pending" | "completed" | "canceled" | null`
- `reimbursementType?: string | null`
- `triggerEvent?: string | null`
- `receiptEmailed?: boolean`

Budget category selector:
- `budgetCategoryId?: string | null`
  - Non-canonical: authoritative category selector.
  - Canonical inventory (`INV_*`): recommended to remain `null` (“uncategorized”) and must not be used for attribution.

Completeness / rollup helpers (optional; denormalized):
- `needsReview?: boolean`
- `taxRatePresetId?: string | null`
- `taxRatePct?: number | null`
- `subtotalCents?: number | null`
- `sumItemPurchasePricesCents?: number | null`

Canonical inventory transaction selectors (Roles v2 + queryability):
- `isCanonicalInventory?: boolean`
- `canonicalKind?: "INV_PURCHASE" | "INV_SALE" | "INV_TRANSFER" | null`
- `attributedCategoryIds?: Record<string, true> | null`
  - Server-maintained selector for canonical transactions only:
    - keys are non-null `item.inheritedBudgetCategoryId` values present among linked items
- `attributedUncategorizedCreatorUids?: Record<string, true> | null`
  - Server-maintained selector for canonical transactions only:
    - keys are uids of creators who have at least one linked item with `inheritedBudgetCategoryId == null`

Linkage helpers (optional; denormalized):
- `itemIds?: string[]`
  - Non-authoritative cache; use `item.transactionId` as the canonical association.

Sync fields (required): see “Sync fields” above.

### INV_* semantics (authoritative vs derived)

Canonical inventory transactions are identified by id prefix:
- `INV_PURCHASE_<projectId>`
- `INV_SALE_<projectId>`
- `INV_TRANSFER_*`

Required attribution invariant:
- **Non-canonical** transactions: category attribution is transaction-driven via `transaction.budgetCategoryId`.
- **Canonical inventory (`INV_*`)** transactions: category attribution is **item-driven** by grouping linked items by `item.inheritedBudgetCategoryId`.
  - `transaction.budgetCategoryId` must be treated as **non-authoritative** even if populated for compatibility.

Authoritative value source for canonical totals:
- For canonical `INV_*` totals, the authoritative source is the linked items’ values (see `40_features/budget-and-accounting/feature_spec.md`).
- `transaction.amountCents` may be treated as a cached/denormalized value for list rendering, but must be safe to recompute.

### Scope semantics + Firestore locations

Project-scope transaction:
- `projectId = "<projectId>"`
- Firestore: `accounts/{accountId}/projects/{projectId}/transactions/{transactionId}`

Business inventory transaction:
- `projectId = null`
- Firestore: `accounts/{accountId}/inventory/transactions/{transactionId}`

### SQLite mapping

Table: `transactions`

Key columns:
- `id` (TEXT PRIMARY KEY)
- `account_id` (TEXT NOT NULL)
- `project_id` (TEXT NULL)

Core columns:
- `transaction_date` (TEXT NOT NULL)
- `amount_cents` (INTEGER NOT NULL)
- `source` (TEXT NULL)
- `transaction_type` (TEXT NULL)
- `payment_method` (TEXT NULL)
- `notes` (TEXT NULL)

Workflow columns:
- `status` (TEXT NULL)
- `reimbursement_type` (TEXT NULL)
- `trigger_event` (TEXT NULL)
- `receipt_emailed` (INTEGER NOT NULL DEFAULT 0)

Category + canonical semantics:
- `budget_category_id` (TEXT NULL)
- `is_canonical_inventory` (INTEGER NOT NULL DEFAULT 0)
- `canonical_kind` (TEXT NULL)
- `attributed_category_ids_json` (TEXT NULL) (JSON map of `{ [categoryId]: true }`)
- `attributed_uncategorized_creator_uids_json` (TEXT NULL) (JSON map of `{ [uid]: true }`)

Completeness / denormalized helpers:
- `needs_review` (INTEGER NOT NULL DEFAULT 0)
- `tax_rate_preset_id` (TEXT NULL)
- `tax_rate_pct` (REAL NULL)
- `subtotal_cents` (INTEGER NULL)
- `sum_item_purchase_prices_cents` (INTEGER NULL)
- `item_ids_json` (TEXT NULL) (optional; JSON array; non-authoritative cache)

Sync + local bookkeeping: per `local_sqlite_schema.md` common columns.

---

## Entity: Attachment

Decision (canonical storage):
- **Attachment documents are canonical**. Parent entities (items/transactions/spaces/projects) should not embed canonical arrays of attachment metadata.

This contract must satisfy:
- `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md` (required UI state machine; images + PDFs)
- `40_features/project-transactions/feature_spec.md` (receipts + other images; offline placeholders)
- `40_features/sync_engine_spec.plan.md` (§8 media strategy; attachment docs + delta visibility)

### Canonical fields

Required:
- `id: string` (doc id)
- `accountId: string`
- `projectId: string | null`
- `parentType: "item" | "transaction" | "space" | "project"`
- `parentId: string`

Optional / nullable:
- `kind?: "receipt" | "image" | "pdf" | "other" | null`
  - Why it exists: UI can separate receipts vs other media without guessing from mime types.

Remote file identity (nullable until uploaded):
- `storagePath?: string | null`
- `mimeType?: string | null`
- `byteSize?: number | null`
- `sha256?: string | null`
- `filename?: string | null`

Media metadata (optional):
- `width?: number | null`
- `height?: number | null`
- `durationMs?: number | null`

Lifecycle state (remote-visible; nullable):
- `uploadState?: "uploading" | "uploaded" | "failed" | null`
  - Note: `local_only` is a **local-only** state (cannot be represented in Firestore when offline).
- `uploadError?: string | null`

Audit (recommended):
- `createdBy?: string | null`
- `uploadedBy?: string | null`
- `uploadedAt?: Timestamp | null`

Sync fields (required once the doc exists in Firestore): see “Sync fields” above.

Local-only fields (SQLite only; never persisted to Firestore):
- `localUri?: string | null`
- `localMediaId?: string | null`

### Firestore locations

Project-scope attachments:
- `accounts/{accountId}/projects/{projectId}/attachments/{attachmentId}`

Business inventory attachments:
- `accounts/{accountId}/inventory/attachments/{attachmentId}`

### SQLite mapping

Table: `attachments`

Key columns:
- `id`, `account_id`, `project_id`

Parent association:
- `parent_type` (TEXT NOT NULL)
- `parent_id` (TEXT NOT NULL)
- `kind` (TEXT NULL)

Lifecycle + local cache:
- `upload_state` (TEXT NOT NULL) (`local_only`, `uploading`, `uploaded`, `failed`)
- `upload_error` (TEXT NULL)
- `local_uri` (TEXT NULL)
- `local_media_id` (TEXT NULL)

Remote identity:
- `storage_path` (TEXT NULL)
- `mime_type` (TEXT NULL)
- `byte_size` (INTEGER NULL)
- `sha256` (TEXT NULL)
- `filename` (TEXT NULL)
- `width` (INTEGER NULL)
- `height` (INTEGER NULL)
- `duration_ms` (INTEGER NULL)
- `uploaded_by` (TEXT NULL)
- `uploaded_at_server` (INTEGER NULL)

Sync + local bookkeeping: per `local_sqlite_schema.md` common columns.

---

## Entity: LineageEdge (append-only)

This contract must satisfy:
- `40_features/inventory-operations-and-lineage/feature_spec.md` (append-only edges + item pointers)
- `40_features/inventory-operations-and-lineage/flows/lineage_edges_and_pointers.md` (offline availability requirement)

### Canonical fields

Required:
- `id: string` (doc id)
- `accountId: string`
- `itemId: string`
- `fromTransactionId: string | null`
  - `null` means “from inventory” (no prior transaction context).
- `toTransactionId: string | null`
  - `null` means “to inventory”.
- `createdAt: Timestamp`
- `createdBy: string`

Optional:
- `note?: string | null`

Sync fields (required): see “Sync fields” above.

### Firestore location (cross-scope)

Lineage must remain available across item scope moves (project ↔ inventory). To avoid losing history when an item changes physical collection location, lineage edges are stored in an **account-wide collection**:

- `accounts/{accountId}/lineageEdges/{edgeId}`

### SQLite mapping

Table: `lineage_edges`

Key columns:
- `id` (TEXT PRIMARY KEY)
- `account_id` (TEXT NOT NULL)
- `item_id` (TEXT NOT NULL)

Edge columns:
- `from_transaction_id` (TEXT NULL)
- `to_transaction_id` (TEXT NULL)
- `note` (TEXT NULL)
- `created_at_server` (INTEGER NOT NULL)
- `created_by` (TEXT NOT NULL)

Sync + local bookkeeping: per `local_sqlite_schema.md` common columns.

