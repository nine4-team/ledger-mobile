# Firebase Data Model (Firestore + Storage Metadata)

This doc defines the canonical Firestore data model and the fields required to support:

- local-first + explicit outbox
- delta sync (by `updatedAt` cursor)
- tombstones for deletes
- idempotency (optional; only if you implement end-to-end operation ids)
- a tiny per-project change-signal listener (`meta/sync`)

Canonical sync constraints live here (link rather than duplicate):

- [`sync_engine_spec.plan.md`](../sync_engine_spec.plan.md)

---

## Validation / sources of truth

This document mixes:

- **Confirmed fields** (grounded in the current codebase + DB schema)
- **Proposed fields** (reasonable for Firestore/offline-first, but must be validated against product behavior)

Primary sources used to validate entity shapes:

- `src/types/index.ts` (domain types used by UI/services)
- `supabase/migrations/*` (current DB schema + recent migrations)

Canonical contract note:
- `20_data/data_contracts.md` is the **single source of truth** for entity field lists and persistence conventions.
  This document should link to contracts rather than redefining shapes in multiple places.

---

## v1 parity checklist (against current app)

Use this as a “don’t break the app” gate. If any **Unchecked** item is required for a screen/flow you care about, the
Firestore model (and sync engine) is not yet v1-parity.

### Entity parity (schemas + paths)

- [ ] **Projects**: `Project` fields present (`name`, `description`, `clientName`, `budget`, `designFee`, `budgetCategories`, `defaultCategoryId`, `mainImageUrl`, optional `settings/metadata`, optional counts)
  - **Canonical source**: `src/types/index.ts` `Project`; migrations `001_initial_schema.sql`, `019_add_project_default_category_id.sql`, `020_add_project_main_image_url.sql`
  - **Firestore path**: `accounts/{accountId}/projects/{projectId}`
- [ ] **Budget categories (account presets)**: `BudgetCategory` fields present (`name`, `slug`, `isArchived`, `metadata`)
  - **Canonical source**: `src/types/index.ts` `BudgetCategory`; migrations `017_create_budget_categories.sql`, `20250101_add_version_and_updated_by_for_offline.sql`
  - **Firestore path**: `accounts/{accountId}/presets/budgetCategories/{budgetCategoryId}`
- [ ] **Account presets**: default category + ordering/preset bundles represented (either embedded on account or a dedicated meta doc)
  - **Canonical source**: migration `20250104_00_create_account_presets.sql`
  - **Firestore path (proposed)**: `accounts/{accountId}/meta/accountPresets`
- [ ] **Spaces**: templates + checklists + images + archive state modeled
  - **Canonical source**: `src/types/index.ts` `Space`/`SpaceTemplate`; migrations `20260124_create_spaces_and_item_space_id.sql`, `20260124_create_space_templates_and_space_template_id.sql`, `20260124_add_space_checklists.sql`
  - **Firestore paths**:
    - `accounts/{accountId}/projects/{projectId}/spaces/{spaceId}`
    - `accounts/{accountId}/inventory/spaces/{spaceId}`
    - `accounts/{accountId}/inventory/spaceTemplates/{templateId}` (or per-project if intentionally redesigned)
- [ ] **Items**: pricing + tax + images + lineage fields modeled
  - **Canonical source**: `src/types/index.ts` `Item`; migrations `001_initial_schema.sql`, `20251110_add_item_tax_amounts.sql`, `20251230_remove_legacy_tax_amount.sql`, plus lineage-related migrations if/when mirrored
  - **Firestore paths**:
    - `accounts/{accountId}/projects/{projectId}/items/{itemId}`
    - `accounts/{accountId}/inventory/items/{itemId}`
- [ ] **Transactions**: lifecycle + receipts + tax preset/subtotal + completeness fields modeled
  - **Canonical source**: `src/types/index.ts` `Transaction`; migrations `001_initial_schema.sql`, `018_add_transaction_category_id.sql`, `20251110_add_needs_review_flag.sql`, `20251110_add_sum_item_purchase_prices.sql`, `20260107_sync_canonical_transaction_amounts.sql`
  - **Firestore paths**:
    - `accounts/{accountId}/projects/{projectId}/transactions/{transactionId}`
    - `accounts/{accountId}/inventory/transactions/{transactionId}`

### Behavior parity (these are easy places to get “naively wrong”)

