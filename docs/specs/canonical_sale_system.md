# Canonical Sale System (Project ↔ Business) — Spec

## Purpose

Capture the **canonical sale system** as a single source of truth: the **logical flow**, the **components involved**, and **testable requirements**.

This spec is written to be implementation-friendly (clear inputs/outputs, invariants, and acceptance criteria hooks) while staying UI/UX aware (what the user sees and why).

## Scope

- **In scope**
  - Canonical sale **directions**, **entry points**, and **flows**
  - Canonical “system sale transactions” that are **split by budget category** (category-coded)
  - Category prompting + persistence rules for items
  - Deterministic identity rules for canonical system transactions
  - Requirements for rollups (budget progress, reporting) to treat canonical txs consistently
- **Out of scope**
  - Exact UI styling, copywriting, animations
  - Data migration strategy and backfill details (unless required to enforce invariants)
  - Permission/role rules outside of “must block unauthorized actions”

## Definitions / glossary

- **Business Inventory**: the global inventory context (not tied to a single project).
- **Project Inventory**: a project-scoped set of items.
- **Canonical directions (only two)**
  - `project_to_business`
  - `business_to_project`
- **Project → Project**: *not* a canonical direction; it is always represented as **two hops**:
  - Hop 1: `project_to_business`
  - Hop 2: `business_to_project`
- **Canonical system sale transaction**: a system-maintained transaction representing a sale “bucket” used for rollups and lineage.
  - These are **read-only** in the UI.
  - These are **category-coded** and **split by category** (one category per canonical transaction).
- **Item budget category field**: the persisted category on an item (`budgetCategoryId`). In this spec it means:
  - "This item's current budget category (persisted), possibly set via prompting."

## Canonical model (high-level)

### Core decisions

- **Only canonical directions**: `project_to_business` and `business_to_project`.
- **One category per canonical system sale transaction** (category-split model).
- **Sell as the entry point**: a context-aware **Sell** menu.
- **Category resolution happens before writing**: if a required category is missing or incompatible, prompt, persist to item, then proceed.

### Master flow chart (canonical mental model)

```mermaid
flowchart TD
  itemInProject[Item (in Project)] --> sellMenuProject[Sell menu (Project context)]
  itemInInventory[Item (in Business Inventory)] --> sellMenuInventory[Sell menu (Business Inventory context)]

  sellMenuProject --> sellToBusiness[Sell to Business]
  sellMenuProject --> sellToProject[Sell to Project]
  sellMenuInventory --> sellToProjectFromInventory[Sell to Project]

  sellToBusiness --> ensureSourceCategory[Ensure source category on item]
  ensureSourceCategory --> canonSaleTxSource[Canonical system sale tx: Project→Business (by category)]

  sellToProject --> hop1[Hop 1: Project→Business]
  hop1 --> hop2[Hop 2: Business→Project]
  hop2 --> ensureDestCategory[Ensure destination category allowed in target project]
  ensureDestCategory --> canonSaleTxDest[Canonical system sale tx: Business→Project (by category)]

  sellToProjectFromInventory --> ensureDestCategory
```

## User-facing entry points (UI requirements)

### Sell menu (single conceptual entry point)

- **In Business Inventory context**
  - Must show: **Sell to Project**
  - Must not show: **Sell to Business** (already in business)
- **In Project context**
  - Must show: **Sell to Business**
  - Must show: **Sell to Project** (two-hop)

### Guardrails

- If an item is in a state where selling is disallowed (e.g. locked, permission denied, transaction-attached constraints), the Sell action must be **hidden or disabled** with a clear reason.

## Bulk sale operations

### Scope

Bulk sale operations allow the user to select multiple items and apply a canonical sale flow to all of them in one action. Bulk operations follow the same logical flows (A, B, C) as single-item operations — they do not introduce new canonical directions or shortcuts.

### Entry points

Bulk sale actions appear in the **bulk actions sheet** (opened from the bulk selection bar). The available actions are context-dependent, mirroring the single-item sell menu:

