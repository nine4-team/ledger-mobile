# Proto Item Capture
Status: new
Last updated: 2026-05-21

User-facing name: **Item Quick Draft**. The code/data model uses `ProtoItem`; UI copy should use "Item Quick Draft" or "Item Quick Drafts".

## Summary

Proto item capture lets a designer record a physical object quickly before all item details are known. A proto item is a persistent photo group plus lightweight context. It is not a real `Item` yet and does not affect project budgets, inventory value, transactions, invoices, or reports until it is converted.

The goal is to make the field workflow simple: capture the object now, convert the business data later.

## Problem

Designers can usually log transactions later, but item-level detail capture is the painful part. When unloading purchases or installing at a project, the designer may know "this object is for Sandra" or "this came from our inventory" but may not know the receipt, vendor, SKU, purchase price, project price, or transaction line yet.

The current item flow asks for too much too early. It treats item creation as a data-entry task when the real first task is physical capture.

## Core Concept

A **ProtoItem** is the data model for an item quick draft: a draft capture record for one physical object or one intended line item.

It can contain:

- one or more photos of the object
- one or more photos of the tag, price label, SKU, or packaging
- an optional quick name/label for the capture
- optional project context
- optional extracted text/OCR metadata in a later phase
- conversion state

It cannot contain:

- budget impact
- invoice membership
- sale/return transaction impact
- canonical item lineage

Those belong to real `Item` and `Transaction` records after conversion.

## Capture Principle

At capture time, ask only what the designer already knows.

At review time, ask what the business needs.

This means capture should not require price, vendor, tax, budget category, SKU, transaction, project price, or final item details. It should prioritize repeated capture speed: optional quick name, photo, tag photo, save, next.

The add flow is photo-first with one optional text field: a quick name/label. Project-scoped capture may also expose the lightweight **From Inventory** affordance because it records routing intent without requiring conversion metadata. When the user taps add for an Item Quick Draft, the app shows the lightweight draft form and lets the user add photos from camera or photo library. The user must be able to select multiple photos from the library and take multiple camera photos before returning to the form. Source, notes, SKU, vendor, category, price, and other item metadata are collected later during conversion, when the draft is converted into or merged with a real `Item`.

## Entry Points

Item drafts should be visible where they were captured, not only in a review queue. The Needs Review area is a cross-workflow cleanup workbench, but the project, inventory, or transaction context is the draft's natural home.

Across contexts, the **Items** surface is the canonical place for item-like work. If a context has both unfinished captures and real items, the Items surface should expose the same two sub-areas:

- **Item Quick Drafts**: unconverted `ProtoItem` records.
- **Items**: real `Item` records.

This keeps the navigation vocabulary consistent. Users should learn that "Items" contains both drafts and finished items, while "Needs Review" means "work that needs attention."

### Project Capture

When the designer is in a project and adds a proto item:

- `projectId` is set to the current project.
- The capture is treated as intended for that project.

This handles the common workflow: "I am unloading or installing items for this project."

### Inventory Capture

When the designer is in business inventory and adds a proto item:

- `projectId` is null.
- The capture belongs to business inventory.

This handles: "We bought this, but it will probably go to Sandra later."

### Transaction Capture

Transaction-scoped capture is allowed but should not be the primary flow. If a proto item is captured from a transaction detail screen:

- `transactionId` is set to that transaction as the authoritative association.
- `projectId` may be inherited from the transaction if present.
- The proto item still remains separate from real items until converted.

This replaces the narrow ephemeral "create items from images" workflow with persistent capture groups.

## Contextual Visibility

Unconverted item quick drafts should appear in their owning context before the normal item list. This keeps captured objects discoverable in the place the designer expects to find them.

### Project Items

Project-scoped item quick drafts appear in the Project Items tab as an **Item Quick Drafts** collapsible section. Real project items remain in a separate **Items** collapsible section on the same scrolling page.

The Item Quick Drafts section should:

- show only unconverted drafts for the current project
- show a photo-first draft row/card with up to 3 thumbnails and a small action menu
- omit status badges, source/date/note fields, and normal item metadata from the contextual row/card
- keep item quick drafts visually distinct from real items
- expose a lightweight **From Inventory** control for marking drafts that came from business inventory
- offer draft actions from the card menu: convert to item, merge with existing item, and delete draft

The **From Inventory** control is a conversion hint, not a completed sale. It records that the draft should later be converted through the inventory-to-project flow. Setting this hint must not require price, budget category, transaction, SKU, or full item metadata, and it must not create budget, transaction, sale, or lineage effects by itself.

