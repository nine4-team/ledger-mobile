# Add Existing Items

## Overview

When users are inside a transaction or space, they can pull items from anywhere in the account — other transactions in the same project, other projects, or business inventory. The system determines the correct operation (reassign or sell) based on whether the source and destination are in the same scope, then applies the appropriate field updates and audit trail entries.

This spec covers the picker scoping rules, conflict detection, scope change routing, and field update semantics. For reassign vs sell business rules, see reassign-vs-sell.md. For the canonical sale transaction system, see canonical-sales.md.

## Entry Points

The "add existing items" flow is triggered from two contexts:

| Context | Destination Entity | What Gets Updated |
|---------|-------------------|-------------------|
| Transaction detail | Transaction | `item.transactionId`, `transaction.itemIds` |
| Space detail | Space | `item.spaceId` |

Each context has different scoping rules and different conflict behavior.

## Picker Scope Tabs

### Adding to a Transaction (project scope)

The picker presents items organized by source proximity:

| Tab | Contents | Query Logic |
|-----|----------|-------------|
| Suggested | Items matching the transaction's `source` (vendor) field, from same project, not already in this transaction | `projectId == thisProjectId AND source == transaction.source AND id NOT IN transaction.itemIds` |
| Project | All items in the same project not already in this transaction | `projectId == thisProjectId AND id NOT IN transaction.itemIds` |
| Outside | Items from other projects + business inventory | `projectId != thisProjectId OR projectId == null` |

**Tab visibility rules:**

- **Suggested** is only shown when the transaction has a non-empty `source` field AND at least one matching item exists
- **Project** is always shown when the transaction belongs to a project
- **Outside** is always shown

**Default tab:** The first visible tab is selected by default. If Suggested is hidden, Project is the default.

### Adding to a Transaction (business inventory scope)

When the transaction has no `projectId`:

| Tab | Contents |
|-----|----------|
| Inventory | All business inventory items not in this transaction |
| Projects | Items from all projects |

### Adding to a Space

Spaces are project-scoped. The picker shows:

| Tab | Contents |
|-----|----------|
| Project | Items in the same project not already in this space |
| Outside | Items from other projects + business inventory |

Adding "outside" items to a space implies a scope change if they come from a different project or inventory. The same scope change routing rules apply (see Scope Change Routing below).

## Eligibility

Not all items in the picker are selectable.

### Transaction Picker

| Condition | Eligible? | Visual Indicator |
|-----------|-----------|-----------------|
| Item already in this transaction | No | "Already linked" (disabled, green checkmark) |
| Item in a different transaction (any scope) | Yes | "In [Transaction Name]" (informational, not blocking) |
| Item with no transaction | Yes | (none) |

Items linked to other transactions are eligible but trigger conflict detection on add.

### Space Picker

| Condition | Eligible? | Visual Indicator |
|-----------|-----------|-----------------|
| Item already in this space | No | "Already here" (disabled, green checkmark) |
| Item in a different space | Yes | (none) |
| Item with no space | Yes | (none) |

## Conflict Detection

When selected items are currently linked to another transaction, the system must warn the user before proceeding.

### Detection Rule

An item has a conflict when:

1. `item.transactionId` is not null, AND
2. `item.transactionId != destinationTransaction.id`

### Confirmation Prompt

When one or more selected items have conflicts:

- **Message:** "These items are currently in [Source Transaction Name]. Reassign them?"
- **Item list:** Show up to 4 item display names. If more than 4, show first 4 then "+ N more"
- **Actions:** Cancel (abort entire add operation) or Confirm (proceed)

When items come from **multiple** source transactions, group conflicts by source transaction. Show a summary: "N items from M transactions will be reassigned."

### No Conflict Cases

No confirmation is needed when:

- Item has no `transactionId` (simple add)
- Item is already in the destination transaction (no-op, filtered by eligibility)

## Scope Change Routing

The system determines the operation automatically based on source and destination scope. The user is never asked to choose between reassign and sell.

**Scope comparison uses `projectId`:**

- Same scope: `item.projectId` == destination entity's `projectId` (including both null for inventory-to-inventory)
- Different scope: `item.projectId` != destination entity's `projectId`

### Decision Matrix

| Source Scope | Destination Scope | Operation | Reference |
|-------------|-------------------|-----------|-----------|
| Same project | Same project | Direct reassign | reassign-vs-sell.md §Reassign |
| Business inventory | Business inventory | Direct reassign | reassign-vs-sell.md §Reassign |
| Business inventory | Project | Sell (business_to_project) | canonical-sales.md |
| Project | Business inventory | Sell (project_to_business) | canonical-sales.md |
| Project A | Project B | Two-hop sell (A→inventory→B) | reassign-vs-sell.md §Project-to-Project |

### Bulk Selection Across Scopes

When a user selects items spanning multiple source scopes:

1. Group items by `item.projectId` — each group shares a source scope
2. For each group, determine operation type using the decision matrix
3. Same-scope groups: direct reassign (client-side writes)
4. Cross-scope groups: sell via request doc (server-side atomic operation)

