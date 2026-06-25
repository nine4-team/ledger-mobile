# One-Off Production Repair Plan: H11MvVi0hAmeTmTF8qaz

Status: completed on 2026-06-24 09:58 MDT.

Related dry run: `docs/plans/production-repair-H11MvVi0hAmeTmTF8qaz-dry-run.md`

## Goal

Backfill the missing source-side transaction and lineage trail for the two Regan nightstands that were sold from `Kapcsos Martinique Rental` to `Sandra- BAHAMA Unit`.

This is not a move/correction operation. The items already live in the correct destination project and destination transaction. The repair is append-only accounting/audit backfill.

## Production Evidence

- Firebase project: `ledger-nine4`
- Account: `1dd4fd75-8eea-4f7a-98e7-bf45b987ae94` (`1584 Design`)
- Source project: `405GIhLoU2pLY4zqb71R` (`Kapcsos Martinique Rental`)
- Destination project: `fc4e8569-75f6-46b4-97ae-c4bc57f615d0` (`Sandra- BAHAMA Unit`)
- Source transaction: `dT91f6jiZXVRmkX8RN7t`
- Destination transaction: `E614DE46-40F0-4D95-99EC-CD9F2E59432C`
- Budget category: `da556858-1df8-40be-b10c-b15710d7cc9a` (`Furnishings`)
- Affected items:
  - `H11MvVi0hAmeTmTF8qaz`
  - `Dcysdan3I84AOmFMfrMd`

Both items originated in the source project from a Wayfair Purchase. They should therefore get a source-side Sale-to-Inventory hop, not a Return-to-Inventory hop.

## Dependency

Preferred order:

1. Implement and deploy the budget-rollup fix in `budget-rollup-inventory-egress-plan.md`.
2. Run this one-off repair.

Reason: the repair transaction should carry `sourceBudgetCategoryId`, and the deployed rollup should understand that field before or immediately after the transaction is created. If this repair is applied first, the audit/trail backfill will still be correct, but source-project budget summary will need a later recompute after the code fix deploys.

## Write Plan

### 1. Add a Repair Script

Create a one-off script, for example:

`mcp-server/scripts/repair-H11MvVi0hAmeTmTF8qaz.ts`

Script behavior:

- Dry-run by default.
- Requires `--commit` for writes.
- Uses Firebase Admin with ADC or `GOOGLE_APPLICATION_CREDENTIALS`.
- Refuses to write unless all expected current documents still match the dry-run evidence.
- Uses a Firestore transaction or batched write.
- Does not update item docs.
- Does not edit or delete existing lineage edges.
- Does not mutate source/destination transaction `itemIds`.

### 2. Preconditions

Before write mode, assert:

- Repair transaction does not exist:
  - `accounts/{accountId}/transactions/REPAIR_SALE_TO_INVENTORY_20260624_001`
- Both item docs exist and still have:
  - `projectId == fc4e8569-75f6-46b4-97ae-c4bc57f615d0`
  - `budgetCategoryId == da556858-1df8-40be-b10c-b15710d7cc9a`
  - `transactionId == E614DE46-40F0-4D95-99EC-CD9F2E59432C`
  - `source == Wayfair`
  - `currentSource == 1584 Design Inventory`
  - `purchasePriceCents == 49499`
  - `projectPriceCents == 49499`
- Source transaction exists and is still:
  - `type == Purchase`
  - `source == Wayfair`
  - `projectId == 405GIhLoU2pLY4zqb71R`
  - `budgetCategoryId == da556858-1df8-40be-b10c-b15710d7cc9a`
- Destination transaction exists and is still:
  - `type == Purchase`
  - `source == 1584 Design Inventory`
  - `projectId == fc4e8569-75f6-46b4-97ae-c4bc57f615d0`
  - `budgetCategoryId == da556858-1df8-40be-b10c-b15710d7cc9a`
  - `itemIds` contains both affected items
- No existing `soldToInventory` lineage edge for either affected item points to `REPAIR_SALE_TO_INVENTORY_20260624_001`.

### 3. Create Missing First-Hop Sale

Path:

`accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94/transactions/REPAIR_SALE_TO_INVENTORY_20260624_001`

Fields:

```json
{
  "type": "Sale",
  "source": "1584 Design Inventory",
  "projectId": "405GIhLoU2pLY4zqb71R",
  "sourceBudgetCategoryId": "da556858-1df8-40be-b10c-b15710d7cc9a",
  "amountCents": 98998,
  "subtotalCents": 98998,
  "itemIds": [
    "Dcysdan3I84AOmFMfrMd",
    "H11MvVi0hAmeTmTF8qaz"
  ],
  "status": "completed",
  "isComplete": true,
  "transactionDate": "6/23/2026",
  "createdAt": "2026-06-24T00:10:10.732Z",
  "updatedAt": "SERVER_TIMESTAMP",
  "createdBy": "4ef35958-597c-4aea-b99e-1ef62352a72d",
  "notes": "[AI 6/24/2026] Repair: backfilled missing source-side Sale-to-Inventory hop for project-to-project sale of two Regan 3-Drawer Nightstand items (SKU W004254185). Items originated in source project transaction dT91f6jiZXVRmkX8RN7t from Wayfair and were sold into destination project transaction E614DE46-40F0-4D95-99EC-CD9F2E59432C through 1584 Design Inventory."
}
```

`budgetCategoryId` remains absent. `sourceBudgetCategoryId` preserves the source project category for budget rollup without changing the shape rule that project -> inventory Sale transactions have no destination budget category.

### 4. Add First-Hop Intent Lineage

Create one auto-ID lineage edge per item:

```json
{
  "accountId": "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94",
  "itemId": "<ITEM_ID>",
  "fromProjectId": "405GIhLoU2pLY4zqb71R",
  "toProjectId": null,
  "fromTransactionId": "dT91f6jiZXVRmkX8RN7t",
  "toTransactionId": "REPAIR_SALE_TO_INVENTORY_20260624_001",
  "movementKind": "soldToInventory",
  "source": "repair",
  "createdAt": "SERVER_TIMESTAMP",
  "createdBy": "4ef35958-597c-4aea-b99e-1ef62352a72d",
  "note": "Repair backfill: missing first-hop Sale-to-Inventory for project-to-project sale into E614DE46-40F0-4D95-99EC-CD9F2E59432C."
}
```

### 5. Post-Write Verification

Immediately after commit:

- Re-read the repair Sale transaction and both lineage edges.
- Re-read both item docs and confirm they were not changed.
- Re-read source transaction audit. It should remain complete and include the affected item value in sold-lineage accounting.
- Re-read destination transaction audit. It should remain complete.
- Re-read source and destination project budget summaries after Functions drain.

Expected budget effect after the budget-rollup fix:

- Source project `405GIhLoU2pLY4zqb71R` Furnishings spend decreases by `98998`.
- Destination project `fc4e8569-75f6-46b4-97ae-c4bc57f615d0` Furnishings spend remains increased by the existing destination Purchase `98998`.

## Rollback Posture

Do not delete the repair transaction or lineage edges as a normal rollback. If a mistake is discovered, use another append-only correction note/transaction plan so the production audit trail remains explainable.

## Execution Log

2026-06-24:

- Added guarded script: `mcp-server/scripts/repair-H11MvVi0hAmeTmTF8qaz.mjs`.
- Dry-run passed all production precondition checks.
- Write mode completed successfully against Firebase project `ledger-nine4`.
- Created transaction:
  - `accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94/transactions/REPAIR_SALE_TO_INVENTORY_20260624_001`
  - `type: Sale`
  - `source: 1584 Design Inventory`
  - `projectId: 405GIhLoU2pLY4zqb71R`
  - `sourceBudgetCategoryId: da556858-1df8-40be-b10c-b15710d7cc9a`
  - `amountCents: 98998`
  - `itemIds: Dcysdan3I84AOmFMfrMd, H11MvVi0hAmeTmTF8qaz`
- Created lineage edges:
  - `Kr3bVyf5Mc6GAQPdp3nf` for `Dcysdan3I84AOmFMfrMd`
  - `XwUb82Nd5K0ncpCr5XPv` for `H11MvVi0hAmeTmTF8qaz`
- Verified both item docs were not moved or edited:
  - still in destination project `fc4e8569-75f6-46b4-97ae-c4bc57f615d0`
  - still on transaction `E614DE46-40F0-4D95-99EC-CD9F2E59432C`
- Verified audits:
  - source transaction audit remains complete with `soldItemsCount: 2`, `soldItemsSumCents: 98998`, `varianceCents: 0`
  - destination transaction audit remains complete with `linkedItemsSumCents: 98998`, `varianceCents: 0`
- Budget summaries recalculated after the write, but the source project budget still does not decrement for this Sale-to-Inventory transaction until `budget-rollup-inventory-egress-plan.md` is implemented.
