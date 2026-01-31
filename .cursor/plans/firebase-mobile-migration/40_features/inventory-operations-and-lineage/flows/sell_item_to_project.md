## Flow: Sell item to another project

## Intent
Move an item from a source project into a different target project using deterministic canonical mechanics, with explicit partial completion handling.

## Preconditions
- Item exists and is currently in `sourceProjectId`.
- `targetProjectId != sourceProjectId`.
- Item is eligible for canonical multi-entity operations (Firebase permissions, any required guardrails like known `inheritedBudgetCategoryId`).

Parity evidence:
- Preconditions and error codes: `sellItemToProject` in `src/services/inventoryService.ts` (`SellItemToProjectError`).

## Behavior contract

### Step 1: Deallocate from source project into Business Inventory
Perform the canonical deallocation path (or purchase-reversion if applicable):
- Expected canonical sale bucket: `INV_SALE_<sourceProjectId>` (unless purchase-reversion causes null)

Parity evidence:
- `sellItemToProject` calls `deallocationService.handleInventoryDesignation(...)` in `src/services/inventoryService.ts`.

### Step 2: Allocate into target project
Allocate to canonical purchase bucket:
- `INV_PURCHASE_<targetProjectId>`

Parity evidence:
- `sellItemToProject` calls `allocateItemToProject(...)` in `src/services/inventoryService.ts`.

### Step 3: Partial completion handling (required)
If allocation fails after deallocation succeeds:
- The user must be told: “Item was moved to business inventory. Allocate it to the target project from there.”
- The operation should record enough state so the UI can recover deterministically (the item is now in Business Inventory, linked to `INV_SALE_<sourceProjectId>` or null depending on purchase-reversion).

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
