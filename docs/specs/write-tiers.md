# Write Tiers

The system uses four distinct write patterns, ordered by complexity. Each tier exists for a specific reason.

## Tier 1: Fire-and-Forget (Direct Firestore Write)

**When to use:** Single-document updates where eventual consistency is acceptable and no cross-document invariants need to be maintained.

**How it works:**
1. Client writes directly to Firestore
2. Firestore SDK handles offline queueing automatically
3. Client does NOT await server acknowledgment -- UI updates optimistically
4. Error handling: catch the error and log it, but do not block UI

**Examples:**
- Updating a transaction's notes field
- Changing an item's name or SKU
- Toggling a checklist item's completion state
- Updating project preferences (pinned categories)
- Setting a space's name or notes

**Why this tier:** Most writes in the app are single-field or single-document updates. The Firestore SDK handles offline persistence and sync automatically. Awaiting the server would block UI and violate offline-first principles.

**Invariant:** Never await a fire-and-forget write in UI code. The write must be non-blocking.

## Tier 2: Request Document (Write-Ahead Log)

**When to use:** Multi-document operations that must be atomic or have complex server-side logic. The client cannot (or should not) perform the operation directly because it spans multiple documents or requires server-side validation.

**How it works:**
1. Client creates a "request document" in Firestore at `accounts/{accountId}/requestDocs/{requestDocId}`
2. The request document contains: `type` (operation name), `status: "pending"`, and a `payload` map with operation-specific data
3. A Cloud Function trigger (`onRequestDocCreated`) picks up the document
4. The Cloud Function executes the multi-document operation atomically (using Firestore transactions or batched writes)
5. The Cloud Function updates the request document's `status` to `"completed"` or `"failed"` (with an `error` field if failed)
6. The client subscribes to the request document and reacts to status changes

**Request document fields:**
- `id` -- auto-generated document ID
- `accountId` -- scoping
- `type` -- string identifying the operation (e.g., "sellItems", "returnItem", "moveItemToTransaction")
- `status` -- "pending" | "processing" | "completed" | "failed"
- `payload` -- map containing operation-specific data
- `error` -- string, populated on failure
- `createdAt` -- server timestamp
- `createdBy` -- user ID

**Examples of operations that use request docs:**
- **Sell items** (canonical sale): Creates/updates a canonical sale transaction, moves items between scopes, creates lineage edges -- all atomically
- **Return item**: Moves item back to source transaction, updates item status, creates lineage edge
- **Move item to different transaction**: Updates both the source and destination transaction's `itemIds` arrays and the item's `transactionId`
- **Bulk operations**: Any operation that touches multiple items or multiple transactions

**Why this tier:** When an operation must update 2+ documents consistently (e.g., remove item from one transaction's `itemIds` AND add it to another's), a direct client write could leave data inconsistent if the app crashes mid-operation. The request-doc pattern ensures atomicity via server-side execution.

**Client-side pattern:**
1. Create the request document (fire-and-forget write)
2. Subscribe to the request document for status updates
3. Show a progress/status indicator based on `status` field changes
4. On "completed": update UI, dismiss loading state
5. On "failed": show error message from `error` field

## Tier 3: Callable Cloud Function

**When to use:** Operations that need server-side logic but don't need the write-ahead-log pattern. Typically used for operations that return a result the client needs immediately.

**How it works:**
1. Client calls a Cloud Function directly (Firebase callable function)
2. Function executes on server and returns a result
3. Client uses the result

**Examples:**
- Invoice PDF import/parsing (sends PDF, gets back extracted line items)
- Account creation with seed data
- Operations that need external API calls

**Why this tier:** When the client needs a synchronous response (not just "it worked"), callable functions provide request-response semantics. Unlike request docs, there's no status subscription -- it's a single round-trip.

**Trade-off:** Does not work offline. The client must have connectivity. Use only for operations where offline support is not required.

## Tier 4: Server-Side Triggers

**When to use:** Derived data maintenance, denormalization, and background processing that should happen automatically when source data changes.

**How it works:**
1. A Firestore document is created, updated, or deleted (by any tier above)
2. A Cloud Function trigger fires automatically
3. The trigger updates derived/denormalized data

**Examples:**
- **Budget summary recalculation**: When a transaction is written (created/updated/deleted), a trigger recalculates the project's `budgetSummary` field by aggregating all non-canceled transactions
- **Budget category changes**: When an account-level budget category's name, type, or archive status changes, a trigger updates all affected project budget summaries
- **Request doc processing**: The `onRequestDocCreated` trigger that processes Tier 2 operations is itself a Tier 4 trigger

**Why this tier:** Keeps derived data consistent without client involvement. The client writes source data; triggers maintain computed/denormalized data automatically.

**Invariant:** Triggers must be idempotent -- running the same trigger twice on the same data must produce the same result. This is because Firestore may deliver triggers more than once.

## Choosing the Right Tier

| Question | Answer | Tier |
|----------|--------|------|
| Is it a single-document update? | Yes | Tier 1 |
| Does it touch multiple documents atomically? | Yes | Tier 2 |
| Does the client need a synchronous response? | Yes | Tier 3 |
| Is it derived data that auto-updates when source changes? | Yes | Tier 4 |
| Must it work offline? | Yes | Tier 1 or 2 (not 3) |

## Design Decision: Why Request Docs Over Direct Batch Writes

The system could use client-side batched writes (Firestore batch/transaction) for multi-document operations. We chose request docs instead because:

1. **Atomicity guarantee**: Server-side Firestore transactions have stronger consistency guarantees than client-side batches, especially under concurrent writes
2. **Auditability**: Request docs create an audit trail -- every multi-document operation is logged with who initiated it, when, and what the payload was
3. **Retry safety**: If a request doc fails, the Cloud Function can retry safely (the request doc itself serves as an idempotency key)
4. **Offline support**: The client can create a request doc offline (Tier 1 fire-and-forget). When connectivity returns, the request doc syncs to server and the trigger processes it. This is superior to client-side batches, which would fail entirely offline.
5. **Separation of concerns**: Complex business logic lives server-side, not in client code. Multiple client platforms (web, iOS, future Android) share the same server-side logic.
