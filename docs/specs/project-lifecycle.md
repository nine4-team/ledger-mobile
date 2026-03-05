# Project Lifecycle

## Overview

Projects are the primary organizational unit in Ledger. Each project represents a client engagement (e.g., a home renovation, an interior design project) and contains transactions, items, spaces, and budget allocations.

## Project Fields

- `id` — unique identifier
- `accountId` — owning account
- `name` — project name (required)
- `clientName` — client's name (required for creation)
- `status` — project status (e.g., "active", "archived")
- `address` — project/property address (optional)
- `notes` — free text notes
- `images` — array of AttachmentRef
- `budgetSummary` — denormalized budget progress (maintained by Cloud Function triggers)
- `createdAt`, `updatedAt` — timestamps
- `createdBy`, `updatedBy` — user IDs

## Creation

### Required Fields

- `name` — must be non-empty
- `clientName` — must be non-empty

### Optional Fields at Creation

- `address`
- `notes`
- Budget allocations (can be set later)

### Post-Creation Setup

After creating a project, users typically:

1. Set budget allocations (enable categories and set amounts)
2. Create spaces from templates
3. Start adding transactions

## Budget Allocation

Budget categories are enabled per-project by creating ProjectBudgetCategory documents (see budget-management.md). A project can have any subset of the account's budget categories enabled, each with its own budget amount.

## Project Data Scope

A project owns (via `projectId` foreign key):

- **Transactions** — all transactions with `projectId` matching this project
- **Items** — all items with `projectId` matching this project
- **Spaces** — all spaces with `projectId` matching this project

When loading a project detail view, the system subscribes to all of these collections filtered by `projectId`.

## Archiving

Projects can be archived (soft deleted) by setting `status` to "archived". Archived projects:

- Are hidden from the default project list
- Can be viewed in an "Archived" filter/tab
- Retain all their data (transactions, items, spaces)
- Can be unarchived by changing status back to "active"

## Deletion

Project deletion is a destructive operation. When a project is deleted:

- The project document is removed
- Associated transactions, items, and spaces are NOT automatically deleted (they become orphaned with a `projectId` that no longer resolves)
- Items in the project should be moved to business inventory first if they need to be preserved

**Design decision:** Deletion is rarely needed. Archiving is preferred. Deletion exists for data cleanup but should always prompt for confirmation.

## Budget Summary Denormalization

The project document contains a `budgetSummary` field that is maintained by Cloud Function triggers (see budget-management.md). This allows the project list to show budget progress bars without loading all transactions for every project.

The summary is recalculated:

- When any transaction in the project is created, updated, or deleted
- When project budget categories change
- When account-level budget category metadata changes

## Multi-Project Context

Users can have multiple active projects. The app supports:

- Project list with budget progress previews
- Quick switching between projects
- Sibling navigation (next/previous project from detail view)

## Edge Cases

1. **Project with no transactions** — valid state; shows empty transaction list with prompts to add.
2. **Project with no budget** — valid; budget section shows a "Set Budget" prompt.
3. **Deleting a project with items** — warn user that items will become orphaned. Suggest moving to business inventory first.
4. **Duplicate project names** — allowed (projects are identified by ID, not name).
5. **Offline project creation** — works via fire-and-forget write. Budget summary won't populate until the Cloud Function trigger runs (requires connectivity).
