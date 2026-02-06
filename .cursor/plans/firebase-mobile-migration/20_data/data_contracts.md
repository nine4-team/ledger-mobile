# Data contracts (canonical entity shapes)

This document consolidates the **domain entity contracts** for the Firebase mobile migration.

If there is a disagreement between:

- a feature spec under `40_features/**`
- `firebase_data_model.md` (Firestore)
- `local_sqlite_schema.md` (SQLite)

…**feature specs win** for product intent. This document should be updated to match feature specs where explicit, and should mark gaps/contradictions as **TBD**.

Other docs under `20_data/` should **reference** these contracts rather than restating fields.

---

## Firestore data tree (paths + doc shapes)

This is a **single, skim-friendly map** of:

- **Where data lives** in Firestore (paths)
- **What each document looks like** (field shapes)

### Path tree (at a glance)

```text
accounts/{accountId}
  projects/{projectId}
    budgetCategories/{budgetCategoryId}           (ProjectBudgetCategory)

  items/{itemId}                                  (Item)
  spaces/{spaceId}                                (Space)
  transactions/{transactionId}                    (Transaction)
  requests/{requestId}                            (RequestDoc)
  lineageEdges/{edgeId}                           (LineageEdge)

  users/{uid}                                     (AccountUser / Member)
    projectPreferences/{projectId}                (ProjectPreferences)

  invites/{inviteId}                              (Invite)

  profile/default                                 (Profile)
  billing/entitlements                             (BillingEntitlements)
  billing/usage                                    (BillingUsage)

  presets/default
    budgetCategories/{budgetCategoryId}           (BudgetCategory)
    spaceTemplates/{templateId}                   (SpaceTemplate)
    vendors/{vendorId}                            (VendorDefaults; use vendorId = "default")
```

### Shared shapes used below

```ts
type Timestamp = any; // Firestore Timestamp

type AttachmentKind = "image" | "pdf";

type AttachmentRef = {
  url: string; // remote URL or "offline://<mediaId>"
  kind: AttachmentKind;
  contentType?: string;
  isPrimary?: boolean;
};

// Contract note:
// - For scoped mutable entity docs (items/transactions/spaces/lineage edges, etc.),
//   include these lifecycle/audit fields (see "Lifecycle + audit fields" below).
type LifecycleAuditFields = {
  createdAt: Timestamp;
  updatedAt: Timestamp;
  deletedAt: Timestamp | null;
  createdBy?: string | null;
  updatedBy?: string | null;
  schemaVersion?: number;
};

type SpaceChecklistItem = {
  id: string;
  text: string;
  isChecked: boolean;
};

type SpaceChecklist = {
  id: string;
  name: string;
  items: SpaceChecklistItem[];
};
```

### Doc shapes by path

#### `accounts/{accountId}/projects/{projectId}` (Project)

```ts
type Project = {
  id: string; // doc id
  accountId: string;
  name: string;
  clientName: string;

  description?: string | null;
  mainImageUrl?: string | null; // may be "offline://<mediaId>"
  metadata?: Record<string, any> | null;
} & LifecycleAuditFields;
```

#### `accounts/{accountId}/users/{userId}/projectPreferences/{projectId}` (ProjectPreferences)

```ts
type ProjectPreferences = {
  id: string; // id = projectId
  accountId: string;
  userId: string;
  projectId: string;
  pinnedBudgetCategoryIds: string[];

  // Lifecycle/audit fields are recommended for this doc (see entity section below).
  createdAt?: Timestamp;
  updatedAt?: Timestamp;
};
```

#### `accounts/{accountId}/presets/default/budgetCategories/{budgetCategoryId}` (BudgetCategory)

```ts
type BudgetCategoryMetadata = {
  categoryType?: "standard" | "itemized" | "fee";
  excludeFromOverallBudget?: boolean;
  legacy?: Record<string, any> | null;
};

type BudgetCategory = {
  id: string; // doc id
  accountId: string;
  projectId: null; // preset categories are account-level
  name: string;
  slug: string;
  isArchived: boolean;

  metadata?: BudgetCategoryMetadata | null;
} & LifecycleAuditFields;
```

#### `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}` (ProjectBudgetCategory)

```ts
type ProjectBudgetCategory = {
  id: string; // id = budgetCategoryId (preset id)
  budgetCents: number | null; // integer cents; null = enabled but not budgeted
} & LifecycleAuditFields;
```

#### `accounts/{accountId}/items/{itemId}` (Item)

```ts
type Item = {
  id: string; // doc id
  accountId: string;
  projectId: string | null; // null = Business Inventory scope
  createdBy: string; // required (Roles v2 selectors)
  // Canonical item label. Note: may be an empty string for parity/legacy data.
  name: string;

  source?: string | null;
  sku?: string | null;
  notes?: string | null;
  bookmark?: boolean;
  purchasedBy?: "Client" | "Design Business" | null;
  status?: "to purchase" | "purchased" | "to return" | "returned" | null;

  images?: AttachmentRef[];

  transactionId?: string | null;
  spaceId?: string | null;
  // Item-owned budget category id. May be set via:
  // - linking to a non-canonical categorized transaction
  // - explicit user choice during a sell/allocation prompt
  budgetCategoryId?: string | null; // required field; may be null

  purchasePriceCents?: number | null;
  projectPriceCents?: number | null;
  marketValueCents?: number | null;

  taxRatePct?: number | null;
  taxAmountPurchasePriceCents?: number | null;
  taxAmountProjectPriceCents?: number | null;

  originTransactionId?: string | null;
  latestTransactionId?: string | null;
} & LifecycleAuditFields;
```

