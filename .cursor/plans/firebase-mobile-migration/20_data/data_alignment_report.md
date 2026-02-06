# Data alignment report — Items + Transactions (pass after Project alignment)

This report records mismatches found between **feature specs** (behavioral truth) and the existing data docs under `20_data/*`, and how those mismatches were resolved by tightening the canonical contracts in `20_data/data_contracts.md`.

Scope of this pass:
- **Items**
- **Transactions**
- Cross-cutting data they require: canonical `INV_SALE_*` semantics, category attribution rules, lineage, Roles v2 selectors, media/attachments

## Summary of resolutions

- **Canonical contracts expanded**: `Item`, `Transaction`, `LineageEdge` (plus item lineage pointers) were tightened in `20_data/data_contracts.md`.
- **Media contract realigned to feature specs**: removed the prior “Attachment doc” contract and aligned to embedded URL refs (`offline://` placeholders) on owning entities (e.g. `transaction.receiptImages[]`, `space.images[]`).
- **Firestore + SQLite docs realigned**:
  - `firebase_data_model.md` now focuses on Firestore paths + modeling rules and points back to canonical contracts.
  - `local_sqlite_schema.md` now defines **optional derived search indexes only** (SQLite is non-authoritative and rebuildable).
- **Money representation decision**: adopted **Option B (tightened)** — persist money as **integer cents** for Items + Transactions (documented in canonical contracts and reflected in SQLite column naming).

## Mismatches found (spec vs data docs) and how they were resolved

### 1) Canonical `INV_SALE_*` attribution is transaction-category-driven (new model)

- **Spec truth (new model)**
  - Canonical inventory rows are **sale transactions only** and are **category-coded** via `transaction.budgetCategoryId`.
  - Canonical inventory sale rows are also **direction-coded** via `inventorySaleDirection`.
  - Canonical id format: `SALE_<projectId>_<direction>_<budgetCategoryId>`.
  - Sources:
    - `40_features/project-transactions/feature_spec.md` (canonical sale definitions + filters)
    - `40_features/project-items/feature_spec.md` (guards for `budgetCategoryId` on items)

- **Prior data doc mismatch**
  - Legacy docs referenced `INV_PURCHASE_*` and “item-driven attribution,” which conflicts with the new canonical sale model.

- **Resolution**
  - Canonical **sale-only** semantics are now explicit in `20_data/data_contracts.md` → **Entity: Transaction**:
    - `budgetCategoryId` is required for canonical inventory sale rows (category-coded invariant).
    - `inventorySaleDirection` is required for canonical inventory sale rows (direction-coded invariant).

### 2) Roles v2 requires server-enforceable selectors (no “download everything then filter”)

- **Spec truth**
  - Items require `createdBy` to support scoped-user visibility for uncategorized items (`budgetCategoryId == null`).
  - Canonical **sale** transactions are category-coded, so visibility can use `transaction.budgetCategoryId` like non-canonical rows.
  - Sources:
    - `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md`

- **Prior data doc mismatch**
  - Prior drafts added special selector fields for canonical rows based on item joins (no longer needed under the new canonical sale model).

- **Resolution**
  - `20_data/data_contracts.md` → **Entity: Item** keeps:
    - `createdBy` (security field required by Roles v2)
    - `budgetCategoryId` (stable selector)
  - Canonical transaction **item-join selector fields** are removed from the contracts; canonical visibility uses `budgetCategoryId` like other transactions.
  - Note: SQLite is no longer described as a mirrored local DB; any local indexing is TBD and must be justified by an explicit feature requirement.

### 3) Lineage is required offline (append-only edges + item pointers)

- **Spec truth**
  - Must append lineage edges on cross-scope operations.
  - Must maintain item pointers (`latestTransactionId`, optionally `originTransactionId`).
  - Lineage edges should be available offline (intentional delta vs web).
  - Sources:
    - `40_features/inventory-operations-and-lineage/feature_spec.md`
    - `40_features/inventory-operations-and-lineage/flows/lineage_edges_and_pointers.md`

- **Prior data doc mismatch**
  - Prior drafts treated lineage as “nice to have” rather than a first-class, queryable entity with a stable Firestore location across scope moves.

- **Resolution**
  - `20_data/data_contracts.md` adds **Entity: LineageEdge** and item lineage pointer fields.
  - Lineage edges are stored in an account-wide Firestore collection (`accounts/{accountId}/lineageEdges/{edgeId}`) so history survives scope moves. Firestore native offline persistence provides offline availability.

### 4) Offline media lifecycle requires embedded `offline://` placeholders (spec-aligned)

- **Spec truth**
  - Attachments must support the UI state machine: `local_only`, `uploading`, `uploaded`, `failed`.
  - Must support images + PDFs, and offline placeholders via `offline://<mediaId>`.
  - PDF-vs-image must be explicit on the persisted attachment ref (do not infer from URL).
  - Sources:
    - `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
    - `40_features/project-transactions/feature_spec.md` (receipts and other attachments)

- **Prior data doc mismatch**
  - Prior drafts modeled separate attachment documents and de-emphasized embedded arrays, conflicting with feature specs that explicitly reference embedded fields like `transaction.receiptImages[]` and `space.images[]`.

- **Resolution**
  - Canonical decision: media is represented as **embedded `AttachmentRef` values** on the owning entity, with `offline://<mediaId>` placeholders allowed (`20_data/data_contracts.md` → “Embedded media references”).
    - `AttachmentRef.kind = "image" | "pdf"` is required (explicit PDF-vs-image).
    - Transient upload state is **local + derived** (not persisted on the Firestore domain entity).
  - TBD: whether we also add separate Firestore attachment docs as an optimization (must be additive and cannot replace the embedded contract without updating feature specs).

### 5) Money representation for Items/Transactions was inconsistent across docs

- **Spec truth**
  - Rollups treat money as two-decimal currency semantics and require consistent rounding.
  - Sources:
    - `40_features/budget-and-accounting/feature_spec.md` (money normalization + rollups)

- **Prior data doc mismatch**
  - Prior drafts mixed string money and numeric money across docs.

- **Resolution**
  - Canonical decision in `20_data/data_contracts.md`: **persist money as integer cents** for Items + Transactions (Option B), including explicit parsing/rounding expectations for migration/import boundaries.
  - SQLite is no longer specified as a full mirrored schema; any numeric storage there is strictly derived/index-only.

## Intentional deltas (with rationale + blast radius)

### A) Lineage edges stored in an account-wide Firestore collection

- **Decision**
  - Store lineage edges at `accounts/{accountId}/lineageEdges/{edgeId}` (not under project/inventory scope collections).

- **Rationale**
  - Items physically move between project scope and inventory scope collections; storing lineage under an item subcollection would risk losing history or requiring copy-on-move.

- **Blast radius**
  - Security rules must enforce lineage visibility via linked item/transaction selectors.
  - Scoped listeners must include lineage edges relevant to visible items/transactions (exact listener/query strategy is TBD and should be derived from the lineage feature flows).

## Open decisions / questions (not resolvable from specs alone)

### 1) Canonical sale rows and Roles v2 selectors

The new canonical sale model removes the need for item-join selector fields on canonical transactions. Roles v2 visibility can use `transaction.budgetCategoryId` for canonical sale rows just like non-canonical transactions.

### 2) Embedded media URL timing (placeholder → remote)

Feature specs require `offline://` placeholders to render immediately and later resolve to remote URLs.

Open decision:
- When (and how) do we patch embedded arrays from `offline://<mediaId>` to a remote URL, and what (if any) additional **stable** metadata is persisted alongside `AttachmentRef.url` (e.g. `contentType`)?

