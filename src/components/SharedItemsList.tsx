import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, Pressable, RefreshControl, StyleSheet, Text, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { AppText } from './AppText';
import { AppButton } from './AppButton';
import { ListControlBar } from './ListControlBar';
import { ItemCard } from './ItemCard';
import { useScreenRefresh } from './Screen';
import { useListState } from '../data/listStateStore';
import { getScopeId, ScopeConfig } from '../data/scopeConfig';
import { layout } from '../ui';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { useAccountContextStore } from '../auth/accountContextStore';
import { useScopedListeners } from '../data/useScopedListeners';
import { refreshScopedItems, ScopedItem, subscribeToScopedItems } from '../data/scopedListData';
import { deleteItem, updateItem } from '../data/itemsService';
import { requestBusinessToProjectPurchase, requestProjectToBusinessSale } from '../data/inventoryOperations';
import { resolveAttachmentUri } from '../offline/media';

type SharedItemsListProps = {
  scopeConfig: ScopeConfig;
  listStateKey: string;
  refreshToken?: number;
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
  | 'no-description'
  | 'no-project-price'
  | 'no-image'
  | 'no-transaction';

type ItemFilters = {
  mode?: ItemFilterMode;
  showDuplicates?: boolean;
};

type ListRow =
  | { type: 'group'; groupId: string; label: string; count: number; itemIds: string[] }
  | { type: 'item'; item: ItemRow; groupId?: string };

const SORT_MODES = ['alphabetical', 'creationDate'] as const;
type SortMode = (typeof SORT_MODES)[number];
const DEFAULT_SORT: SortMode = 'creationDate';

const PROJECT_FILTER_MODES: ItemFilterMode[] = [
  'all',
  'bookmarked',
  'from-inventory',
  'to-return',
  'returned',
  'no-sku',
  'no-description',
  'no-project-price',
  'no-image',
  'no-transaction',
];

const INVENTORY_FILTER_MODES: ItemFilterMode[] = [
  'all',
  'bookmarked',
  'no-sku',
  'no-description',
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

function getPrimaryImage(item: ScopedItem) {
  const images = item.images ?? [];
  const primary = images.find((image) => image.isPrimary) ?? images[0];
  if (!primary) return null;
  return resolveAttachmentUri(primary) ?? primary.url;
}

export function SharedItemsList({ scopeConfig, listStateKey, refreshToken }: SharedItemsListProps) {
  const listRef = useRef<FlatList<ListRow>>(null);
  const { state, setSearch, setSort, setFilters, setRestoreHint, clearRestoreHint } = useListState(listStateKey);
  const [query, setQuery] = useState(state.search ?? '');
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [bulkMode, setBulkMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [bulkSpaceId, setBulkSpaceId] = useState('');
  const [bulkProjectId, setBulkProjectId] = useState('');
  const [bulkCategoryId, setBulkCategoryId] = useState('');
  const [bulkError, setBulkError] = useState<string | null>(null);
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const scopeId = useMemo(() => getScopeId(scopeConfig), [scopeConfig]);
  const lastScrollOffsetRef = useRef(0);
  const screenRefresh = useScreenRefresh();

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
    if (!accountId || !scopeId) {
      setItems([]);
      setIsLoading(false);
    }
  }, [accountId, scopeId]);

  useEffect(() => {
    if (!accountId || !scopeId || refreshToken == null) {
      return;
    }
    void refreshScopedItems(accountId, scopeConfig, 'online').then((next) => {
      if (next.length) {
        setItems(next);
      }
    });
  }, [accountId, refreshToken, scopeConfig, scopeId]);

  const handleSubscribe = useCallback(() => {
    if (!accountId || !scopeId) {
      setItems([]);
      setIsLoading(false);
      return () => {};
    }

    setIsLoading(true);
    return subscribeToScopedItems(accountId, scopeConfig, (next) => {
      setItems(next);
      setIsLoading(false);
    });
  }, [accountId, scopeConfig, scopeId]);

  useScopedListeners(scopeId, handleSubscribe);

  const rows = useMemo(() => {
    return items.map((item) => {
      const label = item.name?.trim() || item.description?.trim() || 'Untitled item';
      const subtitle = item.projectId ? `Project ${item.projectId}` : 'Inventory';
      return { id: item.id, label, subtitle, item };
    });
  }, [items]);

  const sortMode = (state.sort as SortMode | undefined) ?? DEFAULT_SORT;

  const activeFilters = (state.filters ?? {}) as ItemFilters;
  const filterModes = scopeConfig.scope === 'inventory' ? INVENTORY_FILTER_MODES : PROJECT_FILTER_MODES;

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const normalizedNeedle = normalizeSku(needle);
    const filteredItems = needle
      ? rows.filter((row) => {
          const item = row.item;
          const sku = item.sku ?? '';
          const haystack = [
            row.label,
            item.description ?? '',
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
      const mode = activeFilters.mode ?? 'all';
      if (mode === 'bookmarked' && !item.bookmark) return false;
      if (mode === 'from-inventory' && item.projectId) return false;
      if (mode === 'to-return' && item.status !== 'to return') return false;
      if (mode === 'returned' && item.status !== 'returned') return false;
      if (mode === 'no-sku' && item.sku?.trim()) return false;
      if (mode === 'no-description' && item.description?.trim()) return false;
      if (mode === 'no-project-price' && typeof item.projectPriceCents === 'number') return false;
      if (mode === 'no-image' && (item.images?.length ?? 0) > 0) return false;
      if (mode === 'no-transaction' && item.transactionId) return false;
      return true;
    });

    const sorted = [...filteredByFilters].sort((a, b) => {
      if (sortMode === 'alphabetical') {
        return a.label.localeCompare(b.label);
      }
      const aDate = a.item.createdAt ? String(a.item.createdAt) : '';
      const bDate = b.item.createdAt ? String(b.item.createdAt) : '';
      if (aDate && bDate) {
        return bDate.localeCompare(aDate);
      }
      return b.id.localeCompare(a.id);
    });

    return sorted;
  }, [activeFilters.mode, query, rows, sortMode]);

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
        itemIds: groupItems.map((item) => item.id),
      });
      if (!(state.filters as any)?.[`collapsed:${groupId}`]) {
        groupItems.forEach((item) => output.push({ type: 'item', item, groupId }));
      }
    });
    return output;
  }, [activeFilters.showDuplicates, filtered, state.filters]);

  useEffect(() => {
    const restore = state.restore;
    if (!restore) return;

    let restored = false;
    if (restore.anchorId) {
      const index = groupedRows.findIndex(
        (row) => row.type === 'item' && row.item.id === restore.anchorId
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

  const toggleSelection = useCallback((id: string) => {
    setSelectedIds((prev) => (prev.includes(id) ? prev.filter((itemId) => itemId !== id) : [...prev, id]));
  }, []);

  const handleSelectGroup = useCallback((ids: string[]) => {
    setSelectedIds((prev) => Array.from(new Set([...prev, ...ids])));
  }, []);

  const handleToggleGroup = useCallback(
    (groupId: string) => {
      const nextFilters = {
        ...(state.filters ?? {}),
        [`collapsed:${groupId}`]: !(state.filters as any)?.[`collapsed:${groupId}`],
      };
      setFilters(nextFilters as Record<string, unknown>);
    },
    [setFilters, state.filters]
  );

  const handleBulkDelete = useCallback(async () => {
    if (!accountId || selectedIds.length === 0) return;
    await Promise.all(selectedIds.map((id) => deleteItem(accountId, id)));
    setSelectedIds([]);
  }, [accountId, selectedIds]);

  const handleBulkMoveToSpace = useCallback(async () => {
    if (!accountId || selectedIds.length === 0 || !bulkSpaceId.trim()) return;
    await Promise.all(
      selectedIds.map((id) => updateItem(accountId, id, { spaceId: bulkSpaceId.trim() }))
    );
    setSelectedIds([]);
    setBulkSpaceId('');
  }, [accountId, bulkSpaceId, selectedIds]);

  const handleBulkRemoveFromSpace = useCallback(async () => {
    if (!accountId || selectedIds.length === 0) return;
    await Promise.all(selectedIds.map((id) => updateItem(accountId, id, { spaceId: null })));
    setSelectedIds([]);
  }, [accountId, selectedIds]);

  const handleBulkAllocateToProject = useCallback(async () => {
    if (!accountId || selectedIds.length === 0 || !bulkProjectId.trim()) return;
    if (!bulkCategoryId.trim()) {
      setBulkError('Select a destination category before allocating.');
      return;
    }
    setBulkError(null);
    await requestBusinessToProjectPurchase({
      accountId,
      targetProjectId: bulkProjectId.trim(),
      inheritedBudgetCategoryId: bulkCategoryId.trim(),
      items: items.filter((item) => selectedIds.includes(item.id)),
    });
    setSelectedIds([]);
    setBulkProjectId('');
    setBulkCategoryId('');
  }, [accountId, bulkCategoryId, bulkProjectId, items, selectedIds]);

  const handleBulkSellToBusiness = useCallback(async () => {
    if (!accountId || selectedIds.length === 0 || scopeConfig.scope !== 'project') return;
    const selected = items.filter((item) => selectedIds.includes(item.id));
    const missingCategory = selected.find((item) => !item.inheritedBudgetCategoryId);
    if (missingCategory) {
      setBulkError(
        'Can’t move to Design Business Inventory yet. Link this item to a categorized transaction first.'
      );
      return;
    }
    setBulkError(null);
    await requestProjectToBusinessSale({
      accountId,
      projectId: scopeConfig.projectId ?? '',
      items: selected,
    });
    setSelectedIds([]);
  }, [accountId, items, scopeConfig.projectId, scopeConfig.scope, selectedIds]);

  const handleToggleSort = useCallback(() => {
    const currentIndex = SORT_MODES.indexOf(sortMode);
    const nextMode = SORT_MODES[(currentIndex + 1) % SORT_MODES.length];
    setSort(nextMode);
  }, [setSort, sortMode]);

  const handleCreateItem = useCallback(() => {
    router.push({
      pathname: '/items/new',
      params: {
        scope: scopeConfig.scope,
        projectId: scopeConfig.projectId ?? '',
        listStateKey,
      },
    });
  }, [listStateKey, router, scopeConfig.projectId, scopeConfig.scope]);

  const handleSelectAll = useCallback(() => {
    if (selectedIds.length === filtered.length) {
      setSelectedIds([]);
    } else {
      setSelectedIds(filtered.map((row) => row.id));
    }
  }, [filtered, selectedIds.length]);

  const allSelected = bulkMode && selectedIds.length === filtered.length && filtered.length > 0;

  return (
    <View style={styles.container}>
      <ListControlBar
        search={query}
        onChangeSearch={setQuery}
        actions={[
          { title: 'Sort', variant: 'secondary', onPress: handleToggleSort, iconName: 'sort' },
          {
            title: 'Filter',
            variant: 'secondary',
            onPress: () => setFiltersOpen((prev) => !prev),
            iconName: 'filter-list',
          },
          { title: 'Add', variant: 'primary', onPress: handleCreateItem, iconName: 'add' },
        ]}
      />
      {/* Select All - moved below search */}
      <Pressable
        onPress={() => {
          if (!bulkMode) {
            setBulkMode(true);
            handleSelectAll();
          } else {
            handleSelectAll();
          }
        }}
        style={({ pressed }) => [
          styles.selectAllRow,
          pressed && styles.selectAllPressed,
        ]}
        accessibilityRole="checkbox"
        accessibilityState={{ checked: bulkMode && allSelected }}
        hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
      >
        <View
          style={[
            styles.checkbox,
            {
              borderColor: uiKitTheme.border.primary,
              backgroundColor: bulkMode && allSelected ? uiKitTheme.primary.main : 'transparent',
            },
          ]}
        >
          {bulkMode && allSelected && (
            <AppText style={styles.checkmark}>✓</AppText>
          )}
        </View>
        <Text style={[styles.selectAllLabel, { color: theme.colors.textSecondary }]}>Select all</Text>
      </Pressable>
      {filtersOpen ? (
        <View style={styles.filterPanel}>
          <View style={styles.filterRow}>
            {filterModes.map((mode) => (
              <Pressable
                key={mode}
                onPress={() => setFilters({ ...activeFilters, mode })}
                style={[
                  styles.filterChip,
                  {
                    borderColor:
                      (activeFilters.mode ?? 'all') === mode
                        ? uiKitTheme.primary.main
                        : uiKitTheme.border.primary,
                  },
                ]}
              >
                <AppText variant="caption">{mode.replace(/-/g, ' ')}</AppText>
              </Pressable>
            ))}
          </View>
          <View style={styles.filterRow}>
            <Pressable
              onPress={() =>
                setFilters({ ...activeFilters, showDuplicates: !activeFilters.showDuplicates })
              }
            >
              <AppText variant="caption">
                {activeFilters.showDuplicates === false ? 'Show duplicates' : 'Hide duplicates'}
              </AppText>
            </Pressable>
          </View>
        </View>
      ) : null}
      {bulkMode ? (
        <View style={[styles.bulkPanel, { backgroundColor: uiKitTheme.background.surface, borderColor: uiKitTheme.border.primary }]}>
          <View style={styles.bulkHeader}>
            <AppText variant="caption" style={{ fontWeight: '600' }}>
              {selectedIds.length} selected
            </AppText>
            <Pressable onPress={() => setBulkMode(false)}>
              <AppText variant="caption" style={{ color: theme.colors.primary, fontWeight: '600' }}>
                Done
              </AppText>
            </Pressable>
          </View>
          {bulkError ? (
            <AppText variant="caption" style={{ color: theme.colors.error }}>
              {bulkError}
            </AppText>
          ) : null}
          <View style={styles.bulkActions}>
            <View style={styles.bulkActionGroup}>
              <TextInput
                value={bulkSpaceId}
                onChangeText={setBulkSpaceId}
                placeholder="Target space id"
                placeholderTextColor={theme.colors.textSecondary}
                style={[styles.filterInput, { borderColor: uiKitTheme.border.primary, color: theme.colors.text }]}
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
            {scopeConfig.scope === 'inventory' ? (
              <View style={styles.bulkActionGroup}>
                <TextInput
                  value={bulkProjectId}
                  onChangeText={setBulkProjectId}
                  placeholder="Target project id"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={[styles.filterInput, { borderColor: uiKitTheme.border.primary, color: theme.colors.text }]}
                />
                <TextInput
                  value={bulkCategoryId}
                  onChangeText={setBulkCategoryId}
                  placeholder="Destination category id"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={[styles.filterInput, { borderColor: uiKitTheme.border.primary, color: theme.colors.text }]}
                />
                <AppButton
                  title="Allocate to project"
                  variant="secondary"
                  onPress={handleBulkAllocateToProject}
                  style={styles.bulkActionButton}
                />
              </View>
            ) : null}
            {scopeConfig.scope === 'project' ? (
              <AppButton
                title="Sell to business"
                variant="secondary"
                onPress={handleBulkSellToBusiness}
                style={styles.bulkActionButton}
              />
            ) : null}
            <AppButton
              title="Delete"
              variant="secondary"
              onPress={handleBulkDelete}
              style={styles.bulkActionButton}
            />
          </View>
        </View>
      ) : null}
      <FlatList
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
            <AppText variant="body">
              {isLoading ? 'Loading items…' : 'No items yet.'}
            </AppText>
          </View>
        }
        renderItem={({ item: row }) => {
          if (row.type === 'group') {
            return (
              <View style={styles.groupRow}>
                <AppText variant="body">{row.label}</AppText>
                <AppText variant="caption">{row.count} duplicates</AppText>
                {bulkMode ? (
                  <Pressable onPress={() => handleSelectGroup(row.itemIds)}>
                    <AppText variant="caption">Select group</AppText>
                  </Pressable>
                ) : null}
                <Pressable onPress={() => handleToggleGroup(row.groupId)}>
                  <AppText variant="caption">
                    {(state.filters as any)?.[`collapsed:${row.groupId}`] ? 'Expand' : 'Collapse'}
                  </AppText>
                </Pressable>
              </View>
            );
          }

          const item = row.item;
          return (
            <ItemCard
              description={item.label}
              sku={item.item.sku ?? undefined}
              sourceLabel={item.item.source ?? undefined}
              locationLabel={scopeConfig.fields?.showBusinessInventoryLocation ? item.item.spaceId ?? undefined : undefined}
              priceLabel={formatCents(item.item.projectPriceCents ?? item.item.purchasePriceCents) ?? undefined}
              statusLabel={item.item.status ?? undefined}
              thumbnailUri={getPrimaryImage(item.item) ?? undefined}
              selected={bulkMode ? selectedIds.includes(item.id) : undefined}
              onSelectedChange={bulkMode ? () => toggleSelection(item.id) : undefined}
              bookmarked={Boolean(item.item.bookmark ?? (item.item as any).isBookmarked)}
              onBookmarkPress={
                bulkMode
                  ? undefined
                  : async () => {
                      if (!accountId) return;
                      const next = !(item.item.bookmark ?? (item.item as any).isBookmarked);
                      await updateItem(accountId, item.id, { bookmark: next });
                    }
              }
              onPress={() => {
                if (bulkMode) {
                  toggleSelection(item.id);
                  return;
                }
                setRestoreHint({ anchorId: item.id, scrollOffset: lastScrollOffsetRef.current });
                const backTarget =
                  scopeConfig.scope === 'inventory'
                    ? '/(tabs)/screen-two?tab=items'
                    : scopeConfig.projectId
                      ? `/project/${scopeConfig.projectId}?tab=items`
                      : '/(tabs)/index';
                router.push({
                  pathname: '/items/[id]',
                  params: {
                    id: item.id,
                    listStateKey,
                    backTarget,
                    scope: scopeConfig.scope,
                    projectId: scopeConfig.projectId ?? '',
                  },
                });
              }}
              style={[
                styles.row,
                { borderColor: uiKitTheme.border.primary, backgroundColor: uiKitTheme.background.surface },
              ]}
            />
          );
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    gap: 16,
  },
  selectAllRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginTop: -6,
    paddingVertical: 8,
    paddingHorizontal: 4,
  },
  selectAllPressed: {
    opacity: 0.6,
  },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: 10,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkmark: {
    fontSize: 14,
    fontWeight: '700',
    color: '#FFFFFF',
    lineHeight: 18,
  },
  selectAllLabel: {
    fontSize: 14,
    fontWeight: '400',
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
  emptyState: {
    alignItems: 'center',
    paddingVertical: 12,
  },
  row: {
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 14,
    gap: 6,
  },
  rowPressed: {
    opacity: 0.7,
  },
  rowHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  filterPanel: {
    gap: 10,
    paddingVertical: 6,
  },
  filterRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  filterChip: {
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 6,
    paddingHorizontal: 10,
  },
  filterInput: {
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  bulkPanel: {
    gap: 12,
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
  },
  bulkHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
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
  groupRow: {
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 10,
    paddingHorizontal: 12,
    gap: 4,
  },
});
