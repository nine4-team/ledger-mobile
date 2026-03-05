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

**Trigger:** Item moves between business inventory and a project (in either direction) via the canonical sale system.

**Semantics:**

- `fromTransactionId`: the transaction the item was previously in (if any)
- `toTransactionId`: the canonical sale transaction
- `fromProjectId`: source project (null = business inventory)
- `toProjectId`: destination project (null = business inventory)

**When created:**

- User sells items from business inventory to a project
- User sells items from a project back to business inventory
- Bulk sale operations (one edge per item)

### 3. Returned (`movementKind: "returned"`)

**Trigger:** Item is returned from its current transaction back to a return transaction or its source.

**Semantics:**

- `fromTransactionId`: the transaction the item is being returned from
- `toTransactionId`: the return transaction (or the original source transaction)
- `fromProjectId` / `toProjectId`: typically the same (returns don't change project scope by default)

**When created:**

- User marks an item as returned
- User moves an item to a return-type transaction
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

## Creation Rules

Lineage edges are created server-side as part of request-doc processing (see write-tiers.md, Tier 2). They are never created directly by client code.

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

## Relationship to Other Systems

- **Canonical sales** (see canonical-sales.md): Every canonical sale creates "sold" lineage edges.
- **Return flow** (see return-and-sale-tracking.md): Returns create "returned" lineage edges.
- **Item membership** (see data-model.md): Lineage edges record the history of which transaction an item belonged to, complementing the current-state `itemIds` field on transactions.

## Design Decision: Why a Separate Collection

Lineage edges live in their own collection (`lineageEdges`) rather than being embedded on item or transaction documents because:

1. **Append-only semantics.** Edges are never modified, only appended. This is a natural fit for a separate collection.
2. **Query flexibility.** Can query by item, by transaction, by project, by edge type, or by time range -- independently.
3. **No document size limits.** An item that moves many times won't bloat its own document.
4. **Audit independence.** Lineage data is preserved even if the source item or transaction is modified.
