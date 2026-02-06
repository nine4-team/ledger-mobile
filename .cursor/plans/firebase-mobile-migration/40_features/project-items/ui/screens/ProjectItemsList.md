# Screen contract: Project Items List

This contract defines **project-scope** Items list behaviors relevant to canonical attribution + `inheritedBudgetCategoryId` guardrails.

Shared-module requirement:

- The Items list UI (including per-row actions menus and bulk controls) must be a **shared implementation** reused across Project + Business Inventory scopes, with scope-driven configuration (not duplicated implementations).
- The guardrails in this doc apply when the active scope is **Project** and the user is attempting Project → Business Inventory operations.

Source of truth:

- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`

Primary parity evidence (web):

- Project list page: `src/pages/InventoryList.tsx`
- Per-item actions menu: `src/components/items/ItemActionsMenu.tsx`
- Bulk actions surface: `src/components/ui/BulkItemControls.tsx`
- Sell/deallocate action triggers deallocation: `src/pages/InventoryList.tsx` (calls `integrationService.handleItemDeallocation`)

---

## Core list behaviors (non-exhaustive)

List UI (search/filter/sort/group, selection, bulk actions) should match existing parity patterns. This doc focuses only on behaviors impacted by the canonical attribution rules.

### Search (required; parity)
Project-scope item search must match current web parity.

- State key (web parity): `itemSearch`.
- Mobile (Expo Router): persist via list state store keyed by `listStateKey = project:${projectId}:items` (see shared list-state contract).
- **Search matches (web parity)**:
  - `item.description`
  - `item.source`
  - `item.sku` (including a normalized “fuzzy SKU” match that ignores non-alphanumeric chars, e.g. `3SEAT-001` matches `3SEAT001`)
  - `item.paymentMethod`
  - `item.space`

Parity evidence:
- Observed in `src/pages/InventoryList.tsx` (search filter logic).
- Observed in `src/pages/ItemDetail.tsx` (next/previous navigation uses the same filtered+sorted list logic).

### Filters (required; parity)

- State key (web parity): `itemFilter`
- Allowed modes (web parity):
  - `all`
  - `bookmarked`
  - `from-inventory`
  - `to-return`
  - `returned`
  - `no-sku`
  - `no-description`
  - `no-project-price`
  - `no-image`
  - `no-transaction`

Parity evidence:

- Observed in `ledger/src/pages/InventoryList.tsx` (`ITEM_FILTER_MODES`, `itemFilter` URL param).

### Sort (required; parity)

- State key (web parity): `itemSort`
- Allowed modes (web parity):
  - `alphabetical`
  - `creationDate` (newest-first)

Parity evidence:

- Observed in `ledger/src/pages/InventoryList.tsx` (`ITEM_SORT_MODES`, `itemSort` URL param).

### Duplicate grouping (recommended; parity)

Project items list should support “duplicate grouping” (collapsed groups) and preserve selection semantics.

Parity evidence:

- Observed in `ledger/src/pages/InventoryList.tsx` (`getInventoryListGroupKey`, `CollapsedDuplicateGroup`).

### List state + scroll restoration (required; Expo Router)

We do **not** wire scroll restoration separately for:

- project items
- inventory items

Instead, the shared Items list module owns:

- persistence of search/filter/sort (debounced) via `ListStateStore[listStateKey]`
- best-effort scroll restoration on return (anchor-first)

Required keys:

- Project items list: `listStateKey = project:${projectId}:items`
- Inventory items list: `listStateKey = inventory:items`

Restore behavior:

- When navigating list → item detail, record:
  - preferred: `anchorId = <opened itemId>`
  - optional fallback: `scrollOffset`
- When returning to the list, restore best-effort (anchor-first) and clear the restore hint after first attempt.

Source of truth:
- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md` → “List state + scroll restoration”
- `40_features/navigation-stack-and-context-links/feature_spec.md`

---

## Item action restrictions (required)

### 1) Project → Business Inventory category resolution (prompt + persist)

If an item’s `inheritedBudgetCategoryId` is missing, the row actions menu must still allow `Sell → Sell to Business`, but initiating the action must:
- Prompt the user to select a category from the source project’s enabled categories.
- Persist it onto the item (`item.inheritedBudgetCategoryId`).
- Then proceed with the canonical sale (`project_to_business`) request-doc workflow.

Notes:
- This is an **intentional Firebase-migration delta**; current web code does not check this field (field does not exist yet).
- “Move to Business Inventory” is a correction path and does not create canonical sale transactions; it remains blocked when the item is transaction-attached (same parity behavior).

---

## Status changes (required)

### 2) “Sell to Business” triggers canonical deallocation (and may prompt)

When the user initiates `Sell → Sell to Business`, the system triggers the canonical deallocation flow (project → business inventory).

Parity evidence (web):

- `InventoryList` calls `integrationService.handleItemDeallocation(...)` from the item actions menu / flow (`src/pages/InventoryList.tsx`).

Required Firebase-migration policy:
- If `inheritedBudgetCategoryId` is missing, prompt for a category (per section 1) and persist it before submitting the request doc.
- If the user cancels the prompt, do not enqueue the request and keep the item unchanged.

---

## Bulk actions (required)

### 3) Bulk sell to Business

If the user bulk-initiates `Sell → Sell to Business`:
- If any selected item is missing `inheritedBudgetCategoryId`, prompt once for a category and apply it to the uncategorized items in the batch before submitting the request(s).
- The backend must split the operation into one canonical sale transaction per category as needed (no special UI required beyond the prompt).

Parity evidence (web):

- Bulk controls exist and include bulk cross-scope operations (`src/components/ui/BulkItemControls.tsx`), and the project items list bulk action triggers deallocation via `integrationService.handleItemDeallocation` (`src/pages/InventoryList.tsx`).

Intentional delta (vs web):

- Current web implementation does not have the `inheritedBudgetCategoryId` field and thus cannot enforce the guardrail.

### 4) Bulk move/sell (future surface)

If/when the Project Items list adds additional bulk “Move/Sell to Business Inventory” actions, they must follow the same prompt + persist rule for missing item category id.
Avoid “hard blocking” the operation solely due to missing category; resolve via prompt instead.

## Add item entrypoint (required; parity)

- The list must provide an “Add Item” entrypoint that navigates to the shared `ItemForm` create screen in project scope.

Parity evidence:

- Observed in `ledger/src/pages/InventoryList.tsx` (add item entrypoint).

