# Developer Quickstart: Detail Screen Polish

**Feature**: 005-detail-screen-polish
**Last Updated**: 2026-02-10

## Overview

This guide provides patterns and code examples for implementing the detail screen polish fixes. Use these patterns to ensure consistency across transaction, item, and space detail screens.

## Core Patterns

### 1. Using SharedItemsList in Embedded Mode

**Purpose**: Replace ItemsSection with SharedItemsList for visual parity with project/inventory tabs.

**Basic Usage**:

```typescript
import { SharedItemsList } from '@/src/components/SharedItemsList';
import { useItemsManager } from '@/src/hooks/useItemsManager';

// In your detail screen component:
const manager = useItemsManager({
  listStateKey: 'transaction-items',  // Unique key for state persistence
  initialSort: 'created-desc',
});

// Fetch items from Firestore
const items = useItemsForTransaction(transactionId);

// Define screen-specific bulk actions
const bulkActions = [
  { id: 'set-space', label: 'Set Space', onPress: (ids) => handleSetSpace(ids) },
  { id: 'set-status', label: 'Set Status', onPress: (ids) => handleSetStatus(ids) },
  { id: 'remove', label: 'Remove', onPress: (ids) => handleRemove(ids) },
  { id: 'delete', label: 'Delete', onPress: (ids) => handleDelete(ids), destructive: true },
];

return (
  <SharedItemsList
    embedded={true}  // ← Hides top control bar
    manager={manager}  // ← External state management
    items={items}
    bulkActions={bulkActions}  // ← Custom actions for this screen
    onItemPress={(id) => router.push(`/items/${id}`)}
    getItemMenuItems={(item) => [
      { label: 'Open', onPress: () => router.push(`/items/${item.id}`) },
      { label: 'Delete', onPress: () => handleDeleteItem(item.id), destructive: true },
    ]}
  />
);
```

**Key Props**:

- **`embedded`**: `boolean` - When `true`, hides search/sort/filter controls (shows only list + bulk bar)
- **`manager`**: `UseItemsManagerReturn` - State manager from `useItemsManager` hook
- **`items`**: `ScopedItem[]` - Array of items to display
- **`bulkActions`**: `BulkAction[]` - Custom actions for this screen's bulk sheet
- **`onItemPress`**: `(id: string) => void` - Item card tap handler
- **`getItemMenuItems`**: `(item: ScopedItem) => AnchoredMenuItem[]` - Context menu items

**Note**: When `embedded={false}` (default), SharedItemsList uses internal state and shows full controls (standalone mode).

---

### 2. Consistent Section Spacing

**Rule**: All detail screens must use **4px gap** between collapsible sections (header-to-header), with **12px gap** between a section header and its content.

**Problem**: The `gap` property on `SectionList` `contentContainerStyle` applies to **all direct children**, including both:
- Section-to-section spacing (what we want to be 4px)
- Header-to-content spacing (should be larger, ~12px)

**Solution**: Wrap each section's header + content in a single View with internal spacing.

**Implementation Pattern**:

```typescript
// For sections using SECTION_HEADER_MARKER pattern:
function renderItem({ item, section }: { item: string; section: Section }) {
  if (item === SECTION_HEADER_MARKER) {
    const collapsed = collapsedSections[section.key];

    return (
      <View style={{ gap: 12 }}>  {/* ← Header-to-content gap */}
        <CollapsibleSectionHeader
          title={section.title}
          collapsed={collapsed}
          onToggle={() => toggleSection(section.key)}
        />
        {!collapsed && (
          <Card>
            {/* Section content */}
          </Card>
        )}
      </View>
    );
  }

  // Other item types...
}

// Then set contentContainerStyle gap to 4:
<SectionList
  sections={sections}
  renderItem={renderItem}
  contentContainerStyle={{
    gap: 4,  // ← Section-to-section spacing
    paddingTop: layout.screenBodyTopMd.paddingTop,
    paddingBottom: 24,
  }}
/>
```

**Current Values to Change**:

| Screen | Current `gap` | Target `gap` | Internal wrapper gap |
|--------|---------------|--------------|---------------------|
| Transaction Detail | 10 | 4 | 12 (new) |
| Item Detail | 18 | 4 | 12 (new) |
| Space Detail | 20 | 4 | 12 (new) |

**Key Points**:
- Wrapper View combines header + content into single SectionList child
- `contentContainerStyle.gap: 4` controls section-to-section spacing
- Wrapper's internal `gap: 12` controls header-to-content spacing
- When collapsed, only header renders inside wrapper (content conditionally rendered)
- This keeps Card component clean (no added margins)

---

### 3. Item Detail Hero Card with Linked Transaction

**Purpose**: Display linked transaction as "Source - $Amount" with proper styling, plus space info.

**Pattern**:

