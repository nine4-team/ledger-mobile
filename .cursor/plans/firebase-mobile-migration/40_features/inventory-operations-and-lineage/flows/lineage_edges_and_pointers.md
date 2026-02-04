## Flow: Lineage edges and pointers

## What lineage is for
Lineage is the append-only history that lets users and the system answer:

- “Where did this item go?”
- “Which transaction did this item come from / move to?”
- “What was the last known transaction context for this item?”

This spec treats lineage as **required** for cross-scope operations and canonical inventory mechanics.

## Data model (conceptual)

### Edges (append-only)
Each edge represents a move:
- `fromTransactionId` (nullable; null means “from inventory”)
- `toTransactionId` (nullable; null means “to inventory”)
- `createdAt`
- `createdBy`
- `movementKind` (optional; intent classification)
- `source` (optional; provenance)
- `note` (optional)

Parity evidence:
- `ItemLineageEdge` shape + conversion: `src/services/lineageService.ts`

### Pointers (on item)
Maintain pointers so most screens do not need to reconstruct full history:
- `latestTransactionId` (nullable)
- optionally `originTransactionId` (set once)

Parity evidence:
- Pointer maintenance: `updateItemLineagePointers` in `src/services/lineageService.ts`.

## Behavior contract

### 0) Always append association edges (audit)
On every server-observed change of `item.transactionId`, append a lineage edge with:
- `movementKind = "association"`
- `source = "server"`
- `fromTransactionId = <previous item.transactionId>`
- `toTransactionId = <new item.transactionId>`

This is the durable “what happened” record and can exist alongside intent edges.
Short rationale:
- Keeps an unbroken history, even when a move is corrected later.

### 1) Append lineage edge on every cross-scope move (best-effort)
Operations that must append lineage edges:
- Project → Business Inventory (move correction)
- Project → Business Inventory (canonical deallocation)
- Business Inventory → Project allocation
- Project → Project sell (both sub-steps)

Implementation note (Firebase):
- Prefer appending lineage as part of the server-owned invariant transaction for the operation.

Classification note (required):
- Economic inventory operations (canonical request-doc flows) must write a **separate** intent edge:
  - `movementKind = "sold"`
  - `source = "server"`
- Linking an item into a Return transaction must write a **separate** intent edge:
  - `movementKind = "returned"`
  - `source = "server"`
- Corrective moves must write intent edges **only** when the user explicitly chose a “fix mistake” action:
  - `movementKind = "correction"`
  - `source = "app"` (or `"server"` if routed through a request-doc invariant)
  - Do not infer correction from an association change.
Short rationale:
- Intent edges are about why, so they are written only when intent is known.

Parity evidence (web calls):
- `moveItemToBusinessInventory` (best-effort lineage) in `src/services/inventoryService.ts`
- `deallocationService.handleInventoryDesignation` (best-effort lineage) in `src/services/inventoryService.ts`
- Allocation helpers call lineage methods in `src/services/inventoryService.ts`

### 2) Duplicate suppression / idempotency
Rapid repeated lineage writes should not create duplicates.

Parity evidence:
- `appendItemLineageEdge` duplicate suppression window (5 seconds) in `src/services/lineageService.ts`.

### 3) Update pointers on write
After appending an edge, update `latestTransactionId` to match `toTransactionId`.

Parity evidence:
- `updateItemLineagePointers` in `src/services/lineageService.ts` and usage in `src/services/inventoryService.ts`.

### 4) UI consumption
Lineage history can be fetched for an item detail view.

Parity evidence:
- `getItemLineageHistory` in `src/services/lineageService.ts`.

## Offline behavior
Parity in the current web app:
- When offline, lineage history fetch returns empty.

Parity evidence:
- `getItemLineageHistory` checks `isNetworkOnline()` in `src/services/lineageService.ts`.

Firebase migration requirement:
- Lineage edges should be available offline via Firestore-native offline persistence (cache-first reads when offline) so Item Detail can show history even offline.  
  **Intentional delta**: unlike the web app, the mobile Firebase app can render lineage history offline from cached Firestore docs (and/or a derived local cache), consistent with `OFFLINE_FIRST_V2_SPEC.md`.

## Association vs intent edges (best system; not mutually exclusive)
In Firebase, the most reliable (least “guessy”) system is:

### A) Always record association changes (audit)
On every server-observed change of `item.transactionId`, append a lineage edge with:
- `movementKind = "association"`
- `source = "server"`
- `fromTransactionId = <previous item.transactionId>`
- `toTransactionId = <new item.transactionId>`

This creates a complete, durable audit trail (including mistakes/corrections).

### B) Additionally record intent edges when intent is known
Separately, append a second edge when intent is deterministic:
- `sold`: written by canonical inventory request-doc handlers (allocate/deallocate/project-to-project)
- `returned`: written when linking into a Return transaction (can be server-triggered by destination transaction type)
- `correction`: written only by explicit “fix mistake” actions (when the UI/server has explicit user intent)

Implementation note (Firebase):
- Association edges should be implemented as a server-side trigger on `accounts/{accountId}/items/{itemId}` updates (transactionId change detector),
  so it also covers client-direct linking/unlinking and reassignments (not just request-doc invariants).

Observed in code (Firebase lineage write points):
- `ledger_mobile/firebase/functions/src/index.ts` (top comment block; design overview)
- `ledger_mobile/firebase/functions/src/index.ts` (`onItemTransactionIdChanged` → `movementKind: "association"` + `movementKind: "returned"` when Return)
- `ledger_mobile/firebase/functions/src/index.ts` (`handleProjectToBusiness`, `handleBusinessToProject`, `handleProjectToProject` → `movementKind: "sold"`)