- [ ] **Money types**: money is persisted as **integer cents** per `20_data/data_contracts.md` (no floats; no stringly money in persisted rows).
- [ ] **Transaction ↔ item linkage**: `transactionId` on items and `itemIds` on transactions behavior is preserved, or an explicit redesign is documented and implemented.
- [ ] **Images**: embedded `ItemImage[]` / `TransactionImage[]` behavior (including offline placeholder metadata) is preserved **unless** you intentionally redesign to attachment docs.
- [ ] **Spaces UX**: checklist completion state and representative images behave the same offline/online.
- [ ] **Conflict fields**: `version`/`updatedBy` semantics match the offline conflict detection + authorization approach (don’t assume global monotonicity).

### Optional optimizations (must not be correctness-critical)

- [ ] **`meta/sync` change-signal** implemented as a latency optimization only (delta-by-`updatedAt` remains the correctness path).
- [ ] **Idempotency keys** (e.g. `lastMutationId`) only added if implemented end-to-end (writes, rules, merge behavior).

---

## Document conventions (apply to every entity)

### Scope note: “canonical” vs “proposed redesign”

This doc previously mixed “canonical (must match current app)” and “proposed redesign (nice in Firestore)”
in a way that can silently introduce breaking changes.

From here on:

- **Canonical** means: aligns with `src/types/index.ts` + the Supabase migrations that created/modified the entity.
- **Proposed** means: optional redesign for Firestore, explicitly called out as such, and never required for v1 parity.

### Required fields (scoped mutable entity docs)

Not every Firestore document needs the same sync/audit fields.

Only **scoped mutable entities** (e.g. project/inventory items, transactions, spaces, budget categories, templates)
need the offline/conflict metadata below.

Every **scoped mutable entity document** MUST include:

- `accountId: string`
- `projectId: string | null` (nullable; `null` means **Business Inventory** scope)
- `updatedAt: Timestamp` (server timestamp)
- `deletedAt: Timestamp | null` (tombstone)
- `version: number` (integer used for conflict detection; do **not** assume global monotonicity across devices)
- `updatedBy?: string | null` (uid; required only if rules depend on it for offline-queued writes)
- `schemaVersion?: number` (recommended)

Notes:

- `lastMutationId` is **not canonical in the current app**. Treat it as *Proposed* unless you’ve already implemented
  an outbox idempotency key end-to-end (writes + rules + merge behavior).
- Top-level docs like `accounts/{accountId}`, membership docs, and invites do **not** necessarily carry `projectId`
  or conflict fields; keep those schemas minimal and purpose-built.

### Timestamps

- `updatedAt` is always written with a server timestamp (or `request.time` in rules for direct client writes).
- When a doc is deleted, write **both** `deletedAt` and `updatedAt`.

### Deletes (tombstones)

We do **not** immediately hard-delete entity docs. Instead:

- set `deletedAt = serverTimestamp()`
- set `updatedAt = serverTimestamp()`
- increment `version`
- optional (Proposed): set an idempotency key field (e.g. `lastMutationId`) if you implement end-to-end operation ids

Clients treat any doc with `deletedAt != null` as deleted.

Optional later cleanup:

- scheduled deletion of tombstones older than N days (30–90), once all clients can tolerate it.

### ID strategy

- IDs are generated client-side (UUID/ULID) so offline-created entities can be referenced immediately.
- ID is stable across devices (the Firestore doc id is the canonical id mirrored into SQLite).

---

## Top-level tenancy + membership

### Accounts

`accounts/{accountId}`

Suggested fields:

- `createdAt`, `createdBy`
- `name`
- `plan` (optional)

### Memberships

`accounts/{accountId}/members/{uid}`

Suggested fields:

- `role: "admin" | "user"` (account-level role; system-level `"owner"` is separate)
- `joinedAt`, `joinedBy`
- Optional (only if you need offboarding without deleting the doc):
  - `disabledAt?: Timestamp | null`
  - `disabledBy?: string | null`

### Invites

`accounts/{accountId}/invites/{inviteId}`

Suggested fields:

- `email` (or `emailHash`)
- `role: "admin" | "user"`
- `status: "pending" | "accepted" | "expired"`
- `tokenHash` (never store raw tokens; use for `/invite/{token}` lookup)
- `expiresAt`
- `acceptedAt: Timestamp | null`
- `invitedBy` (uid)
- `createdAt`

