# Transaction Items Control Bar - Full Feature Parity Implementation Plan

**Status:** Ready for implementation
**Created:** 2026-02-08
**Goal:** Add sort, filter, search, bulk operations, and enhanced menus to transaction items section

---

## Executive Summary

The transaction detail page (`app/transactions/[id]/index.tsx`) currently has minimal items controls (only "Add Item" button). The legacy web app provides comprehensive controls including sort, filter, search, bulk selection, and rich context menus. All necessary mobile components exist and are proven in the space detail screen - this is primarily a configuration and integration task.

---

## Phase 1 Findings: Legacy Web App Feature Audit

### Control Bar Features

**Primary Controls:**
- ✅ **Add Item** dropdown: "Create new" | "Add existing"
- ✅ **Sort** button: Alphabetical | Price (descending)
- ✅ **Filter** button: 6 options
- ✅ **Search** bar: Searches description, SKU, space, notes
- ✅ **Select All** checkbox for bulk selection

**Sort Options (2 total):**
1. **Alphabetical** (name ascending)
2. **Price (descending)** (highest price first)

**Filter Options (6 total):**
1. **All Items** (default)
2. **Bookmarked** (show starred items only)
3. **No SKU** (missing SKU)
4. **No Name** (missing name)
5. **No Project Price** (missing price)
6. **No Image** (no images uploaded)

### Item Card Context Menu

**Transaction Context Actions:**
- Edit
- Make Copies
- Set Space
- **Remove from Transaction** ⚠️ (unique to transaction context)
- **Move to Return Transaction** ⚠️
- **Associate with Transaction**
- **Sell** submenu:
  - Sell to Design Business
  - Sell to Project
- **Move** submenu:
  - Move to Design Business
  - Move to Project
- **Status** submenu:
  - To Purchase
  - Purchased
  - To Return
  - Returned
- Delete

### Bulk Operations (Multi-Select)

When items are selected:
- Assign to Transaction
- Set Space
- Set Disposition
- Set SKU
- Delete
- Clear selection

### Transaction-Specific Differences

**Added in Transaction Context:**
- "Remove from Transaction" action (unlink without deleting item)
- "Move to Return Transaction" action
- Multiple display sections: Current items | Returned items | Sold items
- Transaction link suppressed on item cards (avoid circular reference)

**Same as Regular Items:**
- Sort/filter/search capabilities
- Bulk operations
- Bookmarking
- Duplication
- Space assignment

---

## Phase 2 Findings: Current Mobile App Architecture

### Existing Components (All Reusable)

✅ **ItemsListControlBar** - Provides search, sort, filter, add buttons
✅ **ItemCard** - Supports selection, bookmarks, context menus, images
✅ **BottomSheetMenuList** - Sort/filter menu rendering with subactions
✅ **SharedItemPicker** - Advanced item picker with tabs, search, grouping

### Current Transaction Page Status

**Implemented:**
- Hero header, receipt/images, notes, details, tax
- Transaction items section with:
  - Basic `ListControlBar` (only "Add Item" button)
  - Item picker modal (Suggested/Project/Outside tabs)
  - Item cards with "View item" / "Remove from transaction" menu

**Missing:**
- ❌ Sort controls
- ❌ Filter controls
- ❌ Search functionality
- ❌ Bulk operations (selection/move/remove)
- ❌ Full context menu (only has 2 actions vs 10+ in legacy)

### Space Detail Screen Reference

The space detail screen (`app/project/[projectId]/spaces/[spaceId].tsx`) already implements the full pattern:

