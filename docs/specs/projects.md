# Projects

> **Target-state notice (2026-08-31):** The shipped Firebase app stores a
> free-text `clientName`, creates Project setup through several independent
> writes, and can delete only the Project document while orphaning children.
> Those mechanics below remain current-system and migration evidence. The
> redesigned app requires the account-scoped Client identity and mandatory
> `project.clientId` in
> [Client Identity and Project Transfers](client-identity-and-project-transfers.md),
> a durable Project-setup result, and archive-first lifecycle. O-024 controls
> whether any persisted Project may be physically deleted; O-025 controls Client
> reassignment/merge.

## Overview

Projects are the primary organizational unit in Ledger. Each project represents a client engagement (e.g., a home renovation, an interior design project) and contains transactions, items, spaces, and budget allocations. Projects exist alongside business inventory as the two scopes in the system — every item and transaction belongs to either a project or business inventory.

## Target Redesign Requirements

- Every Project belongs to one authoritative account-scoped Client by stable ID.
  Client display names remain searchable but never authorize relationships or
  same-Client Transfers.
- Project creation selects or creates a Client and durably records the Project,
  Client relationship, selected categories, and exact nullable allocations as
  one observable operation. Attachment upload reconciles through the separate
  durable media lifecycle.
- Project rename, Client rename, Project archive, and any future Client
  reassignment are distinct operations.
- Project archive preserves all history. No normal delete may orphan Items,
  Transactions, Spaces, notes, Invoices, preferences, or accounting evidence.
- Current lists/details remain usable from synchronized local data and expose
  readiness when a Project's required history is not fully available offline.

## Project Entity

**Firestore path:** `accounts/{accountId}/projects/{projectId}`

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | auto | Document ID |
| `accountId` | string | yes | Owning account |
| `name` | string | yes | Project name (non-empty) |
| `clientName` | string | yes | Client's name (non-empty) |
| `description` | string | no | Free text description |
| `mainImageUrl` | string | no | Hero image URL (uploaded to Firebase Storage) |
| `isArchived` | boolean | no | Soft delete flag (default: false/nil) |
| `budgetSummary` | object | no | Denormalized budget progress (maintained by Cloud Function triggers — see budget-management.md) |

### Validation

- `name` must be non-empty after trimming whitespace
- `clientName` must be non-empty after trimming whitespace
- Duplicate project names are allowed (projects are identified by ID, not name)

## Project Data Scope

A project owns (via `projectId` foreign key):

- **Transactions** — all transactions where `projectId` matches
- **Items** — all items where `projectId` matches
- **Spaces** — all spaces where `projectId` matches
- **ProjectBudgetCategories** — budget allocations at `accounts/{accountId}/projects/{projectId}/budgetCategories/{categoryId}`

When a project detail view activates, the system subscribes to all of these collections filtered by `projectId`, plus account-level budget categories and user project preferences (pinned categories).

## Creation Flow

Project creation uses a 3-step sheet form:

### Step 1: Basic Info

- Project name (required)
- Client name (required)
- Description (optional)
- Hero image (optional — selected via PhotosPicker)

### Step 2: Category Selection

- Shows all active (non-archived) account-level budget categories, sorted by `order`
- All categories are pre-selected by default; user unchecks any they don't need
- Each row shows category name and type badge (Itemized / Fee) where applicable — general categories have no badge
- "Add Category" button opens a create form for a new budget category
- **On-the-fly category creation:** Creates the category at account level (`accounts/{accountId}/presets/default/budgetCategories`), making it available in Settings and all future projects. The new category is auto-selected for the current project.
- At least one category must be selected to proceed

### Step 3: Budget Amounts

- Shows only the categories selected in Step 2
- Currency input per category for budget allocation
- Budget amounts are optional (categories can be enabled with no budget set)

### On Create

1. Project document created (fire-and-forget) — dismiss happens immediately (optimistic UI)
2. Background: for each selected category, a `ProjectBudgetCategory` document is created with the entered `budgetCents` (0 if left empty)
3. Background: hero image uploaded to Firebase Storage if provided, then `mainImageUrl` updated on the project document

## Editing

Edit uses the same 3-step sheet as creation, pre-populated with current values.

