# Feature spec: Inventory operations + lineage (Firebase mobile migration)

## Intent
Provide a deterministic, offline-first way to perform **cross-entity inventory operations** (allocate/move/sell/deallocate) while preserving:

- **Correctness** across items ↔ transactions ↔ projects
- **Idempotency** under retries (no double-sell / double-allocate)
- **Lineage visibility** (audit path and “where did this go?” cues)
- **Cost control** (scoped/bounded listeners only; avoid unbounded “listen to everything” patterns)

This spec is written for the React Native + Firebase target architecture described in `OFFLINE_FIRST_V2_SPEC.md`.

## Key definitions

### Scopes
- **Project scope**: item has `projectId = <projectId>`.
- **Business Inventory scope**: item has `projectId = null`.

### Canonical inventory transactions
Canonical inventory transactions are system-owned mechanics. Their ids use these prefixes:

- `INV_PURCHASE_<projectId>` — canonical purchase bucket used when allocating items into a project
- `INV_SALE_<projectId>` — canonical sale bucket used when moving items from a project into business inventory (except purchase-reversion)

Parity evidence:
- Canonical id detection: `isCanonicalTransactionId` in `src/services/inventoryService.ts`
- Canonical invariants verification for queued ops: `verifyCanonicalInvariants` in `src/services/operationQueue.ts`

### “Move” vs “Sell/Deallocate”
This migration must preserve the web distinction:

- **Move to business inventory (correction)**: scope correction for an item that is **not tied to a transaction**. Does **not** create/require a canonical sale.
- **Sell/Deallocate to business inventory (canonical)**: an inventory designation operation that **creates/updates `INV_SALE_<projectId>`**, unless it is a purchase-reversion case.

Parity evidence:
- Move correction blocks transaction-attached items: `moveItemToBusinessInventory` in `src/services/inventoryService.ts` and UI enforcement in `src/pages/ItemDetail.tsx`
- Canonical deallocation entrypoint: `integrationService.handleItemDeallocation` → `deallocationService.handleInventoryDesignation` in `src/services/inventoryService.ts`
- Sell/deallocate action triggers canonical deallocation: item actions calling `integrationService.handleItemDeallocation` (e.g. `src/pages/InventoryList.tsx`, `src/pages/BusinessInventory.tsx`)

## Architecture constraints (must hold)

### Firestore-native offline + request-doc correctness (default)
For operations that update multiple docs and enforce invariants, the default mechanism is **request docs**:

- Client writes a `request` doc describing the operation (works offline via Firestore-native offline persistence).
- A Cloud Function processes the request and applies all writes in a Firestore transaction.
- The request doc records `status` so the client can render `pending/applied/failed/denied` and offer retry.

Reference: `OFFLINE_FIRST_V2_SPEC.md` (“Request-doc workflows”).

### Server-owned invariants for multi-entity correctness (Firebase)
Multi-entity operations in this feature MUST be implemented as server-owned invariants, because they update multiple documents and must be idempotent under retries.

Required Firebase shape (conceptual):
- A request-doc workflow (recommended default) that triggers a Cloud Function and executes a Firestore transaction:
  - `ITEM_SALE_PROJECT_TO_BUSINESS`
  - `ITEM_SALE_BUSINESS_TO_PROJECT`
  - `ITEM_SALE_PROJECT_TO_PROJECT`

Each function must:
- Validate permissions (membership + role).
- Validate preconditions (expected current state; detect conflicts).
- Apply all document writes atomically (items + canonical transaction docs + lineage docs + request status updates).
- Use `opId` to make retries safe. (`requestId` is the Firestore doc id for a single attempt; retries create a new request doc with the same `opId`.)

### Request-doc collection + payload shapes (required)
This feature MUST define concrete request-doc shapes so implementation can be transactional, idempotent, and debuggable.

Collection shape (recommended; per `OFFLINE_FIRST_V2_SPEC.md`):
- Account-scoped requests: `accounts/{accountId}/requests/{requestId}`
  - Scope is encoded in `payload` (e.g. `payload.projectId` where applicable).

Common request doc fields:
- `type`: `"ITEM_SALE_PROJECT_TO_BUSINESS" | "ITEM_SALE_BUSINESS_TO_PROJECT" | "ITEM_SALE_PROJECT_TO_PROJECT"`
- `status`: `"pending" | "applied" | "failed" | "denied"` (clients write only `"pending"`)
- `createdAt`, `createdBy`
- `appliedAt?`
- `errorCode?`, `errorMessage?` (safe, non-sensitive)
- `opId`: stable idempotency key for the *logical* user action
- `payload`: minimal IDs + fields required for the invariant

