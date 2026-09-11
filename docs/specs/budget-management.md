# Budget Management

> **Target-state notice (2026-08-30):** Project budget progress is no longer
> Transaction-only in the approved redesign. See
> [Invoice-Centered Project Accounting](invoice-centered-project-accounting.md).
> Each category combines client-paid and invoicing/unpaid source allocations;
> collection transfers an amount between those segments without changing the
> total, and the settlement Transaction cannot be counted a second time.
>
> Firestore paths, Cloud Function summaries, legacy sign tables, per-batch
> movement Transactions and source Item-category rules below are migration
> evidence, not instructions for the Supabase implementation. D-001/D-007–D-013
> and D-017 govern target accounting. Shared category mutations remain gated by
> O-026, Project allocation permissions by O-052, and personal pin behavior by
> O-040. No new Firebase implementation is required.

## Overview

Budget management lets users define Account-wide categories, allocate Project
budgets and track progress. Every target budget contribution must resolve its
category and provenance; this does not require one category on every Transaction
header. A collected Invoice payment uses frozen content allocations, and
Business Inventory records do not acquire a Project category merely to satisfy
the old Transaction-header convention.

## Budget Categories

Preserve the settings controls: separate active/archived lists, Add/Edit,
name/type/exclusion fields, behavior explanation, Save/Cancel, archive
confirmation, restore and drag reorder. Target mutations have visible durable
outcomes and shared authorization; silent independent source writes are not
successful target behavior. Protected rows and dependency rules remain O-026.

### Definition

Budget categories are account-level presets that define spending groupings. They live at `accounts/{accountId}/presets/default/budgetCategories/{budgetCategoryId}`.

### Category Types

Three mutually exclusive types controlled by `metadata.categoryType`:

| Type | Purpose | Budget semantics | Example |
|------|---------|-----------------|---------|
| `general` | Standard spending | Higher % = more spent (warning) | "Install", "Storage & Receiving" |
| `itemized` | Spending with line-item tracking | Same as general, plus enables transaction audit | "Furnishings" |
| `fee` | Income/fees received | Higher % = more received (good) | "Design Fee" |

A category cannot be both `itemized` and `fee`. These are mutually exclusive.

### Category Fields

The field list describes source validation and UI semantics. Final shared
mutation rules remain under O-026; do not assume that a warning permits changing
the meaning of used history. O-056 governs the conflicting category-name
validation/uniqueness rules. Dependencies include open charges/credits,
Expenses, Fees, Invoice lines, frozen allocations and Transfers, not only
Transactions. Source name validators disagree on accepted characters; reconcile
that contract before claiming target create/rename completeness.

- `id` — unique identifier
- `accountId` — owning account
- `name` — display name (unique per account, case-insensitive, max 100 chars, allowed: letters, numbers, spaces, hyphens, ampersands)
- `slug` — URL-friendly identifier (reserved for future use)
- `isArchived` — soft delete flag (archived categories hidden from forms but data preserved). **Categories with existing transactions cannot be deleted — they must be archived instead.** If changing a category's type when it has existing transactions, warn the user (semantics change from "spent" to "received" or vice versa).
- `metadata.categoryType` — "general", "itemized", or "fee". Defaults to `"general"` if not specified.
- `metadata.excludeFromOverallBudget` — when true, this category's spend is excluded from overall budget totals. Defaults to `false` (included). Fee categories are not automatically excluded; each category's setting is explicit.

### Default Categories (Seeded on Account Creation)

1. **Furnishings** — type: itemized, excludeFromOverall: false
2. **Install** — type: general, excludeFromOverall: false
3. **Design Fee** — type: fee, excludeFromOverall: true
4. **Storage & Receiving** — type: general, excludeFromOverall: false

Furnishings is set as the account-wide default category for new transactions. Seeding is idempotent — check if categories already exist before creating to prevent duplicates.

### Account Presets

Defaults apply only where the owning target story permits category selection.
They cannot override Furnishings for Item charges/credits or the frozen category
allocations of a collected Invoice payment.

Lives at `accounts/{accountId}/presets/default`.

- `defaultBudgetCategoryId` — the category pre-selected in new transaction forms. Users can change this.
- `budgetCategoryOrder` — array of category IDs defining custom display order. When set, categories are sorted in this order instead of alphabetically.

