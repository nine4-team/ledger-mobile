# Budget Rollup Fix Plan: Inventory Egress

Status: superseded by `docs/plans/budget-category-accounting-cleanup-plan.md`.

## Superseding Decision

Do not add or rely on `sourceBudgetCategoryId`.

Use transaction `budgetCategoryId` as the accounting category for every project-impacting transaction, including source-side Sale/Return inventory egress. Item `budgetCategoryId` remains current item placement state and can be cleared when the item lands in business inventory; transaction `budgetCategoryId` remains frozen historical accounting attribution.

This file is retained as the original problem statement and implementation history. The implementation should follow `budget-category-accounting-cleanup-plan.md`.

## Goal

Make project budget summaries correctly subtract items that leave a project through real inventory egress:

- from-inventory item -> Return-to-Inventory
- project-originated item -> Sale-to-Inventory
- project -> project first hop, whether Return-to-Inventory or Sale-to-Inventory

Destination project purchases already roll up correctly because they are `Purchase` transactions with `budgetCategoryId`. The broken area is source-project egress: current egress transactions intentionally have no `budgetCategoryId`, and the budget-summary function skips no-category transactions.

## Current Problem

`recalculateProjectBudgetSummary` currently does this:

- queries project transactions
- skips any transaction with no `budgetCategoryId`
- subtracts `Return`
- treats other category-bearing transactions as positive unless legacy direction says otherwise

But current project -> inventory transactions are shaped like:

- `Return` to inventory:
  - `type: Return`
  - `projectId: <sourceProjectId>`
  - no `budgetCategoryId`
- Sale-to-Inventory:
  - `type: Sale`
  - `projectId: <sourceProjectId>`
  - no `budgetCategoryId`

Because both lack `budgetCategoryId`, source-project budget summaries do not get the decrement.

## Design Decision

Use `budgetCategoryId` on the source-side egress transaction.

Rules:

- `budgetCategoryId` means the category this transaction affects for project accounting.
- Inventory egress transactions use `budgetCategoryId` for budget rollup.
- Do not keep `budgetCategoryId` absent on Sale-to-Inventory when that Sale belongs to a source project.
- Do not add `sourceBudgetCategoryId`.
- Treat transaction `budgetCategoryId` as an accounting shape field after creation.

## Batch Shape Rule

An egress transaction should represent exactly one source project and one source budget category.

Why: budget summaries are category-level. A single no-category or mixed-category egress transaction cannot be assigned safely to one category after the items have moved and item docs have lost their source category.

Implementation rule:

- Group source-exit legs by `(movementKind, sourceProjectId, budgetCategoryId)`.
- Create one first-hop transaction per group:
  - from-inventory items: `Return`
  - project-originated items: `Sale`
- Each first-hop transaction carries:
  - `projectId: sourceProjectId`
  - `budgetCategoryId`
  - purchase-price `amountCents` / `subtotalCents`
  - itemIds for that group
- Destination project Purchase remains one transaction per destination category.

If any source item lacks `budgetCategoryId`, block the financial egress and require a correction first.

## Code Changes

### Firebase Functions

File: `firebase/functions/src/index.ts`

Update `recalculateProjectBudgetSummary`:

- Resolve a budget-impact category from `budgetCategoryId`.
- Resolve amount sign:
  - `Return` -> negative.
  - Sale-to-Inventory -> negative when:
    - `type == "Sale"`
    - `budgetCategoryId` exists
    - `source` is an inventory label or otherwise matches the project -> inventory shape.
  - Legacy canonical sales keep existing `inventorySaleDirection` behavior.
  - Inventory -> project Purchase stays positive.
- Preserve existing behavior for canceled transactions: `0`.

Update transaction audit handling if needed:

- Current in-flight changes already include `soldToInventory` in source transaction audit lineage. Keep that behavior so source purchase audit remains complete when items leave via Sale-to-Inventory.

### iOS Writers

File: `LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift`

Update first-hop writers to preserve source category:

- `returnToInventory`
- `sellToInventory`
- mixed `moveToInventory` / inventory disposition flow
- `sellItemsFromProjectToProject` first-hop Return/Sale legs

Required behavior:

