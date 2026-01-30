# Local SQLite Schema (Source of Truth on Device)

This doc defines the local SQLite schema used by the React Native (Expo) client.

Goals:

- **SQLite is the UI source of truth** (screens read from SQLite only)
- durable outbox, sync cursors, and conflicts
- fast list/filter/search at 1,000–10,000 items

Canonical sync constraints:

- [`sync_engine_spec.plan.md`](../sync_engine_spec.plan.md)

---

## Storage strategy (Expo-friendly)

### SQLite driver

Start with Expo’s SQLite. Validate early:

- transaction performance
- WAL mode support
- FTS / prefix search support

If FTS/prefix search is insufficient, move to an Expo Dev Build with a higher-performance native SQLite driver. Keep the schema the same so the migration is mechanical.

### Schema versioning

Maintain:

- `PRAGMA user_version = <int>` for schema migrations
- a migrations table (optional) for detailed tracking:
  - `schema_migrations(version, applied_at)`

Rule:

- never ship a client that cannot migrate from the prior released version.

---

## Core entity tables

The local DB mirrors Firestore entities and adds local-only bookkeeping fields.

### Common columns (apply to all scoped entity tables)

Recommended common fields:

- `id TEXT PRIMARY KEY`
- `account_id TEXT NOT NULL`
- `project_id TEXT` (nullable for account-scoped tables)

Note:
- Cross-scope/account-wide tables (e.g. `lineage_edges`) may omit `project_id` if their Firestore source is not project- or inventory-scoped.

Remote sync fields (mirrored from Firestore):

- `updated_at_server INTEGER` (ms since epoch, from Firestore `updatedAt`)
- `deleted_at_server INTEGER` (ms since epoch, nullable; from `deletedAt`)
- `version INTEGER NOT NULL DEFAULT 0`
- `updated_by TEXT`
- `last_mutation_id TEXT`
- `schema_version INTEGER`

Local-only fields:

- `local_pending INTEGER NOT NULL DEFAULT 0` (0/1; indicates unsynced local changes)
- `local_updated_at INTEGER NOT NULL` (ms since epoch; when local write happened)

---

## Suggested tables (minimal set)

### `accounts`

Account-scoped metadata cached locally.

Columns (example):

- `id`, `name`
- common sync + local fields (account_id = id; project_id null)

### `projects`

This table must match the canonical Project contract:

- See: `20_data/data_contracts.md` → **Entity: Project**

Columns (recommended; aligns with specs and Firestore model):

- Identity:
  - `id TEXT PRIMARY KEY`
  - `account_id TEXT NOT NULL`
- Core:
  - `name TEXT NOT NULL`
  - `client_name TEXT NOT NULL`
  - `description TEXT NULL`
- Budgeting:
  - `budget_cents INTEGER NULL` (currency cents; avoid float drift)
  - `design_fee_cents INTEGER NULL` (currency cents; avoid float drift)
  - `default_category_id TEXT NULL`
- Images:
  - `main_image_url TEXT NULL` (parity field used by list/shell UI)
  - `main_image_attachment_id TEXT NULL` (optional; for attachment-doc redesign)
- Flexible fields:
  - `settings_json TEXT NULL`
  - `metadata_json TEXT NULL`
- Sync + local fields:
  - common sync fields (`updated_at_server`, `deleted_at_server`, `version`, `updated_by`, `last_mutation_id`, `schema_version`)
  - common local fields (`local_pending`, `local_updated_at`)

Indexes:

- `projects(account_id, deleted_at_server, name)`
- `projects(account_id, updated_at_server, id)` (supports delta apply ordering locally)

### `project_budget_categories`

This table stores per-project budget allocations for preset budget categories.

Canonical source:

- See: `20_data/data_contracts.md` → **Entity: ProjectBudgetCategory**

Columns (recommended):

- `account_id TEXT NOT NULL`
- `project_id TEXT NOT NULL`
- `budget_category_id TEXT NOT NULL`
- `budget_cents INTEGER NULL` (integer cents; `NULL` means “enabled but no budget set”)
- common sync + local fields

Primary key:

- `(account_id, project_id, budget_category_id)`

Indexes:

- `project_budget_categories(account_id, project_id)`
- `project_budget_categories(account_id, project_id, updated_at_server, budget_category_id)`

### `items`

This table must match the canonical Item contract:

- See: `20_data/data_contracts.md` → **Entity: Item**

Key fields (recommended):

- Identity:
  - `id TEXT PRIMARY KEY`
  - `account_id TEXT NOT NULL`
  - `project_id TEXT NULL`
- Security selectors (required):
  - `created_by TEXT NOT NULL`
    - Required by Roles v2 “own uncategorized items” (`40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md`).
- Category attribution selector (required):
  - `inherited_budget_category_id TEXT NULL`
    - Required field (may be null) (`40_features/project-items/feature_spec.md`).
- Core:
  - `name TEXT NULL`
  - `description TEXT NOT NULL`
  - `source TEXT NULL`
  - `sku TEXT NULL`
  - `notes TEXT NULL`
  - `bookmark INTEGER NOT NULL DEFAULT 0`
  - `payment_method TEXT NULL`
  - `disposition TEXT NULL`
- Relationships:
  - `transaction_id TEXT NULL`
    - Required for canonical attribution joins (`40_features/budget-and-accounting/feature_spec.md`).
  - `space_id TEXT NULL`
- Money (integer cents; tightened):
  - `purchase_price_cents INTEGER NULL`
  - `project_price_cents INTEGER NULL`
  - `market_value_cents INTEGER NULL`
    - Required for canonical transaction value computation (`40_features/budget-and-accounting/feature_spec.md`).
- Tax (optional but parity-aligned):
  - `tax_rate_pct REAL NULL`
  - `tax_amount_purchase_price_cents INTEGER NULL`
  - `tax_amount_project_price_cents INTEGER NULL`
- Inventory state:
  - `inventory_status TEXT NULL`
  - `business_inventory_location TEXT NULL`
- Lineage pointers (required):
  - `origin_transaction_id TEXT NULL`
  - `latest_transaction_id TEXT NULL`
    - Required by lineage pointer contract (`40_features/inventory-operations-and-lineage/flows/lineage_edges_and_pointers.md`).

Indexes (examples):

- `items(account_id, project_id, deleted_at_server, name)`
- `items(account_id, project_id, transaction_id)`
  - Required for canonical attribution joins (`40_features/budget-and-accounting/feature_spec.md`).
- `items(account_id, project_id, space_id)`
- `items(account_id, project_id, disposition)`
- `items(account_id, project_id, bookmark)`
- `items(account_id, project_id, inherited_budget_category_id)`
  - Required for canonical-transaction budget-category filtering (`40_features/project-transactions/feature_spec.md`) and Roles v2 (`40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md`).
- `items(account_id, project_id, created_by, inherited_budget_category_id)`
  - Supports “own uncategorized” checks and views (Roles v2).
- `items(account_id, project_id, updated_at_server, id)` (supports deterministic apply ordering)

Search:

- Prefer SQLite FTS if available (`items_fts`) or a dedicated `search_text` column + prefix index strategy.
- Because the product requirement allows **prefix search**, an FTS table is ideal but not strictly required if performance is acceptable.

### `transactions`

This table must match the canonical Transaction contract:

- See: `20_data/data_contracts.md` → **Entity: Transaction**

Key fields (recommended):

- Identity:
  - `id TEXT PRIMARY KEY`
  - `account_id TEXT NOT NULL`
  - `project_id TEXT NULL`
- Core:
  - `transaction_date TEXT NOT NULL`
  - `amount_cents INTEGER NOT NULL`
    - Money tightened per contracts (also required for rollups: `40_features/budget-and-accounting/feature_spec.md`).
  - `source TEXT NULL`
  - `transaction_type TEXT NULL`
  - `payment_method TEXT NULL`
  - `notes TEXT NULL`
- Category selector (required for non-canonical):
  - `budget_category_id TEXT NULL`
    - Non-canonical attribution selector (`40_features/project-transactions/feature_spec.md` / `40_features/budget-and-accounting/feature_spec.md`).