```typescript
// State management
const [sortMode, setSortMode] = useState<SortMode>('created-desc')
const [filterMode, setFilterMode] = useState<FilterMode>('all')
const [showSearch, setShowSearch] = useState(false)
const [searchQuery, setSearchQuery] = useState('')

// Control bar
<ItemsListControlBar
  search={searchQuery}
  onChangeSearch={setSearchQuery}
  showSearch={showSearch}
  onToggleSearch={() => setShowSearch(!showSearch)}
  onSort={() => setSortMenuVisible(true)}
  isSortActive={sortMode !== 'created-desc'}
  onFilter={() => setFilterMenuVisible(true)}
  isFilterActive={filterMode !== 'all'}
  onAdd={() => setAddMenuVisible(true)}
/>

// Sort/filter menus
<BottomSheetMenuList visible={sortMenuVisible} items={sortMenuItems} />
<BottomSheetMenuList visible={filterMenuVisible} items={filterMenuItems} />
```

---

## Phase 3: Implementation Specification

### 3.1 Gap Analysis

| Feature | Legacy Web | Current Mobile | Status |
|---------|-----------|----------------|--------|
| Search | ✅ (description, SKU, space, notes) | ❌ | **Add** |
| Sort | ✅ (2 options: alphabetical, price) | ❌ | **Add** |
| Filter | ✅ (6 options) | ❌ | **Add** |
| Bulk select | ✅ | ❌ | **Add** |
| Add item | ✅ | ✅ | ✅ **Working** |
| Item context menu | ✅ (10+ actions) | ⚠️ (2 actions) | **Expand** |
| Remove from transaction | ✅ | ✅ | ✅ **Working** |
| Bulk operations | ✅ | ❌ | **Add** |

### 3.2 Sort Options Configuration

**Mobile Implementation:**
```typescript
type TransactionItemSortMode =
  | 'alphabetical-asc'   // Name A → Z (matches legacy "Alphabetical")
  | 'alphabetical-desc'  // Name Z → A (opposite for completeness)
  | 'price-desc'         // Price high → low (matches legacy "Price descending")
  | 'price-asc'          // Price low → high (opposite for completeness)
  | 'created-desc'       // Newest first (mobile default, not in legacy)
  | 'created-asc'        // Oldest first (for completeness)

// Sort menu items
const sortMenuItems: AnchoredMenuItem[] = [
  {
    label: 'Sort by',
    subactions: [
      { key: 'alphabetical-asc', label: 'Name A → Z', onPress: () => setSortMode('alphabetical-asc') },
      { key: 'alphabetical-desc', label: 'Name Z → A', onPress: () => setSortMode('alphabetical-desc') },
      { key: 'price-desc', label: 'Price high → low', onPress: () => setSortMode('price-desc') },
      { key: 'price-asc', label: 'Price low → high', onPress: () => setSortMode('price-asc') },
      { key: 'created-desc', label: 'Newest first', onPress: () => setSortMode('created-desc') },
      { key: 'created-asc', label: 'Oldest first', onPress: () => setSortMode('created-asc') },
    ],
    selectedSubactionKey: sortMode,
  },
]
```

**Sort Logic:**
```typescript
const sortedItems = [...items].sort((a, b) => {
  if (sortMode === 'alphabetical-asc') return (a.name ?? '').localeCompare(b.name ?? '')
  if (sortMode === 'alphabetical-desc') return (b.name ?? '').localeCompare(a.name ?? '')
  if (sortMode === 'price-desc') return (b.price ?? 0) - (a.price ?? 0)
  if (sortMode === 'price-asc') return (a.price ?? 0) - (b.price ?? 0)
  if (sortMode === 'created-asc') return String(a.createdAt ?? '').localeCompare(String(b.createdAt ?? ''))
  return String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? ''))
})
```

### 3.3 Filter Options Configuration

