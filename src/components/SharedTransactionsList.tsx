import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, Pressable, RefreshControl, Share, StyleSheet, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { AppText } from './AppText';
import { ListControlBar } from './ListControlBar';
import { useScreenRefresh } from './Screen';
import { useListState } from '../data/listStateStore';
import { getScopeId, ScopeConfig } from '../data/scopeConfig';
import { layout } from '../ui';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { useAccountContextStore } from '../auth/accountContextStore';
import { useScopedListenersMultiple } from '../data/useScopedListeners';
import {
  refreshScopedTransactions,
  ScopedItem,
  ScopedTransaction,
  subscribeToScopedItems,
  subscribeToScopedTransactions,
} from '../data/scopedListData';
import { isCanonicalTransactionId } from '../data/inventoryOperations';
import { subscribeToBudgetCategories, mapBudgetCategories } from '../data/budgetCategoriesService';
import { updateTransaction } from '../data/transactionsService';

type SharedTransactionsListProps = {
  scopeConfig: ScopeConfig;
  listStateKey: string;
  refreshToken?: number;
};

type TransactionRow = {
  id: string;
  label: string;
  subtitle?: string;
  transaction: ScopedTransaction;
};

type TransactionFilters = {
  status?: 'all' | 'pending' | 'completed' | 'canceled' | 'inventory-only';
  reimbursement?: 'all' | 'we-owe' | 'client-owes';
  receipt?: 'all' | 'yes' | 'no';
  type?: 'all' | 'purchase' | 'return';
  budgetCategoryId?: string;
  completeness?: 'all' | 'needs-review' | 'complete';
  source?: string;
};

const SORT_MODES = ['date-desc', 'date-asc', 'created-desc', 'created-asc', 'source', 'amount'] as const;
type SortMode = (typeof SORT_MODES)[number];
const DEFAULT_SORT: SortMode = 'date-desc';

function getCanonicalTitle(id: string): string {
  if (id.startsWith('INV_PURCHASE_')) return 'Company Inventory Purchase';
  if (id.startsWith('INV_SALE_')) return 'Company Inventory Sale';
  return `Transaction ${id.slice(0, 6)}`;
}

function formatCents(value?: number | null) {
  if (typeof value !== 'number') return null;
  return `$${(value / 100).toFixed(2)}`;
}

function computeCanonicalTotal(items: ScopedItem[]): number {
  return items.reduce((sum, item) => {
    const value =
      typeof item.projectPriceCents === 'number'
        ? item.projectPriceCents
        : typeof item.purchasePriceCents === 'number'
          ? item.purchasePriceCents
          : 0;
    return sum + value;
  }, 0);
}