#### `accounts/{accountId}/spaces/{spaceId}` (Space)

```ts
type Space = {
  id: string; // doc id
  accountId: string;
  projectId: string | null; // null = Business Inventory scope
  name: string;

  notes?: string | null;
  images?: AttachmentRef[];
  checklists?: SpaceChecklist[];
} & LifecycleAuditFields;
```

#### `accounts/{accountId}/presets/default/spaceTemplates/{templateId}` (SpaceTemplate)

```ts
type SpaceTemplate = {
  id: string; // doc id
  accountId: string;
  name: string;
  isArchived: boolean;

  notes?: string | null;
  checklists?: SpaceChecklist[]; // uses the same checklist shapes as Space
} & LifecycleAuditFields;
```

#### `accounts/{accountId}/users/{uid}` (AccountUser / Member)

```ts
type Member = {
  id: string; // id = uid
  accountId: string;
  uid: string;
  role: "owner" | "admin" | "user";

  allowedBudgetCategoryIds?: Record<string, true> | null;
  isDisabled?: boolean;

  // Lifecycle/audit fields are recommended for this doc (see entity section below).
  createdAt?: Timestamp;
  updatedAt?: Timestamp;
};
```

#### `accounts/{accountId}/invites/{inviteId}` (Invite)

```ts
type Invite = {
  id: string; // inviteId; doc id
  accountId: string;
  email: string;
  role: "admin" | "user";
  token: string;

  createdAt: Timestamp;
  createdByUid?: string | null;
  expiresAt?: Timestamp | null;
  acceptedAt?: Timestamp | null;
  acceptedByUid?: string | null;
  revokedAt?: Timestamp | null;
};
```

#### `accounts/{accountId}/profile/default` (Profile)

```ts
type Profile = {
  id: "default";
  accountId: string;
  businessName: string;
  logo?: AttachmentRef | null;

  createdAt?: Timestamp;
  updatedAt?: Timestamp;
  updatedBy?: string | null;
};
```

#### `accounts/{accountId}/billing/entitlements` (BillingEntitlements)

```ts
type BillingEntitlements = {
  accountId: string;
  planType: "free" | "pro";
  limits: {
    maxProjects: number;
    maxItems: number;
    maxTransactions: number;
    maxUsers: number;
  };
  updatedAt: Timestamp;

  source?: {
    provider: "revenuecat";
    environment?: "sandbox" | "production";
    appUserId?: string;
    lastSyncedAt?: Timestamp;
  };
};
```

#### `accounts/{accountId}/billing/usage` (BillingUsage)

```ts
type BillingUsage = {
  projectCount: number;
  itemCount: number;
  transactionCount: number;
  userCount: number;
  updatedAt: Timestamp;
};
```

#### Request docs (RequestDoc)

Paths:
- `accounts/{accountId}/requests/{requestId}` (canonical home; scope encoded in `payload`, e.g. `payload.projectId` where applicable)

```ts
type RequestDoc = {
  id: string; // requestId; doc id
  type: string;
  status: "pending" | "applied" | "failed" | "denied";
  opId: string; // idempotency key for the logical user action
  createdAt: Timestamp;
  createdBy: string; // uid
  payload: Record<string, any>;

  appliedAt?: Timestamp;
  errorCode?: string;
  errorMessage?: string;
};
```

Known minimum `payload` shapes (from feature specs):

```ts
type ItemSaleExpectedSnapshot = {
  itemProjectId: string | null;
  itemTransactionId?: string | null;
};

type ItemSaleProjectToBusinessPayload = {
  itemId: string;
  sourceProjectId: string;
  budgetCategoryId: string;
  expected: ItemSaleExpectedSnapshot;
};

type ItemSaleBusinessToProjectPayload = {
  itemId: string;
  targetProjectId: string;
  budgetCategoryId: string;
  expected: ItemSaleExpectedSnapshot;
  // optional parity-only fields intentionally omitted here (see entity sections below)
};

type ItemSaleProjectToProjectPayload = {
  itemId: string;
  sourceProjectId: string;
  targetProjectId: string;
  sourceBudgetCategoryId: string;
  destinationBudgetCategoryId: string;
  expected: ItemSaleExpectedSnapshot;
  // optional parity-only fields intentionally omitted here (see entity sections below)
};

type InvoiceImportPayloadMinimum = {
  projectId: string;
  transaction: Partial<Transaction>;
  items: Array<Partial<Item>>;
};
```

#### `accounts/{accountId}/presets/default/vendors/{vendorId}` (VendorDefaults; use `vendorId = "default"`)

```ts
type VendorDefaults = {
  vendors: string[]; // ordered list (parity: 10 slots)

  createdAt?: Timestamp;
  updatedAt?: Timestamp;
};
```

#### `accounts/{accountId}/transactions/{transactionId}` (Transaction)