**Mobile Implementation:**
```typescript
type TransactionItemFilterMode =
  | 'all'             // All items
  | 'bookmarked'      // Bookmarked items only
  | 'no-sku'          // Missing SKU
  | 'no-name'         // Missing name
  | 'no-price'        // Missing project price
  | 'no-image'        // No images uploaded

// Filter menu items (checkbox pattern with check icon)
const filterMenuItems: AnchoredMenuItem[] = [
  {
    key: 'all',
    label: 'All items',
    onPress: () => setFilterMode('all'),
    icon: filterMode === 'all' ? 'check' : undefined
  },
  {
    key: 'bookmarked',
    label: 'Bookmarked',
    onPress: () => setFilterMode('bookmarked'),
    icon: filterMode === 'bookmarked' ? 'check' : undefined
  },
  {
    key: 'no-sku',
    label: 'No SKU',
    onPress: () => setFilterMode('no-sku'),
    icon: filterMode === 'no-sku' ? 'check' : undefined
  },
  {
    key: 'no-name',
    label: 'No name',
    onPress: () => setFilterMode('no-name'),
    icon: filterMode === 'no-name' ? 'check' : undefined
  },
  {
    key: 'no-price',
    label: 'No project price',
    onPress: () => setFilterMode('no-price'),
    icon: filterMode === 'no-price' ? 'check' : undefined
  },
  {
    key: 'no-image',
    label: 'No image',
    onPress: () => setFilterMode('no-image'),
    icon: filterMode === 'no-image' ? 'check' : undefined
  },
]
```

**Filter Logic:**
```typescript
const filteredItems = items.filter((item) => {
  if (filterMode === 'bookmarked') return Boolean(item.bookmark)
  if (filterMode === 'no-sku') return !item.sku?.trim()
  if (filterMode === 'no-name') return !item.name?.trim()
  if (filterMode === 'no-price') return !item.price || item.price === 0
  if (filterMode === 'no-image') return !(item.images?.length > 0)
  return true // 'all'
})
```

### 3.4 Search Configuration

**Implementation:**
```typescript
const [showSearch, setShowSearch] = useState(false)
const [searchQuery, setSearchQuery] = useState('')

// Search logic (matches legacy: description, SKU, space, notes)
const searchedItems = items.filter((item) => {
  if (!searchQuery.trim()) return true
  const needle = searchQuery.trim().toLowerCase()
  const haystack = [
    item.name ?? '',
    item.sku ?? '',
    item.source ?? '',      // "source" is the mobile equivalent of "space" label
    item.notes ?? '',
  ].join(' ').toLowerCase()
  return haystack.includes(needle)
})
```

### 3.5 Item Context Menu (Enhanced)

**Current (2 actions):**
```typescript
const itemMenuItems: AnchoredMenuItem[] = [
  { label: 'View item', onPress: () => router.push(...) },
  { label: 'Remove from transaction', onPress: handleRemove, destructive: true },
]
```

**Target (Full feature parity):**
```typescript
const getItemMenuItems = (item: ProjectItem): AnchoredMenuItem[] => [
  {
    label: 'View item',
    onPress: () => router.push(`/items/${item.id}?accountId=${accountId}`)
  },
  {
    label: 'Edit',
    onPress: () => router.push(`/items/${item.id}/edit?accountId=${accountId}`)
  },
  {
    label: 'Make copies',
    onPress: () => handleDuplicateItem(item.id)
  },
  {
    label: 'Set space',
    onPress: () => handleSetSpace(item.id)
  },
  {
    label: 'Remove from transaction',
    onPress: () => handleRemoveFromTransaction(item.id),
    destructive: true
  },
  {
    label: 'Status',
    subactions: [
      { key: 'to-purchase', label: 'To Purchase', onPress: () => handleSetStatus(item.id, 'to-purchase') },
      { key: 'purchased', label: 'Purchased', onPress: () => handleSetStatus(item.id, 'purchased') },
      { key: 'to-return', label: 'To Return', onPress: () => handleSetStatus(item.id, 'to-return') },
      { key: 'returned', label: 'Returned', onPress: () => handleSetStatus(item.id, 'returned') },
    ],
    selectedSubactionKey: item.status,
  },
  {
    label: 'Sell',
    actionOnly: true,
    subactions: [
      { key: 'sell-to-design', label: 'Sell to Design Business', onPress: () => handleSellToDesign(item.id) },
      { key: 'sell-to-project', label: 'Sell to Project', onPress: () => handleSellToProject(item.id) },
    ],
  },
  {
    label: 'Move',
    actionOnly: true,
    subactions: [
      { key: 'move-to-design', label: 'Move to Design Business', onPress: () => handleMoveToDesign(item.id) },
      { key: 'move-to-project', label: 'Move to Project', onPress: () => handleMoveToProject(item.id) },
    ],
  },
  {
    label: 'Delete',
    onPress: () => handleDeleteItem(item.id),
    destructive: true
  },
]
```

