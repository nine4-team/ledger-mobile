# Correction Spec Before/After Draft

> Saved August 23, 2026. This is an unapproved audit artifact preserving the exact correction-related before/after list presented in chat. It is not an active specification.

Unrelated pricing changes are omitted.

## 1. Correct / Move Label

### Before

> **Correct / Move** — corrections only, no financial impact. Within-scope reassignment.

### Proposed

> **Correct / Move** — corrections only, no new financial event. Transaction corrections and item corrections are separate operations.

## 2. Correct / Move Definition

### Before

> Correct/Move reassigns an item from one transaction to another **within the same scope** (same project, or within business inventory). No financial impact — no new transactions are created, no budget amounts change. The "Correct" half of the label signals intent (this is a data fix, not a business event); the "Move" half describes the mechanic (the item is being relocated between transactions).

### Proposed

> Correct/Move fixes recorded data without inventing a Sale, Return, or Purchase movement. A transaction correction changes transaction fields. An item correction changes item fields, either by fixing its transaction link or by fixing a wrongly recorded project/inventory scope. Correcting a transaction does not implicitly correct its linked items, and correcting items does not implicitly rewrite their transaction.
>
> The correction can change which project budget displays the original purchase, because it fixes where that purchase always belonged. That corrected accounting attribution is not a new financial event.

## 3. Correct / Move Validation

### Before

> - Source and destination must be in the same scope (same projectId, or both null for business inventory)
> - If scopes differ, the operation is a Sell, not a Correct/Move

### Proposed

> - A transaction-link reassignment must leave the item and destination transaction in a consistent scope.
> - A project/inventory scope change is a correction only when the prior scope was a recording mistake.
> - If the item actually changed scopes as a business event, the operation is a Sell or Return, not a Correct/Move.

## 4. Item Correction Section

### Before

> This section did not exist. The specification only described moving an item between transactions within the same project or within inventory.

### Proposed

> ### Item Scope Correction
>
> Use this when an item's recorded project or inventory scope is wrong. Correct only the item document:
>
> - Set `item.projectId` to the scope where the item was always supposed to be recorded.
> - Set `item.budgetCategoryId` consistently: null in inventory, or the corrected project category in a project.
> - Clear `item.spaceId` when its existing space belongs to the wrong scope.
> - Preserve `item.transactionId` unless correcting the transaction association is a separate requested change.
> - Write `correction` lineage for the item scope fix.
> - Create no Sale, Return, or Purchase movement transaction.

## 5. Transaction Correction Section

### Before

> This section did not exist.

### Proposed

> ### Transaction Correction
>
> Use this path when the original transaction was recorded under the wrong project or category:
>
> - Update only the original transaction's `projectId` and `budgetCategoryId`.
> - Preserve the transaction ID and `itemIds` membership.
> - Do not update linked item documents as a side effect.
> - Create no Sale, Return, or Purchase movement transaction.
>
> For a Purchase corrected into business inventory, set:
>
> `transaction.projectId = null`
>
> `transaction.budgetCategoryId = null`
>
> `transaction.purchaseHandling = inventory_resale`
>
> `transaction.reimbursementType = none`
>
> If linked items were also misfiled, correct those items separately. Their item correction sets `projectId` and `budgetCategoryId` to null and clears project-scoped `spaceId`, while preserving `transactionId`. Verify the transaction and item corrections before recording later business events.
>
> Any later inventory-to-project disposition is a separate, real **Sell** operation. This distinction allows one misfiled acquisition to be corrected into inventory first and then split across multiple destination projects while unsold items remain attached to the original inventory acquisition.

## 6. Decision Matrix Additions

### Before

> There were no rows covering a transaction or item that had been recorded against the wrong project.

### Proposed Transaction Row

> Source: Purchase transaction recorded in Project A but belongs in inventory
>
> Destination: Business Inventory
>
> User-facing action: **Correct / Move → Move to Inventory**
>
> Underlying mechanics: Correct the transaction only; correct misfiled items separately
>
> Financial impact: No new financial event

### Proposed Item Row

