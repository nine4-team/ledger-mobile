# Budget Rollup Fix Plan: Inventory Egress

Status: proposed; not implemented in this plan.

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

Add a source-side category field for project egress:

`sourceBudgetCategoryId`

Rules:

- `budgetCategoryId` continues to mean destination/current transaction category.
- `sourceBudgetCategoryId` means the category the items left from in the source project.
- Inventory egress transactions use `sourceBudgetCategoryId` for budget rollup.
- Keep `budgetCategoryId` absent on Sale-to-Inventory so the existing direction shape stays clear.
- Treat `sourceBudgetCategoryId` as an accounting shape field after creation.

## Batch Shape Rule

An egress transaction should represent exactly one source project and one source budget category.

Why: budget summaries are category-level. A single no-category or mixed-category egress transaction cannot be assigned safely to one category after the items have moved and item docs have lost their source category.

Implementation rule:

- Group source-exit legs by `(movementKind, sourceProjectId, sourceBudgetCategoryId)`.
- Create one first-hop transaction per group:
  - from-inventory items: `Return`
  - project-originated items: `Sale`
- Each first-hop transaction carries:
  - `projectId: sourceProjectId`
  - `sourceBudgetCategoryId`
  - purchase-price `amountCents` / `subtotalCents`
  - itemIds for that group
- Destination project Purchase remains one transaction per destination category.

If any source item lacks `budgetCategoryId`, block the financial egress and require a correction first.

## Code Changes

### Firebase Functions

File: `firebase/functions/src/index.ts`

Update `recalculateProjectBudgetSummary`:

- Resolve a budget-impact category:
  - Use `budgetCategoryId` for normal category-bearing transactions.
  - For inventory egress transactions with no `budgetCategoryId`, use `sourceBudgetCategoryId`.
- Resolve amount sign:
  - `Return` -> negative.
  - Sale-to-Inventory -> negative when:
    - `type == "Sale"`
    - no `budgetCategoryId`
    - `sourceBudgetCategoryId` exists
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
- Write `sourceBudgetCategoryId` on every source-exit transaction.
- Keep item updates the same: items landing in inventory clear `budgetCategoryId`; items landing in destination project use destination category.
- Keep amount basis unchanged:
  - source exit uses purchase price
  - destination project purchase uses project price

### MCP Writers

File: `mcp-server/src/tools/inventory-operations.ts`

Mirror iOS behavior:

- Dry-run output shows source-exit groups and `sourceBudgetCategoryId`.
- Commit creates one egress transaction per source category group.
- Validation rejects egress if any source item lacks `budgetCategoryId`.
- `sell_items_from_project_to_project` first hop groups by origin and source category.
- Destination Purchase remains one transaction using `destinationBudgetCategoryId`.

### Shared / Read Models

Update types and projections where useful:

- `mcp-server/src/types.ts`: add optional `sourceBudgetCategoryId` to `Transaction`.
- `LedgeriOS/LedgeriOS/Models/Transaction.swift`: add optional `sourceBudgetCategoryId`.
- Transaction detail/export/search can display or export the field only if useful; it is mainly a rollup/audit field.

### Firestore Rules

File: `firebase/firestore.rules`

- Add `sourceBudgetCategoryId` to frozen accounting shape fields on inventory movement transactions.
- Allow it on create.
- Disallow mutation after create except for legacy canonical carve-outs if applicable.
- Keep `itemIds` mutable if the active-membership rules remain in this branch.

### Specs

Update:

- `docs/specs/sale-transactions.md`
- `docs/specs/budget-management.md`
- `docs/specs/data-model.md`
- `docs/specs/return-and-sale-tracking.md`
- `CLAUDE.md`

Spec points:

- `budgetCategoryId` is destination/category membership.
- `sourceBudgetCategoryId` is source-project category for inventory egress.
- Project -> inventory Sale/Return uses purchase price and subtracts from `sourceBudgetCategoryId`.
- Project -> project source hop subtracts from `sourceBudgetCategoryId`; destination hop adds to `destinationBudgetCategoryId`.

## Tests

### Functions / Emulator

Add emulator-backed cases that create transactions and verify `budgetSummary`:

- Project-originated item -> Sale-to-Inventory:
  - Sale has no `budgetCategoryId`
  - Sale has `sourceBudgetCategoryId`
  - source category spend decreases by purchase price
- From-inventory item -> Return-to-Inventory:
  - Return has no `budgetCategoryId`
  - Return has `sourceBudgetCategoryId`
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

- source-exit transactions include `sourceBudgetCategoryId`
- mixed category source exits split into multiple first-hop transactions
- missing source `budgetCategoryId` fails before write
- existing project-price prompt behavior is unchanged for destination project sales

### MCP Tests

Update `mcp-server/test/sell-items.test.ts`:

- dry-run exposes `sourceBudgetCategoryId`
- commit writes grouped source-exit transactions
- budget/source fields match iOS behavior

## Production Backfill Strategy

After code deploy:

1. Query existing project -> inventory egress transactions with no `sourceBudgetCategoryId`.
2. For each transaction, infer source category from:
   - current lineage `fromTransactionId` source transaction `budgetCategoryId`
   - historical item category only if still reliable
3. If all items in the transaction map to one source category, set `sourceBudgetCategoryId`.
4. If items map to multiple source categories, do not guess:
   - produce a report
   - decide whether to split with append-only replacement records or manually classify
5. Recompute or trigger recompute for affected project budget summaries.

The `H11MvVi0hAmeTmTF8qaz` repair should create the repair Sale with `sourceBudgetCategoryId` from the start, so it should not need this backfill.

## Release Order

1. Implement code/spec/tests.
2. Run targeted iOS, MCP, Functions emulator tests.
3. Deploy Functions/rules.
4. Apply the `H11MvVi0hAmeTmTF8qaz` one-off repair.
5. Verify source/destination budgets.
6. Run broader backfill report for older egress transactions.

