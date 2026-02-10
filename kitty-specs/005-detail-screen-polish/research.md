# Phase 0 Research: Detail Screen Polish

**Feature**: 005-detail-screen-polish
**Date**: 2026-02-10
**Status**: Complete

## Overview

This document contains research findings for refactoring detail screens to use consistent item list patterns, fix regressions from feature 004, and normalize visual styling across transaction, item, and space detail screens.

## Research Questions

### Q1: How does SharedItemsList currently handle grouped items and bulk actions?

**Findings**:

**Component Location**: `src/components/SharedItemsList.tsx`

**Current Props Interface**:
```typescript
type SharedItemsListProps = {
  scopeConfig: ScopeConfig;
  listStateKey: string;
  refreshToken?: number;
};
```

**Grouping Pattern**:
- Detects duplicate items when `activeFilters.showDuplicates === false`
- Groups by composite key: `[name.toLowerCase(), sku, source].join('::').toLowerCase()`
- Renders `GroupedItemCard` for groups with >1 item
- Renders individual `ItemCard` for singles
- Stores collapse state via filters: `collapsed:{groupId}` → boolean

**Bulk Selection Pattern**:
- **Bottom bar**: Sticky at bottom, shows "{N} selected" count + "Clear" and "Bulk actions" buttons
- **Bottom sheet**: Opens when "Bulk actions" tapped, contains:
  - Move to space (with space selector)
  - Remove from space
  - Allocate to project (inventory scope only)
  - Sell to business (project scope only)
  - Delete items (with confirmation)

**Additional Features**:
- Search (by name, notes, source, space, SKU)
- Sort (created-desc/asc, alphabetical-asc/desc)
- Filters (bookmarked, from-inventory, to-return, returned, no-sku, no-name, no-project-price, no-image, no-transaction)
- Per-item context menu (Open, Delete)
- Bookmark toggle on each card
- State persistence via `useListState(listStateKey)`

**What's Missing for Detail Screen Use**:
- No "embedded mode" prop (always renders full-page with search/sort/filter controls)
- Bulk actions are hardcoded (not configurable per-context)
- No way to hide top control bar
- No linked transaction info display on item cards

---

### Q2: What are the key differences between ItemsSection and SharedItemsList?

**Findings**:

**ItemsSection Location**: `src/components/ItemsSection.tsx`

**Props Interface**:
```typescript
type ItemsSectionProps<S extends string = string, F extends string = string> = {
  manager: UseItemsManagerReturn<S, F>;
  items: ScopedItem[];
  onItemPress: (id: string) => void;
  getItemMenuItems: (item: ScopedItem) => AnchoredMenuItem[];
  onBookmarkPress?: (item: ScopedItem) => void;
  bulkActions?: BulkAction[];
  onBulkAction?: (actionId: string, selectedIds: string[]) => void;
  emptyMessage?: string;
};
```

**Architectural Differences**:

| Feature | SharedItemsList | ItemsSection |
|---------|----------------|--------------|
| **Purpose** | Standalone full-page list | Section fragment for embedding |
| **State Management** | Internal (`useListState`) | External (`useItemsManager` from parent) |
| **Search/Sort/Filter UI** | Built-in top control bar | None (parent responsible) |
| **Bulk Selection UI** | Bottom bar + bottom sheet | Inline panel (appears when selections exist) |
| **Grouping** | ✅ Yes (via GroupedItemCard) | ❌ No (plain ItemCard only) |
| **Selector Circles** | ✅ Yes | ❌ No (prop not passed) |
| **Status Badges** | ✅ Yes | ❌ No (prop not passed) |

**Usage in Codebase**:
- **SharedItemsList**: Project items tab, Inventory items tab (standalone screens)
- **ItemsSection**: Transaction detail, Space detail (embedded in SectionList)