- Workflow:
  - `status TEXT NULL` (`pending`/`completed`/`canceled`)
  - `reimbursement_type TEXT NULL`
  - `trigger_event TEXT NULL`
  - `receipt_emailed INTEGER NOT NULL DEFAULT 0`
- Canonical inventory selectors (Roles v2 + offline filtering):
  - `is_canonical_inventory INTEGER NOT NULL DEFAULT 0`
    - Canonical `INV_*` semantics are required (`40_features/project-transactions/feature_spec.md`).
  - `canonical_kind TEXT NULL` (`INV_PURCHASE`/`INV_SALE`/`INV_TRANSFER`)
  - `attributed_category_ids_json TEXT NULL` (JSON map `{ [categoryId]: true }`)
  - `attributed_uncategorized_creator_uids_json TEXT NULL` (JSON map `{ [uid]: true }`)
    - Required for server-enforceable visibility without “download everything then filter” (`40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md`).
- Denormalized helpers (optional):
  - `needs_review INTEGER NOT NULL DEFAULT 0`
  - `tax_rate_preset_id TEXT NULL`
  - `tax_rate_pct REAL NULL`
  - `subtotal_cents INTEGER NULL`
  - `sum_item_purchase_prices_cents INTEGER NULL`
  - `item_ids_json TEXT NULL` (JSON array; non-authoritative cache)

Indexes:

- `transactions(account_id, project_id, deleted_at_server, transaction_date)`
- `transactions(account_id, project_id, updated_at_server, id)`
- `transactions(account_id, project_id, budget_category_id, transaction_date)`
  - Supports category filters for non-canonical (`40_features/project-transactions/feature_spec.md`).
- `transactions(account_id, project_id, is_canonical_inventory, transaction_date)`
  - Useful for list partitioning and debugging.

Notes:
- Canonical `INV_*` category filters must be item-driven, not `budget_category_id`-driven. The local DB must support joining via `items(transaction_id)` + `items.inherited_budget_category_id` (`40_features/project-transactions/feature_spec.md`).

### `spaces`

Key fields (example):

- `id`, `account_id`, `project_id`
- `name`, `type`, `notes`

Indexes:

- `spaces(project_id, deleted_at_server, name)`
- `spaces(project_id, updated_at_server, id)`

### `attachments`

Represents local and remote attachment metadata.

This table must match the canonical Attachment contract:

- See: `20_data/data_contracts.md` → **Entity: Attachment**

Key fields (recommended):

- `id`, `account_id`, `project_id`
- Parent association:
  - `parent_type TEXT NOT NULL`
  - `parent_id TEXT NOT NULL`
  - `kind TEXT NULL` (`receipt`, `image`, `pdf`, `other`)
    - Required because transactions distinguish receipts vs other attachments (`40_features/project-transactions/feature_spec.md`).
- Remote identity (nullable until uploaded):
  - `storage_path TEXT NULL`
  - `mime_type TEXT NULL`
  - `byte_size INTEGER NULL`
  - `sha256 TEXT NULL`
  - `filename TEXT NULL`
  - `width INTEGER NULL`
  - `height INTEGER NULL`
  - `duration_ms INTEGER NULL`
  - `uploaded_by TEXT NULL`
  - `uploaded_at_server INTEGER NULL`
- Offline lifecycle (required UI state machine):
  - `local_uri TEXT NULL`
  - `local_media_id TEXT NULL`
  - `upload_state TEXT NOT NULL` (`local_only`, `uploading`, `uploaded`, `failed`)
  - `upload_error TEXT NULL`
    - Required by offline media lifecycle (`40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`).
- sync + local fields

Indexes:

- `attachments(account_id, project_id, parent_type, parent_id)`
- `attachments(account_id, project_id, upload_state)`
- `attachments(account_id, project_id, updated_at_server, id)`

---

### `lineage_edges`

This table must match the canonical LineageEdge contract:

- See: `20_data/data_contracts.md` → **Entity: LineageEdge**

Required because lineage history must be available offline (`40_features/inventory-operations-and-lineage/flows/lineage_edges_and_pointers.md`).

Columns (recommended):

