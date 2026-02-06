## Inventory operations + lineage

This feature covers **cross-entity operations** that move and link items across:

- Project scope ↔ Business Inventory scope
- Item ↔ Transaction relationships
- Canonical inventory **sale** transactions (direction-coded + category-coded) used for deterministic inventory/accounting mechanics

It is the primary correctness layer for “allocate/move/sell/deallocate” flows and must be compatible with:

- Firestore-native offline persistence (offline-ready baseline)
- request-doc workflows for multi-doc correctness (server-owned invariants)
- scoped listeners bounded to the active scope (detach on background; reattach on resume)

See: `OFFLINE_FIRST_V2_SPEC.md`.

## Docs in this folder
- `feature_spec.md` — behavior spec + required invariants
- `acceptance_criteria.md` — testable checklist with parity evidence or explicit deltas
- `flows/` — multi-screen/multi-entity flows
- `prompt_packs/` — prompt packs for parallel AI dev chats

## Cross-cutting links
- Shared Items + Transactions modules (must be reused across project + business inventory):  
  `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`
- Budget-category inheritance and guardrails (`inheritedBudgetCategoryId`):  
  `40_features/project-items/flows/inherited_budget_category_rules.md`

## Scope

In scope:
- Project → Business Inventory:
  - **Move** (correction path) — item becomes Business Inventory without canonical sale
  - **Deallocate/Sell** (canonical path) — item becomes Business Inventory and is linked to the canonical sale transaction for:
    - `(projectId, direction = project_to_business, budgetCategoryId)`
    - (with allocation-reversion exception)
- Business Inventory → Project:
  - **Allocate** — item becomes project-scoped and is linked to the canonical sale transaction for:
    - `(projectId, direction = business_to_project, budgetCategoryId)`
- Project → Project:
  - **Sell item to another project** — two-phase operation: sale then sale (project → business, then business → project)
- **Lineage**:
  - Append edges and maintain pointers so moves are auditably reconstructable

Out of scope (but referenced by this feature):
- Project Items / Transactions UI surface area (lists/details/forms), which live in their respective feature specs and must reuse shared modules.
- Budget rollups UI (uses these flows for correctness).