**Note:** "Move to Return Transaction" action is conditional - only show when a return transaction exists for the current transaction.

### 3.6 Bulk Operations

**State Management:**
```typescript
const [selectedItemIds, setSelectedItemIds] = useState<Set<string>>(new Set())
const [bulkMode, setBulkMode] = useState(false)

const handleSelectAll = () => {
  if (selectedItemIds.size === filteredItems.length) {
    setSelectedItemIds(new Set()) // Deselect all
  } else {
    setSelectedItemIds(new Set(filteredItems.map(item => item.id))) // Select all
  }
}

const handleItemSelectionChange = (itemId: string, selected: boolean) => {
  setSelectedItemIds(prev => {
    const next = new Set(prev)
    if (selected) next.add(itemId)
    else next.delete(itemId)
    return next
  })
}
```

**Bulk Action Menu:**
```typescript
const bulkMenuItems: AnchoredMenuItem[] = [
  { label: 'Set space', onPress: () => handleBulkSetSpace() },
  { label: 'Set status', onPress: () => handleBulkSetStatus() },
  { label: 'Set SKU', onPress: () => handleBulkSetSKU() },
  { label: 'Remove from transaction', onPress: () => handleBulkRemove(), destructive: true },
  { label: 'Delete', onPress: () => handleBulkDelete(), destructive: true },
  { label: 'Clear selection', onPress: () => setSelectedItemIds(new Set()) },
]
```

**Control Bar with Bulk Mode:**
```typescript
// When items are selected, show bulk action button instead of Add button
{selectedItemIds.size > 0 ? (
  <ListControlBar
    actions={[
      { title: '', iconName: 'search', onPress: () => setShowSearch(!showSearch) },
      { title: 'Sort', iconName: 'sort', onPress: () => setSortMenuVisible(true), active: sortMode !== 'created-desc' },
      { title: 'Filter', iconName: 'filter-list', onPress: () => setFilterMenuVisible(true), active: filterMode !== 'all' },
      { title: `${selectedItemIds.size} selected`, variant: 'secondary', iconName: 'more-horiz', onPress: () => setBulkMenuVisible(true) },
    ]}
    search={searchQuery}
    onChangeSearch={setSearchQuery}
    showSearch={showSearch}
  />
) : (
  <ItemsListControlBar
    search={searchQuery}
    onChangeSearch={setSearchQuery}
    showSearch={showSearch}
    onToggleSearch={() => setShowSearch(!showSearch)}
    onSort={() => setSortMenuVisible(true)}
    isSortActive={sortMode !== 'created-desc'}
    onFilter={() => setFilterMenuVisible(true)}
    isFilterActive={filterMode !== 'all'}
    onAdd={() => setAddMenuVisible(true)}
  />
)}
```

### 3.7 File-by-File Changes

#### **File 1: `app/transactions/[id]/index.tsx`**

**Changes Required:**

1. **Import additions:**
```typescript
import { ItemsListControlBar } from '@/components/ItemsListControlBar'
import { BottomSheetMenuList } from '@/components/BottomSheetMenuList'
import type { AnchoredMenuItem } from '@/components/AnchoredMenuList'
```