```ts
type Transaction = {
  id: string; // doc id
  accountId: string;
  projectId: string | null; // null = Business Inventory scope
  transactionDate: string; // stored as string for parity
  amountCents: number; // authoritative; canonical inventory sale rows are system-computed and read-only

  source?: string | null;
  transactionType?: string | null;
  purchasedBy?: "Client" | "Design Business" | null;
  notes?: string | null;
  status?: "pending" | "completed" | "canceled" | null;
  reimbursementType?: string | null;
  triggerEvent?: string | null;
  receiptEmailed?: boolean;

  receiptImages?: AttachmentRef[];
  otherImages?: AttachmentRef[];
  transactionImages?: AttachmentRef[];

  budgetCategoryId?: string | null;

  needsReview?: boolean;
  taxRatePresetId?: string | null;
  taxRatePct?: number | null;
  subtotalCents?: number | null;
  sumItemPurchasePricesCents?: number | null;

  // Canonical inventory sale semantics (new model):
  // - category-coded via `budgetCategoryId` (required for canonical inventory sale rows)
  // - direction-coded via `inventorySaleDirection`
  isCanonicalInventorySale?: boolean;
  inventorySaleDirection?: "business_to_project" | "project_to_business" | null;

  itemIds?: string[]; // non-authoritative cache
} & LifecycleAuditFields;
```

#### `accounts/{accountId}/lineageEdges/{edgeId}` (LineageEdge)

```ts
type LineageEdge = {
  id: string; // doc id
  accountId: string;
  itemId: string;
  fromTransactionId: string | null; // null = from inventory
  toTransactionId: string | null; // null = to inventory
  createdAt: Timestamp;
  createdBy: string;

  // Classification used by UI/semantics. This is intentionally not inferred purely
  // from "where it moved to" because some moves are corrective (non-economic).
  // `null` is allowed for legacy/unknown edges.
  movementKind?: "sold" | "returned" | "correction" | "association" | null;

  // Provenance for debugging + filtering (e.g., hide auto association edges in UI).
  // This replaces the legacy "db_trigger/app" mental model:
  // - `server` includes request-doc handlers and server-side triggers.
  source?: "app" | "server" | "migration";

  // Optional scope hints (rules + query helpers).
  // These are derived by the server at write time and represent the project context
  // implied by the edge endpoints.
  fromProjectId?: string | null;
  toProjectId?: string | null;

  note?: string | null;
} & LifecycleAuditFields;
```

---

## Conventions (applies to all entities below)

### Naming

- **Canonical field names** are `camelCase` (TypeScript + Firestore documents).
- **SQLite columns** are `snake_case`.

### Document IDs (single source of truth)

Firestore document identity is the **document id** (the `{...Id}` segment in the path). To avoid “multiple id fields” drift:

- **Do not persist a separate `id` field inside the document body** for domain entities (projects, items, transactions, etc.).
- In TypeScript/UI models we still refer to an `id: string` for convenience, but it is **derived from the Firestore document id** (e.g. `snapshot.id`) rather than stored.

Contract note for this document:
- In the `ts` code blocks below, fields like `id: string` refer to the **document id**, not a persisted field.

Offline-first note:
- Firestore can generate document ids **offline** (auto-id) for user-created docs (e.g. items/transactions/requests). These ids are stable across retries and sync.

### ID character constraints (for deterministic canonical sale ids)

Some system docs use deterministic ids (not auto-ids), most notably canonical inventory sale transactions:

- Canonical sale transaction id format (deterministic):
  - `SALE_<projectId>_<direction>_<budgetCategoryId>`
- To keep this safely **parseable** by splitting on `_`, the component ids MUST NOT contain `_`:
  - `projectId` and `budgetCategoryId` must match `^[A-Za-z0-9]+$` (no underscores).

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

- **Project scope**: `projectId = "<projectId>"` and docs live under the account-level collections (e.g. `accounts/{accountId}/items/{itemId}`)
- **Business inventory scope**: `projectId = null` and docs live under the same account-level collections

Contract rule:
- `projectId: string | null` is always present on **scoped mutable entities** (items/transactions/spaces/lineage edges, etc.).
- `projectId = null` must mean **Business Inventory** (not “unknown project”).

### Lifecycle + audit fields (Firestore-native offline baseline)

Architecture baseline note:
- Firestore is canonical, with native offline persistence + scoped listeners.
- Do **not** require bespoke sync-engine primitives (outbox ids, delta cursors, `meta/sync`) as part of entity contracts unless a feature spec explicitly requires them.

For every **scoped mutable entity doc** (including items, transactions, spaces, lineage edges), include:

- `createdAt: Timestamp`
- `updatedAt: Timestamp` (server timestamp; updated on every accepted change)
- `deletedAt: Timestamp | null` (tombstone)
- `createdBy?: string | null` (uid; required when Rules need it as a selector)
- `updatedBy?: string | null` (uid; optional unless Rules require it)
- `schemaVersion?: number` (optional; recommended)

### Security fields (Roles v2)

Roles v2 requires **server-enforceable selectors**. At minimum:

- Entities that use “own uncategorized” behavior MUST include `createdBy: string` (uid).
  - Required for **Items** (see Roles v2 spec: uncategorized items visible only to creator).

