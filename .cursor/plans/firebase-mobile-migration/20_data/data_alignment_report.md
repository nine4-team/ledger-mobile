# Data alignment report — Items + Transactions (pass after Project alignment)

This report records mismatches found between **feature specs** (behavioral truth) and the existing data docs under `20_data/*`, and how those mismatches were resolved by tightening the canonical contracts in `20_data/data_contracts.md`.

Scope of this pass:
- **Items**
- **Transactions**
- Cross-cutting data they require: canonical `INV_*` semantics, category attribution rules, lineage, Roles v2 selectors, media/attachments

## Summary of resolutions

- **Canonical contracts expanded**: `Item`, `Transaction`, `Attachment`, `LineageEdge` (plus item lineage pointers) were added to `20_data/data_contracts.md`.
- **Firestore + SQLite docs de-duplicated**: `firebase_data_model.md` now links to contracts for entity field shapes (no divergent field lists); SQLite schema doc aligns `items`/`transactions` and adds a `lineage_edges` table.
- **Money representation decision**: adopted **Option B (tightened)** — persist money as **integer cents** for Items + Transactions (documented in canonical contracts and reflected in SQLite column naming).

## Mismatches found (spec vs data docs) and how they were resolved

### 1) Canonical `INV_*` attribution is item-driven, not transaction-category-driven

- **Spec truth**
  - Canonical inventory transactions (`INV_PURCHASE_*`, `INV_SALE_*`, `INV_TRANSFER_*`) must be treated as “uncategorized” at the transaction level; attribution is **item-driven** via `item.inheritedBudgetCategoryId`.
  - Sources:
    - `40_features/project-items/feature_spec.md` (Rules 1–2; required `inheritedBudgetCategoryId`)
    - `40_features/project-transactions/feature_spec.md` (canonical rows treated as uncategorized; budget-category filters must join via items)
    - `40_features/budget-and-accounting/feature_spec.md` (canonical attribution grouping and value computation)

- **Prior data doc mismatch**
  - `20_data/firebase_data_model.md` had a longer “canonical transaction budgeting” section but also mixed in legacy “transaction category” expectations in ways that made it easy to treat canonical rows as category-driven.

- **Resolution**
  - Canonical `INV_*` semantics are now explicit in `20_data/data_contracts.md` → **Entity: Transaction**:
    - `budgetCategoryId` is non-authoritative for canonical transactions
    - canonical attribution uses linked items’ `inheritedBudgetCategoryId`

### 2) Roles v2 requires server-enforceable selectors (no “download everything then filter”)

- **Spec truth**
  - Items require `createdBy` to support scoped-user visibility for uncategorized items (`inheritedBudgetCategoryId == null`).
  - Canonical `INV_*` transaction visibility is derived from **linked items**; you cannot treat `transaction.categoryId == null` as “private/mine”.
  - Sources:
    - `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md`

- **Prior data doc mismatch**
  - Existing data docs did not clearly require the selectors needed to enforce Roles v2 without “download then filter”, especially for canonical `INV_*` transactions.

- **Resolution**
  - `20_data/data_contracts.md` → **Entity: Item** now requires:
    - `createdBy` (security field required by Roles v2)
    - `inheritedBudgetCategoryId` (stable selector)
  - `20_data/data_contracts.md` → **Entity: Transaction** adds **server-maintained selector fields** for canonical transactions:
    - `attributedCategoryIds` (set/map of in-scope categories present among linked items)
    - `attributedUncategorizedCreatorUids` (set/map of creators who have uncategorized linked items)
  - `20_data/local_sqlite_schema.md` was updated to include these selectors locally as JSON map columns for offline filtering.

### 3) Lineage is required offline (append-only edges + item pointers)

- **Spec truth**
  - Must append lineage edges on cross-scope operations.
  - Must maintain item pointers (`latestTransactionId`, optionally `originTransactionId`).
  - Lineage edges should be available offline (intentional delta vs web).
  - Sources:
    - `40_features/inventory-operations-and-lineage/feature_spec.md`
    - `40_features/inventory-operations-and-lineage/flows/lineage_edges_and_pointers.md`

