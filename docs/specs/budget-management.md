# Budget Management

## Overview

Budget management lets users define account-wide budget categories, allocate per-project budgets, and track spending progress in real-time. Every transaction must have a budget category — there are no uncategorized transactions.

## Budget Categories

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

The system handles current per-batch inventory movement transactions plus legacy canonical sales. The dual-read path lives in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts) `normalizeSpendAmount`. Any new reader must consult this function rather than reimplement the convention.

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

**Current implementation:** Uses brand primary color for all progress bars, with red for overage/overflow. The graduated color system below is preserved for potential future use.

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

Project list cards show a budget preview with this fallback chain:

1. Pinned categories (if any exist)
2. Top 1-2 categories by highest spend percentage (if no pins)
3. Overall Budget (if no categories have budget activity)

Amounts only — no percentage displayed on the card.

## Denormalized Budget Summary

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

1. Pinned categories (in user-defined order)
2. Non-pinned standard/itemized categories (custom order or alphabetical)
3. Overall Budget (cannot be pinned — always shown here)
4. Fee categories (always last)

**First-time behavior:** When a user first views a project, Furnishings is pinned by default (if enabled and has non-zero budget).

**Cleanup rules:**
- If a pinned category is **deleted**: remove its ID from `pinnedBudgetCategoryIds` (clean up stale references).
- If a pinned category is **archived**: keep its ID in the array (user intent preserved; restored if unarchived).

## Transaction Budget Attribution

- **Purchase / Return transactions**: Category selected by user via form picker, which only shows categories enabled for the current project (those with a `ProjectBudgetCategory` document). Pre-filled from account default if that category is enabled.
- **Per-batch inventory purchases** (new model): Category collected from the user at movement time and applied to every item in the batch. One category per Purchase transaction; no per-item category. Amounts use normalized `projectPriceCents`, which is automatically raised to at least `purchasePriceCents`; the UI collects a price only when neither is positive. See [sale-transactions.md](sale-transactions.md).
- **Project → inventory exits**: Return and Sale-to-Inventory transactions subtract from the source project at `purchasePriceCents`, including the source exit of project → project moves. The destination Purchase in project → project moves uses project price.
- **Legacy canonical sales**: Category was derived from the item's `budgetCategoryId` at the time of writing. Historical reads only.

## Item Budget Category Attribution

Items have a `budgetCategoryId` that follows this invariant:

**`(item.projectId == null) ↔ (item.budgetCategoryId == null)`**

Items in business inventory have no category. Items in a project have a category. This invariant is enforced on every write by both clients (iOS and MCP) and is the core change from the legacy "categories persist across scope moves" model.

**Setting rules:**

1. **When creating an item with `projectId == null`** (in business inventory): `budgetCategoryId` is forced to null. Any value passed by the caller is ignored or rejected.
2. **When creating an item linked to a project transaction**: `item.budgetCategoryId = transaction.budgetCategoryId`.
3. **When purchasing from inventory into a project**: the user picks a category for the whole batch, which is set on every item AND on the new Purchase transaction. Each project price is normalized to at least purchase cost; the user sets a sale price only if neither price is positive.
4. **When returning from a project to inventory**: `item.budgetCategoryId` is wiped to null.
5. **When reassigning within the same project**: `item.budgetCategoryId` may be updated to match the new transaction's category, but the projectId does not change.

**Auto-enable on transfer:** When items or transactions are moved to a destination project, the system automatically creates `ProjectBudgetCategory` documents for any budget category IDs that don't already have one in the destination (using `setData(merge: true)` to avoid overwriting existing budget amounts). This applies to:
- `sellToProject` — auto-enables the chosen batch category in the destination project
- `reassignTransactionToProject` — auto-enables the transaction's `budgetCategoryId` in the destination project

This ensures transferred spend always appears in the destination project's budget display without requiring manual category setup.

**Why the invariant matters:** Categories belong to projects. An item sitting in inventory has no project, so it has no category. Re-resolving the category at sell time makes the relationship explicit and eliminates a class of drift bugs that came from items carrying stale categories across scope moves. See [inventory-as-store.md](inventory-as-store.md) for the full rationale.

**Existing inventory items with stale categories.** Items currently in inventory that have a non-null `budgetCategoryId` from before the redesign are left as-is. The next time one of them moves (return or sell), the new flow takes over. No backfill is run.

## Enabled Categories Determination

A category appears in a project's budget display when it has a `ProjectBudgetCategory` document (i.e., it was explicitly enabled for this project). Budget amount and spend are irrelevant — a category with `budgetCents: 0` and no spend still appears if it has been enabled. Categories without a `ProjectBudgetCategory` document are hidden regardless of spend.

This ensures the budget tab only shows categories the user intentionally selected during project creation or later enabled via the category selection sheet.

## Offline and Conflict Behavior

- **Conflict resolution:** Last-write-wins (database default) for all budget data. Acceptable because most edits are single-user, single-device.
- **Category name uniqueness:** Cannot be enforced offline (requires server query). Allow potential duplicates offline; surface error on sync.
- **Transaction count aggregation:** Requires server query. Offline views use cached counts which may be stale.

## Edge Cases

1. **No categories enabled**: Show empty state prompting user to set up budget
2. **Category archived with existing transactions**: Category hidden from forms/displays, but transactions retain their `budgetCategoryId` and budget calculations still include them
3. **Pinned category archived**: Hidden from pinned display but kept in preferences array (restored if unarchived)
4. **Transaction with invalid budgetCategoryId**: Display as "Unknown Category", exclude from budget calculations
5. **Division by zero (zero budget)**: Show spend amount without percentage, or show "No budget set"
6. **Over 100% spent**: Show actual percentage, cap progress bar at 100% width but show overflow indicator
