# Proto Item Capture Implementation Plan
Status: in progress
Last updated: 2026-05-18

## Goal

Implement persistent proto item capture so designers can capture physical items quickly, then convert those captures later into real items, existing receipt-created items, or inventory-to-project flows.

Primary spec: [../specs/proto-item-capture.md](../specs/proto-item-capture.md)

UI naming: show these records as **Item Quick Drafts**. Keep `ProtoItem` for code and Firestore.

Visibility principle: item quick drafts live in their capture context first. The **Items** surface is the canonical home for both **Item Quick Drafts** and real **Items** in project, transaction, and inventory contexts. Needs Review is the cross-workflow cleanup queue, not the only home for drafts.

## Phase 1 — Data Model And Services

Add a separate `ProtoItem` model and service layer.

Progress:

- Created the `ProtoItem` model, status/context/source-hint enums, and extraction payload.
- Added `ProtoItemsService` and `ProtoItemsServiceProtocol` for create, update, delete, review, convert, scoped subscriptions, and photo upload metadata.
- Added Firestore rules for `accounts/{accountId}/protoItems/{protoItemId}`.
- Added initial codable and media path tests.

Work items:

- [x] Create `ProtoItem` model with fields from the data model spec.
- [x] Add `ProtoItemsService` for create, update, delete, and conversion-state writes.
- [x] Add upload support for proto item images.
- [x] Add account-scoped query for open/in-review proto items.
- [x] Add scoped queries for project, inventory, and transaction contexts.
- Keep proto items out of normal item queries and budget/report calculations.

Acceptance:

- A proto item can be created with photos and context.
- Open proto items survive app restart.
- Existing item lists and transaction totals do not change when proto items are created.

## Phase 2 — Fast Capture UI

Build the capture experience around repeated, low-friction entry.

Progress:

- Added a project-scoped `ItemDraftCaptureSheet` entry from the Project Items tab.
- The sheet captures an optional quick name plus grouped photos. It preserves multi-select from the photo library and multi-shot camera capture before returning to the form. Source, notes, SKU, vendor, category, price, and other item metadata belong to the conversion flow when the draft becomes or merges into a real item.
- Saving creates a `ProtoItem`, queues photo uploads, and resets for the next item quick draft.

Entry points:

- [x] Project detail: capture item for current project.
- Inventory: capture item for inventory, optional intended project.
- Transaction detail: capture item with `candidateTransactionId`.

Capture UI:

- Add object photo.
- Add tag/SKU/price photo.
- Add more photos if needed.
- Optional quick source hint: client purchase, business purchase, from inventory.
- [x] Save and immediately reset for the next item quick draft.

Acceptance:

- A designer can capture multiple proto items in sequence without reselecting project context.
- Capture requires no price, vendor, SKU, category, or transaction.
- Project/inventory context is visible before save.

## Phase 3 — Needs Review Integration

Surface proto items in their natural contexts and in the review workflow.

Work items:

- Keep Transaction Detail as a single scrolling page.
- Add transaction-linked Item Quick Drafts as a collapsible section in that scroll.
- Keep the existing transaction Items section collapsible and preserve its sticky composite header/control bar by using `SharedItemsList` inline mode with `inlineSectionHeader`.
- Replace the Project Items sub-tab design with two collapsible sections on the same scrolling page: Item Quick Drafts and Items.
- Keep the Project Items real-item section on `SharedItemsList` inline mode so project-level search/sort/filter/select/bulk controls apply only to real items and keep their sticky behavior.
- Add one project Items add affordance that routes to Item Quick Draft or New Item.
- Add `Item Quick Drafts` and `Items` sub-areas for Inventory when the inventory UI is implemented.
- Add proto item sections to Needs Review as an account-wide cleanup queue.
- Group by project, intended project, inventory/unassigned, and transaction-linked captures.
- Show image group and context hints in review queues; keep contextual project/transaction cards photo-first.
- Add actions: convert to item, merge with existing item, convert from inventory, delete draft.

Acceptance:

- Transaction Detail remains one scrolling page with peer collapsible sections.
- Transaction Item Quick Drafts and real Items are separated into collapsible sections.
- The transaction real Items section preserves the original sticky section header/control bar behavior.
- Real item list controls remain scoped to real Items and do not imply they affect Item Quick Drafts.
- A user opening a project can see unconverted item quick drafts for that project in the Project Items tab's Item Quick Drafts section.
- Project Items and Transaction Detail teach the same structure: Item Quick Drafts for captures, Items for real item records.
- Item Quick Draft cards open a dedicated draft detail screen for inline name/media edits.
- Item Quick Draft cards expose a kebab menu for Convert to Item, Merge with Existing Item, and Delete Draft.
- Project-scoped Item Quick Draft cards expose a lightweight From Inventory control that marks the draft for later inventory-to-project conversion without creating item, budget, transaction, sale, or lineage effects.
- Convert to Item seeds the normal item creation flow with the draft name/photos and marks the draft converted after item creation.
- Delete Draft removes the proto item and its media.
- A user opening inventory can see unconverted inventory item quick drafts in the inventory Items surface.
- A reviewer can find all unconverted proto items from one place.
- Proto item cards make the next action obvious.
- Converted/deleted proto items leave the active queue.

## Phase 4 — Conversion Flows

Implement manual conversion first.

### Create Item

- Convert proto item into a new inventory item or project item.
- Reuse existing item creation and transaction membership rules.
- Mark proto item `converted` with `convertedItemId`.

### Merge with Existing Item

- Let reviewer search/filter existing items, especially skeletal receipt-created items.
- Attach proto item images to the chosen item.
- Optionally copy notes/extracted text.
- Mark proto item `converted` with `convertedItemId`.

### Convert From Inventory

- If the draft is marked From Inventory, route through existing inventory-to-project operations.
- Require destination project and budget category before committing sale.
- Mark proto item converted once the resulting item/project sale is created.

Acceptance:

- Every conversion path is reversible through existing item/transaction editing where practical.
- Merge does not create duplicate items.
- From Inventory conversion uses existing inventory movement mechanics rather than a parallel write path.

## Phase 5 — Automation Assist

Layer in suggestions after the manual workflow is useful.

Candidates:

- On-device OCR for SKU/price/tag text.
- Suggested receipt transaction from date/vendor/project context.
- Suggested existing item match by SKU or name.
- Suggested item name from image or receipt description.

Acceptance:

- Suggestions are optional and human-confirmed.
- Low-confidence matches remain open.
- No automated suggestion creates budget impact without confirmation.

## Test Strategy

- Unit tests for `ProtoItem` encode/decode and status transitions.
- Service tests for create/update/delete/convert writes.
- UI tests for repeated capture flow.
- Review queue tests for grouping and filtering.
- Integration tests for merge and From Inventory conversion.
- Regression tests confirming unconverted proto items do not affect item counts, transaction completeness, budgets, invoices, or reports.

## Rollout Notes

This should ship behind a feature flag or hidden entry point until the full capture → review → convert loop works. A capture-only release would create a new backlog bucket without giving the reviewer a way to clear it.
