# Budget Category Accounting Cleanup Plan

Created: 2026-06-25
Status: implemented locally on 2026-06-25; backend/app deploy still required before user rollout.

## Decision

`budgetCategoryId` is the accounting category for a project transaction. If a transaction changes a project's budget or accounting rollup, it should carry the category that rollup should use, whether the transaction is money in, money out, purchase, sale, return, or a hop in a project-to-project sale.

Do not use `sourceBudgetCategoryId` as the canonical accounting field. That design is superseded.

Keep the distinction clear:

- Transaction `budgetCategoryId`: frozen historical accounting attribution for that project-side transaction.
- Item `budgetCategoryId`: current placement/category state for the item. It can be cleared when the item lands in business inventory.
- `destinationBudgetCategoryId`: only use as a transient UI/service input if needed before creating the destination transaction. Persist the destination transaction's accounting category as its own `budgetCategoryId`.

## Required Behavior

Inventory or project to project:

- Destination project Purchase uses project price.
- Destination project Purchase requires or prompts for a destination project price when missing.
- Destination project Purchase writes `budgetCategoryId` from the destination project category selected by the user.

Project to business inventory:

- Sale or Return uses purchase price.
- No destination budget category UI is needed because business inventory is not a project budget.
- The project-exit transaction writes `budgetCategoryId` from the item's current project category.
- The item can be updated to business inventory and have item-level `budgetCategoryId` cleared.

Project to project, two-hop flow:

- Source project exit transaction uses purchase price.
- Source project exit transaction writes `budgetCategoryId` from the item's current source project category.
- Destination project Purchase writes its own `budgetCategoryId` from the destination category selected by the user.
- Each persisted transaction stands alone for accounting; no source/destination category pair is needed on one transaction.

Correction or reassignment flows:

- Do not create Sale/Purchase/Return accounting transactions.
- Preserve or correct transaction accounting category intentionally.
- Do not reuse sale paths or project-price prompting for correction-only operations.

## Implementation Steps

1. Replace the `sourceBudgetCategoryId` direction in specs and implementation notes.

   Update the earlier inventory-egress budget plan and affected specs so they say project-side egress transactions use `budgetCategoryId`. Explicitly remove language implying Sale-to-Inventory should omit `budgetCategoryId`.

2. Update iOS inventory operation writes.

   In `InventoryOperationsService`, ensure all project-affecting transaction documents include `budgetCategoryId`:

   - inventory to project Purchase: destination category
   - project to project source Sale/egress: source item category
   - project to project destination Purchase: destination category
   - project to business inventory Sale: source item category
   - return to business inventory Return: source item category

   If a source-exit operation includes items with different source categories, split the source-exit transaction by category. If any source item is missing a category, block and require correction before sale/return.

3. Update MCP inventory operation writes.

   Mirror the iOS behavior in MCP tools:

   - dry runs show source-exit category grouping
   - commits write `budgetCategoryId`, not `sourceBudgetCategoryId`
   - project-to-inventory and project-to-project source exits validate source item category
   - destination project Purchases keep using destination category selection/input

4. Update budget rollup logic.

   The budget summary code should continue using transaction `budgetCategoryId` as the grouping key. No special source-category field is needed.

   Fix transaction sign rules so project-exit inventory transactions decrement the source project budget:

   - Return to business inventory: negative
   - Sale to business inventory: negative
   - Project-to-project source Sale/egress: negative
   - Destination project Purchase: positive

5. Update Firestore rules and validation.

   Rules should allow and preserve `budgetCategoryId` on project-side Sale/Return egress transactions. They should not require an inventory item document to retain a category after it lands in business inventory.

   Keep transaction accounting fields frozen after commit unless an approved admin repair path is being used.

6. Update specs.

   Review and align at least:

   - `docs/specs/sale-transactions.md`
   - `docs/specs/inventory-as-store.md`
   - `docs/specs/budget-management.md`
   - `docs/specs/data-model.md`
   - `docs/specs/transaction-type.md`
   - `docs/specs/reassign-vs-sell.md`
   - `CLAUDE.md`

   The specs should explicitly state that transaction category and item category are different concepts.

