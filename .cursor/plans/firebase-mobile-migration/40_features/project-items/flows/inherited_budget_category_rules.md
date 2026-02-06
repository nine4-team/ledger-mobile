# Flow: item budget category id rules (`inheritedBudgetCategoryId`) — prompts + canonical sale semantics

This doc is the shared source for Project Items and Business Inventory specs.

Goal: make it unambiguous:
- where the item’s budget category id comes from
- when it changes
- what happens when it’s missing (and how the UI resolves it)

> Naming note: the field is currently named `item.inheritedBudgetCategoryId` in the migration data contracts.
> In this revised model it is **item-owned** (not strictly “inherited”). A later rename to `item.budgetCategoryId` is recommended but out of scope for this spec pack.

---

## Definitions

- **User-facing (non-canonical) transaction**: a normal transaction whose budget category is set by the user (`transaction.budgetCategoryId`).
- **Canonical inventory sale transaction (system)**: a system-generated **sale** transaction that represents cross-scope movement, and is:
  - **direction-coded**: `business_to_project` or `project_to_business`
  - **category-coded**: exactly one `transaction.budgetCategoryId`
  - **deterministic**: `canonicalSaleTransactionId(projectId, direction, budgetCategoryId)` (recommended id prefix `INV_SALE__`)
- Note: “project → project” movement is modeled as **two hops**:
  - Project A → Business Inventory (`project_to_business`)
  - then Business Inventory → Project B (`business_to_project`)

Source of truth working doc:
- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`

---

## 1) Attribution rules (non-canonical vs canonical)

### 1.1 Non-canonical attribution (transaction-driven)
- Category attribution comes from `transaction.budgetCategoryId`.

### 1.2 Canonical inventory sale attribution (transaction-driven)
- Canonical inventory sale transactions are **category-coded**, so attribution comes from `transaction.budgetCategoryId` (not from grouping items).
- Budget rollups apply sign rules based on direction:
  - `business_to_project`: adds to spend
  - `project_to_business`: subtracts from spend

---

## 2) The item field: `inheritedBudgetCategoryId` (semantics + write rules)

### 2.1 Required storage
Every item persists a stable `inheritedBudgetCategoryId` field (nullable but present).

### 2.2 How it is set (inherit vs direct assignment)

**A) On link to a non-canonical transaction** (inherit):
- If a non-canonical transaction has `budgetCategoryId`, set:
  - `item.inheritedBudgetCategoryId = transaction.budgetCategoryId`

**B) On canonical inventory sale operations** (direct assignment when needed):
- Canonical sale operations may need to set or change the item’s category so the correct canonical sale transaction is used.
- When a prompt is shown (see below), persist the chosen category onto the item as:
  - `item.inheritedBudgetCategoryId = <chosenCategoryId>`

### 2.3 When it changes

- **Business Inventory → Project**:
  - If `item.inheritedBudgetCategoryId` is enabled/available in the destination project, keep it.
  - Otherwise prompt for a destination project category and persist it onto the item.
- **Project → Business Inventory**:
  - If `item.inheritedBudgetCategoryId` is missing, prompt for a source project category and persist it onto the item.
  - Otherwise keep it.

### 2.4 What breaks if missing

If the item’s category is missing, the system cannot select the correct canonical sale transaction id (canonical rows are split by category).
Therefore, the UI must **prompt + persist** before the canonical sale is applied (rather than blocking the operation outright).

---

## 3) UI rules (required)

### 3.1 Project → Business Inventory (Sell to Business)

If `item.inheritedBudgetCategoryId` is missing:
- Prompt the user to select a category from the **source project’s enabled categories**.
- Persist it to `item.inheritedBudgetCategoryId`.
- Then apply the canonical sale (`project_to_business`) to the matching category-coded canonical sale transaction.

Correction path clarification (parity-informed):
- “Move to Design Business” (correction) is a direct item scope update and does not create canonical inventory sale transactions.
  It remains blocked when the item is transaction-attached (same as current parity).

### 3.2 Business Inventory → Project (Sell to Project)

If `item.inheritedBudgetCategoryId` is missing **or** not enabled/available in the destination project:
- Prompt the user to select a category from the destination project.
- Persist it to `item.inheritedBudgetCategoryId`.
- Then apply the canonical sale (`business_to_project`) to the matching category-coded canonical sale transaction.

Defaulting:
- If the item already has a category id that is enabled/available in the destination project, do not prompt.

Batch:
- One selection applies to all items in the batch (fast path).

---

## 4) Migration/backfill (out of scope)

Any one-time migration/backfill logic for existing data is handled separately and is explicitly **out of scope** for this spec pack.

