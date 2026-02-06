# Feature spec: Project Items (Firebase mobile migration)

This spec defines **Project Items** behavior for the React Native + Firebase app, with explicit rules for:

- **Canonical inventory transactions** vs **user-facing (non-canonical) transactions**
- **Budget-category attribution** (how budget rollups attribute spend)
- The required item field **`inheritedBudgetCategoryId`** (where it comes from, when it changes, and what breaks if missing)

When current web behavior differs from the desired Firebase policy, it is labeled as an **Intentional delta**.

## Shared module requirement (Project + Business Inventory)

Items must be implemented as a **shared domain module + shared UI primitives** reused across:

- Project workspace context
- Business inventory workspace context

This spec is authored from the project entrypoints, but it is also the **canonical contract** for shared Item components/flows that must be reused in business-inventory scope (with scope-driven configuration, not duplicated implementations).

Source of truth:

- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`
  - See also: “Scope config object (contract)” (single config object consumed by shared Items + Transactions UI across project + inventory scopes)

## Routing / screens (mobile; required)

The Firebase mobile app may have different **wrapper routes** for Project vs Business Inventory, but it must render a **single shared implementation** for:

- Items list
- Item detail
- Item create/edit form

Those shared screens/components must be configured via the `ScopeConfig` contract:

- Project wrapper routes pass `ScopeConfig = { scope: 'project', projectId }`
- Business-inventory wrapper routes pass `ScopeConfig = { scope: 'inventory' }`

Anti-goal (explicit):

- Do **not** implement separate `ProjectItemDetail` vs `BusinessInventoryItemDetail` screens/components that diverge over time. Scope-specific deltas belong in scope-config and the scope screen contracts (e.g. search fields, allowed actions).

## Canonical contracts (where the “shared items object” is defined)

If you’re looking for the shared Item “object” / document shape, it is **not** redefined in this feature spec. It is defined in the canonical data contracts:

- **Item entity contract**: `20_data/data_contracts.md` → `## Entity: Item`

Canonical UI/screen contracts owned by this feature:

- Project items list: `40_features/project-items/ui/screens/ProjectItemsList.md`
- Item detail (shared module; project-scope guardrails): `40_features/project-items/ui/screens/ItemDetail.md`
- Item create/edit form (shared module): `40_features/project-items/ui/screens/ItemForm.md`

Inventory-scope deltas (config-only; do not fork implementations):

- Inventory Items scope config: `40_features/business-inventory/ui/screens/BusinessInventoryItemsScopeConfig.md`

---

## Scope

Project Items includes:

- Project items list (search/filter/sort/group, bulk select + bulk actions)
- Item detail (view/edit, images, transaction association, move/sell flows)
- Item action restrictions and user-facing messaging around cross-scope inventory operations

Out of scope (but referenced):

- Budget rollups UI (project budget screens)
- Business Inventory **workspace shell** screens (tabs/navigation). Item list/detail/actions must still reuse the shared Items module components per the shared-module contract.
- The server-owned multi-entity invariants for allocation/sale/deallocation (see “Architecture constraints”)

---

## Form validation + shared components (required)

### Validation (create/edit)

- An item is valid only if **at least one** of these is present:
  - `description` (non-empty)
  - `sku` (non-empty)
  - **at least one** image attachment
- If all three are missing, the form must block submission and show a clear inline error.

### Shared components (attachments + media)

- Image selection, preview, and placeholder handling must use the **shared media utilities/components** (no per-screen custom logic).
- The shared components must support:
  - `offline://<mediaId>` placeholders
  - remove + set-primary behavior
  - max counts (items: 5 images)

---

## Key definitions

### Non-canonical (user-facing) transaction

A normal user-entered transaction where budget category attribution is **transaction-driven**:

- Source-of-truth category selector: `transaction.budgetCategoryId`
  - Legacy naming notes: web/SQL docs may refer to this as `category_id`; the canonical SQLite column name is `budget_category_id` (see `20_data/data_contracts.md`).