- Group first-hop items by source `budgetCategoryId`.
- Create separate Return/Sale transactions per category group.
- Write source-category `budgetCategoryId` on every source-exit transaction.
- Keep item updates the same: items landing in inventory clear `budgetCategoryId`; items landing in destination project use destination category.
- Keep amount basis unchanged:
  - source exit uses purchase price
  - destination project purchase uses project price

### MCP Writers

File: `mcp-server/src/tools/inventory-operations.ts`

Mirror iOS behavior:

- Dry-run output shows source-exit groups and source-category `budgetCategoryId`.
- Commit creates one egress transaction per source category group.
- Validation rejects egress if any source item lacks `budgetCategoryId`.
- `sell_items_from_project_to_project` first hop groups by origin and source category.
- Destination Purchase remains one transaction using `destinationBudgetCategoryId`.

### Shared / Read Models

No new read-model field is needed. Use existing transaction `budgetCategoryId`.

### Firestore Rules

File: `firebase/firestore.rules`

- Keep `budgetCategoryId` in frozen accounting shape fields on inventory movement transactions.
- Allow it on create for project-side Sale/Return egress transactions.
- Disallow mutation after create except for approved repair/admin paths.
- Keep `itemIds` mutable if the active-membership rules remain in this branch.

### Specs

Update:

- `docs/specs/sale-transactions.md`
- `docs/specs/budget-management.md`
- `docs/specs/data-model.md`
- `docs/specs/return-and-sale-tracking.md`
- `CLAUDE.md`

Spec points:

- Transaction `budgetCategoryId` is the project accounting category.
- Item `budgetCategoryId` is current placement/category state.
- Project -> inventory Sale/Return uses purchase price and subtracts from transaction `budgetCategoryId`.
- Project -> project source hop subtracts from its transaction `budgetCategoryId`; destination hop adds to its own transaction `budgetCategoryId`.

## Tests

### Functions / Emulator

Add emulator-backed cases that create transactions and verify `budgetSummary`:

- Project-originated item -> Sale-to-Inventory:
  - Sale has source-category `budgetCategoryId`
  - source category spend decreases by purchase price
- From-inventory item -> Return-to-Inventory:
  - Return has source-category `budgetCategoryId`
  - source category spend decreases by purchase price
- Project -> project, project-originated:
  - source Sale-to-Inventory subtracts purchase price from source category
  - destination Purchase adds project price to destination category
- Project -> project, from-inventory:
  - source Return subtracts purchase price from source category
  - destination Purchase adds project price to destination category
- Mixed source categories:
  - source first-hop creates separate egress transactions per source category
  - each source category gets the correct decrement

### iOS Unit / Integration

Update or add tests around `InventoryOperationsService`:

- source-exit transactions include source-category `budgetCategoryId`
- mixed category source exits split into multiple first-hop transactions
- missing source `budgetCategoryId` fails before write
- existing project-price prompt behavior is unchanged for destination project sales

### MCP Tests

Update `mcp-server/test/sell-items.test.ts`:

- dry-run exposes source-category `budgetCategoryId`
- commit writes grouped source-exit transactions
- budget/source fields match iOS behavior

## Production Backfill Strategy

After code deploy:

1. Query existing project -> inventory egress transactions with no `budgetCategoryId` or with accidental `sourceBudgetCategoryId`.
2. For each transaction, infer source category from:
   - current lineage `fromTransactionId` source transaction `budgetCategoryId`
   - historical item category only if still reliable
3. If all items in the transaction map to one source category, set `budgetCategoryId` and remove `sourceBudgetCategoryId`.
4. If items map to multiple source categories, do not guess:
   - produce a report
   - decide whether to split with append-only replacement records or manually classify
5. Recompute or trigger recompute for affected project budget summaries.

The `H11MvVi0hAmeTmTF8qaz` repair transaction was initially created with `sourceBudgetCategoryId`; it should be patched to use `budgetCategoryId` and delete `sourceBudgetCategoryId`.

## Release Order

1. Implement code/spec/tests.
2. Run targeted iOS, MCP, Functions emulator tests.
3. Deploy Functions/rules.
4. Apply the `H11MvVi0hAmeTmTF8qaz` one-off repair.
5. Verify source/destination budgets.
6. Run broader backfill report for older egress transactions.