Groups are processed independently. A failure in one group does not roll back other groups.

## Field Updates

### Adding Item to a Transaction (Same Scope)

This is a reassign. All writes are client-side (Tier 1: fire-and-forget).

| Field | Update |
|-------|--------|
| `item.transactionId` | Set to destination transaction ID |
| `item.budgetCategoryId` | Set from destination transaction's `budgetCategoryId` **only if** item's current value is null |
| Source `transaction.itemIds` | Remove item ID (arrayRemove) — only if item had a previous transactionId |
| Destination `transaction.itemIds` | Add item ID (arrayUnion) |

**What does NOT change:** `item.projectId`, `item.spaceId`, `item.status`, `item.purchasePriceCents`.

**Lineage:** A `correction` edge is created client-side (see lineage-tracking.md).

### Adding Item to a Transaction (Cross-Scope)

This is a sell. Uses request doc pattern (Tier 2). See canonical-sales.md for the full write sequence.

| Field | Update |
|-------|--------|
| `item.projectId` | Updated to destination project ID (or null for inventory) |
| `item.transactionId` | Set to canonical sale transaction ID |
| `item.spaceId` | Cleared (null) — spaces are project-scoped |
| `item.budgetCategoryId` | Resolved per budget category resolution rules (see below) |
| Source `transaction.itemIds` | Remove item ID |
| Canonical sale `transaction.itemIds` | Add item ID |
| Canonical sale `transaction.amountCents` | Recalculated (sum of all linked item `purchasePriceCents`) |

**Lineage:** A `sold` edge is created server-side by the Cloud Function.

### Adding Item to a Space

Simple field update (Tier 1: fire-and-forget).

| Field | Update |
|-------|--------|
| `item.spaceId` | Set to destination space ID |

**What does NOT change:** `item.transactionId`, `item.projectId`, `item.budgetCategoryId`.

**Cross-scope note:** If an "outside" item is added to a space, the scope change (updating `projectId`) must happen first via the sell system. Then `spaceId` is set as a follow-up write after the scope change completes. These are two separate operations — the sell is atomic (Tier 2), the space assignment is fire-and-forget (Tier 1).

## Budget Category Resolution

Required for cross-scope operations only. Same-scope reassigns do not require category resolution.

Resolution order (same as canonical-sales.md §Budget Category Resolution):

1. **Item already has `budgetCategoryId`** → use it directly
2. **Item has no category** → prompt user to select one before the operation can proceed
3. **Item's category is not enabled in the destination project** → prompt user to either enable the category or select a different one

**Same-scope convenience:** When pulling same-scope items that lack a `budgetCategoryId`, the destination transaction's category is applied as a convenience default — not a hard requirement.

## Atomicity

| Operation | Write Tier | Rationale |
|-----------|-----------|-----------|
| Same-scope reassign | Tier 1 (fire-and-forget) | 2–3 document updates, no cross-document financial invariants |
| Cross-scope sell | Tier 2 (request doc) | Multiple documents, budget impact, lineage edge — must be atomic |
| Space assignment | Tier 1 (fire-and-forget) | Single field update on one document |

**Same-scope reassign atomicity caveat:** The reassign updates source `transaction.itemIds` (arrayRemove), destination `transaction.itemIds` (arrayUnion), and `item.transactionId` as separate writes. If one fails, data may be temporarily inconsistent. This is acceptable because:

- `arrayUnion`/`arrayRemove` are idempotent
- The user can retry
- No financial data is affected

For batch operations (multiple items in one add), same-scope reassigns should use a Firestore `WriteBatch` to group all writes into a single atomic commit.

## Edge Cases

1. **Item already in destination transaction.** No-op. Eligibility check prevents selection, but if somehow submitted, `arrayUnion` is idempotent.

2. **Item with no transactionId.** Simple add — no conflict detection, no source transaction to update. Just set `item.transactionId` and `arrayUnion` to destination.

3. **Item from archived/deleted project.** The item still exists in Firestore and can be pulled. Its `projectId` references a project that may no longer appear in lists, but scope change routing still works.

4. **Concurrent modification.** If another user moves an item while it's displayed in the picker, the Firestore real-time listener updates the picker list. If the item disappears or changes state, the add operation either succeeds with a conflict (triggering conflict detection) or fails gracefully.

5. **Bulk selection spanning same-scope and cross-scope items.** Items are grouped by operation type. Same-scope items are reassigned immediately (client-side). Cross-scope items go through the sell system (request doc). The user sees a single "add" action but the system executes multiple operations.

6. **Category prompt interrupts bulk add.** If any cross-scope item lacks a `budgetCategoryId`, the prompt must be presented before the request doc is created. The user resolves categories for all items that need them, then the operation proceeds.

7. **Suggested tab with no vendor match.** The tab is hidden entirely (not shown empty). The first visible tab becomes the default.

8. **Transaction with no source field.** Suggested tab is not shown.

9. **Adding to a space when item is in a different project.** Two-step operation: sell the item into the destination project (scope change), then assign the space. The user should be informed that this will affect budget.
