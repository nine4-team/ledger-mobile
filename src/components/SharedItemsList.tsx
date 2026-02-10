import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, FlatList, Pressable, RefreshControl, StyleSheet, TextInput, TouchableOpacity, View } from 'react-native';
import { useRouter } from 'expo-router';
import { AppText } from './AppText';
import { AppButton } from './AppButton';
import { ItemsListControlBar } from './ItemsListControlBar';
import { ListSelectAllRow } from './ListSelectionControls';
import { SelectorCircle } from './SelectorCircle';
import { BUTTON_BORDER_RADIUS } from '../ui';
import { BottomSheet } from './BottomSheet';
import { GroupedItemCard } from './GroupedItemCard';
import { ItemCard } from './ItemCard';
import type { ItemCardProps } from './ItemCard';
import { FilterMenu } from './FilterMenu';
import { SortMenu } from './SortMenu';
import { BulkSelectionBar } from './BulkSelectionBar';
import { useScreenRefresh } from './Screen';
import { useListState } from '../data/listStateStore';
import { getScopeId, ScopeConfig } from '../data/scopeConfig';
import { getTextColorStyle, layout } from '../ui';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { useAccountContextStore } from '../auth/accountContextStore';
import { useScopedListeners } from '../data/useScopedListeners';
import { refreshScopedItems, ScopedItem, subscribeToScopedItems } from '../data/scopedListData';
import { deleteItem, updateItem } from '../data/itemsService';
import { requestBusinessToProjectPurchase, requestProjectToBusinessSale } from '../data/inventoryOperations';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../data/budgetCategoriesService';
import { resolveAttachmentUri } from '../offline/media';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { BottomSheetMenuList } from './BottomSheetMenuList';

type BulkAction = {
  id: string;
  label: string;
  onPress: (selectedIds: string[]) => void;
  destructive?: boolean;
};

type UseItemsManagerReturn = {
  selectedIds: string[];
  selectAll: () => void;
  clearSelection: () => void;
  setItemSelected: (id: string, selected: boolean) => void;
  setGroupSelection: (ids: string[], selected: boolean) => void;
};

type SharedItemsListProps = {
  // Standalone mode props (optional when embedded=true)
  scopeConfig?: ScopeConfig;
  listStateKey?: string;
  refreshToken?: number;

  // Embedded mode props
  embedded?: boolean;
  manager?: UseItemsManagerReturn;
  items?: ScopedItem[];
  bulkActions?: BulkAction[];
  onItemPress?: (id: string) => void;
  getItemMenuItems?: (item: ScopedItem) => AnchoredMenuItem[];
  emptyMessage?: string;
};

type ItemRow = {
  id: string;
  label: string;
  subtitle?: string;
  item: ScopedItem;
};

type ItemFilterMode =
  | 'all'
  | 'bookmarked'
  | 'from-inventory'
  | 'to-return'
  | 'returned'
  | 'no-sku'
  | 'no-name'
  | 'no-project-price'
  | 'no-image'
  | 'no-transaction';

type ItemFilters = {
  mode?: ItemFilterMode | ItemFilterMode[];
  showDuplicates?: boolean;
};

type ListRow =
  | { type: 'group'; groupId: string; label: string; count: number; items: ItemRow[] }
  | { type: 'item'; item: ItemRow; groupId?: string };

const SORT_MODES = ['created-desc', 'created-asc', 'alphabetical-asc', 'alphabetical-desc'] as const;
type SortMode = (typeof SORT_MODES)[number];
const DEFAULT_SORT: SortMode = 'created-desc';

const PROJECT_FILTER_MODES: ItemFilterMode[] = [
  'all',
  'bookmarked',
  'from-inventory',
  'to-return',
  'returned',
  'no-sku',
  'no-name',
  'no-project-price',
  'no-image',
  'no-transaction',
];

const INVENTORY_FILTER_MODES: ItemFilterMode[] = [
  'all',
  'bookmarked',
  'no-sku',
  'no-name',
  'no-project-price',
  'no-image',
  'no-transaction',
];

function normalizeSku(value: string) {
  return value.replace(/[^a-z0-9]/gi, '').toLowerCase();
}

function formatCents(value?: number | null) {
  if (typeof value !== 'number') return null;
  return `$${(value / 100).toFixed(2)}`;
}

function hasMeaningfulProjectPrice(item: ScopedItem): boolean {
  if (typeof item.projectPriceCents !== 'number') return false;
  // If project price was auto-copied from purchase price, treat it as "not set"
  // so we fall back to the purchase price for display.
  if (typeof item.purchasePriceCents === 'number' && item.projectPriceCents === item.purchasePriceCents) return false;
  return true;
}

function getDisplayPriceCents(item: ScopedItem): number | null {
  if (hasMeaningfulProjectPrice(item)) return item.projectPriceCents ?? null;
  if (typeof item.purchasePriceCents === 'number') return item.purchasePriceCents;
  if (typeof item.projectPriceCents === 'number') return item.projectPriceCents;
  return null;
}