Invite acceptance should be handled by a callable Function (see security model).

---

## Collaboration scopes (Projects + Business Inventory)

Your product has two collaboration scopes:

- **Project scope**: `projectId = "<projectId>"`
- **Business inventory scope**: `projectId = null`

The architecture supports both scopes with the same primitives:

- SQLite local-first writes + explicit outbox
- delta sync by `updatedAt` cursor
- **one tiny change-signal listener per active scope**

---

## Projects

`accounts/{accountId}/projects/{projectId}`

Suggested fields (aligned to current app + DB; see `src/types/index.ts` `Project`):

- `accountId`
- `name`
- `description`
- `clientName`
- Spaces (hierarchy-aligned):
  - Projects **own** spaces as a subcollection: `accounts/{accountId}/projects/{projectId}/spaces/{spaceId}`
  - Business Inventory owns account-wide spaces as a subcollection: `accounts/{accountId}/inventory/spaces/{spaceId}`
  - “Separate docs” here means: do **not** embed a `spaces: Space[]` array inside the project doc. Use one document per space in the appropriate subcollection.
- `budget?: number` (optional legacy “overall budget”; used for high-level budget progress)
  - **Money representation**: persist as **integer cents** (see `20_data/data_contracts.md`).
- `designFee?: number` (optional; treated as a special budget bucket in UI)
  - **Money representation**: persist as **integer cents** (see `20_data/data_contracts.md`).
- Design Fee semantics (planned revision; keep this invariant in the Firebase model):
  - Design Fee progress is “received”, not “spent”.
  - Design Fee is excluded from “spent totals” and category budget sums.
  - If you ever represent “design fee specialness” in category/preset metadata, bind it to a stable identifier (slug/metadata), not a mutable display name.
- `budgetCategories?: { [budgetCategoryId: string]: number }` (sparse map of **account-defined** budget category ids → budget amount)
  - **Revised for Firestore**: do **not** embed category budgets as a map on the project doc.
  - Store per-project per-category allocations as one doc per preset category id:
    - `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`
  - Canonical contract: `20_data/data_contracts.md` → **Entity: ProjectBudgetCategory**.
- `defaultCategoryId?: string | null`
  - Note: current app treats the default budget category as **account-wide** (preset), but project rows still carry this field for compatibility/history.
- `mainImageUrl?: string | null` (project cover image URL; stored directly on the project in the current app)
- Optional linking (if using attachment docs for offline + delta visibility):
  - `mainImageAttachmentId?: string | null` (points at an `attachments/{attachmentId}` doc whose `parentType="project"`)
- Optional: `settings?: { locations?: string[]; ... }` (legacy; locations are now modeled by `spaces` + `items.spaceId`)
- Optional (present in current app types; may be derived/denormalized):
  - `metadata?: Record<string, any> | null`
  - `itemCount?: number`
  - `transactionCount?: number`
  - `totalValue?: number`

Sync fields (required):

- `updatedAt`, `deletedAt`, `version`, `updatedBy`, `schemaVersion`

Rationale (why subcollection docs vs embedding):

- Firestore doc size limits + contention: embedding large/mutable arrays (items/spaces/transactions) causes frequent write conflicts and can hit doc size limits.
- Offline/outbox + delta sync: one-doc-per-entity keeps conflict detection and incremental sync predictable and cheap.
- Query patterns: listing spaces/items/transactions naturally maps to querying the subcollection, and the local SQLite layer can still power complex UI views.

### Change signal doc (one tiny listener per active project)

`accounts/{accountId}/projects/{projectId}/meta/sync`

Fields:

- `seq: number` (monotonic)
- `changedAt: Timestamp`
- `byCollection: { [collectionName: string]: number }` (monotonic per key)

Write pattern:

- For any mutation applied to Firestore, increment:
  - `seq`
  - `byCollection.<collectionName>`
  - set `changedAt = serverTimestamp()`

Clients listen to this doc while foregrounded and run targeted delta fetch for any collections whose sequence advanced.

Important:

- Treat `meta/sync` as a **latency optimization**, not a correctness requirement.
- Correctness must come from delta sync by `updatedAt` (or other canonical cursor), because missed/failed increments
  can otherwise create “silent desync” where clients stop fetching changes.

### Change signal doc for Business Inventory (projectId = null)

When the user is actively using Business Inventory, the app attaches a single listener to an account-level inventory signal doc:

