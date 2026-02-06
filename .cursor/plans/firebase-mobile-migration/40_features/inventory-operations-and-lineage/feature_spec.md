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

### Canonical inventory sale transactions (new model)
Canonical inventory transactions are system-owned mechanics. In the new model, the only canonical inventory transactions are **sale transactions** that are:

- **Direction-coded**:
  - `business_to_project` (Business Inventory → Project)
  - `project_to_business` (Project → Business Inventory)
- **Category-coded**: each canonical sale transaction has exactly one `budgetCategoryId`
- **Split per category**: a project has at most `2 × (# enabled budget categories)` canonical sale transactions

Deterministic identity (required):
- `canonicalSaleTransactionId(projectId, direction, budgetCategoryId)` must be deterministic and parseable.
- Recommended format:
- `SALE_<projectId>_<direction>_<budgetCategoryId>`

Recommended explicit fields on the transaction doc (even if direction/category are encoded in the id):
- `isCanonicalInventorySale: true`
- `inventorySaleDirection: "business_to_project" | "project_to_business"`
- `budgetCategoryId: string` (required on canonical sale rows)

### “Move” vs “Sell/Deallocate”
This migration must preserve the web distinction:

- **Move to business inventory (correction)**: scope correction for an item that is **not tied to a transaction**. Does **not** create/require a canonical sale.
- **Sell/Deallocate to business inventory (canonical)**: an inventory designation operation that creates/updates the canonical sale transaction for:
  - `(projectId = sourceProjectId, direction = "project_to_business", budgetCategoryId = item budget category id)`
  - except for the **allocation-reversion** case (see core flows)

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

Canonical total invariant (required):
- The server MUST be the only writer of canonical sale transaction `amountCents`.
- When applying a sale operation that affects a canonical sale transaction, the handler MUST recompute and persist the canonical transaction total (`amountCents`) as part of the server-owned transaction.

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
  - `budgetCategoryId` (required; resolved from the item or prompted from the source project)
  - `expected`: `{ itemProjectId, itemTransactionId? }` (conflict detection / precondition)
- `ITEM_SALE_BUSINESS_TO_PROJECT`:
  - `itemId`, `targetProjectId`
  - `budgetCategoryId` (required; resolved for the destination project, prompting if missing/mismatched)
  - optional: `space`, `notes`, `amount` (match parity fields if they exist)
  - `expected`: `{ itemProjectId, itemTransactionId? }`
- `ITEM_SALE_PROJECT_TO_PROJECT`:
  - `itemId`, `sourceProjectId`, `targetProjectId`
  - `sourceBudgetCategoryId` (required; resolved from the item or prompted from the source project)
  - `destinationBudgetCategoryId` (required; resolved for the destination project, prompting if missing/mismatched)

Repair safety net (recommended):
- Provide a server-owned scheduled and/or on-demand repair path that recomputes canonical sale totals (`amountCents`) and corrects drift.
- Clients MUST NOT “self-heal” canonical totals by writing `amountCents` directly.
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
- If the item is currently linked to the canonical sale transaction for:
  - `(projectId = sourceProjectId, direction = "business_to_project", budgetCategoryId = item budget category id)`
  treat as **allocation-reversion**:
  - remove the item from that canonical sale transaction and return to Business Inventory
  - do **not** create/update a `project_to_business` canonical sale transaction
- Otherwise:
  - ensure/update the canonical sale transaction for:
    - `(projectId = sourceProjectId, direction = "project_to_business", budgetCategoryId = item budget category id)`
  - move the item to Business Inventory and link it to that canonical sale transaction
  - append lineage edge (from prior transaction → canonical sale transaction)

Parity evidence:
- Purchase-reversion path: `deallocationService.handleInventoryDesignation` in `src/services/inventoryService.ts`

### 3) Business Inventory → Project (Allocate: canonical sale, direction = business_to_project)
User intent: “Move this item into Project X.”

Required behavior:
- Ensure/update the canonical sale transaction for:
  - `(projectId = targetProjectId, direction = "business_to_project", budgetCategoryId = resolved destination category)`
- Link the item to that canonical sale transaction.
- Set item `projectId = <projectId>`.
- Append lineage edge (from prior transaction or inventory → canonical sale transaction).

Parity evidence:
- Allocation deterministic branching: `allocateItemToProject` in `src/services/inventoryService.ts`
- Offline queue operation types: `ALLOCATE_ITEM_TO_PROJECT` in `src/types/operations.ts` and `executeAllocateItemToProject` in `src/services/operationQueue.ts`

### 4) Project → Project (Sell item to another project)
User intent: “Sell this project item to Project Y.”

Required behavior:
- Two-phase canonical flow:
  - Deallocate from source project into Business Inventory (canonical sale, `project_to_business`, or allocation-reversion if applicable)
  - Allocate into target project (canonical sale, `business_to_project`)
- Partial completion handling must be explicit:
  - If sale completes but purchase fails, surface an error that tells the user the item is now in Business Inventory and must be allocated from there.

Parity evidence:
- `sellItemToProject` in `src/services/inventoryService.ts` (two-step, includes PARTIAL_COMPLETION error)
- UI surfaces this error: `src/pages/ItemDetail.tsx` and `src/pages/TransactionDetail.tsx`

## Budget-category determinism (required)
All canonical sale operations require a resolved `budgetCategoryId` so the server can select the correct canonical sale transaction id.

- Business Inventory → Project operations must ensure the item’s category is valid for the destination project; if not, prompt and persist before sale.
- Project → Business Inventory operations must ensure the item has a category; if missing, prompt and persist before sale.

Source of truth:
- `40_features/project-items/flows/inherited_budget_category_rules.md`

Implementation note (Firebase):
- Category choice must be part of the server-owned invariant for BI → Project operations so retries remain deterministic.

User-facing requirement (required):
- When prompting is required, the UI must clearly explain *why* a category is needed (the sale is tracked per budget category) and persist the selection onto the item.

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