### Embedded media references (URLs + `offline://` placeholders)

Feature specs model media as **embedded references on domain entities** (not as separate “Attachment docs”).

Canonical shared shapes (used by multiple entities):

- `AttachmentKind = "image" | "pdf"`
- `AttachmentRef` (persisted on the owning domain entity doc in Firestore):
  - `url: string`
    - Either a remote URL **or** an `offline://<mediaId>` placeholder string (must render via local media cache).
    - Contract: `offline://<mediaId>` is a stable join key into the local media cache + upload queue (see cross-cutting spec: `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`).
  - `kind: AttachmentKind`
    - **Required**. This is how we represent **image vs PDF** explicitly (not by inferring from the URL).
  - `contentType?: string`
    - Optional, recommended when known (e.g. `"image/jpeg"`, `"image/png"`, `"application/pdf"`).
  - `isPrimary?: boolean`
    - Only for entity galleries that support a single primary image (e.g. `item.images[]`, `space.images[]`).
    - Constraint: at most one entry per gallery should have `isPrimary === true` (enforced by app logic and/or server-owned invariants where applicable).

Important rule (GAP B resolution):
- **Do not persist transient upload state** (`local_only | uploading | failed | uploaded`) on Firestore domain entities.
  - Firestore persists stable domain truth (“this entity has these attachments”).
  - Upload state is tracked locally (durable upload queue + local media cache); UI derives state by joining on `offline://<mediaId>` and/or local records.

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
- `mainImageUrl?: string | null`
  - Project cover image URL stored directly on the project.
  - May be a remote URL or an `offline://<mediaId>` placeholder string (see “Embedded media references” above).
- `metadata?: Record<string, any> | null`

Lifecycle/audit fields (required): see “Lifecycle + audit fields” above.

Budgeting model (canonical; required for correctness):
- Project budgeting is defined by per-category allocation docs (see **Entity: ProjectBudgetCategory** below).
- “Fee” categories:
  - are identified by `BudgetCategory.metadata.categoryType === "fee"` (see **Entity: BudgetCategory** below)
  - use “received” rollup semantics (not “spent”) in the Budget UI
- “Excluded from overall” categories:
  - are identified by `BudgetCategory.metadata.excludeFromOverallBudget === true`
  - are excluded from:
    - “spent overall” totals
    - the overall budget denominator
  - default behavior: included (the flag is absent/false)
- “Itemized” categories:
  - are identified by `BudgetCategory.metadata.categoryType === "itemized"`
  - enable the transaction “itemization” UI + tax inputs (see `40_features/project-transactions/**`)
- Mutual exclusivity invariant:
  - a category MUST NOT be both fee and itemized (enforced structurally by a single `categoryType` field)

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
- **images**:
  - `main_image_url` (TEXT)
- **flex**:
  - `metadata_json` (TEXT)
- **sync + local bookkeeping**: per `local_sqlite_schema.md` common columns

---

## Entity: ProjectPreferences (per-user per-project)

This entity captures **per-user UI preferences** for a specific project. These preferences are **not shared** project settings.

Primary use cases:
- **Pinned budget categories**: drive which budget trackers are shown in the collapsed Budget view.
- **Projects list budget preview**: uses the same pinned subset as the collapsed Budget view (see `40_features/budget-and-accounting/**` and `40_features/projects/**`).

Bootstrap requirement (Firebase migration; required):
- For **every new project**, the system ensures **“Furnishings” is pinned by default**.
  - Pins are **per-user per-project** (not shared project settings), so this means:
    - the creator gets a seeded `ProjectPreferences` doc at project creation time, and
    - other users get a `ProjectPreferences` doc created **lazily** the first time a surface needs it (e.g., Projects list preview or Budget tab), if they don’t already have one.
      - The created doc uses `pinnedBudgetCategoryIds = [<furnishingsCategoryId>]` as its initial value.

### Canonical fields (TypeScript / Firestore doc shape)

Doc id:
- `id = projectId`

Required:
- `accountId: string`
- `userId: string`
- `projectId: string`
- `pinnedBudgetCategoryIds: string[]`
  - Ordered list.
  - UI constraint (recommended): cap to a small number (e.g. 3–5).

Lifecycle/audit fields (recommended):
- `createdAt: Timestamp`
- `updatedAt: Timestamp`

### Firestore location (recommended)

- `accounts/{accountId}/users/{userId}/projectPreferences/{projectId}`

### SQLite mapping (optional)

Not required to persist to SQLite: Firestore-native offline persistence provides a local cache for these user preferences.

If additional local persistence is desired for faster boot or cross-surface caching, store as a small table keyed by `(accountId, userId, projectId)`:
- `account_id` (TEXT NOT NULL)
- `user_id` (TEXT NOT NULL)
- `project_id` (TEXT NOT NULL)
- `pinned_budget_category_ids_json` (TEXT NOT NULL) (JSON array; ordered)
- sync + local bookkeeping columns (per `local_sqlite_schema.md`)

Primary key:
- `(account_id, user_id, project_id)`

---

## Entity: BudgetCategory (account preset)

This is the account-wide **preset category definition** used by:

- transaction category pickers (`transaction.budgetCategoryId`)
- project budget setup (project-specific allocation docs reference these ids)