`accounts/{accountId}/inventory/meta/sync`

Fields (same shape as project `meta/sync`):

- `seq: number` (monotonic)
- `changedAt: Timestamp`
- `byCollection: { [collectionName: string]: number }` (monotonic per key)

Write pattern:

- any mutation applied to Firestore that affects **inventory-scope docs** increments this signal doc.

---

## Entities (scoped subcollections; cost-control guardrail)

To preserve the original cost-control intent and make “wide queries” harder to accidentally ship, entities live in **scoped subcollections**:

### Project scope

`accounts/{accountId}/projects/{projectId}/...`

- `items/{itemId}`
- `transactions/{transactionId}`
- `spaces/{spaceId}`
- `attachments/{attachmentId}` (scope-root attachment docs; see `20_data/data_contracts.md` → **Entity: Attachment**)

### Business Inventory scope

`accounts/{accountId}/inventory/...`

- `items/{itemId}`
- `transactions/{transactionId}`
- `spaces/{spaceId}`
- `attachments/{attachmentId}` (scope-root attachment docs; see `20_data/data_contracts.md` → **Entity: Attachment**)

Sharing code does **not** require unified Firestore collections. We keep shared UI/services by passing a `scope` (projectId or inventory) and mapping it to the correct collection root.

Note: keeping `projectId: string | null` on docs is still acceptable for unified TypeScript/domain modeling; for inventory docs it should be `null` (matching the existing app model).

---

## Budget categories (account presets)

In the current app, **budget categories are account-level presets** that users manage in Settings. Projects then reference those presets by id (and optionally allocate a per-project budget per category).

Store the canonical category definitions under a dedicated **presets** collection (account-level metadata).

Ordering/default behavior today is implemented via an **account presets** concept (see Supabase `account_presets`),
so avoid inventing a new required Firestore meta doc unless you intentionally redesign presets.

### Budget category docs

Presets: `accounts/{accountId}/presets/budgetCategories/{budgetCategoryId}`

Suggested fields:

- `accountId`
- `projectId: null`
- `name`
- `slug` (unique per account; stable identifier for imports/migrations)
- `isArchived: boolean`
- `metadata?: { itemizationEnabled?: boolean; isDefault?: boolean; [k: string]: any } | null` (keep flexible; the current app already uses metadata for category behavior)

Sync fields (required):

- `updatedAt`, `deletedAt`, `version`, `updatedBy`, `schemaVersion`

### Account presets (canonical concept; optional Firestore representation)

Canonical: there is an “account presets” concept in the current system which includes the default category id and
other preset bundles.

Proposed Firestore doc (if you want a first-class document instead of embedding in `accounts/{accountId}`):

`accounts/{accountId}/meta/accountPresets`

Suggested fields:

- `accountId`
- `defaultCategoryId: string | null`
- `presets: { budgetCategories?: { order?: string[] }; taxPresets?: any; vendorDefaults?: any; [k: string]: any }`
- `updatedAt`, `schemaVersion`

### Items

Project: `accounts/{accountId}/projects/{projectId}/items/{itemId}`

Inventory: `accounts/{accountId}/inventory/items/{itemId}`

Canonical contract:
- See `20_data/data_contracts.md` → **Entity: Item**

Firestore-only notes:
- Keep Firestore docs small and conflict-friendly: relationships are modeled via foreign keys on the item (`transactionId`, `spaceId`) rather than maintaining large arrays on transactions/spaces (see `sync_engine_spec.plan.md` cost notes).
- The key selector fields that must remain queryable (for sync + Roles v2 + budgeting) are on the item doc:
  - `projectId`, `updatedAt`, `deletedAt`
  - `inheritedBudgetCategoryId` (required by item-driven canonical attribution)
  - `createdBy` (required for Roles v2 “own uncategorized items”)
- Lineage pointers live on the item doc (for cheap UI access); full history lives in `accounts/{accountId}/lineageEdges` (see “Lineage edges” below).

### Transactions

Project: `accounts/{accountId}/projects/{projectId}/transactions/{transactionId}`

Inventory: `accounts/{accountId}/inventory/transactions/{transactionId}`

Canonical contract:
- See `20_data/data_contracts.md` → **Entity: Transaction**