```typescript
import { useTheme } from '@/src/theme/theme';
import { useRouter } from 'expo-router';

// Load transaction and space data (cache-first)
const transactionData = useTransactionById(item.transactionId);
const spaceData = useSpaceById(item.spaceId);

const theme = useTheme();
const router = useRouter();

return (
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
);
```

**Key Points**:
- **Label**: `variant="caption"` (secondary color, smaller)
- **Value**: `variant="body"` (primary color, larger)
- **Link**: Apply `color: theme.colors.primary` + `onPress` handler
- **Separator**: ` | ` (literal pipe with spaces, caption variant)
- **Layout**: `flexDirection: 'row'`, `alignItems: 'baseline'`, `flexWrap: 'wrap'`

**Edge Cases**:
- Transaction deleted/not loadable: Show `"[Deleted]"` or `"[Unavailable]"` (not hide the row)
- No transaction linked: Show `"None"`
- No space assigned: Omit space info entirely (don't show "Space: None")

---

### 4. Merging Tax into Details Section

**Purpose**: Combine Tax/Itemization and Details into single collapsible section in transaction detail.

**Before**:
```typescript
// Two separate sections
<CollapsibleSectionHeader title="DETAILS">...</CollapsibleSectionHeader>
<CollapsibleSectionHeader title="TAX & ITEMIZATION">...</CollapsibleSectionHeader>
```

**After**:
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

  // Conditionally add tax rows
  ...(transaction.itemizationEnabled ? [
    { label: 'Subtotal', value: formatCurrency(transaction.subtotal) },
    { label: 'Tax rate', value: `${transaction.taxRate}%` },
    { label: 'Tax amount', value: formatCurrency(transaction.taxAmount) },
  ] : []),
];

<CollapsibleSectionHeader title="DETAILS" collapsed={collapsedSections.details}>
  <Card>
    {detailRows.map(row => (
      <DetailRow key={row.label} label={row.label} value={row.value} />
    ))}
  </Card>
</CollapsibleSectionHeader>
```

**Remove**: The separate "TAX & ITEMIZATION" section header and content.

---

### 5. Fixing Duplicate Section Titles

**Problem**: `CollapsibleSectionHeader` renders "DETAILS", then inner `TitledCard` renders "Details" again.

**Fix**: Use `Card` instead of `TitledCard` inside collapsible sections.

**Before**:
```typescript
<CollapsibleSectionHeader title="DETAILS">
  <TitledCard title="Details">  {/* ← Duplicate title */}
    {content}
  </TitledCard>
</CollapsibleSectionHeader>
```

**After**:
```typescript
<CollapsibleSectionHeader title="DETAILS">
  <Card>  {/* ← No title, section header provides it */}
    {content}
  </Card>
</CollapsibleSectionHeader>
```

**Apply to**: All collapsible sections in all detail screens.

---

### 6. Bulk Selection Toggle Fix

**Problem**: Bulk select button always selects, never deselects when all items are already selected.

**Fix**:

```typescript
const handleBulkSelect = () => {
  const allSelected = manager.selectedIds.length === items.length;
  if (allSelected) {
    manager.clearSelection();
  } else {
    manager.selectAll();
  }
};

// In render:
<AppButton
  title={allSelected ? "Deselect All" : "Select All"}
  onPress={handleBulkSelect}
/>
```

**Note**: This fix applies to SharedItemsList's internal bulk button. If implementing custom bulk controls, use this pattern.

---

### 7. Moving Inline Sections to Kebab Menu

**Example**: Move Item form in item detail.

**Before**:
```typescript
// Inline section at bottom of screen
{scope === 'project' && (
  <View style={styles.moveSection}>
    <AppText variant="h2">Move Item</AppText>
    <MoveItemForm itemId={id} />
  </View>
)}
```

**After**:
```typescript
// Add to kebab menu
const menuItems: AnchoredMenuItem[] = [
  { label: 'Edit', onPress: () => router.push(`/items/${id}/edit`) },
  { label: 'Move Item', onPress: () => setMoveSheetVisible(true) },  // ← New
  { label: 'Delete', onPress: handleDelete, destructive: true },
];

// Render form in bottom sheet
<FormBottomSheet
  visible={moveSheetVisible}
  onClose={() => setMoveSheetVisible(false)}
  title="Move Item"
>
  <MoveItemForm
    itemId={id}
    onSuccess={() => {
      setMoveSheetVisible(false);
      // Optionally refresh or navigate
    }}
  />
</FormBottomSheet>
```

**Remove**: The inline section from the main screen body.

---

### 8. Space Detail Default Sections

**Rule**: Only the images section should be expanded by default.

**Implementation**:

```typescript
const [collapsedSections, setCollapsedSections] = useState({
  images: false,    // Expanded
  items: true,      // ← Change from false to true
  notes: true,      // Collapsed
  checklists: true, // Collapsed
});
```

**Location**: `src/components/SpaceDetailContent.tsx` or equivalent.

---

## Component API Reference

### SharedItemsList (Embedded Mode)

```typescript
type SharedItemsListProps = {
  // Existing props (for standalone mode)
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
  emptyMessage?: string;
};

