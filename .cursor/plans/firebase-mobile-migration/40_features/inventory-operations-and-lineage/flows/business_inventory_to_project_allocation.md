## Flow: Business Inventory → Project allocation

## Intent
Move one or more Business Inventory items into a target project, updating canonical **sale** mechanics (direction = `business_to_project`) and lineage deterministically.

## Preconditions
- Item exists.
- Target project exists and user has permission.
- The operation must resolve a **destination project budget category id** for the item:
  - If the item already has a category id and it is enabled/available in the destination project, use it.
  - Otherwise prompt the user to choose a category from the destination project.
  - Persist the result onto the item (currently `item.inheritedBudgetCategoryId`).
  Source of truth: `40_features/project-items/flows/inherited_budget_category_rules.md`.

## Behavior contract (single item)

### Step 1: Determine expected canonical sale transaction (direction = `business_to_project`)
- `saleTransactionId = canonicalSaleTransactionId(projectId, "business_to_project", budgetCategoryId)`

Parity evidence:
- Web parity uses a canonical purchase bucket (`INV_PURCHASE_<projectId>`) in `allocateItemToProject`.
  Firebase migration delta: we replace purchase buckets with **category-split canonical sale transactions** and track direction explicitly.

### Step 2: Deterministic state machine for current canonical linkage
Allocation must handle items currently in:
- a canonical sale transaction (any project / either direction)
- no `transactionId` (inventory)

If the item is already in the destination project but linked to a different canonical sale transaction (wrong direction or wrong category), the server must re-home it into the correct canonical sale transaction for `(targetProjectId, "business_to_project", budgetCategoryId)` without creating duplicates.

Parity evidence:
- Deterministic branching in `allocateItemToProject` in `src/services/inventoryService.ts` (“Scenario A/B/C”).

### Step 3: Apply updates atomically (Firebase requirement)
Allocation is a multi-entity update (item + canonical transaction + lineage). In Firebase it must be server-owned and transactional.

Minimum resulting item state:
- `projectId = <projectId>`
- `transactionId = canonicalSaleTransactionId(projectId, "business_to_project", budgetCategoryId)`
- `status = purchased` (or equivalent)
- optional: set/clear `space` as selected

Parity evidence (web):
- Item updates and canonical bucket mechanics live in `src/services/inventoryService.ts`.
  Firebase migration delta: canonical row identity changes but the invariant “single deterministic canonical row per bucket” remains.

### Step 4: Lineage
Append lineage edge representing the move:
- inventory (null) → `saleTransactionId` when allocating from inventory
- or `oldTransactionId` → `saleTransactionId` when re-homing between canonical sale rows

Parity evidence:
- `lineageService.appendItemLineageEdge` calls inside allocation helpers in `src/services/inventoryService.ts`.

## Offline-ready / request-doc requirement (Firebase)
Represent allocation as **one request doc** with one idempotency key (`requestId` / `opId`), using `type = ITEM_SALE_BUSINESS_TO_PROJECT`.
The server processes the request and applies the multi-doc write set in a Firestore transaction (see `OFFLINE_FIRST_V2_SPEC.md` → request-doc workflows).
Retry model: create a new request doc with the same `opId` (see `feature_spec.md` → “Request-doc collection + payload shapes”).

Parity evidence (web outbox; intentional delta vs Firebase request-doc):
- `ALLOCATE_ITEM_TO_PROJECT` op: `src/types/operations.ts`
- Execution: `executeAllocateItemToProject` in `src/services/operationQueue.ts`

## Batch allocation (optional parity detail)
The current web service supports batch allocation, updating the same canonical bucket. In the new model, batch allocation targets the same canonical sale transaction for the chosen destination category.

Parity evidence:
- Batch allocate comment and implementation near `Batch allocate multiple items...` in `src/services/inventoryService.ts`.