## Per-Project Budget Allocation

### ProjectBudgetCategory

Lives at `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`.

The document ID matches the budget category ID (1:1 relationship).

**Semantics:**

- Document exists = category is enabled for this project
- `budgetCents: null` = enabled but no specific budget set
- `budgetCents: 0` = explicitly zero budget
- No document = category not enabled

**Fields:**

- `id` — matches budget category ID
- `budgetCents` — budget allocation in cents (non-negative or null, max 2,147,483,647 / ~$21.5M)

**Enabling additional categories:** User opens a category selection sheet showing all active account categories not yet enabled for this project. On confirm, create `ProjectBudgetCategory` documents with `budgetCents: null`.

**Disabling categories:** When saving the budget form, categories the user disabled have their `ProjectBudgetCategory` document deleted.

**Total Budget:** The overall project budget is the sum of all enabled category `budgetCents` (treating null as 0). This is read-only and updates live as individual category amounts change.

## Project Creation Flow

This section records the source form and source write sequence. Target setup
preserves the user controls but follows `projects.md`: one durable observable
Project/category/allocation result, with enabled-with-null distinct from
explicit zero. An empty budget input does not become zero. Media upload has its
separate durable lifecycle; the independent Firebase writes under On Create
are not a target implementation plan.

Project creation uses a 3-step form:

### Step 1: Basic Info

- Project name (required)
- Client name (required)
- Description (optional)
- Hero image (optional)

### Step 2: Category Selection

- Shows all active (non-archived) account-level budget categories
- All categories are pre-selected by default; user unchecks any they don't need
- Each row shows category name and type badge (Itemized / Fee) where applicable
- "Add Category" button opens a create form for a new budget category
- **On-the-fly category creation:** Creates the category at account level (`accounts/{accountId}/presets/default/budgetCategories`), making it available in Settings and all future projects. The new category is auto-selected for the current project.
- At least one category must be selected to proceed

### Step 3: Budget Amounts

- Shows only the categories selected in Step 2
- Currency input per category for budget allocation
- Budget amounts are optional (categories can be enabled with no budget set)

### On Create

1. Project document created at `accounts/{accountId}/projects/{projectId}`
2. For each selected category, a `ProjectBudgetCategory` document is created (using `setData(merge: true)`) with the entered `budgetCents` (0 if left empty)
3. Hero image uploaded in background if provided

## Budget Progress Calculation

**Target authority:** Each category's progress is client-paid plus
invoicing/unpaid, including open Item charges/credits, Expenses and Fees even
when not yet on an Invoice. Collection moves the frozen amounts between those
segments without changing the total; never also add the lump-sum payment.
Item charges/credits use Furnishings, with Additional Requests as a non-additive
overlay. Same-Client Transfer reallocates value between Projects and is
client-wide net zero. The Transaction-only formula below is source comparison
evidence; it is not the target calculation.

### Per-Category Spent

```
categorySpentCents = sum of (amountCents * multiplier) for all non-canceled transactions
                     where budgetCategoryId matches this category

transactionType values: "purchase", "return", "sale"
  (legacy data may use title case — comparisons should be case-insensitive)
inventorySaleDirection values: "business_to_project", "project_to_business" (LEGACY only)

multiplier rules (in order — first match wins):
  if transactionType is "return": -1
  if isCanonicalInventorySale AND inventorySaleDirection is "project_to_business": -1   # legacy carve-out
  if isCanonicalInventorySale AND inventorySaleDirection is "business_to_project": +1   # legacy carve-out
  if transactionType is "sale": -1                                                      # new project → inventory acquisition
  otherwise: +1                                                                          # purchases
```

See the "Sign Conventions" section below for the canonical reference.

### Per-Category Percentage

```
categoryPercentage = (categorySpentCents / categoryBudgetCents) * 100
```

### Overall Budget Spent

```
overallSpentCents = sum of categorySpentCents
                    for all categories where excludeFromOverallBudget is false
```

### Overall Budget Total

```
overallBudgetCents = sum of budgetCents
                     for all enabled categories where excludeFromOverallBudget is false
                     (treat null budgetCents as 0)
```

### Overall Percentage

```
overallPercentage = (overallSpentCents / overallBudgetCents) * 100
```

