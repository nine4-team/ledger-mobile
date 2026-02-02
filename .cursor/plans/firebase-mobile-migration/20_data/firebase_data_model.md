# Firebase Data Model (Firestore canonical)

This doc describes the **Firestore collection layout** and cross-cutting modeling rules for the mobile Firebase migration.

## Sources of truth

- **Offline architecture baseline**: `OFFLINE_FIRST_V2_SPEC.md`
  - Firestore native offline persistence (cache + queued writes) with scoped listeners
  - No bespoke sync engine (no outbox/delta cursors/`meta/sync` correctness primitives)
  - SQLite allowed only as a derived, rebuildable search index (non-authoritative)
- **Canonical entity field contracts**: `20_data/data_contracts.md`
- **Authoritative product specs**: `40_features/**` (feature specs win if there’s a conflict; mark gaps/contradictions as TBD in `data_contracts.md`)

---

## Tenancy + scoping (canonical)

Everything is scoped under an `accountId`.

Two collaboration scopes exist for mutable entities:

- **Project scope**: `accounts/{accountId}/projects/{projectId}/...`
- **Business inventory scope**: `accounts/{accountId}/inventory/...` (and `projectId = null` in entity fields)

---

## Canonical collection layout (by entity)

This doc intentionally focuses on **paths**. Field lists live in `20_data/data_contracts.md`.

### Account + membership

- Account: `accounts/{accountId}`
- Members: `accounts/{accountId}/members/{uid}`
- Invites: `accounts/{accountId}/invites/{inviteId}`

Account-scoped requests (gated creates / account workflows):
- Requests: `accounts/{accountId}/requests/{requestId}`

Billing (server-owned enforcement + counters):
- Entitlements: `accounts/{accountId}/billing/entitlements/current`
- Usage: `accounts/{accountId}/billing/usage`

Per-user preferences (within an account):
- Project preferences (pinned budget categories): `accounts/{accountId}/users/{userId}/projectPreferences/{projectId}`

Account business profile (branding inputs):
- Business profile: `accounts/{accountId}/businessProfile/current`

### Presets (account-wide)

- Budget category presets: `accounts/{accountId}/presets/budgetCategories/{budgetCategoryId}`
- Space templates: `accounts/{accountId}/presets/spaceTemplates/{templateId}`
- Vendor defaults: `accounts/{accountId}/presets/vendorDefaults/current`
- (Optional / TBD) Account presets meta doc: `accounts/{accountId}/meta/accountPresets`
  - TBD: confirm whether this doc is required as a first-class Firestore document vs embedded fields elsewhere.

### Project scope

- Project: `accounts/{accountId}/projects/{projectId}`
- Project budget allocations (per preset category): `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`
- Items: `accounts/{accountId}/projects/{projectId}/items/{itemId}`
- Transactions: `accounts/{accountId}/projects/{projectId}/transactions/{transactionId}`
- Spaces: `accounts/{accountId}/projects/{projectId}/spaces/{spaceId}`

### Business inventory scope

- Items: `accounts/{accountId}/inventory/items/{itemId}`
- Transactions: `accounts/{accountId}/inventory/transactions/{transactionId}`
- Spaces: `accounts/{accountId}/inventory/spaces/{spaceId}`

### Cross-scope lineage

Lineage edges must survive scope moves (project ↔ inventory). Store edges in an account-wide collection:

- `accounts/{accountId}/lineageEdges/{edgeId}`

---

## Multi-doc correctness (request-doc workflows)

Default approach for multi-entity operations:

- Client writes a **request doc** (single-document write, offline-safe)
- A Cloud Function validates + applies changes atomically (Firestore transaction/batch)
- Function updates request status (`pending` → `applied` / `failed` / `denied`) with structured error info

TBD / needs confirmation:
- Per operation (allocate/sell/deallocate/transfer/etc.), the exact request-doc shape and status fields should be derived from the specific feature flow specs in `40_features/`.

---

## Embedded media (no “Attachment docs” baseline)

Feature specs reference embedded media fields like:

- `transaction.receiptImages[]` / `transaction.otherImages[]`
- `space.images[]`

Each entry uses the canonical `AttachmentRef` contract defined in:

- `20_data/data_contracts.md` → “Embedded media references (URLs + `offline://` placeholders)”

At minimum:

- `url` may be:

- a remote URL, or
- an `offline://<mediaId>` placeholder that must render via the local media cache

and:

- `kind` must be explicit (`"image" | "pdf"`) so PDF-vs-image is not inferred from URLs.

Important rule (GAP B resolution):
- Do not store transient upload state on Firestore domain entities. Upload state is local + derived; Firestore stores stable attachment refs only.

---

## SQLite usage (search index only)

SQLite must be **non-authoritative** and **rebuildable**.

Because search is a mandatory UX feature (Items/Transactions lists), the **presence of a local search index** should be treated as **required** even though its implementation details can evolve.

- Use it only as a derived search index (e.g., FTS) for multi-field search on Items/Transactions.
- Rebuild strategy should be “clear index → reindex from current Firestore snapshots”.

See: `20_data/local_sqlite_schema.md`.