> Source: Item recorded in Project A but always belonged in inventory
>
> Destination: Business Inventory
>
> User-facing action: **Correct / Move**
>
> Underlying mechanics: Correct item `projectId`/`budgetCategoryId`; preserve its transaction link
>
> Financial impact: No new financial event

## 7. Correct / Move Availability

### Before

> - Item is linked to a transaction
> - Other transactions exist in the same scope (same projectId, or both null for business inventory)
> - Framed in the UI as a correction — no money moves, no Sale or Return created

### Proposed

> - An item is linked to another transaction in the same scope, or an ordinary non-movement transaction was recorded in the wrong project/inventory scope.
> - Transaction-level **Move to Inventory** is hidden for immutable generated inventory movements and transactions already in inventory.
> - The action is framed as a correction: no Sale, Return, or Purchase movement is created.

## 8. Inventory-As-Store Correction Section

### Before

> This section did not exist.

### Proposed

> ### Correcting a misfiled transaction into inventory
>
> If an original vendor Purchase was recorded against a project by mistake, **Move to Inventory** on that transaction is a transaction correction, not an inventory movement:
>
> - Correct only the original transaction to `projectId == null` and `budgetCategoryId == null`.
> - Preserve its transaction ID and active `itemIds` membership.
> - Mark the Purchase as `purchaseHandling == inventory_resale` with no project reimbursement owed.
> - Create no Sale, Return, or Purchase movement transaction.
>
> Items are separate records. If linked items were also recorded against the wrong project, correct them in a separate item operation by setting their `projectId` and `budgetCategoryId` to null and clearing project-scoped `spaceId` values. Preserve their `transactionId` links to the corrected inventory Purchase.
>
> After verifying both the transaction and item corrections, any items that really leave inventory use the normal sell-to-project operation. Items not sold remain attached to the corrected inventory acquisition.

## 9. Real Movement Into Inventory

### Before

> ### Moving into inventory — routed by item origin
>
> The user performs a single **Return to Inventory** action. The service routes each item based on origin:

### Proposed

> ### Moving into inventory — routed by item origin
>
> This section applies to a real disposition after the items were correctly recorded in a project. It does not apply to **Move to Inventory** under Correct / Move. The user performs an explicit **Return to Inventory** or **Sell to Business Inventory** action, and the service routes each item based on origin:

The remaining origin-routing language was not changed.

## 10. Purchase-Handling Inverse Correction

### Before

> The specification only defined the opposite correction: a Purchase mistakenly routed to inventory that should have been a covered project purchase.

### Proposed

> The inverse is also a correction: a vendor Purchase mistakenly recorded in a project but actually acquired for inventory resale must be corrected in place. Transactions and items are separate records, so this requires two explicit corrections rather than one implicit cascade:
>
> 1. Correct the original Purchase to business inventory, clear its project budget category, set `purchaseHandling = inventory_resale`, and set `reimbursementType = none`.
> 2. Separately correct the affected items to business inventory, clear their project budget categories and project-scoped spaces, and preserve their `transactionId`.
>
> Neither correction creates a Sale, Return, or Purchase movement transaction. Verify both entity types before continuing.
>
> Any later disposition from inventory to one or more projects is recorded through separate canonical sell-to-project operations. Unsold items remain on the original inventory acquisition.

## 11. MCP Requirement

### Before

> No requirement explicitly said that `projectId` and `budgetCategoryId` could be cleared to null during a transaction correction.

### Proposed Addition

> - correct ordinary transaction scope, including clearing `projectId` and `budgetCategoryId` to explicit null for business inventory, without inventing a movement event;

## 12. Repository Doctrine

### Before

> There was no correction-specific doctrine here.

### Proposed Addition

> **Corrections are not inventory movements.** Transactions and items are separate records. If both were misfiled, correct the transaction and items with separate operations; neither correction creates a Sale, Return, or Purchase movement. Any later sell from inventory is a separate real event.

## Unapproved Assumptions Embedded In The Draft

1. A Purchase transaction corrected to inventory also changes `purchaseHandling` to `inventory_resale` and `reimbursementType` to `none`.
2. An item corrected to inventory clears a project-scoped `spaceId` while preserving its `transactionId`.