- `id TEXT PRIMARY KEY`
- `account_id TEXT NOT NULL`
- `item_id TEXT NOT NULL`
- `from_transaction_id TEXT NULL`
- `to_transaction_id TEXT NULL`
- `note TEXT NULL`
- `created_by TEXT NOT NULL`
- `created_at_server INTEGER NOT NULL`
- common sync + local fields (including `updated_at_server`, `deleted_at_server`, `version`, `updated_by`, `last_mutation_id`, `schema_version`, `local_pending`, `local_updated_at`)

Indexes:

- `lineage_edges(account_id, item_id, created_at_server)`
- `lineage_edges(account_id, from_transaction_id)`
- `lineage_edges(account_id, to_transaction_id)`

---

## System tables (sync engine)

### `outbox_ops`

Durable queue of remote mutations generated by local writes.

Columns (example):

- `op_id TEXT PRIMARY KEY`
- `account_id TEXT NOT NULL`
- `scope_type TEXT NOT NULL` (`project` or `inventory`)
- `scope_id TEXT NULL` (`projectId` when `scope_type=project`, else NULL)
- `entity_type TEXT NOT NULL` (items/transactions/spaces/projects/attachments/...)
- `entity_id TEXT NOT NULL`
- `op_type TEXT NOT NULL` (create/update/delete/callable/...)
- `payload_json TEXT NOT NULL`
- `created_at_local INTEGER NOT NULL`
- `state TEXT NOT NULL` (`pending`, `in_flight`, `succeeded`, `failed`, `blocked`)
- `attempt_count INTEGER NOT NULL DEFAULT 0`
- `last_error TEXT NULL`
- `last_attempt_at INTEGER NULL`

Indexes:

- `outbox_ops(state, created_at_local)`
- `outbox_ops(scope_type, scope_id, state, created_at_local)`

### `sync_state`

Delta cursor state per collection per active scope (project or inventory).

Columns:

- `account_id TEXT NOT NULL`
- `scope_type TEXT NOT NULL` (`project` or `inventory`)
- `scope_id TEXT NULL` (`projectId` when `scope_type=project`, else NULL)
- `collection TEXT NOT NULL` (items/transactions/spaces/attachments/projects)
- `cursor_updated_at_server INTEGER NOT NULL DEFAULT 0`
- `cursor_doc_id TEXT NOT NULL DEFAULT ''`
- `last_seen_seq INTEGER NOT NULL DEFAULT 0`
- `updated_at_local INTEGER NOT NULL`

Primary key:

- `(account_id, scope_type, scope_id, collection)`

### `conflicts`

Persisted conflicts to resolve later.

Columns (example):

- `conflict_id TEXT PRIMARY KEY`
- `account_id TEXT NOT NULL`
- `scope_type TEXT NOT NULL` (`project` or `inventory`)
- `scope_id TEXT NULL` (`projectId` when `scope_type=project`, else NULL)
- `entity_type TEXT NOT NULL`
- `entity_id TEXT NOT NULL`
- `field TEXT NOT NULL`
- `local_json TEXT NOT NULL`
- `server_json TEXT NOT NULL`
- `created_at_local INTEGER NOT NULL`
- `resolved_at_local INTEGER NULL`
- `resolution TEXT NULL` (`use_local`, `use_server`, `merged`)

Indexes:

- `conflicts(scope_type, scope_id, resolved_at_local)`

---

## Apply-from-remote (idempotent upsert rules)

When applying deltas from Firestore:

- Upsert by `id`.
- If `deletedAt != null`, delete the local row (or mark as deleted locally).
- Set the server fields (`updated_at_server`, `deleted_at_server`, `version`, `last_mutation_id`, etc.).
- Clear `local_pending` only when it is safe to do so (e.g., lastMutationId matches a completed outbox op).

All applies should be done inside SQLite transactions and batched per delta page.

---

## Local migrations strategy (practical)

- Additive changes are preferred (add columns/tables; backfill lazily).
- When changing constraints/indexes, do it in a migration step keyed by `user_version`.
- Keep schema evolution simple; features should not invent per-feature DB schemas without updating this doc.