- **In Project context**: "Sell to Business", "Sell to Project"
- **In Business Inventory context**: "Sell to Project"

### UI flow pattern

Every bulk sale action follows a **two-step modal pattern**:

1. **Step 1 — Action button**: User taps the action label in the bulk actions sheet. The bulk actions sheet closes.
2. **Step 2 — Destination/config modal**: A secondary bottom sheet opens with the required selectors for that flow. The modal title includes the count (e.g., "Sell 5 item(s) to Business"). The modal has Cancel and a confirmation button. Confirmation button is disabled until all required fields are resolved.

No bulk sale action should have inline inputs (text fields, pickers) directly in the bulk actions sheet.

### Bulk Flow A: Sell to Business (Project → Business)

**Trigger**: Bulk actions sheet → "Sell to Business" (project scope only)

**Modal contents**:
- Category picker (list of source project's enabled categories)
- Label: "Category for uncategorized items"
- Only shown when at least one selected item has no `budgetCategoryId`
- If all selected items already have categories, skip the picker — show a confirmation-only modal
- Confirm button: "Sell to Business"

**Category resolution (batch rule)**:
- Items that already have a `budgetCategoryId` → use their existing category
- Items missing a category → use the category selected in the picker
- The selected category is **persisted onto each uncategorized item** before the sale write (same as single-item rule)

**Writes**:
- One request doc per item, each following Flow A's single-item write contract
- Fire-and-forget, offline-safe

### Bulk Flow B: Sell to Project (Business → Project)

**Trigger**: Bulk actions sheet → "Sell to Project" (business inventory scope)

**Modal contents**:
- Project picker (list of account's projects, excluding current context if applicable)
- Category picker (list of **target project's** enabled categories)
  - Only shown after a project is selected
  - Only required when at least one selected item's category is missing or not allowed in the target project
  - If all items have valid categories for the target, skip the category picker
- Confirm button: "Sell to Project"

**Category resolution (batch rule)**:
- Items whose `budgetCategoryId` is valid in the target project → use their existing category
- Items whose category is missing or not allowed → use the category selected in the picker
- The selected category is **persisted onto each affected item** before the sale write

**Writes**:
- One request doc per item, each following Flow B's single-item write contract
- Fire-and-forget, offline-safe

### Bulk Flow C: Sell to Project (Project → Project, two-hop)

**Trigger**: Bulk actions sheet → "Sell to Project" (project scope)

**Modal contents**:
- Project picker (list of account's projects, excluding current project)
- Source category picker (source project's enabled categories)
  - Only required when at least one selected item has no `budgetCategoryId`
- Destination category picker (target project's enabled categories)
  - Only shown after a target project is selected
  - Only required when at least one item's category is missing or not allowed in the target
- Confirm button: "Sell to Project"

**Category resolution (batch rule)**:
- Hop 1 (source): items with a category use it; uncategorized items use the source picker selection (persisted)
- Hop 2 (destination): items whose category is valid in target use it; others use the destination picker selection (persisted)

**Writes**:
- One request doc per item, each following Flow C's single-item write contract
- Fire-and-forget, offline-safe

### Shared requirements

- **No text inputs for IDs**: All entity selection (projects, categories, spaces) must use proper picker/selector components, never raw text fields.
- **Confirmation before execution**: Every bulk sale action requires an explicit confirm tap in the secondary modal.
- **Selection cleared on confirm**: After the user confirms, selection is cleared and the modal closes.
- **Error display**: If the batch produces validation errors (e.g., zero valid items), show an inline error in the modal — do not silently no-op.
- **Offline-first**: All writes are fire-and-forget with `.catch()`. No spinners gating on server acknowledgment.

### Acceptance criteria (bulk-specific)

- Bulk "Sell to Business" opens a modal with category picker (when needed); does not use inline inputs.
- Bulk "Sell to Project" opens a modal with project picker + category picker (when needed); does not use inline inputs.
- Category resolution applies per-item: items with existing valid categories are not overwritten.
- Each item produces its own request doc (no batch request doc).
- All bulk sale actions are context-gated (project scope vs business inventory scope).
- Code uses "Sell to Project" terminology, not "Allocate to Project."

### Component notes (implementation guidance)

- `SpaceSelector` already exists and should be used for space selection.
- A `ProjectSelector` component will need to be created (or extracted) for project selection in bulk flows B and C.
- Category selection should use `BottomSheetMenuList` (already used for single-item category resolution in the sell-to-business flow).

### Testing guidance (for implementation time)

Tests for bulk sale operations should cover three layers:

**1. Modal gating logic (unit)**
- Action button opens the correct secondary modal (not inline inputs)
- Modal shows/hides category picker based on whether any selected items lack a valid category
- Confirm button is disabled until all required fields are resolved
- Context gating: "Sell to Business" only appears in project scope; "Sell to Project" only in business inventory scope (for Flow B) or project scope (for Flow C)

**2. Category resolution (unit)**
- Items with existing valid `budgetCategoryId` are not overwritten by the picker selection
- Items missing a category receive the picker selection
- Items whose category is invalid in the target project receive the picker selection (Flows B, C)
- Mixed batch: some items keep their category, some get the picker value — verify per-item

**3. Write contract (integration)**
- Each selected item produces exactly one request doc (no batch doc, no missing items)
- Request docs contain the correct resolved `sourceCategoryId` / `destinationCategoryId` per item
- Writes are fire-and-forget (no awaited promises blocking UI)
- Selection is cleared and modal closes after confirm

**What NOT to test here:**
- Server-side request doc processing (canonical tx creation, lineage) — that's the request doc handler's responsibility
- Exact picker UI rendering — that's `BottomSheetMenuList` / `ProjectSelector`'s own test surface
- Offline queue behavior — that's `trackPendingWrite`'s responsibility

### Implementation notes (current state → target state)

This section documents what exists today and what needs to change. Read this before touching code.

#### What to remove from `SharedItemsList.tsx`

The standalone bulk actions sheet (rendered when `!embedded`) currently has inline inputs and hardcoded handlers. These must be replaced with the same `BulkAction` array pattern used by embedded mode.

**State to remove** (lines 222–228 as of this writing):
- `bulkSpaceId` — raw text input for space ID
- `bulkProjectId` — raw text input for project ID
- `bulkCategoryId` — raw text input for category ID
- `bulkSourceCategoryId` — inline category picker state
- `sourceCategoryMenuOpen` — menu visibility for inline picker
- `budgetCategories` — only used to populate the inline picker

**Handlers to remove:**
- `handleBulkMoveToSpace` — uses `bulkSpaceId` text input
- `handleBulkAllocateToProject` — uses `bulkProjectId`/`bulkCategoryId` text inputs
- `handleBulkSellToBusiness` — uses inline `bulkSourceCategoryId` picker
- `sourceCategoryMenuItems` — menu items for the inline picker

**UI to remove:**
- The entire standalone `<>...</>` block inside the bulk actions sheet (the `TextInput` fields, inline pickers, and their associated buttons)
- The `<BottomSheetMenuList>` for `sourceCategoryMenuOpen`

#### What to replace it with

Standalone mode should build a `BulkAction[]` array (context-gated by `scopeConfig`) and render it through the same path embedded mode uses. Each action's `onPress` opens a secondary modal — no inline inputs in the bulk sheet.

**Correct pattern** (already working in `SpaceDetailContent.tsx` and `app/transactions/[id]/index.tsx`):
1. Define a `BulkAction[]` array where each `onPress(selectedIds)` sets state to open a secondary bottom sheet
2. Render the array as a list of labeled buttons in the bulk actions sheet
3. Each secondary sheet contains the appropriate picker(s) + Cancel/Confirm buttons
4. On confirm: call the service function, clear selection, close sheet

#### Existing service functions (in `src/data/inventoryOperations.ts`)

All three service functions already exist. No new service functions are needed.

| Function | Operation type | Spec flow | Currently used in standalone bulk? |
|----------|---------------|-----------|-----------------------------------|
| `requestProjectToBusinessSale(params)` | `ITEM_SALE_PROJECT_TO_BUSINESS` | Flow A | Yes (with inline picker) |
| `requestBusinessToProjectPurchase(params)` | `ITEM_SALE_BUSINESS_TO_PROJECT` | Flow B | Yes (with text inputs) |
| `requestProjectToProjectMove(params)` | `ITEM_SALE_PROJECT_TO_PROJECT` | Flow C | **No** (not wired to any UI) |

**Signatures:**
- Flow A: `{ accountId, projectId, items, budgetCategoryId? (fallback for uncategorized), opId? }` → `string[]`
- Flow B: `{ accountId, targetProjectId, budgetCategoryId (required), items, opId? }` → `string[]`
- Flow C: `{ accountId, sourceProjectId, targetProjectId, sourceBudgetCategoryId?, destinationBudgetCategoryId (required), items, opId? }` → `string[]`

#### `scopeConfig` contract (`src/data/scopeConfig.ts`)

```typescript
type ScopeConfig = {
  scope: 'project' | 'inventory';
  projectId?: string;
  capabilities?: {
    canExportCsv?: boolean;
    supportsInventoryOnlyStatusFilter?: boolean;
    canAllocateToProject?: boolean;  // ← rename to align with spec terminology
  };
  fields?: {
    showBusinessInventoryLocation?: boolean;
  };
};
```

**Rename needed:** `canAllocateToProject` → `canSellToProject` to match the canonical sale spec terminology. This flag is `true` for inventory scope, `false` for project scope. After rename, the gating logic is:
- `scope === 'project'` → show "Sell to Business" and "Sell to Project" (Flow C, two-hop)
- `scope === 'inventory'` + `canSellToProject` → show "Sell to Project" (Flow B)

#### Components that need to be created

- **`ProjectSelector`**: A picker component for selecting a project. Analogous to `SpaceSelector`. Takes `accountId`, `value`, `onChange`, and optionally `excludeProjectId` (to exclude the current project in Flow C). Renders as a list of the account's projects in a bottom sheet or inline picker.

## Logical flows (step-by-step)

Each flow section below specifies:
- **Inputs**
- **Required prompts / resolution**
- **Writes**
- **Outputs / invariants**

### Flow A: Sell to Business (Project → Business)

**Inputs**
- `sourceProjectId`
- `itemId`

**Category resolution**
- If the item has no category:
  - Prompt the user to choose a category **from the source project’s enabled categories**
  - Persist the chosen category onto the item
- Else:
  - Use the item’s current category as the source category

**Writes**
- Write a request doc representing `ITEM_SALE_PROJECT_TO_BUSINESS` with:
  - `sourceProjectId`, `itemId`, `sourceCategoryId` (resolved)
- Ensure the move is represented as a `project_to_business` sale operation (lineage + inventory location update).
- Link the operation to the correct **canonical system sale transaction** (see “Canonical transaction identity”).

**Outputs / invariants**
- The item ends in Business Inventory.
- The operation is traceable in lineage.
- Exactly one canonical system sale transaction is affected for this direction+project+category.

### Flow B: Sell to Project (Business → Project)

**Inputs**
- `targetProjectId`
- `itemId`

**Category resolution**
- If the item’s category is not present/allowed in the target project:
  - Prompt the user to choose a category **from the target project’s enabled categories**
  - Persist the chosen category onto the item
- Else:
  - Use the item’s current category as the destination category

**Writes**
- Write a request doc representing `ITEM_SALE_BUSINESS_TO_PROJECT` with:
  - `targetProjectId`, `itemId`, `destinationCategoryId` (resolved)
- Ensure the move is represented as a `business_to_project` sale operation.
- Link the operation to the correct canonical system sale transaction.

**Outputs / invariants**
- The item ends in the target project.
- The item’s persisted category is valid for the target project.

### Flow C: Sell to Project (Project → Project as two hops)

**Inputs**
- `sourceProjectId`
- `targetProjectId`
- `itemId`

**Category resolution rules**
- Hop 1 (Project → Business):
  - Uses the item’s **source category**
  - If missing: prompt from **source project** categories; persist to item; proceed
- Hop 2 (Business → Project):
  - Requires the item category to be allowed in the **target project**
  - If not allowed: prompt from **target project** categories; persist to item; proceed

**Writes**
- Write a request doc representing `ITEM_SALE_PROJECT_TO_PROJECT` with:
  - `sourceProjectId`, `targetProjectId`, `itemId`
  - `sourceCategoryId` (resolved) and `destinationCategoryId` (resolved)
- Internally represent as two canonical-direction operations (Hop 1 then Hop 2), each linking to its direction-specific canonical system sale transaction.

**Outputs / invariants**
- Item ends in the target project.
- Item ends with a category valid in the target project.
- Lineage indicates the two-hop sale path without introducing a third “project_to_project” canonical direction.

## Canonical system sale transactions

### Why they exist

Canonical system sale transactions exist to:
- Provide stable **rollup anchors** for budget progress/reporting
- Provide stable **link targets** for item-level sale operations and lineage
- Reduce ambiguous “where does this sale count” logic

### Key rules

- Canonical system sale transactions are **system-created and system-owned**
  - They must be **read-only** in the UI (no edits, no delete)
- Canonical system sale transactions are **category-coded**
  - Each canonical transaction has exactly one `budgetCategoryId`
- Canonical system sale transactions are **direction-coded**
  - Each canonical transaction is for exactly one direction: `project_to_business` or `business_to_project`
- Cardinality constraint
  - At most `2 × (# enabled budget categories in the project)` canonical sale transactions per project

### Canonical transaction identity (deterministic)

Each canonical system sale transaction must be uniquely identified by these inputs:
- `projectId`
- `direction` (`project_to_business` | `business_to_project`)
- `budgetCategoryId`

Implementation may choose the exact string format, but it must be deterministic.

Example (illustrative; current naming convention):
- `SALE_<projectId>_<direction>_<budgetCategoryId>`

Note:
- This assumes `projectId` and `budgetCategoryId` contain no underscores so the id can be safely split if needed (see `20_data/data_contracts.md`). App logic should still prefer explicit fields (`isCanonicalInventorySale`, `inventorySaleDirection`, `budgetCategoryId`) over parsing ids.

### Amount computation

- The canonical transaction `amountCents` is **system-computed** from linked items/operations (per the system’s existing rules).
- Because canonical txs are single-category, rollups do not need “group items by item.category” tricks to attribute canonical amounts.

### Drift prevention + repair (offline-first)

Because the app is offline-first and multiple clients can act concurrently:

- Clients MUST treat canonical system sale transactions as **read-only** (including `amountCents`).
- The server MUST recompute and persist canonical `amountCents` as part of applying sale operations (request-doc handler transaction).

Safety net (recommended):

- Add a server-owned **repair job** (scheduled and/or on-demand) that recomputes canonical sale totals and corrects drift, with logging.
- If the client detects a mismatch (computed-from-items vs stored), it MAY show a “may be updating” indicator, but MUST NOT write a self-heal patch.

## Components and responsibilities

This section is intentionally “component-shaped” so it can map to modules/services and UI screens.

### UI components

- **Sell menu**
  - Picks the flow based on current context (Project vs Business Inventory)
  - Collects required target (for “Sell to Project”)
- **Category resolver prompt**
  - Determines whether prompting is needed
  - Presents a category list appropriate to the step:
    - Source project categories (for Project → Business missing category)
    - Target project categories (for Business → Project mismatch)
  - Persists the selection to the item before continuing

### Domain / service components (conceptual)

- **Inventory operation runner**
  - Executes the sale operation
  - Ensures idempotency (retries/offline) and correct linking
- **Canonical transaction resolver**
  - Given (projectId, direction, budgetCategoryId), finds/creates the canonical system sale transaction
  - Enforces “one per triple” invariant
- **Lineage writer**
  - Records the correct edges/pointers for sale moves
- **Budget/report rollup**
  - Computes budget progress directly from transactions by `budgetCategoryId`
  - Includes canonical system sale transactions as category-coded rows

### Data contracts (conceptual fields)

- **Item**
  - `id`
  - `currentLocation` (projectId or business)
  - `budgetCategoryId` (persisted budget category for this item)
- **Transaction**
  - `id`
  - `budgetCategoryId` (required for canonical sale txs)
  - `direction` or “type/sign” representation (must be unambiguous)
  - `isCanonicalSystem` (or equivalent marker)
- **RequestDoc (sale)**
  - Must contain enough info to resolve canonical tx and apply the operation:
    - `sourceProjectId` / `targetProjectId`
    - `itemId`
    - Resolved category ids (`sourceCategoryId` and/or `destinationCategoryId` as appropriate)

## Feature requirements (testable)

### Direction + flow requirements

- **MUST** support only two canonical directions: `project_to_business`, `business_to_project`.
- **MUST** represent project→project as two hops, never as a third direction.
- **MUST** expose Sell actions via a single Sell entry point with context-appropriate options.

### Category prompting + persistence

- **MUST** prompt and persist a source category when selling Project → Business and the item has no category.
- **MUST** prompt and persist a destination category when selling Business → Project and the item’s category is not allowed in the target project.
- **MUST** never proceed to write a sale operation without the required category having been resolved.

### Canonical transaction invariants

- **MUST** have exactly one canonical system sale transaction per \((projectId, direction, budgetCategoryId)\).
- **MUST** mark canonical system sale transactions as read-only in UI and API.
- **MUST** store `budgetCategoryId` directly on canonical system sale transactions.

### Rollups / reporting

- **MUST** compute budget progress using transaction rows by `budgetCategoryId`, including canonical system sale transactions.
- **MUST NOT** require joining sale-linked items to attribute canonical rows to categories (the category is on the transaction).

### Offline / idempotency (minimum bar)

- **MUST** be safe under retries (same request doc applied multiple times does not double-count or duplicate canonical txs).
- **SHOULD** allow the user to continue after transient failures (clear errors and retry path).

## Acceptance criteria (ready-to-copy checklist)

- **Sell menu**
  - In Business Inventory, user can only “Sell to Project”.
  - In Project, user can “Sell to Business” and “Sell to Project”.
- **Project → Business**
  - If item has no category, user is prompted with source project categories; selection is persisted; sale completes.
  - Sale links to canonical tx for (sourceProjectId, project_to_business, sourceCategoryId).
- **Business → Project**
  - If item category is invalid for target, user is prompted with target project categories; selection persisted; sale completes.
  - Sale links to canonical tx for (targetProjectId, business_to_project, destinationCategoryId).
- **Project → Project**
  - Flow executes as two hops with correct prompts and final category validity in the target project.
- **Canonical txs**
  - Canonical tx rows are category-coded, direction-specific, and read-only.
  - No duplicates exist for the same (projectId, direction, budgetCategoryId).

## References (source material)

- Plan that introduced the flow chart + model revision:
  - `.cursor/plans/allocation-sale-spec-revision_2aa7de45.plan.md`
- Related feature specs where this should be reflected:
  - `.cursor/plans/firebase-mobile-migration/40_features/inventory-operations-and-lineage/*`
  - `.cursor/plans/firebase-mobile-migration/40_features/project-items/*`
  - `.cursor/plans/firebase-mobile-migration/40_features/project-transactions/*`
  - `.cursor/plans/firebase-mobile-migration/40_features/budget-and-accounting/*`

## Open questions (fill in as we learn)

- Where should “direction” live on transactions (explicit `direction` field vs type/sign encoding)?
- What is the canonical behavior when a project has zero enabled categories?
- Should category prompting be skippable (cancel) and if so, what state does the UI return to?