2. **State additions:**
```typescript
// Sort/filter/search state
const [sortMode, setSortMode] = useState<TransactionItemSortMode>('created-desc')
const [sortMenuVisible, setSortMenuVisible] = useState(false)
const [filterMode, setFilterMode] = useState<TransactionItemFilterMode>('all')
const [filterMenuVisible, setFilterMenuVisible] = useState(false)
const [showSearch, setShowSearch] = useState(false)
const [searchQuery, setSearchQuery] = useState('')

// Bulk selection state
const [selectedItemIds, setSelectedItemIds] = useState<Set<string>>(new Set())
const [bulkMenuVisible, setBulkMenuVisible] = useState(false)
```

3. **Type definitions:**
```typescript
type TransactionItemSortMode =
  | 'alphabetical-asc' | 'alphabetical-desc'
  | 'price-desc' | 'price-asc'
  | 'created-desc' | 'created-asc'

type TransactionItemFilterMode =
  | 'all' | 'bookmarked' | 'no-sku'
  | 'no-name' | 'no-price' | 'no-image'
```

4. **Menu items (useMemo hooks):**
```typescript
const sortMenuItems = useMemo(() => [...], [sortMode])
const filterMenuItems = useMemo(() => [...], [filterMode])
const bulkMenuItems = useMemo(() => [...], [selectedItemIds.size])
```

5. **Filtering/sorting logic:**
```typescript
const filteredAndSortedItems = useMemo(() => {
  let result = transactionItems

  // Apply filter
  result = result.filter((item) => {
    if (filterMode === 'bookmarked') return Boolean(item.bookmark)
    if (filterMode === 'no-sku') return !item.sku?.trim()
    if (filterMode === 'no-name') return !item.name?.trim()
    if (filterMode === 'no-price') return !item.price || item.price === 0
    if (filterMode === 'no-image') return !(item.images?.length > 0)
    return true
  })

  // Apply search
  const needle = searchQuery.trim().toLowerCase()
  if (needle) {
    result = result.filter((item) => {
      const haystack = [item.name ?? '', item.sku ?? '', item.source ?? '', item.notes ?? ''].join(' ').toLowerCase()
      return haystack.includes(needle)
    })
  }

  // Apply sort
  return [...result].sort((a, b) => {
    if (sortMode === 'alphabetical-asc') return (a.name ?? '').localeCompare(b.name ?? '')
    if (sortMode === 'alphabetical-desc') return (b.name ?? '').localeCompare(a.name ?? '')
    if (sortMode === 'price-desc') return (b.price ?? 0) - (a.price ?? 0)
    if (sortMode === 'price-asc') return (a.price ?? 0) - (b.price ?? 0)
    if (sortMode === 'created-asc') return String(a.createdAt ?? '').localeCompare(String(b.createdAt ?? ''))
    return String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? ''))
  })
}, [transactionItems, searchQuery, sortMode, filterMode])
```

6. **Replace control bar:**
```typescript
// BEFORE (line ~450):
<ListControlBar
  actions={[
    {
      title: 'Add Item',
      variant: 'primary',
      iconName: 'add',
      onPress: () => setAddMenuVisible(true),
    },
  ]}
/>

// AFTER:
{selectedItemIds.size > 0 ? (
  <ListControlBar
    actions={[
      { title: '', iconName: 'search', onPress: () => setShowSearch(!showSearch) },
      { title: 'Sort', iconName: 'sort', onPress: () => setSortMenuVisible(true), active: sortMode !== 'created-desc' },
      { title: 'Filter', iconName: 'filter-list', onPress: () => setFilterMenuVisible(true), active: filterMode !== 'all' },
      { title: `${selectedItemIds.size} selected`, variant: 'secondary', iconName: 'more-horiz', onPress: () => setBulkMenuVisible(true) },
    ]}
    search={searchQuery}
    onChangeSearch={setSearchQuery}
    showSearch={showSearch}
  />
) : (
  <ItemsListControlBar
    search={searchQuery}
    onChangeSearch={setSearchQuery}
    showSearch={showSearch}
    onToggleSearch={() => setShowSearch(!showSearch)}
    onSort={() => setSortMenuVisible(true)}
    isSortActive={sortMode !== 'created-desc'}
    onFilter={() => setFilterMenuVisible(true)}
    isFilterActive={filterMode !== 'all'}
    onAdd={() => setAddMenuVisible(true)}
  />
)}
```

