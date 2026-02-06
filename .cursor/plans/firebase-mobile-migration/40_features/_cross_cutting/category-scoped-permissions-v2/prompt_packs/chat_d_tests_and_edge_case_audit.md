# Prompt Pack — Chat D: Tests + edge-case audit (Roles v2)

## Goal
Reduce regression and security risk by adding targeted tests and auditing edge cases for Roles v2:

- item visibility (null vs non-null `inheritedBudgetCategoryId`)
- item writes (null → allowed; A → B admin-only)
- transaction visibility:
  - non-canonical by `transaction.budgetCategoryId`
  - canonical inventory sale (system) by `transaction.budgetCategoryId` (canonical rows are category-coded and system-owned)

## Required reading (ground truth)
- Spec: `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md`
- Canonical attribution evidence (do not change):
  - `40_features/project-items/flows/inherited_budget_category_rules.md`
  - `40_features/project-transactions/feature_spec.md`
  - `40_features/budget-and-accounting/feature_spec.md`

## Outputs (required)
- Add tests that cover the read/write matrix:
  - admin vs scoped
  - item uncategorized ownership exception
  - canonical inventory sale transaction visibility + read-only constraints
- Add a brief “edge-case audit” note (in the implementation PR or in a small doc update) listing what was checked and any intentional deltas.

## Constraints
- Do not add new capabilities.
- Tests should validate that unauthorized rows are not surfaced and (preferably) not synced to SQLite.

