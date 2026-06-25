# Production Repair Dry Run: H11MvVi0hAmeTmTF8qaz

Status: dry-run only; no production writes applied.

Generated: 2026-06-24 09:40 MDT

## Scope

- Firebase project: `ledger-nine4`
- Account: `1dd4fd75-8eea-4f7a-98e7-bf45b987ae94` (`1584 Design`)
- Reported item: `H11MvVi0hAmeTmTF8qaz`
- Companion same-name/SKU item: `Dcysdan3I84AOmFMfrMd`

Both items are:

- Name: `Regan 3-Drawer Nightstand`
- SKU: `W004254185`
- Purchase price: `49499`
- Project price: `49499`
- Current project: `fc4e8569-75f6-46b4-97ae-c4bc57f615d0` (`Sandra- BAHAMA Unit`)
- Current transaction: `E614DE46-40F0-4D95-99EC-CD9F2E59432C`
- Source: `Wayfair`
- Current source: `1584 Design Inventory`

## Existing Evidence

### Source Project

- Project: `405GIhLoU2pLY4zqb71R` (`Kapcsos Martinique Rental`)
- Source transaction: `dT91f6jiZXVRmkX8RN7t`
- Source transaction shape:
  - `type`: `Purchase`
  - `source`: `Wayfair`
  - `projectId`: `405GIhLoU2pLY4zqb71R`
  - `budgetCategoryId`: `da556858-1df8-40be-b10c-b15710d7cc9a` (`Furnishings`)
  - `amountCents`: `1867761`
  - `subtotalCents`: `1822565`

The source transaction is a normal project Purchase from Wayfair. The two nightstands were not originally purchased from business inventory, so the missing source-side hop should be Sale-to-Inventory, not Return-to-Inventory.

### Destination Project

- Project: `fc4e8569-75f6-46b4-97ae-c4bc57f615d0` (`Sandra- BAHAMA Unit`)
- Existing destination transaction: `E614DE46-40F0-4D95-99EC-CD9F2E59432C`
- Destination transaction shape:
  - `type`: `Purchase`
  - `source`: `1584 Design Inventory`
  - `projectId`: `fc4e8569-75f6-46b4-97ae-c4bc57f615d0`
  - `budgetCategoryId`: `da556858-1df8-40be-b10c-b15710d7cc9a` (`Furnishings`)
  - `amountCents`: `98998`
  - `subtotalCents`: `98998`
  - `itemIds`: `Dcysdan3I84AOmFMfrMd`, `H11MvVi0hAmeTmTF8qaz`
  - `createdAt`: `2026-06-24T00:10:10.732Z`
  - `createdBy`: `4ef35958-597c-4aea-b99e-1ef62352a72d`

### Existing Lineage

Existing intent edges:

- `tmmuvn4UJV73mexmPOn8`: `Dcysdan3I84AOmFMfrMd`, `movementKind: sold`
- `FV8SXc5W2Qk1kQy7L2or`: `H11MvVi0hAmeTmTF8qaz`, `movementKind: sold`

Both point from:

- `fromTransactionId`: `dT91f6jiZXVRmkX8RN7t`
- `fromProjectId`: `405GIhLoU2pLY4zqb71R`

to:

- `toTransactionId`: `E614DE46-40F0-4D95-99EC-CD9F2E59432C`
- `toProjectId`: `fc4e8569-75f6-46b4-97ae-c4bc57f615d0`

Existing server association edges also exist for both items from the same source transaction to the destination transaction.

No existing Sale-to-Inventory or Return-to-Inventory first-hop transaction was found for these two items near the destination transaction timestamp.

## Classification

Both items should be treated as project-originated for this repair.

Reason: the historical source transaction is a project Purchase from `Wayfair`, not an inventory-sourced Purchase from `1584 Design Inventory`. Under the current doctrine, project-originated item leaving a project for business inventory is a Sale-to-Inventory at purchase price.

## Proposed Append-Only Writes

Do not move the items again. Their current item docs already point at the destination project and destination Purchase.

### 1. Create Missing First-Hop Transaction

Path:

`accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94/transactions/REPAIR_SALE_TO_INVENTORY_20260624_001`

Data:

```json
{
  "type": "Sale",
  "source": "1584 Design Inventory",
  "projectId": "405GIhLoU2pLY4zqb71R",
  "amountCents": 98998,
  "subtotalCents": 98998,
  "itemIds": [
    "Dcysdan3I84AOmFMfrMd",
    "H11MvVi0hAmeTmTF8qaz"
  ],
  "isComplete": true,
  "transactionDate": "6/23/2026",
  "createdAt": "2026-06-24T00:10:10.732Z",
  "updatedAt": "SERVER_TIMESTAMP",
  "createdBy": "4ef35958-597c-4aea-b99e-1ef62352a72d",
  "notes": "[AI 6/24/2026] Repair: backfilled missing source-side Sale-to-Inventory hop for project-to-project sale of two Regan 3-Drawer Nightstand items (SKU W004254185). Items originated in source project transaction dT91f6jiZXVRmkX8RN7t from Wayfair and were sold into destination project transaction E614DE46-40F0-4D95-99EC-CD9F2E59432C through 1584 Design Inventory."
}
```