function getPrimaryImage(item: ScopedItem) {
  const images = item.images ?? [];
  const primary = images.find((image) => image.isPrimary) ?? images[0];
  if (!primary) return null;
  return resolveAttachmentUri(primary) ?? primary.url;
}

export function SharedItemsList({
  // Standalone props
  scopeConfig,
  listStateKey,
  refreshToken,

  // Embedded props
  embedded = false,
  manager: externalManager,
  items: externalItems,
  bulkActions: externalBulkActions,
  onItemPress: externalOnItemPress,
  getItemMenuItems: externalGetItemMenuItems,
  emptyMessage = "No items found",
}: SharedItemsListProps) {
  // Prop validation in development mode
  if (__DEV__ && embedded) {
    if (!externalManager) {
      console.warn('SharedItemsList: embedded mode requires manager prop');
    }
    if (!externalItems) {
      console.warn('SharedItemsList: embedded mode requires items prop');
    }
    if (!externalBulkActions) {
      console.warn('SharedItemsList: embedded mode requires bulkActions prop');
    }
  }

  if (__DEV__ && !embedded) {
    if (!scopeConfig) {
      console.warn('SharedItemsList: standalone mode requires scopeConfig prop');
    }
    if (!listStateKey) {
      console.warn('SharedItemsList: standalone mode requires listStateKey prop');
    }
  }

  const listRef = useRef<FlatList<ListRow>>(null);
  const { state, setSearch, setSort, setFilters, setRestoreHint, clearRestoreHint } = useListState(listStateKey ?? 'default');
  const [query, setQuery] = useState(state.search ?? '');
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [sortOpen, setSortOpen] = useState(false);
  const [showSearch, setShowSearch] = useState(false);
  const [internalItems, setInternalItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [bulkSheetOpen, setBulkSheetOpen] = useState(false);
  const [internalSelectedIds, setInternalSelectedIds] = useState<string[]>([]);
  const [bulkSpaceId, setBulkSpaceId] = useState('');
  const [bulkProjectId, setBulkProjectId] = useState('');
  const [bulkCategoryId, setBulkCategoryId] = useState('');
  const [bulkSourceCategoryId, setBulkSourceCategoryId] = useState('');
  const [bulkError, setBulkError] = useState<string | null>(null);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string }>>({});
  const [sourceCategoryMenuOpen, setSourceCategoryMenuOpen] = useState(false);
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const bulkSheetDividerStyle = useMemo(
    () => ({ borderBottomColor: uiKitTheme.border.secondary }),
    [uiKitTheme]
  );
  const primaryTextStyle = useMemo(() => getTextColorStyle(theme.colors.primary), [theme]);
  const errorTextStyle = useMemo(() => getTextColorStyle(theme.colors.error), [theme]);
  const filterInputThemeStyle = useMemo(
    () => ({ borderColor: uiKitTheme.border.primary, color: theme.colors.text }),
    [uiKitTheme, theme]
  );
  const selectButtonThemeStyle = useMemo(
    () => ({
      backgroundColor: uiKitTheme.button.secondary.background,
      borderColor: uiKitTheme.border.primary,
    }),
    [uiKitTheme]
  );
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const scopeId = useMemo(() => scopeConfig ? getScopeId(scopeConfig) : null, [scopeConfig]);
  const lastScrollOffsetRef = useRef(0);
  const screenRefresh = useScreenRefresh();

  // Choose data and state sources based on embedded mode
  const items = embedded ? (externalItems ?? []) : internalItems;
  const selectedIds = embedded ? (externalManager?.selectedIds ?? []) : internalSelectedIds;

  const setItemSelected = useCallback((id: string, next: boolean) => {
    if (embedded && externalManager) {
      externalManager.setItemSelected(id, next);
    } else {
      setInternalSelectedIds((prev) => {
        const has = prev.includes(id);
        if (next) return has ? prev : [...prev, id];
        return has ? prev.filter((itemId) => itemId !== id) : prev;
      });
    }
  }, [embedded, externalManager]);

  const setGroupSelection = useCallback((ids: string[], next: boolean) => {
    if (embedded && externalManager) {
      externalManager.setGroupSelection(ids, next);
    } else {
      setInternalSelectedIds((prev) => {
        if (next) return Array.from(new Set([...prev, ...ids]));
        const remove = new Set(ids);
        return prev.filter((itemId) => !remove.has(itemId));
      });
    }
  }, [embedded, externalManager]);

  const clearSelection = useCallback(() => {
    if (embedded && externalManager) {
      externalManager.clearSelection();
    } else {
      setInternalSelectedIds([]);
    }
    setBulkError(null);
  }, [embedded, externalManager]);

  const selectAll = useCallback(() => {
    if (embedded && externalManager) {
      externalManager.selectAll();
    } else {
      setInternalSelectedIds(items.map(item => item.id));
    }
  }, [embedded, externalManager, items]);

  useEffect(() => {
    setQuery(state.search ?? '');
  }, [state.search]);

  useEffect(() => {
    const handle = setTimeout(() => {
      setSearch(query.trim());
    }, 350);
    return () => clearTimeout(handle);
  }, [query, setSearch]);

  useEffect(() => {
    if (embedded) return; // Skip in embedded mode
    if (!accountId || !scopeId) {
      setInternalItems([]);
      setIsLoading(false);
    }
  }, [accountId, scopeId, embedded]);

  useEffect(() => {
    if (embedded) return; // Skip in embedded mode
    if (!accountId) {
      setBudgetCategories({});
      return;
    }
    return subscribeToBudgetCategories(accountId, (next) => {
      setBudgetCategories(mapBudgetCategories(next));
    });
  }, [accountId, embedded]);

  useEffect(() => {
    if (embedded) return; // Skip in embedded mode
    if (!accountId || !scopeId || refreshToken == null || !scopeConfig) {
      return;
    }
    void refreshScopedItems(accountId, scopeConfig, 'online').then((next) => {
      if (next.length) {
        setInternalItems(next);
      }
    });
  }, [accountId, refreshToken, scopeConfig, scopeId, embedded]);

  const handleSubscribe = useCallback(() => {
    if (embedded) return () => {}; // Skip in embedded mode
    if (!accountId || !scopeId || !scopeConfig) {
      setInternalItems([]);
      setIsLoading(false);
      return () => {};
    }

    setIsLoading(true);
    return subscribeToScopedItems(accountId, scopeConfig, (next) => {
      setInternalItems(next);
      setIsLoading(false);
    });
  }, [accountId, scopeConfig, scopeId, embedded]);

  useScopedListeners(scopeId, handleSubscribe);

  const rows = useMemo(() => {
    return items.map((item) => {
      const label = item.name?.trim() || 'Untitled item';
      const subtitle = item.projectId ? `Project ${item.projectId}` : 'Inventory';
      return { id: item.id, label, subtitle, item };
    });
  }, [items]);

  const sortMode = (state.sort as SortMode | undefined) ?? DEFAULT_SORT;

  const activeFilters = (state.filters ?? {}) as ItemFilters;
  const filterModes = scopeConfig?.scope === 'inventory' ? INVENTORY_FILTER_MODES : PROJECT_FILTER_MODES;

  const selectedModes = useMemo<ItemFilterMode[]>(() => {
    const modeValue = activeFilters.mode;
    const normalizeMode = (value: string) => (value === 'no-description' ? 'no-name' : value);
    if (Array.isArray(modeValue)) {
      const normalized = modeValue.map((m) => normalizeMode(String(m))) as ItemFilterMode[];
      return normalized.length > 0 ? normalized : ['all'];
    }
    return modeValue ? ([normalizeMode(String(modeValue))] as ItemFilterMode[]) : ['all'];
  }, [activeFilters.mode]);

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const normalizedNeedle = normalizeSku(needle);
    const filteredItems = needle
      ? rows.filter((row) => {
          const item = row.item;
          const sku = item.sku ?? '';
          const haystack = [
            row.label,
            item.name ?? '',
            item.notes ?? '',
            item.source ?? '',
            item.spaceId ?? '',
            sku,
          ]
            .join(' ')
            .toLowerCase();
          if (haystack.includes(needle)) return true;
          if (normalizedNeedle && normalizeSku(sku).includes(normalizedNeedle)) return true;
          return false;
        })
      : rows;

    const filteredByFilters = filteredItems.filter((row) => {
      const item = row.item;
      if (selectedModes.includes('all')) return true;
      return selectedModes.some((mode) => {
        if (mode === 'bookmarked') return Boolean(item.bookmark);
        if (mode === 'from-inventory') return !item.projectId;
        if (mode === 'to-return') return item.status === 'to return';
        if (mode === 'returned') return item.status === 'returned';
        if (mode === 'no-sku') return !item.sku?.trim();
        if (mode === 'no-name') return !item.name?.trim();
        if (mode === 'no-project-price') return !hasMeaningfulProjectPrice(item);
        if (mode === 'no-image') return (item.images?.length ?? 0) === 0;
        if (mode === 'no-transaction') return !item.transactionId;
        return false;
      });
    });

    const sorted = [...filteredByFilters].sort((a, b) => {
      if (sortMode === 'alphabetical-asc' || sortMode === 'alphabetical-desc') {
        const order = sortMode === 'alphabetical-asc' ? 1 : -1;
        return order * a.label.localeCompare(b.label);
      }
      if (sortMode === 'created-desc' || sortMode === 'created-asc') {
        const aDate = a.item.createdAt ? String(a.item.createdAt) : '';
        const bDate = b.item.createdAt ? String(b.item.createdAt) : '';
        const order = sortMode === 'created-desc' ? -1 : 1;
        if (aDate && bDate) {
          return order * bDate.localeCompare(aDate);
        }
      }
      return b.id.localeCompare(a.id);
    });

    return sorted;
  }, [query, rows, selectedModes, sortMode]);

  const groupedRows = useMemo(() => {
    if (activeFilters.showDuplicates === false) {
      return filtered.map((row) => ({ type: 'item', item: row } as ListRow));
    }
    const groups = new Map<string, ItemRow[]>();
    filtered.forEach((row) => {
      const key = [row.label, row.item.sku ?? '', row.item.source ?? ''].join('::').toLowerCase();
      const list = groups.get(key) ?? [];
      list.push(row);
      groups.set(key, list);
    });

    const output: ListRow[] = [];
    groups.forEach((groupItems, groupKey) => {
      if (groupItems.length <= 1) {
        output.push({ type: 'item', item: groupItems[0] });
        return;
      }
      const groupId = `dup:${groupKey}`;
      output.push({
        type: 'group',
        groupId,
        label: groupItems[0].label,
        count: groupItems.length,
        items: groupItems,
      });
    });
    return output;
  }, [activeFilters.showDuplicates, filtered]);

  useEffect(() => {
    const restore = state.restore;
    if (!restore) return;

    let restored = false;
    if (restore.anchorId) {
      const index = groupedRows.findIndex(
        (row) =>
          (row.type === 'item' && row.item.id === restore.anchorId) ||
          (row.type === 'group' && row.items.some((item) => item.id === restore.anchorId))
      );
      if (index >= 0) {
        try {
          listRef.current?.scrollToIndex({ index, animated: false });
          restored = true;
        } catch {
          // ignore index restore failures
        }
      }
    }

    if (!restored && restore.scrollOffset != null) {
      listRef.current?.scrollToOffset({ offset: restore.scrollOffset, animated: false });
    }

    clearRestoreHint();
  }, [clearRestoreHint, groupedRows, state.restore]);

  useEffect(() => {
    if (selectedIds.length === 0 && bulkSheetOpen) {
      setBulkSheetOpen(false);
    }
  }, [bulkSheetOpen, selectedIds.length]);

  const setGroupExpanded = useCallback(
    (groupId: string, expanded: boolean) => {
      const nextFilters = {
        ...(state.filters ?? {}),
        [`collapsed:${groupId}`]: !expanded,
      };
      setFilters(nextFilters as Record<string, unknown>);
    },
    [setFilters, state.filters]
  );

  const handleBulkDelete = useCallback(() => {
    if (!accountId || selectedIds.length === 0) return;
    selectedIds.forEach((id) => {
      deleteItem(accountId, id);
    });
    clearSelection();
  }, [accountId, selectedIds, clearSelection]);

  const handleBulkMoveToSpace = useCallback(() => {
    if (!accountId || selectedIds.length === 0 || !bulkSpaceId.trim()) return;
    selectedIds.forEach((id) => {
      updateItem(accountId, id, { spaceId: bulkSpaceId.trim() });
    });
    clearSelection();
    setBulkSpaceId('');
  }, [accountId, bulkSpaceId, selectedIds, clearSelection]);

  const handleBulkRemoveFromSpace = useCallback(() => {
    if (!accountId || selectedIds.length === 0) return;
    selectedIds.forEach((id) => {
      updateItem(accountId, id, { spaceId: null });
    });
    clearSelection();
  }, [accountId, selectedIds, clearSelection]);

  const handleBulkAllocateToProject = useCallback(() => {
    if (!accountId || selectedIds.length === 0 || !bulkProjectId.trim()) return;
    if (!bulkCategoryId.trim()) {
      setBulkError('Select a destination category before allocating.');
      return;
    }
    setBulkError(null);
    requestBusinessToProjectPurchase({
      accountId,
      targetProjectId: bulkProjectId.trim(),
      budgetCategoryId: bulkCategoryId.trim(),
      items: items.filter((item) => selectedIds.includes(item.id)),
    });
    clearSelection();
    setBulkProjectId('');
    setBulkCategoryId('');
  }, [accountId, bulkCategoryId, bulkProjectId, items, selectedIds, clearSelection]);

  const handleBulkSellToBusiness = useCallback(() => {
    if (!accountId || selectedIds.length === 0 || !scopeConfig || scopeConfig.scope !== 'project') return;
    const selected = items.filter((item) => selectedIds.includes(item.id));
    const missingCategory = selected.find((item) => !item.budgetCategoryId);
    if (missingCategory && !bulkSourceCategoryId.trim()) {
      setBulkError('Select a source category for uncategorized items before selling.');
      return;
    }
    setBulkError(null);
    requestProjectToBusinessSale({
      accountId,
      projectId: scopeConfig.projectId ?? '',
      budgetCategoryId: bulkSourceCategoryId.trim() || undefined,
      items: selected,
    });
    clearSelection();
    setBulkSourceCategoryId('');
  }, [accountId, bulkSourceCategoryId, items, scopeConfig, selectedIds, clearSelection]);

  const bulkSourceCategoryLabel = useMemo(() => {
    if (!bulkSourceCategoryId.trim()) return 'No source category';
    return budgetCategories[bulkSourceCategoryId]?.name ?? bulkSourceCategoryId;
  }, [budgetCategories, bulkSourceCategoryId]);

  const sourceCategoryMenuItems: AnchoredMenuItem[] = useMemo(() => {
    const options = Object.entries(budgetCategories)
      .map(([id, cat]) => ({ id, label: cat.name }))
      .sort((a, b) => a.label.localeCompare(b.label));

    if (options.length === 0) {
      return [
        {
          key: 'empty',
          label: 'No categories yet',
          onPress: () => {},
        },
      ];
    }

    return [
      {
        key: 'none',
        label: 'No source category',
        icon: !bulkSourceCategoryId.trim() ? 'check' : undefined,
        onPress: () => setBulkSourceCategoryId(''),
      },
      ...options.map((option) => ({
        key: option.id,
        label: option.label,
        icon: bulkSourceCategoryId === option.id ? 'check' : undefined,
        onPress: () => setBulkSourceCategoryId(option.id),
      })),
    ];
  }, [budgetCategories, bulkSourceCategoryId]);

  const handleToggleSort = useCallback(() => {
    setSortOpen(true);
  }, []);

  const sortMenuItems: AnchoredMenuItem[] = useMemo(() => {
    const getCreatedSubactionKey = () => {
      if (sortMode === 'created-desc' || sortMode === 'created-asc') {
        return sortMode;
      }
      return 'created-desc';
    };

    const getAlphabeticalSubactionKey = () => {
      if (sortMode === 'alphabetical-asc' || sortMode === 'alphabetical-desc') {
        return sortMode;
      }
      return 'alphabetical-asc';
    };

    return [
      {
        key: 'created',
        label: 'Created',
        selectedSubactionKey: getCreatedSubactionKey(),
        defaultSelectedSubactionKey: 'created-desc',
        suppressDefaultCheckmark: true,
        subactions: [
          {
            key: 'created-desc',
            label: 'Newest First',
            onPress: () => setSort('created-desc'),
          },
          {
            key: 'created-asc',
            label: 'Oldest First',
            onPress: () => setSort('created-asc'),
          },
        ],
      },
      {
        key: 'alphabetical',
        label: 'Alphabetical',
        selectedSubactionKey: getAlphabeticalSubactionKey(),
        defaultSelectedSubactionKey: 'alphabetical-asc',
        suppressDefaultCheckmark: true,
        subactions: [
          {
            key: 'alphabetical-asc',
            label: 'A-Z',
            onPress: () => setSort('alphabetical-asc'),
          },
          {
            key: 'alphabetical-desc',
            label: 'Z-A',
            onPress: () => setSort('alphabetical-desc'),
          },
        ],
      },
    ];
  }, [setSort, sortMode]);

  const filterMenuItems: AnchoredMenuItem[] = useMemo(() => {
    const normalizedModes = selectedModes.length > 0 ? selectedModes : ['all'];
    return filterModes.map((mode) => {
      const label = mode === 'all' ? 'All' : mode.replace(/-/g, ' ').replace(/\b\w/g, (l) => l.toUpperCase());
      const isSelected = normalizedModes.includes(mode);
      return {
        key: mode,
        label,
        onPress: () => {
          if (mode === 'all') {
            setFilters({ ...activeFilters, mode: 'all' });
            return;
          }
          const next = normalizedModes.filter((value) => value !== 'all');
          const nextModes = next.includes(mode) ? next.filter((value) => value !== mode) : [...next, mode];
          setFilters({ ...activeFilters, mode: nextModes.length > 0 ? nextModes : 'all' });
        },
        icon: isSelected && mode !== 'all' ? 'check' : undefined,
      };
    });
  }, [activeFilters, filterModes, selectedModes, setFilters]);

  const handleCreateItem = useCallback(() => {
    if (!scopeConfig || !listStateKey) return;
    router.push({
      pathname: '/items/new',
      params: {
        scope: scopeConfig.scope,
        projectId: scopeConfig.projectId ?? '',
        listStateKey,
      },
    });
  }, [listStateKey, router, scopeConfig]);

  const handleOpenItem = useCallback(
    (id: string) => {
      // Use external handler in embedded mode
      if (embedded && externalOnItemPress) {
        externalOnItemPress(id);
        return;
      }

      // Default standalone behavior
      if (!scopeConfig || !listStateKey) return;
      setRestoreHint({ anchorId: id, scrollOffset: lastScrollOffsetRef.current });
      const backTarget =
        scopeConfig.scope === 'inventory'
          ? '/(tabs)/screen-two?tab=items'
          : scopeConfig.projectId
            ? `/project/${scopeConfig.projectId}?tab=items`
            : '/(tabs)/index';
      router.push({
        pathname: '/items/[id]',
        params: {
          id,
          listStateKey,
          backTarget,
          scope: scopeConfig.scope,
          projectId: scopeConfig.projectId ?? '',
        },
      });
    },
    [embedded, externalOnItemPress, listStateKey, router, scopeConfig, setRestoreHint]
  );

  const handleDeleteItem = useCallback(
    (id: string, label: string) => {
      if (!accountId) return;
      Alert.alert('Delete item', `Delete "${label}"? This can't be undone.`, [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            deleteItem(accountId, id);
            if (embedded && externalManager) {
              externalManager.setItemSelected(id, false);
            } else {
              setInternalSelectedIds((prev) => prev.filter((itemId) => itemId !== id));
            }
          },
        },
      ]);
    },
    [accountId, embedded, externalManager]
  );

  const handleSelectAll = useCallback(() => {
    const allItemIds = filtered.map((row) => row.id);
    const allSelected = allItemIds.length > 0 &&
      allItemIds.every(id => selectedIds.includes(id));

    if (allSelected) {
      clearSelection();
    } else {
      selectAll();
    }
  }, [filtered, selectedIds, clearSelection, selectAll]);

  const hasFiltered = filtered.length > 0;
  const allItemIds = filtered.map((row) => row.id);
  const allSelected = allItemIds.length > 0 && allItemIds.every(id => selectedIds.includes(id));

  const getSortLabel = useCallback(() => {
    if (sortMode === 'alphabetical-asc') return 'Alphabetical (A-Z)';
    if (sortMode === 'alphabetical-desc') return 'Alphabetical (Z-A)';
    if (sortMode === 'created-desc') return 'Created (Newest First)';
    if (sortMode === 'created-asc') return 'Created (Oldest First)';
    return sortMode;
  }, [sortMode]);

  const isSortActive = sortMode !== DEFAULT_SORT;
  const isFilterActive =
    !selectedModes.includes('all') || selectedModes.length > 1 || activeFilters.showDuplicates === false;

  const getMenuItems = useCallback((item: ScopedItem, label: string): AnchoredMenuItem[] => {
    // Use external menu items in embedded mode
    if (embedded && externalGetItemMenuItems) {
      return externalGetItemMenuItems(item);
    }

    // Default standalone menu items
    return [
      { key: 'open', label: 'Open', onPress: () => handleOpenItem(item.id) },
      { key: 'delete', label: 'Delete', onPress: () => handleDeleteItem(item.id, label) },
    ];
  }, [embedded, externalGetItemMenuItems, handleOpenItem, handleDeleteItem]);

  return (
    <View style={styles.container}>
      {!embedded && (
        <View style={styles.controlSection}>
          <ItemsListControlBar
            search={query}
            onChangeSearch={setQuery}
            showSearch={showSearch}
            onToggleSearch={() => setShowSearch(!showSearch)}
            onSort={handleToggleSort}
            isSortActive={isSortActive}
            onFilter={() => setFiltersOpen(true)}
            isFilterActive={isFilterActive}
            onAdd={handleCreateItem}
            leftElement={
              <TouchableOpacity
                disabled={!hasFiltered}
                onPress={() => {
                  if (!hasFiltered) return;
                  handleSelectAll();
                }}
                style={[
                  styles.selectButton,
                  selectButtonThemeStyle,
                  !hasFiltered && styles.selectButtonDisabled,
                ]}
                accessibilityRole="checkbox"
                accessibilityState={{ checked: allSelected }}
              >
                <SelectorCircle selected={allSelected} indicator="check" />
              </TouchableOpacity>
            }
          />
        </View>
      )}
      {!embedded && (
        <>
          <SortMenu
            visible={sortOpen}
            onRequestClose={() => setSortOpen(false)}
            items={sortMenuItems}
            activeSubactionKey={sortMode}
          />
          <FilterMenu visible={filtersOpen} onRequestClose={() => setFiltersOpen(false)} items={filterMenuItems} />
        </>
      )}
      <BottomSheet visible={bulkSheetOpen} onRequestClose={() => setBulkSheetOpen(false)}>
        <View style={[styles.bulkSheetTitleRow, bulkSheetDividerStyle]}>
          <AppText variant="body" style={styles.bulkSheetTitle}>
            Bulk actions
          </AppText>
        </View>
        <View style={styles.bulkSheetContent}>
          <View style={styles.bulkHeader}>
            <AppText variant="caption" style={styles.semiboldText}>
              {selectedIds.length} selected
            </AppText>
            <Pressable onPress={clearSelection}>
              <AppText variant="caption" style={[styles.semiboldText, primaryTextStyle]}>
                Done
              </AppText>
            </Pressable>
          </View>
          {bulkError ? (
            <AppText variant="caption" style={errorTextStyle}>
              {bulkError}
            </AppText>
          ) : null}
          <View style={styles.bulkActions}>
            {embedded && externalBulkActions ? (
              // Render custom bulk actions in embedded mode
              externalBulkActions.map((action) => (
                <AppButton
                  key={action.id}
                  title={action.label}
                  variant={action.destructive ? 'secondary' : 'secondary'}
                  onPress={() => {
                    action.onPress(selectedIds);
                    setBulkSheetOpen(false);
                  }}
                  style={[
                    styles.bulkActionButton,
                    action.destructive ? { backgroundColor: theme.colors.error } : undefined,
                  ]}
                />
              ))
            ) : (
              // Render default standalone bulk actions
              <>
            <View style={styles.bulkActionGroup}>
              <TextInput
                value={bulkSpaceId}
                onChangeText={setBulkSpaceId}
                placeholder="Target space id"
                placeholderTextColor={theme.colors.textSecondary}
                style={[styles.filterInput, filterInputThemeStyle]}
              />
              <AppButton
                title="Move to space"
                variant="secondary"
                onPress={handleBulkMoveToSpace}
                style={styles.bulkActionButton}
              />
              <AppButton
                title="Remove from space"
                variant="secondary"
                onPress={handleBulkRemoveFromSpace}
                style={styles.bulkActionButton}
              />
            </View>
            {scopeConfig?.scope === 'inventory' ? (
              <View style={styles.bulkActionGroup}>
                <TextInput
                  value={bulkProjectId}
                  onChangeText={setBulkProjectId}
                  placeholder="Target project id"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={[styles.filterInput, filterInputThemeStyle]}
                />
                <TextInput
                  value={bulkCategoryId}
                  onChangeText={setBulkCategoryId}
                  placeholder="Destination category id"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={[styles.filterInput, filterInputThemeStyle]}
                />
                <AppButton
                  title="Allocate to project"
                  variant="secondary"
                  onPress={handleBulkAllocateToProject}
                  style={styles.bulkActionButton}
                />
              </View>
            ) : null}
            {scopeConfig?.scope === 'project' ? (
              <View style={styles.bulkActionGroup}>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel="Select source category"
                  onPress={() => setSourceCategoryMenuOpen(true)}
                  style={[styles.filterInput, filterInputThemeStyle, styles.categoryPicker]}
                >
                  <AppText variant="caption" style={styles.categoryPickerLabel}>
                    Source category (for uncategorized)
                  </AppText>
                  <AppText variant="body">{bulkSourceCategoryLabel}</AppText>
                </Pressable>
                <AppButton
                  title="Sell to business"
                  variant="secondary"
                  onPress={handleBulkSellToBusiness}
                  style={styles.bulkActionButton}
                />
              </View>
            ) : null}
                <AppButton
                  title="Delete"
                  variant="secondary"
                  onPress={handleBulkDelete}
                  style={styles.bulkActionButton}
                />
              </>
            )}
          </View>
        </View>
      </BottomSheet>
      <BottomSheetMenuList
        visible={sourceCategoryMenuOpen}
        onRequestClose={() => setSourceCategoryMenuOpen(false)}
        items={sourceCategoryMenuItems}
        title="Source category"
      />
      <FlatList
        ref={listRef}
        data={groupedRows}
        keyExtractor={(row) => (row.type === 'group' ? row.groupId : row.item.id)}
        contentContainerStyle={[styles.list, selectedIds.length > 0 ? styles.listWithBulkBar : null]}
        refreshControl={
          screenRefresh ? (
            <RefreshControl refreshing={screenRefresh.refreshing} onRefresh={screenRefresh.onRefresh} />
          ) : undefined
        }
        onScroll={(event) => {
          lastScrollOffsetRef.current = event.nativeEvent.contentOffset.y;
        }}
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <AppText variant="body">
              {isLoading ? 'Loading items…' : emptyMessage}
            </AppText>
          </View>
        }
        renderItem={({ item: row }) => {
          if (row.type === 'group') {
            const groupIds = row.items.map((item) => item.id);
            const groupSelected = groupIds.every((id) => selectedIds.includes(id));
            const summaryItem = row.items.find((item) => getPrimaryImage(item.item)) ?? row.items[0];
            const summaryThumbnailUri = summaryItem ? (getPrimaryImage(summaryItem.item) ?? undefined) : undefined;
            const isCollapsed = ((state.filters as any)?.[`collapsed:${row.groupId}`] ?? true) as boolean;
            const groupPriceCents = row.items
              .map((item) => getDisplayPriceCents(item.item))
              .filter((value): value is number => typeof value === 'number');
            const totalLabel =
              groupPriceCents.length === row.items.length
                ? formatCents(groupPriceCents.reduce((sum, value) => sum + value, 0))
                : null;

            return (
              <GroupedItemCard
                summary={{
                  name: row.label,
                  sku: summaryItem?.item.sku ?? undefined,
                  sourceLabel: summaryItem?.item.source ?? undefined,
                  locationLabel: scopeConfig?.fields?.showBusinessInventoryLocation
                    ? summaryItem?.item.spaceId ?? undefined
                    : undefined,
                  notes: summaryItem?.item.notes ?? undefined,
                  thumbnailUri: summaryThumbnailUri,
                }}
                countLabel={`×${row.count}`}
                totalLabel={totalLabel ?? undefined}
                items={row.items.map((item) => {
                  const isSelected = selectedIds.includes(item.id);
                  const menuItems = getMenuItems(item.item, item.label);

                  const cardProps: ItemCardProps = {
                    name: item.label,
                    sku: item.item.sku ?? undefined,
                    sourceLabel: item.item.source ?? undefined,
                    locationLabel: scopeConfig?.fields?.showBusinessInventoryLocation ? item.item.spaceId ?? undefined : undefined,
                    priceLabel: formatCents(getDisplayPriceCents(item.item)) ?? undefined,
                    statusLabel: item.item.status ?? undefined,
                    thumbnailUri: getPrimaryImage(item.item) ?? undefined,
                    selected: isSelected,
                    onSelectedChange: (next) => {
                      setItemSelected(item.id, next);
                    },
                    menuItems,
                    bookmarked: Boolean(item.item.bookmark ?? (item.item as any).isBookmarked),
                    onBookmarkPress: () => {
                      if (!accountId) return;
                      const next = !(item.item.bookmark ?? (item.item as any).isBookmarked);
                      updateItem(accountId, item.id, { bookmark: next });
                    },
                    onPress: () => {
                      handleOpenItem(item.id);
                    },
                  };

                  return cardProps;
                })}
                expanded={!isCollapsed}
                onExpandedChange={(next) => setGroupExpanded(row.groupId, next)}
                selected={groupSelected}
                onSelectedChange={(next) => {
                  setGroupSelection(groupIds, next);
                }}
              />
            );
          }

          const item = row.item;
          const isSelected = selectedIds.includes(item.id);
          const menuItems = getMenuItems(item.item, item.label);
          return (
            <ItemCard
              name={item.label}
              sku={item.item.sku ?? undefined}
              sourceLabel={item.item.source ?? undefined}
              locationLabel={scopeConfig?.fields?.showBusinessInventoryLocation ? item.item.spaceId ?? undefined : undefined}
              priceLabel={formatCents(getDisplayPriceCents(item.item)) ?? undefined}
              statusLabel={item.item.status ?? undefined}
              thumbnailUri={getPrimaryImage(item.item) ?? undefined}
              selected={isSelected}
              onSelectedChange={(next) => setItemSelected(item.id, next)}
              menuItems={menuItems}
              bookmarked={Boolean(item.item.bookmark ?? (item.item as any).isBookmarked)}
              onBookmarkPress={() => {
                if (!accountId) return;
                const next = !(item.item.bookmark ?? (item.item as any).isBookmarked);
                updateItem(accountId, item.id, { bookmark: next });
              }}
              onPress={() => {
                handleOpenItem(item.id);
              }}
            />
          );
        }}
      />
      <BulkSelectionBar
        selectedCount={selectedIds.length}
        onBulkActionsPress={() => setBulkSheetOpen(true)}
        onClearSelection={clearSelection}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    gap: 0,
  },
  controlSection: {
    gap: 0,
    marginBottom: 12,
  },
  selectButton: {
    borderRadius: BUTTON_BORDER_RADIUS,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 40,
    minWidth: 40,
    paddingVertical: 10,
    paddingHorizontal: 10,
    borderWidth: 1,
  },
  selectButtonDisabled: {
    opacity: 0.5,
  },
  bulkSelectButton: {
    paddingVertical: 8,
    paddingHorizontal: 12,
  },
  bulkSelectText: {
    fontWeight: '500',
  },
  list: {
    flexGrow: 1,
    paddingBottom: layout.screenBodyTopMd.paddingTop,
    gap: 10,
  },
  listWithBulkBar: {
    paddingBottom: layout.screenBodyTopMd.paddingTop + 56,
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 12,
  },
  rowPressed: {
    opacity: 0.7,
  },
  rowHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  filterInput: {
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  bulkSheetTitleRow: {
    paddingHorizontal: 16,
    paddingBottom: 10,
    paddingTop: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  bulkSheetTitle: {
    fontWeight: '700',
  },
  bulkSheetContent: {
    gap: 12,
    paddingHorizontal: 16,
    paddingBottom: 12,
    paddingTop: 8,
  },
  bulkHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  semiboldText: {
    fontWeight: '600',
  },
  bulkActions: {
    gap: 12,
  },
  bulkActionGroup: {
    gap: 8,
  },
  bulkActionButton: {
    minHeight: 36,
    paddingVertical: 8,
    paddingHorizontal: 12,
  },
  categoryPicker: {
    gap: 4,
  },
  categoryPickerLabel: {
    fontWeight: '600',
  },
});
