# Reassign: Disambiguating Non-Sale Scope Changes from Sell

> **Goal:** Replace "Move" with "Reassign" for non-sale project-scope changes, eliminating confusion with "Sell". All other actions (space, transaction link, etc.) remain standard menu items — no new conceptual framework needed.

## 1. Problem Statement

The legacy web app has two ways to change an item's project scope:

| Action | Intent | Creates canonical transactions? |
|--------|--------|-------------------------------|
| **Sell** | Business operation — transfer item between scopes with financial tracking | Yes (INV_SALE / INV_PURCHASE) |
| **Move** | Fix a misallocation — direct field update, no financial records | No |

"Move" and "Sell" appeared side by side in menus. Users couldn't tell them apart. The word "Move" gives no hint about *why* it's different from "Sell."

### 1.1 Why "Reassign" Instead of "Correct"

We considered a "Correct" framing but rejected it because:
- It implies the user made a mistake, which feels judgmental
- It creates an artificial category that pulls in unrelated actions (space changes, transaction links) that are really just normal editing
- No user would confuse "Assign to Space" with "Sell" — the overlap is **only** with project-scope changes

"Reassign" is neutral, descriptive, and clearly different from "Sell."

### 1.2 Scope of This Spec

**In scope (Reassign):** Non-sale project-scope changes for items and transactions.

**Out of scope (unchanged):** Space assignment, transaction linking/unlinking, budget category changes. These are standard editing actions — they stay where they are, no reframing needed.

## 2. The Two Project-Scope Actions

Users need two distinct ways to change an item or transaction's project scope. Both need to exist, and users need to pick the right one.

### Sell (existing, unchanged)
- Creates canonical INV_SALE / INV_PURCHASE transaction records
- Used when the transfer is a real business event that should be tracked financially
- Example: Business inventory item is purchased for use in a project

### Reassign (replacing "Move")
- Direct field update, no canonical transactions created
- Used when the original scope was wrong — data entry correction
- Example: Item was accidentally created in Project A but belongs in Project B

## 3. Confirmation Dialogs

Both Sell and Reassign should present confirmation dialogs that give users the context they need to choose correctly. This is where the distinction is made clear — not through menu naming alone, but at decision time.

### 3.1 Reassign Confirmation

