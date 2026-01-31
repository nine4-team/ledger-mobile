# Prompt Pack: Multi-entity ops + idempotency (Inventory operations)

## Goal
You are helping migrate Ledger to **React Native + Firebase** with the **Offline Data v2** architecture:
- Native Firestore offline persistence is the baseline (“Magic Notebook”)
- Multi-doc correctness uses **request-doc workflows** (server applies changes in a Firestore transaction)
- Listeners are allowed but must be **scoped/bounded** (no unbounded “listen to everything”)

Your job in this chat:
- Tighten and complete the **multi-entity operation contracts** for inventory operations so implementation can be done via server-owned invariants (Callable Functions / Firestore transactions) with idempotency.

## Outputs (required)
Update/create only these docs:
- `40_features/inventory-operations-and-lineage/feature_spec.md`
- `40_features/inventory-operations-and-lineage/acceptance_criteria.md`
- `40_features/inventory-operations-and-lineage/flows/project_to_business_inventory.md`
- `40_features/inventory-operations-and-lineage/flows/business_inventory_to_project_allocation.md`
- `40_features/inventory-operations-and-lineage/flows/sell_item_to_project.md`

## Source-of-truth code pointers
Use these as the canonical references for parity:
- Canonical op implementations: `src/services/inventoryService.ts`
  - `allocateItemToProject`
  - `sellItemToProject`
  - `moveItemToBusinessInventory`
  - `deallocationService.handleInventoryDesignation`
- Offline queue + invariants:
  - `src/types/operations.ts`
  - `src/services/operationQueue.ts` (`executeDeallocateItemToBusinessInventory`, `executeAllocateItemToProject`, `executeSellItemToProject`, `verifyCanonicalInvariants`)
- UI entrypoints (to ensure UX/copy is consistent with what operations can do):
  - `src/pages/ItemDetail.tsx`
  - `src/pages/InventoryList.tsx`
  - `src/pages/BusinessInventory.tsx`
  - `src/pages/TransactionDetail.tsx`

## What to capture (required)
- **Request-doc payload shapes** (what the client writes as the request doc)
- **Idempotency strategy** (server-owned, `requestId` / `opId`)
- **Preconditions + conflict semantics** (expected current state checks)
- **Atomic write set** per operation (which docs must be written together)
- **Partial completion semantics** (especially sell-to-project)

## Evidence rule (anti-hallucination)
For each non-obvious behavior:
- Provide **parity evidence**: point to where it is observed in the current codebase (file + component/function), OR
- Mark as an **intentional delta** and explain why (Firebase correctness/cost constraints).

## Constraints / non-goals
- Do not prescribe “subscribe to everything” listeners; realtime must use scoped/bounded listeners per `OFFLINE_FIRST_V2_SPEC.md`.
- Do not do pixel-perfect design specs; focus on correctness and offline behavior.
