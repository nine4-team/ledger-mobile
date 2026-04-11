# Lineage Tracking

## Overview

Lineage tracking maintains a complete audit trail of item movements across transactions and projects. Every time an item is linked to a transaction, sold between scopes, returned, or corrected, a lineage edge is created. These edges form a directed graph that shows the full history of every item.

## The LineageEdge Entity

**Firestore path:** `accounts/{accountId}/lineageEdges/{edgeId}`

**Fields:**

| Field | Description |
|-------|-------------|
| `id` | Auto-generated document ID |
| `accountId` | Account scope |
| `itemId` | The item this edge describes |
| `movementKind` | One of four types (see below) |
| `fromTransactionId` | The transaction the item was in before (null for initial association) |
| `toTransactionId` | The transaction the item moved to |
| `fromProjectId` | The project the item was in before (null for business inventory) |
| `toProjectId` | The project the item moved to (null for business inventory) |
| `timestamp` | When the edge was created (server timestamp) |
| `createdBy` | The user who initiated the action |

## Four Edge Types

### 1. Association (`movementKind: "association"`)

**Trigger:** Item is linked to a transaction for the first time, or linked to a new transaction.

**Semantics:**

- `fromTransactionId`: null (if first-ever link) or the previous transaction
- `toTransactionId`: the transaction the item is now linked to
- `fromProjectId` / `toProjectId`: typically the same project (association doesn't change scope)

**When created:**

- User adds an existing item to a transaction
- User creates a new item within a transaction context
- Item is moved from one transaction to another within the same project

### 2. Sold (`movementKind: "sold"`)

**Trigger:** Item moves from business inventory into a project via the per-batch sale flow. (Under the per-batch sale model, "sold" only goes one direction; project → inventory is a `returned` edge, not `sold`.)

**Semantics:**

- `fromTransactionId`: the transaction the item was previously in (if any — null is valid)
- `toTransactionId`: the new per-batch Sale transaction
- `fromProjectId`: null (item was in business inventory)
- `toProjectId`: destination project

**When created:**

- User sells items from business inventory to a project (one edge per item)
- The destination side of a project → project move (after the source side has produced a `returned` edge)
- Bulk sale operations (one edge per item)

**Legacy:** Sold edges produced by the legacy canonical-sale system may have `fromProjectId` set to a project (representing the deprecated `project_to_business` direction). New per-batch flows never produce edges in that direction — those are `returned` edges now.

### 3. Returned (`movementKind: "returned"`)

**Trigger:** Item is returned from its current transaction to a return transaction. Two flavors:

1. **Vendor return:** the item goes back to the original vendor. `fromProjectId == toProjectId` — the project doesn't change because the item is leaving the system, not moving scopes.
2. **Return to inventory:** the item moves from a project back to business inventory. `fromProjectId` is the source project, `toProjectId` is null. This is the path that replaces the legacy `project_to_business` canonical sale.

**Semantics:**

- `fromTransactionId`: the transaction the item is being returned from
- `toTransactionId`: the return transaction (`source: "<vendor>"` for vendor returns, `source: "Business Inventory"` for return-to-inventory)
- `fromProjectId`: source project
- `toProjectId`: source project for vendor returns, null for return-to-inventory

**When created:**

- User marks an item as returned (vendor return)
- User returns items from a project to inventory (return-to-inventory)
- Source side of a project → project move (the destination side produces a `sold` edge)
- Return flow processes an item disposition

### 4. Correction (`movementKind: "correction"`)

**Trigger:** Manual data correction by a user or admin.

**Semantics:**

- `fromTransactionId`: what was recorded before
- `toTransactionId`: what it's being corrected to
- Serves as an audit trail for manual fixes

**When created:**

- Admin manually re-links an item to a different transaction to fix a data error
- Rarely used -- exists for data integrity

## Two-Layer Architecture

Lineage edges serve two distinct purposes, created by different layers:

### Audit layer: `"association"` edges

Created **server-side** by the `onItemTransactionIdChanged` cloud function (see `firebase/functions/src/index.ts`). Fires automatically whenever an item's `transactionId` field changes, regardless of the operation that caused it. Records **what happened** — the item moved from transaction A to transaction B.

### Intent layer: `"sold"` / `"returned"` / `"correction"` edges

Created **client-side** by the operation that caused the move. Records **why it happened** — was it a sale, a return, or a data correction?

### Both layers can fire for the same move

A single item move can produce both an association edge (audit) and an intent edge (sold/returned/correction). They are not mutually exclusive. For example, a sell operation creates a `"sold"` edge client-side, and the server creates an `"association"` edge when the item's `transactionId` changes.

## Creation Rules

**Invariants:**

1. Every scope change (project to/from business inventory) MUST create a lineage edge.
2. Every transaction-to-transaction move MUST create a lineage edge.
3. Lineage edges are append-only -- they are never updated or deleted.
4. Each edge records the state at the time of the action (snapshot, not live reference).

## Querying Lineage

### Full item history

To get an item's complete movement history:

```
query lineageEdges
  where itemId == targetItemId
  order by timestamp ascending
```

Returns a chronological list of all movements for that item.

### All movements for a transaction

```
query lineageEdges
  where toTransactionId == targetTransactionId
     OR fromTransactionId == targetTransactionId
```

Note: Firestore does not support OR across different fields in a single query. In practice, run two queries (one on `toTransactionId`, one on `fromTransactionId`) and merge results client-side, deduplicating by edge ID.

### All movements for a project

```
query lineageEdges
  where toProjectId == targetProjectId
     OR fromProjectId == targetProjectId
```

Same two-query-and-merge pattern as above.

## Use Cases

### Item Provenance

"Where did this item come from?" -- Follow the lineage edges backward from the current transaction to the original association.

### Return Tracking

"Was this item returned?" -- Check for a lineage edge with `movementKind: "returned"` for this item.

### Audit Trail

"Who moved this item and when?" -- Each edge has `createdBy` and `timestamp`, providing a complete audit trail.

### Sale History

"What items were sold to this project?" -- Query lineage edges where `toProjectId == projectId` and `movementKind == "sold"`.

### Transaction Audit Completeness

Lineage edges with `movementKind` "returned" or "sold" are included in the source transaction's audit calculation. The Cloud Function (`computeIsComplete`) queries these edges from `fromTransactionId`, fetches the referenced items, and adds their `purchasePriceCents` to the transaction's `itemsSumCents`. This ensures a transaction's completeness status reflects its full purchase history — items that were returned or sold still count toward the audit, preventing false "incomplete" flags after returns.

## Relationship to Other Systems

- **Per-batch sales** (see [sale-transactions.md](sale-transactions.md)): Every sale creates one `sold` lineage edge per item.
- **Return flow** (see [return-and-sale-tracking.md](return-and-sale-tracking.md)): Vendor returns and returns-to-inventory both create `returned` lineage edges.
- **Project → project moves** (see [sale-transactions.md](sale-transactions.md) "Project → Project Moves"): Each item produces TWO edges in one batch — a `returned` edge for the source-to-inventory hop and a `sold` edge for the inventory-to-destination hop.
- **Legacy canonical sales** (see [canonical-sales.md](canonical-sales.md)): Historical canonical sales also created `sold` edges, but those edges may point at long-lived aggregator transactions and may have `fromProjectId` set (the deprecated `project_to_business` direction). New per-batch flows produce edges with stricter semantics.
- **Item membership** (see [data-model.md](data-model.md)): Lineage edges record the history of which transaction an item belonged to, complementing the current-state `itemIds` field on transactions.

## Design Decision: Why a Separate Collection

Lineage edges live in their own collection (`lineageEdges`) rather than being embedded on item or transaction documents because:

1. **Append-only semantics.** Edges are never modified, only appended. This is a natural fit for a separate collection.
2. **Query flexibility.** Can query by item, by transaction, by project, by edge type, or by time range -- independently.
3. **No document size limits.** An item that moves many times won't bloat its own document.
4. **Audit independence.** Lineage data is preserved even if the source item or transaction is modified.