Parity evidence (web):

- Transaction records carry `category_id` and legacy `budget_category` mapping (`src/services/inventoryService.ts`).

### Canonical inventory sale transaction (system)

A system-generated **sale** transaction used for inventory correctness across scope moves. Canonical inventory sale transactions are:

- **Direction-coded**: `business_to_project` or `project_to_business`
- **Category-coded**: `transaction.budgetCategoryId` is required and represents the single category for the transaction
- **Deterministic**: one canonical sale transaction per `(projectId, direction, budgetCategoryId)`
  - recommended id: `INV_SALE__<projectId>__<direction>__<budgetCategoryId>`

Note: “project → project” movement is modeled as **two hops**:
- Project A → Business Inventory (`project_to_business`)
- then Business Inventory → Project B (`business_to_project`)

Parity evidence (web):

- Canonical transaction id detection: `isCanonicalTransactionId` (`src/services/inventoryService.ts`).
- Web parity canonical sale creation uses `INV_SALE_<projectId>` (`src/services/inventoryService.ts`).
  Firebase migration delta: canonical sale ids are category-split and direction-coded (recommended `INV_SALE__<projectId>__<direction>__<budgetCategoryId>`).

---

## Canonical vs non-canonical budget attribution (required)

### Rule 1 — Non-canonical attribution is transaction-driven

- For **non-canonical** transactions, budget-category attribution comes from `transaction.budgetCategoryId`.

Source of truth (canonical working doc):

- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`

### Rule 2 — Canonical inventory sale attribution is transaction-driven

- For **canonical inventory sale transactions**, budget-category attribution comes from `transaction.budgetCategoryId`.
  (This is safe because the canonical sale transaction is single-category by invariant.)

Implications:
- Users do not “categorize the canonical row.” The canonical row is system-owned.
- The system may still need to prompt for an item’s category when it’s missing/mismatched, so it can choose the correct category-coded canonical sale row.

Source of truth (canonical working doc):

- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`

Intentional delta (vs current web):
- Web canonical inventory buckets are not split by category and use separate purchase/sale ids.
- Firebase migration uses **category-split canonical sale transactions** with explicit direction, so budget progress can compute directly from transactions per category.

---

## Required item field: `inheritedBudgetCategoryId` (item-owned category id)

### Field requirements

Every item must persist a stable `inheritedBudgetCategoryId` that:

- Represents the item’s **budget category id** used by canonical inventory sale mechanics.
- Is **stable across scope changes** (project ↔ business inventory).
- Is a **direct selector** for downstream systems (e.g., scoping/visibility in roles v2, budget rollups).

Source of truth:

- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`
- Compatibility note in feature list: `feature_list.md` calls out `item.inheritedBudgetCategoryId` as a denormalized selector.

### Where it comes from (set rules)

1) **Linking item to a user-facing transaction** sets `item.inheritedBudgetCategoryId`:

- When an item is linked/assigned to a **non-canonical** transaction that has `budgetCategoryId`, set:
  - `item.inheritedBudgetCategoryId = transaction.budgetCategoryId`

2) Canonical inventory sale operations may require direct assignment:
- When a sell/allocation prompt resolves a category (source or destination), persist:
  - `item.inheritedBudgetCategoryId = <chosenCategoryId>`

3) Unlinking from a transaction does **not** clear `item.inheritedBudgetCategoryId`:

- The field is “inherited historically” and should remain stable for deterministic attribution later.

### When it changes (update rules)

Business Inventory → Project allocation/sale may update the field:
- If the item’s current category is enabled/available in the destination project, keep it.
- Otherwise prompt the user to choose a **destination project budget category** and persist:
  - `item.inheritedBudgetCategoryId = <chosenDestinationCategoryId>`

Project → Business Inventory sell/deallocate may also require updating the field:
- If the item’s category is missing, prompt the user to choose a **source project budget category** and persist it before applying the sale.

Source of truth:

- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`

