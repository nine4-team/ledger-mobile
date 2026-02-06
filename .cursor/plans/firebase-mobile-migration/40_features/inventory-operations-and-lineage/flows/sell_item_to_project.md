## Flow: Sell item to another project

## Intent
Move an item from a source project into a different target project using deterministic canonical mechanics, with explicit partial completion handling.

## Preconditions
- Item exists and is currently in `sourceProjectId`.
- `targetProjectId != sourceProjectId`.
- Item is eligible for canonical multi-entity operations (Firebase permissions).
- The operation must resolve:
  - `sourceBudgetCategoryId` (from the item, or prompt from the source project if missing)
  - `destinationBudgetCategoryId` (must be enabled/available in the target project; prompt if missing/mismatched)
  - Persist any prompted category choice back onto the item.

Parity evidence:
- Preconditions and error codes: `sellItemToProject` in `src/services/inventoryService.ts` (`SellItemToProjectError`).

## Behavior contract

### Step 1: Deallocate from source project into Business Inventory
Perform the canonical deallocation path (or allocation-reversion if applicable).

- **Expected canonical sale transaction**:
  - `canonicalSaleTransactionId(sourceProjectId, "project_to_business", sourceBudgetCategoryId)`
  - unless allocation-reversion applies, in which case the item ends in Business Inventory with `transactionId = null`.

Parity evidence:
- `sellItemToProject` calls `deallocationService.handleInventoryDesignation(...)` in `src/services/inventoryService.ts`.

### Step 2: Allocate into target project
Allocate via canonical sale transaction (direction = `business_to_project`):

- `canonicalSaleTransactionId(targetProjectId, "business_to_project", destinationBudgetCategoryId)`

Parity evidence:
- `sellItemToProject` calls `allocateItemToProject(...)` in `src/services/inventoryService.ts`.

### Step 3: Partial completion handling (required)
Firebase requirement:
- Preferred behavior is atomic (one request doc; one Firestore transaction), so “partial completion” should not occur.

If allocation fails after deallocation succeeds (only possible if the implementation ever becomes multi-stage):
- The user must be told: “Item was moved to business inventory. Allocate it to the target project from there.”
- The operation should record enough state so the UI can recover deterministically (the item is now in Business Inventory, linked to the source `project_to_business` canonical sale transaction or `null` depending on allocation-reversion).

Parity evidence:
- `SellItemToProjectError` code `PARTIAL_COMPLETION` and message handling in:
  - `src/services/inventoryService.ts`
  - UI handlers in `src/pages/ItemDetail.tsx` and `src/pages/TransactionDetail.tsx`

## Offline-ready / request-doc requirement (Firebase)
In Firebase, this must be a single server-owned operation represented by **one request doc** with a single idempotency key (`requestId` / `opId`), even though it writes multiple documents.
The server processes the request and applies the multi-doc write set in a Firestore transaction (see `OFFLINE_FIRST_V2_SPEC.md` → request-doc workflows).
Retry model: create a new request doc with the same `opId` (see `feature_spec.md` → “Request-doc collection + payload shapes”).

Parity evidence (web outbox; intentional delta vs Firebase request-doc):
- `SELL_ITEM_TO_PROJECT` op type: `src/types/operations.ts`
- Queue execution: `executeSellItemToProject` in `src/services/operationQueue.ts`