export function SharedTransactionsList({ scopeConfig, listStateKey, refreshToken }: SharedTransactionsListProps) {
  const listRef = useRef<FlatList<TransactionRow>>(null);
  const { state, setSearch, setSort, setFilters, setRestoreHint, clearRestoreHint } = useListState(listStateKey);
  const [query, setQuery] = useState(state.search ?? '');
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [transactions, setTransactions] = useState<ScopedTransaction[]>([]);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [bulkMode, setBulkMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string }>>({});
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const scopeId = useMemo(() => getScopeId(scopeConfig), [scopeConfig]);
  const lastScrollOffsetRef = useRef(0);
  const lastSelfHealRef = useRef<Record<string, number>>({});
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
      setTransactions([]);
      setIsLoading(false);
    }
  }, [accountId, scopeId]);

  useEffect(() => {
    if (!accountId) {
      setBudgetCategories({});
      return;
    }
    return subscribeToBudgetCategories(accountId, (next) => {
      setBudgetCategories(mapBudgetCategories(next));
    });
  }, [accountId]);

  useEffect(() => {
    if (!accountId || !scopeId || refreshToken == null) {
      return;
    }
    void refreshScopedTransactions(accountId, scopeConfig, 'online').then((next) => {
      if (next.length) {
        setTransactions(next);
      }
    });
  }, [accountId, refreshToken, scopeConfig, scopeId]);

  const handleSubscribe = useCallback(() => {
    if (!accountId || !scopeId) {
      setTransactions([]);
      setIsLoading(false);
      return () => {};
    }

    setIsLoading(true);
    return subscribeToScopedTransactions(accountId, scopeConfig, (next) => {
      setTransactions(next);
      setIsLoading(false);
    });
  }, [accountId, scopeConfig, scopeId]);

  const handleItemsSubscribe = useCallback(() => {
    if (!accountId || !scopeId) {
      setItems([]);
      return () => {};
    }
    return subscribeToScopedItems(accountId, scopeConfig, (next) => {
      setItems(next);
    });
  }, [accountId, scopeConfig, scopeId]);

  useScopedListenersMultiple(scopeId, [handleSubscribe, handleItemsSubscribe]);

  const rows = useMemo(() => {
    return transactions.map((tx) => {
      const linkedItems = items.filter((item) => item.transactionId === tx.id);
      const canonicalTotal = isCanonicalTransactionId(tx.id) ? computeCanonicalTotal(linkedItems) : null;
      const amountValue =
        typeof canonicalTotal === 'number' ? canonicalTotal : typeof tx.amountCents === 'number' ? tx.amountCents : null;
      const amountLabel = amountValue != null ? `$${(amountValue / 100).toFixed(2)}` : 'No amount';
      const dateLabel = tx.transactionDate?.trim() || 'No date';
      const sourceLabel = tx.source?.trim() || '';
      const label = isCanonicalTransactionId(tx.id) ? getCanonicalTitle(tx.id) : sourceLabel || tx.id.slice(0, 6);
      const subtitle = [amountLabel, dateLabel, sourceLabel].filter(Boolean).join(' • ');
      return { id: tx.id, label, subtitle, transaction: tx };
    });
  }, [items, transactions]);

  const sortMode = (state.sort as SortMode | undefined) ?? DEFAULT_SORT;

  const activeFilters = (state.filters ?? {}) as TransactionFilters;

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const filteredTx = needle
      ? rows.filter((row) => {
          const tx = row.transaction;
          const amount = typeof tx.amountCents === 'number' ? (tx.amountCents / 100).toFixed(2) : '';
          const haystack = [
            row.label,
            tx.source ?? '',
            tx.notes ?? '',
            tx.type ?? '',
            amount,
          ]
            .join(' ')
            .toLowerCase();
          return haystack.includes(needle);
        })
      : rows;

    const filteredByFilters = filteredTx.filter((row) => {
      const tx = row.transaction;
      if (activeFilters.status && activeFilters.status !== 'all') {
        if (activeFilters.status === 'inventory-only' && tx.projectId !== null) return false;
        if (activeFilters.status !== 'inventory-only' && tx.status !== activeFilters.status) return false;
      }
      if (activeFilters.type && activeFilters.type !== 'all' && tx.type !== activeFilters.type) return false;
      const receiptFilter = (activeFilters.receipt === ('no-email' as any) ? 'no' : activeFilters.receipt) as
        | 'all'
        | 'yes'
        | 'no'
        | undefined;
      if (receiptFilter && receiptFilter !== 'all') {
        if (receiptFilter === 'yes' && !tx.hasEmailReceipt) return false;
        if (receiptFilter === 'no' && tx.hasEmailReceipt) return false;
      }
      if (activeFilters.reimbursement && activeFilters.reimbursement !== 'all') {
        const match =
          activeFilters.reimbursement === 'we-owe'
            ? 'owed-to-company'
            : activeFilters.reimbursement === 'client-owes'
              ? 'owed-to-client'
              : '';
        if (match && tx.reimbursementType !== match) return false;
      }
      if (activeFilters.completeness && activeFilters.completeness !== 'all') {
        if (activeFilters.completeness === 'needs-review' && !tx.needsReview) return false;
        if (activeFilters.completeness === 'complete' && tx.needsReview) return false;
      }
      if (activeFilters.budgetCategoryId) {
        if (isCanonicalTransactionId(tx.id)) {
          const matchingItem = items.find(
            (item) => item.transactionId === tx.id && item.inheritedBudgetCategoryId === activeFilters.budgetCategoryId
          );
          if (!matchingItem) return false;
        } else if (tx.budgetCategoryId !== activeFilters.budgetCategoryId) {
          return false;
        }
      }
      if (activeFilters.source) {
        const value = tx.source?.toLowerCase() ?? '';
        if (!value.includes(activeFilters.source.toLowerCase())) return false;
      }
      return true;
    });

    const sorted = [...filteredByFilters].sort((a, b) => {
      if (sortMode === 'source') {
        return (a.transaction.source ?? '').localeCompare(b.transaction.source ?? '');
      }
      if (sortMode === 'amount') {
        return (b.transaction.amountCents ?? 0) - (a.transaction.amountCents ?? 0);
      }
      if (sortMode === 'created-desc' || sortMode === 'created-asc') {
        const aDate = a.transaction.createdAt ? String(a.transaction.createdAt) : '';
        const bDate = b.transaction.createdAt ? String(b.transaction.createdAt) : '';
        const order = sortMode === 'created-desc' ? -1 : 1;
        if (aDate && bDate) {
          return order * bDate.localeCompare(aDate);
        }
      }
      const aDate = a.transaction.transactionDate ?? '';
      const bDate = b.transaction.transactionDate ?? '';
      const order = sortMode === 'date-asc' ? 1 : -1;
      if (aDate && bDate) {
        return order * aDate.localeCompare(bDate);
      }
      return b.id.localeCompare(a.id);
    });

    return sorted;
  }, [activeFilters, items, query, rows, sortMode]);

  useEffect(() => {
    const restore = state.restore;
    if (!restore) return;

    let restored = false;
    if (restore.anchorId) {
      const index = filtered.findIndex((tx) => tx.id === restore.anchorId);
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
  }, [clearRestoreHint, filtered, state.restore]);

  useEffect(() => {
    if (!accountId) return;
    const now = Date.now();
    const nextHeal: Record<string, number> = { ...lastSelfHealRef.current };
    filtered.forEach((row) => {
      if (!isCanonicalTransactionId(row.id)) return;
      const linkedItems = items.filter((item) => item.transactionId === row.id);
      const computed = computeCanonicalTotal(linkedItems);
      if (typeof row.transaction.amountCents !== 'number') return;
      if (row.transaction.amountCents === computed) return;
      const last = nextHeal[row.id] ?? 0;
      if (now - last < 10_000) return;
      nextHeal[row.id] = now;
      void updateTransaction(accountId, row.id, { amountCents: computed });
    });
    lastSelfHealRef.current = nextHeal;
  }, [accountId, filtered, items]);

  const toggleSelection = useCallback((id: string) => {
    setSelectedIds((prev) => (prev.includes(id) ? prev.filter((itemId) => itemId !== id) : [...prev, id]));
  }, []);

  const handleSelectAll = useCallback(() => {
    if (selectedIds.length === filtered.length) {
      setSelectedIds([]);
    } else {
      setSelectedIds(filtered.map((row) => row.id));
    }
  }, [filtered, selectedIds.length]);

  const allSelected = bulkMode && selectedIds.length === filtered.length && filtered.length > 0;

  const handleToggleSort = useCallback(() => {
    const currentIndex = SORT_MODES.indexOf(sortMode);
    const nextMode = SORT_MODES[(currentIndex + 1) % SORT_MODES.length];
    setSort(nextMode);
  }, [setSort, sortMode]);

  const handleCreateTransaction = useCallback(() => {
    router.push({
      pathname: '/transactions/new',
      params: {
        scope: scopeConfig.scope,
        projectId: scopeConfig.projectId ?? '',
        listStateKey,
      },
    });
  }, [listStateKey, router, scopeConfig.projectId, scopeConfig.scope]);

  const handleExportCsv = useCallback(async (ids?: string[]) => {
    if (!scopeConfig.capabilities?.canExportCsv) return;
    const targetIds = ids && ids.length ? new Set(ids) : null;
    const targetTransactions = targetIds ? transactions.filter((tx) => targetIds.has(tx.id)) : transactions;
    const headers = ['id', 'date', 'source', 'amount', 'categoryName', 'budgetCategoryId', 'itemCategories'];
    const rows = targetTransactions.map((tx) => {
      const isCanonical = isCanonicalTransactionId(tx.id);
      const categoryName =
        tx.budgetCategoryId && budgetCategories[tx.budgetCategoryId]
          ? budgetCategories[tx.budgetCategoryId].name
          : '';
      const itemCategories = items
        .filter((item) => item.transactionId === tx.id && item.inheritedBudgetCategoryId)
        .map((item) => item.inheritedBudgetCategoryId)
        .filter(Boolean)
        .join('|');
      return [
        tx.id,
        tx.transactionDate ?? '',
        tx.source ?? '',
        typeof tx.amountCents === 'number' ? (tx.amountCents / 100).toFixed(2) : '',
        isCanonical ? '' : (categoryName || tx.budgetCategoryId) ?? '',
        isCanonical ? '' : tx.budgetCategoryId ?? '',
        itemCategories,
      ];
    });
    const csv = [headers, ...rows].map((row) => row.map((cell) => `"${String(cell ?? '').replace(/"/g, '""')}"`).join(',')).join('\n');
    await Share.share({ message: csv, title: `${scopeConfig.scope}-transactions.csv` });
  }, [budgetCategories, items, scopeConfig.capabilities?.canExportCsv, scopeConfig.scope, transactions]);

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
          { title: 'Add', variant: 'primary', onPress: handleCreateTransaction, iconName: 'add' },
          ...(scopeConfig.capabilities?.canExportCsv
            ? [
                {
                  title: 'Export',
                  variant: 'secondary' as const,
                  onPress: () => handleExportCsv(),
                  iconName: 'file-download',
                },
              ]
            : []),
        ]}
      />
      <Pressable
        onPress={() => {
          if (!bulkMode) {
            setBulkMode(true);
            handleSelectAll();
          } else {
            handleSelectAll();
          }
        }}
        style={({ pressed }) => [styles.selectAllRow, pressed && styles.selectAllPressed]}
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
          {bulkMode && allSelected && <AppText style={styles.checkmark}>✓</AppText>}
        </View>
        <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
          Select all
        </AppText>
      </Pressable>
      {filtersOpen ? (
        <View style={styles.filterPanel}>
          <View style={styles.filterRow}>
            <AppText variant="caption">Status</AppText>
            <View style={styles.filterRow}>
              {(['all', 'pending', 'completed', 'canceled'] as const).map((mode) => (
                <Pressable
                  key={mode}
                  onPress={() => setFilters({ ...activeFilters, status: mode })}
                >
                  <AppText variant="caption">{mode}</AppText>
                </Pressable>
              ))}
              {scopeConfig.capabilities?.supportsInventoryOnlyStatusFilter ? (
                <Pressable onPress={() => setFilters({ ...activeFilters, status: 'inventory-only' })}>
                  <AppText variant="caption">inventory-only</AppText>
                </Pressable>
              ) : null}
            </View>
          </View>
          <TextInput
            value={activeFilters.source ?? ''}
            onChangeText={(value) => setFilters({ ...activeFilters, source: value })}
            placeholder="Source filter"
            placeholderTextColor={theme.colors.textSecondary}
            style={[styles.filterInput, { borderColor: uiKitTheme.border.primary, color: theme.colors.text }]}
          />
          <TextInput
            value={activeFilters.budgetCategoryId ?? ''}
            onChangeText={(value) => setFilters({ ...activeFilters, budgetCategoryId: value })}
            placeholder="Budget category id"
            placeholderTextColor={theme.colors.textSecondary}
            style={[styles.filterInput, { borderColor: uiKitTheme.border.primary, color: theme.colors.text }]}
          />
          <View style={styles.filterRow}>
            <Pressable onPress={() => setFilters({ ...activeFilters, receipt: 'yes' })}>
              <AppText variant="caption">Receipt emailed</AppText>
            </Pressable>
            <Pressable onPress={() => setFilters({ ...activeFilters, receipt: 'no' })}>
              <AppText variant="caption">No receipt email</AppText>
            </Pressable>
            <Pressable onPress={() => setFilters({ ...activeFilters, receipt: 'all' })}>
              <AppText variant="caption">All receipts</AppText>
            </Pressable>
          </View>
          <View style={styles.filterRow}>
            <Pressable onPress={() => setFilters({ ...activeFilters, reimbursement: 'we-owe' })}>
              <AppText variant="caption">We owe</AppText>
            </Pressable>
            <Pressable onPress={() => setFilters({ ...activeFilters, reimbursement: 'client-owes' })}>
              <AppText variant="caption">Client owes</AppText>
            </Pressable>
            <Pressable onPress={() => setFilters({ ...activeFilters, reimbursement: 'all' })}>
              <AppText variant="caption">All reimbursement</AppText>
            </Pressable>
          </View>
          <View style={styles.filterRow}>
            <Pressable onPress={() => setFilters({ ...activeFilters, type: 'purchase' })}>
              <AppText variant="caption">Purchase</AppText>
            </Pressable>
            <Pressable onPress={() => setFilters({ ...activeFilters, type: 'return' })}>
              <AppText variant="caption">Return</AppText>
            </Pressable>
            <Pressable onPress={() => setFilters({ ...activeFilters, type: 'all' })}>
              <AppText variant="caption">All types</AppText>
            </Pressable>
          </View>
          <View style={styles.filterRow}>
            <Pressable onPress={() => setFilters({ ...activeFilters, completeness: 'needs-review' })}>
              <AppText variant="caption">Needs review</AppText>
            </Pressable>
            <Pressable onPress={() => setFilters({ ...activeFilters, completeness: 'complete' })}>
              <AppText variant="caption">Complete</AppText>
            </Pressable>
            <Pressable onPress={() => setFilters({ ...activeFilters, completeness: 'all' })}>
              <AppText variant="caption">All completeness</AppText>
            </Pressable>
          </View>
        </View>
      ) : null}
      {bulkMode ? (
        <View
          style={[
            styles.bulkPanel,
            { backgroundColor: uiKitTheme.background.surface, borderColor: uiKitTheme.border.primary },
          ]}
        >
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
          {scopeConfig.capabilities?.canExportCsv ? (
            <Pressable onPress={() => handleExportCsv(selectedIds)} style={styles.bulkActionButton}>
              <AppText variant="caption" style={{ color: theme.colors.primary }}>
                Export CSV
              </AppText>
            </Pressable>
          ) : null}
        </View>
      ) : null}
      <FlatList
        ref={listRef}
        data={filtered}
        keyExtractor={(item) => item.id}
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
              {isLoading ? 'Loading transactions…' : 'No transactions yet.'}
            </AppText>
          </View>
        }
        renderItem={({ item }) => (
          <Pressable
            onPress={() => {
              if (bulkMode) {
                toggleSelection(item.id);
                return;
              }
              setRestoreHint({ anchorId: item.id, scrollOffset: lastScrollOffsetRef.current });
              const backTarget =
                scopeConfig.scope === 'inventory'
                  ? '/(tabs)/screen-two?tab=transactions'
                  : scopeConfig.projectId
                    ? `/project/${scopeConfig.projectId}?tab=transactions`
                    : '/(tabs)/index';
              router.push({
                pathname: '/transactions/[id]',
                params: {
                  id: item.id,
                  listStateKey,
                  backTarget,
                  scope: scopeConfig.scope,
                  projectId: scopeConfig.projectId ?? '',
                },
              });
            }}
            style={({ pressed }) => [
              styles.row,
              { borderColor: uiKitTheme.border.primary, backgroundColor: uiKitTheme.background.surface },
              pressed && styles.rowPressed,
            ]}
          >
            {bulkMode ? (
              <View
                style={[
                  styles.checkbox,
                  {
                    borderColor: uiKitTheme.border.primary,
                    backgroundColor: selectedIds.includes(item.id) ? uiKitTheme.primary.main : 'transparent',
                  },
                ]}
              >
                {selectedIds.includes(item.id) ? <AppText style={styles.checkmark}>✓</AppText> : null}
              </View>
            ) : null}
            <View style={styles.rowContent}>
              <AppText variant="body">{item.label}</AppText>
              {item.subtitle ? <AppText variant="caption">{item.subtitle}</AppText> : null}
              {!isCanonicalTransactionId(item.id) && item.transaction.budgetCategoryId ? (
                <AppText variant="caption">
                  {budgetCategories[item.transaction.budgetCategoryId]?.name ?? item.transaction.budgetCategoryId}
                </AppText>
              ) : null}
            </View>
          </Pressable>
        )}
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
  list: {
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
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  rowPressed: {
    opacity: 0.7,
  },
  rowContent: {
    flex: 1,
    gap: 4,
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
  bulkActionButton: {
    paddingVertical: 6,
  },
});