## Sign Conventions

The source Firebase system handles per-batch inventory movement transactions
plus legacy canonical sales. Its dual-read path lives in
[mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts)
`normalizeSpendAmount`. Use it to understand and reconcile source evidence,
not as target runtime authority. Target Purchase/Return record real owner cash
movement, Transfer is the sole non-cash Transaction exception, and Item
charge/credit provenance is separate.

### Sign convention for inventory movement transactions

- **Legacy canonical sales** (`isCanonicalInventorySale == true`): sign depends on `inventorySaleDirection`. `business_to_project` → +1. `project_to_business` → -1. These are historical documents only; no new code writes them.
- **Inventory → project purchases** (`type == "Purchase"`, inventory source, `budgetCategoryId` set): always +1.
- **Project → inventory sales** (`type == "Sale"`, no `isCanonicalInventorySale` flag): subtract from the transaction `budgetCategoryId`, which is the frozen source project accounting category.
- **Returns** (`type == "Return"`): always -1. Includes both vendor returns and return-to-inventory transactions.
- **Payment to business** (`type == "paymentToBusiness"`): always +1. In fee
  categories this is displayed as money received, not ordinary project cost.

### Full table

| Transaction Type | Multiplier | Effect on Budget |
|-----------------|------------|------------------|
| Purchase | +1 | Adds to spent |
| Return (vendor or inventory) | -1 | Subtracts from spent |
| Inventory → project Purchase (`type: "Purchase"`, inventory source) | +1 | Adds to spent |
| Project → inventory Sale (`type: "Sale"`, source category) | -1 | Subtracts from project spend |
| Payment to business (`type: "paymentToBusiness"`) | +1 | Adds to received for fee categories |
| **Legacy** canonical sale, `business_to_project` | +1 | Adds to spent |
| **Legacy** canonical sale, `project_to_business` | -1 | Subtracts from spent |
| Canceled transactions (`status == "canceled"`, any type) | excluded | No effect |

## Payment / Revenue Category Differences

The `paymentToBusiness` table below is source presentation, not target Fee
accounting. Target Fees are planned demand in Invoicing: unpaid before
collection and paid afterwards, with no increase in total from collection.
Do not label all Fee demand as money already received.

Categories used for `paymentToBusiness` rows represent money received rather
than project spend. They use inverted semantics where displayed as revenue:

| Aspect | Project cost | Payment / revenue |
|--------|-------------------|-----|
| Amount label | "$X spent" | "$X received" |
| Remaining label | "$X remaining" | "$X remaining to receive" |
| Color at 75%+ | Red (warning) | Green (good progress) |
| Color at 0-49% | Green (healthy) | Red (low progress) |
| Display name suffix | "Budget" (e.g., "Furnishings Budget") | None (e.g., "Design Fee") |
| Over-budget label | "$X over" | "$X over received" |
| Default overall inclusion | Included (field defaults to `false`) | Per-category (Design Fee seed sets `true`) |

## Color Thresholds

**Verified source behavior:** `BudgetTabView` calls
`BudgetTrackerCalculations.progressColor` for category and Overall rows, so the
graduated thresholds below already appear in the source. The “future” heading
names are historical. They do not choose the target's separate paid/unpaid
segment colors or negative-credit presentation under O-005.

### Standard/Itemized Categories (future)

- 0-49% spent: Green (healthy)
- 50-74% spent: Yellow (warning)
- 75-99% spent: Red (critical)
- 100%+ spent: Red with overflow indicator

### Fee Categories (Inverted, future)

- 75%+ received: Green (good)
- 50-74% received: Yellow (partial)
- 0-49% received: Red (low)

## Project Card Budget Preview

This source-spec fallback differs from current UI behavior (pinned → Furnishings
→ Overall). O-040 owns the target choice; neither fallback is implicitly
approved for the redesign.

Project list cards show a budget preview with this fallback chain:

1. Pinned categories (if any exist)
2. Top 1-2 categories by highest spend percentage (if no pins)
3. Overall Budget (if no categories have budget activity)

Amounts only — no percentage displayed on the card.

## Denormalized Budget Summary

This section describes the source Firebase summary and recalculation triggers.
Retain it for migration comparison; do not build these Functions for the target
or treat the source summary as proof of target paid/unpaid completeness.

