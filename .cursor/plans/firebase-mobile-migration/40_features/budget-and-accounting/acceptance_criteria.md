# Budget + Accounting — Acceptance criteria (parity + Firebase deltas)

Each non-obvious criterion includes **parity evidence** (web code pointer) or is labeled **intentional delta** (Firebase mobile requirement / new model).

## Budget tab — budget progress

- [ ] **Renders budget progress inside a project** (Budget sub-tab), derived from local data only.  
  Observed entrypoint in `src/pages/ProjectLayout.tsx` (renders `BudgetProgress`).
- [ ] **Excludes canceled transactions** from all rollups.  
  Observed in `src/components/ui/BudgetProgress.tsx` (filters out `status === 'canceled'`).
- [ ] **Overall budget denominator is the sum of per-category budgets** (excluding categories marked `excludeFromOverallBudget`).  
  Observed in `src/components/ui/BudgetProgress.tsx` (`overallFromCategories`).
- [ ] **Purchases add and returns subtract** in spend totals.  
  Observed in `src/components/ui/BudgetProgress.tsx` (multiplier for `transactionType === 'Return'`).
- [ ] **Canonical inventory sales apply sign by direction** in spend totals:
  - `inventorySaleDirection === "business_to_project"` adds
  - `inventorySaleDirection === "project_to_business"` subtracts
  Web parity evidence (old model): `src/components/ui/BudgetProgress.tsx` uses `INV_SALE_*` multiplier -1.

## Canonical attribution (required model; main intentional delta)

- [ ] **Canonical inventory sale transactions are category-coded + direction-coded**:
  - `transaction.budgetCategoryId` is populated (single-category invariant)
  - `inventorySaleDirection` is populated (`business_to_project` or `project_to_business`)
  Source of truth: `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`.
- [ ] **Non-canonical attribution is transaction-driven**: category attribution comes from `transaction.budgetCategoryId`.  
  Source of truth: `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`.
- [ ] **Canonical inventory sale attribution is transaction-driven**: canonical inventory sale transactions are category-coded, so attribution comes from `transaction.budgetCategoryId` with sign from `inventorySaleDirection`.
  Source of truth: `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`.
- [ ] **Canonical inventory sale amount is authoritative**: rollups use `transaction.amountCents` for canonical inventory sale rows (system-computed by inventory invariants).
- [ ] **Cross-project movement uses a two-hop canonical model**: there is no standalone “transfer” transaction; movement is represented as:
  - Project A → Business Inventory (`project_to_business`)
  - then Business Inventory → Project B (`business_to_project`)
  Rollups apply the direction sign rules to each hop.
  Source of truth: `40_features/budget-and-accounting/feature_spec.md` and `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`.

## Fee tracker categories (special semantics)

- [ ] **Fee category progress is “received”, not “spent”**.  
  Source of truth: `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`.
- [ ] **Fee category budgets come from per-category project allocations** (not from a dedicated `project.designFee*` field).  
  Source of truth: `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`.
- [ ] **Categories are included in overall rollups by default**; exclusion is explicit via `budgetCategory.metadata.excludeFromOverallBudget === true`.  
  Source of truth: `20_data/data_contracts.md` and `40_features/budget-and-accounting/feature_spec.md`.
- [ ] **Excluded-from-overall categories are excluded from overall spent and overall budget denominator**.  
  Parity evidence: `src/components/ui/BudgetProgress.tsx` excludes “design fee” (web naming) from overall spent and overall budget sum (legacy behavior now generalized).
- [ ] **Fee categories are identified by explicit type metadata** (not mutable display name matching).  
  **Intentional delta** vs web: web uses name heuristic (`isDesignFeeCategory`) in `src/components/ui/BudgetProgress.tsx`.
- [ ] **Mutual exclusivity**: a budget category cannot be both `fee` and `itemized`.  
  Source of truth: `20_data/data_contracts.md` (`BudgetCategory.metadata.categoryType` is a single field).

## Budget UI behavior (high-level parity)

- [ ] **Pinned categories drive collapsed view**: collapsed Budget view shows **only** the per-user per-project pinned category trackers.  
  If **no pins exist**, collapsed shows **Overall Budget only** (deterministic fallback).  
  **Intentional delta**: replaces any “single default/featured category” behavior with per-user pinned categories (source of truth: `20_data/data_contracts.md` → `ProjectPreferences.pinnedBudgetCategoryIds`).
- [ ] **Expanded shows full set**: “Show all budget categories” expands to the full enabled category list and shows the Overall Budget row.  
  Parity evidence: `src/components/ui/BudgetProgress.tsx` (toggle + overall budget row placement).
- [ ] **Project list preview uses same pinned subset**: project cards show a compact budget progress preview using the same pinned categories subset as the collapsed Budget view.  
  If **no pins exist**, preview shows **Overall Budget only** (same deterministic fallback as collapsed).  
  Parity evidence: `src/pages/Projects.tsx` (uses `BudgetProgress` preview mode).  
  **Intentional delta**: preview subset is per-user pinned categories, not a hard-coded category concept.

## Accounting tab — rollups + report entrypoints

- [ ] **Accounting rollups render inside the project budget section** (Accounting sub-tab).  
  Observed in `src/pages/ProjectLayout.tsx` (`budgetTabs`, `activeBudgetTab === 'accounting'`).
- [ ] **Owed to Design Business** equals sum of non-canceled transactions with `reimbursementType === CLIENT_OWES_COMPANY`.  
  Observed in `src/pages/ProjectLayout.tsx` (`owedTo1584`) and `src/constants/company.ts`.
- [ ] **Owed to Client** equals sum of non-canceled transactions with `reimbursementType === COMPANY_OWES_CLIENT`.  
  Observed in `src/pages/ProjectLayout.tsx` (`owedToClient`) and `src/constants/company.ts`.
- [ ] **Report buttons exist** for Invoice, Client Summary, and Property Management Summary.  
  Observed in `src/pages/ProjectLayout.tsx` (report buttons).  
  Note: report behavior is owned by `reports-and-printing`.

## Firebase/offline-first constraints

- [ ] **Rollups render correctly offline** from **Firestore-native offline persistence** (cache-first reads; no network required to render last-known data).  
  **Intentional delta** required by `OFFLINE_FIRST_V2_SPEC.md` (Firestore is canonical; offline persistence is baseline).
- [ ] **Scoped listeners only**: if listeners are used, they are bounded to the active project scope and detach on background.  
  **Intentional delta** required by `OFFLINE_FIRST_V2_SPEC.md` (no unbounded “listen to everything” listeners).
