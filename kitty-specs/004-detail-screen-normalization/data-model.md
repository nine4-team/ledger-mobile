# Data Model: Detail Screen Normalization

**Feature**: 004-detail-screen-normalization
**Date**: 2026-02-09

This feature does not introduce new data entities. It extracts shared UI patterns from existing detail screens. This document defines the component interfaces and type contracts.

## 1. Shared Types

### Section Definition
```typescript
// Generic section type used by all detail screens with SectionList
type DetailSection<K extends string = string> = {
  key: K;
  title?: string;
  data: any[];
  badge?: string;
};

// Sentinel for non-sticky section headers rendered as data items
const SECTION_HEADER_MARKER = '__sectionHeader__';
```

### Collapsed State
```typescript
// Per-screen default collapsed states (configurable)
type CollapsedSections<K extends string = string> = Record<K, boolean>;
```

## 2. SpaceDetailContent Component

### Props
```typescript
type SpaceScope = {
  projectId: string | null;  // null = business inventory, string = project
  spaceId: string;
};

type SpaceDetailContentProps = {
  scope: SpaceScope;
};
```

### Derived Behavior
| projectId | Scope Config | Picker Tab Label | Back Target | Item Scope |
|-----------|-------------|------------------|-------------|------------|
| `null` | `createInventoryScopeConfig()` | "In Business Inventory" | `/business-inventory/spaces` | `'inventory'` |
| `string` | `createProjectScopeConfig(projectId)` | "Project" | `/project/${projectId}?tab=spaces` | `'project'` |

### Route Wrappers
```typescript
// app/business-inventory/spaces/[spaceId].tsx
export default function BISpaceDetailScreen() {
  const { spaceId } = useLocalSearchParams<{ spaceId: string }>();
  if (!spaceId) return <NotFound />;
  return <SpaceDetailContent scope={{ projectId: null, spaceId }} />;
}

// app/project/[projectId]/spaces/[spaceId].tsx
export default function ProjectSpaceDetailScreen() {
  const { projectId, spaceId } = useLocalSearchParams<{ projectId: string; spaceId: string }>();
  if (!projectId || !spaceId) return <NotFound />;
  return <SpaceDetailContent scope={{ projectId, spaceId }} />;
}
```

## 3. useItemsManager Hook

### Input Config
```typescript
type SortMode = 'created-desc' | 'created-asc' | 'alphabetical-asc' | 'alphabetical-desc';
type FilterMode = string;  // screen-specific filter values

type UseItemsManagerConfig = {
  items: ScopedItem[];
  defaultSort?: SortMode;           // default: 'created-desc'
  defaultFilter?: FilterMode;       // default: 'all'
  sortModes: SortMode[];            // available sort options
  filterModes: FilterMode[];        // available filter options
  searchFields?: (keyof ScopedItem)[];  // fields to search (default: ['name', 'sku', 'source', 'notes'])
  filterFn?: (item: ScopedItem, filterMode: FilterMode) => boolean;  // custom filter logic
};
```

### Return Value
```typescript
type UseItemsManagerReturn = {
  // Derived data
  filteredAndSortedItems: ScopedItem[];

  // Search
  searchQuery: string;
  setSearchQuery: (q: string) => void;
  showSearch: boolean;
  toggleSearch: () => void;

  // Sort
  sortMode: SortMode;
  setSortMode: (mode: SortMode) => void;
  sortMenuVisible: boolean;
  setSortMenuVisible: (v: boolean) => void;
  isSortActive: boolean;

  // Filter
  filterMode: FilterMode;
  setFilterMode: (mode: FilterMode) => void;
  filterMenuVisible: boolean;
  setFilterMenuVisible: (v: boolean) => void;
  isFilterActive: boolean;

  // Selection
  selectedIds: Set<string>;
  toggleSelection: (id: string) => void;
  selectAll: () => void;
  clearSelection: () => void;
  hasSelection: boolean;
  allSelected: boolean;
  selectionCount: number;
};
```

## 4. ItemsSection Component

### Props
```typescript
type ItemsSectionProps = {
  // From useItemsManager
  manager: UseItemsManagerReturn;

  // Item rendering
  items: ScopedItem[];
  onItemPress: (id: string) => void;
  getItemMenuItems: (item: ScopedItem) => AnchoredMenuItem[];
  onBookmarkPress?: (item: ScopedItem) => void;

  // Control bar
  onAdd: () => void;
  controlBarLeftElement?: React.ReactNode;

  // Bulk actions (screen-specific)
  bulkActions?: BulkAction[];
  onBulkAction?: (actionId: string, selectedIds: string[]) => void;

  // Display
  emptyMessage?: string;
};

type BulkAction = {
  id: string;
  label: string;
  variant: 'primary' | 'secondary' | 'destructive';
  icon?: string;
};
```

## 5. DetailRow Component

### Props
```typescript
type DetailRowProps = {
  label: string;
  value: string | React.ReactNode;
  showDivider?: boolean;  // default: true (last row should set false)
  onPress?: () => void;   // optional tap action
};
```

### Usage
```tsx
// In any detail screen's Details section:
<Card>
  <DetailRow label="Source" value={transaction.source ?? '—'} />
  <DetailRow label="Date" value={formatDate(transaction.transactionDate)} />
  <DetailRow label="Amount" value={formatMoney(transaction.amountCents)} />
  <DetailRow label="Status" value={transaction.status ?? '—'} showDivider={false} />
</Card>
```

## 6. Section Definitions Per Screen

### Transaction Detail (existing, reference)
| Section Key | Title | Sticky | Default State | Content |
|------------|-------|--------|---------------|---------|
| `hero` | — | No | Always visible | HeroSection |
| `receipts` | RECEIPTS | No | Expanded | ReceiptsSection (MediaGallerySection) |
| `otherImages` | OTHER IMAGES | No | Collapsed | OtherImagesSection (MediaGallerySection) |
| `notes` | NOTES | No | Collapsed | NotesSection |
| `details` | DETAILS | No | Collapsed | DetailsSection (DetailRow x N) |
| `taxes` | TAX & ITEMIZATION | No | Collapsed | TaxesSection (conditional) |
| `items` | TRANSACTION ITEMS | **Yes** | Collapsed | ItemsSection |
| `audit` | TRANSACTION AUDIT | No | Collapsed | AuditSection |

### Item Detail (to be migrated)
| Section Key | Title | Sticky | Default State | Content |
|------------|-------|--------|---------------|---------|
| `hero` | — | No | Always visible | Hero card (name + transaction link) |
| `media` | IMAGES | No | Expanded | MediaGallerySection |
| `notes` | NOTES | No | Collapsed | NotesSection |
| `details` | DETAILS | No | Collapsed | DetailRow x N (SKU, prices, space, category) |

### Space Detail (to be migrated)
| Section Key | Title | Sticky | Default State | Content |
|------------|-------|--------|---------------|---------|
| `media` | IMAGES | No | Expanded | MediaGallerySection (no cap) |
| `notes` | NOTES | No | Collapsed | NotesSection |
| `items` | ITEMS | **Yes** | Expanded | ItemsSection + bulk ops |
| `checklists` | CHECKLISTS | No | Collapsed | Checklist cards |
