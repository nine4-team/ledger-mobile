# Data (`20_data/`)

Data model + schema docs that features should reference instead of reinventing.

Put docs here like:
- `firebase_data_model.md`
- `local_sqlite_schema.md`
- `data_contracts.md` (canonical entity contracts; other docs should reference this)

## Architecture baseline (must align)

This folder is aligned to the current offline architecture baseline:

- **Firestore native offline persistence** (cache + queued writes) with **scoped listeners**
- **No bespoke sync engine**: no outbox/delta cursors/“SQLite as source of truth” baseline
- **SQLite allowed only as a derived, rebuildable search index** (non-authoritative)
- **Multi-doc correctness** defaults to **request-doc workflows** (client writes request doc; Cloud Function applies atomically + status)

Primary reference: `OFFLINE_FIRST_V2_SPEC.md`.

## Naming conventions (canonical)

These conventions keep the Firebase plan aligned with the **current app** (`src/types`) and avoid drift.

### Firestore documents (remote)

- **Field casing**: `camelCase`
- **IDs**: use document id as canonical `id`; also store foreign keys as `accountId`, `projectId`, etc. (camelCase)
- **Timestamps**: `createdAt`, `updatedAt`, `deletedAt` (Firestore `Timestamp`)
- **Lifecycle/audit fields (remote, recommended on mutable entities)**:
  - `createdAt`, `updatedAt`, `deletedAt`, `createdBy?`, `updatedBy?`, `schemaVersion?`
- **Enums/roles**: match app enums (e.g. account membership role is `"admin" | "user"`, system owner is `"owner"`)

### SQLite tables (local)

- **Column casing**: `snake_case`
- **Use**: SQLite must remain **non-authoritative**. It is used only as a **derived, rebuildable search index** (not a sync engine).
- **Naming**: use `snake_case` for columns, and keep source ids explicit (`account_id`, `project_id`, `item_id`, `transaction_id`).