Firestore-only notes:
- Canonical `INV_*` semantics are **behavioral truth** and must remain enforceable:
  - Non-canonical attribution uses `transaction.budgetCategoryId`.
  - Canonical `INV_*` attribution uses linked items’ `item.inheritedBudgetCategoryId` (transaction category is non-authoritative).
- Roles v2 requires canonical `INV_*` transaction visibility to be enforceable server-side without “download everything then filter”.
  - The contract includes server-maintained selector fields for canonical transactions (`attributedCategoryIds`, `attributedUncategorizedCreatorUids`) specifically to support Rules/delta sync.

### Spaces

Project: `accounts/{accountId}/projects/{projectId}/spaces/{spaceId}`

Inventory: `accounts/{accountId}/inventory/spaces/{spaceId}`

Canonical fields (must support current app behavior; see `src/types/index.ts` `Space`):

- `accountId`, `projectId` (`null` = account-wide/business inventory, string = project-specific)
- `templateId?: string | null` (optional provenance: created from a template)
- `name: string`
- `notes?: string | null`
- `images?: ItemImage[]` (space gallery; reuses `ItemImage` shape)
- `checklists?: SpaceChecklist[]` (multiple named checklists with per-item completion state)
- `isArchived: boolean`
- `metadata?: Record<string, any> | null`
- Sync/conflict fields:
  - `createdAt`, `updatedAt`, `createdBy?`, `updatedBy?`, `version`

Avoid storing large arrays of item ids; prefer querying items by `spaceId`.

### Space templates (canonical; not optional)

Space templates exist in the current system to create spaces from account-scoped defaults.

Project: `accounts/{accountId}/projects/{projectId}/meta/spaceTemplates/{templateId}` (if you decide templates are per-project)
Inventory/account: `accounts/{accountId}/inventory/spaceTemplates/{templateId}` (if templates are account-scoped like today)

Canonical fields (see `src/types/index.ts` `SpaceTemplate`):

- `accountId`
- `name`
- `notes?: string | null`
- `checklists?: SpaceChecklist[]`
- `isArchived: boolean`
- `sortOrder?: number | null`
- `metadata?: Record<string, any> | null`
- `createdAt`, `updatedAt`, `createdBy?`, `updatedBy?`, `version`

### Attachments (metadata)

Canonical contract:
- See `20_data/data_contracts.md` → **Entity: Attachment**

Firestore-only notes:
- Attachments are modeled as **scope-root docs** so delta sync can be a simple scoped collection query (no collection-group dependency):
  - Project: `accounts/{accountId}/projects/{projectId}/attachments/{attachmentId}`
  - Inventory: `accounts/{accountId}/inventory/attachments/{attachmentId}`
- `local_only` is a **local SQLite-only** state; remote docs typically appear once upload begins/finishes.
- Parent entities should link/resolve attachments via `(parentType, parentId)` (and local SQLite joins), rather than embedding large attachment arrays on the parent doc.

### Lineage edges (metadata)

Canonical contract:
- See `20_data/data_contracts.md` → **Entity: LineageEdge**

Firestore-only notes:
- Stored in an account-wide collection to preserve history across item scope moves:
  - `accounts/{accountId}/lineageEdges/{edgeId}`

---

## Delta sync query strategy (indexes)

### Cursor

For each collection, clients store a cursor:

- `cursorUpdatedAt`
- `cursorDocId`

### Query shape (per collection)

When doing incremental delta:

- `where("updatedAt", ">", cursorUpdatedAt)` OR stable composite cursor logic
- `orderBy("updatedAt")`
- `orderBy("__name__")`
- `limit(pageSize)`

Why:

- multiple docs can share the same `updatedAt`
- `(updatedAt, docId)` provides stable paging without missing or duplicating docs

### Composite indexes

Most collections will require composite indexes to support:

- `accountId + projectId + updatedAt` ordering
- plus any “list” filters (e.g., disposition/status) as needed

Rule of thumb:

- keep Firestore queries in the sync engine **uniform and predictable**
- keep feature list views powered by SQLite queries instead of complex Firestore queries

---

## Storage paths (naming convention)

Store files in Firebase Storage under tenant/project boundaries:

Project scope:

`attachments/{accountId}/projects/{projectId}/{attachmentId}/{filename}`

Inventory scope:

`attachments/{accountId}/inventory/{attachmentId}/{filename}`

Rationale:

- easy to apply Storage rules by path
- easy to enumerate/delete per project if needed

