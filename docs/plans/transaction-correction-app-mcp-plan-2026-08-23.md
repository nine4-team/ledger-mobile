# Transaction Correction App and MCP Repair Plan

Status: Temporary implementation plan saved for the August 23, 2026 repair. This is not an active product specification.

## Confirmed Contract

- Transaction Correct / Move and item Correct / Move are distinct operations.
- Correcting an ordinary transaction from a project into business inventory updates the original transaction in place.
- The transaction correction sets `projectId` and `budgetCategoryId` to null.
- The transaction correction preserves the transaction ID and `itemIds` membership.
- The transaction correction does not update linked item documents.
- The transaction correction creates no Sale, Return, Purchase, or movement lineage.
- Linked items are corrected separately when requested.
- Any later inventory-to-project sale is a separate real inventory operation.
- Generated inventory-movement transactions retain their frozen accounting shape and cannot use this correction path.
- This repair does not infer or rewrite `purchaseHandling`, `reimbursementType`, intended-destination fields, prices, spaces, or lineage.

## Plan A: Repair the App Regression

1. Restore transaction-level Move to Inventory in `TransactionDetailView` as an in-place transaction update.
2. Write only `projectId = null` and `budgetCategoryId = null` for that correction.
3. Do not call `InventoryOperationsService.moveToInventory`, `returnToInventory`, or any item movement operation.
4. Keep the action unavailable when the transaction is already inventory-scoped.
5. Keep the existing `TransactionMenuBuilder` guard that suppresses Correct / Move for generated immutable inventory movements.
6. Add focused testable calculation/command coverage proving the correction payload contains only the two scope fields and that inventory-scoped transactions have no Move to Inventory action.
7. Run the relevant iOS test suite or targeted tests and compile the affected app target.

## Plan B: Repair the MCP Schema Gap

1. Change `update_transaction.projectId` and `budgetCategoryId` to accept explicit null as well as string values.
2. When `projectId` is explicitly null, require or normalize `budgetCategoryId` to null so the transaction cannot retain a project category in inventory scope.
3. Do not rewrite items, purchase-intent fields, reimbursement fields, prices, spaces, or lineage.
4. Preserve the existing server-side immutability guard for generated inventory-movement transactions.
5. Update the tool description so agents understand that this is an in-place transaction correction and that linked items must be corrected separately.
6. Add MCP tests proving:
   - an ordinary project Purchase can be corrected to inventory;
   - the original transaction ID and `itemIds` are preserved;
   - no Sale or Return is created;
   - purchase-intent and reimbursement fields are untouched;
   - generated inventory movements reject the scope change.
7. Run MCP build and focused tests.

## Documentation Cleanup

1. Remove the unapproved broad rewrite that merged transaction correction into the item-focused `reassign-vs-sell.md` contract.
2. Keep the saved before/after audit artifact unchanged as a historical record.
3. Add only narrowly scoped MCP/app documentation required to describe the repaired behavior, without redefining existing item correction semantics.

## Completion Criteria

- App Move to Inventory corrects only the selected ordinary transaction.
- MCP `update_transaction` accepts `projectId: null` and performs the same narrow correction.
- Neither path initiates a Sale, Return, Purchase, item update, or lineage write.
- Immutable generated inventory movements remain protected.
- Relevant tests and builds pass.
