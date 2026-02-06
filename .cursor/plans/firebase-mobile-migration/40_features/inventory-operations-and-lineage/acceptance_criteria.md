# Inventory operations + lineage — Acceptance criteria (parity + Firebase deltas)

Each non-obvious criterion includes **parity evidence** (web code pointer) or is labeled **intentional delta** (Firebase mobile requirement).

## Canonical transaction ids (system-owned)
- [ ] **Canonical detection**: Canonical inventory transactions are detected as **canonical sale transactions**.
  Recommended detection:
  - `transaction.isCanonicalInventorySale === true`, or
  - deterministic id prefix `INV_SALE__`.
  Web parity evidence (old model): `src/services/inventoryService.ts` (`CANONICAL_TRANSACTION_PREFIXES`, `isCanonicalTransactionId`).
- [ ] **Canonical invariants are checkable** after multi-entity ops apply (projectId/transactionId expectations).  
  Web parity evidence: `src/services/operationQueue.ts` (`verifyCanonicalInvariants`).
  Firebase mobile delta: invariants are enforced by server-owned request-doc processing (not an explicit client outbox flush).

## Project → Business Inventory (Move: correction path)
- [ ] **Blocked when transaction-attached**: “Move to business inventory” is blocked when the item is tied to any transaction (canonical or non-canonical) with copy that instructs the user to move the transaction instead.  
  Observed in `src/services/inventoryService.ts` (`moveItemToBusinessInventory` throws `TRANSACTION_ATTACHED`) and `src/pages/ItemDetail.tsx` (shows error).
- [ ] **Move updates scope without canonical sale**: Move correction sets `projectId = null`, `transactionId = null`.  
  Observed in `src/services/inventoryService.ts` (`moveItemToBusinessInventory`).
- [ ] **Move appends lineage edge** from previous transaction (or null) to null and updates pointers (best-effort).  
  Observed in `src/services/inventoryService.ts` (`moveItemToBusinessInventory` uses `lineageService.*`).

## Project → Business Inventory (Deallocate/Sell: canonical path)
- [ ] **Sell/deallocate action triggers canonical deallocation**: initiating “Sell/Deallocate to Business Inventory” triggers the canonical deallocation flow.  
  Observed in `src/pages/InventoryList.tsx` / `src/pages/BusinessInventory.tsx` (item actions that call `integrationService.handleItemDeallocation`).
- [ ] **Deallocation is offline-queueable (Firebase)**: the user can initiate deallocation while offline and see “saved offline” messaging.  
  Web parity evidence: `src/services/inventoryService.ts` (outbox enqueue in `integrationService.handleItemDeallocation`) and UI offline messaging in `src/pages/ItemDetail.tsx`.
  Firebase mobile delta: operation is queued by Firestore-native offline persistence as a **request doc**; the server applies the multi-doc invariant when the request reaches the backend.
- [ ] **Allocation-reversion exception (new model)**: if the item is linked to the canonical sale transaction for:
  - `(projectId = sameProjectId, direction = business_to_project, budgetCategoryId = item budget category id)`
  - deallocation removes it from that canonical sale row and returns to Business Inventory **without creating** a `project_to_business` canonical sale row.
  - Web parity evidence (old model): `deallocationService.handleInventoryDesignation` purchase-reversion branch.
- [ ] **Otherwise canonical sale**: deallocation ensures the canonical sale transaction exists/updates for:
  - `(projectId = sourceProjectId, direction = project_to_business, budgetCategoryId = item budget category id)`
  - moves the item to Business Inventory, and links the item to that canonical sale transaction.
- [ ] **Lineage edge appended** for deallocation moves (best-effort) and pointers updated.  
  Observed in `src/services/inventoryService.ts` (`deallocationService.handleInventoryDesignation`) and `src/services/lineageService.ts`.

