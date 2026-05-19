# Proto Item Capture
Status: new
Last updated: 2026-05-18

## Summary

Proto item capture lets a designer record a physical object quickly before all item details are known. A proto item is a persistent photo group plus lightweight context. It is not a real `Item` yet and does not affect project budgets, inventory value, transactions, invoices, or reports until it is resolved.

The goal is to make the field workflow simple: capture the object now, resolve the business data later.

## Problem

Designers can usually log transactions later, but item-level detail capture is the painful part. When unloading purchases or installing at a project, the designer may know "this object is for Sandra" or "this came from our inventory" but may not know the receipt, vendor, SKU, purchase price, project price, or transaction line yet.

The current item flow asks for too much too early. It treats item creation as a data-entry task when the real first task is physical capture.

## Core Concept

A **ProtoItem** is a draft capture record for one physical object or one intended line item.

It can contain:

- one or more photos of the object
- one or more photos of the tag, price label, SKU, or packaging
- optional project context
- optional inventory/source hint
- optional destination hint
- optional notes
- optional extracted text/OCR metadata in a later phase
- resolution state

It cannot contain:

- budget impact
- invoice membership
- sale/return transaction impact
- canonical item lineage

Those belong to real `Item` and `Transaction` records after resolution.

## Capture Principle

At capture time, ask only what the designer already knows.

At review time, ask what the business needs.

This means capture should not require price, vendor, tax, budget category, SKU, transaction, project price, or final item name. It should prioritize repeated capture speed: photo, tag photo, save, next.

## Entry Points

### Project Capture

When the designer is in a project and adds a proto item:

- `projectId` is set to the current project.
- The capture is treated as intended for that project.
- The designer can optionally mark "from inventory" if the item should be sold from business inventory into this project.

This handles the common workflow: "I am unloading or installing items for this project."

### Inventory Capture

When the designer is in business inventory and adds a proto item:

- `projectId` is null.
- The capture belongs to business inventory.
- The designer can optionally set an intended destination project.

This handles: "We bought this, but it will probably go to Sandra later."

### Transaction Capture

Transaction-scoped capture is allowed but should not be the primary flow. If a proto item is captured from a transaction detail screen:

- `candidateTransactionId` is set.
- `projectId` may be inherited from the transaction if present.
- The proto item still remains separate from real items until resolved.

This replaces the narrow ephemeral "create items from images" workflow with persistent capture groups.

## Data Rules

### Storage

Proto items live in their own collection:

`accounts/{accountId}/protoItems/{protoItemId}`

They are intentionally separate from `items` so normal item lists, item counts, budgets, invoices, and inventory operations are not polluted by incomplete captures.

### Required Fields

A proto item requires at least one image or a non-empty note. In normal use, at least one image is expected.

### Statuses

| Status | Meaning |
|---|---|
| `open` | Captured but not resolved |
| `in_review` | A human or assistant is actively resolving it |
| `resolved` | Converted or merged into an item |
| `dismissed` | Not an item, duplicate, accidental capture, or intentionally ignored |

Only `open` and `in_review` proto items appear in active review queues.

### Source and Destination Hints

Hints should be simple and reversible:

| Field | Meaning |
|---|---|
| `projectId` | Project the capture is currently associated with. Null means inventory/unassigned. |
| `intendedProjectId` | Destination project hint for an inventory capture. |
| `sourceHint` | One of `unknown`, `client_purchase`, `business_purchase`, `from_inventory`. |
| `candidateTransactionId` | Possible matching transaction. Not authoritative. |
| `candidateItemId` | Possible matching item. Not authoritative until resolved. |

Hints never create budget or transaction effects by themselves.

## Resolution

A proto item is resolved by one of these actions:

### Create New Item

The proto item's photos and context are used to create a new `Item`.

If the proto item is project-scoped, resolution must choose or create a valid project transaction/category before the item becomes budget-impacting. If the proto item is inventory-scoped, the new item is created in inventory with `projectId == null` and `budgetCategoryId == null`.

### Merge Into Existing Item

The proto item's photos, notes, and any extracted metadata are attached to an existing `Item`.

This is the preferred flow when receipt/email parsing has already created skeletal items with SKU and price. A reviewer can search or filter by SKU, pick the matching item, and merge the captured photos into it.

### Sell From Inventory To Project

If a project-scoped proto item is marked `sourceHint == from_inventory`, resolution should route through the existing sell-to-project mechanism:

1. reviewer selects the matching inventory item or creates one
2. reviewer selects the destination project/category if not already known
3. app creates the normal per-batch Sale transaction
4. proto item is marked resolved and linked to the resulting item

### Dismiss

If the capture is accidental, duplicate, or not needed, it can be dismissed. Dismissal does not delete image data immediately unless the user explicitly deletes it; this leaves an audit-friendly recovery path.

## Review Queue

Proto items should appear in the Needs Review area as a first-class review type. The queue should group by:

1. project captures
2. inventory captures with intended destination project
3. unassigned inventory captures
4. transaction-linked captures

Each row/card should show the image group, capture context, and the next likely action:

- Create item
- Merge with item
- Match receipt/transaction
- Sell from inventory
- Dismiss

## AI And Automation

AI is an accelerator, not a dependency for v1.

The app should be useful with a human reviewer doing the matching manually. Later phases can add:

- on-device OCR for tag/SKU/price text
- receipt line matching by SKU/date/vendor/amount
- suggested item names from images
- suggested merge targets
- confidence labels

Automated suggestions should never silently resolve proto items in v1. A human confirms the merge/create/sell action.

## Relationship To Existing Items

Proto items are not incomplete `Item` documents. They are separate captures that may become or enrich items.

This protects existing invariants:

- inventory items still have `projectId == null` and `budgetCategoryId == null`
- project items still need a real transaction/category relationship
- item counts continue to mean real items
- reports and invoices ignore unresolved captures

## Relationship To Transactions

Proto items may point at candidate transactions, but transactions do not own proto items. The transaction is financial evidence; the proto item is physical evidence. Review connects them.

If a proto item resolves into a transaction-created item, the resulting `Item` follows normal transaction membership rules.

## Open Questions

- Should proto item images be stored using the same attachment uploader and storage path as item images, or under a separate `protoItems` path?
- Should a proto item support multiple quantities, or should repeated physical objects be captured as separate proto items?
- Should `sourceHint` be a required quick toggle, or optional metadata hidden behind a secondary control?
- What is the exact UX for selecting an existing skeletal item during merge?
- Should OCR run immediately after capture on-device, or only when the reviewer opens the queue?