Bootstrap requirement (Firebase migration; required):
- New accounts (and newly joined members, when they first enter an account) must have a **seeded set of budget category presets** sufficient for the core app to function offline.
- The seeded set must include **“Furnishings”**.
  - Canonical baseline seed list (v1):
    - **Furnishings** (`metadata.categoryType = "itemized"`)
    - **Design Fee** (`metadata.categoryType = "fee"`)

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

- `metadata?: BudgetCategoryMetadata | null`

Where:

- `BudgetCategoryMetadata`:
  - `categoryType?: "standard" | "itemized" | "fee"`
    - Default: `"standard"` when missing.
    - UI label: `"standard"` is shown as **General** in the app.
    - `categoryType === "itemized"` enables transaction itemization + tax inputs.
    - `categoryType === "fee"` enables “fee tracker” semantics (received, not spent) in budget rollups.
    - Mutual exclusivity is structural: a category cannot be both fee and itemized.
  - `excludeFromOverallBudget?: boolean`
    - Default: `false` when missing.
    - When `true`, this category is excluded from the “overall” rollups:
      - overall spent
      - overall budget denominator
  - `legacy?: Record<string, any> | null`
    - Escape hatch for pre-migration / legacy UI toggles; do not add new semantics here.

Lifecycle/audit fields (required): see “Lifecycle + audit fields” above.

### Firestore location

- `accounts/{accountId}/presets/default/budgetCategories/{budgetCategoryId}`

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

Lifecycle/audit fields (required): see “Lifecycle + audit fields” above.

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
- `40_features/project-items/feature_spec.md` (requires `budgetCategoryId`)
- `40_features/budget-and-accounting/feature_spec.md` (canonical attribution uses item prices)
- `40_features/inventory-operations-and-lineage/feature_spec.md` + `flows/lineage_edges_and_pointers.md` (lineage pointers)
- `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md` (requires `createdBy` and selector semantics)

### Canonical fields

Required:
- `id: string` (doc id; stable across offline/online)
- `accountId: string`
- `projectId: string | null`
- `createdBy: string`
  - Roles v2: required to enforce "own uncategorized items" when `budgetCategoryId == null`.
- `name: string`
  - Canonical item label.
  - Parity/legacy: `name` may be an empty string.

Optional / nullable:
- `source?: string | null`
- `sku?: string | null`
- `notes?: string | null`
- `bookmark?: boolean`
- `purchasedBy?: "Client" | "Design Business" | null`
- `status?: "to purchase" | "purchased" | "to return" | "returned" | null`
- `images?: AttachmentRef[]`
  - Embedded media references (remote URLs or `offline://<mediaId>` placeholders).
  - Constraint: `images[].kind` should be `"image"` for item galleries.
  - `isPrimary` is optional; if present, at most one image should be marked primary.

Relationships / selectors (nullable):
- `transactionId?: string | null`
- `spaceId?: string | null`
  - When `projectId = null` (Business Inventory), `spaceId` is the inventory location reference (Space in inventory scope).
- `budgetCategoryId?: string | null`
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

Lineage pointers (nullable):
- `originTransactionId?: string | null`
- `latestTransactionId?: string | null`

Lifecycle/audit fields (required): see “Lifecycle + audit fields” above.

### Scope semantics + Firestore locations

Project-scope item:
- `projectId = "<projectId>"`
- Firestore: `accounts/{accountId}/items/{itemId}`

Business inventory item:
- `projectId = null`
- Firestore: `accounts/{accountId}/items/{itemId}`

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
- `purchased_by` (TEXT NULL)
- `status` (TEXT NULL)

Local search index note:
- SQLite is optional and non-authoritative; if used, prefer a rebuildable search index per `local_sqlite_schema.md`.

---

## Entity: Space

This contract must satisfy:

- `40_features/spaces/feature_spec.md` (project + inventory spaces; images; checklists; scope consistency rules)

### Canonical fields

Required:
- `id: string` (doc id)
- `accountId: string`
- `projectId: string | null`
  - `null` means **Business Inventory scope**.
- `name: string`

Optional / nullable:
- `notes?: string | null`
- `images?: AttachmentRef[]`
  - See “Embedded media references (URLs + `offline://` placeholders)” above.
  - Constraint: `images[].kind` should be `"image"` for space galleries.
- `checklists?: SpaceChecklist[]`

Where:

- `SpaceChecklist`:
  - `id: string`
  - `name: string`
  - `items: SpaceChecklistItem[]`
- `SpaceChecklistItem`:
  - `id: string`
  - `text: string`
  - `isChecked: boolean`

Notes:
- Checklists are ordered by array order. Each checklist’s items are ordered by array order.

Lifecycle/audit fields (required): see “Lifecycle + audit fields” above.

### Scope semantics + Firestore locations

Project-scope space:
- `projectId = "<projectId>"`
- Firestore: `accounts/{accountId}/spaces/{spaceId}`

Business inventory space:
- `projectId = null`
- Firestore: `accounts/{accountId}/spaces/{spaceId}`

### SQLite mapping (optional)

If Spaces require robust offline search beyond Firestore cache and bounded queries, model them as part of the non-authoritative, rebuildable search index.

Otherwise, SQLite persistence is not required for Spaces under the Firestore-native offline baseline.

