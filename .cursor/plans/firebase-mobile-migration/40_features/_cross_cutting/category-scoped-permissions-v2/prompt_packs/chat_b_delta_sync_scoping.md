# Prompt Pack — Chat B: Scoped queries/listeners + offline cache semantics (Roles v2)

## Goal
Implement Roles v2 scoping via **Firestore query/listener shape**, so the client never downloads unauthorized rows and the UI never relies on “fetch then filter”.

This must remain compatible with:
- `OFFLINE_FIRST_V2_SPEC.md` (Firestore-native offline persistence; scoped listeners; no “listen to everything”)

## Required reading (ground truth)
- Spec: `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md` (see §4.2–4.4)
- Canonical attribution evidence (do not change):
  - `40_features/project-items/flows/inherited_budget_category_rules.md`
  - `40_features/project-transactions/feature_spec.md`
  - `40_features/budget-and-accounting/feature_spec.md`

## Outputs (required)
- Update the read/query strategy so that:
  - items fetched/listened are only those visible under Roles v2 rules
  - non-canonical transactions fetched/listened are only those visible under Roles v2 rules
  - canonical `INV_*` transaction fetching respects derived visibility (only fetch canonical rows that have at least one in-scope linked item)
- Define behavior for scope changes (`allowedBudgetCategoryIds`):
  - when it expands: newly-visible rows become available via updated queries/listeners (and optional backfill if using paginated lists)
  - when it shrinks: queries/listeners update immediately so newly-disallowed rows are no longer returned for future reads

## Constraints
- No client-side filtering after downloading unauthorized rows.
- No large/unbounded listeners.
- Do not introduce new product capabilities; implement Roles v2 only.

## Edge cases that must be explicit
- “Uncategorized item” rule is item-specific (`item.inheritedBudgetCategoryId == null`), not transaction-specific.
- Canonical transactions have `categoryId == null` by design; do not treat them as globally visible.

