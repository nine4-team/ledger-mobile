import { useState, useMemo, useCallback, useEffect } from 'react';
import type { ScopedItem } from '../data/scopedListData';

/**
 * Base sort modes supported by all screens.
 * Screens can extend this with additional modes via generics.
 */
export type BaseSortMode = 'created-desc' | 'created-asc' | 'alphabetical-asc' | 'alphabetical-desc';

/**
 * Configuration for useItemsManager hook.
 *
 * @template S - Sort mode union type (extends string)
 * @template F - Filter mode union type (extends string)
 */
export type UseItemsManagerConfig<S extends string = BaseSortMode, F extends string = string> = {
  /** The items to manage */
  items: ScopedItem[];

  /** Default sort mode (defaults to first in sortModes array) */
  defaultSort?: S;

  /** Default filter mode (defaults to first in filterModes array) */
  defaultFilter?: F;

  /** Available sort modes for this screen */
  sortModes: S[];

  /** Available filter modes for this screen */
  filterModes: F[];

  /** Fields to search (defaults to ['name', 'sku', 'source', 'notes']) */
  searchFields?: (keyof ScopedItem)[];

  /** Custom filter function (optional - hook provides built-in filters) */
  filterFn?: (item: ScopedItem, filterMode: F) => boolean;

  /** Custom sort function (optional - hook provides built-in sorts for BaseSortMode) */
  sortFn?: (a: ScopedItem, b: ScopedItem, sortMode: S) => number;
};

/**
 * Return type for useItemsManager hook.
 *
 * @template S - Sort mode union type (extends string)
 * @template F - Filter mode union type (extends string)
 */
export type UseItemsManagerReturn<S extends string = BaseSortMode, F extends string = string> = {
  // Derived data
  /** Items after applying filter, search, and sort */
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
  /** True if sort mode differs from default */
  isSortActive: boolean;

  // Filter
  filterMode: F;
  setFilterMode: (mode: F) => void;
  filterMenuVisible: boolean;
  setFilterMenuVisible: (v: boolean) => void;
  /** True if filter mode differs from default */
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

/**
 * useItemsManager - Reusable hook for managing items lists with search, sort, filter, and selection.
 *
 * Provides unified state management for items displayed in list screens (transaction detail, space detail, etc).
 * Handles search query, sort mode, filter mode, and multi-select with Set-based IDs for O(1) lookups.
 *
 * @example
 * ```tsx
 * const manager = useItemsManager({
 *   items: allItems,
 *   sortModes: ['created-desc', 'alphabetical-asc'],
 *   filterModes: ['all', 'bookmarked', 'no-sku'],
 * });
 *
 * // Use filtered items in your list
 * <FlatList data={manager.filteredAndSortedItems} ... />
 * ```
 */
export function useItemsManager<S extends string = BaseSortMode, F extends string = string>(
  config: UseItemsManagerConfig<S, F>
): UseItemsManagerReturn<S, F> {
  // ============================================================================
  // T018: Search, sort, and filter state
  // ============================================================================

  // Search state
  const [searchQuery, setSearchQuery] = useState('');
  const [showSearch, setShowSearch] = useState(false);

  const toggleSearch = useCallback(() => {
    setShowSearch((prev) => {
      if (prev) setSearchQuery(''); // Clear search when hiding
      return !prev;
    });
  }, []);

  // Sort state
  const [sortMode, setSortMode] = useState<S>(config.defaultSort ?? config.sortModes[0]);
  const [sortMenuVisible, setSortMenuVisible] = useState(false);
  const isSortActive = sortMode !== (config.defaultSort ?? config.sortModes[0]);

  // Filter state
  const [filterMode, setFilterMode] = useState<F>(config.defaultFilter ?? config.filterModes[0]);
  const [filterMenuVisible, setFilterMenuVisible] = useState(false);
  const isFilterActive = filterMode !== (config.defaultFilter ?? config.filterModes[0]);

  // ============================================================================
  // T019: Filtered and sorted items computation
  // ============================================================================

  const filteredAndSortedItems = useMemo(() => {
    let result = [...config.items];

    // Step 1: Apply filter
    const defaultFilterMode = config.defaultFilter ?? config.filterModes[0];

    if (filterMode !== defaultFilterMode) {
      if (config.filterFn) {
        // Use custom filter function if provided
        result = result.filter((item) => config.filterFn!(item, filterMode));
      } else {
        // Built-in filters for common filter modes
        result = result.filter((item) => {
          switch (filterMode as string) {
            case 'bookmarked':
              return item.bookmark === true;
            case 'no-sku':
              return !item.sku?.trim();
            case 'no-image':
              return !item.images?.length;
            case 'no-name':
              return !item.name?.trim();
            case 'no-price':
              return item.purchasePriceCents == null;
            default:
              return true;
          }
        });
      }
    }

    // Step 2: Apply search
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase().trim();
      const fields = config.searchFields ?? ['name', 'sku', 'source', 'notes'];
      result = result.filter((item) =>
        fields.some((field) => {
          const value = item[field];
          return typeof value === 'string' && value.toLowerCase().includes(query);
        })
      );
    }

    // Step 3: Apply sort
    if (config.sortFn) {
      // Use custom sort function if provided
      result.sort((a, b) => config.sortFn!(a, b, sortMode));
    } else {
      // Built-in sort for base modes
      result.sort((a, b) => {
        switch (sortMode as string) {
          case 'created-desc':
            return (
              ((b.createdAt as any)?.toMillis?.() ?? 0) - ((a.createdAt as any)?.toMillis?.() ?? 0)
            );
          case 'created-asc':
            return (
              ((a.createdAt as any)?.toMillis?.() ?? 0) - ((b.createdAt as any)?.toMillis?.() ?? 0)
            );
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
  }, [
    config.items,
    config.filterFn,
    config.sortFn,
    config.searchFields,
    config.defaultFilter,
    config.filterModes,
    filterMode,
    searchQuery,
    sortMode,
  ]);

  // ============================================================================
  // T020: Selection state and handlers
  // ============================================================================

  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  const toggleSelection = useCallback((id: string) => {
    setSelectedIds((prev) => {
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
    setSelectedIds(new Set(filteredAndSortedItems.map((item) => item.id)));
  }, [filteredAndSortedItems]);

  const clearSelection = useCallback(() => {
    setSelectedIds(new Set());
  }, []);

  // Derived selection values
  const hasSelection = selectedIds.size > 0;
  const selectionCount = selectedIds.size;
  const allSelected =
    filteredAndSortedItems.length > 0 &&
    filteredAndSortedItems.every((item) => selectedIds.has(item.id));

  // Clear selection when filter changes (matches current space detail behavior)
  useEffect(() => {
    setSelectedIds(new Set());
  }, [filterMode]);

  // ============================================================================
  // Return
  // ============================================================================

  return {
    // Derived data
    filteredAndSortedItems,

    // Search
    searchQuery,
    setSearchQuery,
    showSearch,
    toggleSearch,

    // Sort
    sortMode,
    setSortMode,
    sortMenuVisible,
    setSortMenuVisible,
    isSortActive,

    // Filter
    filterMode,
    setFilterMode,
    filterMenuVisible,
    setFilterMenuVisible,
    isFilterActive,

    // Selection
    selectedIds,
    toggleSelection,
    selectAll,
    clearSelection,
    hasSelection,
    allSelected,
    selectionCount,
  };
}