Legacy request-type mapping (web app parity):

| Legacy name (older docs/web app) | Standardized name (this migration) |
|---|---|
| `INVENTORY_DEALLOCATE_TO_BUSINESS` | `ITEM_SALE_PROJECT_TO_BUSINESS` |
| `INVENTORY_ALLOCATE_TO_PROJECT` | `ITEM_SALE_BUSINESS_TO_PROJECT` |
| `INVENTORY_SELL_ITEM_TO_PROJECT` | `ITEM_SALE_PROJECT_TO_PROJECT` |

Retry + idempotency rules (required):
- **Default retry**: write a *new* request doc (new `requestId`) with the **same `opId`**.
- Server MUST treat `(type, opId)` as **at-most-once**:
  - if already applied, mark the new request as `applied` (or `failed` with a deterministic “already applied” code) without reapplying writes
  - if already failed, a new request with the same `opId` may retry depending on error type (policy must be explicit in implementation)

Payload shapes (minimum required fields):
- `ITEM_SALE_PROJECT_TO_BUSINESS`:
  - `itemId`, `sourceProjectId`
  - `expected`: `{ itemProjectId, itemTransactionId? }` (conflict detection / precondition)
- `ITEM_SALE_BUSINESS_TO_PROJECT`:
  - `itemId`, `targetProjectId`
  - `inheritedBudgetCategoryId` (required; see `40_features/project-items/flows/inherited_budget_category_rules.md`)
  - optional: `space`, `notes`, `amount` (match parity fields if they exist)
  - `expected`: `{ itemProjectId, itemTransactionId? }`
- `ITEM_SALE_PROJECT_TO_PROJECT`:
  - `itemId`, `sourceProjectId`, `targetProjectId`
  - `inheritedBudgetCategoryId` (required for the destination project attribution)
  - optional: `space`, `notes`, `amount`
  - `expected`: `{ itemProjectId, itemTransactionId? }`

Partial completion semantics (required):
- Preferred Firebase behavior is **atomic**: the sell-to-project request applies deallocation + allocation in **one Firestore transaction**, so “partial completion” should not occur.
- If implementation ever requires multiple transactions (e.g., future batch ops), request docs MUST record a resumable `stage` and remain idempotent across stages.

## Core flows (spec-level summary)

Detailed flow specs live under `flows/`.

### 1) Project → Business Inventory (Move: correction path)
User intent: “This item should be in Business Inventory.”

Required behavior:
- Block if item is tied to a transaction (canonical or non-canonical): user must move the transaction instead.
- Update item to business inventory scope without creating a canonical sale transaction.

Parity evidence:
- Guard + error copy: `src/pages/ItemDetail.tsx` (`handleMoveToBusinessInventory`) and `src/components/items/ItemActionsMenu.tsx`
- Core mutation + lineage update: `moveItemToBusinessInventory` in `src/services/inventoryService.ts`

### 2) Project → Business Inventory (Deallocate/Sell: canonical path)
User intent: “Move this item to Business Inventory (inventory designation), preserving canonical mechanics.”

Required behavior:
- If the item is currently linked to `INV_PURCHASE_<sameProjectId>`, treat as **purchase-reversion**:
  - remove from that purchase and return to inventory (do **not** create `INV_SALE_<projectId>`)
- Otherwise:
  - ensure/update `INV_SALE_<projectId>`
  - move the item to business inventory and link it to `INV_SALE_<projectId>`
  - append lineage edge (from prior transaction → sale transaction)

Parity evidence:
- Purchase-reversion path: `deallocationService.handleInventoryDesignation` in `src/services/inventoryService.ts`

### 3) Business Inventory → Project (Allocate: canonical purchase)
User intent: “Move this item into Project X.”

Required behavior:
- Ensure/update `INV_PURCHASE_<projectId>` and link the item to it.
- Set item `projectId = <projectId>`.
- Append lineage edge (from prior transaction or inventory → purchase transaction).

Parity evidence:
- Allocation deterministic branching: `allocateItemToProject` in `src/services/inventoryService.ts`
- Offline queue operation types: `ALLOCATE_ITEM_TO_PROJECT` in `src/types/operations.ts` and `executeAllocateItemToProject` in `src/services/operationQueue.ts`

