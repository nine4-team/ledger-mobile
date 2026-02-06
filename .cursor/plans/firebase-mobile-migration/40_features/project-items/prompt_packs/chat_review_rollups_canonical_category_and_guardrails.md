# Prompt pack: Review rollups + canonical category + guardrails (Project Items)

You are updating Firebase mobile migration specs. Your task is to review and improve the Project Items spec pack so it is implementation-ready, specifically around:

- Canonical inventory sale rollup logic (no new UI)
- Canonical sale transaction identity (direction-coded + category-coded)
- Category prompting rules for sell flows
- Ensuring “move” corrections stay distinct from canonical sells

## Context (source of truth)

- Working doc (canonical on this topic): `.cursor/plans/firebase-mobile-migration/00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`
- Architecture constraints: `OFFLINE_FIRST_V2_SPEC.md`
- Project Items spec pack (your targets):
  - `.cursor/plans/firebase-mobile-migration/40_features/project-items/feature_spec.md`
  - `.cursor/plans/firebase-mobile-migration/40_features/project-items/acceptance_criteria.md`
  - `.cursor/plans/firebase-mobile-migration/40_features/project-items/flows/inherited_budget_category_rules.md`
  - `.cursor/plans/firebase-mobile-migration/40_features/project-items/ui/screens/ProjectItemsList.md`
  - `.cursor/plans/firebase-mobile-migration/40_features/project-items/ui/screens/ItemDetail.md`

## Parity evidence (web app code pointers)

- Budget rollups today: `src/components/ui/BudgetProgress.tsx` (note: uses transaction category fields; canonical sale treated as negative)
- Canonical transactions + move vs sell distinction:
  - Canonical IDs + creation helpers: `src/services/inventoryService.ts`
  - Move correction (no canonical rows): `moveItemToBusinessInventory` in `src/services/inventoryService.ts`
  - Deallocation/sell to business inventory (creates/updates `INV_SALE_*`): `handleItemDeallocation` path in `src/pages/ItemDetail.tsx`, `src/pages/InventoryList.tsx`
- Item actions surface: `src/components/items/ItemActionsMenu.tsx`
- Bulk controls surface: `src/components/ui/BulkItemControls.tsx`

## What to do

1) **Rollup logic requirement (must be explicit)**
   - Ensure specs clearly require rollups where:
     - non-canonical attribution uses `transaction.budgetCategoryId`
     - canonical inventory sale attribution also uses `transaction.budgetCategoryId` (canonical rows are category-coded by invariant)
     - rollups apply sign based on direction (`business_to_project` adds, `project_to_business` subtracts)
   - Add/adjust “Intentional delta” callouts pointing to `BudgetProgress.tsx`.

2) **Canonical sale identity + invariants**
   - Ensure specs define:
     - one canonical sale transaction per `(projectId, direction, budgetCategoryId)`
    - a deterministic id format (recommended prefix `SALE_`)
     - canonical rows are system-owned (read-only in UI)
3) **Prompt rules (replace hard blocks)**
   - Project → Business: if `item.budgetCategoryId` is missing, prompt the user to choose a source-project category, persist it, then proceed.
   - Business → Project: prompt only if the item category is missing or not enabled/available in the destination project; persist and proceed.
   - Bulk: one selection applies to the uncategorized items (fast path).

4) **Guardrail scope: “move” vs “sell/deallocate”**
   - Ensure specs keep “Move to Business Inventory” as a correction path (no canonical rows) and do not require category prompting unless/when the user uses Sell flows.

## Evidence rule (anti-hallucination)

Every non-obvious behavior you add must include:

- Parity evidence (file + component/function), OR
- Intentional delta (explicitly labeled).

## Output expectations

Make edits directly in the spec pack files listed above. Keep changes narrowly scoped to the four topics above.