When a user selects a Reassign action, the confirmation dialog should explain what will (and won't) happen:

**Reassign item to Inventory:**
```
Reassign to Inventory?

This item will be moved to business inventory.
No sale or purchase records will be created.

Use this to fix items that were added to the wrong project.
If this is a real business transfer, use Sell instead.

[Cancel]  [Reassign]
```

**Reassign item to [Project Name]:**
```
Reassign to [Project Name]?

This item will be moved directly to [Project Name].
No sale or purchase records will be created.

Use this to fix items that were added to the wrong project.
If this is a real business transfer, use Sell instead.

[Cancel]  [Reassign]
```

**Reassign transaction to [Project Name]:**
```
Reassign to [Project Name]?

This transaction and all its items will be moved to [Project Name].
No sale or purchase records will be created.

[Cancel]  [Reassign]
```

### 3.2 Sell Confirmation

Sell confirmations should similarly clarify what happens:

**Sell item to Inventory:**
```
Sell to Inventory?

This item will be moved to business inventory.
A sale record will be created for financial tracking.

If you're just fixing a misallocation, use Reassign instead.

[Cancel]  [Sell]
```

**Sell item to [Project Name]:**
```
Sell to [Project Name]?

This item will be transferred to [Project Name].
Sale and purchase records will be created for financial tracking.

If you're just fixing a misallocation, use Reassign instead.

[Cancel]  [Sell]
```

### 3.3 Design Notes for Confirmations
- The "use X instead" hint is a soft nudge, not a blocker — users may have legitimate reasons for either choice
- Keep the language simple; avoid jargon like "canonical transactions"
- The dialog should be brief enough to scan quickly but informative enough that a user who doesn't know the difference can make the right call

## 4. Menu Structure

### 4.1 Info Tooltips on Menu Labels

Both "Sell" and "Reassign" should have a small info icon `(i)` next to them in the menu. Tapping the icon shows a brief tooltip — this way users can learn the difference without committing to an action.

| Menu Label | Tooltip Text |
|-----------|-------------|
| **Sell** `(i)` | "Creates sale and purchase records for financial tracking." |
| **Reassign** `(i)` | "Moves the item directly — no sale or purchase records. Use this to fix a misallocation." |

**Design notes:**
- The `(i)` icon should be subtle (secondary color, small) so it doesn't clutter the menu
- Tooltip could be a small popover or inline expansion below the label
- After a user has seen the tooltip a few times, they'll internalize the difference and stop tapping it — so it shouldn't be intrusive

### 4.2 Item Detail Screen

```
Menu:
├── Edit
├── Sell (i) ▸
│   ├── Sell to Inventory              (if item is in a project)
│   └── Sell to Project                (always, excludes current project)
│       → Project picker → Sell confirmation
├── Reassign (i) ▸
│   ├── Reassign to Inventory          (if item is in a project AND no transaction link)
│   └── Reassign to Project            (if item is in a project AND no transaction link)
│       → Project picker → Reassign confirmation
├── Link to Transaction                (if no transactionId — standard action)
├── Unlink from Transaction            (if has transactionId — standard action)
├── [Space actions as normal]
└── Delete
```

**When is Reassign hidden?** When the item is already in inventory (nothing to reassign) or when the item is linked to a transaction (must unlink first, or reassign the transaction instead).

**When is Reassign disabled with explanation?** When item has a transaction link — show: "Unlink from transaction first, or reassign the transaction instead."

### 4.3 Transaction Detail Screen

```
Menu:
├── Edit
├── Reassign ▸
│   ├── Reassign to Project            (if non-canonical transaction)
│   │   → Project picker → Reassign confirmation
│   └── Reassign to Inventory          (if in a project AND non-canonical)
│       → Reassign confirmation
└── Delete
```

**Not available for:** Canonical transactions (INV_SALE_*, INV_PURCHASE_*). These are system-generated — show: "Canonical sale/purchase transactions cannot be reassigned."

**Note:** Transactions don't have a "Sell" equivalent — you sell *items*, not transactions. So there's no Sell/Reassign confusion on the transaction detail screen. We use "Reassign" here for consistency with the item-level terminology.

### 4.4 Bulk Actions (SharedItemsList)

**Project scope:**
```
Bulk actions:
├── Sell ▸
│   ├── Sell to Inventory
│   └── Sell to Project
└── Reassign ▸
    ├── Reassign to Inventory
    └── Reassign to Project
```

**Inventory scope:**
```
Bulk actions:
└── Sell ▸
    └── Sell to Project
```
(No Reassign in inventory scope — items are already unallocated.)

**Transaction-linked items:** If any selected items have transaction links, Reassign options are disabled with a count: "N items are linked to transactions and cannot be reassigned."

## 5. Gap Analysis

### 5.1 Not yet implemented

| Capability | Priority | Complexity | Notes |
|-----------|----------|-----------|-------|
| **Reassign item to project** | High | Medium | Direct `projectId` update + clear txn/space. Needs project picker. Exists in legacy. |
| **Reassign transaction to project** | High | High | Must update transaction + all child items. Needs project picker. Canonical txn guard. Currently stubbed ("coming soon"). |
| **Reassign transaction to inventory** | High | Medium | Subset of above (target = null). Currently stubbed. |
| **Confirmation dialogs for Sell** | Medium | Low | Add confirmation with "use Reassign instead" hint to existing Sell flows. |
| **Confirmation dialogs for Reassign** | Medium | Low | Add confirmation with "use Sell instead" hint. |

### 5.2 Already implemented (rename only)

| Capability | Current Location | Change |
|-----------|-----------------|--------|
| Move item to inventory | Item detail → Move → Move to Inventory | Rename to "Reassign to Inventory", add confirmation dialog |

### 5.3 Unchanged

| Capability | Notes |
|-----------|-------|
| Sell flows (all three: to business, to project, project-to-project) | Keep as-is, add confirmation dialogs |
| Space actions (assign, move, remove) | Standard menu actions, no reframing |
| Transaction link/unlink | Standard menu actions, no reframing |
| Budget category changes | Edit flow, no reframing |

## 6. Implementation Details

### 6.1 Reassign Service Functions (new file: `src/data/reassignService.ts`)

Create a dedicated service file for reassign operations. This keeps the logic testable and separate from the existing item/transaction services.

```typescript
import { updateItem } from './itemsService';
import { updateTransaction } from './transactionsService';
import type { Item } from './itemsService';
import type { Transaction } from './transactionsService';

// --- Validation (pure, testable) ---

export type ReassignValidationResult =
  | { valid: true }
  | { valid: false; error: string };

export function validateItemReassign(
  item: Pick<Item, 'projectId' | 'transactionId'>,
  targetProjectId: string | null  // null = inventory
): ReassignValidationResult {
  if (item.transactionId) {
    return { valid: false, error: 'This item is linked to a transaction. Unlink it first, or reassign the transaction instead.' };
  }
  if (!item.projectId) {
    return { valid: false, error: 'This item is already in inventory.' };
  }
  if (targetProjectId && item.projectId === targetProjectId) {
    return { valid: false, error: 'Item is already in this project.' };
  }
  return { valid: true };
}

export function validateTransactionReassign(
  transaction: Pick<Transaction, 'projectId' | 'isCanonicalInventory'>,
  targetProjectId: string | null
): ReassignValidationResult {
  if (transaction.isCanonicalInventory) {
    return { valid: false, error: 'Sale/purchase transactions cannot be reassigned.' };
  }
  if (targetProjectId === null && !transaction.projectId) {
    return { valid: false, error: 'This transaction is already in inventory.' };
  }
  if (targetProjectId && transaction.projectId === targetProjectId) {
    return { valid: false, error: 'Transaction is already in this project.' };
  }
  return { valid: true };
}

// --- Execution (fire-and-forget, uses existing services) ---

export function reassignItemToInventory(accountId: string, itemId: string): void {
  updateItem(accountId, itemId, { projectId: null, transactionId: null, spaceId: null });
}

export function reassignItemToProject(accountId: string, itemId: string, targetProjectId: string): void {
  updateItem(accountId, itemId, { projectId: targetProjectId, transactionId: null, spaceId: null });
}

export function reassignTransactionToProject(
  accountId: string,
  transactionId: string,
  targetProjectId: string,
  itemIds: string[]
): void {
  updateTransaction(accountId, transactionId, { projectId: targetProjectId });
  for (const itemId of itemIds) {
    updateItem(accountId, itemId, { projectId: targetProjectId, spaceId: null });
  }
}

export function reassignTransactionToInventory(
  accountId: string,
  transactionId: string,
  itemIds: string[]
): void {
  updateTransaction(accountId, transactionId, { projectId: null });
  for (const itemId of itemIds) {
    updateItem(accountId, itemId, { projectId: null, spaceId: null });
  }
}
```

**Design rationale:**
- Validation functions are **pure** — no Firebase, no side effects, fully unit-testable
- Execution functions delegate to existing `updateItem`/`updateTransaction` which already handle `trackPendingWrite()` and fire-and-forget semantics
- `itemIds` is passed to transaction reassign (not queried internally) because the caller already has the items from the UI state — avoids an unnecessary read

### 6.2 Item Detail Screen Changes (`app/items/[id]/index.tsx`)

**Current state (lines 413-420):**
```typescript
items.push({
  label: 'Move',
  icon: 'swap-horiz',
  actionOnly: true,
  subactions: [
    { key: 'move-to-inventory', label: 'Move to Inventory', onPress: handleMoveToInventoryCorrection, icon: 'inventory' },
  ],
});
```

**Replace with:**
```typescript
items.push({
  label: 'Reassign',
  icon: 'swap-horiz',
  actionOnly: true,
  subactions: [
    { key: 'reassign-to-inventory', label: 'Reassign to Inventory', onPress: handleReassignToInventory, icon: 'inventory' },
    { key: 'reassign-to-project', label: 'Reassign to Project', onPress: () => setReassignToProjectVisible(true), icon: 'assignment' },
  ],
});
```

**Existing handler to update (lines 272-279):**
`handleMoveToInventoryCorrection` → rename to `handleReassignToInventory`, add `Alert.alert` confirmation dialog before calling `reassignItemToInventory()`.

**New handler:**
`handleReassignToProject` — opens a project picker bottom sheet (reuse `ProjectSelector` component already at `src/components/ProjectSelector.tsx`), then shows confirmation dialog, then calls `reassignItemToProject()`.

**Visibility gating:** The Reassign menu item is only pushed when `scope !== 'inventory'` (same gate as current Move — line 403). No change needed for that condition.

### 6.3 Transaction Detail Screen Changes (`app/transactions/[id]/index.tsx`)

**Current state (lines 1004-1029):** Menu only has Edit and Delete.

**Add Reassign submenu** between Edit and Delete:
```typescript
// Only for non-canonical transactions
if (!transaction?.isCanonicalInventory) {
  items.push({
    label: 'Reassign',
    icon: 'swap-horiz',
    actionOnly: true,
    subactions: [
      ...(transaction?.projectId ? [{
        key: 'reassign-to-inventory',
        label: 'Reassign to Inventory',
        onPress: handleReassignToInventory,
        icon: 'inventory' as MenuIconName,
      }] : []),
      {
        key: 'reassign-to-project',
        label: 'Reassign to Project',
        onPress: () => setReassignToProjectVisible(true),
        icon: 'assignment' as MenuIconName,
      },
    ],
  });
}
```

**New handlers needed:**
- `handleReassignToInventory` — confirmation dialog → `reassignTransactionToInventory(accountId, id, itemIds)`
- `handleReassignToProject` — project picker → confirmation dialog → `reassignTransactionToProject(accountId, id, targetProjectId, itemIds)`

**Item IDs source:** The transaction detail screen already has the linked items loaded (used for the items section). Extract `itemIds` from the existing `items` or `linkedItems` state.

**Also update per-item context menu (lines 746-837):** Replace the stubbed `handleMoveToDesign` / `handleMoveToProject` (lines 701-717) with real handlers that call the reassign service. Rename labels from "Move to Design Business" → "Reassign to Inventory" and "Move to Project" → "Reassign to Project".

### 6.4 SharedItemsList Bulk Actions (`src/components/SharedItemsList.tsx`)

**Current state (lines 782-846):** `standaloneBulkMenuItems` only has Sell and Delete.

**Add Reassign bulk actions** for project scope:
```typescript
if (scopeConfig.scope === 'project') {
  items.push({
    key: 'reassign',
    label: 'Reassign',
    icon: 'swap-horiz',
    actionOnly: true,
    subactions: [
      {
        key: 'reassign-to-inventory',
        label: 'Reassign to Inventory',
        icon: 'inventory',
        onPress: () => setReassignToInventoryVisible(true),
      },
      {
        key: 'reassign-to-project',
        label: 'Reassign to Project',
        icon: 'assignment',
        onPress: () => setReassignToProjectVisible(true),
      },
    ],
  });
}
```

**Bulk reassign handler pattern:**
1. Filter selected items: exclude any with `transactionId` (show count warning)
2. For "Reassign to Inventory": confirmation → loop `reassignItemToInventory()` for each eligible item
3. For "Reassign to Project": project picker → confirmation → loop `reassignItemToProject()` for each eligible item

### 6.5 Sell Confirmation Dialogs

Add `Alert.alert` confirmations to existing sell handlers. The sell flows already work — we're just wrapping them with a confirmation that mentions Reassign as an alternative.

**Item detail — `handleSellToInventory` (line 256):** Wrap in `Alert.alert` with the copy from section 3.2.

**Item detail — Sell to Project modal:** Add a confirmation step after the user picks a project and category, before the request is fired.

**SharedItemsList — bulk sell modals:** Add confirmation before executing.

## 7. UX Copy

| Context | Label | Confirmation | Success Toast |
|---------|-------|-------------|---------------|
| Item → Inventory | "Reassign to Inventory" | See 3.1 | "Reassigned to inventory" |
| Item → Project | "Reassign to [Project]" | See 3.1 | "Reassigned to [Project]" |
| Transaction → Project | "Reassign to [Project]" | See 3.1 | "Transaction reassigned to [Project]" |
| Transaction → Inventory | "Reassign to Inventory" | See 3.1 | "Transaction reassigned to inventory" |
| Error: has txn link | — | — | "This item is linked to a transaction. Unlink it first, or reassign the transaction instead." |
| Error: canonical txn | — | — | "Sale/purchase transactions cannot be reassigned." |

## 8. File Inventory

All files that will be created or modified, with the nature of each change:

| File | Action | What Changes |
|------|--------|-------------|
| `src/data/reassignService.ts` | **Create** | Validation functions + execution functions |
| `src/data/__tests__/reassignService.test.ts` | **Create** | Unit tests for validation + execution |
| `app/items/[id]/index.tsx` | **Modify** | Rename Move→Reassign, add Reassign to Project, add confirmation dialogs, add sell confirmations |
| `app/transactions/[id]/index.tsx` | **Modify** | Add Reassign submenu to top menu, implement stubbed per-item reassign handlers, add project picker state |
| `src/components/SharedItemsList.tsx` | **Modify** | Add Reassign bulk actions for project scope, add reassign modals/handlers |

**No changes to:**
- `src/data/itemsService.ts` — `updateItem` used as-is
- `src/data/transactionsService.ts` — `updateTransaction` used as-is
- `src/data/inventoryOperations.ts` — Sell flows unchanged (only confirmation wrappers added at call sites)
- `src/components/ProjectSelector.tsx` — reused as-is
- `src/data/scopeConfig.ts` — no new capabilities needed

## 9. Testing Strategy

### 9.1 Design for Testability

The key architectural decision is separating **validation** (pure functions) from **execution** (Firebase side effects). This means:

- Validation logic is fully unit-testable with zero mocking
- Execution functions are thin wrappers around existing tested services — integration-tested manually
- Menu visibility logic can be tested as pure functions if extracted

### 9.2 Unit Tests: `src/data/__tests__/reassignService.test.ts`

Tests for the pure validation functions. These run in the automated test loop (`npm test`) and catch logic errors without needing Firebase.

```typescript
// Test structure follows existing pattern from bulkSaleUtils.test.ts

describe('validateItemReassign', () => {
  // Happy paths
  it('allows reassign when item is in project with no transaction', () => {});
  it('allows reassign to inventory (targetProjectId = null)', () => {});

  // Blocked states
  it('rejects when item has transactionId', () => {});
  it('rejects when item is already in inventory (no projectId)', () => {});
  it('rejects when target project matches current project', () => {});

  // Edge cases
  it('allows reassign when projectId differs from targetProjectId', () => {});
});

describe('validateTransactionReassign', () => {
  // Happy paths
  it('allows reassign for non-canonical transaction', () => {});
  it('allows reassign to inventory when transaction is in a project', () => {});

  // Blocked states
  it('rejects when transaction is canonical inventory', () => {});
  it('rejects when transaction is already in target project', () => {});
  it('rejects reassign-to-inventory when already in inventory', () => {});

  // Edge cases
  it('allows reassign when isCanonicalInventory is null/undefined', () => {});
  it('allows reassign when isCanonicalInventory is false', () => {});
});
```

### 9.3 Unit Tests: Menu Visibility Logic

Extract menu visibility predicates as pure functions (or test them inline):

```typescript
describe('Reassign menu visibility', () => {
  // Item detail
  it('shows Reassign when scope is project', () => {});
  it('hides Reassign when scope is inventory', () => {});

  // Transaction detail
  it('shows Reassign when transaction is not canonical', () => {});
  it('hides Reassign when transaction is canonical', () => {});
  it('hides Reassign to Inventory when transaction has no projectId', () => {});
});
```

### 9.4 Unit Tests: Bulk Reassign Filtering

```typescript
describe('Bulk reassign item filtering', () => {
  it('excludes items with transactionId', () => {});
  it('includes items without transactionId', () => {});
  it('returns correct count of excluded items for warning message', () => {});
});
```

### 9.5 TypeScript Compilation Check

Run `npx tsc --noEmit` after implementation to catch type errors. Known pre-existing errors to ignore:

- `__tests__/` files: missing `@types/jest` (actually installed but may show)
- `SharedItemsList.tsx`, `SharedTransactionsList.tsx`: icon type mismatches
- `resolveItemMove.ts`: variable shadowing (`budgetCategoryId`)
- `settings.tsx`: `BudgetCategoryType` union mismatch
- `accountContextStore.ts`: null handling

**Only new errors (not in the list above) should be treated as regressions.**

### 9.6 Automated Test Loop

The implementation agent should follow this loop after each file change:

```
1. Write/modify code
2. Run: npm test
3. If tests fail → fix and go to 2
4. Run: npx tsc --noEmit 2>&1 | grep -v '__tests__\|SharedItemsList\|SharedTransactionsList\|resolveItemMove\|settings\.tsx\|accountContextStore'
5. If new type errors → fix and go to 4
6. Proceed to next file
```

### 9.7 What Requires Manual Testing

These cannot be automated in the current test setup and require manual verification:

| Scenario | What to Check |
|----------|---------------|
| Reassign item to inventory | Item disappears from project, appears in inventory. No canonical transaction created. |
| Reassign item to project | Item disappears from source project, appears in target project. Space and transaction cleared. |
| Reassign transaction to project | Transaction and all items move to target project. Items' spaces cleared. |
| Reassign canonical transaction | "Cannot be reassigned" error shown. Action blocked. |
| Reassign item with transaction link | Error message shown. Action blocked. |
| Sell confirmation shows Reassign hint | Dialog includes "use Reassign instead" text. |
| Reassign confirmation shows Sell hint | Dialog includes "use Sell instead" text. |
| Bulk reassign with mixed selection | Transaction-linked items excluded with count warning. |
| Info tooltips | (i) icons render, tapping shows tooltip text. |

## 10. Open Questions

1. **Should Reassign be available from the transaction detail's per-item menu?** The legacy app allows item-level moves from within a transaction view. The mobile app has stubs for this ("coming soon"). If yes, the per-item kebab menu in transaction detail would show Reassign options.

2. **Reassign item from inventory to project?** An item in business inventory could be "reassigned" into a project without canonical transactions. Is this a valid use case (fixing an item that was accidentally created in inventory instead of a project), or should all inventory→project transitions go through Sell?

3. **Bulk reassign for transactions?** Should users be able to bulk-reassign multiple transactions at once, or is transaction reassignment rare enough to be item-by-item only?
