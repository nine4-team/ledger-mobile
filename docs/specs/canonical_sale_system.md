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