Each project document has a denormalized `budgetSummary` field maintained by Cloud Function triggers (Tier 4 — see write-tiers.md). This enables project list views to show budget progress without additional queries.

### What Triggers Recalculation

- Transaction created, updated, or deleted — recalculate affected project
- Project budget category created, updated, or deleted — recalculate the project
- Account budget category name, type, archive status, or excludeFromOverall changed — recalculate all projects in account

### Summary Fields

- `spentCents` — overall spent (excluding excludeFromOverall categories)
- `totalBudgetCents` — overall budget (excluding excludeFromOverall categories)
- `categories` — map of category ID to { budgetCents, spentCents, name, categoryType, excludeFromOverallBudget, isArchived }
- `updatedAt` — server timestamp of last recalculation

### Invariant

Recalculation is always full and idempotent — it reads ALL transactions and budget categories for the project and recomputes everything from scratch. This prevents drift between incremental updates.

## User Preferences: Pinning

Users can pin budget categories to customize their view. Pins are per-user, per-project.

**Storage:** `accounts/{accountId}/users/{userId}/projectPreferences/{projectId}` with a `pinnedBudgetCategoryIds` array.

**Display order:**

This source-spec order conflicts with the actual Overall pin control and
personal preview behavior. O-040 decides target Overall eligibility, missing
versus empty preferences, automatic Furnishings and stale-reference handling.
Retain both evidence sets rather than treating this list as approved policy.

1. Pinned categories (in user-defined order)
2. Non-pinned standard/itemized categories (custom order or alphabetical)
3. Overall Budget (cannot be pinned — always shown here)
4. Fee categories (always last)

**First-time behavior:** When a user first views a project, Furnishings is pinned by default (if enabled and has non-zero budget).

**Cleanup rules:**
- If a pinned category is **deleted**: remove its ID from `pinnedBudgetCategoryIds` (clean up stale references).
- If a pinned category is **archived**: keep its ID in the array (user intent preserved; restored if unarchived).

## Transaction Budget Attribution

The movement-Transaction rules below are source-era behavior. Target Item
charges/credits use Furnishings and frozen collected category allocations;
direct client-paid records, Expenses and Fees follow their canonical accounting
stories. Moving an Item must not manufacture a cash Transaction or duplicate
budget contribution.

- **Purchase / Return transactions**: Category selected by user via form picker, which only shows categories enabled for the current project (those with a `ProjectBudgetCategory` document). Pre-filled from account default if that category is enabled.
- **Per-batch inventory purchases** (new model): Category collected from the user at movement time and applied to every item in the batch. The picker contains only active, non-system, itemized categories already enabled in the destination project. One category per Purchase transaction; no per-item category. Amounts use normalized `projectPriceCents`, which is automatically raised to at least `purchasePriceCents`; the UI collects a price only when neither is positive. See [sale-transactions.md](sale-transactions.md).
- **Uncollected Purchase-from-Inventory correction:** The entire Purchase may be reclassified to another project-enabled itemized category through the dedicated trusted operation. The transaction and its currently attached items change atomically; departed item placement and downstream movement transactions do not. The normal operation is blocked after an affected invoice source is collected.
- **Project → inventory exits**: Inventory-originated Returns subtract normalized `projectPriceCents`; project-originated Sale-to-Inventory acquisitions subtract `purchasePriceCents`. Project → project uses that origin-aware rule for the source exit and project price for the destination Purchase.
- **Legacy canonical sales**: Category was derived from the item's `budgetCategoryId` at the time of writing. Historical reads only.

## Item Budget Category Attribution

The following field-level rules document source behavior, not target accounting
authority. One target Item identity may have multiple charge/credit cycles with
their own category snapshots; current placement must not rewrite paid history.
An Unaccounted For Item can already have a Project/category without contributing
spend. Preserve or quarantine source category evidence during migration; the
source's “no backfill” policy does not waive target reconciliation.

Items have a `budgetCategoryId` that follows this invariant:

**`(item.projectId == null) ↔ (item.budgetCategoryId == null)`**

Items in business inventory have no category. Items in a project have a category. This invariant is enforced on every write by both clients (iOS and MCP) and is the core change from the legacy "categories persist across scope moves" model.

**Setting rules:**

