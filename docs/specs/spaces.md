# Spaces

> **Target-state notice (2026-08-31):** Spaces remain organizational placement,
> never accounting authority. The target uses typed, scope-validating Space and
> Item-assignment operations over local read models. Current Firestore hard
> delete, independent bulk writes, URL-keyed review-note references, and
> last-write-wins embedded checklist updates are source behavior rather than
> target parity. O-037 controls assigned Items when a Space is archived.

## Overview

Spaces are organizational containers for items. They represent physical locations (rooms, storage units, warehouses) or logical groupings where items are placed. Spaces can belong to a project or to business inventory.

## Scope

- `projectId` set: space belongs to that project
- `projectId` null: space belongs to business inventory (account-wide)

Items are assigned to spaces via `item.spaceId`. Multiple items can share the same space.

## Space Fields

- `id` — unique identifier
- `accountId` — owning account
- `projectId` — owning project (null = business inventory)
- `name` — display name
- `notes` — free text notes
- `images` — array of AttachmentRef (no cap on image count)
- `checklists` — array of embedded Checklist objects
- `isArchived` — soft delete flag
- `createdAt`, `updatedAt` — timestamps

## Checklists

Spaces support embedded checklists for tracking setup tasks.

### Checklist Structure

Each checklist has:
- `id` — unique within the space
- `name` — checklist title (e.g., "Installation Tasks", "QC Checklist")
- `items` — array of checklist items

Each checklist item has:
- `id` — unique within the checklist
- `text` — task description
- `isChecked` — completion state (boolean)

### Checklist Progress

Progress is calculated as:

```
completedCount = count of items where isChecked is true
totalCount = total items in checklist
progressPercent = (completedCount / totalCount) * 100
```

When a space has multiple checklists, aggregate progress:

```
totalCompleted = sum of completedCount across all checklists
totalItems = sum of totalCount across all checklists
overallProgress = (totalCompleted / totalItems) * 100
```

## Space Templates

Reusable templates allow users to create new spaces with pre-configured checklists.

> **Current implementation gap:** Template management persistence exists, but
> the shipped New Space picker is a stub and Save as Template currently reports
> success without writing. The current `createFromSpace` service also copies
> checked state. These are source defects, not target parity: the target must
> support actual select/apply/save flows and reset every template checklist item
> to unchecked.

**Storage:** `accounts/{accountId}/presets/default/spaceTemplates/{templateId}`

### Template Fields

- `id` — unique identifier
- `name` — template name
- `notes` — default notes (optional)
- `checklists` — array of Checklist objects (items start unchecked)
- `isArchived` — soft delete flag
- `order` — numeric sort order for display

### Creating from Template

When a user creates a space from a template:
1. Copy template's `notes` to new space
2. Copy template's `checklists` to new space (all items set to unchecked)
3. User can customize the space after creation

### Saving as Template

Users can save an existing space's checklist configuration as a new template. The template captures the checklist structure but resets all `isChecked` values to false.

## Item Assignment

Items are assigned to spaces via `item.spaceId`:
- Setting `item.spaceId` to a space's ID assigns the item to that space
- Setting `item.spaceId` to null removes the assignment
- An item can only be in one space at a time
- Moving an item to a new space replaces the old assignment

### Bulk Assignment

Multiple Items may be assigned or cleared through one durable typed operation.
The authoritative handler validates that every Item and destination Space still
belong to the same Project or Business Inventory scope and applies the complete
selection atomically/idempotently. Scope-changing Item commands separately
validate or clear incompatible Space assignments.

## Space in Budget Context

Spaces do not directly participate in budget calculations. However, items in spaces carry their `budgetCategoryId`, and items in spaces contribute to transaction audit completeness through their `purchasePriceCents`.

## Edge Cases

1. **Space with no items**: Valid state -- spaces can exist as empty containers awaiting items.
2. **Deleting a space**: Ordinary removal means archive, not hard delete. O-037
   controls whether assigned Items retain a resolvable archived reference or
   must be explicitly moved/cleared; target code must not leave an unexplained
   hidden ID or silently erase placement.
3. **Moving items between spaces**: Use a typed, scope-validating assignment
   operation with stable Item IDs and a durable result.
4. **Space images**: No cap on image count (unlike transactions which may have separate receipt/other image categories).
5. **Empty checklists**: Valid -- a checklist can have zero items.
6. **Duplicate space names**: Allowed (spaces are identified by ID, not name).