Superseding note, 2026-06-25: the Sale-to-Inventory repair should carry transaction `budgetCategoryId` for source-project accounting. The earlier no-`budgetCategoryId` shape was wrong because it confused item placement state with transaction accounting attribution.

### 2. Create First-Hop Intent Lineage Edges

Create one auto-ID document per item under:

`accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94/lineageEdges`

Edge for `Dcysdan3I84AOmFMfrMd`:

```json
{
  "accountId": "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94",
  "itemId": "Dcysdan3I84AOmFMfrMd",
  "fromProjectId": "405GIhLoU2pLY4zqb71R",
  "fromTransactionId": "dT91f6jiZXVRmkX8RN7t",
  "toTransactionId": "REPAIR_SALE_TO_INVENTORY_20260624_001",
  "movementKind": "soldToInventory",
  "source": "repair",
  "createdAt": "SERVER_TIMESTAMP",
  "createdBy": "4ef35958-597c-4aea-b99e-1ef62352a72d",
  "note": "Repair backfill: missing first-hop Sale-to-Inventory for project-to-project sale into E614DE46-40F0-4D95-99EC-CD9F2E59432C."
}
```

Edge for `H11MvVi0hAmeTmTF8qaz`:

```json
{
  "accountId": "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94",
  "itemId": "H11MvVi0hAmeTmTF8qaz",
  "fromProjectId": "405GIhLoU2pLY4zqb71R",
  "fromTransactionId": "dT91f6jiZXVRmkX8RN7t",
  "toTransactionId": "REPAIR_SALE_TO_INVENTORY_20260624_001",
  "movementKind": "soldToInventory",
  "source": "repair",
  "createdAt": "SERVER_TIMESTAMP",
  "createdBy": "4ef35958-597c-4aea-b99e-1ef62352a72d",
  "note": "Repair backfill: missing first-hop Sale-to-Inventory for project-to-project sale into E614DE46-40F0-4D95-99EC-CD9F2E59432C."
}
```

### 3. Do Not Update Item Docs

No item-field writes are proposed.

Reason: both item docs already point at the destination project/category/transaction:

- `projectId`: `fc4e8569-75f6-46b4-97ae-c4bc57f615d0`
- `budgetCategoryId`: `da556858-1df8-40be-b10c-b15710d7cc9a`
- `transactionId`: `E614DE46-40F0-4D95-99EC-CD9F2E59432C`
- `currentSource`: `1584 Design Inventory`

### 4. Do Not Update Existing Lineage Edges

No existing lineage edge should be edited or deleted. Lineage is append-only. The existing `sold` edges and server `association` edges remain as the destination hop / audit evidence.

### 5. Do Not Update Source Transaction `itemIds`

No source-transaction array update is proposed. The source transaction `dT91f6jiZXVRmkX8RN7t` already no longer contains either item in `itemIds`.

## Accounting Caveat

The append-only writes above restore the missing first-hop transaction and intent lineage trail, but there is a code-level budget-rollup caveat:

- The repair Sale-to-Inventory transaction should have `budgetCategoryId`.
- The deployed `recalculateProjectBudgetSummary` function only includes transactions that have a `budgetCategoryId`; source-project egress also needs negative sign handling.
- Therefore, creating this no-category Sale-to-Inventory transaction will not, by itself, decrement the source project's denormalized `budgetSummary`.

The source transaction audit is already complete because the existing direct `sold` edges from `dT91f6jiZXVRmkX8RN7t` count both items as sold:

- `soldItemsCount`: `2`
- `soldItemsSumCents`: `98998`
- `varianceCents`: `0`

Before write-mode repair, decide how to handle the budget/accounting layer:

1. Apply only the append-only trail repair above, then fix/deploy budget rollup semantics separately.
2. First patch budget rollup semantics so project-to-inventory Sale transactions affect source-project spend correctly, then apply this repair.
3. Manually patch the source project `budgetSummary` as a temporary production correction, understanding the next budget recompute may overwrite it until the code-level rollup is fixed.

Recommendation: use option 2 for durable accounting correctness.

## Post-Write Verification Checklist

After approved write mode:

- Re-read `REPAIR_SALE_TO_INVENTORY_20260624_001`.
- Re-read both item docs and confirm no item fields changed.
- Re-read lineage for both items and confirm each now has:
  - `soldToInventory` first-hop edge to `REPAIR_SALE_TO_INVENTORY_20260624_001`
  - existing `sold` destination edge to `E614DE46-40F0-4D95-99EC-CD9F2E59432C`
  - existing `association` audit edge to `E614DE46-40F0-4D95-99EC-CD9F2E59432C`
- Re-read source transaction `dT91f6jiZXVRmkX8RN7t` audit.
- Re-read destination transaction `E614DE46-40F0-4D95-99EC-CD9F2E59432C` audit.
- Re-read source and destination project budget summaries after Functions drain.