---

## Entity: SpaceTemplate (account preset)

This contract must satisfy:

- `40_features/spaces/feature_spec.md` (“Space template: account-wide preset”)
- `40_features/settings-and-admin/feature_spec.md` (Presets → Space templates manager)

### Canonical fields

Required:
- `id: string` (doc id)
- `accountId: string`
- `name: string`
- `isArchived: boolean`

Optional / nullable:
- `notes?: string | null`
- `checklists?: SpaceTemplateChecklist[]`

Where:

- `SpaceTemplateChecklist` and `SpaceTemplateChecklistItem` reuse the `SpaceChecklist` / `SpaceChecklistItem` shapes from **Entity: Space**.

Normalization requirement (from feature specs):
- Template checklist items should be stored with `isChecked = false` (templates are “prefill”, not “stateful progress”).

Lifecycle/audit fields (required): see “Lifecycle + audit fields” above.

### Firestore location (recommended; aligns with “presets” semantics)

- `accounts/{accountId}/presets/default/spaceTemplates/{templateId}`

---

## Entity: Member (account membership / role)

This contract must satisfy:

- `40_features/auth-and-invitations/feature_spec.md` (membership-gated access; server-owned invite acceptance)
- `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md` (Roles v2 selectors)
- `40_features/settings-and-admin/feature_spec.md` (owner/admin gating)

Member/users doc = the account roster entry (uid, role, allowed categories, disabled flag, etc.).
ProjectPreferences = per-user UI preferences, stored under that roster doc.

### Canonical fields

Doc id:
- `id = uid`

Required:
- `accountId: string`
- `uid: string`
- `role: "owner" | "admin" | "user"`

Optional:
- `allowedBudgetCategoryIds?: Record<string, true> | null`
  - Roles v2: preferred “set/map shape” for Rules checks.
- `isDisabled?: boolean`
  - If true, the client must fail closed (treat as no access).

Lifecycle/audit fields (recommended):
- `createdAt: Timestamp`
- `updatedAt: Timestamp`

### Firestore location

- `accounts/{accountId}/users/{uid}`

---

## Entity: Invite (pending invitation)

This contract must satisfy:

- `40_features/auth-and-invitations/feature_spec.md` (tokenized deep links + server-owned acceptance)
- `40_features/settings-and-admin/feature_spec.md` (pending invites list + copy link)

### Canonical fields

Required:
- `id: string` (inviteId; doc id)
- `accountId: string`
- `email: string`
- `role: "admin" | "user"`
- `token: string`

Optional / nullable:
- `createdAt: Timestamp`
- `createdByUid?: string | null`
- `expiresAt?: Timestamp | null`
- `acceptedAt?: Timestamp | null`
- `acceptedByUid?: string | null`
- `revokedAt?: Timestamp | null`

### Firestore location

- `accounts/{accountId}/invites/{inviteId}`

---

## Entity: Profile (account branding)

This entity provides the account-level branding inputs used by Settings and Reports (business name + logo).

### Canonical fields

Doc id:
- `id = "default"`

Required:
- `accountId: string`
- `businessName: string`

Optional / nullable:
- `logo?: AttachmentRef | null`
  - Uses the same embedded media reference convention as other entities.
  - Constraint: `logo.kind` should be `"image"`.

Lifecycle/audit fields (recommended):
- `createdAt: Timestamp`
- `updatedAt: Timestamp`
- `updatedBy?: string | null`

### Firestore location (canonical)

- `accounts/{accountId}/profile/default`

---

## Entity: BillingEntitlements (server-owned enforcement snapshot)

This contract must satisfy:

- `40_features/_cross_cutting/billing-and-entitlements/feature_spec.md`

### Canonical fields (v1)

Required:
- `accountId: string`
- `planType: "free" | "pro"`
- `limits: { maxProjects: number; maxItems: number; maxTransactions: number; maxUsers: number }`
- `updatedAt: Timestamp`

Optional:
- `source?: { provider: "revenuecat"; environment?: "sandbox" | "production"; appUserId?: string; lastSyncedAt?: Timestamp }`

### Firestore location

- `accounts/{accountId}/billing/entitlements`

---

## Entity: BillingUsage (server-owned counters)

This contract must satisfy:

- `40_features/_cross_cutting/billing-and-entitlements/feature_spec.md`

### Canonical fields (v1)

Required:
- `projectCount: number`
- `itemCount: number`
- `transactionCount: number`
- `userCount: number`
- `updatedAt: Timestamp`

### Firestore location

- `accounts/{accountId}/billing/usage`

---

## Entity: RequestDoc (request-doc workflow envelope)

This contract must satisfy:

- `OFFLINE_FIRST_V2_SPEC.md` (request-doc workflows)
- `40_features/inventory-operations-and-lineage/feature_spec.md` (required fields + `opId` idempotency)
- `40_features/invoice-import/feature_spec.md` (create transaction + items via request-docs)
- `40_features/_cross_cutting/billing-and-entitlements/feature_spec.md` (account-scoped gated create via request-docs)

### Canonical fields

Required:
- `id: string` (doc id; requestId)
- `type: string`
- `status: "pending" | "applied" | "failed" | "denied"`
  - Note: some features only need `pending|applied|failed`; `denied` is used when the server explicitly rejects due to policy/entitlements.
