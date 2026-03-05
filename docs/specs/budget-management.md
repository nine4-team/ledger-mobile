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

## Budget Progress Calculation

### Per-Category Spent

```
categorySpentCents = sum of (amountCents * multiplier) for all non-canceled transactions
                     where budgetCategoryId matches this category

transactionType values: "purchase", "return", "sale", "to-inventory"
  (legacy data may use title case — comparisons should be case-insensitive)
inventorySaleDirection values: "business_to_project", "project_to_business"

multiplier rules:
  if transactionType is "return": -1
  if isCanonicalInventorySale AND inventorySaleDirection is "project_to_business": -1
  otherwise: +1
```

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

| Transaction Type | Multiplier | Effect on Budget |
|-----------------|------------|------------------|
| Purchase | +1 | Adds to spent |
| Return | -1 | Subtracts from spent |
| Sale (business to project) | +1 | Adds to spent |
| Sale (project to business) | -1 | Subtracts from spent |
| Canceled transactions | excluded | No effect |

## Fee Category Differences

Fee categories use inverted semantics:

| Aspect | Standard/Itemized | Fee |
|--------|-------------------|-----|
| Amount label | "$X spent" | "$X received" |
| Remaining label | "$X remaining" | "$X remaining to receive" |
| Color at 75%+ | Red (warning) | Green (good progress) |
| Color at 0-49% | Green (healthy) | Red (low progress) |
| Display name suffix | "Budget" (e.g., "Furnishings Budget") | None (e.g., "Design Fee") |
| Over-budget label | "$X over" | "$X over received" |
| Default overall inclusion | Included (field defaults to `false`) | Per-category (Design Fee seed sets `true`) |

## Color Thresholds

### Standard/Itemized Categories

- 0-49% spent: Green (healthy)
- 50-74% spent: Yellow (warning)
- 75-99% spent: Red (critical)
- 100%+ spent: Red with overflow indicator

### Fee Categories (Inverted)

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

- **Non-canonical transactions**: Category selected by user via form (pre-filled from account default).
- **Canonical inventory sales**: Category derived from the item's `budgetCategoryId`, not from user selection. This is what makes canonical sale grouping deterministic.

## Item Budget Category Attribution

Items carry a persistent `budgetCategoryId` field. Once set, this field stays with the item across scope moves.

**Setting rules:**

1. When linking an item to a transaction: `item.budgetCategoryId = transaction.budgetCategoryId`
2. When moving to a different scope: if item has no category or category is not enabled in destination, prompt user to select. Note: "enabled in destination" only applies to project destinations — business inventory doesn't have per-project enabled categories, so only "missing" is checked.

**Why persistent:** This enables deterministic canonical sale grouping — the system always knows which sale transaction an item belongs to without prompting the user again.

## Enabled Categories Determination

A category appears in the budget display when:

1. It has a non-zero budget allocation (`budgetCents > 0`), OR
2. It has non-zero attributed spend (transactions exist for it)

AND it is not archived.

Categories with `budgetCents: 0` and no spend are hidden to prevent clutter.

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
