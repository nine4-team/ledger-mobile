# Reassign vs Sell

## Overview

When items need to move between projects or between a project and business inventory, there are two distinct operations with different semantics. Users must understand which they're performing because the financial implications differ.

## Reassign

### Definition

Reassign moves an item from one transaction to another **within the same scope** (same project, or within business inventory). No financial impact — no new transactions are created, no budget amounts change.

### What Changes

- `item.transactionId` is updated to the new transaction
- The item is removed from the old transaction's `itemIds` array
- The item is added to the new transaction's `itemIds` array
- A lineage edge of type `"association"` is created

### What Does NOT Change

- `item.projectId` stays the same
- No canonical sale transaction is created
- No budget impact
- `item.budgetCategoryId` is unchanged

### When to Use

- Correcting a data entry mistake (item was linked to wrong transaction)
- Reorganizing items between transactions within the same project
- Moving an item from one business inventory transaction to another

### Validation

- Source and destination must be in the same scope (same projectId, or both null for business inventory)
- If scopes differ, the operation is a "sell," not a "reassign"

## Sell

### Definition

Sell moves items **between scopes** — from a project to business inventory, or from business inventory to a project. This creates or updates a canonical sale transaction and has budget implications.

### What Changes

- `item.projectId` changes (set to destination project ID, or null for business inventory)
- `item.transactionId` updated to the canonical sale transaction
- Item removed from source transaction's `itemIds`
- Item added to canonical sale transaction's `itemIds`
- Canonical sale transaction's `amountCents` recalculated
- A lineage edge of type `"sold"` is created
- Budget spend in the project is affected (see canonical-sales.md)

### When to Use

- Moving items from business inventory into a project (project is "buying")
- Moving items from a project back to business inventory (project is "returning to inventory")

### Budget Impact

- Business to Project: adds to project budget spend
- Project to Business: subtracts from project budget spend

See canonical-sales.md for the full canonical sale system documentation.

## Decision Matrix

| Source | Destination | Operation | Financial Impact |
|--------|-------------|-----------|------------------|
| Project A, Transaction X | Project A, Transaction Y | Reassign | None |
| Business Inventory, Txn X | Business Inventory, Txn Y | Reassign | None |
| Business Inventory | Project A | Sell | Adds to Project A budget |
| Project A | Business Inventory | Sell | Subtracts from Project A budget |
| Project A | Project B | Sell (two-step) | Subtracts from A, adds to B |

### Project-to-Project Moves

Moving items between two different projects is a two-step sell:

1. Sell from Project A to Business Inventory (subtracts from A's budget)
2. Sell from Business Inventory to Project B (adds to B's budget)

This ensures clean audit trail and correct budget attribution for both projects.

## Menu Visibility Rules

The actions available to users depend on context.

### "Reassign" is available when:

- Item is linked to a transaction
- Other transactions exist in the same scope

### "Sell to Project" is available when:

- Item is in business inventory (projectId is null)
- At least one project exists

### "Send to Inventory" is available when:

- Item is in a project (projectId is not null)

### "Move to Different Project" is available when:

- Item is in a project
- Other projects exist
- Implemented as two-step sell (project to inventory to project)

## Budget Category Resolution During Sell

When selling items, the budget category must be resolved (see canonical-sales.md for details):

1. Item already has `budgetCategoryId` -- use it
2. Item has no category -- prompt user to select
3. Item's category not enabled in destination -- prompt to enable or select different

## Design Decision: Why Separate Operations?

Reassign and sell could theoretically be one "move" operation that detects scope changes automatically. They are kept separate because:

1. **User intent matters.** Reassigning (fixing a mistake) vs selling (financial transaction) have different mental models. Conflating them leads to accidental financial entries.
2. **Reversibility.** Reassign is trivially reversible (just reassign back). Sell creates canonical transactions and lineage edges that persist.
3. **Validation differs.** Sell requires budget category resolution and may need user input. Reassign is always immediate.
4. **Audit trail clarity.** The lineage edge types ("association" vs "sold") clearly distinguish organizational moves from financial ones.