- `opId: string`
  - Stable idempotency key for the logical user action.
- `createdAt: Timestamp`
- `createdBy: string` (uid)
- `payload: Record<string, any>`

Optional:
- `appliedAt?: Timestamp`
- `errorCode?: string`
- `errorMessage?: string`

### Firestore locations (canonical)

- `accounts/{accountId}/requests/{requestId}`
  - Scope is encoded in the RequestDoc `payload` (e.g. `payload.projectId` where applicable).

### Known request payload schemas (codified from feature specs)

This section exists to prevent each feature from inventing incompatible `payload` shapes. Feature specs are the source of truth.

#### Inventory operations (`inventory-operations-and-lineage`) — required

Source of truth: `40_features/inventory-operations-and-lineage/feature_spec.md` (“Request-doc collection + payload shapes”).

All of these use:

- `type`: `"ITEM_SALE_PROJECT_TO_BUSINESS" | "ITEM_SALE_BUSINESS_TO_PROJECT" | "ITEM_SALE_PROJECT_TO_PROJECT"`
- `opId`: stable idempotency key for the logical user action
- `payload.expected`: conflict-detection snapshot required by the feature spec

`payload` shapes (minimum required fields):

- `ITEM_SALE_PROJECT_TO_BUSINESS`
  - `itemId: string`
  - `sourceProjectId: string`
  - `budgetCategoryId: string`
  - `expected: { itemProjectId: string | null; itemTransactionId?: string | null }`

- `ITEM_SALE_BUSINESS_TO_PROJECT`
  - `itemId: string`
  - `targetProjectId: string`
  - `budgetCategoryId: string`
  - optional parity fields: `space`, `notes`, `amount`
  - `expected: { itemProjectId: string | null; itemTransactionId?: string | null }`

- `ITEM_SALE_PROJECT_TO_PROJECT`
  - `itemId: string`
  - `sourceProjectId: string`
  - `targetProjectId: string`
  - `sourceBudgetCategoryId: string`
  - `destinationBudgetCategoryId: string`
  - optional parity fields: `space`, `notes`, `amount`
  - `expected: { itemProjectId: string | null; itemTransactionId?: string | null }`

Notes:
- The optional fields above are intentionally left untyped here because they are parity-only and must be reconciled with the canonical `Item` + `Transaction` fields when implemented.
- The required fields are the invariants needed for idempotent, transactional correctness.

#### Invoice import (transaction + items create) — required (minimal)

Source of truth: `40_features/invoice-import/feature_spec.md` + `40_features/invoice-import/ui/screens/*` (request-doc workflow requirement).

This feature requires a request-doc workflow to create a transaction and items atomically. The feature specs do not currently standardize a `type` string for this operation; the important part for alignment is that:

- the request payload includes the transaction fields and item fields to create, and
- all money fields are expressed in integer cents per the canonical entity contracts.

Minimum payload shape (conceptual; aligns to entity contracts):

- `projectId: string`
- `transaction: Partial<Transaction>` (fields to create; must use `*Cents` for money)
- `items: Array<Partial<Item>>` (fields to create; must use `*Cents` for money)

---

## Entity: VendorDefaults (account preset; recommended shape)

This entity is required by feature specs (transactions/forms) but is not fully specified elsewhere yet.
It is stored as a single doc under `vendors/default` to avoid extra nesting while keeping a presets umbrella.

### Canonical fields (recommended)

Required:
- `vendors: string[]`
  - Ordered list, UI-capped (parity: 10 slots).

Lifecycle/audit fields (recommended):
- `createdAt: Timestamp`
- `updatedAt: Timestamp`

### Firestore location (recommended)

- `accounts/{accountId}/presets/default/vendors/default`

---

## Entity: Transaction

This contract must satisfy:
- `40_features/project-transactions/feature_spec.md` (filters, canonical title/amount semantics, receipts/PDFs via embedded `receiptImages[]`)
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
  - For canonical inventory sale transactions, this is **system-computed** (server-owned invariant) and treated as read-only by clients.

Optional / nullable:
- `source?: string | null`
- `transactionType?: string | null`
- `purchasedBy?: "Client" | "Design Business" | null`
- `notes?: string | null`
- `status?: "pending" | "completed" | "canceled" | null`
- `reimbursementType?: string | null`
- `triggerEvent?: string | null`
- `receiptEmailed?: boolean`

Embedded media (per feature specs; uses “Embedded media references” above):
- `receiptImages?: AttachmentRef[]`
  - Receipts accept images and PDFs in feature specs:
    - images: `kind: "image"`
    - PDFs: `kind: "pdf"`
  - `isPrimary` is typically unused for receipts; if present, treat it as a UI hint only (not correctness-critical).
- `otherImages?: AttachmentRef[]`
  - Constraint: `kind: "image"` (non-PDF) for this field.
- `transactionImages?: AttachmentRef[]`
  - Legacy compat: feature specs mention mirroring receipts here.

Budget category selector:
- `budgetCategoryId?: string | null`
  - Non-canonical: authoritative category selector.
  - Canonical inventory sale (system): required (category-coded invariant).