- **Prior data doc mismatch**
  - `20_data/local_sqlite_schema.md` had no lineage edges table.

- **Resolution**
  - `20_data/data_contracts.md` adds **Entity: LineageEdge** and item lineage pointer fields.
  - `20_data/local_sqlite_schema.md` adds `lineage_edges` table + indexes for offline lineage history.

### 4) Offline media lifecycle needs explicit attachment lifecycle state

- **Spec truth**
  - Attachments must support the state machine: `local_only`, `uploading`, `uploaded`, `failed`.
  - Must support images + PDFs.
  - Sources:
    - `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
    - `40_features/project-transactions/feature_spec.md` (receipts and other attachments)
    - `40_features/sync_engine_spec.plan.md` (§8 media strategy)

- **Prior data doc mismatch**
  - Firestore doc previously described attachments as nested subcollections under parents, while the sync plan’s appendix uses scope-root attachments.
  - SQLite attachment table existed, but the canonical decision (embedded arrays vs attachment docs) was not authoritative.

- **Resolution**
  - Canonical decision: **Attachment docs are canonical** (`20_data/data_contracts.md` → **Entity: Attachment**).
  - Firestore paths were aligned to **scope-root attachment docs**:
    - `accounts/{accountId}/projects/{projectId}/attachments/{attachmentId}`
    - `accounts/{accountId}/inventory/attachments/{attachmentId}`
  - SQLite `attachments` section was updated to include required lifecycle fields and metadata (`kind`, `local_media_id`, etc.).

### 5) Money representation for Items/Transactions was inconsistent across docs

- **Spec truth**
  - Rollups treat money as two-decimal currency semantics and require consistent rounding.
  - Sources:
    - `40_features/budget-and-accounting/feature_spec.md` (money normalization + rollups)

- **Prior data doc mismatch**
  - `20_data/firebase_data_model.md` and `20_data/local_sqlite_schema.md` described transaction/item money as strings.
  - `20_data/data_contracts.md` already tightened some money fields (project budgets) but did not establish a consistent Items/Transactions rule.

- **Resolution**
  - Canonical decision in `20_data/data_contracts.md`: **persist money as integer cents** for Items + Transactions (Option B), including explicit parsing/rounding expectations for migration/import boundaries.
  - SQLite docs updated to use `_cents` columns for all money-like fields on `items` and `transactions`.

## Intentional deltas (with rationale + blast radius)

### A) Lineage edges stored in an account-wide Firestore collection

- **Decision**
  - Store lineage edges at `accounts/{accountId}/lineageEdges/{edgeId}` (not under project/inventory scope collections).

- **Rationale**
  - Items physically move between project scope and inventory scope collections; storing lineage under an item subcollection would risk losing history or requiring copy-on-move.

- **Blast radius**
  - Security rules must enforce lineage visibility via linked item/transaction selectors.
  - Delta sync must include the `lineageEdges` collection (or otherwise backfill edges relevant to visible items).

## Open decisions / questions (not resolvable from specs alone)

### 1) How exactly are canonical transaction selector fields maintained?

The contracts assume canonical transaction selector fields (`attributedCategoryIds`, `attributedUncategorizedCreatorUids`) are **server-maintained** to satisfy Roles v2 enforcement constraints.

Open implementation decisions:
- Which operations update these fields (item link/unlink, item recategorization, cross-scope ops)?
- Are these fields maintained only for `isCanonicalInventory == true`, or for all transactions (with different semantics)?
- Do we need a dedicated “visibility index” collection instead (Roles v2 spec suggests this as a possible approach)?

### 2) Attachment Firestore doc timing (create-before-upload vs create-after-upload)

The contract allows the Firestore attachment doc to appear once upload begins/finishes (since `local_only` cannot exist remotely).

Open decision:
- Do we create Firestore attachment docs immediately when online selection happens (to replicate “uploading” state to other devices), or only after upload finishes (cheaper; fewer transient writes)?