7. Update tests.

   Add or repair coverage for:

   - project to business inventory writes source-category `budgetCategoryId`
   - return to business inventory writes source-category `budgetCategoryId`
   - project to project creates a negative source transaction with source-category `budgetCategoryId` and a positive destination Purchase with destination-category `budgetCategoryId`
   - mixed source categories split source-exit transactions by category
   - missing source category blocks source-exit sale/return
   - budget rollups decrement for source-exit Sale/Return and increment for destination Purchase
   - item category clears when item lands in business inventory while transaction category remains frozen

8. Repair the already-created production transaction.

   Update:

   `accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94/transactions/REPAIR_SALE_TO_INVENTORY_20260624_001`

   Required patch:

   - set `budgetCategoryId = da556858-1df8-40be-b10c-b15710d7cc9a`
   - remove `sourceBudgetCategoryId`
   - leave `amountCents = 98998`
   - leave `projectId = 405GIhLoU2pLY4zqb71R`
   - leave `itemIds = ["Dcysdan3I84AOmFMfrMd", "H11MvVi0hAmeTmTF8qaz"]`
   - leave the existing `soldToInventory` lineage edges intact

   Then rerun or trigger the affected source project budget recompute and verify Furnishings decreases by `98998`.

9. Backfill or report other affected transactions.

   Query for project-side Sale/Return inventory-egress transactions missing `budgetCategoryId` or carrying `sourceBudgetCategoryId`. For each, determine the historical project category from item history, lineage, or original purchase context, then patch `budgetCategoryId` and remove `sourceBudgetCategoryId`.

10. Deployment order.

   - Update specs and tests.
   - Implement app, MCP, rules, and function rollup changes.
   - Run local unit/integration tests and Firebase emulator tests.
   - Deploy backend/rules/MCP changes.
   - Ship app changes through normal release flow.
   - Apply production repair patch.
   - Recompute affected budgets.
   - Verify transaction audit, accounting summary, item lineage, and source/destination project trails.

## Implementation Log

2026-06-25:

- Updated iOS inventory writers so project-side Sale/Return egress transactions write source-category `budgetCategoryId`, split mixed source categories, reject missing source categories, and keep item categories cleared when items land in inventory.
- Updated MCP inventory tools to mirror the same category grouping and validation; dry-runs and commits now use `budgetCategoryId`, not `sourceBudgetCategoryId`.
- Updated budget sign logic across iOS, MCP, Firebase Functions, and the backfill script so non-legacy project-side Sales subtract from budgets while legacy canonical inventory sales still use `inventorySaleDirection`.
- Updated display/card/report calculations so `budgetCategoryId` no longer makes a Sale render/account like a Purchase.
- Updated Firestore rules/specs/plans around transaction-vs-item category ownership and immutable accounting fields.
- Patched production repair transaction `REPAIR_SALE_TO_INVENTORY_20260624_001` to set `budgetCategoryId: da556858-1df8-40be-b10c-b15710d7cc9a` and remove `sourceBudgetCategoryId`.

Verification:

- `npm run build` in `firebase/functions` passed.
- `npm run build` in `mcp-server` passed.
- `npm test -- --run test/sell-items.test.ts` in `mcp-server` passed against the Firestore emulator.
- Targeted iOS calculation tests for transaction display/card behavior passed.
- Full iOS test suite compiled and ran. Non-integration tests passed; the remaining failures were emulator/auth integration setup failures (`ERROR_INVALID_CREDENTIAL` / `ERROR_TOO_MANY_REQUESTS`), not assertion failures from this implementation.

## Out Of Scope

The separate "active membership itemIds plus lineage history" model is not part of this cleanup plan. Do not mix that semantic change into this work unless it is separately approved and tested.

This plan also does not change user-facing Sell vs Correct labels except where required to prevent correction flows from calling sale/accounting paths.