---

## Guardrails (required UI + behavior)

### Guardrail A — Project → Business Inventory requires a resolved category (prompt + persist)

If `item.inheritedBudgetCategoryId` is missing, do not block the sell.
Instead, prompt the user to select a category from the source project, persist it onto the item, then apply the sale.

This guardrail applies to all project → business inventory paths that would create/update canonical inventory rows:

- Item actions: “Sell to Design Business”
- Sell/deallocate action to Business Inventory (canonical deallocation trigger)

This guardrail does **not** apply to “Move to Design Business” when “move” is a pure correction that does not create canonical transactions. In that case, attribution determinism is not required at the moment of the correction (but will be required later for deallocation-like flows).

Source of truth:

- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`

Parity evidence (web paths that must be guarded in Firebase):

- Item detail “sell to business inventory” triggers deallocation: `integrationService.handleItemDeallocation` (`src/pages/ItemDetail.tsx`).
- Project items list “sell/deallocate to business inventory” triggers deallocation: `integrationService.handleItemDeallocation` (`src/pages/InventoryList.tsx`).
- “Move to business inventory” exists as a separate correction path that only updates the item’s scope and does not create canonical transactions: `moveItemToBusinessInventory` (`src/services/inventoryService.ts`).

Intentional delta (vs current web):
- The web UI does not have this item category field yet; mobile will prompt/persist when needed.

### Guardrail B — Business Inventory → Project requires conditional category prompt

At BI → Project allocation/sale time:
- If `item.inheritedBudgetCategoryId` is enabled/available in the destination project, do not prompt.
- Otherwise, prompt the user to choose a **destination project budget category**.

Defaulting:
- If a valid category exists on the item, preselect it.
- Otherwise, require a selection.

Batch behavior:

- One category choice applies to the whole batch (fast path).

Persistence:
- As part of the operation, set/update `item.inheritedBudgetCategoryId` to the chosen category.

Source of truth:

- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`

Intentional delta (vs current web):

- The current web “sell/move to project” flows prompt only for project selection and do not prompt for a destination budget category (`src/pages/ItemDetail.tsx`, `src/pages/InventoryList.tsx`).

---

## Rollup logic note (no new UI in this feature)

Budget rollups are owned by `budget-and-accounting`, but Project Items must remain consistent with the rollup model:
- Non-canonical transactions: category attribution comes from `transaction.budgetCategoryId`.
- Canonical inventory sale transactions: category attribution also comes from `transaction.budgetCategoryId` (category-coded invariant), with sign based on direction.

This replaces the older “group canonical items by item category id” approach.

---

## Architecture constraints (must hold)

All Firebase/RN implementations must follow:

- Offline data v2 architecture: `OFFLINE_FIRST_V2_SPEC.md`
  - Firestore (native RN SDK) is the canonical datastore with offline persistence.
  - Scoped listeners are allowed (and required to be bounded); we do **not** build a bespoke “outbox + delta sync engine” in this repo.
  - SQLite is allowed only as an **optional derived search index** (non-authoritative), if the product requires robust offline multi-field search.
- Multi-entity correctness must be enforced as **server-owned invariants** for allocation/sale/deallocation using the **request-doc workflow** (Cloud Function applies the change in a Firestore transaction), not UI-only.
  - Idempotency: every request doc must include an `opId` that the server uses to de-dupe retries. (`requestId` is the Firestore doc id for a single attempt.)
  - Retry model: default retry is **create a new request doc** (do not mutate a previously-applied request).
  - UX contract: request docs must expose `status: pending|applied|failed|denied` (and error info) so the UI can show queued/applied/failed/denied states.

Implications for this spec:

- `inheritedBudgetCategoryId` must be a first-class field in the **item document** (it is authoritative and must sync).
- Cross-scope operations that set/update `inheritedBudgetCategoryId` must be **atomic with the scope move** so retries are safe and deterministic (i.e., part of the same server-owned invariant operation).