## Business Inventory → Project (Allocate: canonical sale, direction = business_to_project)
- [ ] **Allocate creates/updates canonical sale**: allocating to project links the item to the canonical sale transaction for:
  - `(projectId = targetProjectId, direction = business_to_project, budgetCategoryId = resolved destination category)`.
- [ ] **Allocate is offline-queueable (Firebase)**: the user can allocate while offline and see “saved offline” messaging; on apply, the canonical id is deterministic via `canonicalSaleTransactionId(projectId, direction, budgetCategoryId)`.  
  Web parity evidence: `src/services/inventoryService.ts` (outbox path) and `src/services/operationQueue.ts`.
  Firebase mobile delta: allocation is queued as a request doc; server applies and client observes status + resulting doc changes.

## Project → Project (Sell item to another project)
- [ ] **Two-phase canonical behavior**: sell-to-project performs a deallocation step then an allocation step.  
  Observed in `src/services/inventoryService.ts` (`sellItemToProject`).
- [ ] **Offline behavior (Firebase)**: selling to project is queueable offline (via request doc), producing deterministic canonical sale ids:
  - `canonicalSaleTransactionId(sourceProjectId, "project_to_business", sourceBudgetCategoryId)`
  - `canonicalSaleTransactionId(targetProjectId, "business_to_project", destinationBudgetCategoryId)`
  when applied.  
  Web parity evidence: `src/services/inventoryService.ts` (outbox branch) and `src/types/operations.ts` (`SELL_ITEM_TO_PROJECT`).
- [ ] **Partial completion handling**: if the sale completes but allocation fails, user sees a message that the item is now in business inventory and must be allocated from there.  
  Observed in `src/services/inventoryService.ts` (`SellItemToProjectError` code `PARTIAL_COMPLETION`) and handling in `src/pages/ItemDetail.tsx` / `src/pages/TransactionDetail.tsx`.

## Lineage requirements
- [ ] **Append-only lineage edges** are recorded for cross-scope moves and can be fetched for an item history view.  
  Observed in `src/services/lineageService.ts` (`appendItemLineageEdge`, `getItemLineageHistory`).
- [ ] **Idempotency / duplicate suppression** exists for rapid repeated edge writes.  
  Observed in `src/services/lineageService.ts` (5-second duplicate window).
- [ ] **Pointers updated** so UI can show “latest transaction” without recomputing history.  
  Observed in `src/services/lineageService.ts` (`updateItemLineagePointers`).

## Budget-category determinism (Firebase)
- [ ] **BI → Project category prompt is conditional**: if the item’s current category is missing or not enabled/available in the destination project, the user is prompted and the selected destination category is persisted on the item (currently `inheritedBudgetCategoryId`).  
  **Intentional delta / required** by `40_features/project-items/flows/inherited_budget_category_rules.md`.
- [ ] **Project → BI category prompt is required when missing**: if the item’s category is missing, the user is prompted to pick a category from the source project and the selection is persisted onto the item before applying the canonical sale.
  Required by `40_features/project-items/flows/inherited_budget_category_rules.md`.

## Firebase-specific invariant enforcement (server-owned)
- [ ] **Multi-entity inventory ops are server-owned (required)**: not “best effort” client multi-write.  
  Required by `OFFLINE_FIRST_V2_SPEC.md` (request-doc workflows; server applies in a Firestore transaction).
- [ ] **Idempotency key (required)**: Each operation is safe under retry via a request id / op id and does not double-apply on reconnect or after app restart.  
  Required by `OFFLINE_FIRST_V2_SPEC.md` (request-doc correctness framework).
- [ ] **Retry model is explicit (required)**: default retry creates a *new* request doc with the same `opId` and the server treats `(type, opId)` as at-most-once.  
  Required by `OFFLINE_FIRST_V2_SPEC.md` (“Retry model: create a new request doc”).

## Collaboration / propagation (Firebase)
- [ ] **Scoped listeners only (required)**: clients may use listeners, but they must be bounded to the active scope and detach on background.  
  Required by `OFFLINE_FIRST_V2_SPEC.md`.
