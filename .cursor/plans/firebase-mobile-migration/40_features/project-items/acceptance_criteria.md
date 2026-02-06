# Acceptance criteria: Project Items — canonical attribution + `inheritedBudgetCategoryId`

These criteria are written so a dev can implement the rules without reading the working doc.

All items below are **required** unless explicitly marked as optional.

Shared-module requirement:

- The Items list/detail/actions/bulk-controls components must be implemented as a **shared Items module** reused across Project + Business Inventory scopes (scope-driven configuration; no duplicated implementations).
- Source of truth: `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`

---

## A) Canonical vs non-canonical attribution rules

- **A1 (non-canonical)**: For non-canonical (user-facing) transactions, budget attribution uses `transaction.budgetCategoryId`.
- **A2 (canonical inventory sale)**: For canonical inventory **sale** transactions (recommended id prefix `INV_SALE__` + explicit direction), budget attribution is **transaction-driven**:
  - `transaction.budgetCategoryId` is required and is the single category for that canonical row
  - rollups apply sign based on direction (`business_to_project` adds, `project_to_business` subtracts)
- **A3 (system-owned canonical rows)**: Canonical inventory sale transactions are system-owned (read-only in UI). Users do not “set a category on the canonical row,” but the system may prompt for an item category when missing/mismatched so it can choose the correct canonical row.

Evidence / deltas:

- **Intentional delta** vs current web: budget rollups currently use legacy transaction category fields (e.g. `category_id` / `budgetCategory`) and do not group canonical rows by item category (`src/components/ui/BudgetProgress.tsx`).

---

## B) Item field: `inheritedBudgetCategoryId`

- **B1 (field exists)**: Every item record includes `inheritedBudgetCategoryId` (nullable), persisted in local DB and synced remotely.
- **B2 (stable across scope moves)**: When an item moves between project ↔ business inventory, `inheritedBudgetCategoryId` is preserved unless explicitly updated by a rule below.
- **B3 (set on user-facing link)**: When linking an item to a **non-canonical** transaction with a non-null `budgetCategoryId`, set:
  - `item.inheritedBudgetCategoryId = transaction.budgetCategoryId`
- **B4 (canonical sale operations may set the field)**: When a sell/allocation flow prompts the user to select a category, persist:
  - `item.inheritedBudgetCategoryId = <chosenCategoryId>`
- **B5 (do not clear on unlink)**: Unlinking an item from a transaction must not clear `item.inheritedBudgetCategoryId`.

---

## C) Project → Business Inventory category resolution (prompt + persist)

### C1 — Prompt requirement
If an item’s `inheritedBudgetCategoryId` is missing (null/empty), the UI must **prompt the user to select a category from the source project**, persist it onto the item, then proceed with the canonical sale (`project_to_business`).

Explicitly allowed:
- “Move to Design Business” (correction path) remains a separate action. It is still blocked when the item is transaction-attached (same parity behavior).

Evidence / deltas:

- **Intentional delta** vs current web: current UI allows these actions without `inheritedBudgetCategoryId` gating because the field doesn’t exist (`src/components/items/ItemActionsMenu.tsx`, `src/pages/ItemDetail.tsx`, `src/pages/InventoryList.tsx`).

---

## F) Item form validation + shared media (required)

- **F1 (validation)**: An item can be created/updated only if **at least one** of the following is present:
  - `description` (non-empty)
  - `sku` (non-empty)
  - one or more image attachments
- **F2 (error messaging)**: If all three are missing, block submission and show inline error text.
- **F3 (shared media components)**: Image pickers/preview must use shared attachment utilities/components; do not implement one-off image logic per screen.

---

## D) BI → Project prompt (destination project budget category)

### D1 — Conditional prompt requirement

When allocating/selling from Business Inventory to a Project, prompt the user to choose a destination **project budget category** only when needed:
- If `item.inheritedBudgetCategoryId` is enabled/available in the destination project, do not prompt.
- Otherwise, require selection.

### D2 — Defaulting rules
- If the item has a valid category for the destination project, preselect it.
- Otherwise, show no default and require an explicit selection.

### D3 — Batch rule (fast path)

If the operation is applied to a batch of items, one selected category applies to the whole batch.

### D4 — Persistence requirement

On success, persist the choice back onto the item(s):

- `item.inheritedBudgetCategoryId = <chosenDestinationCategoryId>`

Evidence / deltas:

- **Intentional delta** vs current web: current “sell/move to project” dialogs prompt only for project selection, no category prompt (`src/pages/ItemDetail.tsx`, `src/pages/InventoryList.tsx`).

---

## E) Rollup logic update (required; no new UI)

- **E1**: Budget rollups must treat canonical inventory sale transactions as category-coded and direction-coded:
  - Non-canonical: attribute by `transaction.budgetCategoryId`
  - Canonical inventory sale: attribute by `transaction.budgetCategoryId` and apply sign based on direction
- **E2**: Canonical inventory sale transactions are split per category by invariant; rollups must not require “group canonical items by item category id.”

Parity evidence (intentional change):

- Current web rollups use transaction category fields and a negative multiplier for `INV_SALE_*` (`src/components/ui/BudgetProgress.tsx`).