7. **Add bottom sheet menus:**
```typescript
{/* Sort menu */}
<BottomSheetMenuList
  visible={sortMenuVisible}
  onRequestClose={() => setSortMenuVisible(false)}
  items={sortMenuItems}
  title="Sort by"
  showLeadingIcons={false}
/>

{/* Filter menu */}
<BottomSheetMenuList
  visible={filterMenuVisible}
  onRequestClose={() => setFilterMenuVisible(false)}
  items={filterMenuItems}
  title="Filter items"
  showLeadingIcons={false}
/>

{/* Bulk actions menu */}
<BottomSheetMenuList
  visible={bulkMenuVisible}
  onRequestClose={() => setBulkMenuVisible(false)}
  items={bulkMenuItems}
  title="Bulk actions"
  showLeadingIcons={false}
/>
```

8. **Update ItemCard props:**
```typescript
<ItemCard
  key={item.id}
  // ... existing props
  selected={selectedItemIds.has(item.id)}
  onSelectedChange={(selected) => handleItemSelectionChange(item.id, selected)}
  menuItems={getItemMenuItems(item)}  // Use enhanced menu
/>
```

9. **Add bulk operation handlers:**
```typescript
const handleBulkSetSpace = () => { /* ... */ }
const handleBulkSetStatus = () => { /* ... */ }
const handleBulkSetSKU = () => { /* ... */ }
const handleBulkRemove = () => { /* ... */ }
const handleBulkDelete = () => { /* ... */ }
```

10. **Add enhanced item menu items:**
```typescript
const getItemMenuItems = (item: ProjectItem): AnchoredMenuItem[] => [
  // Full menu implementation from section 3.5
]
```

#### **File 2: `src/components/ItemCard.tsx`**

**No changes required** - component already supports all needed props:
- ✅ `selected` / `onSelectedChange` for bulk mode
- ✅ `menuItems` for context menu
- ✅ `bookmarked` / `onBookmarkPress` for bookmarking

#### **File 3: `src/components/ItemsListControlBar.tsx`**

**No changes required** - component is already fully functional and matches the needed interface.

#### **File 4: `src/components/ListControlBar.tsx`**

**No changes required** - base component is already flexible enough for bulk mode rendering.

### 3.8 State Management Approach

**Pattern:** Local state in transaction detail screen (same as space detail)

**Rationale:**
- Sort/filter/search preferences are transient (session-only)
- No need for global state or persistence
- Follows existing patterns in `app/project/[projectId]/spaces/[spaceId].tsx`

**State variables:**
```typescript
// UI state
const [sortMode, setSortMode] = useState<TransactionItemSortMode>('created-desc')
const [sortMenuVisible, setSortMenuVisible] = useState(false)
const [filterMode, setFilterMode] = useState<TransactionItemFilterMode>('all')
const [filterMenuVisible, setFilterMenuVisible] = useState(false)
const [showSearch, setShowSearch] = useState(false)
const [searchQuery, setSearchQuery] = useState('')
const [selectedItemIds, setSelectedItemIds] = useState<Set<string>>(new Set())
const [bulkMenuVisible, setBulkMenuVisible] = useState(false)

// Derived state
const filteredAndSortedItems = useMemo(() => {
  // Apply filter → search → sort
}, [transactionItems, searchQuery, sortMode, filterMode])
```

---

## 4. Implementation Checklist