type BulkAction = {
  id: string;
  label: string;
  onPress: (selectedIds: string[]) => void;
  destructive?: boolean;
};
```

**Standalone vs Embedded**:

| Prop | Standalone | Embedded |
|------|-----------|----------|
| `scopeConfig` | Required | Optional (not used) |
| `listStateKey` | Required | Optional (not used) |
| `manager` | N/A (internal) | Required |
| `items` | N/A (loaded internally) | Required |
| `bulkActions` | N/A (hardcoded) | Required |

### useItemsManager Hook

```typescript
type UseItemsManagerReturn<S extends string, F extends string> = {
  // State
  selectedIds: string[];
  searchQuery: string;
  activeSort: S;
  activeFilters: Record<F, boolean>;

  // Actions
  selectAll: () => void;
  clearSelection: () => void;
  toggleSelection: (id: string) => void;
  setSearchQuery: (query: string) => void;
  setSort: (sort: S) => void;
  toggleFilter: (filter: F) => void;

  // Computed
  filteredItems: ScopedItem[];
  sortedItems: ScopedItem[];
};

// Usage:
const manager = useItemsManager<SortOption, FilterOption>({
  listStateKey: 'unique-key',
  initialSort: 'created-desc',
});
```

---

## Offline-First Checklist

**CRITICAL**: All changes must preserve offline-first patterns.

- [ ] No `await` on Firestore writes in UI code
- [ ] Use fire-and-forget writes with `.catch()` for error logging
- [ ] Use cache-first reads (`mode: 'offline'`) in save handlers
- [ ] UI updates happen immediately (optimistic updates)
- [ ] Navigation happens immediately (don't wait for server)
- [ ] Loading states show cached data, not spinners blocking on server

**Example - Offline-First Write**:

```typescript
// ❌ BAD: Awaits Firestore write
const handleSave = async () => {
  setLoading(true);
  await updateItem(itemId, data);  // Blocks UI on network
  setLoading(false);
  router.back();
};

// ✅ GOOD: Fire-and-forget, immediate navigation
const handleSave = () => {
  updateItem(itemId, data).catch(err => {
    console.error('Failed to update item:', err);
    // Optionally show toast/banner
  });
  router.back();  // Navigate immediately
};
```

---

## Theme Usage Guide

### Text Variants

| Variant | Use For | Color | Size |
|---------|---------|-------|------|
| `h1` | Screen titles | `text` | 28px |
| `h2` / `title` | Section titles, card titles | `text` | 20px |
| `body` | Primary content, values | `text` | 16px |
| `caption` | Labels, secondary info | `textSecondary` | 14px |

### Color Access

```typescript
import { useTheme } from '@/src/theme/theme';

const theme = useTheme();

// Common colors:
theme.colors.text           // Primary text
theme.colors.textSecondary  // Secondary text (labels, captions)
theme.colors.primary        // Brand color (links, accent)
theme.colors.background     // Screen background
theme.colors.border         // Borders, dividers
```

**DO NOT hardcode colors**. Always use theme tokens.

---

## Testing Checklist

### Visual QA

Before/after screenshots for each screen:

- [ ] Transaction detail
  - [ ] Item list uses grouped cards with selector circles and status badges
  - [ ] Bulk selection uses bottom bar + bottom sheet (not inline buttons)
  - [ ] Details section includes tax rows (when applicable)
  - [ ] Section gap is 4px
  - [ ] No duplicate section titles

- [ ] Item detail
  - [ ] Hero card shows "Transaction: Source - $Amount" (or "[Deleted]" or "None")
  - [ ] Hero card shows space name when assigned
  - [ ] Info row styling matches transaction detail (caption labels, body values, pipe separator)
  - [ ] "Move Item" in kebab menu (not inline section)
  - [ ] Section gap is 4px
  - [ ] No duplicate section titles

- [ ] Space detail
  - [ ] Item list uses grouped cards with selector circles and status badges
  - [ ] Bulk selection uses bottom bar + bottom sheet
  - [ ] Only images section expanded by default
  - [ ] Section gap is 4px
  - [ ] No duplicate section titles

### Functional QA

- [ ] Bulk select toggle deselects all when all selected
- [ ] Bulk actions open bottom sheet with context-appropriate actions
- [ ] Item cards navigate to item detail on tap
- [ ] Linked transaction in item detail navigates to transaction detail
- [ ] Move Item form opens in bottom sheet from kebab menu
- [ ] Search/sort/filter work in item lists (if visible)
- [ ] Selection state persists when section collapsed

### Edge Cases

- [ ] Empty item lists show empty state message (no bulk bar)
- [ ] Items with no name show "Untitled item"
- [ ] Deleted transactions show "[Deleted]" (not hidden)
- [ ] Items with no space assignment omit space info (not "Space: None")
- [ ] All items selected → bulk toggle button says "Deselect All"

### Offline-First Verification

- [ ] Airplane mode: Item list loads from cache instantly
- [ ] Airplane mode: Bulk actions trigger immediately (no spinner of doom)
- [ ] Airplane mode: Navigation happens immediately after save
- [ ] Network restored: Pending writes sync automatically

---

## Component Deprecation

### ItemsSection.tsx

**Status**: Deprecated as of 005-detail-screen-polish.

**Migration**: Replace with `SharedItemsList` in embedded mode (see pattern above).

**Do NOT delete** in this feature. Mark as deprecated:

```typescript
/**
 * @deprecated Use SharedItemsList with embedded={true} instead.
 * This component lacks grouping support, proper bulk UI, and visual parity with project/inventory tabs.
 * See kitty-specs/005-detail-screen-polish/quickstart.md for migration guide.
 */