**Key Issues with ItemsSection** (from spec):
1. Missing selector circles on item cards
2. Missing status badges
3. No grouping support (shows flat list)
4. Broken bulk toggle logic (doesn't deselect when all selected)
5. Bulk actions in inline panel instead of bottom bar + sheet

---

### Q3: What are the current section spacing values across detail screens?

**Findings**:

**Transaction Detail** (`app/transactions/[id]/index.tsx`):
```typescript
content: {
  paddingTop: layout.screenBodyTopMd.paddingTop,
  paddingBottom: 24,
  gap: 10  // ← Between sections
}
```

**Item Detail** (`app/items/[id]/index.tsx`):
```typescript
content: {
  paddingTop: layout.screenBodyTopMd.paddingTop,
  paddingBottom: 24,
  gap: 18  // ← Between sections
}
```

**Space Detail** (`src/components/SpaceDetailContent.tsx`):
```typescript
content: {
  gap: 20,  // ← Between sections
  paddingTop: layout.screenBodyTopMd.paddingTop,
}
section: {
  gap: 12,  // ← Within a section
}
list: {
  gap: 10,  // ← Between items
}
itemSeparator: {
  height: 10,
}
```

**Summary**:
- **Inconsistent section gaps**: 10px (transaction), 18px (item), 20px (space)
- **Target**: Normalize all to 4px (per spec requirement)
- **Item separators**: Consistent at 10px (keep this)
- **Card padding**: Consistent at 16px (`CARD_PADDING`)

---

### Q4: How does item detail currently display linked transaction info?

**Findings**:

**Current Implementation** (`app/items/[id]/index.tsx`):

```typescript
// Hero section displays:
<Card>
  <AppText variant="h2">{item.name || "Untitled item"}</AppText>
  <AppText variant="caption">
    Transaction:
    {item.transactionId ? (
      <AppText
        variant="body"
        style={{color: theme.colors.primary}}
        onPress={() => router.push(`/transactions/${item.transactionId}`)}
      >
        {item.transactionId.slice(0, 8)}...
      </AppText>
    ) : (
      <AppText variant="body" style={{color: theme.colors.textSecondary}}>
        None
      </AppText>
    )}
  </AppText>
</Card>
```

**Issues**:
1. Shows truncated transaction ID (`abc12345...`) instead of meaningful info
2. Should show "Source - $Amount" (e.g., "Amazon - $149.99")
3. No space info displayed (should show assigned space if present)
4. Styling doesn't match transaction detail hero card pattern

**Target Format** (from spec):
```
Item Name
────────────────────────
Transaction: Amazon - $149.99  |  Space: Kitchen
           ↑ body variant           ↑ body variant
           (tappable link)
```

**Edge Cases**:
- Transaction deleted/unavailable: Show "Transaction: [Deleted]" or "Transaction: Unavailable"
- No transaction linked: Show "Transaction: None"
- No space assigned: Omit space info entirely (not "Space: None")

---

## Component Refactoring Strategy

### Decision: Extract Shared Logic

Based on the research, the optimal approach is to:

1. **Extract reusable components from SharedItemsList**:
   - `BulkSelectionBar` - sticky bottom bar with count and actions button
   - `BulkActionsSheet` - bottom sheet with configurable actions
   - `useGroupedItems` hook - grouping logic that both components can use

2. **Add "embedded mode" to SharedItemsList**:
   - New prop: `embedded?: boolean`
   - When true: Hide top control bar (search/sort/filter)
   - Expose `manager` prop for external state control (like ItemsSection does)
   - Allow custom bulk actions via `bulkActionsConfig` prop

3. **Update detail screens**:
   - Replace `<ItemsSection>` with `<SharedItemsList embedded>`
   - Pass screen-specific bulk actions config
   - Use existing `useItemsManager` for state

### Implementation Plan

**Step 1**: Extract `BulkSelectionBar` component
```typescript
// src/components/BulkSelectionBar.tsx
type BulkSelectionBarProps = {
  selectedCount: number;
  onClear: () => void;
  onBulkActions: () => void;
};
```

**Step 2**: Extract `BulkActionsSheet` component
```typescript
// src/components/BulkActionsSheet.tsx
type BulkAction = {
  id: string;
  label: string;
  icon?: string;
  onPress: (selectedIds: string[]) => void;
};

type BulkActionsSheetProps = {
  visible: boolean;
  selectedIds: string[];
  actions: BulkAction[];
  onClose: () => void;
};
```

**Step 3**: Update SharedItemsList to accept external state
```typescript
type SharedItemsListProps = {
  // Existing props
  scopeConfig?: ScopeConfig;
  listStateKey?: string;
  refreshToken?: number;

  // New props for embedded mode
  embedded?: boolean;
  manager?: UseItemsManagerReturn;
  items?: ScopedItem[];
  bulkActions?: BulkAction[];
  onItemPress?: (id: string) => void;
  getItemMenuItems?: (item: ScopedItem) => AnchoredMenuItem[];
};
```

**Backward Compatibility**: When `embedded` is false (default), use internal state like today.

---

## Item Detail Top Card Pattern

### Reference: Transaction Detail Hero Card

**Location**: `app/transactions/[id]/index.tsx`

**Pattern**:
```typescript
<Card>
  <AppText variant="h2">{source}</AppText>
  <View style={{ flexDirection: 'row', alignItems: 'baseline' }}>
    <AppText variant="caption">Date: </AppText>
    <AppText variant="body">{formatDate(date)}</AppText>
    <AppText variant="caption"> | </AppText>
    <AppText variant="caption">Amount: </AppText>
    <AppText variant="body">{formatCurrency(amount)}</AppText>
  </View>
</Card>
```

**Key Styling**:
- Label: `variant="caption"` (smaller, secondary color)
- Value: `variant="body"` (larger, primary color)
- Separator: ` | ` (pipe with spaces)
- Layout: `flexDirection: 'row'`, `alignItems: 'baseline'`

### Target: Item Detail Hero Card

**New Pattern**:
```typescript
<Card>
  <AppText variant="h2">{item.name || "Untitled item"}</AppText>
  <View style={{ flexDirection: 'row', alignItems: 'baseline', flexWrap: 'wrap' }}>
    <AppText variant="caption">Transaction: </AppText>
    {transactionData ? (
      <AppText
        variant="body"
        style={{ color: theme.colors.primary }}
        onPress={() => router.push(`/transactions/${item.transactionId}`)}
      >
        {transactionData.source} - {formatCurrency(transactionData.amount)}
      </AppText>
    ) : item.transactionId ? (
      <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
        [Deleted]
      </AppText>
    ) : (
      <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
        None
      </AppText>
    )}
    {item.spaceId && spaceData && (
      <>
        <AppText variant="caption"> | </AppText>
        <AppText variant="caption">Space: </AppText>
        <AppText variant="body">{spaceData.name}</AppText>
      </>
    )}
  </View>
</Card>
```

**Data Loading**:
- Load transaction data from Firestore (cache-first)
- Load space data from Firestore (cache-first)
- Handle loading states gracefully (show skeleton or fall back to ID)

---

## Section Spacing Normalization

### Target Spacing Values

**Between Sections (Collapsible Headers)**:
- Gap: **4px** (tightest, most compact)
- This is the target from spec (currently used in space detail)

**Within Sections (Content)**:
- Card padding: **16px** (`CARD_PADDING`)
- Item list gap: **10px** (between item cards)
- Meta info gap: **6px** (within info rows)

**Screen Content**:
- Top padding: `layout.screenBodyTopMd.paddingTop` (consistent across all)
- Bottom padding: **24px** (consistent across all)

### Changes Required

| Screen | Current Gap | Target Gap | Change |
|--------|-------------|------------|--------|
| Transaction Detail | 10 | 4 | -6px |
| Item Detail | 18 | 4 | -14px |
| Space Detail | 20 | 4 | -16px |

**Implementation**:
```typescript
// All detail screens:
contentContainerStyle={{
  gap: 4,  // ← Normalize to 4px
  paddingTop: layout.screenBodyTopMd.paddingTop,
  paddingBottom: 24,
}}
```

---

## Bulk Selection Toggle Fix

### Current Issue

**Location**: `src/components/ItemsSection.tsx` (and likely SharedItemsList too)

**Problem**: Bulk select button calls `selectAll()` but doesn't toggle to deselect when all items are already selected.

**Current Logic**:
```typescript
const handleBulkSelect = () => {
  manager.selectAll();  // ← Always selects, never deselects
};
```

**Expected Behavior**:
- If some items unselected → select all
- If all items selected → deselect all

### Fix

**Target Logic**:
```typescript
const handleBulkSelect = () => {
  const allSelected = manager.selectedIds.length === items.length;
  if (allSelected) {
    manager.clearSelection();
  } else {
    manager.selectAll();
  }
};
```

**Apply to**:
- SharedItemsList bulk select button
- Any other bulk select toggle buttons in detail screens

---

## Space Detail Default Sections

### Current Behavior

**Location**: `src/components/SpaceDetailContent.tsx`

**Current Defaults** (expanded sections):
- Images: ✅ Expanded
- Items: ✅ Expanded ← Should be collapsed
- Notes: ❌ Collapsed
- Checklists: ❌ Collapsed

### Target Behavior

**New Defaults**:
- Images: ✅ Expanded (only this one)
- Items: ❌ Collapsed
- Notes: ❌ Collapsed
- Checklists: ❌ Collapsed

**Implementation**:
```typescript
const [collapsedSections, setCollapsedSections] = useState({
  images: false,    // Expanded
  items: true,      // ← Change from false to true
  notes: true,
  checklists: true,
});
```

---

## Move Item to Kebab Menu

### Current Implementation

**Location**: `app/items/[id]/index.tsx`

**Problem**: Move item form rendered inline as a section at bottom of screen.

**Current**:
```typescript
{scope === 'project' && (
  <View style={styles.moveSection}>
    <AppText variant="h2">Move Item</AppText>
    <MoveItemForm itemId={id} />
  </View>
)}
```

### Target Implementation

**Remove inline section**, add to kebab menu:

```typescript
const menuItems: AnchoredMenuItem[] = [
  { label: 'Edit', onPress: () => router.push(`/items/${id}/edit`) },
  { label: 'Bookmark', onPress: handleBookmark },
  { label: 'Move Item', onPress: () => setMoveSheetVisible(true) },  // ← New
  { label: 'Delete', onPress: handleDelete, destructive: true },
];

// Render bottom sheet
<FormBottomSheet
  visible={moveSheetVisible}
  onClose={() => setMoveSheetVisible(false)}
  title="Move Item"
>
  <MoveItemForm
    itemId={id}
    onSuccess={() => setMoveSheetVisible(false)}
  />
</FormBottomSheet>
```

---

## Tax/Details Section Merge

### Current Implementation

**Location**: `app/transactions/[id]/index.tsx` or `app/transactions/[id]/sections/`

**Problem**: Two separate collapsible sections:
1. "DETAILS" - Source, Date, Amount, Status, Purchased by, etc.
2. "TAX & ITEMIZATION" - Subtotal, Tax rate, Tax amount

### Target Implementation

**Single "DETAILS" section** containing all rows:

```typescript
const detailRows = [
  { label: 'Source', value: transaction.source },
  { label: 'Date', value: formatDate(transaction.date) },
  { label: 'Amount', value: formatCurrency(transaction.amount) },
  { label: 'Status', value: transaction.status },
  { label: 'Purchased by', value: transaction.purchasedBy },
  { label: 'Reimbursement', value: transaction.reimbursementType },
  { label: 'Budget category', value: transaction.budgetCategory },
  { label: 'Email receipt', value: transaction.emailReceipt ? 'Yes' : 'No' },

  // Tax rows (conditional - only if itemization enabled)
  ...(transaction.itemizationEnabled ? [
    { label: 'Subtotal', value: formatCurrency(transaction.subtotal) },
    { label: 'Tax rate', value: `${transaction.taxRate}%` },
    { label: 'Tax amount', value: formatCurrency(transaction.taxAmount) },
  ] : []),
];

// Render single collapsible section
<CollapsibleSectionHeader title="DETAILS" collapsed={...}>
  <Card>
    {detailRows.map(row => (
      <DetailRow key={row.label} label={row.label} value={row.value} />
    ))}
  </Card>
</CollapsibleSectionHeader>
```

**Remove**: Separate `<CollapsibleSectionHeader title="TAX & ITEMIZATION">` section.

---

## Duplicate Section Titles Fix

### Problem

**Location**: Various detail screens using `CollapsibleSectionHeader` + `Card`/`TitledCard`

**Issue**: `CollapsibleSectionHeader` renders "DETAILS" (uppercase), then inner `TitledCard` renders "Details" again inside the section content. This produces a double title.

**Example**:
```
DETAILS                    ← CollapsibleSectionHeader
┌─────────────────────┐
│ Details             │    ← Card title (duplicate!)
│ Source: Amazon      │
│ Date: 2026-01-15    │
└─────────────────────┘
```

### Fix Options

**Option A**: Use `Card` instead of `TitledCard` inside collapsible sections
```typescript
<CollapsibleSectionHeader title="DETAILS">
  <Card>  {/* No title prop */}
    {detailRows.map(row => ...)}
  </Card>
</CollapsibleSectionHeader>
```

**Option B**: Add `hideTitle` prop to `TitledCard`
```typescript
<CollapsibleSectionHeader title="DETAILS">
  <TitledCard title="Details" hideTitle>  {/* Title hidden in output */}
    {detailRows.map(row => ...)}
  </TitledCard>
</CollapsibleSectionHeader>
```

**Recommendation**: Option A (simpler, no component changes needed).

**Apply to**:
- Transaction detail: Details section, Tax section (now merged)
- Item detail: Details section
- Space detail: All collapsible sections

---

## Summary of Changes

### Components to Modify

1. **SharedItemsList.tsx**
   - Add `embedded` mode prop
   - Add `bulkActionsConfig` prop
   - Extract `BulkSelectionBar` component
   - Support external state management

2. **ItemsSection.tsx**
   - Mark as deprecated (add JSDoc comment)
   - Keep for now (don't delete in this feature)

3. **app/transactions/[id]/index.tsx**
   - Replace ItemsSection with SharedItemsList (embedded mode)
   - Merge Tax & Details sections into single "DETAILS" section
   - Update section gap from 10 to 4
   - Fix double titles (use Card, not TitledCard)

4. **app/items/[id]/index.tsx**
   - Fix hero card transaction display ("Source - $Amount")
   - Add space info row to hero card
   - Update section gap from 18 to 4
   - Move "Move Item" from inline section to kebab menu
   - Fix double titles

5. **src/components/SpaceDetailContent.tsx** (or `app/project/[projectId]/spaces/[spaceId].tsx`)
   - Replace ItemsSection with SharedItemsList (embedded mode)
   - Update default expanded sections (only images)
   - Update section gap from 20 to 4
   - Fix double titles

6. **Bulk selection toggle logic** (wherever it exists)
   - Fix toggle to deselect when all selected

### New Components to Create

1. **src/components/BulkSelectionBar.tsx**
   - Extracted from SharedItemsList
   - Reusable sticky bottom bar
   - Props: selectedCount, onClear, onBulkActions

2. **src/components/BulkActionsSheet.tsx** (optional)
   - Extracted bulk actions bottom sheet
   - Configurable actions list
   - Props: visible, selectedIds, actions, onClose

### Spacing Values

| Context | Value |
|---------|-------|
| Section gap (between collapsible headers) | 4px |
| Item list gap (between item cards) | 10px |
| Card padding | 16px |
| Screen top padding | `layout.screenBodyTopMd.paddingTop` |
| Screen bottom padding | 24px |

### Theme Usage

**Info rows** (transaction hero, item hero):
- Label: `<AppText variant="caption">` (secondary color)
- Value: `<AppText variant="body">` (primary color)
- Link: `style={{ color: theme.colors.primary }}` + `onPress`
- Separator: ` | ` (literal pipe with spaces)
- Layout: `flexDirection: 'row'`, `alignItems: 'baseline'`

---

## Alternatives Considered

### Alternative 1: Keep ItemsSection, Add Features

**Rejected because**:
- Would duplicate grouping logic from SharedItemsList
- Would duplicate bulk selection UI from SharedItemsList
- Creates two implementations that could drift
- Doesn't address root cause (bad spec decision in 004)

### Alternative 2: Create New DetailItemsList Component

**Rejected because**:
- Adds third implementation alongside SharedItemsList and ItemsSection
- More code to maintain
- Doesn't unify the codebase

### Alternative 3: Use SharedItemsList As-Is (No Refactoring)

**Rejected because**:
- SharedItemsList currently requires full-page mode
- Would need significant prop drilling for embedded use
- Bulk actions hardcoded (not configurable)
- Top control bar cannot be hidden

---

## Next Steps

1. ✅ Research complete
2. → Phase 1: Create quickstart.md with developer patterns
3. → Update agent context with new component patterns
4. → User runs `/spec-kitty.tasks` to generate work packages
5. → Implementation begins with `/spec-kitty.implement WP01`