### Phase A: Basic Controls (Sort/Filter/Search)

- [x] Add state variables for sort/filter/search
- [x] Add type definitions for `TransactionItemSortMode` and `TransactionItemFilterMode`
- [x] Create `sortMenuItems` useMemo hook
- [x] Create `filterMenuItems` useMemo hook
- [x] Create `filteredAndSortedItems` useMemo hook with filter/search/sort logic
- [x] Replace `ListControlBar` with `ItemsListControlBar`
- [x] Add sort `BottomSheetMenuList`
- [x] Add filter `BottomSheetMenuList`
- [x] Update item list to use `filteredAndSortedItems` instead of `transactionItems`
- [ ] Test sort options (alphabetical, price, created)
- [ ] Test filter options (all, bookmarked, no-sku, no-name, no-price, no-image)
- [ ] Test search across name, SKU, source, notes

### Phase B: Bulk Selection

- [x] Add `selectedItemIds` state (Set<string>)
- [x] Add `bulkMenuVisible` state
- [x] Add `handleSelectAll` function
- [x] Add `handleItemSelectionChange` function
- [x] Update `ItemCard` to pass `selected` and `onSelectedChange` props
- [x] Update control bar to show bulk actions when `selectedItemIds.size > 0`
- [x] Create `bulkMenuItems` useMemo hook
- [x] Add bulk menu `BottomSheetMenuList`

### Phase C: Enhanced Item Context Menu

- [ ] Create `getItemMenuItems` function
- [ ] Add "Edit" action
- [ ] Add "Make copies" action with handler
- [ ] Add "Set space" action with handler
- [ ] Add "Status" submenu with 4 status options
- [ ] Add "Sell" submenu with 2 sell options
- [ ] Add "Move" submenu with 2 move options
- [ ] Add "Delete" action with handler
- [ ] Test all menu actions
- [ ] Handle "Move to Return Transaction" conditional logic

### Phase D: Bulk Operation Handlers

- [ ] Implement `handleBulkSetSpace` - show space picker bottom sheet
- [ ] Implement `handleBulkSetStatus` - show status picker bottom sheet
- [ ] Implement `handleBulkSetSKU` - show SKU input bottom sheet
- [ ] Implement `handleBulkRemove` - remove selected items from transaction
- [ ] Implement `handleBulkDelete` - delete selected items with confirmation
- [ ] Add confirmation dialogs for destructive bulk operations
- [ ] Follow offline-first patterns (fire-and-forget Firestore writes)
- [ ] Call `trackPendingWrite()` after bulk operations

### Phase E: Polish & Testing

- [ ] Verify theme-aware colors (use `useTheme()` / `useThemeContext()`)
- [ ] Test in dark mode
- [ ] Test with 0 items (control bar should still show)
- [ ] Test with 1 item
- [ ] Test with 50+ items (performance)
- [ ] Test search with special characters
- [ ] Test sort with missing data (undefined name/price/createdAt)
- [ ] Test filter edge cases (item with multiple missing fields)
- [ ] Verify offline-first behavior (no network hangs)
- [ ] Verify pending write tracking for all operations
- [ ] Test bulk operations with mixed item types
- [ ] Run TypeScript checks (`npm run tsc`)
- [ ] Manual QA pass

---

## 5. Design Decisions (RESOLVED)

### ✅ Decision 1: "No Name" Filter - Field Mapping

**Question:** The legacy web app filters on "description" but mobile `ProjectItem` has both `name` and `notes`. Which field should the filter check?

**Decision:** Filter on `item.name` (not `item.notes`). Rename filter to "No Name" to clearly indicate what it checks.

**Rationale:**
- Checking for missing item names is more useful than missing notes
- Name is the primary identifier for items
- Makes the filter behavior clear and predictable

---

### ✅ Decision 2: Bulk "Set SKU" - UI Approach

**Question:** How should bulk "Set SKU" work?

