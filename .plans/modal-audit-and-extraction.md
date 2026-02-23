# Modal Audit & Reusable Component Extraction

## A. Audit Results — Action × Screen Matrix

### Legend
- **OK** = handler exists, modal/picker present where needed, fire-and-forget compliant
- **STUB** = menu item exists but handler is a placeholder (shows "coming soon" alert)
- **MISSING** = action not available in this context
- **ISSUE** = something broken or non-compliant (details in Issues section)
- N/A = action doesn't make sense in this context

| Action | Item Detail | Txn Per-Item | Txn Bulk | Items List Bulk | Space Per-Item | Space Bulk |
|---|---|---|---|---|---|---|
| **Set Transaction** | OK (text input) | N/A | N/A | OK (TextInput modal) | MISSING | MISSING |
| **Clear Transaction** | OK (inline) | OK (inline) | OK (Alert) | OK (inline) | MISSING | MISSING |
| **Set Space** | OK (SpaceSelector) | OK (SpaceSelector) | OK (SpaceSelector) | OK (SpaceSelector) | N/A | N/A |
| **Clear Space** | OK (inline) | OK (inline) | OK (inline) | OK (inline) | OK ("Remove") | OK (Alert) |
| **Set Status** | OK (header pill) | OK (submenu) | OK (menu picker) | MISSING | MISSING | MISSING |
| **Set SKU** | MISSING | MISSING | OK (TextInput) | MISSING | MISSING | MISSING |
| **Sell to Business** | OK (Alert) | STUB | MISSING | OK (modal) | MISSING | MISSING |
| **Sell to Project** | OK (ProjectSelector + cat pickers) | STUB | MISSING | OK (ProjectSelector + cat pickers) | MISSING | MISSING |
| **Reassign to Inventory** | OK (Alert) | OK (Alert) | MISSING | OK (modal) | MISSING | MISSING |
| **Reassign to Project** | OK (ProjectSelector) | OK (ProjectSelector) | MISSING | OK (ProjectSelector) | MISSING | MISSING |
| **Move to Space** | MISSING | MISSING | MISSING | MISSING | N/A | OK (SpaceSelector) |
| **Delete** | OK (Alert) | OK (Alert) | OK (Alert) | OK (inline) | MISSING | OK (Alert) |

---

### Issues Found

#### 1. Transaction detail: Sell to Business & Sell to Project are stubs
**File:** `app/transactions/[id]/index.tsx`
**Lines:** ~704-720
**Problem:** `handleSellToDesign()` and `handleSellToProject()` show "coming soon" alerts instead of functional modals.
**Fix:** Implement proper modals using the extracted `SellToProjectModal` / `SellToBusinessModal` components (see Part B).

#### 2. Item detail: "Set Transaction" has no visible text input UI
**File:** `app/items/[id]/index.tsx`
**Lines:** 93, 134, 179-193
**Problem:** `transactionId` state exists and `handleLinkTransaction()` reads from it, but there is no `<TextInput>` in the JSX for users to enter a new transaction ID. The state is initialized from `item.transactionId` (the current value). The menu action "Set Transaction" calls the handler directly — but the user has no way to type a new ID.
**Fix:** Add a `SetTransactionModal` (BottomSheet + TextInput) matching the pattern already in SharedItemsList.

#### 3. SharedItemsList `handleBulkSetTransaction` — await on `getTransaction` is acceptable
**File:** `src/components/SharedItemsList.tsx`, line 812
**Note:** The `await getTransaction(accountId, trimmed, 'offline')` is a cache-first *read* for validation, not a Firestore write. This is explicitly allowed by the offline-first rules: "Read operations in save/submit handlers must use cache-first mode." The `updateItem()` calls that follow are properly fire-and-forget. No issue.

#### 4. Transaction detail: per-item Reassign and Delete handlers may be awaited
**File:** `app/transactions/[id]/index.tsx`
**Problem:** `reassignItemToInventory`, `reassignItemToProject`, `deleteItem` appear to be awaited in some handlers. These should be fire-and-forget per offline-first rules.
**Action:** Verify and fix if awaited.

