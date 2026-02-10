---
work_package_id: WP04
title: Extract useItemsManager Hook
lane: "doing"
dependencies: []
base_branch: main
base_commit: 2f7c959f279431af650f173f031787246dfcfb38
created_at: '2026-02-10T03:41:28.658645+00:00'
subtasks:
- T017
- T018
- T019
- T020
phase: Phase 2 - Shared Items Management
assignee: ''
agent: ''
shell_pid: "39956"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-10T02:25:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP04 – Extract useItemsManager Hook

## Important: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP04
```

No dependencies — this creates a standalone new hook. Can run in parallel with WP01-WP03.

---

## Objectives & Success Criteria

- **Objective**: Extract the duplicated items management state and logic (search, sort, filter, selection) from transaction detail (~120 lines) and space detail (~100 lines) into a reusable `useItemsManager` hook.
- Supports **User Story 3** (shared items management) by providing the state management foundation.

**Success Criteria**:
1. `src/hooks/useItemsManager.ts` exports a complete hook with typed config and return value
2. Hook manages: search query + visibility, sort mode + menu, filter mode + menu, selection (Set-based)
3. Hook computes `filteredAndSortedItems` via a 3-step pipeline (filter → search → sort)
4. TypeScript types are well-defined and exported for consumers
5. Hook is pure state management — no rendering, no service calls, no side effects
6. Hook API accommodates both transaction detail (6 sort modes, 6 filter modes) and space detail (4 sort modes, 4 filter modes) via config

## Context & Constraints

**Reference: data-model.md** — Section 3 defines the complete `UseItemsManagerConfig` and `UseItemsManagerReturn` types. Follow those exactly.

**Current duplication across screens**:

| State/Logic | Transaction Detail | Space Detail |
|-------------|-------------------|--------------|
| `searchQuery` / `showSearch` | `useState` | `useState` |
| `sortMode` | 6 modes + price sort | 4 modes |
| `filterMode` | 6 modes (all, bookmarked, no-sku, no-name, no-price, no-image) | 4 modes (all, bookmarked, no-sku, no-image) |
| `selectedIds` | `Set<string>` via `useState` | `string[]` via `useState` |
| `sortMenuVisible` / `filterMenuVisible` | `useState` | `useState` |
| Filtered+sorted computation | `useMemo` 3-step pipeline | `useMemo` 3-step pipeline |
| Selection handlers | toggle, selectAll, clear | toggle, selectAll, clear (via bulkSelectedIds) |

**Key design decisions**:
- Selection uses `Set<string>` (not `string[]`) for O(1) lookups — transaction detail already uses this
- Sort modes are configurable via `sortModes` array, not hardcoded
- Filter modes are configurable; custom `filterFn` escape hatch for screen-specific logic
- Search fields are configurable (default: `['name', 'sku', 'source', 'notes']`)

---

## Subtasks & Detailed Guidance

### Subtask T017 – Define types and create hook skeleton

**Purpose**: Establish the file with all TypeScript types and the hook signature.

**Steps**:
1. Create `src/hooks/useItemsManager.ts`
2. Define the shared sort mode type:
   ```typescript
   export type BaseSortMode = 'created-desc' | 'created-asc' | 'alphabetical-asc' | 'alphabetical-desc';
   ```
3. Define config type (from data-model.md):
   ```typescript
   export type UseItemsManagerConfig<S extends string = BaseSortMode, F extends string = string> = {
     items: ScopedItem[];
     defaultSort?: S;
     defaultFilter?: F;
     sortModes: S[];
     filterModes: F[];
     searchFields?: (keyof ScopedItem)[];
     filterFn?: (item: ScopedItem, filterMode: F) => boolean;
     sortFn?: (a: ScopedItem, b: ScopedItem, sortMode: S) => number;
   };
   ```
4. Define return type:
   ```typescript
   export type UseItemsManagerReturn<S extends string = BaseSortMode, F extends string = string> = {
     // Derived data
     filteredAndSortedItems: ScopedItem[];

     // Search
     searchQuery: string;
     setSearchQuery: (q: string) => void;
     showSearch: boolean;
     toggleSearch: () => void;

     // Sort
     sortMode: S;
     setSortMode: (mode: S) => void;
     sortMenuVisible: boolean;
     setSortMenuVisible: (v: boolean) => void;
     isSortActive: boolean;

     // Filter
     filterMode: F;
     setFilterMode: (mode: F) => void;
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
5. Create the hook function with config parameter and empty return:
   ```typescript
   export function useItemsManager<S extends string = BaseSortMode, F extends string = string>(
     config: UseItemsManagerConfig<S, F>
   ): UseItemsManagerReturn<S, F> {
     // T018-T020 fill this in
   }
   ```
6. Import `ScopedItem` type from items service (check existing import path in transaction/space screens)

**Files**:
- `src/hooks/useItemsManager.ts` (new, ~60 lines for types + skeleton)

**Notes**:
- Generic type parameters `<S, F>` allow screens to pass screen-specific sort/filter mode unions
- `ScopedItem` is the existing item type used across all screens — import from the items service

---

### Subtask T018 – Implement search, sort, and filter state

**Purpose**: Set up all the controlled state for search, sort, filter, and their associated menu visibility.

**Steps**:
1. Add state for search:
   ```typescript
   const [searchQuery, setSearchQuery] = useState('');
   const [showSearch, setShowSearch] = useState(false);

   const toggleSearch = useCallback(() => {
     setShowSearch(prev => {
       if (prev) setSearchQuery(''); // Clear search when hiding
       return !prev;
     });
   }, []);
   ```

2. Add state for sort:
   ```typescript
   const [sortMode, setSortMode] = useState<S>(config.defaultSort ?? config.sortModes[0]);
   const [sortMenuVisible, setSortMenuVisible] = useState(false);
   const isSortActive = sortMode !== (config.defaultSort ?? config.sortModes[0]);
   ```

3. Add state for filter:
   ```typescript
   const [filterMode, setFilterMode] = useState<F>(config.defaultFilter ?? config.filterModes[0]);
   const [filterMenuVisible, setFilterMenuVisible] = useState(false);
   const isFilterActive = filterMode !== (config.defaultFilter ?? config.filterModes[0]);
   ```

4. Wire into the return object

**Files**:
- `src/hooks/useItemsManager.ts` (modify)

**Notes**:
- `isSortActive` and `isFilterActive` compare against the default mode. This drives the visual indicator on the control bar buttons.
- When search is toggled off, clear the search query to avoid stale filter results.

---

### Subtask T019 – Implement filtered and sorted items computation

**Purpose**: Create the `filteredAndSortedItems` useMemo that applies the 3-step pipeline: filter → search → sort.

**Steps**:
1. Implement the computation:
   ```typescript
   const filteredAndSortedItems = useMemo(() => {
     let result = [...config.items];

     // Step 1: Apply filter
     if (config.filterFn && filterMode !== (config.defaultFilter ?? config.filterModes[0])) {
       result = result.filter(item => config.filterFn!(item, filterMode));
     }

     // Step 2: Apply search
     if (searchQuery.trim()) {
       const query = searchQuery.toLowerCase().trim();
       const fields = config.searchFields ?? ['name', 'sku', 'source', 'notes'];
       result = result.filter(item =>
         fields.some(field => {
           const value = item[field];
           return typeof value === 'string' && value.toLowerCase().includes(query);
         })
       );
     }

     // Step 3: Apply sort
     if (config.sortFn) {
       result.sort((a, b) => config.sortFn!(a, b, sortMode));
     } else {
       // Built-in sort for base modes
       result.sort((a, b) => {
         switch (sortMode as string) {
           case 'created-desc':
             return (b.createdAt?.toMillis?.() ?? 0) - (a.createdAt?.toMillis?.() ?? 0);
           case 'created-asc':
             return (a.createdAt?.toMillis?.() ?? 0) - (b.createdAt?.toMillis?.() ?? 0);
           case 'alphabetical-asc':
             return (a.name ?? '').localeCompare(b.name ?? '');
           case 'alphabetical-desc':
             return (b.name ?? '').localeCompare(a.name ?? '');
           default:
             return 0;
         }
       });
     }

     return result;
   }, [config.items, config.filterFn, config.sortFn, config.searchFields,
       config.defaultFilter, config.filterModes, filterMode, searchQuery, sortMode]);
   ```

2. **Built-in filter logic** (optional, for common filter modes):
   If `filterFn` is not provided but `filterMode` is set, the hook can provide built-in handling for common modes:
   ```typescript
   // Built-in filters when no custom filterFn provided
   if (!config.filterFn && filterMode !== (config.defaultFilter ?? config.filterModes[0])) {
     result = result.filter(item => {
       switch (filterMode as string) {
         case 'bookmarked': return item.bookmark === true;
         case 'no-sku': return !item.sku?.trim();
         case 'no-image': return !item.images?.length;
         case 'no-name': return !item.name?.trim();
         case 'no-price': return item.purchasePriceCents == null;
         default: return true;
       }
     });
   }
   ```

3. The computation must be efficient — it runs on every items change, search keystroke, or sort/filter change.

**Files**:
- `src/hooks/useItemsManager.ts` (modify)

**Edge Cases**:
- `createdAt` may be a Firestore Timestamp or null — handle with `?.toMillis?.()` fallback to 0
- Empty items array → returns empty array (no error)
- All items filtered out → returns empty array (empty state shown by consumer)

---

### Subtask T020 – Implement selection state and handlers

**Purpose**: Provide Set-based selection management for bulk operations.

**Steps**:
1. Add selection state:
   ```typescript
   const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
   ```

2. Implement handlers:
   ```typescript
   const toggleSelection = useCallback((id: string) => {
     setSelectedIds(prev => {
       const next = new Set(prev);
       if (next.has(id)) {
         next.delete(id);
       } else {
         next.add(id);
       }
       return next;
     });
   }, []);

   const selectAll = useCallback(() => {
     // Select all currently FILTERED items (not all items)
     setSelectedIds(new Set(filteredAndSortedItems.map(item => item.id)));
   }, [filteredAndSortedItems]);

   const clearSelection = useCallback(() => {
     setSelectedIds(new Set());
   }, []);
   ```

3. Compute derived values:
   ```typescript
   const hasSelection = selectedIds.size > 0;
   const selectionCount = selectedIds.size;
   const allSelected = filteredAndSortedItems.length > 0 &&
     filteredAndSortedItems.every(item => selectedIds.has(item.id));
   ```

4. **Clear selection on filter/sort change**: When the filter or sort changes, the visible items change. Selection should be preserved unless items are removed from view. An alternative is to clear selection on filter change — match existing behavior:
   ```typescript
   // Clear selection when filter changes (matches current space detail behavior)
   useEffect(() => {
     setSelectedIds(new Set());
   }, [filterMode]);
   ```

5. Wire everything into the return object.

**Files**:
- `src/hooks/useItemsManager.ts` (modify)

**Notes**:
- `selectAll` selects only filtered items — if 100 items exist but filter shows 10, selectAll selects 10
- Transaction detail uses `Set<string>` for selectedIds; space detail uses `string[]`. The hook standardizes on `Set<string>` for O(1) lookups. Consumers that used `string[]` will need to adapt (handled in WP05 integration)
- The hook does NOT manage bulk action menus or modals — those are screen-specific UI handled by the consumer

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Hook API doesn't fit all screens | Medium | Medium | Designed from research on all 3 consumers. Generic types + filterFn/sortFn escape hatches |
| Sort mode type differences | Low | Low | Generic `<S>` parameter lets each screen pass its own union type |
| Selection behavior mismatch | Low | Low | Standardize on Set (transaction already uses it); space adapts in WP05 |

## Review Guidance

1. Verify all types are exported and well-documented
2. Check filteredAndSortedItems pipeline handles edge cases (empty, all filtered out, null fields)
3. Verify selectAll selects only filtered items
4. Check that isSortActive/isFilterActive compute correctly from defaults
5. No side effects — hook is pure state management
6. No imports of Firestore/service code — hook is data-agnostic

---

## Activity Log

- 2026-02-10T02:25:42Z – system – lane=planned – Prompt created.
