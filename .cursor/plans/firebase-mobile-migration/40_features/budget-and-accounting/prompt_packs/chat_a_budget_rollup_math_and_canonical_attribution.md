# Chat A — Budget rollup math + canonical inventory sales (direction-coded)

## Goal
Specify and/or implement the budget rollup computation layer for the Firebase mobile app (Firestore is canonical; Firestore-native offline persistence), with the **canonical inventory sale direction model**.

## Critical constraints (must obey)
- UI reads from Firestore-cached data; rollups must be derivable offline via Firestore-native offline persistence (`OFFLINE_FIRST_V2_SPEC.md`).
- Canonical inventory sale transactions are system-owned, **category-coded** (via `transaction.budgetCategoryId`), and **direction-coded** (via `inventorySaleDirection`).
  Rollups attribute canonical rows by `transaction.budgetCategoryId` and apply sign by direction.
  Source of truth: `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`

## Exact output files
Update only:
- `40_features/budget-and-accounting/feature_spec.md`
- `40_features/budget-and-accounting/acceptance_criteria.md`

If you need a shared contract doc (only if necessary), add:
- `40_features/_cross_cutting/budget_rollup_query_contract.md`

## What to produce
- A deterministic definition of:
  - overall spent (excluding categories marked `excludeFromOverallBudget`)
  - per-category spent (non-canonical + canonical)
  - overall budget denominator (sum of project category budgets)
- A Firestore query strategy sufficient to implement rollups from transactions directly, including canonical inventory sale transactions with direction sign.

Also cover these spec-required behaviors (do not omit):
- **Pinned categories subset + fallback**:
  - Collapsed Budget view shows **only** the per-user per-project pinned category trackers.
  - Project list preview uses the **same** pinned subset.
  - If **no pins exist**, both collapsed + preview show **Overall Budget only**.
  - Source of truth: `20_data/data_contracts.md` → Entity `ProjectPreferences` (`pinnedBudgetCategoryIds`).
- **Enabled category set rule**:
  - A category appears in the expanded list if a per-project budget doc exists **OR** it has non-zero attributed spend (even if no budget is set).
- **Canonical overall spent uses canonical transaction amount**:
  - For canonical inventory sale rows, overall spent uses `transaction.amountCents` with sign based on `inventorySaleDirection`.
  - `transaction.amountCents` is system-computed from linked items by inventory invariants.
- **Two-hop cross-project movement**:
  - There is no standalone “transfer” canonical transaction; movement is modeled as:
    - `project_to_business` (Project A → Business Inventory)
    - then `business_to_project` (Business Inventory → Project B)
  Rollups apply direction sign independently per hop.

## Parity evidence (web sources)
- Current budget rollup UI + math (note: we are intentionally deviating for canonical attribution):
  - `src/components/ui/BudgetProgress.tsx`
  - `src/components/ui/__tests__/BudgetProgress.test.tsx`
- Canonical transaction totals derive from item values:
  - `src/services/inventoryService.ts` (`computeCanonicalTransactionTotal`)

## Evidence rule
For each non-obvious behavior, include either:
- **Parity evidence**: “Observed in …” with file path + function/component, OR
- **Intentional delta**: explicitly state what changes and why (reference the working doc).

