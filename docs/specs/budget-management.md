# Budget Management Specification

**Version**: 1.0
**Date**: 2026-02-06
**Status**: Draft
**Supersedes**: `.cursor/plans/firebase-mobile-migration/40_features/budget-and-accounting/`

---

## Table of Contents

1. [Overview](#overview)
2. [Goals & Principles](#goals--principles)
3. [Data Model](#data-model)
4. [Budget Progress Calculation](#budget-progress-calculation)
5. [UI Components](#ui-components)
6. [Visual Design System](#visual-design-system)
7. [Interaction Patterns](#interaction-patterns)
8. [Fee Categories](#fee-categories)
9. [Pinning & Collapsed/Expanded Behavior](#pinning--collapsedexpanded-behavior)
10. [Budget Category Management](#budget-category-management)
11. [Project Budget Form](#project-budget-form)
12. [Mobile Adaptations](#mobile-adaptations)
13. [Edge Cases & Validation](#edge-cases--validation)
14. [Offline Behavior](#offline-behavior)
15. [Default Categories](#default-categories)
16. [Language & Labeling](#language--labeling)
17. [Acceptance Criteria](#acceptance-criteria)

---

## Overview

Budget Management enables users to:
- Define account-wide budget categories
- Allocate category-specific budgets per project
- Track spending progress against budgets in real-time
- Distinguish between standard spending categories and fee-based income categories
- Customize budget display with user-defined pinning

**Key Innovation vs Legacy**: The new system requires every transaction to have a budget category, simplifying attribution and enabling accurate cross-scope tracking with Business Inventory.

---

## Goals & Principles

### Primary Goals

1. **Simple Defaults**: New users should understand budget tracking without learning complex concepts
2. **Accurate Progress**: Budget tracking must correctly handle Business Inventory movements and canonical transactions
3. **Flexible Categorization**: Support diverse business models (product sales, services, fees)
4. **Offline-First**: All budget displays render from local Firestore cache with no network dependency

### Design Principles

- **Category-Required**: Every transaction must have a budget category (no uncategorized transactions)
- **Stable Attribution**: Items carry persistent `budgetCategoryId` for deterministic canonical operations
- **Explicit Semantics**: Fee categories identified by metadata (not name matching)
- **User Control**: Pinning allows customization of collapsed budget views
- **Visual Clarity**: Color-coded progress bars with clear thresholds
- **Mobile-First**: Touch-optimized interactions, responsive layouts

---

## Data Model

### Budget Category (Account-Scoped Preset)

**Firestore Path**: `accounts/{accountId}/presets/default/budgetCategories/{budgetCategoryId}`

```typescript
type BudgetCategoryMetadata = {
  categoryType?: "general" | "itemized" | "fee";
  excludeFromOverallBudget?: boolean;
  legacy?: Record<string, any> | null;
};

type BudgetCategory = {
  id: string;                              // UUID
  accountId: string;                       // Account scope
  projectId: null;                         // Always null (account-level preset)
  name: string;                            // Display name (e.g., "Furnishings")
  slug: string;                            // URL-friendly identifier (reserved for future use)
  isArchived: boolean;                     // Soft delete flag
  metadata?: BudgetCategoryMetadata | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  createdBy: string;
  updatedBy: string;
};
```

**Category Types**:
- **`general`**: Default type, tracks spending (e.g., "Install", "Storage & Receiving")
- **`itemized`**: Tracks spending with line-item detail (e.g., "Furnishings")
- **`fee`**: Tracks income/fees received (e.g., "Design Fee")

**Constraints**:
- `name` must be unique per account (case-insensitive)
- `name` must be non-empty (min 1 char, max 100 chars)
- `categoryType` defaults to `"general"` if not specified
- Cannot be both `fee` and `itemized` (mutually exclusive)

---

### Project Budget Category (Per-Project Allocation)

**Firestore Path**: `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`

```typescript
type ProjectBudgetCategory = {
  id: string;                              // id = budgetCategoryId (matches preset)
  budgetCents: number | null;              // Budget in cents; null = enabled but not budgeted
  createdAt: Timestamp;
  updatedAt: Timestamp;
  createdBy: string;
  updatedBy: string;
};
```

**Semantics**:
- Document exists = category enabled for this project
- `budgetCents: null` = category enabled but no specific budget allocated
- `budgetCents: 0` = explicitly set to zero budget
- No document = category not enabled for this project

**Constraints**:
- `budgetCents` must be non-negative if not null
- Maximum value: 2,147,483,647 cents ($21,474,836.47)

---

### Project Preferences (User-Specific Display Settings)

**Firestore Path**: `accounts/{accountId}/users/{userId}/projectPreferences/{projectId}`

```typescript
type ProjectPreferences = {
  id: string;                              // id = projectId
  accountId: string;
  userId: string;
  projectId: string;
  pinnedBudgetCategoryIds: string[];      // Ordered list of pinned category IDs
  createdAt?: Timestamp;
  updatedAt?: Timestamp;
};
```

**Semantics**:
- `pinnedBudgetCategoryIds` determines which categories appear in collapsed budget view
- Order in array = display order in collapsed view
- Empty array = no pins, fallback to Overall Budget only in collapsed view

---

### Account Presets (Account-Wide Defaults)

**Firestore Path**: `accounts/{accountId}/presets/default`

```typescript
type AccountPresets = {
  id: "default";
  accountId: string;
  defaultBudgetCategoryId?: string | null; // Default for new transactions
  budgetCategoryOrder?: string[] | null;   // Custom display order (category IDs)
  // ...other preset fields...
};
```

---

### Transaction Budget Attribution

**Firestore Path**: `accounts/{accountId}/projects/{projectId}/transactions/{transactionId}`

```typescript
type Transaction = {
  // ...other fields...
  budgetCategoryId: string;                // Required: FK to BudgetCategory.id
  transactionType: "Purchase" | "Return" | "Sale" | "To Inventory";
  amountCents: number;                     // Transaction amount in cents
  isCanceled: boolean;
  isCanonicalInventorySale?: boolean;      // True if system-generated canonical sale
  inventorySaleDirection?: "business_to_project" | "project_to_business";
  // ...
};
```

**Attribution Rules**:
- **Non-canonical transactions**: Category selected by user via form
- **Canonical inventory sales**: Category derived from item's `budgetCategoryId`

---

### Item Budget Category

**Firestore Path**: `accounts/{accountId}/items/{itemId}`

```typescript
type Item = {
  // ...other fields...
  budgetCategoryId?: string | null; // Persistent category for canonical operations
  // ...
};
```

**Set Rules**:
1. When linking item to non-canonical transaction: `item.budgetCategoryId = transaction.budgetCategoryId`
2. When moving Business Inventory → Project: prompt if missing or not enabled in destination
3. When moving Project → Business Inventory: prompt if missing

**Persistence**: Once set, `budgetCategoryId` is stable across scope moves (not cleared on unlink)

---

## Budget Progress Calculation

### Overall Budget Spent

**Formula**:
```typescript
overallSpentCents = sum(
  transactions
    .filter(t => !t.isCanceled)
    .filter(t => !getBudgetCategory(t.budgetCategoryId)?.metadata?.excludeFromOverallBudget)
    .map(t => t.amountCents * getMultiplier(t))
);

function getMultiplier(transaction: Transaction): number {
  if (transaction.transactionType === "Return") return -1;
  if (transaction.isCanonicalInventorySale) {
    return transaction.inventorySaleDirection === "project_to_business" ? -1 : 1;
  }
  return 1;
}
```

**Rules**:
- Purchases: add to spent (`+1` multiplier)
- Returns: subtract from spent (`-1` multiplier)
- Canonical sales `business_to_project`: add to spent (`+1` multiplier)
- Canonical sales `project_to_business`: subtract from spent (`-1` multiplier)
- Canceled transactions: always excluded
- Transactions in categories with `excludeFromOverallBudget === true`: excluded

---

### Overall Budget Denominator

**Formula**:
```typescript
overallBudgetCents = sum(
  projectBudgetCategories
    .filter(pbc => !getBudgetCategory(pbc.id)?.metadata?.excludeFromOverallBudget)
    .map(pbc => pbc.budgetCents ?? 0)
);
```

**Rules**:
- Sum of all enabled category budgets
- Excludes categories with `excludeFromOverallBudget === true`
- Categories with `budgetCents: null` treated as 0 for denominator

---

### Overall Budget Percentage

**Formula**:
```typescript
overallPercentage = (overallSpentCents / overallBudgetCents) * 100;
```

**Display Cap**: Cap percentage at 100% for progress bar width, but show actual percentage in text

---

### Per-Category Budget Spent

**Formula**:
```typescript
categorySpentCents[categoryId] = sum(
  transactions
    .filter(t => !t.isCanceled)
    .filter(t => t.budgetCategoryId === categoryId)
    .map(t => t.amountCents * getMultiplier(t))
);
```

**Rules**:
- Same multiplier logic as overall spent
- Includes all transactions attributed to this category (canonical + non-canonical)

---

### Per-Category Budget Percentage

**Formula**:
```typescript
categoryPercentage = (categorySpentCents / categoryBudgetCents) * 100;
```

**Special Case - Fee Categories**:
```typescript
// For categories with categoryType === "fee"
feeReceivedCents = categorySpentCents;
feePercentage = (feeReceivedCents / categoryBudgetCents) * 100;
```

Fee categories use "received" language but same underlying calculation.

---

## UI Components

### 1. Budget Progress Display (Full Mode)

**Location**: Project detail screen, above tabs (always visible)

**Purpose**: Show budget progress at-a-glance for active project

**Display Modes**:
- **Collapsed**: Shows pinned budget categories only (or Overall Budget if no pins)
- **Expanded**: Shows all enabled categories + Overall Budget

**Component Structure**:
```
┌─────────────────────────────────────────┐
│  [Pinned Category 1]                    │
│  ▓▓▓▓▓▓▓▓░░░░ 65%                      │
│  $6,500 spent • $3,500 remaining        │
│                                         │
│  [Pinned Category 2]                    │
│  ▓▓▓▓▓▓▓░░░░░ 45%                      │
│  $2,250 spent • $2,750 remaining        │
│                                         │
│  [▼ Show All Budget Categories]         │  ← Toggle button (if categories exist beyond pins)
└─────────────────────────────────────────┘

--- When Expanded ---

┌─────────────────────────────────────────┐
│  [Pinned Category 1]                    │
│  ▓▓▓▓▓▓▓▓░░░░ 65%                      │
│  $6,500 spent • $3,500 remaining        │
│                                         │
│  [Pinned Category 2]                    │
│  ▓▓▓▓▓▓▓░░░░░ 45%                      │
│  $2,250 spent • $2,750 remaining        │
│                                         │
│  [Other Category 1]                     │
│  ▓▓░░░░░░░░░░ 15%                      │
│  $750 spent • $4,250 remaining          │
│                                         │
│  [Overall Budget]                       │
│  ▓▓▓▓▓▓▓▓▓░░░ 58%                      │
│  $23,200 spent • $16,800 remaining      │
│                                         │
│  [Design Fee]                           │
│  ▓▓▓▓▓▓▓▓▓▓▓░ 85%                      │
│  $4,250 received • $750 remaining       │
│                                         │
│  [▲ Show Less]                          │  ← Toggle button
└─────────────────────────────────────────┘
```

**Category Display Order**:
1. Pinned categories (in user-defined order)
2. Non-pinned enabled categories (in account custom order or alphabetical)
3. Overall Budget (always shown in expanded view, at end before fees)
4. Fee categories (always last)

---

### 2. Budget Progress Preview (Project Card)

**Location**: Project list screen, on each project card

**Purpose**: Compact budget preview without interaction

**Behavior**:
- Shows same pinned categories as collapsed full mode
- Fallback: Overall Budget if no pins
- No toggle button (static display)
- Single line per category (condensed layout)

**Layout**:
```
┌─────────────────────────────────────┐
│  Project Name                       │
│  Client Name                        │
│                                     │
│  Furnishings: $6.5k / $10k (65%) ▓▓▓▓░│
│  Overall: $23.2k / $40k (58%)    ▓▓▓░░│
└─────────────────────────────────────┘
```

---

### 3. Budget Category Tracker (Individual Component)

**Element Structure**:
```
Category Name Budget                    ← Title (with "Budget" suffix)
$6,500 spent • $3,500 remaining         ← Amounts
▓▓▓▓▓▓▓▓░░░░░░░░                       ← Progress bar
```

**Elements**:
1. **Title Row**: Category name + "Budget" suffix (except Design Fee, Overall Budget)
2. **Amount Row**: Spent + remaining (or "over" if exceeded)
3. **Progress Bar**: Colored bar showing visual progress (capped at 100% width)
4. **Overflow Indicator**: Dark red bar at right edge if >100%

---

## Visual Design System

### Color Thresholds (General Categories)

**Progress Bar Colors**:
- **Green** (`#22C55E` / `bg-green-500`): 0-49% spent (healthy)
- **Yellow** (`#EAB308` / `bg-yellow-500`): 50-74% spent (warning)
- **Red** (`#EF4444` / `bg-red-500`): 75-99% spent (critical)
- **Red** (`#EF4444` / `bg-red-500`): 100%+ spent (over budget)

**Overflow Indicator**:
- **Dark Red** (`#991B1B` / `bg-red-800`): Amount over 100% (separate bar segment)

**Amount Text Colors**:
- **Green Text** (`#059669` / `text-green-600`): 0-49% spent
- **Yellow Text** (`#CA8A04` / `text-yellow-600`): 50-74% spent
- **Red Text** (`#DC2626` / `text-red-600`): 75%+ spent

---

### Color Thresholds (Fee Categories)

**Inverted Logic** (opposite of standard):
- **Green** (`#22C55E` / `bg-green-500`): ≥75% received (good progress)
- **Yellow** (`#EAB308` / `bg-yellow-500`): 50-74% received (partial progress)
- **Red** (`#EF4444` / `bg-red-500`): 0-49% received (low progress)

**Amount Text Colors**:
- **Green Text** (`#059669` / `text-green-600`): ≥75% received
- **Yellow Text** (`#CA8A04` / `text-yellow-600`): 50-74% received
- **Red Text** (`#DC2626` / `text-red-600`): <50% received

---

### Typography

**Category Title**:
- Font: System (SF Pro / Roboto)
- Size: `16px` (`text-base`)
- Weight: `500` (`font-medium`)
- Color: `#111827` (`text-gray-900`)

**Amount Text**:
- Font: System
- Size: `14px` (`text-sm`)
- Weight: `400` (normal) for labels, `700` (`font-bold`) for amounts when over budget
- Color: `#6B7280` (`text-gray-500`) for base, color-coded for emphasis

---

### Layout & Spacing

**Budget Module Container**:
- Padding: `16px` all sides
- Background: `#FFFFFF` (`bg-white`)
- Border: `1px solid #E5E7EB` (`border-gray-200`)
- Border Radius: `12px` (`rounded-xl`)
- Shadow: `0 1px 3px rgba(0, 0, 0, 0.1)` (`shadow-sm`)

**Category Sections**:
- Spacing: `16px` vertical gap between trackers (`space-y-4`)
- First tracker: no top margin
- Last tracker: no bottom margin

**Progress Bar**:
- Height: `8px` (`h-2`)
- Border Radius: `9999px` (`rounded-full`)
- Background: `#E5E7EB` (`bg-gray-200`)
- Transition: `all 300ms ease` (smooth animation)
- Margin Bottom: `4px` (small gap before amount row)

**Amount Row**:
- Layout: Flexbox, space-between alignment
- Gap: `8px` between elements
- Vertical Alignment: Center

---

### Mobile Spacing Adjustments

- Container padding: `12px` (reduced from 16px)
- Category gap: `12px` (reduced from 16px)
- Font sizes: Same as desktop (16px/14px remain readable)

---

## Interaction Patterns

### Toggle Button (Show All / Show Less)

**Appearance**:
- Button Type: Text button with icon
- Position: Below last visible category tracker, centered or left-aligned
- Padding: `8px 12px`
- Font: `14px`, `font-medium`
- Color: Primary color (`text-primary-600`)

**States**:
- **Collapsed**: Shows `ChevronDown` icon + "Show All Budget Categories"
- **Expanded**: Shows `ChevronUp` icon + "Show Less"

**Visibility Rules**:
```typescript
showToggleButton = (
  hasUnpinnedEnabledCategories ||
  hasOverallBudget ||
  hasFeeCategories
);
```

Only show toggle if there's additional content beyond pinned categories.

**Behavior**:
- Tap: Toggle between collapsed/expanded state
- No animation on initial load (renders in collapsed state)
- Smooth height transition (300ms ease) on toggle
- Scroll position: maintain scroll (don't jump to top)

---

### Pinning Affordance

**Location**: Long-press menu or swipe actions on category tracker (implementation-defined)

**Actions**:
- **Pin**: Add category to user's `pinnedBudgetCategoryIds` (if not already pinned)
- **Unpin**: Remove category from user's `pinnedBudgetCategoryIds`
- **Reorder Pins**: Drag-and-drop or up/down buttons (see Budget Category Management)

**Visual Indicator**:
- Pinned categories: optional pin icon (`📌` or `PinIcon`) in category title
- No indicator: also acceptable (pinning is implicit by position)

**Constraints**:
- Overall Budget cannot be pinned (always in expanded view)
- Can pin any enabled category (standard, itemized, or fee)
- Maximum pins: unlimited (but recommend max 5 for UX)

---

### Touch Targets

**Minimum Size**: 44x44pt (iOS) / 48x48dp (Android)

**Interactive Elements**:
- Toggle button: Full button area (44pt minimum height)
- Pin/unpin actions: Full row tap or swipe gesture
- Category detail tap: Optional (navigate to category detail/filter transactions)

---

### Loading States

**Initial Load** (first render):
- Show skeleton placeholders for 2-3 category trackers
- Skeleton: gray rounded rectangles mimicking tracker layout
- Duration: Until Firestore data loads from cache

**Empty State** (no enabled categories):
- Message: "No budget categories enabled for this project"
- Action: "Set Budget" button → navigate to project budget form

**No Pins State** (collapsed, no pinned categories):
- Show Overall Budget only
- Message below: "Pin categories to customize this view"

---

### Error States

**Offline - Data Unavailable**:
- Show last cached state (if available)
- Banner: "Offline - showing cached budget data"
- Disable editing actions (pin/unpin, toggle)

**Sync Error**:
- Show last cached state
- Banner: "Budget data may be out of date - retrying..."
- Auto-retry on network recovery

**Permission Error**:
- Message: "You don't have permission to view budget information"
- Hide all budget trackers

---

## Fee Categories

### Identification

**Method**: Explicit metadata (not name matching)

```typescript
function isFeeCategory(category: BudgetCategory): boolean {
  return category.metadata?.categoryType === "fee";
}
```

**Mutual Exclusivity**:
- Cannot be `"fee"` and `"itemized"` simultaneously
- Validation: Form should prevent selecting both during creation/edit

---

### Language Differences

| Element | Standard Category | Fee Category |
|---------|------------------|--------------|
| Title Suffix | "Budget" (e.g., "Furnishings Budget") | No suffix (e.g., "Design Fee") |
| Amount Label | "$X spent" | "$X received" |
| Remaining Label | "$X remaining" | "$X remaining to receive" |
| Progress Direction | Higher % = more spent (bad if exceeds) | Higher % = more received (good) |

---

### Progress Bar Color Logic

**General Categories**:
```typescript
function getGeneralColor(percentage: number): string {
  if (percentage >= 75) return "red";
  if (percentage >= 50) return "yellow";
  return "green";
}
```

**Fee Categories** (inverted):
```typescript
function getFeeColor(percentage: number): string {
  if (percentage >= 75) return "green";   // Good: most of fee received
  if (percentage >= 50) return "yellow";  // Partial: some fee received
  return "red";                           // Bad: little fee received
}
```

---

### Display Position

**Rule**: Fee categories always displayed last

**Sort Order**:
1. Pinned non-fee categories (user order)
2. Non-pinned non-fee categories (custom order or alphabetical)
3. Overall Budget (in expanded view)
4. Fee categories (alphabetical)

---

### Exclusion from Overall Budget

**Default**: Fee categories included in overall budget calculations

**Opt-Out**: Set `metadata.excludeFromOverallBudget = true` to exclude

**Typical Configuration**:
- Design Fee: `excludeFromOverallBudget = true` (fee is income, not spending)
- Fee categories that represent project income should be excluded
- Fee categories that represent reimbursable expenses should be included

**UI Guidance**: Provide toggle in Budget Category Settings: "Exclude from overall budget"

---

## Pinning & Collapsed/Expanded Behavior

### Default Collapsed View

**Behavior**:
```typescript
function getCollapsedCategories(
  projectId: string,
  userId: string,
  enabledCategories: BudgetCategory[]
): BudgetCategory[] {
  const preferences = getProjectPreferences(userId, projectId);

  if (preferences.pinnedBudgetCategoryIds.length > 0) {
    // Show pinned categories in user-defined order
    return preferences.pinnedBudgetCategoryIds
      .map(id => enabledCategories.find(c => c.id === id))
      .filter(c => c !== undefined);
  } else {
    // Fallback: show Overall Budget only
    return []; // Empty array = show Overall Budget tracker only
  }
}
```

---

### Default Expanded View

**Behavior**:
```typescript
function getExpandedCategories(
  enabledCategories: BudgetCategory[]
): BudgetCategory[] {
  // Show all enabled categories + Overall Budget
  return [
    ...enabledCategories.filter(c => c.metadata?.categoryType !== "fee"),
    // Overall Budget inserted here (synthetic entry)
    ...enabledCategories.filter(c => c.metadata?.categoryType === "fee")
  ];
}
```

---

### Enabled Categories Determination

**Rule**: Category appears in expanded list if:
1. Project budget doc exists (`projectBudgetCategories/{categoryId}`), OR
2. Has non-zero attributed spend (even without budget doc)

```typescript
function getEnabledCategories(
  projectId: string,
  budgetCategories: BudgetCategory[]
): BudgetCategory[] {
  const projectBudgets = getProjectBudgetCategories(projectId);
  const spendByCategory = calculateSpendByCategory(projectId);

  return budgetCategories.filter(category => {
    const hasProjectBudget = projectBudgets[category.id] !== undefined;
    const hasSpend = spendByCategory[category.id] !== 0;
    return hasProjectBudget || hasSpend;
  });
}
```

---

### Initial Pinning (First-Time User)

**Seed Behavior**:
- When user first views project, check if `ProjectPreferences` doc exists
- If not: seed with Furnishings pinned by default (if enabled)
- If Furnishings not enabled: no pins (fallback to Overall Budget)

**Implementation**:
```typescript
async function ensureProjectPreferences(userId: string, projectId: string) {
  const prefs = await getProjectPreferences(userId, projectId);
  if (!prefs) {
    const furnishingsCategory = await findCategoryByName("Furnishings");
    const projectBudget = await getProjectBudgetCategory(projectId, furnishingsCategory.id);

    const pinnedIds = projectBudget ? [furnishingsCategory.id] : [];

    await createProjectPreferences({
      userId,
      projectId,
      pinnedBudgetCategoryIds: pinnedIds
    });
  }
}
```

---

### Pinning Persistence

**Storage**: `ProjectPreferences.pinnedBudgetCategoryIds`

**Scope**: Per-user, per-project (each user can have different pins for same project)

**Ordering**: Array order = display order in collapsed view

**Validation**:
- Pinned category must exist in account's budget categories
- Pinned category should be enabled in project (but handle gracefully if not)
- If pinned category is archived: hide from collapsed view (don't show archived)

---

## Budget Category Management

### Settings Screen

**Location**: Account settings → Budget Categories

**Purpose**: Create, edit, archive, reorder budget categories

**Layout**:
```
┌─────────────────────────────────────────┐
│  Budget Categories                      │
│                                         │
│  Account-Wide Default                   │
│  [Dropdown: Furnishings ▼]             │  ← Default for new transactions
│                                         │
│  ─────────────────────────────────────  │
│                                         │
│  Active Categories                      │
│                                         │
│  ☰ Furnishings              📝 🗑️       │  ← Drag handle, name, actions
│     [✓] Itemize                         │
│                                         │
│  ☰ Install                  📝 🗑️       │
│     [ ] Itemize                         │
│                                         │
│  ☰ Design Fee               📝 🗑️       │
│     [✓] Exclude from Overall            │
│                                         │
│  [+ Add Category]                       │
│                                         │
│  ─────────────────────────────────────  │
│                                         │
│  [▼ Show Archived (3)]                  │  ← Toggle to show archived
└─────────────────────────────────────────┘
```

---

### Category Row (Active)

**Elements**:
1. **Drag Handle** (`☰` or `GripVertical` icon): Reorder categories
2. **Category Name**: Editable on tap (inline edit) or via edit modal
3. **Metadata Toggles**:
   - "Itemize" toggle: Enable/disable `categoryType = "itemized"`
   - "Fee Category" toggle: Enable/disable `categoryType = "fee"`
   - "Exclude from Overall" toggle: Enable/disable `excludeFromOverallBudget`
4. **Actions Menu** (`⋮`):
   - Edit name
   - Archive
   - View transaction count

**Constraints**:
- Cannot delete categories with transactions (must archive instead)
- Cannot edit name to duplicate existing category name
- Itemize and Fee toggles are mutually exclusive

---

### Category Row (Archived)

**Elements**:
1. **Category Name** (grayed out, no drag handle)
2. **Transaction Count**: "(12 transactions)"
3. **Actions Menu** (`⋮`):
   - Unarchive
   - View transactions

**Visual Style**:
- Opacity: `0.6`
- Text color: `text-gray-500`
- No drag handle (cannot reorder archived)

---

### Add Category Flow

**Steps**:
1. Tap "[+ Add Category]" button
2. Modal/sheet opens:
   - Input: Category name
   - Toggle: Itemize (default off)
   - Toggle: Fee Category (default off)
   - Toggle: Exclude from Overall (default off)
3. Tap "Create"
4. Validation:
   - Name not empty
   - Name not duplicate (case-insensitive)
   - Itemize and Fee not both enabled
5. Success: Close modal, new category appears at end of active list

---

### Edit Category Flow

**Steps**:
1. Tap category row or edit icon
2. Modal/sheet opens (pre-filled with current values)
3. User edits name or toggles
4. Tap "Save"
5. Validation: Same as Add
6. Success: Close modal, category updates in place

**Constraints**:
- Cannot change name to duplicate
- If category has transactions and changing type (e.g., itemized → standard), warn user

---

### Archive Category Flow

**Steps**:
1. Tap actions menu (`⋮`) → "Archive"
2. Confirmation prompt:
   - Message: "Archive [Category Name]? This category will be hidden but can be restored later."
   - Show transaction count: "This category has 12 transactions."
   - Buttons: "Cancel" / "Archive"
3. On confirm: Set `isArchived = true`
4. Category moves to Archived section (collapsed by default)

**Behavior**:
- Archived categories hidden from transaction forms
- Archived categories hidden from budget displays
- Existing transactions retain `budgetCategoryId` (not deleted)
- Can unarchive to restore

---

### Reorder Categories

**Method**: Drag-and-drop (mobile: long-press to enter drag mode)

**Behavior**:
1. User long-presses drag handle
2. Row lifts with visual feedback (shadow, opacity)
3. User drags to new position
4. Other rows shift with animation
5. On release: Save new order to `AccountPresets.budgetCategoryOrder`

**Visual Feedback**:
- Dragging row: `opacity-50`, increased shadow
- Drag-over position: blue border top (`border-t-2 border-primary-500`)
- Smooth transitions: 200ms ease

**Persistence**:
```typescript
await saveAccountPresets({
  budgetCategoryOrder: reorderedCategoryIds
});
```

**Fallback**: If drag-and-drop not feasible, provide up/down arrow buttons

---

### Default Category Setting

**Purpose**: Set account-wide default for new transaction forms

**UI**:
- Dropdown at top of Budget Category Settings screen
- Label: "Account-Wide Default"
- Options: All active categories (not archived)
- Default selection: Furnishings (if exists)

**Behavior**:
- On change: Save to `AccountPresets.defaultBudgetCategoryId`
- Transaction form: Pre-select this category on load
- User can still change category per transaction

---

### Transaction Count Display

**Purpose**: Show usage before archiving

**UI**:
- Shown in archive confirmation prompt
- Shown in category row (optional, on hover or in collapsed state)
- Format: "(12 transactions)"

**Calculation**:
```typescript
async function getTransactionCount(accountId: string, categoryId: string): Promise<number> {
  const query = firestore
    .collection(`accounts/${accountId}/transactions`)
    .where("budgetCategoryId", "==", categoryId);

  const snapshot = await query.count().get();
  return snapshot.data().count;
}
```

**Note**: This is an aggregation query (may not be offline-available). Consider caching count or computing on-demand.

---

## Project Budget Form

### Location

**Access Points**:
- Project settings → Budget
- First-time project setup wizard
- Budget module → "Set Budget" button (if no budgets set)

---

### Layout

```
┌─────────────────────────────────────────┐
│  Project Budget                         │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │  Total Budget                   │   │  ← Auto-calculated, prominent display
│  │  $40,000                        │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Budget Categories                      │
│                                         │
│  ┌───────────────┬───────────────┐     │
│  │ Furnishings   │ Install       │     │  ← 2-column grid (mobile: 1 column)
│  │ $ 25,000      │ $ 8,000       │     │
│  └───────────────┴───────────────┘     │
│                                         │
│  ┌───────────────┬───────────────┐     │
│  │ Design Fee    │ Storage       │     │
│  │ $ 5,000       │ $ 2,000       │     │
│  └───────────────┴───────────────┘     │
│                                         │
│  [+ Enable More Categories]             │
│                                         │
│  [Cancel]  [Save]                       │
└─────────────────────────────────────────┘
```

---

### Total Budget Display

**Appearance**:
- Container: `bg-primary-50 rounded-xl border-2 border-primary-200`
- Padding: `16px`
- Label: "Total Budget" (`text-sm text-gray-500`)
- Amount: Large font `32px`, `font-bold`, `text-gray-900`
- Position: Above category grid

**Calculation**:
```typescript
totalBudget = sum(enabledCategoryBudgets.map(c => c.budgetCents ?? 0));
```

**Behavior**:
- Updates live as user edits category amounts
- Read-only (not directly editable)

---

### Category Input Fields

**Layout**:
- Grid: 2 columns on tablet/desktop, 1 column on mobile
- Gap: `16px` between fields

**Input Appearance**:
- Label: Category name (top or left of input)
- Input: Currency formatted, left-aligned
- Prefix: "$" icon or text
- Border: `2px solid #E5E7EB`, focus: `border-primary-500`
- Border Radius: `8px`
- Padding: `12px`

**Behavior**:
- On input: Parse currency (allow $, commas, decimals)
- On blur: Format to `$X,XXX.XX`
- Validation: Non-negative numbers only
- Empty = `null` (category enabled but not budgeted)

---

### Enable More Categories

**UI**:
- Button: "[+ Enable More Categories]"
- Opens: Category selection sheet/modal

**Modal**:
- List: All active categories not yet enabled
- Checkbox selection (multi-select)
- On confirm: Create `ProjectBudgetCategory` docs with `budgetCents: null`
- New category inputs appear in form

---

### Save Behavior

**Validation**:
- All amounts must be non-negative
- At least one category enabled (warn if removing all)

**Save**:
```typescript
for (const category of enabledCategories) {
  await setProjectBudgetCategory(projectId, category.id, {
    budgetCents: category.budgetCents
  });
}

// Remove disabled categories
for (const disabledCategoryId of disabledCategoryIds) {
  await deleteProjectBudgetCategory(projectId, disabledCategoryId);
}
```

**Success**:
- Show toast: "Budget saved"
- Navigate back to project detail
- Budget display updates immediately (Firestore listener)

---

## Mobile Adaptations

### Responsive Breakpoints

- **Mobile**: < 768px width
- **Tablet**: 768px - 1024px width
- **Desktop**: > 1024px width

---

### Budget Progress Display (Mobile)

**Changes from Desktop**:
- Container padding: `12px` (reduced from 16px)
- Category spacing: `12px` (reduced from 16px)
- Font sizes: Same as desktop (remain readable)
- Progress bar height: Same (`8px`)

**Layout**:
- Single column (same as desktop)
- No horizontal scrolling
- Toggle button full-width (centered text)

---

### Budget Category Management (Mobile)

**Drag-and-Drop Alternative**:
- Long-press category row to enter "reorder mode"
- Drag handle becomes prominent
- Other rows compress slightly
- Drop to new position
- Exit mode: Tap "Done" button

**Or: Up/Down Buttons**:
- Show up/down arrow buttons in edit mode
- Tap to move category one position
- Simpler than drag-and-drop for mobile

---

### Project Budget Form (Mobile)

**Grid Layout**:
- 1 column (stacked inputs) on mobile
- 2 columns on tablet/desktop

**Input Fields**:
- Full-width on mobile
- Larger tap targets (`48px` height minimum)
- Larger font size in inputs (`16px` to prevent zoom)

---

### Pinning Affordance (Mobile)

**Gesture**: Swipe left on category tracker row

**Actions Revealed**:
- Swipe left: "Pin" / "Unpin" button appears
- Tap button to toggle pin state
- Swipe back to dismiss

**Alternative**: Long-press context menu

---

## Edge Cases & Validation

### Empty States

**No Budget Categories (Account)**:
- Message: "No budget categories created yet"
- Action: "Create Your First Category" button → navigate to Settings

**No Enabled Categories (Project)**:
- Message: "No budget categories enabled for this project"
- Action: "Set Budget" button → navigate to Project Budget Form

**No Pinned Categories (Collapsed View)**:
- Show: Overall Budget only
- Message below: "Pin categories to customize this view"
- Action: "View All" button (same as expand toggle)

**All Categories Archived**:
- Same as "No Enabled Categories"
- Additional message: "All categories are archived"

---

### Validation Rules

**Budget Category Name**:
- Required: Non-empty
- Length: 1-100 characters
- Unique: Case-insensitive uniqueness per account
- Characters: Allow letters, numbers, spaces, hyphens, ampersands

**Budget Amount**:
- Non-negative: `>= 0`
- Maximum: `$21,474,836.47` (2^31 - 1 cents)
- Precision: Cents (2 decimal places)
- Null allowed: Represents "enabled but not budgeted"

**Category Type Constraints**:
- Cannot be both `"itemized"` and `"fee"`
- Validation: Form should disable Fee toggle if Itemize is on (and vice versa)

---

### Orphaned Data Handling

**Pinned Category Deleted**:
- Remove from `pinnedBudgetCategoryIds` array
- Update display immediately (reactive)

**Pinned Category Archived**:
- Keep in array (user intent preserved)
- Hide from collapsed view (archived = hidden)
- Show in expanded view with archived styling (optional)

**Budget Category with Transactions Deleted** (should not be possible):
- Prevent deletion via UI (archive only)
- If manually deleted in Firestore: Transactions retain `budgetCategoryId`
- Display: Show "Unknown Category" or category ID in transaction list

**Transaction with Invalid `budgetCategoryId`**:
- Display: "Unknown Category"
- Budget progress: Exclude from calculations (or include in "Other/Uncategorized")
- Prevention: Validate `budgetCategoryId` on transaction creation

---

## Offline Behavior

### Firestore Offline Persistence

**Configuration**:
```typescript
const db = initializeFirestore(app, {
  experimentalForceLongPolling: false,
  localCache: persistentLocalCache({
    tabManager: persistentMultipleTabManager()
  })
});
```

**Behavior**:
- All budget data cached locally by Firestore SDK
- Reads served from cache (instant, no network)
- Writes queued when offline, synced on reconnect

---

### Offline UI Indicators

**Banner**: Show network status banner at top of screen

**States**:
- **Online**: No banner (or small green indicator)
- **Offline**: Yellow banner "Offline - changes will sync when connected"
- **Sync Error**: Red banner "Sync error - retrying..."

**Budget Display**:
- Render normally from cache
- No special treatment needed (Firestore handles)
- Optional: Small "Offline" badge on budget module

---

### Offline Limitations

**Cannot Perform**:
- Transaction count aggregation (requires server query)
- Category name uniqueness check (requires server query)

**Workarounds**:
- Cache transaction counts locally (update on sync)
- Allow duplicate names offline, resolve on sync (show error after)

---

### Sync Behavior

**On Reconnect**:
1. Firestore syncs pending writes (automatic)
2. Fetch latest data from server (automatic)
3. Resolve conflicts (Firestore last-write-wins)
4. Update UI reactively (Firestore listeners fire)

**Conflict Resolution**:
- Budget category edits: Last-write-wins (Firestore default)
- Pinning: Per-user (no conflicts)
- Project budgets: Last-write-wins

---

## Default Categories

### Seed on Account Creation

**Categories to Create**:

1. **Furnishings**
   - `categoryType: "itemized"`
   - `excludeFromOverallBudget: false`
   - Purpose: Track furniture and furnishing purchases with line-item detail

2. **Install**
   - `categoryType: "general"`
   - `excludeFromOverallBudget: false`
   - Purpose: Track installation labor and services

3. **Design Fee**
   - `categoryType: "fee"`
   - `excludeFromOverallBudget: true`
   - Purpose: Track design fee income (received, not spent)

4. **Storage & Receiving**
   - `categoryType: "general"`
   - `excludeFromOverallBudget: false`
   - Purpose: Track storage and receiving costs

**Implementation**:
```typescript
async function seedDefaultBudgetCategories(accountId: string) {
  const categories = [
    { name: "Furnishings", categoryType: "itemized", excludeFromOverall: false },
    { name: "Install", categoryType: "general", excludeFromOverall: false },
    { name: "Design Fee", categoryType: "fee", excludeFromOverall: true },
    { name: "Storage & Receiving", categoryType: "general", excludeFromOverall: false },
  ];

  for (const cat of categories) {
    await createBudgetCategory(accountId, {
      name: cat.name,
      metadata: {
        categoryType: cat.categoryType,
        excludeFromOverallBudget: cat.excludeFromOverall
      }
    });
  }

  // Set Furnishings as default
  const furnishingsId = await findCategoryByName(accountId, "Furnishings");
  await setDefaultCategory(accountId, furnishingsId);
}
```

---

### When to Seed

**Trigger**: Account creation (on first sign-up or account creation)

**Location**: Cloud Function or client-side account setup flow

**Idempotency**: Check if categories already exist before seeding (prevent duplicates)

---

## Language & Labeling

### Category Name Display

**Format**:
- General/Itemized: Append " Budget" suffix (e.g., "Furnishings Budget")
- Fee: No suffix (e.g., "Design Fee")
- Overall: "Overall Budget" (no transformation)

**Implementation**:
```typescript
function getDisplayName(category: BudgetCategory | "overall"): string {
  if (category === "overall") return "Overall Budget";
  if (category.metadata?.categoryType === "fee") return category.name;
  return `${category.name} Budget`;
}
```

---

### Amount Labels

**Templates**:

| Category Type | Spent Label | Remaining Label | Over Label |
|---------------|-------------|-----------------|------------|
| General/Itemized | `$X spent` | `$Y remaining` | `$Z over` |
| Fee | `$X received` | `$Y remaining to receive` | `$Z over received` |

**Implementation**:
```typescript
function getAmountLabels(category: BudgetCategory, spent: number, budget: number) {
  const isFee = category.metadata?.categoryType === "fee";
  const remaining = budget - spent;
  const isOver = spent > budget;

  if (isFee) {
    return {
      spent: `$${formatCurrency(spent)} received`,
      remaining: isOver
        ? `$${formatCurrency(Math.abs(remaining))} over received`
        : `$${formatCurrency(remaining)} remaining to receive`
    };
  } else {
    return {
      spent: `$${formatCurrency(spent)} spent`,
      remaining: isOver
        ? `$${formatCurrency(Math.abs(remaining))} over`
        : `$${formatCurrency(remaining)} remaining`
    };
  }
}
```

---

### Button Labels

| Action | Label |
|--------|-------|
| Expand budget | "Show All Budget Categories" |
| Collapse budget | "Show Less" |
| Add category | "+ Add Category" |
| Enable categories | "+ Enable More Categories" |
| Archive category | "Archive" |
| Unarchive category | "Unarchive" |
| Pin category | "Pin to Top" |
| Unpin category | "Unpin" |

---

### Empty State Messages

| State | Message | Action |
|-------|---------|--------|
| No categories (account) | "No budget categories created yet" | "Create Your First Category" |
| No enabled categories (project) | "No budget categories enabled for this project" | "Set Budget" |
| No pinned categories | "Pin categories to customize this view" | "View All" |
| All categories archived | "All categories are archived. Unarchive or create new categories to track budgets." | "Manage Categories" |

---

## Acceptance Criteria

### Budget Progress Display

- [ ] Budget module renders from local Firestore cache (no network required)
- [ ] Collapsed view shows pinned categories only
- [ ] Collapsed view falls back to Overall Budget if no pins
- [ ] Expanded view shows all enabled categories + Overall Budget
- [ ] Toggle button shows "Show All" / "Show Less" with icons
- [ ] Toggle button hidden if no additional categories beyond pins
- [ ] Progress bars use correct colors (green/yellow/red thresholds)
- [ ] Progress bars show overflow indicator (dark red) if >100%
- [ ] Fee categories use reversed color logic (green = high %)
- [ ] Fee categories show "received" language instead of "spent"
- [ ] Fee categories positioned last in list
- [ ] Overall Budget excluded from collapsed view
- [ ] Overall Budget shown in expanded view only
- [ ] Categories sorted: pinned → custom order → alphabetical → fees
- [ ] Canceled transactions excluded from all calculations
- [ ] Transactions in `excludeFromOverallBudget` categories excluded from overall totals

### Budget Category Management

- [ ] Settings screen lists all active categories
- [ ] Drag-and-drop reordering works (or up/down buttons on mobile)
- [ ] Reorder persists to `AccountPresets.budgetCategoryOrder`
- [ ] Add category flow validates name uniqueness
- [ ] Add category flow prevents itemized + fee simultaneously
- [ ] Edit category flow pre-fills current values
- [ ] Edit category flow validates on save
- [ ] Archive category flow shows confirmation with transaction count
- [ ] Archive category flow hides category from forms and displays
- [ ] Archived section toggles to show/hide archived categories
- [ ] Unarchive flow restores category to active list
- [ ] Default category dropdown sets `AccountPresets.defaultBudgetCategoryId`
- [ ] Transaction form pre-selects default category

### Project Budget Form

- [ ] Total budget displays auto-calculated sum
- [ ] Total budget updates live as category amounts change
- [ ] Category inputs formatted as currency
- [ ] Category inputs validate non-negative
- [ ] Grid is 2 columns on tablet/desktop, 1 column on mobile
- [ ] Enable more categories button opens selection modal
- [ ] Enabling category creates `ProjectBudgetCategory` doc
- [ ] Save persists all category budgets
- [ ] Save removes categories that user disabled
- [ ] Success message shown on save
- [ ] Budget display updates immediately after save (Firestore listener)

### Pinning

- [ ] User can pin/unpin categories (swipe, long-press, or menu)
- [ ] Pinning persists to `ProjectPreferences.pinnedBudgetCategoryIds`
- [ ] Pinning is per-user, per-project
- [ ] Pinned categories appear in collapsed view
- [ ] Pinned order matches array order
- [ ] First-time user has Furnishings pinned by default (if enabled)
- [ ] Pinned category deleted/archived: removed from collapsed view

### Fee Categories

- [ ] Fee categories identified by `categoryType === "fee"`
- [ ] Fee categories show "received" not "spent"
- [ ] Fee categories use reversed color thresholds
- [ ] Fee categories excluded from overall by default (when `excludeFromOverallBudget = true`)
- [ ] Cannot create category that is both fee and itemized
- [ ] Fee category title shown without " Budget" suffix

### Mobile

- [ ] Touch targets minimum 44pt height
- [ ] Swipe gestures work for pin/unpin
- [ ] Drag-and-drop has mobile alternative (long-press or buttons)
- [ ] Budget form uses 1-column layout on mobile
- [ ] Input fields use 16px font to prevent zoom
- [ ] Responsive spacing adjusts for small screens

### Offline

- [ ] Budget displays render offline from Firestore cache
- [ ] Offline indicator shown when disconnected
- [ ] Changes persist offline, sync on reconnect
- [ ] No errors when offline (graceful degradation)
- [ ] Transaction count aggregation shows cached value or "N/A" offline

### Default Categories

- [ ] Four default categories seeded on account creation
- [ ] Furnishings has `categoryType = "itemized"`
- [ ] Design Fee has `categoryType = "fee"` and `excludeFromOverallBudget = true`
- [ ] Install and Storage have `categoryType = "general"`
- [ ] Furnishings set as default category

### Validation & Edge Cases

- [ ] Cannot delete category with transactions (archive only)
- [ ] Cannot create duplicate category names (case-insensitive)
- [ ] Empty state messages shown when no categories
- [ ] Empty state messages shown when no pins
- [ ] Budget amounts validated as non-negative
- [ ] Budget amounts capped at maximum ($21M)
- [ ] Invalid `budgetCategoryId` in transaction handled gracefully

---

## Future Enhancements (Out of Scope for MVP)

- Budget alerts/notifications (e.g., "Furnishings 90% spent")
- Budget templates (copy budget from previous project)
- Budget history/versioning (track changes over time)
- Budget forecasting (predict spending based on current rate)
- Multi-currency budget support
- Budget approval workflows (require approval before exceeding)
- Budget category groups/hierarchies
- Custom color coding per category
- Budget vs actual variance reporting
- Export budget data to CSV/PDF

---

## Related Specifications

- [Data Contracts](../plans/firebase-mobile-migration/20_data/data_contracts.md)
- [Project Transactions](../plans/firebase-mobile-migration/40_features/project-transactions/feature_spec.md)
- [Project Items](../plans/firebase-mobile-migration/40_features/project-items/feature_spec.md)
- [Inventory Operations](../plans/firebase-mobile-migration/40_features/inventory-operations-and-lineage/feature_spec.md)
- [Reports & Printing](../plans/firebase-mobile-migration/40_features/reports-and-printing/feature_spec.md)

---

**End of Specification**
