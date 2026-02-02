# Budget + Accounting (project rollups) — Feature spec (Firebase mobile migration)

## Intent
Provide fast, trustworthy **budget progress** and **accounting rollups** inside a project that:

- render from **Firestore-cached project data** (Firestore is canonical; Firestore-native offline persistence is the baseline)
- remain usable **offline** (cache-first reads; rollups computed from locally cached docs)
- do **not** require users to learn “canonical categories” for inventory mechanics

This spec explicitly **deviates** from the current web implementation for canonical attribution; see “Canonical attribution” below.

## Definitions

- **Budget category preset**: account-scoped category entity the user manages in Settings.
- **Project category budgets**: per-project allocation docs under `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}` (one doc per preset category id).
- **Pinned budget categories**: per-user per-project ordered list of pinned budget category ids.
  - Source of truth contract: `20_data/data_contracts.md` → **Entity: ProjectPreferences**
  - Primary use: drives the collapsed Budget view and Projects list budget preview subset.
- **Fee category**: a budget category preset where `budgetCategory.metadata.categoryType === "fee"`.
  - Fee categories have special semantics in the Budget UI: they are tracked as **received** (not spent).
- **Excluded-from-overall category**: a budget category preset where `budgetCategory.metadata.excludeFromOverallBudget === true`.
  - Excluded-from-overall categories are excluded from:
    - “spent overall” totals
    - the overall budget denominator
  - Default: categories are included in overall rollups.
- **Non-canonical transaction**: user-facing transaction where budget category attribution is transaction-driven via `transaction.budgetCategoryId` (Firestore).
- **Canonical inventory transaction**: system row whose id begins with `INV_PURCHASE_` or `INV_SALE_`.
  - Note: “project → project” movement is modeled as a **two-phase** operation (`INV_SALE_<sourceProjectId>` then `INV_PURCHASE_<targetProjectId>`), not a standalone “transfer” canonical transaction.

Canonical working doc (source of truth):
- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`

## Core model decisions (required)

### 1) Fee categories have special semantics
- **Budget source**: the project’s per-category allocation for that category:
  - `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}.budgetCents`
- **Progress semantics**: “received”, not “spent”
- **Stable identifier**: fee specialness is keyed by a stable, explicit type (`budgetCategory.metadata.categoryType === "fee"`), not by the category name string.
  - Intentional delta vs web: web uses name heuristics in `src/components/ui/BudgetProgress.tsx`.

Mutual exclusivity invariant:
- A category MUST NOT be both fee and itemized.
- Enforced structurally by a single `categoryType` field (see `20_data/data_contracts.md`).

### 2) Categories may be excluded from overall rollups
Categories are included in overall rollups by default. A category is excluded only when:
- `budgetCategory.metadata.excludeFromOverallBudget === true`

Excluding a category removes it from:
- “spent overall” totals
- the overall budget denominator

Note:
- Fee categories are still categories; they may be excluded from overall via this same flag.

### 3) Canonical inventory transactions must not require a user-facing budget category
Canonical rows exist for inventory correctness (allocation / sale / deallocation), not for user budgeting.

Recommendation (preferred):
- Canonical inventory transactions keep `budgetCategoryId = null` (uncategorized).

Schema-compatibility fallback:
- A hidden/internal “canonical system” category may exist, but **rollups must ignore it** for attribution.

### 4) Canonical vs non-canonical attribution (the core deviation)

#### Non-canonical attribution (transaction-driven)
- Budget category attribution comes from `transaction.budgetCategoryId`.

#### Canonical inventory attribution (item-driven) — required
- Canonical inventory transactions are attributed by **items linked to the canonical transaction**, grouped by:
  - `item.inheritedBudgetCategoryId`

Source of truth:
- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`
- `40_features/project-items/flows/inherited_budget_category_rules.md`

Intentional delta (vs web):
- Web budget rollups group canonical transactions by transaction category, not item categories (`src/components/ui/BudgetProgress.tsx`).

## Owned UI surface (project context)

### Project header budget module (above tabs)
The project shell exposes a compact **Budget module** (not a tab) that sits **above** the primary project tabs and provides budget progress at-a-glance.

### Project shell accounting tab
The project shell exposes an **Accounting** tab that contains rollups + report entrypoints (and may include a “View full budget” entrypoint if/when a dedicated budget screen exists).

Web parity evidence:
- `src/pages/ProjectLayout.tsx` (`budgetTabs`, `activeBudgetTab`, BudgetProgress render, accounting cards and report buttons)

### Project list preview
Projects list shows a compact “budget progress preview” for each project.

Web parity evidence:
- `src/pages/Projects.tsx` (uses `BudgetProgress` in preview mode)

## Budget rollups (Budget module)

### Inputs (Firestore cached reads; project-scoped)
All rollups are computed from Firestore-cached reads within the active project scope:
- Project category budgets:
  - `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`
- Budget category presets (account-scoped):
  - `accounts/{accountId}/presets/default/budgetCategories/{budgetCategoryId}`
- Transactions (project-scoped):
  - `accounts/{accountId}/transactions/{transactionId}` with `transaction.projectId = <projectId>`
- Items (project-scoped):
  - `accounts/{accountId}/items/{itemId}` with `item.projectId = <projectId>` and `item.inheritedBudgetCategoryId`

### Money normalization
All persisted currency amounts are **integer cents** per `20_data/data_contracts.md` (e.g. `amountCents`, `purchasePriceCents`).

- UI converts cents ↔ display decimals.
- Any parsing of decimal strings (imports) must be deterministic and must not silently store floats.

