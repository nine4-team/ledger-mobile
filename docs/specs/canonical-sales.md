# Canonical Sales

## Overview

When items move between a project and business inventory, the system creates or updates a "canonical sale transaction" to represent the financial impact. This is the mechanism that tracks money flow when items cross scope boundaries.

## The Two Scopes

Every item and space belongs to one of two scopes:

- **Project scope**: Assigned to a specific project (has a `projectId`)
- **Business inventory scope**: Account-wide, not in any project (`projectId` is null)

Items can move between scopes. When they do, the financial impact must be tracked.

## Sale Directions

There are exactly two sale directions:

1. **Business to Project** (`business_to_project`): Moving items FROM business inventory INTO a project. This ADDS to the project's budget spend (the project is "buying" from inventory).

2. **Project to Business** (`project_to_business`): Moving items FROM a project BACK TO business inventory. This SUBTRACTS from the project's budget spend (the project is "returning" to inventory).

## Deterministic Transaction Identity

A canonical sale transaction is uniquely identified by three fields:

- `projectId` — the project involved
- `inventorySaleDirection` — which direction the items are moving
- `budgetCategoryId` — the budget category of the items being moved

**Identity rule:** For a given (projectId, direction, budgetCategoryId) triple, there is exactly ONE canonical sale transaction. If one already exists, new items moving in that direction under that category are added to the existing transaction rather than creating a new one.

**Transaction ID formula:**

```
transactionId = "SALE_" + projectId + "_" + direction + "_" + budgetCategoryId
```

Example: `SALE_proj123_business_to_project_catFurnishings`

**Why deterministic IDs:** This prevents duplicate transactions when multiple items move in the same direction under the same category. It also makes the system idempotent — processing the same sale request twice won't create a duplicate transaction.

## Canonical Sale Transaction Fields

When a canonical sale transaction is created or updated, it has these distinctive fields:

- `isCanonicalInventorySale: true` — marks it as system-generated (not user-created)
- `inventorySaleDirection` — "business_to_project" or "project_to_business"
- `transactionType: "Sale"`
- `projectId` — the project involved
- `budgetCategoryId` — inherited from the items being moved
- `amountCents` — sum of all item purchase prices in this transaction
- `itemIds` — array of all item IDs that have been moved via this sale

## The Two-Hop Model

Moving items between scopes is a two-step process ("two hops"):

### Hop 1: Remove from Source

- If the item was in a project transaction, remove it from that transaction's `itemIds`
- Clear the item's `transactionId`
- If moving to business inventory: set the item's `projectId` to null

### Hop 2: Add to Destination

- Find or create the canonical sale transaction for this (projectId, direction, budgetCategoryId) triple
- Add the item's ID to the canonical sale transaction's `itemIds`
- Set the item's `transactionId` to the canonical sale transaction's ID
- If moving to a project: set the item's `projectId` to the project ID
- Recalculate the canonical sale transaction's `amountCents` as the sum of all linked item purchase prices

## Amount Calculation

The canonical sale transaction's amount is always recalculated as:

```
amountCents = sum of purchasePriceCents for all items in itemIds
```

This means the amount updates every time an item is added to or removed from the sale.

## Budget Category Resolution

When an item moves between scopes, it needs a budget category for the canonical sale transaction. Resolution order:

1. **Item already has a `budgetCategoryId`**: Use it directly
2. **Item has no category**: Prompt the user to select one before the move can proceed
3. **Item's category is not enabled in the destination project**: Prompt the user to either enable the category or select a different one

**Why items carry persistent `budgetCategoryId`:** Once set, an item's budget category stays with it across scope moves. This ensures deterministic canonical sale grouping — the system always knows which sale transaction an item belongs to without asking the user again.

## Sign Conventions in Budget Calculations

- `business_to_project`: The canonical sale transaction's amount is counted as POSITIVE spend against the project's budget (the project is acquiring items)
- `project_to_business`: The canonical sale transaction's amount is counted as NEGATIVE spend (subtracted from the project's budget, because the project is releasing items)

This is implemented via a multiplier in budget progress calculation:

```
if direction is "business_to_project": multiplier = +1
if direction is "project_to_business": multiplier = -1

budget_impact = amountCents * multiplier
```

## Lineage Tracking

Every canonical sale creates a lineage edge (see lineage-tracking.md):

- `movementKind: "sold"`
- `itemId`: the item being moved
- `fromProjectId`: source project ID (or null for business inventory)
- `toProjectId`: destination project ID (or null for business inventory)
- `fromTransactionId`: the item's previous transaction (if any)
- `toTransactionId`: the canonical sale transaction

## Atomicity

Canonical sale operations use the request-doc pattern (see write-tiers.md, Tier 2) because they involve multiple document updates:

1. Update item fields (projectId, transactionId, budgetCategoryId)
2. Update source transaction's itemIds (remove)
3. Create or update canonical sale transaction (add to itemIds, recalculate amount)
4. Create lineage edge

All four operations must succeed or fail together. The Cloud Function processes the request doc and executes all writes in a Firestore transaction.

## Bulk Sales

Multiple items can be sold in a single operation. Items are grouped by `budgetCategoryId` — each group goes to its own canonical sale transaction (per the deterministic identity rule).

Example: Selling 5 items where 3 have category "Furnishings" and 2 have category "Install":

- Items with "Furnishings" go to canonical sale `SALE_proj123_business_to_project_catFurnishings`
- Items with "Install" go to canonical sale `SALE_proj123_business_to_project_catInstall`

## Edge Cases

1. **Item with no purchase price**: Contributes $0 to the canonical sale amount. The item is still moved and linked.
2. **Selling an item that's already in the destination scope**: No-op. The item is already where it needs to be.
3. **Canonical sale transaction already exists with items**: New items are appended to `itemIds`, and `amountCents` is recalculated from all linked items.
4. **All items removed from a canonical sale**: The transaction remains with `itemIds: []` and `amountCents: 0`. It is not deleted (preserves audit trail).
5. **Item's category not enabled in destination project**: User must resolve before the sale can proceed. Options: enable the category in the project, or change the item's category.

## Display

Canonical sale transactions appear in the transaction list like regular transactions but with distinctive visual treatment:

- Badge: "Sale"
- Display name: Derived from the sale direction and context (e.g., "From Business Inventory" or "To Business Inventory")
- Amount: Shows the computed total from all linked item prices
- They are NOT editable by users (system-generated)