Tapping **From Inventory** toggles the hint immediately. Do not show a confirmation dialog, because no financial or destructive action has happened. Instead, show a readable toast near the control the user just tapped. The toast should stay visible for about 4 seconds:

- When turned on: "Marked \"From Inventory\""
- When turned off: "Removed \"From Inventory\" Marker."

The real Items section should reuse the existing shared item list machinery so search, sort, filter, select, and bulk actions remain scoped to real `Item` records. Its section header and control bar should preserve the sticky behavior used by transaction item sections.

Tapping a draft opens an Item Quick Draft detail screen. The detail screen is the edit surface for the draft:

- inline editable quick name
- editable media gallery: add photos, remove photos, set primary
- convert to item
- merge with existing item
- From Inventory hint, when project-scoped
- delete draft

There is no separate "Edit Draft" menu item because opening the detail screen is the edit action.

### Inventory Items

Inventory-scoped item quick drafts should follow the same pattern when inventory gets the full implementation: Inventory Items exposes **Item Quick Drafts** and **Items** collapsible sections rather than hiding drafts only in review.

The section should:

- show unconverted drafts with `projectId == null`
- surface `intendedProjectId` when present
- support converting into inventory, assigning/selling to a project, merging with an existing item, or deleting

### Transaction Detail

Transaction Detail remains a single scrolling page. It should not split the transaction into top-level Details and Items tabs.

Item-related content appears as peer collapsible sections in the main transaction scroll:

- **Item Quick Drafts**: unconverted `ProtoItem` records linked to this transaction.
- **Items**: real `Item` records linked to this transaction.
- **Returned Items** and **Sold Items**: lineage-derived historical item sections, shown when present.

The sections keep each object type's controls clear. Item Quick Drafts should not be forced into `SharedItemsList`, and real item search/sort/filter/select controls should remain scoped to real Items.

Contextual Item Quick Draft rows/cards are photo-first: up to 3 thumbnails plus an action menu, with no badges or metadata fields. Even if a draft has an optional quick name, conversion details belong in the draft workflow, not in the contextual section row. Project-scoped draft cards may show the lightweight **From Inventory** control because that hint is part of capture, not full item metadata.

The real Items section should preserve the existing collapsible/sticky section behavior: the Items section header and the SharedItemsList control bar pin together while the user scrolls. The add menu can route to:

- Item Quick Draft
- New Item
- Add Existing Items
- Create from Images, when transaction images are available

This keeps creation centered on the user task: "add something item-related to this transaction," while keeping draft management and real item management separate inside the same transaction document.

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
| `open` | Captured but not converted |
| `in_review` | A human or assistant is actively converting it |
| `converted` | Converted or merged into an item |

Only `open` and `in_review` proto items appear in active review queues.

### Conversion Metadata

Source, destination, SKU, vendor, category, price, notes, and suggested matches are conversion metadata. They are collected when an Item Quick Draft is turned into a real item, merged with an item, or routed through the inventory-to-project flow. Except for the lightweight **From Inventory** hint, they should not be required in the initial photo capture flow.

Conversion hints should be simple and reversible:

| Field | Meaning |
|---|---|
| `projectId` | Project the capture is currently associated with. Null means inventory/unassigned. |
| `intendedProjectId` | Destination project hint for an inventory capture. |
| `transactionId` | The single authoritative transaction the eventual item should initially join. Null means no transaction has been selected yet. |
| `sourceHint` | One of `unknown`, `client_purchase`, `business_purchase`, `from_inventory`. `from_inventory` may be set by the card-level **From Inventory** control. |
| `candidateItemId` | Possible matching item. Not authoritative until converted. |

`transactionId` is not a suggestion field. Capturing from Transaction Detail sets it immediately. A transaction suggested later by Ledger remains transient until a human accepts it; acceptance writes `transactionId`. `candidateTransactionId` is deprecated and must not be used as a promotion fallback.

Hints and transaction association never create budget or transaction effects by themselves.

## Conversion

An Item Quick Draft is converted by one of these actions:

### Create New Item

The proto item's photos and context are used to create a new `Item`.

If the proto item is project-scoped, conversion must choose or create a valid project transaction/category before the item becomes budget-impacting. If the proto item is inventory-scoped, the new item is created in inventory with `projectId == null` and `budgetCategoryId == null`.

For a project-scoped quick draft with `transactionId`, conversion resolves the referenced transaction before writing:

- If `transaction.projectId == protoItem.projectId`, create the item directly in that project and link it to the selected project transaction.
- If `transaction.projectId == null`, use the atomic inventory-transaction-to-project-sale path defined below.
- If the transaction belongs to another project, block conversion until the association is corrected.
- If `transactionId` is null, the draft remains unconverted until the user selects or creates the transaction it should join.

The convert flow reuses the normal item creation flow seeded with the draft's quick name and photos. After the item is created, the proto item is marked `converted` with `convertedItemId`.

### Merge with Existing Item

The proto item's photos, notes, and any extracted metadata are attached to an existing `Item`.

This is the preferred flow when receipt/email parsing has already created skeletal items with SKU and price. A reviewer can search or filter by SKU, pick the matching item, and merge the captured photos into it.

### Convert From Inventory To Project

For a project-scoped proto item whose authoritative `transactionId` points to a business-inventory transaction, conversion must route through the existing inventory-to-project mechanism. The transaction scope, not a second transaction field, determines the route.

Before writing, validate that:

- the referenced transaction exists, belongs to the same account, and has `projectId == null`;
- the draft has a destination `projectId`;
- the intended/destination budget category belongs to and is enabled for that project; and
- the item has the purchase price, project price, and other fields required by the canonical sale operation.

Once validation succeeds, perform one atomic operation:

1. create the real item in business inventory under the referenced acquisition transaction with `projectId == null`, `budgetCategoryId == null`, and `transactionId` equal to the acquisition transaction ID;
2. create the canonical per-batch Purchase-from-inventory transaction in the draft's project using `projectPriceCents`;
3. move the item into the draft's project/category and replace its `transactionId` with the new project Purchase ID;
4. remove the item from the acquisition transaction's active `itemIds` membership and preserve the acquisition through a sold lineage edge; and
5. mark the proto item converted and set `convertedItemId` to the final item.

Do not create the inventory item first and attempt the sale in a later non-atomic step. Missing price, category, project, or transaction data must leave the quick draft unconverted rather than stranding a partially converted item in inventory.

The **From Inventory** marker remains useful before a transaction is selected: it tells review that an inventory transaction must be chosen. Once `transactionId` is set, the referenced transaction's scope is authoritative. A project transaction combined with `sourceHint == from_inventory` is a conflict that must be resolved before conversion.

### Delete Draft

If the capture is accidental, duplicate, or not needed, it can be deleted. Deleting a draft removes the proto item and its media.

## Review Queue

Proto items should also appear in the Needs Review area as a first-class review type. Needs Review is the global workbench for finding and converting unconverted drafts across the account; it is not the only place item quick drafts live.

The queue should group by:

1. project captures
2. inventory captures with intended destination project
3. unassigned inventory captures
4. transaction-linked captures

Each row/card should show the image group, capture context, and the next likely action:

- Create item
- Merge with Existing Item
- Match receipt/transaction
- Convert From Inventory
- Delete draft

## AI And Automation

AI is an accelerator, not a dependency for v1.

The app should be useful with a human reviewer doing the matching manually. Later phases can add:

- on-device OCR for tag/SKU/price text
- receipt line matching by SKU/date/vendor/amount
- suggested item names from images
- suggested merge targets
- confidence labels

Automated suggestions should never silently convert proto items in v1. A human confirms the create/merge/from-inventory action.

## Relationship To Existing Items

Proto items are not incomplete `Item` documents. They are separate captures that may become or enrich items.

This protects existing invariants:

- inventory items still have `projectId == null` and `budgetCategoryId == null`
- project items still need a real transaction/category relationship
- item counts continue to mean real items
- reports and invoices ignore unconverted captures

## Relationship To Transactions

Proto items may point at one authoritative transaction through `transactionId`, but transactions do not own proto items as embedded children. The transaction is financial evidence; the proto item is physical evidence. Review connects them.

If a proto item converts into a transaction-created item, the resulting `Item` follows normal transaction membership rules. For project drafts linked to inventory transactions, the acquisition transaction is the initial association and the canonical sale replaces the final item's `transactionId`; lineage preserves the original acquisition relationship.

## Open Questions

- Should proto item images be stored using the same attachment uploader and storage path as item images, or under a separate `protoItems` path?
- Should a proto item support multiple quantities, or should repeated physical objects be captured as separate proto items?
- What is the exact UX for selecting an existing skeletal item during merge?
- Should OCR run immediately after capture on-device, or only when the reviewer opens the queue?
