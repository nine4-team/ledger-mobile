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

- O-052 owns the unresolved role/capability matrix for Project creation,
  description, note creation/editing/deletion, hero-image upload/replacement,
  archive/restore and Project category-allocation mutation.
  Financial read access and existing isolated capability flags do not approve
  those writes. Project rename remains under O-050 and shared category creation
  under O-026; do not substitute one command's grant for another.
- Every Project belongs to one authoritative account-scoped Client by stable ID.
  Client display names remain searchable but never authorize relationships or
  same-Client Transfers.
- Project creation selects or creates a Client and durably records the Project,
  Client relationship, selected categories, and exact nullable allocations as
  one observable operation. Attachment upload reconciles through the separate
  durable media lifecycle.
- Project rename, Client rename, Project archive, and any future Client
  reassignment are distinct operations.
- Project description remains optional. Updating or clearing it is a distinct
  `UpdateProjectDetails` intent: leading/trailing whitespace is not stored and
  whitespace-only input clears the description. It cannot rename the Project,
  change its Client, categories, media, lifecycle, children, or accounting
  history.
- Project archive preserves all history. No normal delete may orphan Items,
  Transactions, Spaces, notes, Invoices, preferences, or accounting evidence.
- Archiving requires an explicit confirmation bound to the currently selected
  active Project and its observed revision. Confirming while offline accepts one
  durable archive operation immediately, moves the Project from Active to
  Archived as pending local evidence, and never doubles as restore/unarchive.
  If the selected Project or revision changes before confirmation, the stale
  confirmation is discarded rather than applied to different evidence.
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
| `notes` | string | no | Initial/legacy Project notes, distinct from description and individual Project-note records |
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
- **Project notes** — individual note records in the Project, in addition to
  the source Project's optional legacy `notes` text
- **ProjectBudgetCategories** — budget allocations at `accounts/{accountId}/projects/{projectId}/budgetCategories/{categoryId}`

When a project detail view activates, the system subscribes to all of these collections filtered by `projectId`, plus account-level budget categories and user project preferences (pinned categories).

## Creation Flow

Project creation uses a 3-step sheet form:

### Step 1: Basic Info

- Project name (required)
- Client name (required)
- Description (optional)
- Initial notes (optional; the current source saves trimmed text in
  `Project.notes`, displayed separately from individual notes)
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
- In the current source, successful archive dismisses detail; successful
  unarchive keeps detail open. These are current-navigation facts, not a new
  decision about the redesigned target's navigation.

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
- Business Inventory navigation card in Active only
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

The layout below describes the current source UI, verified against
`LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailView.swift` on 2026-09-07. It
corrects the older four-tab/Finances description. Preserve the available
capabilities in the target; this source description does not independently
settle target navigation organization or the redesigned Invoicing model.

### Layout

- Toolbar: project name and client name centered, kebab menu on the right
- Pinned budgets section at top (always visible across tabs)
- Scrollable tab bar: Items, Transactions, Spaces, Notes, Budget, Billing, Reports
- Tab content area below

### Tabs

| Tab | Content |
|-----|---------|
| Items | Item list for this project (see items spec) |
| Transactions | Transaction list for this project (see transactions spec) |
| Spaces | Space list for this project (see spaces spec) |
| Notes | Project notes in NotesTabView |
| Budget | Per-category budget progress |
| Billing | Current BillingTabView workspace |
| Reports | Report generation options in AccountingTabView |

Items is the default; an unknown tab ID falls back to Items. The toolbar also
offers Quick Note for the current Project. Notes are separate records, not the
Project description. Budget and Reports have their own tabs; see
budget-management.md and reports.md for their behavior. Target Invoicing
semantics remain governed by invoice-centered-project-accounting.md.

### Notes and Quick Note

Current source verification (`NewProjectView`, `ProjectService`, `NotesTabView`)
shows two forms of notes: initial `Project.notes` text displayed in a read-only
Legacy Notes card, and individual notes displayed newest first. Preserve both
kinds of content and their provenance in target migration; do not silently
merge them into the description or invent author/time metadata.

Individual notes support multiline entry, send, edit, and confirmed deletion;
dismissal cancels deletion. Their cards show available source, author and date
metadata, with no edit/delete menu for a record lacking stable identity. Empty
state retains the input, failed send restores attempted text, and failures stay
visible without leaving the Project. The toolbar Quick Note opens capture for
the current Project. Target app/MCP text validation remains gated by O-039;
this source-behavior inventory does not approve a new text or storage policy.

Quick Note also permits explicit Project selection. It prefills the current
Project only when the current ID and represented Project ID agree. Save requires
a Project and valid text; Save and Cancel are disabled while saving. Failure
keeps the form editable after error acknowledgement, and ordinary Cancel leaves
the Project unchanged. These controls are recorded in the current Product
Behavior Catalog; they are not reasons to create a second note-writing model.

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
