## Flow: Project → Business Inventory

This flow defines two distinct user intents that both result in “item ends up in Business Inventory,” but with different correctness requirements.

## A) Move to Business Inventory (correction path)

### Intent
The user is correcting scope: “This item should be in Business Inventory,” without creating canonical inventory transactions.

### Preconditions
- Item exists and is currently in the source project.
- Item is **not tied to any transaction**.

### Behavior contract
- If item has `transactionId != null`, block the action:
  - Copy: `This item is tied to a transaction. Move the transaction instead.`
- Apply item update:
  - `projectId = null`
  - `transactionId = null`
- Append lineage edge (best-effort):
  - `fromTransactionId = item.latestTransactionId ?? null`
  - `toTransactionId = null`
  - Update pointers: `latestTransactionId = null`

Parity evidence:
- Guard + error: `src/pages/ItemDetail.tsx` (`handleMoveToBusinessInventory`)
- Core mutation: `src/services/inventoryService.ts` (`moveItemToBusinessInventory`)

## B) Deallocate/Sell to Business Inventory (canonical path)

### Intent
The user is designating the item as “inventory,” which must preserve canonical sale mechanics and lineage.

Primary entrypoints in web:
- “Sell to Design Business” action
- “Sell/Deallocate to Business Inventory” action from the project items list or item detail

### Preconditions
- Item exists.
- Project → Business Inventory sell/deallocate requires the item to have a resolved budget category id (currently `item.budgetCategoryId`).
  - If missing, prompt the user to select a category from the **source project’s enabled categories**, persist it onto the item, then proceed.
  - Source of truth: `40_features/project-items/flows/inherited_budget_category_rules.md`.

### Behavior contract (canonical)

#### Step 1: Load item and resolve “previous project link”
Resolve these for later metadata preservation:
- `previousProjectTransactionId`
- `previousProjectId`

Parity evidence:
- `_resolvePreviousProjectLink` in `src/services/inventoryService.ts` (`deallocationService`).

#### Step 2: Allocation-reversion exception (required)
If the item is currently linked to the canonical sale transaction for:
- `(projectId = sourceProjectId, direction = "business_to_project", budgetCategoryId = item budget category id)`

…treat this as an allocation mistake being undone:
- Remove item from that canonical sale transaction (preserve empty canonical rows for lineage/history).
- Update item to Business Inventory:
  - `projectId = null`
  - `transactionId = null`
  - preserve `previousProjectTransactionId` / `previousProjectId`
- Append lineage edge:
  - `fromTransactionId = <the canonical sale transaction id>`
  - `toTransactionId = null`

Parity evidence:
- Web parity has a purchase-reversion branch in `deallocationService.handleInventoryDesignation` in `src/services/inventoryService.ts`.
  Firebase migration delta: purchase buckets become direction-coded canonical sale transactions, so the reversion checks the `business_to_project` canonical sale row instead.

#### Step 3: Canonical sale path (default)
Otherwise:
- Ensure canonical sale transaction exists/updates (category-split):
  - `saleTransactionId = canonicalSaleTransactionId(sourceProjectId, "project_to_business", budgetCategoryId)`
  - Add this item to the canonical sale transaction and recompute amount (sum of item values in this category bucket).
- Update item to Business Inventory and link it to the sale transaction:
  - `projectId = null`
  - `transactionId = saleTransactionId`
  - Clear `space` (scope move)
  - preserve `previousProjectTransactionId` / `previousProjectId`
- Append lineage edge:
  - `fromTransactionId = item.transactionId || null` (pre-move)
  - `toTransactionId = saleTransactionId`

Parity evidence:
- `deallocationService.ensureSaleTransaction` and subsequent item update in `src/services/inventoryService.ts`.

### Offline-ready / request-doc requirement (Firebase)
Represent the canonical deallocate operation as **one request doc** with one idempotency key that the server uses to avoid duplication on retry.
The server processes the request and applies the multi-doc write set in a Firestore transaction (see `OFFLINE_FIRST_V2_SPEC.md` → request-doc workflows).
Retry model: create a new request doc with the same `opId` (see `feature_spec.md` → “Request-doc collection + payload shapes”).

Parity evidence (web outbox; intentional delta vs Firebase request-doc):
- `DEALLOCATE_ITEM_TO_BUSINESS_INVENTORY` op: `src/types/operations.ts`
- Execution: `executeDeallocateItemToBusinessInventory` in `src/services/operationQueue.ts`