#### 5. SpaceDetailContent: missing `trackPendingWrite()` calls
**File:** `src/components/SpaceDetailContent.tsx`
**Problem:** Inline `updateItem()` and `deleteItem()` calls don't include `trackPendingWrite()`.
**Action:** Add after each write (or fix at the service layer if it's already handled there).

#### 6. SpaceDetailContent: redundant bulk actions definition
**File:** `src/components/SpaceDetailContent.tsx`, lines 677-736 and 1003-1063
**Problem:** Bulk actions are defined in two places — once as a `bulkActions` array prop and once inline in a `BottomSheetMenuList`. These should be consolidated.

---

## B. Reusable Components to Extract

### 1. `SetTransactionModal`

**Location:** `src/components/modals/SetTransactionModal.tsx`

**What it encapsulates:**
- BottomSheet with TextInput for transaction ID
- Validation via `getTransaction(accountId, id, 'offline')`
- Error handling (inline or Alert)
- Input state management

**Props Interface:**
```typescript
interface SetTransactionModalProps {
  visible: boolean;
  onRequestClose: () => void;
  accountId: string;
  /** Called with validated transaction. Caller does the updateItem(s). */
  onConfirm: (transaction: { id: string; budgetCategoryId?: string }) => void;
  /** Optional label like "3 items selected" */
  subtitle?: string;
}
```

**Component owns:** `inputValue` state, validation call, error state, loading state during validation
**Caller provides:** `onConfirm` callback (single-item: `updateItem(accountId, itemId, ...)`; bulk: `selectedIds.forEach(...)`)

**Callsites to refactor:**
| Screen | Current Implementation | After |
|---|---|---|
| Item detail kebab | No UI (broken) — needs new modal | `<SetTransactionModal onConfirm={...} />` |
| SharedItemsList bulk | Inline BottomSheet + TextInput (~40 lines) | `<SetTransactionModal subtitle={`${count} items selected`} onConfirm={...} />` |

---

### 2. `SetSpaceModal`

**Location:** `src/components/modals/SetSpaceModal.tsx`

**What it encapsulates:**
- BottomSheet wrapping SpaceSelector
- Optional item count label
- Confirm/cancel flow

**Props Interface:**
```typescript
interface SetSpaceModalProps {
  visible: boolean;
  onRequestClose: () => void;
  projectId: string | null;
  /** Called with selected spaceId. Caller does the updateItem(s). */
  onConfirm: (spaceId: string) => void;
  /** Optional label like "3 items selected" */
  subtitle?: string;
  /** Title override — default "Set Space" */
  title?: string;
}
```

**Component owns:** Selected space state, confirmation flow
**Caller provides:** `onConfirm` callback

**Callsites to refactor:**
| Screen | Current Implementation | After |
|---|---|---|
| Item detail | Inline BottomSheet + SpaceSelector | `<SetSpaceModal onConfirm={...} />` |
| Txn per-item | Inline BottomSheet + SpaceSelector | `<SetSpaceModal onConfirm={...} />` |
| Txn bulk | Inline BottomSheet + SpaceSelector | `<SetSpaceModal subtitle={...} onConfirm={...} />` |
| SharedItemsList bulk | Inline BottomSheet + SpaceSelector | `<SetSpaceModal subtitle={...} onConfirm={...} />` |
| SpaceDetail bulk ("Move") | Inline BottomSheet + SpaceSelector | `<SetSpaceModal title="Move to Another Space" subtitle={...} onConfirm={...} />` |

---

### 3. `ReassignToProjectModal`

**Location:** `src/components/modals/ReassignToProjectModal.tsx`

**What it encapsulates:**
- BottomSheet with description text
- ProjectSelector
- Blocked items warning (for bulk mode)
- Confirm button

**Props Interface:**
```typescript
interface ReassignToProjectModalProps {
  visible: boolean;
  onRequestClose: () => void;
  accountId: string;
  /** Current project to exclude from selector */
  excludeProjectId?: string;
  /** Called with target projectId. Caller does the reassign operation(s). */
  onConfirm: (targetProjectId: string) => void;
  /** Optional description override */
  description?: string;
  /** For bulk: show eligible/blocked counts */
  bulkInfo?: {
    eligibleCount: number;
    blockedCount: number;
  };
}
```

**Component owns:** `targetProjectId` selection state, confirm button disabled logic
**Caller provides:** `onConfirm`, optional `bulkInfo` (caller runs `filterItemsForBulkReassign`)

**Callsites to refactor:**
| Screen | Current Implementation | After |
|---|---|---|
| Item detail | Inline BottomSheet + ProjectSelector (~30 lines) | `<ReassignToProjectModal onConfirm={...} />` |
| Txn per-item | Inline BottomSheet + ProjectSelector | `<ReassignToProjectModal onConfirm={...} />` |
| Txn transaction-level | Inline BottomSheet + ProjectSelector | `<ReassignToProjectModal onConfirm={...} />` |
| SharedItemsList bulk | Inline BottomSheet + ProjectSelector + blocked warning (~50 lines) | `<ReassignToProjectModal bulkInfo={...} onConfirm={...} />` |

---

### 4. `SellToProjectModal`

**Location:** `src/components/modals/SellToProjectModal.tsx`

**What it encapsulates:**
- BottomSheet with ProjectSelector
- Source category picker (when items lack budgetCategoryId)
- Destination category picker (when target project needs category assignment)
- Confirm button with validation

**Props Interface:**
```typescript
interface SellToProjectModalProps {
  visible: boolean;
  onRequestClose: () => void;
  accountId: string;
  excludeProjectId?: string;
  /** Budget categories for destination project — loaded when target changes */
  destBudgetCategories: Record<string, { name: string }>;
  /** Budget categories for source project (for uncategorized items) */
  sourceBudgetCategories: Record<string, { name: string }>;
  /** Whether to show the source category picker */
  needsSourceCategory: boolean;
  /** Whether to show the destination category picker */
  needsDestCategory: boolean;
  /** Called with all selections. Caller does the sale operation(s). */
  onConfirm: (params: {
    targetProjectId: string;
    destCategoryId: string | null;
    sourceCategoryId: string | null;
  }) => void;
  /** Optional count label */
  subtitle?: string;
  /** Callback when target project changes — caller loads dest budget categories */
  onTargetProjectChange?: (projectId: string | null) => void;
}
```

**Component owns:** `targetProjectId`, `destCategoryId`, `sourceCategoryId` selection states, category picker rendering
**Caller provides:** Budget category data, `needsSourceCategory`/`needsDestCategory` flags, `onConfirm`

**Callsites to refactor:**
| Screen | Current Implementation | After |
|---|---|---|
| Item detail | Inline BottomSheet + ProjectSelector + category pickers (~120 lines) | `<SellToProjectModal onConfirm={...} />` |
| SharedItemsList bulk | Inline BottomSheet + ProjectSelector + smart category detection (~140 lines) | `<SellToProjectModal subtitle={...} onConfirm={...} />` |
| Txn per-item (future) | Currently STUB | `<SellToProjectModal onConfirm={...} />` |

---

### 5. `SellToBusinessModal`

**Location:** `src/components/modals/SellToBusinessModal.tsx`

**What it encapsulates:**
- BottomSheet with description
- Source category picker (for uncategorized items)
- Confirm button

**Props Interface:**
```typescript
interface SellToBusinessModalProps {
  visible: boolean;
  onRequestClose: () => void;
  /** Budget categories for source category picker */
  sourceBudgetCategories: Record<string, { name: string }>;
  /** Whether to show the source category picker */
  needsSourceCategory: boolean;
  /** Called with source category. Caller does the sale operation. */
  onConfirm: (sourceCategoryId: string | null) => void;
  /** Optional count label */
  subtitle?: string;
}
```

**Callsites to refactor:**
| Screen | Current Implementation | After |
|---|---|---|
| Item detail | Alert.alert (no category picker) | Could keep as Alert for single item, or upgrade to modal for consistency |
| SharedItemsList bulk | Inline BottomSheet + category picker (~60 lines) | `<SellToBusinessModal subtitle={...} onConfirm={...} />` |

---

### 6. `CategoryPickerList` (Internal helper)

**Location:** `src/components/modals/CategoryPickerList.tsx`

**What it encapsulates:**
- ScrollView with selectable category rows (checkmark pattern)
- Consistent styling

**Props Interface:**
```typescript
interface CategoryPickerListProps {
  categories: Record<string, { name: string }>;
  selectedId: string | null;
  onSelect: (categoryId: string) => void;
  maxHeight?: number;
}
```

**Used internally by:** `SellToProjectModal`, `SellToBusinessModal`
**Replaces:** The duplicated `ScrollView > Pressable > AppText + checkmark` pattern that appears 5+ times across item detail and SharedItemsList.

---

## C. File-by-File Refactoring Plan

### Phase 1: Create shared modal components

| # | File to Create | Lines Saved (est.) |
|---|---|---|
| 1 | `src/components/modals/CategoryPickerList.tsx` | Foundation for other modals |
| 2 | `src/components/modals/SetTransactionModal.tsx` | ~40 lines per callsite |
| 3 | `src/components/modals/SetSpaceModal.tsx` | ~25 lines per callsite |
| 4 | `src/components/modals/ReassignToProjectModal.tsx` | ~35 lines per callsite |
| 5 | `src/components/modals/SellToProjectModal.tsx` | ~130 lines per callsite |
| 6 | `src/components/modals/SellToBusinessModal.tsx` | ~60 lines per callsite |

### Phase 2: Refactor existing screens

| # | File | Changes |
|---|---|---|
| 1 | `app/items/[id]/index.tsx` | Replace inline SpaceSelector BottomSheet → `SetSpaceModal`. Replace inline sell-to-project BottomSheet (~120 lines) → `SellToProjectModal`. Replace inline reassign-to-project BottomSheet → `ReassignToProjectModal`. **Add** `SetTransactionModal` (currently broken — no input UI). Remove ~5 state variables (`sellTargetProjectId`, `sellDestCategoryId`, `sellSourceCategoryId`, `reassignTargetProjectId`). Net: **~-200 lines**. |
| 2 | `src/components/SharedItemsList.tsx` | Replace inline set-transaction BottomSheet → `SetTransactionModal`. Replace inline set-space BottomSheet → `SetSpaceModal`. Replace inline sell-to-business BottomSheet → `SellToBusinessModal`. Replace inline sell-to-project BottomSheet → `SellToProjectModal`. Replace inline reassign-to-inventory BottomSheet → `ReassignToInventoryModal` (simple confirmation variant of ReassignToProjectModal, or just keep Alert). Replace inline reassign-to-project BottomSheet → `ReassignToProjectModal`. Remove ~10 state variables. Net: **~-350 lines** from a 2000+ line file. |
| 3 | `app/transactions/[id]/index.tsx` | Replace inline single-item SpaceSelector BottomSheet → `SetSpaceModal`. Replace inline single-item reassign ProjectSelector → `ReassignToProjectModal`. Replace inline transaction-level reassign ProjectSelector → `ReassignToProjectModal`. Replace inline bulk SpaceSelector → `SetSpaceModal`. **Upgrade** sell stubs to use `SellToProjectModal` / `SellToBusinessModal`. Net: **~-100 lines** + sell actions become functional. |
| 4 | `src/components/SpaceDetailContent.tsx` | Replace inline bulk-move SpaceSelector → `SetSpaceModal title="Move to Another Space"`. Consolidate redundant bulk actions definitions. **Add** missing actions (see Part D). Net: modest line reduction + feature parity. |

### Phase 3: Fix issues

| # | Issue | File | Fix |
|---|---|---|---|
| 1 | Item detail Set Transaction broken | `app/items/[id]/index.tsx` | Add `SetTransactionModal` + visibility state + wire to menu |
| 2 | Txn detail sell stubs | `app/transactions/[id]/index.tsx` | Replace Alert stubs with `SellToProjectModal` / `SellToBusinessModal` |
| 3 | Txn detail fire-and-forget violations | `app/transactions/[id]/index.tsx` | Remove `await` from reassign/delete handlers |
| 4 | Space detail missing `trackPendingWrite` | `src/components/SpaceDetailContent.tsx` | Add after writes (or verify service layer handles it) |
| 5 | Space detail redundant bulk actions | `src/components/SpaceDetailContent.tsx` | Consolidate to single definition |

---

## D. Space Detail Recommendations

### Actions to Add

| Action | Add? | Justification |
|---|---|---|
| **Set Transaction** (bulk) | YES | Items in a space still belong to transactions. Users should be able to bulk-link items to a transaction without leaving the space view. Common workflow: receive items into a space, then batch-link to transaction. |
| **Clear Transaction** (bulk) | YES | Counterpart to Set Transaction. |
| **Set Status** (per-item + bulk) | YES | Status is fundamental item metadata. No reason to force users to navigate away to change it. Low implementation cost. |
| **Sell to Business** (bulk) | YES (project scope only) | Items in a space can be sold. Forcing navigation to items list is friction. |
| **Sell to Project** (bulk) | YES | Same rationale — space is just a physical location grouping, doesn't change what operations are valid. |
| **Reassign to Inventory** (bulk) | YES (project scope only) | Items in a space within a project should be reassignable to inventory. |
| **Reassign to Project** (bulk) | YES | Items in a space should be movable to another project. |
| **Delete** (per-item) | YES | Currently only available as bulk. Per-item delete via long-press menu is consistent with other screens. |
| **Set SKU** (bulk) | NO | SKU is a niche operation, only needed in transaction bulk context. Not worth the menu clutter in space view. |
| **View/Edit** (per-item) | ALREADY EXISTS | "Open" navigates to item detail where editing happens. |

### Implementation Approach for Space Detail

SpaceDetailContent already uses `SharedItemsList` in embedded mode with custom `bulkActions` and `getItemMenuItems`. Adding actions means:

1. **Per-item menu:** Extend `getItemMenuItems` to include Status submenu, Delete (with Alert), and optionally Transaction/Sell/Reassign submenus.
2. **Bulk actions:** Extend the `bulkActions` array to include Set Transaction, Clear Transaction, Set Status, Sell, Reassign, and pass the shared modal components.
3. **Modals:** Since modals are now extracted components, SpaceDetailContent just needs to:
   - Add visibility state for each new modal
   - Render the modal component with appropriate props
   - Wire onConfirm to the appropriate update/service calls

This is dramatically simpler than the current pattern of building inline BottomSheet UIs. Each new action is ~10 lines (state + modal rendering + confirm handler) instead of ~40-130 lines.

---

## Implementation Order

1. **CategoryPickerList** — no dependencies, used by sell modals
2. **SetTransactionModal** — fixes broken item detail action
3. **SetSpaceModal** — highest duplication count (5 callsites)
4. **ReassignToProjectModal** — 4 callsites
5. **SellToProjectModal** — most complex, biggest line savings
6. **SellToBusinessModal** — 2 callsites
7. Refactor item detail screen (highest-value: fixes broken action + removes most inline code)
8. Refactor SharedItemsList (biggest file, most savings)
9. Refactor transaction detail (upgrades stubs to working features)
10. Extend SpaceDetailContent (add missing actions using new shared modals)
