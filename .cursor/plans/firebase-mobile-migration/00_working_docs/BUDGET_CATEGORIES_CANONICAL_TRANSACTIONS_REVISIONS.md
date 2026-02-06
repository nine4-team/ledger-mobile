## Budget Categories Vision (Firebase Migration Working Doc)

Audience: internal implementation/design discussion for the Firebase migration (not a final spec).

### Goals

- **Simple defaults**: Works out of the gate for interior designers with no “concept learning.”
- **Accurate budget progress**: Category budgets reflect reality even with Business Inventory and canonical system rows.
- **Flexible item categorization**: Teams can budget across multiple item buckets (e.g., Furniture + Accessories).
- **Separation of concerns**: Users budget/categorize work; the system maintains canonical rows for inventory integrity.

---

### Current building blocks (existing app model)

- **Account-scoped budget categories**: managed in Settings; projects reference them by id.
- **Project budgets**:
  - Per-project allocations live as one doc per preset category id:
    - `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}` (allocation-only; no name duplication)
  - Fee categories (`budgetCategory.metadata.categoryType === "fee"`) have special UI semantics (“received” vs “spent”).
  - Categories are included in overall rollups by default; exclusion is explicit via `budgetCategory.metadata.excludeFromOverallBudget === true`.
- **Transactions**:
  - Canonical (mobile/Firebase): `transaction.budgetCategoryId` (Firestore) / `transactions.budget_category_id` (SQLite)
  - Legacy web naming (historical): `transactions.category_id` and legacy `transactions.budget_category` (string)
- **Canonical inventory sale transactions (new model)**:
  - System-generated **sale** rows that represent cross-scope moves and track direction explicitly:
    - `business_to_project` (Business Inventory → Project)
    - `project_to_business` (Project → Business Inventory)
  - Each canonical sale transaction is **category-coded** (exactly one `budgetCategoryId`).
  - These rows represent inventory allocation / deallocation mechanics (not user-entered).
  - Note: “project → project” movement is modeled as **two hops**:
    - Project A → Business Inventory (`project_to_business`)
    - then Business Inventory → Project B (`business_to_project`)

---

### Vision decisions

#### 1) Fee categories stay special (user-facing)

- **Budget source**: the project’s per-category allocation for that category (`projects/{projectId}/budgetCategories/{feeCategoryId}.budgetCents`)
- **Progress semantics**: “received”, not “spent”
- **Overall budget**: categories are included by default; excluded categories (via `excludeFromOverallBudget`) are removed from “spent overall” and the overall budget denominator.

Implementation note: the specialness should be bound to a stable identifier (slug/metadata), not a mutable display name.

#### 2) Canonical inventory sale transactions are category-coded and direction-coded

Canonical rows exist for inventory correctness and reconciliation. Users should not have to think about “canonical categories,” but the system still needs canonical rows to land in the *right* budget categories without complex attribution rules.

Therefore, canonical inventory rows are **sale transactions** that are:

- **direction-coded** (Business Inventory → Project vs Project → Business Inventory)
- **category-coded** (each canonical row has exactly one `budgetCategoryId`)
- **split per category** (so mixed-category items do not share a canonical row)

This implies an upper bound per project: **2 × (# enabled budget categories)** canonical system sale transactions.

#### 3) Canonical vs non-canonical attribution rule (revised)

- **Non-canonical transactions**: category attribution comes from `transaction.budgetCategoryId` (status quo; legacy web naming: `transactions.category_id`).
- **Canonical inventory sale transactions**: category attribution comes from the canonical transaction’s own `budgetCategoryId`.

Budget progress becomes simpler: it can compute per-category spend from transactions directly (including canonical system sale rows), applying sign rules based on direction.

---

### Data we need on items (for correctness + prompts)

Each item must have a stable **item-owned budget category id** field (currently named `inheritedBudgetCategoryId` in the migration docs/data contracts).

Semantics (revised):
- The field is **not strictly inherited**. It may be set by:
  - linking an item to a non-canonical categorized transaction (inherit)
  - an explicit user choice during a sell/allocation prompt (direct assignment)
- The field persists across scope moves so future canonical moves are deterministic.

---

### Guardrail: Project → Business Inventory (sell/deallocate)

Constraint (required):
- If the item’s budget category id is missing, **prompt the user to select a category from the source project**, persist it onto the item, then proceed.

On successful move to Business Inventory:
- Item keeps its `inheritedBudgetCategoryId`.

Why:
- Canonical system rows are split by category, so the system must know which category’s canonical sale row to apply.

---

### Business Inventory → Project (sell/allocate) — “mismatch” concern

Concern:
- The Business Inventory “intake” transaction category might not match the destination project’s budgets or the way the project wants to track spend.

Resolution (final):
- Canonical system rows are category-coded; therefore BI → Project must ensure the item has a valid destination project category.
- **At BI → Project sell/allocation time, if the item’s current category is not enabled/available in the destination project, prompt the user to choose a destination-project budget category** for the item (or batch), persist it onto the item, then proceed.

Defaulting behavior for the prompt:
- If the item already has a category id and that category is enabled/available for the destination project, use it (no prompt required).
- Otherwise, leave unselected and require a choice.

Persistence:
- On successful allocation, set/update the item’s category id field (currently `inheritedBudgetCategoryId`) to the user’s chosen destination category so future moves remain deterministic.

Batch behavior (recommended):
- One category choice applies to the whole batch (fast path).
- (Optional later) advanced “split per item” if needed.

---

### Canonical sale transaction identity (deterministic)

Canonical sale transactions must have a deterministic identity so retries and concurrent clients converge without creating duplicates.

Required identity inputs:
- `projectId`
- `direction`: `business_to_project` or `project_to_business`
- `budgetCategoryId`

Recommended id format (implementation-defined but must be deterministic and parseable):
- `INV_SALE__<projectId>__<direction>__<budgetCategoryId>`

Additionally required on the transaction doc (recommended even if direction is encoded in the id):
- `isCanonicalInventorySale: true`
- `inventorySaleDirection: "business_to_project" | "project_to_business"`
- `budgetCategoryId: <budgetCategoryId>` (the category-coded invariant)

---

### UX guidance

- Avoid introducing “roles” as a user-facing concept.
- Use language like:
  - “Used for fee”
  - “Used for item purchases & sales” (if surfaced at all; keep under “Advanced”)
- Prefer “pinning” budget trackers in collapsed views over any single-category “featured tracker” concept.