### Transaction inclusion rules
- Exclude `status === 'canceled'`.
- Overall spent excludes categories where `excludeFromOverallBudget === true` (including fee categories if they are marked excluded).

### Overall “spent” (excluding excluded-from-overall categories)
Overall spent is computed as:

- Sum over all **non-canceled** transactions excluding transactions whose category is marked `excludeFromOverallBudget === true`:
  - Purchases add
  - Returns subtract
  - Canonical purchases add (inventory purchase increases “spent”)
  - Canonical sales subtract (inventory sale reduces “spent”)

Note:
- For canonical `INV_*` rows, the authoritative amount comes from linked item values (see “Spend per category (canonical inventory transactions)”) rather than `transaction.amountCents`.

Web parity note:
- Web currently uses:
  - `transactionType === 'Return'` as subtract
  - `transactionId.startsWith('INV_SALE_')` as subtract
  - and excludes “design fee” (web naming) by category-name heuristic (`BudgetProgress.calculateSpent`)

Firebase migration requirement:
- Identify fee categories by explicit type, not name matching.
- Identify excluded-from-overall categories by explicit boolean flag, not name matching.

### Category breakdown (budget category spend)

#### Enabled category set
- Categories are “enabled” for budgeting in a project when:
  - a per-project budget doc exists for `(projectId, budgetCategoryId)` (regardless of `budgetCents`), OR
  - the category has non-zero attributed spend (so users can see where money went even if budget not set).

#### Spend per category (non-canonical transactions)
For each non-canonical transaction with `categoryId`:
- Add `amount` with sign:
  - `+1` for purchases
  - `-1` for returns

#### Spend per category (canonical inventory transactions) — required
For each canonical inventory transaction:

1) Determine the set of linked items (client-side join by `item.transactionId === transaction.transactionId`).
2) For each linked item, compute its “canonical value”:
   - `item.projectPriceCents ?? item.purchasePriceCents ?? item.marketValueCents ?? 0`
   - (matches existing canonical totals logic in `src/services/inventoryService.ts`)
3) Group items by `item.inheritedBudgetCategoryId` and sum values per group.
4) Apply canonical sign:
   - `INV_PURCHASE_*`: `+1`
   - `INV_SALE_*`: `-1`
   - Transfers are represented by sale+purchase canonical rows (no separate transfer row).

Important:
- Canonical attribution must **not** consult `transaction.budgetCategoryId` even if populated (schema-compatibility fallback).

### Overall budget (budget denominator)
Overall budget is computed as:
- `sum(projectBudgetCategory.budgetCents)` over all per-project budget category docs for the active project (treat missing/NULL as 0), excluding categories where `excludeFromOverallBudget === true`.

Note:
- The legacy `project.budget` field (if present) must not be treated as authoritative if category budgets exist; overall rollups should be category-sum-driven.
  - Parity evidence: web computes overall as sum of category budgets in `BudgetProgress` (`overallFromCategories`).

### Budget module UI behavior (high-level)
- **Collapsed**: show **only** the pinned budget category trackers (per-user per-project pins).
  - If **no pins exist**, collapsed view shows **Overall Budget only** (deterministic fallback).
- **Expanded**: show the full enabled category list (including fee trackers as applicable) plus the Overall Budget row.
- Pin/unpin affordance: the user can pin/unpin categories from within the Budget UI (exact affordance is implementation-defined; the behavior is the contract).

Parity evidence:
- `src/components/ui/BudgetProgress.tsx` (toggle behavior, overall budget row placement)

## Fee rollups (Budget tab)

### Fee received (per fee category)
Fee “received” is computed for each fee category preset (each `budgetCategoryId` where `metadata.categoryType === "fee"`):

- **Budget**: the per-project allocation for that category:
  - `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}.budgetCents` (treat missing/NULL as 0)
- **Received**: sum of non-canceled transactions where `transaction.budgetCategoryId === budgetCategoryId`:
  - purchases add
  - returns subtract
- **Remaining**: `feeBudget - received`

Stable identifier requirement:
- Fee categories are identified by `budgetCategory.metadata.categoryType === "fee"` (not by name matching).

## Accounting rollups (Accounting tab)

### Owed rollups
Accounting shows two rollups computed from project-scoped transactions:

- **Owed to Design Business**: sum of non-canceled transactions where `reimbursementType === CLIENT_OWES_COMPANY`
- **Owed to Client**: sum of non-canceled transactions where `reimbursementType === COMPANY_OWES_CLIENT`

Parity evidence:
- `src/pages/ProjectLayout.tsx` (`owedTo1584`, `owedToClient`)
- Constants:
  - `src/constants/company.ts`

### Report entrypoints
Accounting includes buttons/links to:
- Invoice
- Client Summary
- Property Management Summary

This feature owns only the **entrypoints**; report generation behavior is owned by `reports-and-printing`.

Parity evidence:
- `src/pages/ProjectLayout.tsx` (report buttons + routes)

## Offline-first + collaboration constraints (Firebase target)
- Firestore is canonical; rollups are computed from **locally cached Firestore docs** (no network required to render last-known data).
- While a project is foregrounded, data freshness comes from **scoped/bounded listeners** (and/or explicit refresh) within that project scope. Avoid unbounded “listen to everything” listeners; follow `OFFLINE_FIRST_V2_SPEC.md`.
- Inventory canonical mechanics that affect rollups (e.g., `INV_*` buckets) are produced by **server-owned request-doc workflows** (see `40_features/inventory-operations-and-lineage/`), and rollups should reflect `pending/applied/failed` request status where applicable.

Canonical source:
- `OFFLINE_FIRST_V2_SPEC.md`
