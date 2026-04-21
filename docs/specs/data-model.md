# Data Model Specification

This document defines every Firestore entity, its fields, and all cross-entity relationships used by Ledger. It is the canonical reference for how data is shaped, linked, and computed. Platform-agnostic: no language types, no file paths, no component names.

---

## Table of Contents

1. [Tenant Model](#tenant-model)
2. [Entities](#entities)
3. [Embedded Types](#embedded-types)
4. [Relationships](#relationships)
5. [Computed Entities](#computed-entities)
6. [Scope Semantics](#scope-semantics)
7. [Sign Conventions](#sign-conventions)
8. [Data Validation Rules](#data-validation-rules)

---

## Tenant Model

All data lives under a single **Account** document. Every entity path begins with `accounts/{accountId}/...`. An account is a multi-user tenant; users are represented as **AccountMember** documents.

### Account

**Path:** `accounts/{accountId}`

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID |
| name | string | Required |
| ownerUid | string, nullable | Firebase Auth UID of the account owner |
| logo | AttachmentRef, nullable | Business logo image |
| createdAt | timestamp | |
| updatedAt | timestamp | |

### AccountMember

**Path:** `accounts/{accountId}/users/{userId}`

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID |
| accountId | string, nullable | |
| uid | string, nullable | Firebase Auth UID |
| role | string, nullable | One of: "owner", "admin", "user" |
| email | string, nullable | |
| name | string, nullable | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

## Entities

### 1. Transaction

**Path:** `accounts/{accountId}/transactions/{transactionId}`

A financial event: a purchase, return, sale, or inventory transfer.

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID |
| projectId | string, nullable | FK to Project. Null is valid for business-inventory-scoped transactions |
| budgetCategoryId | string, nullable | FK to BudgetCategory |
| amountCents | number, nullable | Total amount in cents (always stored as positive; see Sign Conventions) |
| subtotalCents | number, nullable | Pre-tax subtotal in cents. When set, should be <= amountCents |
| taxRatePct | number, nullable | Tax rate as a percentage (0-100) |
| transactionType | string, nullable | **Firestore field name is `type`**. One of: `"purchase"`, `"sale"`, `"return"` |
| status | string, nullable | One of: `"pending"`, `"completed"`, `"canceled"` |
| source | string, nullable | Vendor/source name (e.g. "Amazon", "Wayfair"). This is the vendor field. **Sale transactions and return-to-inventory transactions use the literal `"Business Inventory"`.** |
| transactionDate | string, nullable | Date of the transaction (stored as a string, not a timestamp) |
| itemIds | array of string, nullable | **CANONICAL link to items.** List of Item document IDs associated with this transaction |
| notes | string, nullable | |
| ~~isCanceled~~ | ~~boolean~~ | **Removed.** Use `status == "canceled"` instead. Canceled transactions contribute $0 to all budget calculations |
| isCanonicalInventorySale | boolean, nullable | **LEGACY.** True only on legacy canonical sale transactions written before the per-batch redesign. New per-batch sales never set this flag. See [canonical-sales.md](canonical-sales.md). |
| inventorySaleDirection | string, nullable | **LEGACY.** Only set when `isCanonicalInventorySale` is true. New per-batch sales have no direction (sales only go business → project). |
| isCanonicalInventory | boolean, nullable | Legacy flag for older inventory operations |
| canonicalKind | string, nullable | Legacy kind classifier |
| ~~needsReview~~ | ~~boolean~~ | **Removed.** Replaced by `isComplete`. |
| isComplete | boolean, nullable | Auto-computed by Cloud Function. `true` = complete, `false` = needs review (shows badge). See `docs/specs/transaction-completeness.md` |
| audit | TransactionAudit, nullable | Stored completeness audit data. Contains `resolvedSubtotalCents`, `itemsSumCents`, `varianceCents`, `variancePercent`. Null for non-itemized categories. See `docs/specs/transaction-completeness.md` |
| purchasedBy | string, nullable | Who made the purchase |
| reimbursementType | string, nullable | |
| hasEmailReceipt | boolean, nullable | **Firestore field name is `receiptEmailed`** |
| receiptImages | array of AttachmentRef, nullable | Receipt photo attachments |
| otherImages | array of AttachmentRef, nullable | Other supporting images |
| transactionImages | array of AttachmentRef, nullable | General transaction images |
| ingestionSource | string, nullable | Origin of the transaction: `"email"` (auto-ingested from email), `"manual"` (created by human), or null (legacy/unknown) |
| ingestionStatus | string, nullable | Ingestion lifecycle: `"needs_review"` (unmatched or low confidence), `"auto_matched"` (matched to project but unconfirmed), `"confirmed"` (user-verified), or null |
| ingestionMeta | IngestionMeta, nullable | Metadata from the email ingestion pipeline. Null for manually created transactions |
| createdAt | timestamp | |
| updatedAt | timestamp | |

**Why `type` is aliased to `transactionType`:** The Firestore field is named `type`, but application code maps it to `transactionType` to avoid collisions with language-reserved keywords and for clarity.

#### Sale and Return-to-Inventory Immutability

**Per-batch Sale transactions** (the new model — `type: "Sale"` with no `isCanonicalInventorySale` flag) and **Return-to-Inventory transactions** (`type: "Return"` with `source: "Business Inventory"`) are **immutable after creation** for their shape fields:

- `type`
- `source`
- `projectId`
- `amountCents`
- `itemIds`
- `budgetCategoryId`

Mutable fields: `notes`, `status`, `updatedAt`. Cancellation works by setting `status: "canceled"` — the shape fields stay frozen.

Enforced by Firestore security rules ([firebase/firestore.rules](../../firebase/firestore.rules)). Both clients additionally enforce on the write side. Legacy canonical sales (`isCanonicalInventorySale == true`) are exempt from this rule for backwards compatibility — see [canonical-sales.md](canonical-sales.md).

See [sale-transactions.md](sale-transactions.md) for the full sale shape and the rationale.

**Return-to-inventory coalescing exception:** A return-to-inventory transaction MAY be appended to within the same user session (multiple returns coalesce into one transaction via `arrayUnion` on `itemIds` and a recalculated `amountCents`). Once the user leaves the flow or 24h passes, the transaction is treated as closed and clients should create a new one for subsequent returns. See [return-and-sale-tracking.md](return-and-sale-tracking.md).

---

### 2. Item

**Path:** `accounts/{accountId}/items/{itemId}`

A physical or trackable object: furniture, material, supply, etc.

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID |
| accountId | string, nullable | FK to Account |
| projectId | string, nullable | FK to Project. Null means item is in business inventory |
| transactionId | string, nullable | FK to Transaction. **Exists but is NOT reliably set.** Do not use for lookups (see Relationships warning) |
| spaceId | string, nullable | FK to Space |
| budgetCategoryId | string, nullable | FK to BudgetCategory. **Invariant: `(projectId == null) ↔ (budgetCategoryId == null)`** — items in business inventory have no category. Set when an item moves into a project (sell-to-project flow) and wiped when an item moves into inventory (return-to-inventory flow). See "Item Scope/Category Invariant" below. |
| name | string, nullable | Primary display name |
| description | string, nullable | Legacy field. Fallback display name when name is null |
| sku | string, nullable | Stock-keeping unit identifier |
| purchasePriceCents | number, nullable | What was paid for this item (in cents) |
| projectPriceCents | number, nullable | Price charged to/for the project (in cents) |
| marketValueCents | number, nullable | Estimated market value |
| status | string, nullable | One of: `"to purchase"`, `"purchased"`, `"to return"`, `"returned"`, `"sold"`. `"sold"` is system-set by sale operations |
| source | string, nullable | **Original vendor** — where the item was first acquired (e.g. "Homegoods", "Wayfair"). Set once at item creation and **never overwritten** by scope moves. Used for routing returns back to the original store, grouping by vendor, and the editable "Source" field in the item detail modal |
| currentSource | string, nullable | **Immediate source** — denormalized from the item's current transaction `source` so search cards can render the origin without a per-row transaction lookup. Written by `InventoryOperationsService` on `sellToProject` / `returnToInventory` / `moveBetweenProjects` (set to the inventory label). `reassignToProject` and `returnToTransaction` do not touch it (within-project moves don't change the immediate source). At creation time, callers set `currentSource = source`. Legacy items pre-dating this field have `currentSource == nil`; display callers fall back to `source` |
| notes | string, nullable | |
| bookmark | boolean, nullable | User-set bookmark flag |
| purchasedBy | string, nullable | |
| quantity | number, nullable | |
| taxRatePct | number, nullable | Tax rate as a percentage (e.g. 8.375). Inherited from the transaction of origin at item creation time |
| images | array of AttachmentRef, nullable | |
| createdBy | string, nullable | Firebase Auth UID |
| updatedBy | string, nullable | Firebase Auth UID |
| createdAt | timestamp | |
| updatedAt | timestamp | |

**Display name resolution:** Prefer `name`, fall back to `description`, then empty string.

#### Item Scope/Category Invariant

For every Item:

```
(item.projectId == null) ↔ (item.budgetCategoryId == null)
```

Items in business inventory (`projectId == null`) have `budgetCategoryId == null`. Items in a project have a `budgetCategoryId`. Both clients (iOS and MCP) enforce this on every write.

**This replaces** the legacy "items carry their `budgetCategoryId` across scope moves" model. Under the new model, categories belong to projects — when an item moves into inventory, its category is wiped; when an item moves into a project, a category is acquired (resolved at sell time from user input).

Rationale: see [inventory-as-store.md](inventory-as-store.md) and [budget-management.md](budget-management.md) "Item Budget Category Attribution."

**Existing inventory items with stale categories** (items currently in inventory with non-null `budgetCategoryId` from before the redesign) are left as-is. The next time one of them moves, the new flow takes over and either wipes or overwrites the field. No backfill is run.

---

### 3. Space

**Path:** `accounts/{accountId}/spaces/{spaceId}`

A physical location or logical grouping within a project or business inventory (e.g. "Living Room", "Warehouse Shelf A").

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID |
| accountId | string, nullable | FK to Account |
| projectId | string, nullable | FK to Project. Null means business inventory scope |
| name | string | Required. Defaults to empty string |
| notes | string, nullable | |
| images | array of AttachmentRef, nullable | |
| checklists | array of Checklist, nullable | Embedded checklist data |
| isArchived | boolean, nullable | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

### 4. Project

**Path:** `accounts/{accountId}/projects/{projectId}`

A design project, job, or client engagement.

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID |
| accountId | string, nullable | FK to Account |
| name | string | Required. Defaults to empty string |
| clientName | string | Client/customer name. Defaults to empty string |
| description | string, nullable | |
| mainImageUrl | string, nullable | URL to the project's primary image |
| isArchived | boolean, nullable | |
| notes | string, nullable | Free-text notes about the project (e.g. payment method details, billing address variations, other identifiers for receipt matching) |
| budgetSummary | ProjectBudgetSummary, nullable | Denormalized budget rollup (see embedded type below) |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

### 5. BudgetCategory (Account-Scoped Preset)

**Path:** `accounts/{accountId}/presets/default/budgetCategories/{budgetCategoryId}`

A reusable budget category template defined at the account level. These are the "master list" of categories available across all projects.

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID |
| accountId | string, nullable | FK to Account |
| projectId | string, nullable | Always null for account-scoped presets |
| name | string | Required. Defaults to empty string |
| slug | string, nullable | URL-safe identifier |
| isArchived | boolean, nullable | Archived categories are hidden from new allocations but preserved for historical data |
| order | number, nullable | Display order hint |
| metadata | BudgetCategoryMetadata, nullable | See embedded type below |
| createdAt | timestamp | |
| updatedAt | timestamp | |

**Why projectId is always null:** This entity is an account-level preset, not a per-project allocation. The projectId field exists for structural consistency but is always null at this path.

---

### 6. ProjectBudgetCategory (Per-Project Allocation)

**Path:** `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`

Represents a budget category that has been "enabled" for a specific project, with an optional dollar budget.

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID. **Matches the BudgetCategory document ID** |
| budgetCents | number, nullable | Budget allocation in cents. Null means "enabled but no budget set" |
| createdBy | string, nullable | Firebase Auth UID |
| updatedBy | string, nullable | Firebase Auth UID |
| createdAt | timestamp | |
| updatedAt | timestamp | |

**Semantics:**
- Document **exists** = category is enabled for this project
- Document **does not exist** = category is not enabled for this project
- `budgetCents` is null = enabled but not budgeted (no dollar target)
- `budgetCents` is 0 = explicitly budgeted at zero

**Why the ID matches BudgetCategory ID:** This creates a 1:1 mapping between account-level presets and per-project allocations. Looking up a project's budget for a category is a single document read by ID, no query needed.

---

### 7. ProjectPreferences (User-Specific Display Settings)

**Path:** `accounts/{accountId}/users/{userId}/projectPreferences/{projectId}`

Per-user, per-project display preferences. These do not affect data or calculations, only UI presentation.

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID. **Matches the Project document ID** |
| accountId | string, nullable | FK to Account |
| userId | string, nullable | Firebase Auth UID |
| projectId | string, nullable | FK to Project |
| pinnedBudgetCategoryIds | array of string, nullable | Ordered list of BudgetCategory IDs pinned by this user for this project |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

### 8. LineageEdge

**Path:** `accounts/{accountId}/lineageEdges/{edgeId}`

Tracks the movement history of an item across transactions and projects. Each edge represents one movement event.

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID |
| accountId | string, nullable | FK to Account |
| itemId | string, nullable | FK to Item. The item that moved |
| movementKind | string, nullable | One of: "association", "sold", "returned", "correction" |
| fromTransactionId | string, nullable | FK to Transaction. The source transaction (null for "association" edges) |
| toTransactionId | string, nullable | FK to Transaction. The destination transaction |
| fromProjectId | string, nullable | FK to Project. The source project (null for business inventory) |
| toProjectId | string, nullable | FK to Project. The destination project (null for business inventory) |
| source | string, nullable | Origin of the edge: "app", "server", "migration" |
| note | string, nullable | |
| createdBy | string, nullable | Firebase Auth UID |
| createdAt | timestamp | Server timestamp |

**Four edge types:**

| movementKind | Meaning | fromTransactionId | toTransactionId |
|---|---|---|---|
| association | Item linked to a transaction (initial purchase) | null | The transaction the item was purchased in |
| sold | Item sold from one scope to another | Source transaction (or null) | Destination sale/purchase transaction |
| returned | Item returned from one transaction context to another | Original transaction | Return transaction |
| correction | Manual data correction entry | Original transaction | Corrected transaction |

---

### 9. VendorDefaults (Account Preset)

**Path:** `accounts/{accountId}/presets/default/vendors/default`

A single document holding the account's list of vendor/source presets for transaction entry.

| Field | Type | Constraints |
|-------|------|-------------|
| vendors | array of string | List of vendor names |
| updatedAt | timestamp | |

---

### 10. SpaceTemplate (Account Preset)

**Path:** `accounts/{accountId}/presets/default/spaceTemplates/{templateId}`

Predefined space templates for quick space creation.

---

### 11. RequestDoc (Write-Ahead Log for Atomic Operations)

**Path:** `accounts/{accountId}/requests/{requestDocId}` (account-scoped)
**Path:** `accounts/{accountId}/projects/{projectId}/requests/{requestDocId}` (project-scoped)

A write-ahead log entry for multi-document operations that require atomicity guarantees beyond what a client-side batch can provide. The client writes a request document with `status: "pending"`, and a Cloud Function picks it up, executes the multi-document operation atomically, and updates the status.

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Document ID |
| type | string | The operation type (e.g. "bulkSale", "import") |
| status | string | One of: "pending", "applied", "failed", "denied" |
| opId | string | Idempotency key. Client-generated unique ID to prevent duplicate processing |
| payload | map | Operation-specific data. Structure varies by `type` |
| createdAt | timestamp | Server timestamp |
| createdBy | string, nullable | Firebase Auth UID |
| appliedAt | timestamp, nullable | When the operation was executed |
| errorCode | string, nullable | Machine-readable error code on failure |
| errorMessage | string, nullable | Human-readable error description on failure |

**Why this exists:** Some operations (e.g. bulk sales across multiple items and projects) need to update many documents atomically with server-side validation. The client cannot guarantee atomicity for these. Instead, the client writes an intent document, and a Cloud Function reads the intent and executes it in a transaction.

---

## Embedded Types

These are not Firestore collections. They are nested objects/arrays within parent documents.

### AttachmentRef

Embedded within Transaction, Item, and Space documents.

| Field | Type | Constraints |
|-------|------|-------------|
| url | string | Required. Storage download URL or path |
| kind | string | One of: "image", "pdf", "file". Defaults to "image" |
| fileName | string, nullable | Original file name |
| contentType | string, nullable | MIME type |
| isPrimary | boolean, nullable | Whether this is the primary/hero image |

### IngestionMeta

Embedded within Transaction documents. Stores context from the email ingestion pipeline.

| Field | Type | Constraints |
|-------|------|-------------|
| emailId | string, nullable | Unique identifier of the source email (e.g. Gmail message ID). Used for deduplication |
| subject | string, nullable | Email subject line |
| inbox | string, nullable | Email address of the inbox that received the order |
| matchConfidence | number, nullable | 0.0–1.0 confidence score for project matching |
| matchReason | string, nullable | Human-readable explanation of why this transaction was matched to a project |
| orderNumber | string, nullable | Vendor order number parsed from the email |
| linkedIngestionIds | array of string, nullable | Transaction IDs of related ingested transactions (e.g. split shipments from the same order) |

### BudgetCategoryMetadata

Embedded within BudgetCategory documents.

| Field | Type | Constraints |
|-------|------|-------------|
| categoryType | string, nullable | One of: "general", "standard", "itemized", "fee". Defaults to "general" if not set |
| excludeFromOverallBudget | boolean, nullable | When true, this category's spend is not included in the project's overall budget totals |

**Category types explained:**
- **general** / **standard**: Normal spend categories (purchases, materials)
- **itemized**: Categories where individual items are tracked with prices for completeness auditing
- **fee**: Revenue/income categories (e.g. design fees). Display uses "received" instead of "spent"

### ProjectBudgetSummary

Embedded within Project documents. A denormalized rollup of budget data for fast reads.

| Field | Type | Constraints |
|-------|------|-------------|
| totalBudgetCents | number, nullable | Sum of all non-excluded category budgets |
| spentCents | number, nullable | Sum of all non-excluded category spend |
| categories | map of string to BudgetSummaryCategory, nullable | Keyed by budgetCategoryId |

### BudgetSummaryCategory

Embedded within ProjectBudgetSummary.

| Field | Type | Constraints |
|-------|------|-------------|
| budgetCents | number, nullable | |
| spentCents | number, nullable | |
| name | string, nullable | |
| categoryType | string, nullable | Mirrors BudgetCategoryMetadata.categoryType |
| isArchived | boolean, nullable | |
| excludeFromOverallBudget | boolean, nullable | |

### Checklist

Embedded within Space documents.

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Client-generated UUID |
| name | string | Defaults to empty string |
| items | array of ChecklistItem | Defaults to empty array |

### ChecklistItem

Embedded within Checklist.

| Field | Type | Constraints |
|-------|------|-------------|
| id | string | Client-generated UUID |
| text | string | Defaults to empty string |
| isChecked | boolean | Defaults to false |

---

## Relationships

> **WARNING: Transaction to Items lookup direction**
>
> The canonical way to find a transaction's items is to filter items whose `id` appears in `transaction.itemIds`. Do **NOT** filter items by `item.transactionId == transaction.id` -- this field exists on items but is **a cache back-reference, not the source of truth.** It is not reliably set and should not be used for forward lookups.
>
> Card and list views use `transaction.itemIds` for counts. Detail views must use the same source. This has caused bugs when the wrong lookup direction was used.
>
> **Per-batch sale immutability:** under the per-batch sale model (see [sale-transactions.md](sale-transactions.md)), `transaction.itemIds` is set once at sale creation and never mutated. The same applies to Return-to-Inventory transactions (with the documented coalescing exception). This makes `itemIds` reliably authoritative for these transaction types.

### Relationships Table

| Source Entity | Relation | Target Entity | Cardinality | Lookup Field and Direction | Notes |
|---|---|---|---|---|---|
| Transaction | has many | Item | 1:N | `transaction.itemIds` contains item IDs. **CANONICAL -- use this for all lookups.** | Filter items collection where `item.id IN transaction.itemIds` |
| Item | belongs to | Transaction | N:1 | `item.transactionId` | **EXISTS but UNRELIABLE.** Do not use for forward lookups from transaction to items. May be used for reverse lookups (given an item, find its transaction) with caution |
| Item | belongs to | Project | N:1 | `item.projectId` | Null means business inventory. See Scope Semantics |
| Item | belongs to | Space | N:1 | `item.spaceId` | Null means item is not in any space |
| Item | belongs to | BudgetCategory | N:1 | `item.budgetCategoryId` | **Invariant: `(projectId == null) ↔ (budgetCategoryId == null)`.** Set when an item moves into a project (sell-to-project flow); wiped when an item moves into inventory (return-to-inventory flow). Auto-set from destination transaction on association or reassignment within a project. |
| Transaction | belongs to | Project | N:1 | `transaction.projectId` | Null is valid for business-inventory-scoped transactions |
| Transaction | belongs to | BudgetCategory | N:1 | `transaction.budgetCategoryId` | Links transaction spend to a budget category for rollup calculations |
| Space | belongs to | Project | N:1 | `space.projectId` | Null means business inventory scope |
| LineageEdge | belongs to | Item | N:1 | `edge.itemId` | Each edge tracks one item's movement |
| LineageEdge | references (from) | Transaction | N:1 | `edge.fromTransactionId` | Null for "association" edges |
| LineageEdge | references (to) | Transaction | N:1 | `edge.toTransactionId` | The destination transaction |
| LineageEdge | references (from) | Project | N:1 | `edge.fromProjectId` | Null when source is business inventory |
| LineageEdge | references (to) | Project | N:1 | `edge.toProjectId` | Null when destination is business inventory |
| Project | has embedded | ProjectBudgetSummary | 1:1 | `project.budgetSummary` | Denormalized rollup on the project document |
| ProjectBudgetCategory | mirrors | BudgetCategory | 1:1 | Document IDs match | A ProjectBudgetCategory document exists for each BudgetCategory enabled in that project |
| ProjectPreferences | references | Project | 1:1 | `projectPreferences.projectId` (also the document ID) | Per-user display settings for a project |
| ProjectPreferences | references (list) | BudgetCategory | 1:N | `projectPreferences.pinnedBudgetCategoryIds` | Ordered list of pinned categories |

---

## Computed Entities

### TransactionCompleteness

The core audit fields (`itemsSumCents`, `varianceCents`, `variancePercent`, and the lineage breakdown fields) are computed server-side by the `computeIsComplete` Cloud Function and persisted as the `audit` object on the transaction document (see `transaction-completeness.md`). The fields below include both the persisted audit fields and additional presentation-only fields derived client-side.

Compares linked item prices against the transaction subtotal to measure how well items account for the total spend.

| Field | Type | How Computed |
|-------|------|-------------|
| itemsNetTotalCents | number | `sum(item.purchasePriceCents)` for all linked items (including returned and sold items from lineage) |
| itemsCount | number | Count of all linked items |
| itemsMissingPriceCount | number | Count of linked items where `purchasePriceCents` is null or 0 |
| transactionSubtotalCents | number | Resolved subtotal (see resolution order below) |
| completenessRatio | number | `itemsNetTotalCents / transactionSubtotalCents` |
| completenessStatus | string | One of: "complete", "near", "incomplete", "over" |
| missingTaxData | boolean | True when subtotal was derived from amountCents without tax rate |
| inferredTax | number, nullable | `amountCents - transactionSubtotalCents` when tax rate was used to derive subtotal |
| varianceCents | number | `itemsNetTotalCents - transactionSubtotalCents` |
| variancePercent | number | `(varianceCents / transactionSubtotalCents) * 100` |
| returnedItemsCount | number | Count of returned items from lineage |
| returnedItemsTotalCents | number | Sum of returned items' purchasePriceCents |
| soldItemsCount | number | Count of sold items from lineage |
| soldItemsTotalCents | number | Sum of sold items' purchasePriceCents |

**Subtotal resolution order (first match wins):**

1. `transaction.subtotalCents` if set and > 0
2. Inferred from tax: `amountCents / (1 + taxRatePct / 100)` if both amountCents and taxRatePct are set and > 0
3. `transaction.amountCents` if set and > 0 (sets `missingTaxData = true`)
4. If none of the above: completeness is **N/A** (function returns null)

**Completeness status thresholds:**

| Status | Condition |
|--------|-----------|
| over | completenessRatio > 1.2 |
| complete | abs(variancePercent) <= 1.0 |
| near | abs(variancePercent) <= 20.0 |
| incomplete | abs(variancePercent) > 20.0 |

**Division by zero:** When transactionSubtotalCents is 0, completeness is N/A (null return).

---

### BudgetProgress

Computed client-side for budget displays and the budget tab.

| Field | Type | How Computed |
|-------|------|-------------|
| totalBudgetCents | number | Sum of `budgetCents` from all non-excluded ProjectBudgetCategory documents |
| totalSpentCents | number | Sum of normalized spend across all non-excluded categories |
| categories | array of CategoryProgress | One entry per enabled category |

#### CategoryProgress (within BudgetProgress)

| Field | Type | How Computed |
|-------|------|-------------|
| id | string | BudgetCategory document ID |
| name | string | BudgetCategory name |
| budgetCents | number | From the matching ProjectBudgetCategory document (0 if not set) |
| spentCents | number | Sum of `normalizeTransactionAmount(tx)` for all transactions with `budgetCategoryId == id` |
| categoryType | string | From BudgetCategoryMetadata.categoryType (defaults to "general") |
| excludeFromOverallBudget | boolean | From BudgetCategoryMetadata.excludeFromOverallBudget |

**Spend normalization pseudocode (per transaction):**

```
function normalizeTransactionAmount(transaction):
    if transaction.status == "canceled":
        return 0

    amount = transaction.amountCents or 0

    # LEGACY canonical sale carve-out (historical docs only)
    if transaction.isCanonicalInventorySale is true:
        if transaction.inventorySaleDirection == "project_to_business":
            return -abs(amount)     // money back to business
        if transaction.inventorySaleDirection == "business_to_project":
            return abs(amount)      // money spent on project
        return amount               // fallback if direction unknown

    # NEW per-batch sales: always +1
    if transaction.transactionType == "sale":
        return abs(amount)          // money spent on project (one direction only)

    # Returns (vendor or inventory) subtract
    if transaction.transactionType == "return" OR amount < 0:
        return -abs(amount)

    return amount                   // purchases add to spend
```

The dual-read path (legacy canonical sales vs. new per-batch sales) is the intentional cost of preserving historical financial records. Centralized in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts) `normalizeSpendAmount`.

**Overall budget computation:**

```
overallSpentCents = sum(category.spentCents) for categories where excludeFromOverallBudget is false
overallBudgetCents = sum(category.budgetCents) for categories where excludeFromOverallBudget is false
```

**Category filtering for display:**
- Only show categories with `budgetCents > 0 OR spentCents != 0`
- Exclude archived categories
- Sort: non-fee categories first (alphabetical), then fee categories (alphabetical)

---

## Scope Semantics

The application has two scopes:

### Project Scope

An entity with a non-null `projectId` belongs to that project. It appears in that project's lists and contributes to that project's budget calculations.

### Business Inventory Scope

An entity with `projectId: null` belongs to **business inventory** -- the account-wide pool not tied to any specific project. This applies to:

- **Items** with `projectId: null`: These are in business inventory (e.g. purchased but not yet allocated to a project, or returned from a project to inventory)
- **Spaces** with `projectId: null`: These are business-inventory spaces (e.g. warehouse, storage unit)
- **Transactions** with `projectId: null`: These are business-level transactions not tied to a project

**Scope transitions:**

When an item moves between scopes, its `projectId` and `budgetCategoryId` are updated together to preserve the invariant `(projectId == null) ↔ (budgetCategoryId == null)`:

- **Sell to project** (`sellToProject`): item moves from inventory to a project. `projectId` set to destination project ID, `budgetCategoryId` set to the chosen batch category, `spaceId` set to null, `status` set to `"purchased"`. Creates a per-batch Sale transaction. See [sale-transactions.md](sale-transactions.md).
- **Return to inventory** (`returnToInventory`): item moves from a project back to inventory. `projectId` set to null, **`budgetCategoryId` wiped to null**, `spaceId` set to null, `status` set to `"purchased"`. Creates a Return transaction with `source: "Business Inventory"`. See [return-and-sale-tracking.md](return-and-sale-tracking.md).
- **Move between projects** (`moveBetweenProjects`): atomic combination of return-to-inventory + sell-to-destination. Two transactions, one batch. See [sale-transactions.md](sale-transactions.md) "Project → Project Moves."
- **Reassign within scope** (`reassignToProject`, `reassignToInventory`): non-financial moves within the same scope or correcting a scope error. Updates `projectId` and (if needed) `budgetCategoryId` to maintain the invariant.

**The invariant is enforced on every write.** This replaces the legacy "items carry budgetCategoryId across scope moves" model. See [inventory-as-store.md](inventory-as-store.md) for the rationale.

---

## Sign Conventions

All monetary values are stored in **cents** (integer). The stored value in Firestore is always the **absolute magnitude** (positive). Sign is determined by context during computation.

### Transaction amountCents

- **Purchases:** Stored as positive. Adds to project spend.
- **Returns** (vendor or to inventory): Stored as positive. **Multiplied by -1** in budget calculations (subtracts from project spend). Identified by `transactionType == "return"`.
- **Per-batch Sale transactions** (`type == "sale"`, no `isCanonicalInventorySale` flag): Stored as positive. **Adds** to project spend. There is only one direction (business → project); the reverse case is a Return.
- **LEGACY canonical sales, `business_to_project`:** Stored as positive. **Adds** to project spend. Historical only.
- **LEGACY canonical sales, `project_to_business`:** Stored as positive. **Multiplied by -1** in budget calculations. Historical only.
- **Canceled transactions:** Always contribute **$0** regardless of amount. Identified by `status == "canceled"`.

Centralized in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts) `normalizeSpendAmount`. Any new reader must consult this function rather than reimplement the convention.

### Item price fields

- `purchasePriceCents`: Non-negative. What was paid for the item.
- `projectPriceCents`: Non-negative. What the project is charged for the item.
- `marketValueCents`: Non-negative. Estimated market value.

### Budget calculations

- `budgetCents`: Non-negative. The allocated budget for a category.
- `spentCents`: Can be **negative** after normalization (e.g. a category with only returns and no purchases). This is valid and displays as "$X received back" or similar.

---

## Data Validation Rules

### Monetary Fields

| Field | Rule |
|-------|------|
| amountCents | Should be a positive integer when set. Handle null and 0 gracefully |
| subtotalCents | When set, should be <= amountCents. Represents pre-tax amount |
| taxRatePct | When set, should be in range 0-100 |
| purchasePriceCents | Non-negative when set |
| projectPriceCents | Non-negative when set |
| marketValueCents | Non-negative when set |
| budgetCents (ProjectBudgetCategory) | Non-negative when not null. Null means "no budget set" |

### Division Safety

- When `transactionSubtotalCents == 0`: Completeness calculation returns N/A (null). Never divide by zero.
- When `budgetCents == 0`: Budget ratio returns 0. Budget percentage returns "0%". Remaining label returns "No budget set".

### Nullable Array Fields

- `itemIds`: When null or empty, the transaction has no linked items. Treat null and empty array identically.
- `pinnedBudgetCategoryIds`: When null or empty, no categories are pinned. Treat null and empty array identically.
- `images`, `receiptImages`, `otherImages`, `transactionImages`: When null, treat as empty array.
- `checklists`: When null, treat as empty array.

### Field Value Conventions

All enum-like fields use **lowercase with spaces** for multi-word values. Swift enums enforce this via `rawValue` matching the storage format. Display uses `.displayLabel` (computed from `rawValue.capitalized`).

| Field | Valid values |
|-------|-------------|
| `item.status` | `"to purchase"`, `"purchased"`, `"to return"`, `"returned"`, `"sold"` |
| `transaction.type` | `"purchase"`, `"sale"`, `"return"` |
| `transaction.status` | `"pending"`, `"completed"`, `"canceled"` |

- `source` (vendor) values are case-sensitive display strings; do not normalize.
