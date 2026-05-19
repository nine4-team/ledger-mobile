# Proto Item Capture Implementation Plan
Status: in progress
Last updated: 2026-05-18

## Goal

Implement persistent proto item capture so designers can capture physical items quickly, then resolve those captures later into real items, existing receipt-created items, or inventory-to-project sales.

Primary spec: [../specs/proto-item-capture.md](../specs/proto-item-capture.md)

UI naming: show these records as **Item Drafts**. Keep `ProtoItem` for code and Firestore.

Visibility principle: item drafts live in their capture context first. The **Items** surface is the canonical home for both **Item Drafts** and real **Items** in project, transaction, and inventory contexts. Needs Review is the cross-workflow cleanup queue, not the only home for drafts.

## Phase 1 — Data Model And Services

Add a separate `ProtoItem` model and service layer.

Progress:

- Created the `ProtoItem` model, status/context/source-hint enums, and extraction payload.
- Added `ProtoItemsService` and `ProtoItemsServiceProtocol` for create, update, review, resolve, dismiss, scoped subscriptions, and photo upload metadata.
- Added Firestore rules for `accounts/{accountId}/protoItems/{protoItemId}`.
- Added initial codable and media path tests.

Work items:

- [x] Create `ProtoItem` model with fields from the data model spec.
- [x] Add `ProtoItemsService` for create, update, dismiss, and resolve-state writes.
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
- The sheet captures grouped photos, optional source hint, and notes.
- Saving creates a `ProtoItem`, queues photo uploads, and resets for the next item draft.

Entry points:

- [x] Project detail: capture item for current project.
- Inventory: capture item for inventory, optional intended project.
- Transaction detail: capture item with `candidateTransactionId`.

Capture UI:

- Add object photo.
- Add tag/SKU/price photo.
- Add more photos if needed.
- Optional quick source hint: client purchase, business purchase, from inventory.
- [x] Save and immediately reset for the next item draft.

Acceptance:

- A designer can capture multiple proto items in sequence without reselecting project context.
- Capture requires no price, vendor, SKU, category, or transaction.
- Project/inventory context is visible before save.

## Phase 3 — Needs Review Integration

Surface proto items in their natural contexts and in the review workflow.

Work items:

- Refactor Transaction Detail into top-level `Details` and `Items` tabs.
- Keep existing non-item transaction sections in the default `Details` tab.
- Move item-related transaction sections into the `Items` tab.
- Add `Item Drafts` and `Items` sub-tabs inside the transaction `Items` tab.
- Add one item-related add affordance at the transaction `Items` tab level with routes for Item Draft, New Item, Add Existing Items, and Create from Images when available.
- Keep `SharedItemsList` scoped to the real `Items` sub-tab so sticky search/sort/filter/select controls apply only to real items.
- Add `Item Drafts` and `Items` sub-tabs inside the Project Items tab, matching the transaction Items pattern.
- Keep the Project Items real-item sub-tab on `SharedItemsList` so project-level search/sort/filter/select/bulk controls apply only to real items.
- Add one project Items add affordance that routes to Item Draft or New Item.
- Add `Item Drafts` and `Items` sub-areas for Inventory when the inventory UI is implemented.
- Add transaction-linked Item Drafts in the transaction `Items > Item Drafts` sub-tab.
- Add proto item sections to Needs Review as an account-wide cleanup queue.
- Group by project, intended project, inventory/unassigned, and transaction-linked captures.
- Show image group, context hints, capture date, and source hint.
- Add actions: create item, merge into item, sell from inventory, dismiss.

Acceptance:

- Transaction Detail has a default `Details` tab and a dedicated `Items` tab.
- The transaction `Items` tab separates Item Drafts and real Items into sub-tabs.
- There is a single item-related add affordance for the transaction `Items` tab, not competing add buttons in each sub-tab.
- Real item list controls remain scoped to real Items and do not imply they affect Item Drafts.
- A user opening a project can see unresolved item drafts for that project under Project Items > Item Drafts.
- Project Items and Transaction Items teach the same structure: Item Drafts for captures, Items for real item records.
- A user opening inventory can see unresolved inventory item drafts in the inventory Items surface.
- A reviewer can find all unresolved proto items from one place.
- Proto item cards make the next action obvious.
- Dismissed/resolved proto items leave the active queue.

## Phase 4 — Resolution Flows

Implement manual resolution first.

### Create Item

- Convert proto item into a new inventory item or project item.
- Reuse existing item creation and transaction membership rules.
- Mark proto item `resolved` with `resolvedItemId`.

### Merge Into Existing Item

- Let reviewer search/filter existing items, especially skeletal receipt-created items.
- Attach proto item images to the chosen item.
- Optionally copy notes/extracted text.
- Mark proto item `resolved` with `resolvedItemId`.

### Sell From Inventory

- If `sourceHint == from_inventory`, route through existing sell-to-project operations.
- Require destination project and budget category before committing sale.
- Mark proto item resolved once the resulting item/project sale is created.

Acceptance:

- Every resolution path is reversible through existing item/transaction editing where practical.
- Merge does not create duplicate items.
- Sale resolution uses existing inventory sale mechanics rather than a parallel write path.

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
- Service tests for create/update/dismiss/resolve writes.
- UI tests for repeated capture flow.
- Review queue tests for grouping and filtering.
- Integration tests for merge and sell-from-inventory resolution.
- Regression tests confirming unresolved proto items do not affect item counts, transaction completeness, budgets, invoices, or reports.

## Rollout Notes

This should ship behind a feature flag or hidden entry point until the full capture → review → resolve loop works. A capture-only release would create a new backlog bucket without giving the reviewer a way to clear it.
