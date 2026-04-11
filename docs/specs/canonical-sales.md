# Canonical Sales (Legacy)

> **⚠️ Status:** Superseded by [sale-transactions.md](sale-transactions.md). This document describes the legacy canonical-sale model that existed before the per-batch redesign. It is preserved for two reasons:
>
> 1. **Historical data still uses this shape.** Existing sale transactions written under the canonical model remain in Firestore as immutable historical records. Readers must understand this shape to render them correctly.
> 2. **The dual-read path in [util/budget.ts](../../mcp-server/src/util/budget.ts) depends on the sign convention documented here.**
>
> **For all new sale-related work, see [sale-transactions.md](sale-transactions.md) and [inventory-as-store.md](inventory-as-store.md).**

## Quick Links

- [sale-transactions.md](sale-transactions.md) — the active sale transaction spec
- [inventory-as-store.md](inventory-as-store.md) — the conceptual shift that replaced this model
- [return-and-sale-tracking.md](return-and-sale-tracking.md) — how returns work, including return-to-inventory

## What Replaced This Model

| Legacy concept | Replacement |
|---|---|
| Long-lived canonical sale transaction per `(project, direction, category)` | New per-batch Sale transaction per user action ([sale-transactions.md](sale-transactions.md)) |
| `inventorySaleDirection: "business_to_project"` | The only direction. No flag needed. |
| `inventorySaleDirection: "project_to_business"` | Replaced by Return transactions with `source: "Business Inventory"` |
| Items carrying `budgetCategoryId` across scope moves | Items in inventory have `budgetCategoryId == null`; category resolved at sell time |
| Two-hop project → project moves | Return-to-inventory + new sale to destination, atomic |
| `arrayUnion` / `arrayRemove` mutations on long-lived sale documents | Each sale is an immutable per-batch document |

## Legacy Shape (For Historical Reads)

Legacy canonical sale transactions are identified by:

```
isCanonicalInventorySale: true
inventorySaleDirection: "business_to_project" | "project_to_business"
type: "Sale"
```

They have a deterministic ID of the form `SALE_{projectId}_{direction}_{budgetCategoryId}` and an `itemIds` array that may have grown over time as items were added to the aggregator. Their `amountCents` is the sum of linked item prices, frozen as of the last `onItemPriceChanged` invocation before that trigger was disabled for Sale transactions.

### Sign Convention (Legacy)

The dual-read path in [util/budget.ts](../../mcp-server/src/util/budget.ts) `normalizeSpendAmount` handles legacy canonical sales like this:

```
if tx.isCanonicalInventorySale and tx.inventorySaleDirection:
    if tx.inventorySaleDirection == "business_to_project":
        return +abs(tx.amountCents)    // money spent on project
    if tx.inventorySaleDirection == "project_to_business":
        return -abs(tx.amountCents)    // money returned from project
```

New per-batch sales (no `isCanonicalInventorySale` flag) are always `+abs(amountCents)`. See [budget-management.md](budget-management.md) Sign Conventions section for the full table.

## Why Not Migrate

Legacy canonical sales are not converted to per-batch shape. Reasons:

1. **Rewriting historical financial records is risky.** Even with care, the migration could mask or introduce bugs in budget rollups.
2. **Frozen records are accounting-correct.** Once frozen (post-trigger-removal), legacy canonical sales reflect what was true at the time they were last updated. That's a defensible historical position.
3. **The dual-read tax is small and bounded.** One function (`normalizeSpendAmount`) and one branch in tests. Cheaper than the migration risk.

If the legacy doc count becomes problematic in the future, a one-time migration script can be considered as a follow-up. See "Out of Scope" in [the implementation plan](/Users/benjaminmackenzie/.claude/plans/steady-wiggling-cosmos.md).

## What the Legacy Model Looked Like

The remainder of this section is preserved verbatim for historical context. **None of it describes current behavior.** Read [sale-transactions.md](sale-transactions.md) for the current model.

---

### (Historical) Overview

When items moved between a project and business inventory, the system created or updated a "canonical sale transaction" to represent the financial impact. This was the mechanism that tracked money flow when items crossed scope boundaries.

### (Historical) The Two Scopes

Every item and space belonged to one of two scopes:

- **Project scope**: Assigned to a specific project (has a `projectId`)
- **Business inventory scope**: Account-wide, not in any project (`projectId` is null)

Items could move between scopes. When they did, the financial impact had to be tracked.

### (Historical) Sale Directions

There were exactly two sale directions:

1. **Business to Project** (`business_to_project`): Moving items FROM business inventory INTO a project. This ADDED to the project's budget spend (the project was "buying" from inventory).
2. **Project to Business** (`project_to_business`): Moving items FROM a project BACK TO business inventory. This SUBTRACTED from the project's budget spend (the project was "returning" to inventory). **In the new model, this case is a Return transaction, not a Sale.**

### (Historical) Deterministic Transaction Identity

A canonical sale transaction was uniquely identified by three fields:

- `projectId` — the project involved
- `inventorySaleDirection` — which direction the items were moving
- `budgetCategoryId` — the budget category of the items being moved

**Identity rule:** For a given (projectId, direction, budgetCategoryId) triple, there was exactly ONE canonical sale transaction. New items moving in that direction under that category were added to the existing transaction rather than creating a new one.

**Transaction ID formula:**

```
transactionId = "SALE_" + projectId + "_" + direction + "_" + budgetCategoryId
```

### (Historical) Why It Was Replaced

The aggregator pattern caused drift bugs. Multiple writers (iOS, MCP server) mutated the same long-lived documents via `arrayUnion`/`arrayRemove`, and divergence between them produced incorrect `itemIds` lists. The most visible failure: a "Beige Linen Sofa" sold from Brianhead Cabin to Hawaii Apartment continued to appear in Brianhead's purchase transaction because the cleanup code on the sell path read `item.transactionId` (which was nil at sell time) instead of querying which transaction contained the item.

The per-batch redesign eliminates this entire class of bug by making each sale an immutable document. There's no shared mutable state to drift.

### (Historical) Display

Canonical sale transactions appeared in the transaction list with:

- Badge: "Sale"
- Display name: "Sale to Inventory" (project_to_business) or "Purchase from Inventory" (business_to_project)
- Amount: the computed total from all linked item prices
- Not editable by users

This display logic still applies to legacy canonical sales for historical readability.
