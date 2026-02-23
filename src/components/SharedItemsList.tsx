import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, FlatList, Pressable, RefreshControl, StyleSheet, TouchableOpacity, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
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
import { deleteItem, updateItem, type Item } from '../data/itemsService';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../data/budgetCategoriesService';
import { SetSpaceModal } from './modals/SetSpaceModal';
import { ReassignToProjectModal } from './modals/ReassignToProjectModal';
import { SellToProjectModal } from './modals/SellToProjectModal';
import { SellToBusinessModal } from './modals/SellToBusinessModal';
import { TransactionPickerModal } from './modals/TransactionPickerModal';
import { needsSourceCategoryPicker, needsDestinationCategoryPicker, type ItemForCategoryResolution } from '../utils/bulkSaleUtils';
import { resolveAttachmentUri } from '../offline/media';
import { filterItemsForBulkReassign, reassignItemToInventory, reassignItemToProject } from '../data/reassignService';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import { ITEM_STATUSES, getItemStatusLabel } from '../constants/itemStatuses';
import { buildSingleItemMenu, buildBulkMenu } from '../actions/itemMenuBuilder';
import { executeSellToBusiness, executeSellToProject, executeBulkReassignToInventory, executeBulkReassignToProject } from '../actions/itemActionHandlers';
import { showToast } from './toastStore';
import { usePickerMode, type ItemEligibilityCheck } from '../hooks/usePickerMode';
import { ItemPickerControlBar } from './ItemPickerControlBar';

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

  // Picker mode props
  picker?: boolean;
  eligibilityCheck?: ItemEligibilityCheck;
  onAddSingle?: (item: ScopedItem | Item) => void | Promise<void>;
  addedIds?: Set<string>;
  onAddSelected?: () => void | Promise<void>;
  addButtonLabel?: string;
  outsideLoading?: boolean;
  outsideError?: string | null;
  searchPlaceholder?: string;
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

  // Picker props
  picker = false,
  eligibilityCheck,
  onAddSingle,
  addedIds,
  onAddSelected,
  addButtonLabel,
  outsideLoading,
  outsideError,
  searchPlaceholder,
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
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string }>>({});
  const [sellToBusinessVisible, setSellToBusinessVisible] = useState(false);
  const [sellToProjectVisible, setSellToProjectVisible] = useState(false);
  const [sellTargetProjectId, setSellTargetProjectId] = useState<string | null>(null);
  const [sellBudgetCategories, setSellBudgetCategories] = useState<Record<string, { name: string }>>({});
  const [sellDestBudgetCategories, setSellDestBudgetCategories] = useState<Record<string, { name: string }>>({});
  const [statusMenuItemId, setStatusMenuItemId] = useState<string | null>(null);
  const [reassignToInventoryVisible, setReassignToInventoryVisible] = useState(false);
  const [reassignToProjectVisible, setReassignToProjectVisible] = useState(false);
  const [bulkSpacePickerVisible, setBulkSpacePickerVisible] = useState(false);
  const [bulkTransactionPickerVisible, setBulkTransactionPickerVisible] = useState(false);
  // Single-item modal state (for standalone per-item menus)
  const [singleItemId, setSingleItemId] = useState<string | null>(null);
  const [singleItemSpacePickerVisible, setSingleItemSpacePickerVisible] = useState(false);
  const [singleItemTransactionPickerVisible, setSingleItemTransactionPickerVisible] = useState(false);
  const [singleItemSellToBusinessVisible, setSingleItemSellToBusinessVisible] = useState(false);
  const [singleItemSellToProjectVisible, setSingleItemSellToProjectVisible] = useState(false);
  const [singleItemReassignToProjectVisible, setSingleItemReassignToProjectVisible] = useState(false);
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const bulkSheetDividerStyle = useMemo(
    () => ({ borderBottomColor: uiKitTheme.border.secondary }),
    [uiKitTheme]
  );
  const primaryTextStyle = useMemo(() => getTextColorStyle(theme.colors.primary), [theme]);
  const selectButtonThemeStyle = useMemo(
    () => ({
      backgroundColor: uiKitTheme.button.secondary.background,
      borderColor: uiKitTheme.border.primary,
    }),
    [uiKitTheme]
  );
  const router = useRouter();
  const insets = useSafeAreaInsets();
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

  // Picker mode hook
  const pickerMode = usePickerMode({
    enabled: picker,
    items,
    eligibilityCheck,
    onAddSingle,
    addedIds,
    selectedIds,
    setItemSelected,
    setGroupSelection,
  });

  const clearSelection = useCallback(() => {
    if (embedded && externalManager) {
      externalManager.clearSelection();
    } else {
      setInternalSelectedIds([]);
    }
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

  // Subscribe to source project budget categories when sell-to-business modal is open
  const sellToBusinessOpen = sellToBusinessVisible || singleItemSellToBusinessVisible;
  useEffect(() => {
    if (!sellToBusinessOpen || embedded) return;
    if (!accountId || scopeConfig?.scope !== 'project' || !scopeConfig.projectId) {
      setSellBudgetCategories({});
      return;
    }
    return subscribeToBudgetCategories(accountId, (next) => {
      setSellBudgetCategories(mapBudgetCategories(next));
    });
  }, [sellToBusinessOpen, accountId, scopeConfig, embedded]);

  // Subscribe to target project budget categories when sell-to-project modal is open
  const sellToProjectOpen = sellToProjectVisible || singleItemSellToProjectVisible;
  useEffect(() => {
    if (!sellToProjectOpen || embedded || !sellTargetProjectId) {
      setSellDestBudgetCategories({});
      return;
    }
    if (!accountId) return;
    return subscribeToBudgetCategories(accountId, (next) => {
      setSellDestBudgetCategories(mapBudgetCategories(next));
    });
  }, [sellToProjectOpen, sellTargetProjectId, accountId, embedded]);

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

  const handleBulkSetSpace = useCallback((spaceId: string | null) => {
    if (!accountId || selectedIds.length === 0) return;
    selectedIds.forEach((id) => {
      updateItem(accountId, id, { spaceId });
    });
    setBulkSpacePickerVisible(false);
    clearSelection();
  }, [accountId, selectedIds, clearSelection]);

  const handleBulkClearSpace = useCallback(() => {
    if (!accountId || selectedIds.length === 0) return;
    selectedIds.forEach((id) => {
      updateItem(accountId, id, { spaceId: null });
    });
    clearSelection();
  }, [accountId, selectedIds, clearSelection]);

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

  const handleStatusPress = useCallback((itemId: string) => {
    setStatusMenuItemId(itemId);
  }, []);

  const handleStatusChange = useCallback((itemId: string, newStatus: string) => {
    if (!accountId) return;
    updateItem(accountId, itemId, { status: newStatus }).catch((error) => {
      console.error('Failed to update item status:', error);
    });
    setStatusMenuItemId(null);
  }, [accountId]);

  const statusMenuItems = useMemo<AnchoredMenuItem[]>(() => {
    return [
      ...ITEM_STATUSES.map(s => ({
        key: s.key,
        label: s.label,
        onPress: () => statusMenuItemId && handleStatusChange(statusMenuItemId, s.key),
      })),
      {
        key: 'clear',
        label: 'Clear Status',
        onPress: () => statusMenuItemId && handleStatusChange(statusMenuItemId, ''),
      },
    ];
  }, [statusMenuItemId, handleStatusChange]);

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

    if (!scopeConfig) return [];

    return buildSingleItemMenu({
      context: 'list',
      scopeConfig,
      callbacks: {
        onEditOrOpen: () => router.push({ pathname: '/items/[id]/edit', params: { id: item.id, scope: scopeConfig.scope ?? '', projectId: scopeConfig.projectId ?? '' } }),
        onStatusChange: (status) => handleStatusChange(item.id, status),
        onSetTransaction: () => { setSingleItemId(item.id); setSingleItemTransactionPickerVisible(true); },
        onClearTransaction: () => { if (accountId) updateItem(accountId, item.id, { transactionId: null }); },
        onSetSpace: () => { setSingleItemId(item.id); setSingleItemSpacePickerVisible(true); },
        onClearSpace: () => { if (accountId) updateItem(accountId, item.id, { spaceId: null }); },
        onSellToBusiness: scopeConfig.scope === 'project' ? () => { setSingleItemId(item.id); setSingleItemSellToBusinessVisible(true); } : undefined,
        onSellToProject: () => { setSingleItemId(item.id); setSingleItemSellToProjectVisible(true); },
        onReassignToInventory: scopeConfig.scope === 'project' ? () => { if (accountId) reassignItemToInventory(accountId, item.id); } : undefined,
        onReassignToProject: () => { setSingleItemId(item.id); setSingleItemReassignToProjectVisible(true); },
        onDelete: () => handleDeleteItem(item.id, label),
      },
    });
  }, [embedded, externalGetItemMenuItems, scopeConfig, accountId, router, handleStatusChange, handleDeleteItem]);

  const handleBulkClearTransaction = useCallback(() => {
    if (!accountId || selectedIds.length === 0) return;
    selectedIds.forEach((id) => {
      updateItem(accountId, id, { transactionId: null });
    });
    clearSelection();
  }, [accountId, selectedIds, clearSelection]);

  const handleBulkStatusChange = useCallback((status: string) => {
    if (!accountId || selectedIds.length === 0) return;
    selectedIds.forEach((id) => {
      updateItem(accountId, id, { status });
    });
    clearSelection();
  }, [accountId, selectedIds, clearSelection]);

  const standaloneBulkMenuItems = useMemo<AnchoredMenuItem[]>(() => {
    if (embedded || !scopeConfig) return [];
    return buildBulkMenu({
      context: 'list',
      scopeConfig,
      callbacks: {
        onStatusChange: (status) => handleBulkStatusChange(status),
        onSetTransaction: () => setBulkTransactionPickerVisible(true),
        onClearTransaction: () => handleBulkClearTransaction(),
        onSetSpace: () => setBulkSpacePickerVisible(true),
        onClearSpace: () => handleBulkClearSpace(),
        onSellToBusiness: scopeConfig.scope === 'project' ? () => setSellToBusinessVisible(true) : undefined,
        onSellToProject: () => { setSellTargetProjectId(null); setSellToProjectVisible(true); },
        onReassignToInventory: scopeConfig.scope === 'project' ? () => setReassignToInventoryVisible(true) : undefined,
        onReassignToProject: () => setReassignToProjectVisible(true),
        onDelete: () => handleBulkDelete(),
      },
    });
  }, [embedded, scopeConfig, handleBulkStatusChange, handleBulkClearTransaction, handleBulkClearSpace, handleBulkDelete]);

  return (
    <View style={styles.container}>
      {picker ? (
        <View style={styles.controlSection}>
          <ItemPickerControlBar
            search={query}
            onChangeSearch={setQuery}
            searchPlaceholder={searchPlaceholder}
            onSelectAll={pickerMode.handleSelectAll}
            allSelected={pickerMode.allEligibleSelected}
            hasItems={pickerMode.eligibleIds.length > 0}
            onAddSelected={onAddSelected!}
            selectedCount={selectedIds.length}
            addButtonLabel={addButtonLabel}
          />
        </View>
      ) : !embedded ? (
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
      ) : null}
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
      {embedded && externalBulkActions ? (
        <BottomSheet visible={bulkSheetOpen} onRequestClose={() => setBulkSheetOpen(false)}>
          <View style={[styles.bulkSheetTitleRow, bulkSheetDividerStyle]}>
            <AppText variant="body" style={styles.bulkSheetTitle}>
              Bulk Actions
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
            <View style={styles.bulkActions}>
              {externalBulkActions.map((action) => (
                <AppButton
                  key={action.id}
                  title={action.label}
                  variant="secondary"
                  onPress={() => {
                    action.onPress(selectedIds);
                    setBulkSheetOpen(false);
                  }}
                  style={[
                    styles.bulkActionButton,
                    action.destructive ? { backgroundColor: theme.colors.error } : undefined,
                  ]}
                />
              ))}
            </View>
          </View>
        </BottomSheet>
      ) : (
        <BottomSheetMenuList
          visible={bulkSheetOpen}
          onRequestClose={() => setBulkSheetOpen(false)}
          items={standaloneBulkMenuItems}
          title={`Bulk Actions (${selectedIds.length})`}
          showLeadingIcons={true}
        />
      )}
      {/* Sell to Business modal (Flow A: Project -> Business) */}
      <SellToBusinessModal
        visible={sellToBusinessVisible}
        onRequestClose={() => setSellToBusinessVisible(false)}
        sourceBudgetCategories={sellBudgetCategories}
        showSourceCategoryPicker={needsSourceCategoryPicker(items.filter(i => selectedIds.includes(i.id)) as ItemForCategoryResolution[])}
        subtitle={`${selectedIds.length} item${selectedIds.length === 1 ? '' : 's'} selected`}
        onConfirm={(scId) => {
          if (!accountId || !scopeConfig || scopeConfig.scope !== 'project' || !scopeConfig.projectId) return;
          const selected = items.filter(i => selectedIds.includes(i.id));
          executeSellToBusiness({ accountId, projectId: scopeConfig.projectId, items: selected, sourceCategoryId: scId });
          setSellToBusinessVisible(false);
          clearSelection();
          showToast(`${selected.length} item${selected.length === 1 ? '' : 's'} sold to business`);
        }}
      />
      {/* Sell to Project modal (Flow B: Inventory->Project, Flow C: Project->Project) */}
      <SellToProjectModal
        visible={sellToProjectVisible}
        onRequestClose={() => setSellToProjectVisible(false)}
        accountId={accountId!}
        excludeProjectId={scopeConfig?.projectId}
        destBudgetCategories={sellDestBudgetCategories}
        sourceBudgetCategories={sellBudgetCategories}
        showSourceCategoryPicker={scopeConfig?.scope === 'project' && needsSourceCategoryPicker(items.filter(i => selectedIds.includes(i.id)) as ItemForCategoryResolution[])}
        showDestCategoryPicker={needsDestinationCategoryPicker(items.filter(i => selectedIds.includes(i.id)) as ItemForCategoryResolution[], new Set(Object.keys(sellDestBudgetCategories)))}
        subtitle={`${selectedIds.length} item${selectedIds.length === 1 ? '' : 's'} selected`}
        onTargetProjectChange={(pid) => {
          setSellTargetProjectId(pid);
        }}
        onConfirm={({ targetProjectId: tpId, destCategoryId: dcId, sourceCategoryId: scId }) => {
          if (!accountId || !tpId) return;
          const selected = items.filter(i => selectedIds.includes(i.id));
          executeSellToProject({
            accountId,
            scope: scopeConfig?.scope ?? 'inventory',
            sourceProjectId: scopeConfig?.projectId,
            targetProjectId: tpId,
            items: selected,
            sourceCategoryId: scId,
            destCategoryId: dcId,
            validDestCategoryIds: new Set(Object.keys(sellDestBudgetCategories)),
          });
          setSellToProjectVisible(false);
          clearSelection();
          showToast(`${selected.length} item${selected.length === 1 ? '' : 's'} sold to project`);
        }}
      />
      {/* Reassign to Inventory confirmation */}
      <BottomSheet visible={reassignToInventoryVisible} onRequestClose={() => setReassignToInventoryVisible(false)}>
        <View style={[styles.bulkSheetTitleRow, bulkSheetDividerStyle]}>
          <AppText variant="body" style={styles.bulkSheetTitle}>
            Reassign to Inventory
          </AppText>
        </View>
        <View style={styles.bulkSheetContent}>
          {(() => {
            const selected = items.filter(i => selectedIds.includes(i.id));
            const { eligible, blockedCount } = filterItemsForBulkReassign(selected);
            return (
              <>
                <AppText variant="caption">
                  {eligible.length} item{eligible.length === 1 ? '' : 's'} will be moved to business inventory.
                  No sale or purchase records will be created.
                </AppText>
                {blockedCount > 0 && (
                  <AppText variant="caption" style={{ color: theme.colors.error ?? 'red' }}>
                    {blockedCount} item{blockedCount === 1 ? ' is' : 's are'} linked to transactions and cannot be reassigned.
                  </AppText>
                )}
                <AppButton
                  title="Reassign"
                  variant="primary"
                  disabled={eligible.length === 0}
                  onPress={() => {
                    if (!accountId) return;
                    const selected = items.filter(i => selectedIds.includes(i.id));
                    executeBulkReassignToInventory({ accountId, items: selected });
                    setReassignToInventoryVisible(false);
                    clearSelection();
                  }}
                  style={styles.bulkActionButton}
                />
              </>
            );
          })()}
        </View>
      </BottomSheet>
      {/* Reassign to Project picker */}
      <ReassignToProjectModal
        visible={reassignToProjectVisible}
        onRequestClose={() => {
          setReassignToProjectVisible(false);
        }}
        accountId={accountId!}
        excludeProjectId={scopeConfig?.projectId}
        bulkInfo={(() => {
          const selected = items.filter(i => selectedIds.includes(i.id));
          const { eligible, blockedCount } = filterItemsForBulkReassign(selected);
          return { eligibleCount: eligible.length, blockedCount };
        })()}
        onConfirm={(tpId) => {
          if (!accountId) return;
          const selected = items.filter(i => selectedIds.includes(i.id));
          executeBulkReassignToProject({ accountId, items: selected, targetProjectId: tpId });
          setReassignToProjectVisible(false);
          clearSelection();
        }}
      />
      {/* Bulk Set Space */}
      <SetSpaceModal
        visible={bulkSpacePickerVisible}
        onRequestClose={() => setBulkSpacePickerVisible(false)}
        projectId={scopeConfig?.projectId ?? null}
        subtitle={`${selectedIds.length} item${selectedIds.length === 1 ? '' : 's'} selected`}
        onConfirm={(spaceId) => {
          handleBulkSetSpace(spaceId);
        }}
      />
      {/* Bulk Set Transaction */}
      {scopeConfig && (
        <TransactionPickerModal
          visible={bulkTransactionPickerVisible}
          onRequestClose={() => setBulkTransactionPickerVisible(false)}
          accountId={accountId!}
          scopeConfig={scopeConfig}
          subtitle={`${selectedIds.length} item${selectedIds.length === 1 ? '' : 's'} selected`}
          onConfirm={(transaction) => {
            if (!accountId || selectedIds.length === 0) return;
            selectedIds.forEach((itemId) => {
              const update: Partial<{ transactionId: string | null; budgetCategoryId: string | null }> = { transactionId: transaction.id };
              if (transaction.budgetCategoryId) {
                update.budgetCategoryId = transaction.budgetCategoryId;
              }
              updateItem(accountId, itemId, update);
            });
            setBulkTransactionPickerVisible(false);
            clearSelection();
          }}
        />
      )}
      {/* Single-item Set Space */}
      <SetSpaceModal
        visible={singleItemSpacePickerVisible}
        onRequestClose={() => { setSingleItemSpacePickerVisible(false); setSingleItemId(null); }}
        projectId={scopeConfig?.projectId ?? null}
        onConfirm={(spaceId) => {
          if (accountId && singleItemId) {
            updateItem(accountId, singleItemId, { spaceId });
          }
          setSingleItemSpacePickerVisible(false);
          setSingleItemId(null);
        }}
      />
      {/* Single-item Set Transaction */}
      {scopeConfig && (
        <TransactionPickerModal
          visible={singleItemTransactionPickerVisible}
          onRequestClose={() => { setSingleItemTransactionPickerVisible(false); setSingleItemId(null); }}
          accountId={accountId!}
          scopeConfig={scopeConfig}
          onConfirm={(transaction) => {
            if (accountId && singleItemId) {
              const update: Partial<{ transactionId: string | null; budgetCategoryId: string | null }> = { transactionId: transaction.id };
              if (transaction.budgetCategoryId) {
                update.budgetCategoryId = transaction.budgetCategoryId;
              }
              updateItem(accountId, singleItemId, update);
            }
            setSingleItemTransactionPickerVisible(false);
            setSingleItemId(null);
          }}
        />
      )}
      {/* Single-item Sell to Business */}
      <SellToBusinessModal
        visible={singleItemSellToBusinessVisible}
        onRequestClose={() => { setSingleItemSellToBusinessVisible(false); setSingleItemId(null); }}
        sourceBudgetCategories={sellBudgetCategories}
        showSourceCategoryPicker={(() => {
          if (!singleItemId) return false;
          const item = items.find(i => i.id === singleItemId);
          return item ? needsSourceCategoryPicker([item] as ItemForCategoryResolution[]) : false;
        })()}
        onConfirm={(scId) => {
          if (!accountId || !scopeConfig || scopeConfig.scope !== 'project' || !scopeConfig.projectId || !singleItemId) return;
          const item = items.find(i => i.id === singleItemId);
          if (!item) return;
          executeSellToBusiness({ accountId, projectId: scopeConfig.projectId, items: [item], sourceCategoryId: scId });
          setSingleItemSellToBusinessVisible(false);
          setSingleItemId(null);
          showToast('Item sold to business');
        }}
      />
      {/* Single-item Sell to Project */}
      <SellToProjectModal
        visible={singleItemSellToProjectVisible}
        onRequestClose={() => { setSingleItemSellToProjectVisible(false); setSingleItemId(null); }}
        accountId={accountId!}
        excludeProjectId={scopeConfig?.projectId}
        destBudgetCategories={sellDestBudgetCategories}
        sourceBudgetCategories={sellBudgetCategories}
        showSourceCategoryPicker={(() => {
          if (!singleItemId || scopeConfig?.scope !== 'project') return false;
          const item = items.find(i => i.id === singleItemId);
          return item ? needsSourceCategoryPicker([item] as ItemForCategoryResolution[]) : false;
        })()}
        showDestCategoryPicker={(() => {
          if (!singleItemId) return false;
          const item = items.find(i => i.id === singleItemId);
          return item ? needsDestinationCategoryPicker([item] as ItemForCategoryResolution[], new Set(Object.keys(sellDestBudgetCategories))) : false;
        })()}
        onTargetProjectChange={(pid) => {
          setSellTargetProjectId(pid);
        }}
        onConfirm={({ targetProjectId: tpId, destCategoryId: dcId, sourceCategoryId: scId }) => {
          if (!accountId || !tpId || !singleItemId) return;
          const item = items.find(i => i.id === singleItemId);
          if (!item) return;
          executeSellToProject({
            accountId,
            scope: scopeConfig?.scope ?? 'inventory',
            sourceProjectId: scopeConfig?.projectId,
            targetProjectId: tpId,
            items: [item],
            sourceCategoryId: scId,
            destCategoryId: dcId,
            validDestCategoryIds: new Set(Object.keys(sellDestBudgetCategories)),
          });
          setSingleItemSellToProjectVisible(false);
          setSingleItemId(null);
          showToast('Item sold to project');
        }}
      />
      {/* Single-item Reassign to Project */}
      <ReassignToProjectModal
        visible={singleItemReassignToProjectVisible}
        onRequestClose={() => { setSingleItemReassignToProjectVisible(false); setSingleItemId(null); }}
        accountId={accountId!}
        excludeProjectId={scopeConfig?.projectId}
        onConfirm={(tpId) => {
          if (!accountId || !singleItemId) return;
          reassignItemToProject(accountId, singleItemId, tpId);
          setSingleItemReassignToProjectVisible(false);
          setSingleItemId(null);
        }}
      />
      <BottomSheetMenuList
        visible={!!statusMenuItemId}
        onRequestClose={() => setStatusMenuItemId(null)}
        items={statusMenuItems}
        title="Change Status"
      />
      {embedded ? (
        // Embedded mode: picker uses FlatList (virtualized); non-picker uses View (parent handles scroll)
        groupedRows.length === 0 ? (
          <View style={styles.emptyState}>
            {picker && outsideLoading ? (
              <>
                <AppText variant="body">Loading items…</AppText>
              </>
            ) : picker && outsideError ? (
              <AppText variant="body" style={{ color: theme.colors.error ?? 'red' }}>
                {outsideError}
              </AppText>
            ) : (
              <AppText variant="body">
                {isLoading ? 'Loading items…' : emptyMessage}
              </AppText>
            )}
          </View>
        ) : picker ? (
          <FlatList
            style={styles.pickerScroll}
            data={groupedRows}
            keyExtractor={(row) => (row.type === 'group' ? row.groupId : row.item.id)}
            contentContainerStyle={styles.list}
            ListEmptyComponent={
              <View style={styles.emptyState}>
                {outsideLoading ? (
                  <AppText variant="body">Loading items…</AppText>
                ) : outsideError ? (
                  <AppText variant="body" style={{ color: theme.colors.error ?? 'red' }}>
                    {outsideError}
                  </AppText>
                ) : (
                  <AppText variant="body">
                    {isLoading ? 'Loading items…' : emptyMessage}
                  </AppText>
                )}
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
                  const budgetCategoryName = item.item.budgetCategoryId
                    ? budgetCategories[item.item.budgetCategoryId]?.name ?? undefined
                    : undefined;

                  const baseCardProps: ItemCardProps = {
                    name: item.label,
                    sku: item.item.sku ?? undefined,
                    sourceLabel: item.item.source ?? undefined,
                    locationLabel: scopeConfig?.fields?.showBusinessInventoryLocation ? item.item.spaceId ?? undefined : undefined,
                    priceLabel: formatCents(getDisplayPriceCents(item.item)) ?? undefined,
                    statusLabel: getItemStatusLabel(item.item.status) || undefined,
                    budgetCategoryName: budgetCategoryName,
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
                    onStatusPress: () => handleStatusPress(item.id),
                    onPress: () => {
                      handleOpenItem(item.id);
                    },
                  };

                  const pickerProps = pickerMode.getPickerItemProps(item.item, isSelected);
                  return {
                    ...baseCardProps,
                    onPress: pickerProps.onPress,
                    onSelectedChange: pickerProps.onSelectedChange,
                    onBookmarkPress: undefined,
                    onStatusPress: undefined,
                    menuItems: undefined,
                    headerAction: pickerProps.headerAction,
                    statusLabel: pickerProps.statusLabel ?? baseCardProps.statusLabel,
                    style: pickerProps.style,
                  };
                })}
                expanded={!isCollapsed}
                onExpandedChange={(next) => setGroupExpanded(row.groupId, next)}
                {...pickerMode.getPickerGroupProps(row.items.map(i => i.item), groupIds)}
              />
            );
          }

          const item = row.item;
          const isSelected = selectedIds.includes(item.id);
          const menuItems = getMenuItems(item.item, item.label);
          const budgetCategoryName = item.item.budgetCategoryId
            ? budgetCategories[item.item.budgetCategoryId]?.name ?? undefined
            : undefined;

          const pickerProps = pickerMode.getPickerItemProps(item.item, isSelected);

          return (
            <ItemCard
              name={item.label}
              sku={item.item.sku ?? undefined}
              sourceLabel={item.item.source ?? undefined}
              locationLabel={scopeConfig?.fields?.showBusinessInventoryLocation ? item.item.spaceId ?? undefined : undefined}
              priceLabel={formatCents(getDisplayPriceCents(item.item)) ?? undefined}
              statusLabel={pickerProps.statusLabel ?? (getItemStatusLabel(item.item.status) || undefined)}
              budgetCategoryName={budgetCategoryName}
              thumbnailUri={getPrimaryImage(item.item) ?? undefined}
              selected={isSelected}
              onSelectedChange={pickerProps.onSelectedChange}
              menuItems={undefined}
              bookmarked={undefined}
              onBookmarkPress={undefined}
              onStatusPress={undefined}
              onPress={pickerProps.onPress}
              headerAction={pickerProps.headerAction}
              style={pickerProps.style}
            />
          );
            }}
          />
        ) : (
          <View style={styles.list}>
            {groupedRows.map((row) => {
              const renderContent = () => {
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
                  const budgetCategoryName = item.item.budgetCategoryId
                    ? budgetCategories[item.item.budgetCategoryId]?.name ?? undefined
                    : undefined;

                  return {
                    name: item.label,
                    sku: item.item.sku ?? undefined,
                    sourceLabel: item.item.source ?? undefined,
                    locationLabel: scopeConfig?.fields?.showBusinessInventoryLocation ? item.item.spaceId ?? undefined : undefined,
                    priceLabel: formatCents(getDisplayPriceCents(item.item)) ?? undefined,
                    statusLabel: getItemStatusLabel(item.item.status) || undefined,
                    budgetCategoryName: budgetCategoryName,
                    thumbnailUri: getPrimaryImage(item.item) ?? undefined,
                    selected: isSelected,
                    onSelectedChange: (next: boolean) => {
                      setItemSelected(item.id, next);
                    },
                    menuItems,
                    bookmarked: Boolean(item.item.bookmark ?? (item.item as any).isBookmarked),
                    onBookmarkPress: () => {
                      if (!accountId) return;
                      const next = !(item.item.bookmark ?? (item.item as any).isBookmarked);
                      updateItem(accountId, item.id, { bookmark: next });
                    },
                    onStatusPress: () => handleStatusPress(item.id),
                    onPress: () => {
                      handleOpenItem(item.id);
                    },
                  };
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
          const budgetCategoryName = item.item.budgetCategoryId
            ? budgetCategories[item.item.budgetCategoryId]?.name ?? undefined
            : undefined;

          return (
            <ItemCard
              name={item.label}
              sku={item.item.sku ?? undefined}
              sourceLabel={item.item.source ?? undefined}
              locationLabel={scopeConfig?.fields?.showBusinessInventoryLocation ? item.item.spaceId ?? undefined : undefined}
              priceLabel={formatCents(getDisplayPriceCents(item.item)) ?? undefined}
              statusLabel={getItemStatusLabel(item.item.status) || undefined}
              budgetCategoryName={budgetCategoryName}
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
              onStatusPress={() => handleStatusPress(item.id)}
              onPress={() => {
                handleOpenItem(item.id);
              }}
            />
          );
              };

              return (
                <View key={row.type === 'group' ? row.groupId : row.item.id}>
                  {renderContent()}
                </View>
              );
            })}
          </View>
        )
      ) : (
        // Standalone mode: Use FlatList with scroll
        <FlatList
          style={{ flex: 1 }}
          ref={listRef}
          data={groupedRows}
          keyExtractor={(row) => (row.type === 'group' ? row.groupId : row.item.id)}
          contentContainerStyle={styles.list}
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
              {picker && outsideLoading ? (
                <>
                  <AppText variant="body">Loading items…</AppText>
                </>
              ) : picker && outsideError ? (
                <AppText variant="body" style={{ color: theme.colors.error ?? 'red' }}>
                  {outsideError}
                </AppText>
              ) : (
                <AppText variant="body">
                  {isLoading ? 'Loading items…' : emptyMessage}
                </AppText>
              )}
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

                    const baseCardProps: ItemCardProps = {
                      name: item.label,
                      sku: item.item.sku ?? undefined,
                      sourceLabel: item.item.source ?? undefined,
                      locationLabel: scopeConfig?.fields?.showBusinessInventoryLocation ? item.item.spaceId ?? undefined : undefined,
                      priceLabel: formatCents(getDisplayPriceCents(item.item)) ?? undefined,
                      statusLabel: getItemStatusLabel(item.item.status) || undefined,
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
                      onStatusPress: () => handleStatusPress(item.id),
                      onPress: () => {
                        handleOpenItem(item.id);
                      },
                    };

                    // Apply picker mode overrides if enabled
                    if (picker) {
                      const pickerProps = pickerMode.getPickerItemProps(item.item, isSelected);
                      return {
                        ...baseCardProps,
                        onPress: pickerProps.onPress,
                        onSelectedChange: pickerProps.onSelectedChange,
                        onBookmarkPress: undefined,
                        onStatusPress: undefined,
                        menuItems: undefined,
                        headerAction: pickerProps.headerAction,
                        statusLabel: pickerProps.statusLabel ?? baseCardProps.statusLabel,
                        style: pickerProps.style,
                      };
                    }

                    return baseCardProps;
                  })}
                  expanded={!isCollapsed}
                  onExpandedChange={(next) => setGroupExpanded(row.groupId, next)}
                  {...(picker
                    ? pickerMode.getPickerGroupProps(row.items.map(i => i.item), groupIds)
                    : {
                        selected: groupSelected,
                        onSelectedChange: (next) => {
                          setGroupSelection(groupIds, next);
                        },
                      })}
                />
              );
            }

            const item = row.item;
            const isSelected = selectedIds.includes(item.id);
            const menuItems = getMenuItems(item.item, item.label);
            const budgetCategoryName = item.item.budgetCategoryId
              ? budgetCategories[item.item.budgetCategoryId]?.name ?? undefined
              : undefined;

            // Apply picker mode overrides if enabled
            const pickerProps = picker ? pickerMode.getPickerItemProps(item.item, isSelected) : {};

            return (
              <ItemCard
                name={item.label}
                sku={item.item.sku ?? undefined}
                sourceLabel={item.item.source ?? undefined}
                locationLabel={scopeConfig?.fields?.showBusinessInventoryLocation ? item.item.spaceId ?? undefined : undefined}
                priceLabel={formatCents(getDisplayPriceCents(item.item)) ?? undefined}
                statusLabel={picker ? pickerProps.statusLabel : getItemStatusLabel(item.item.status) || undefined}
                budgetCategoryName={budgetCategoryName}
                thumbnailUri={getPrimaryImage(item.item) ?? undefined}
                selected={isSelected}
                onSelectedChange={picker ? pickerProps.onSelectedChange : (next) => setItemSelected(item.id, next)}
                menuItems={picker ? undefined : menuItems}
                bookmarked={picker ? undefined : Boolean(item.item.bookmark ?? (item.item as any).isBookmarked)}
                onBookmarkPress={picker ? undefined : () => {
                  if (!accountId) return;
                  const next = !(item.item.bookmark ?? (item.item as any).isBookmarked);
                  updateItem(accountId, item.id, { bookmark: next });
                }}
                onStatusPress={picker ? undefined : () => handleStatusPress(item.id)}
                onPress={picker ? pickerProps.onPress : () => {
                  handleOpenItem(item.id);
                }}
                headerAction={picker ? pickerProps.headerAction : undefined}
                style={picker ? pickerProps.style : undefined}
              />
            );
          }}
        />
      )}
      {!embedded && (
        <BulkSelectionBar
          selectedCount={selectedIds.length}
          onBulkActionsPress={() => setBulkSheetOpen(true)}
          onClearSelection={clearSelection}
        />
      )}
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
  pickerScroll: {
    flex: 1,
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
  bulkActionButton: {
    minHeight: 36,
    paddingVertical: 8,
    paddingHorizontal: 12,
  },
});