### Category Diffing on Save

The edit flow diffs the selected categories against the original state:

- **Added categories:** New `ProjectBudgetCategory` documents are created
- **Removed categories:** `ProjectBudgetCategory` documents are deleted
- **Kept categories with changed budget:** `ProjectBudgetCategory` documents are updated with the new `budgetCents`
- **Kept categories with unchanged budget:** No write (skip)

Project field updates and category changes happen in background tasks after immediate dismiss (optimistic UI).

## Archiving

Projects can be archived by setting `isArchived` to `true`. Archiving is preferred over deletion.

- Archived projects are hidden from the Active tab in the project list
- Archived projects appear in the Archived tab
- All data is preserved (transactions, items, spaces, budget allocations)
- Projects can be unarchived by setting `isArchived` back to `false`
- Unarchiving navigates back (dismissed from detail since the project was opened from the archived tab)

## Deletion

### Current Firebase behavior

Project deletion removes the project document. This is destructive and prompts for confirmation.

- If the project contains items, the confirmation warns: "This will delete the project and orphan N items. Consider archiving instead to preserve data."
- If the project is empty, the confirmation shows: "This action cannot be undone."
- Associated transactions, items, and spaces are NOT automatically deleted — they become orphaned with a `projectId` that no longer resolves
- On deletion, the user is dismissed back to the project list

This behavior must not be copied into the target. Target physical deletion is
blocked on O-024; archive is the safe supported lifecycle meanwhile.

## Project List

### Layout

- Active/Archived segmented picker at top
- Scrollable list of project cards, sorted alphabetically by name
- "+" button in toolbar opens the creation sheet
- Empty state when no projects exist in the selected tab

### Project Card

Each card shows:

- Hero image (or placeholder if none)
- Project name
- Client name
- Budget preview bars (0–N categories)

### Budget Preview on Cards

Budget preview uses the denormalized `budgetSummary` on the project document. Fallback chain:

1. **Pinned categories** — if the user has pinned categories for this project, show all pinned categories
2. **Top 2 by spend percentage** — if no pins, show the top 2 categories by highest spend percentage (excludes archived categories)
3. **Overall Budget** — if no categories have budget activity, show overall budget totals
4. **Nothing** — if no budget data exists at all

Amounts only — no percentage displayed on the card.

User pin preferences are stored at `accounts/{accountId}/users/{userId}/projectPreferences/{projectId}` with a `pinnedBudgetCategoryIds` array (see budget-management.md for full pinning spec).

## Project Detail

### Layout

- Toolbar: project name and client name centered, kebab menu on the right
- Pinned budgets section at top (always visible across tabs)
- Segmented picker with 4 tabs: Items, Transactions, Spaces, Finances
- Tab content area below

### Tabs

| Tab | Content |
|-----|---------|
| Items | Item list for this project (see items spec) |
| Transactions | Transaction list for this project (see transactions spec) |
| Spaces | Space list for this project (see spaces spec) |
| Finances | Sub-tabs: Budget and Reports |

The Finances tab contains its own segmented picker with Budget and Reports sub-tabs. Budget shows per-category budget progress (see budget-management.md). Reports shows report generation options (see reports.md).

### Kebab Menu Actions

| Action | Behavior |
|--------|----------|
| Edit Project | Opens 3-step edit sheet |
| Export Transactions | Opens CSV export sheet — if on Transactions tab, uses filtered transactions; otherwise exports all project transactions |
| Archive / Unarchive | Confirmation dialog, then toggles `isArchived` |
| Delete | Destructive confirmation dialog, then deletes project document |

## Edge Cases

1. **Project with no transactions** — valid state; shows empty transaction list
2. **Project with no budget categories enabled** — valid; budget section shows empty state
3. **Deleting a project with items** — warns about orphaning, suggests archiving
4. **Duplicate project names** — allowed (identified by ID)
5. **Offline project creation** — works via fire-and-forget write. Budget summary won't populate until the Cloud Function trigger runs (requires connectivity for server-side denormalization)
6. **Hero image upload failure** — project is created without image; upload can be retried via edit
7. **Category created on-the-fly during project creation** — immediately available account-wide, auto-selected for the current project
