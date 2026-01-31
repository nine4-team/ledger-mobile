---
name: Firestore Project budgets contract cleanup
overview: Sanity-check and update the Project-related data contracts to be Firestore-native (no JSON/map budgetCategories on the Project doc), then update all dependent feature specs so contracts and specs stay aligned.
todos:
  - id: contract-project
    content: Update `20_data/data_contracts.md` Project budgeting fields; add per-project budget entity + Firestore path.
    status: pending
  - id: firestore-model
    content: Update `20_data/firebase_data_model.md` to replace embedded map with `projects/{projectId}/budgetCategories/{budgetCategoryId}`.
    status: pending
  - id: sqlite-schema
    content: Update `20_data/local_sqlite_schema.md` to remove project JSON budget column and add a dedicated table + indexes.
    status: pending
  - id: feature-specs
    content: Update `40_features/budget-and-accounting/feature_spec.md` and `40_features/projects/feature_spec.md` to consume the new contract and avoid restating field lists.
    status: pending
  - id: consistency-sweep
    content: Repo-wide sweep for remaining mentions of the old map field; update specs/docs to prevent drift.
    status: pending
isProject: false
---

## Goal

Align the **Project budgeting shape** with Firestore best practices and your offline-first sync constraints by using **one doc per category allocation** under a per-project subcollection (instead of a Project-level JSON/map), and ensure all feature specs reference the canonical contracts to avoid drift.

## Status / architecture note (important)

This plan was written under a prior “sync engine” baseline (delta sync / `meta/sync` wording). The current baseline is Firestore native offline persistence with scoped listeners (no bespoke sync engine). Treat any remaining delta/`meta/sync` references below as **deprecated**.

## What I found (current state)

- The prior drafts used an embedded Project map / local JSON column for per-category budgets.
- We’ve now aligned the docs to:
  - preset definitions at `accounts/{accountId}/presets/budgetCategories/{budgetCategoryId}`
  - per-project allocations at `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`
  - local allocations table `project_budget_categories`

## Target Firestore shape (decision)

- **Account preset categories** remain where they already are:
  - `accounts/{accountId}/presets/budgetCategories/{budgetCategoryId}` (definitions: name/slug/archive/metadata)
- **Per-project budgets/enabled categories** move to a subcollection under the project, using your preferred name:
  - `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`
  - Each doc represents the project’s allocation for that preset category.

### Design fee clarification (answering your question)

- **Yes**: Design fee should be a budget category *preset* used as `transaction.budgetCategoryId` for Design Fee transactions.
- What’s “special” is rollup semantics, not the category’s display name.
- Default stable identification approach (unless you later change it):
  - `accounts/{accountId}/meta/accountPresets.designFeeCategoryId = <budgetCategoryId>`

### Suggested doc shape for per-project budgets

Important distinction:

- `presets/budgetCategories/{budgetCategoryId}` = **preset category definition** (this is where `name`/`slug`/`isArchived` live)
- `projects/{projectId}/budgetCategories/{budgetCategoryId}` = **per-project allocation/enablement** for that preset category (this should *not* duplicate the name)

Doc id: `budgetCategoryId` (matches the preset category id)

Fields (minimal, allocation-only):

- `budgetCents: number | null` (integer cents; `null` means “enabled but not budgeted”)
- Sync fields: `updatedAt`, `deletedAt`, `version`, `updatedBy?`, `schemaVersion?`

About “redundant” fields:

- `budgetCategoryId` does **not** need to be stored as a field because it’s the doc id.
- `accountId` / `projectId` are also **redundant** because they’re implied by the document path. We *can* omit them as long as our rules and sync logic derive scope from the path. If we decide we want strict global uniformity with other scoped docs, we can keep them — but they’re not required for correctness here.

## SQLite alignment (local-first)

Add a dedicated local table to replace `projects.budget_categories_*_json`:

- `project_budget_categories` (or similar), keyed by `(account_id, project_id, budget_category_id)`
- Holds `budget_cents` and the common sync/local fields.
- Budget rollups join:
  - presets table `budget_categories` (account-level) + project budgets table + items/transactions.

## Drift prevention rule (docs)

- Feature specs should **reference** the canonical contract in `20_data/data_contracts.md` instead of restating the Project field list.

```mermaid
flowchart TD
  account[accounts/{accountId}] --> project[projects/{projectId}]
  account --> presets[presets]
  presets --> presetCats[budgetCategories/{budgetCategoryId}]
  project --> projBudgets[budgetCategories/{budgetCategoryId}]
  project --> items[items/{itemId}]
  project --> txns[transactions/{transactionId}]
```



## Files to update

- Canonical contracts:
  - `[/.cursor/plans/firebase-mobile-migration/20_data/data_contracts.md](.cursor/plans/firebase-mobile-migration/20_data/data_contracts.md)`
    - Update **Entity: Project** budgeting to use per-category allocation docs (not an embedded map/JSON field).
    - Add a new canonical entity section for the per-project budget docs (e.g. `Entity: ProjectBudgetCategory` or `Entity: ProjectBudgetAllocation`).
- Firestore model:
  - `[/.cursor/plans/firebase-mobile-migration/20_data/firebase_data_model.md](.cursor/plans/firebase-mobile-migration/20_data/firebase_data_model.md)`
    - Replace the embedded map description with the `projects/{projectId}/budgetCategories/{budgetCategoryId}` subcollection.
    - Ensure collection layout notes include the new collection.
- Local schema:
  - `[/.cursor/plans/firebase-mobile-migration/20_data/local_sqlite_schema.md](.cursor/plans/firebase-mobile-migration/20_data/local_sqlite_schema.md)`
    - Add a `project_budget_categories` table (instead of a project JSON/map column) + indexes.
- Feature specs that currently assume embedded Project maps for category budgets:
  - `[/.cursor/plans/firebase-mobile-migration/40_features/budget-and-accounting/feature_spec.md](.cursor/plans/firebase-mobile-migration/40_features/budget-and-accounting/feature_spec.md)`
    - Update “Inputs (local DB)” + rollup math inputs to read project budgets from the new table.
    - Update wording to “project budgetCategories subcollection/table”.
  - `[/.cursor/plans/firebase-mobile-migration/40_features/projects/feature_spec.md](.cursor/plans/firebase-mobile-migration/40_features/projects/feature_spec.md)`
    - Update create/edit project flow to write project budget category docs (not a JSON map field).
    - (Deprecated note) Prior drafts referenced `meta/sync`; under the current baseline this is not a core correctness primitive.

## Execution todos

- **contract-project**: Update `Entity: Project` contract and introduce the per-project budget entity + Firestore path.
- **firestore-model**: Update `firebase_data_model.md` Projects + Entities list to reflect the new subcollection.
- **sqlite-schema**: Update `local_sqlite_schema.md` (remove JSON column, add table + indexes).
- **feature-specs**: Update `budget-and-accounting` + `projects` feature specs to match the new contract and reference contracts rather than duplicating.
- **consistency-sweep**: Search remaining specs for embedded-map references and convert them to allocation-doc references.