export function ItemsSection(props: ItemsSectionProps) {
  // ...existing implementation
}
```

**Removal timeline**: After 005 is complete and stable, a future cleanup feature can remove ItemsSection.

---

## Common Pitfalls

### 1. Forgetting to Pass Manager State

**Problem**: SharedItemsList in embedded mode receives undefined manager, uses internal state instead.

**Fix**: Always pass `manager` prop when `embedded={true}`.

```typescript
const manager = useItemsManager({ listStateKey: 'my-list' });
<SharedItemsList embedded manager={manager} items={items} />
```

---

### 2. Hardcoding Colors

**Problem**: Using hex colors directly breaks dark mode support.

**Fix**: Always use theme tokens.

```typescript
// ❌ BAD
<AppText style={{ color: '#666' }}>Label</AppText>

// ✅ GOOD
<AppText variant="caption">Label</AppText>
// or
<AppText style={{ color: theme.colors.textSecondary }}>Label</AppText>
```

---

### 3. Awaiting Firestore Writes

**Problem**: UI blocks on network, "spinner of doom" when offline.

**Fix**: Fire-and-forget with `.catch()`.

```typescript
// ❌ BAD
await updateItem(id, data);

// ✅ GOOD
updateItem(id, data).catch(err => console.error(err));
```

---

### 4. Double Titles in Collapsible Sections

**Problem**: Using `TitledCard` inside `CollapsibleSectionHeader` creates duplicate titles.

**Fix**: Use `Card` (no title) instead.

```typescript
// ❌ BAD
<CollapsibleSectionHeader title="DETAILS">
  <TitledCard title="Details">...</TitledCard>
</CollapsibleSectionHeader>

// ✅ GOOD
<CollapsibleSectionHeader title="DETAILS">
  <Card>...</Card>
</CollapsibleSectionHeader>
```

---

## File Locations Quick Reference

| File | Purpose |
|------|---------|
| `src/components/SharedItemsList.tsx` | Main item list component (refactor for embedded mode) |
| `src/components/ItemsSection.tsx` | Deprecated (mark as deprecated, don't delete) |
| `src/components/GroupedItemCard.tsx` | Grouped item card (already implements grouping) |
| `src/components/ItemCard.tsx` | Individual item card |
| `src/components/BulkSelectionBar.tsx` | NEW - sticky bottom bar (extract from SharedItemsList) |
| `src/components/CollapsibleSectionHeader.tsx` | Section header component |
| `src/components/Card.tsx` | Basic card component (no title) |
| `src/components/TitledCard.tsx` | Card with title (avoid in collapsible sections) |
| `src/components/DetailRow.tsx` | Detail row component for info displays |
| `src/hooks/useItemsManager.ts` | State management for item lists |
| `app/transactions/[id]/index.tsx` | Transaction detail screen |
| `app/items/[id]/index.tsx` | Item detail screen |
| `src/components/SpaceDetailContent.tsx` | Space detail screen (or in app/ directory) |

---

## Additional Resources

- **Spec**: [kitty-specs/005-detail-screen-polish/spec.md](spec.md)
- **Plan**: [kitty-specs/005-detail-screen-polish/plan.md](plan.md)
- **Research**: [kitty-specs/005-detail-screen-polish/research.md](research.md)
- **Offline-First Principles**: [.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md](/.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md)

---

## Next Steps

1. Review this quickstart and familiarize yourself with patterns
2. User runs `/spec-kitty.tasks` to generate work packages
3. User runs `/spec-kitty.implement WP01` to begin implementation
4. Follow patterns in this guide during implementation
5. Use testing checklist before submitting for review