1. **When creating an item with `projectId == null`** (in business inventory): `budgetCategoryId` is forced to null. Any value passed by the caller is ignored or rejected.
2. **When creating an item linked to a project transaction**: `item.budgetCategoryId = transaction.budgetCategoryId`.
3. **When purchasing from inventory into a project**: the user picks a category for the whole batch, which is set on every item AND on the new Purchase transaction. Each project price is normalized to at least purchase cost; the user sets a sale price only if neither price is positive.
4. **When returning from a project to inventory**: `item.budgetCategoryId` is wiped to null.
5. **When reassigning within the same project**: `item.budgetCategoryId` may be updated to match the new transaction's category, but the projectId does not change.
6. **When reclassifying an uncollected Purchase from Inventory**: the target must be an active, non-system, project-enabled itemized category. The Purchase and all currently attached items move to that category atomically. This is a whole-transaction correction; it never changes only a selected subset of the Purchase.

**Project-enabled selection:** Inventory sale and Purchase reclassification pickers do not offer account categories that are not already enabled in the destination project. These paths never silently auto-enable a category. Any separate transaction/project reassignment flow that intentionally supports auto-enabling remains responsible for making that behavior explicit before the move.

**Why the invariant matters:** Categories belong to projects. An item sitting in inventory has no project, so it has no category. Re-resolving the category at sell time makes the relationship explicit and eliminates a class of drift bugs that came from items carrying stale categories across scope moves. See [inventory-as-store.md](inventory-as-store.md) for the full rationale.

**Existing inventory items with stale categories.** Items currently in inventory that have a non-null `budgetCategoryId` from before the redesign are left as-is. The next time one of them moves (return or sell), the new flow takes over. No backfill is run.

## Enabled Categories Determination

Target pickers are operation-specific: enforce exact scope, visibility and
allowed category types/enabled state; show No Category only when that command
permits it. The generic source picker filters active/non-system rows but does
not enforce all writer rules. Selection cannot silently enable a category.

A category appears in a project's budget display when it has a `ProjectBudgetCategory` document (i.e., it was explicitly enabled for this project). Budget amount and spend are irrelevant — a category with `budgetCents: 0` and no spend still appears if it has been enabled. Categories without a `ProjectBudgetCategory` document are hidden regardless of spend.

This ensures the budget tab only shows categories the user intentionally selected during project creation or later enabled via the category selection sheet.

## Offline and Conflict Behavior

### Current Firebase behavior

- Most budget and reference writes effectively use database last-write-wins.
- Category reordering and Project setup fan out multiple independent writes.
- Category-name uniqueness is not enforced at the current backend boundary.
- Offline views depend on whatever Firestore documents and derived summaries are
  cached and do not expose one complete-history/readiness state.

### Target requirement

- Accepted local edits have durable operation receipts and survive restart.
- Project category enablement/allocation is one conflict-aware operation and
  preserves absent versus enabled-without-budget versus explicit zero.
- Category definition/type/archive and ordering mutations use revisions or
  equivalent preconditions; interruption cannot report success with a partial
  order.
- Duplicate-name conflicts are surfaced without merging category identities.
- Authorization for shared category changes is blocked on O-026 and enforced at
  the server/RLS boundary, not by hiding Settings UI.
- Budget/read projections expose freshness and incomplete-history state; cached
  denormalized Firebase summaries are migration comparison evidence, not target
  accounting authority.

## Edge Cases

The archived/invalid category display rules below document source behavior.
Target historical allocations must remain explainable through resolvable
category identity/snapshots. An unknown category is an explicit unresolved or
quarantined contribution, not permission to drop real value and publish a
complete total. Missing/partial local evidence must likewise remain visible.

1. **No categories enabled**: Show empty state prompting user to set up budget
2. **Category archived with existing transactions**: Category hidden from forms/displays, but transactions retain their `budgetCategoryId` and budget calculations still include them
3. **Pinned category archived**: Hidden from pinned display but kept in preferences array (restored if unarchived)
4. **Transaction with invalid budgetCategoryId**: Display as "Unknown Category", exclude from budget calculations
5. **Division by zero (zero budget)**: Show spend amount without percentage, or show "No budget set"
6. **Over 100% spent**: Show actual percentage, cap progress bar at 100% width but show overflow indicator