### 4) Project → Project (Sell item to another project)
User intent: “Sell this project item to Project Y.”

Required behavior:
- Two-phase canonical flow:
  - Deallocate from source project into business inventory (canonical sale or purchase-reversion if applicable)
  - Allocate into target project (canonical purchase)
- Partial completion handling must be explicit:
  - If sale completes but purchase fails, surface an error that tells the user the item is now in Business Inventory and must be allocated from there.

Parity evidence:
- `sellItemToProject` in `src/services/inventoryService.ts` (two-step, includes PARTIAL_COMPLETION error)
- UI surfaces this error: `src/pages/ItemDetail.tsx` and `src/pages/TransactionDetail.tsx`

## Budget-category determinism (required)
Business Inventory → Project operations must integrate with the destination budget category selection rule and persist it on the item as `inheritedBudgetCategoryId`.

Source of truth:
- `40_features/project-items/flows/inherited_budget_category_rules.md`

Implementation note (Firebase):
- Category choice must be part of the server-owned invariant for BI → Project operations so retries remain deterministic.

Additional required guardrail (Firebase):
- **Project → Business Inventory sell/deallocate-style operations MUST be blocked** if `item.inheritedBudgetCategoryId` is missing (canonical attribution determinism).
- The **correction “Move to Business Inventory”** path may remain allowed when `inheritedBudgetCategoryId` is missing (it does not create canonical inventory transactions), but it is still blocked when the item is transaction-attached (see “Move: correction path”).

User-facing requirement (required):
- When blocked for this reason, UI must show the standard **disable reason + error toast** defined in `40_features/project-items/flows/inherited_budget_category_rules.md`.

## Lineage (required)
Lineage is required to support:
- “Where did this item go?” cues in Transaction Detail / Item Detail
- Auditability across cross-scope moves

Required model (conceptual):
- Append-only edges: `(fromTransactionId, toTransactionId, createdAt, createdBy, movementKind?, source?, note?)`
  - `movementKind` is **intent**, not an inference:
    - `sold`: economic sale / inventory designation / allocation sale
    - `returned`: explicit move into a Return transaction
    - `correction`: non-economic mistake-fix move
    - `association`: server-recorded audit edge when `item.transactionId` changes
  - `source` is provenance (`app|server|migration`), so UI can hide/grey “automatic” edges if desired.
- Maintain pointers on the item record for quick UI access (e.g. `latestTransactionId`, optionally `originTransactionId`)

Association vs intent edges (not mutually exclusive):
- **Association edges (audit, always):** for every change to `item.transactionId`, append an edge with:
  - `movementKind = "association"`
  - `source = "server"`
  - `fromTransactionId = old item.transactionId`
  - `toTransactionId = new item.transactionId`
- **Intent edges (when known):** append a *separate* edge when user intent is clear:
  - `movementKind = "sold"`: written by canonical request-doc inventory flows
    (`ITEM_SALE_PROJECT_TO_BUSINESS`, `ITEM_SALE_BUSINESS_TO_PROJECT`, `ITEM_SALE_PROJECT_TO_PROJECT`)
  - `movementKind = "returned"`: written when linking into a Return transaction
  - `movementKind = "correction"`: written only for explicit “fix mistake” actions (do not infer)

Short rationale:
- The audit trail never loses history, even for mistakes.
- Sold/Returned UI stays clean because it uses intent edges only.

Parity evidence:
- `src/services/lineageService.ts` (`appendItemLineageEdge`, `updateItemLineagePointers`)

Observed in code (Firebase lineage write points):
- `ledger_mobile/firebase/functions/src/index.ts` (top comment block; design overview)
- `ledger_mobile/firebase/functions/src/index.ts` (`onItemTransactionIdChanged` → `movementKind: "association"` + `movementKind: "returned"` when Return)
- `ledger_mobile/firebase/functions/src/index.ts` (`handleProjectToBusiness`, `handleBusinessToProject`, `handleProjectToProject` → `movementKind: "sold"`)

## Collaboration / realtime expectations (Firebase target)
- Use scoped listeners bounded to the active scope per `OFFLINE_FIRST_V2_SPEC.md` (detach on background, reattach on resume).
- Other foregrounded clients converge via Firestore’s realtime updates within the scope (no bespoke change-signal + delta sync engine).