Completeness / rollup helpers (optional; denormalized):
- `needsReview?: boolean`
- `taxRatePresetId?: string | null`
- `taxRatePct?: number | null`
- `subtotalCents?: number | null`
- `sumItemPurchasePricesCents?: number | null`

Canonical inventory sale transaction selectors (Roles v2 + queryability):
- `isCanonicalInventorySale?: boolean`
- `inventorySaleDirection?: "business_to_project" | "project_to_business" | null`

Linkage helpers (optional; denormalized):
- `itemIds?: string[]`
  - Non-authoritative cache; use `item.transactionId` as the canonical association.

Lifecycle/audit fields (required): see “Lifecycle + audit fields” above.

### Canonical inventory sale semantics (authoritative)

Canonical inventory sale transactions are identified by a deterministic id.
Recommended id prefix:
- `SALE_<projectId>_<direction>_<budgetCategoryId>`

Required attribution invariant:
- **Non-canonical** transactions: category attribution is transaction-driven via `transaction.budgetCategoryId`.
- **Canonical inventory sale (system)** transactions: category attribution is transaction-driven via `transaction.budgetCategoryId` (category-coded invariant).
  Sign is applied by `inventorySaleDirection`.

Cross-entity invariant (required by transaction edit UX; deterministic attribution):
- When editing a **non-canonical** transaction and its `budgetCategoryId` changes, all linked items must have `item.budgetCategoryId` updated to match the new `budgetCategoryId`.
  - Source of truth: `40_features/project-transactions/feature_spec.md` ("Edit a transaction" requirement).

Authoritative value source for canonical totals:
- For canonical inventory sale totals, the authoritative value stored on the transaction is `transaction.amountCents`, computed by the server from linked item values (see `40_features/inventory-operations-and-lineage/feature_spec.md`).
- Clients must not write back “self-healed” canonical totals from UI.

### Scope semantics + Firestore locations

Project-scope transaction:
- `projectId = "<projectId>"`
- Firestore: `accounts/{accountId}/transactions/{transactionId}`

Business inventory transaction:
- `projectId = null`
- Firestore: `accounts/{accountId}/transactions/{transactionId}`

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
- `purchased_by` (TEXT NULL)
- `notes` (TEXT NULL)

Workflow columns:
- `status` (TEXT NULL)
- `reimbursement_type` (TEXT NULL)
- `trigger_event` (TEXT NULL)
- `receipt_emailed` (INTEGER NOT NULL DEFAULT 0)

Category + canonical semantics:
- `budget_category_id` (TEXT NULL)
- `is_canonical_inventory_sale` (INTEGER NOT NULL DEFAULT 0)
- `inventory_sale_direction` (TEXT NULL) (`business_to_project` | `project_to_business`)

Completeness / denormalized helpers:
- `needs_review` (INTEGER NOT NULL DEFAULT 0)
- `tax_rate_preset_id` (TEXT NULL)
- `tax_rate_pct` (REAL NULL)
- `subtotal_cents` (INTEGER NULL)
- `sum_item_purchase_prices_cents` (INTEGER NULL)
- `item_ids_json` (TEXT NULL) (optional; JSON array; non-authoritative cache)

Local search index note:
- SQLite is optional and non-authoritative; if used, prefer a rebuildable search index per `local_sqlite_schema.md`.

---

## Media contract note (replaces prior “Attachment entity”)

Prior drafts modeled media as separate Attachment documents. This conflicts with feature specs, which consistently reference embedded fields like:

- `transaction.receiptImages[]` / `transaction.otherImages[]` (with `offline://` placeholders)
- `space.images[]`
- example: `item.images[]` (embedded media refs)

**Contract decision (aligned to feature specs):** model media as embedded URL refs on the owning entity (see “Embedded media references” above).

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
- `movementKind?: "sold" | "returned" | "correction" | "association" | null`
  - `sold`: user intent was an economic sale / inventory designation / allocation sale.
  - `returned`: user intent was an explicit return into a Return transaction.
  - `correction`: corrective/non-economic move (fixing a mistake).
  - `association`: server-recorded audit edge when `item.transactionId` changes.
  - `null`: legacy/unknown (allowed).
  - Note: association edges are audit-only and can exist **alongside** intent edges
    for the same item move. They are not mutually exclusive.
- `source?: "app" | "server" | "migration"`
  - `server` includes request-doc handlers and server triggers.
- `fromProjectId?: string | null`
- `toProjectId?: string | null`
- `note?: string | null`

Lifecycle/audit fields (required): see “Lifecycle + audit fields” above.

Observed in code (Firebase lineage write points):
- `ledger_mobile/firebase/functions/src/index.ts` (top comment block; design overview)
- `ledger_mobile/firebase/functions/src/index.ts` (`onItemTransactionIdChanged` → `movementKind: "association"` + `movementKind: "returned"` when Return)
- `ledger_mobile/firebase/functions/src/index.ts` (`handleProjectToBusiness`, `handleBusinessToProject`, `handleProjectToProject` → `movementKind: "sold"`)

Short rationale:
- Association edges preserve a full audit trail.
- Intent edges drive UI labels like Sold/Returned without guesswork.

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

Local search index note:
- SQLite is optional and non-authoritative; if used, prefer a rebuildable search index per `local_sqlite_schema.md`.