**Decision:** Simple input - apply same SKU to all selected items.

**Rationale:**
- Matches legacy behavior
- Clear and predictable
- User can manually adjust individual items after bulk operation if needed

**Implementation:** Show a text input dialog/bottom sheet, apply the entered SKU to all selected items using fire-and-forget Firestore writes.

---

### ✅ Decision 3: "Move to Return Transaction" - Creation Flow

**Question:** If no return transaction exists, should the action create one, prompt user, or be hidden?

**Decision:** Hide/disable action until return transaction exists (conditional visibility).

**Rationale:**
- Safest approach - no accidental transaction creation
- Matches legacy conditional logic
- User must explicitly create return transaction first

**Implementation:** Check if transaction has an associated return transaction ID, only show "Move to Return Transaction" menu item when one exists.

---

### ✅ Decision 4: Sort/Filter State Persistence

**Question:** Should sort/filter preferences persist across sessions?

**Decision:** No persistence - session-only state.

**Rationale:**
- Matches existing space detail screen behavior
- Simpler implementation
- Users typically adjust sort/filter per-session based on current task
- Can be added later if user feedback indicates need

**Implementation:** Use local component state (`useState`) - no AsyncStorage or persistence layer needed.

---

## 6. Success Criteria

✅ **Feature parity achieved when:**

1. Transaction items section has same controls as legacy web app:
   - Search (description, SKU, source, notes)
   - Sort (6 options: alphabetical asc/desc, price asc/desc, created asc/desc)
   - Filter (6 options: all, bookmarked, no-sku, no-name, no-price, no-image)
   - Bulk selection and operations

2. Item cards have full context menus with:
   - Edit, Make Copies, Set Space
   - Remove from Transaction
   - Status submenu (4 options)
   - Sell submenu (2 options)
   - Move submenu (2 options)
   - Delete

3. Bulk operations work for:
   - Set Space
   - Set Status
   - Set SKU
   - Remove from Transaction
   - Delete

4. UI matches mobile design patterns:
   - Uses `ItemsListControlBar` component
   - Bottom sheet menus for sort/filter/bulk
   - Theme-aware colors
   - Responsive layout

5. Offline-first architecture maintained:
   - No awaited Firestore writes in UI
   - Fire-and-forget with `.catch()`
   - `trackPendingWrite()` called after operations
   - No "spinners of doom"

---

## 7. Timeline Estimate

**Total effort:** ~6-8 hours (single developer)

- **Phase A (Basic Controls):** 2-3 hours
- **Phase B (Bulk Selection):** 1-2 hours
- **Phase C (Enhanced Menus):** 2-3 hours
- **Phase D (Bulk Handlers):** 1-2 hours
- **Phase E (Polish & Testing):** 1-2 hours

**Parallelization opportunity:** Phases A/B/C can be tackled in separate PRs if needed.

---

## 8. References

**Legacy Web App:**
- `/Users/benjaminmackenzie/Dev/ledger/src/components/ProjectItems/ProjectItems.tsx`
- `/Users/benjaminmackenzie/Dev/ledger/src/components/transaction/TransactionItems.tsx`

**Mobile App:**
- `app/transactions/[id]/index.tsx` (implementation target)
- `app/project/[projectId]/spaces/[spaceId].tsx` (reference implementation)
- `src/components/ItemsListControlBar.tsx` (control bar)
- `src/components/ItemCard.tsx` (item card)
- `src/components/BottomSheetMenuList.tsx` (menus)

**Architecture:**
- `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`
- `CLAUDE.md` (offline-first coding rules)

---

## Status Tracking

**Phase A:** ✅ Completed (2026-02-08)
**Phase B:** ✅ Completed (2026-02-08)
**Phase C:** ⏳ Not started
**Phase D:** ⏳ Not started
**Phase E:** ⏳ Not started

**Last updated:** 2026-02-08
