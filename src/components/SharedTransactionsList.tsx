import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, Pressable, RefreshControl, Share, StyleSheet, TouchableOpacity, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { AppText } from './AppText';
import { AppButton } from './AppButton';
import { ListControlBar } from './ListControlBar';
import { BottomSheet } from './BottomSheet';
import { SelectorCircle } from './SelectorCircle';
import { FilterMenu } from './FilterMenu';
import { SortMenu } from './SortMenu';
import { TransactionCard } from './TransactionCard';
import { useScreenRefresh } from './Screen';
import { useListState } from '../data/listStateStore';
import { getScopeId, ScopeConfig } from '../data/scopeConfig';
import { BUTTON_BORDER_RADIUS, getTextColorStyle, layout } from '../ui';
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
import { isCanonicalInventorySaleTransaction } from '../data/inventoryOperations';
import { getTransactionDisplayName } from '../utils/transactionDisplayName';
import { subscribeToBudgetCategories, mapBudgetCategories } from '../data/budgetCategoriesService';
import { getBudgetCategoryColor } from '../utils/budgetCategoryColors';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import type { AnchoredMenuItem } from './AnchoredMenuList';

type SharedTransactionsListProps = {
  scopeConfig: ScopeConfig;
  listStateKey: string;
  refreshToken?: number;
};

type TransactionRow = {
  id: string;
  label: string;
  subtitle?: string;
  amountCents: number | null;
  transaction: ScopedTransaction;
};

type TransactionFilters = {
  status?: 'all' | 'pending' | 'completed' | 'canceled' | 'inventory-only' | Array<'pending' | 'completed' | 'canceled' | 'inventory-only'>;
  reimbursement?: 'all' | 'we-owe' | 'client-owes' | Array<'we-owe' | 'client-owes'>;
  receipt?: 'all' | 'yes' | 'no' | Array<'yes' | 'no'>;
  type?: 'all' | 'purchase' | 'return' | Array<'purchase' | 'return'>;
  budgetCategoryId?: string | string[];
  completeness?: 'all' | 'needs-review' | 'complete' | Array<'needs-review' | 'complete'>;
  source?: string | string[];
  purchasedBy?: 'all' | 'client-card' | 'design-business' | 'missing' | Array<'client-card' | 'design-business' | 'missing'>;
};

const SORT_MODES = [
  'date-desc',
  'date-asc',
  'created-desc',
  'created-asc',
  'source-asc',
  'source-desc',
  'amount-desc',
  'amount-asc',
] as const;
type SortMode = (typeof SORT_MODES)[number];
const DEFAULT_SORT: SortMode = 'date-desc';


function formatCents(value?: number | null) {
  if (typeof value !== 'number') return null;
  return `$${(value / 100).toFixed(2)}`;
}

function hasMeaningfulProjectPrice(item: ScopedItem): boolean {
  if (typeof item.projectPriceCents !== 'number') return false;
  if (typeof item.purchasePriceCents === 'number' && item.projectPriceCents === item.purchasePriceCents) return false;
  return true;
}

function getDisplayPriceCents(item: ScopedItem): number {
  if (hasMeaningfulProjectPrice(item)) return item.projectPriceCents ?? 0;
  if (typeof item.purchasePriceCents === 'number') return item.purchasePriceCents;
  if (typeof item.projectPriceCents === 'number') return item.projectPriceCents;
  return 0;
}

function computeCanonicalTotal(items: ScopedItem[]): number {
  return items.reduce((sum, item) => {
    const value = getDisplayPriceCents(item);
    return sum + value;
  }, 0);
}

export function SharedTransactionsList({ scopeConfig, listStateKey, refreshToken }: SharedTransactionsListProps) {
  const listRef = useRef<FlatList<TransactionRow>>(null);
  const { state, setSearch, setSort, setFilters, setRestoreHint, clearRestoreHint } = useListState(listStateKey);
  const [query, setQuery] = useState(state.search ?? '');
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [sortOpen, setSortOpen] = useState(false);
  const [showSearch, setShowSearch] = useState(false);
  const [transactions, setTransactions] = useState<ScopedTransaction[]>([]);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [bulkSheetOpen, setBulkSheetOpen] = useState(false);
  const [addMenuVisible, setAddMenuVisible] = useState(false);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string }>>({});
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const bulkSheetDividerStyle = useMemo(
    () => ({ borderBottomColor: uiKitTheme.border.secondary }),
    [uiKitTheme]
  );
  const primaryTextStyle = useMemo(() => getTextColorStyle(theme.colors.primary), [theme]);
  // const rowSurfaceStyle = useMemo(
  //   () => ({ borderColor: uiKitTheme.border.primary, backgroundColor: uiKitTheme.background.surface }),
  //   [uiKitTheme]
  // );
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
    if (selectedIds.length === 0 && bulkSheetOpen) {
      setBulkSheetOpen(false);
    }
  }, [bulkSheetOpen, selectedIds.length]);

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
      const isCanonical = isCanonicalInventorySaleTransaction(tx);
      const canonicalTotal = isCanonical ? computeCanonicalTotal(linkedItems) : null;
      const amountValue =
        typeof tx.amountCents === 'number'
          ? tx.amountCents
          : typeof canonicalTotal === 'number'
            ? canonicalTotal
            : null;
      const amountLabel = amountValue != null ? `$${(amountValue / 100).toFixed(2)}` : 'No amount';
      const dateLabel = tx.transactionDate?.trim() || 'No date';
      const sourceLabel = tx.source?.trim() || '';
      const label = getTransactionDisplayName(tx);
      const subtitle = [amountLabel, dateLabel, sourceLabel].filter(Boolean).join(' • ');
      return { id: tx.id, label, subtitle, amountCents: amountValue, transaction: tx };
    });
  }, [items, transactions]);

  const sortMode = (() => {
    const rawSort = state.sort as SortMode | 'source' | 'amount' | undefined;
    if (rawSort === 'source') return 'source-asc';
    if (rawSort === 'amount') return 'amount-desc';
    return rawSort ?? DEFAULT_SORT;
  })();

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
      
      // Status filter
      if (activeFilters.status && activeFilters.status !== 'all') {
        const statusValues = Array.isArray(activeFilters.status) ? activeFilters.status : [activeFilters.status];
        const matches = statusValues.some((status) => {
          if (status === 'inventory-only') return tx.projectId === null;
          return tx.status === status;
        });
        if (!matches) return false;
      }
      
      // Type filter
      if (activeFilters.type && activeFilters.type !== 'all') {
        const typeValues = Array.isArray(activeFilters.type) ? activeFilters.type : [activeFilters.type];
        if (!typeValues.includes(tx.type as any)) return false;
      }
      
      // Receipt filter
      const receiptFilter = (activeFilters.receipt === ('no-email' as any) ? 'no' : activeFilters.receipt) as
        | 'all'
        | 'yes'
        | 'no'
        | Array<'yes' | 'no'>
        | undefined;
      if (receiptFilter && receiptFilter !== 'all') {
        const receiptValues = Array.isArray(receiptFilter) ? receiptFilter : [receiptFilter];
        const matches = receiptValues.some((receipt) => {
          if (receipt === 'yes') return tx.hasEmailReceipt;
          if (receipt === 'no') return !tx.hasEmailReceipt;
          return false;
        });
        if (!matches) return false;
      }
      
      // Reimbursement filter
      if (activeFilters.reimbursement && activeFilters.reimbursement !== 'all') {
        const reimbursementValues = Array.isArray(activeFilters.reimbursement)
          ? activeFilters.reimbursement
          : [activeFilters.reimbursement];
        const matches = reimbursementValues.some((reimbursement) => {
          const match =
            reimbursement === 'we-owe'
              ? 'owed-to-client'
              : reimbursement === 'client-owes'
                ? 'owed-to-company'
                : '';
          return match && tx.reimbursementType === match;
        });
        if (!matches) return false;
      }
      
      // Completeness filter
      if (activeFilters.completeness && activeFilters.completeness !== 'all') {
        const completenessValues = Array.isArray(activeFilters.completeness)
          ? activeFilters.completeness
          : [activeFilters.completeness];
        const matches = completenessValues.some((completeness) => {
          if (completeness === 'needs-review') return tx.needsReview;
          if (completeness === 'complete') return !tx.needsReview;
          return false;
        });
        if (!matches) return false;
      }
      
      // Budget category filter
      if (activeFilters.budgetCategoryId) {
        const categoryIds = Array.isArray(activeFilters.budgetCategoryId)
          ? activeFilters.budgetCategoryId
          : [activeFilters.budgetCategoryId];
        if (!categoryIds.includes(tx.budgetCategoryId ?? '')) return false;
      }
      
      // Source filter
      if (activeFilters.source) {
        const sourceValues = Array.isArray(activeFilters.source) ? activeFilters.source : [activeFilters.source];
        const txSource = tx.source?.trim().toLowerCase() ?? '';
        const matches = sourceValues.some((source) => txSource === source.trim().toLowerCase());
        if (!matches) return false;
      }
      
      // Purchased by filter
      if (activeFilters.purchasedBy && activeFilters.purchasedBy !== 'all') {
        const purchasedByValues = Array.isArray(activeFilters.purchasedBy)
          ? activeFilters.purchasedBy
          : [activeFilters.purchasedBy];
        const txPurchasedBy = (tx.purchasedBy ?? '').trim().toLowerCase();
        const matches = purchasedByValues.some((purchasedBy) => {
          const normalized = String(purchasedBy ?? '').trim().toLowerCase();
          if (normalized === 'missing' || normalized === 'not set') return txPurchasedBy.length === 0;
          if (normalized === 'client-card' || normalized === 'client card' || normalized === 'client') {
            return txPurchasedBy === 'client-card' || txPurchasedBy.includes('client');
          }
          if (normalized === 'design-business' || normalized === 'design business') {
            return txPurchasedBy === 'design-business' || txPurchasedBy.includes('design');
          }
          return false;
        });
        if (!matches) return false;
      }
      
      return true;
    });

    const sorted = [...filteredByFilters].sort((a, b) => {
      if (sortMode === 'source-asc' || sortMode === 'source-desc') {
        const order = sortMode === 'source-asc' ? 1 : -1;
        const aSource = (a.label ?? '').toLowerCase();
        const bSource = (b.label ?? '').toLowerCase();
        return order * aSource.localeCompare(bSource);
      }
      if (sortMode === 'amount-desc' || sortMode === 'amount-asc') {
        const order = sortMode === 'amount-asc' ? 1 : -1;
        const aAmount = a.transaction.amountCents ?? 0;
        const bAmount = b.transaction.amountCents ?? 0;
        return order * (aAmount - bAmount);
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

  const toggleSelection = useCallback((id: string) => {
    setSelectedIds((prev) => (prev.includes(id) ? prev.filter((itemId) => itemId !== id) : [...prev, id]));
  }, []);

  const clearSelection = useCallback(() => {
    setSelectedIds([]);
    setBulkSheetOpen(false);
  }, []);

  const handleSelectAll = useCallback(() => {
    if (selectedIds.length === filtered.length) {
      setSelectedIds([]);
    } else {
      setSelectedIds(filtered.map((row) => row.id));
    }
  }, [filtered, selectedIds.length]);

  const hasFiltered = filtered.length > 0;
  const allSelected = selectedIds.length === filtered.length && hasFiltered;

  const handleToggleSort = useCallback(() => {
    setSortOpen(true);
  }, []);

  const sortMenuItems: AnchoredMenuItem[] = useMemo(() => {
    const getDateSubactionKey = () => {
      if (sortMode === 'date-desc' || sortMode === 'date-asc') {
        return sortMode;
      }
      return 'date-desc';
    };
    const getCreatedSubactionKey = () => {
      if (sortMode === 'created-desc' || sortMode === 'created-asc') {
        return sortMode;
      }
      return 'created-desc';
    };
    const getSourceSubactionKey = () => {
      if (sortMode === 'source-asc' || sortMode === 'source-desc') {
        return sortMode;
      }
      return 'source-asc';
    };
    const getAmountSubactionKey = () => {
      if (sortMode === 'amount-asc' || sortMode === 'amount-desc') {
        return sortMode;
      }
      return 'amount-desc';
    };
    return [
      {
        key: 'purchase-date',
        label: 'Purchase Date',
        selectedSubactionKey: getDateSubactionKey(),
        defaultSelectedSubactionKey: 'date-desc',
        suppressDefaultCheckmark: true,
        subactions: [
          {
            key: 'date-desc',
            label: 'Newest First',
            onPress: () => setSort('date-desc'),
          },
          {
            key: 'date-asc',
            label: 'Oldest First',
            onPress: () => setSort('date-asc'),
          },
        ],
      },
      {
        key: 'created-date',
        label: 'Created Date',
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
        key: 'source',
        label: 'Source',
        selectedSubactionKey: getSourceSubactionKey(),
        defaultSelectedSubactionKey: 'source-asc',
        suppressDefaultCheckmark: true,
        subactions: [
          {
            key: 'source-asc',
            label: 'A→Z',
            onPress: () => setSort('source-asc'),
          },
          {
            key: 'source-desc',
            label: 'Z→A',
            onPress: () => setSort('source-desc'),
          },
        ],
      },
      {
        key: 'price',
        label: 'Price',
        selectedSubactionKey: getAmountSubactionKey(),
        defaultSelectedSubactionKey: 'amount-desc',
        suppressDefaultCheckmark: true,
        subactions: [
          {
            key: 'amount-desc',
            label: 'High→Low',
            onPress: () => setSort('amount-desc'),
          },
          {
            key: 'amount-asc',
            label: 'Low→High',
            onPress: () => setSort('amount-asc'),
          },
        ],
      },
    ];
  }, [setSort, sortMode]);

  const sourceOptions = useMemo(() => {
    const unique = new Set<string>();
    transactions.forEach((tx) => {
      if (tx.source?.trim()) {
        unique.add(tx.source.trim());
      }
    });
    return Array.from(unique).sort();
  }, [transactions]);

  const filterMenuItems: AnchoredMenuItem[] = useMemo(() => {
    const statusOptions = scopeConfig.capabilities?.supportsInventoryOnlyStatusFilter
      ? ['all', 'pending', 'completed', 'canceled', 'inventory-only'] as const
      : (['all', 'pending', 'completed', 'canceled'] as const);
    const statusLabels: Record<string, string> = {
      all: 'All',
      pending: 'Pending',
      completed: 'Completed',
      canceled: 'Canceled',
      'inventory-only': 'Inventory Only',
    };
    const reimbursementLabels: Record<string, string> = {
      all: 'All',
      'we-owe': 'Owed to Client',
      'client-owes': 'Owed to Design Business',
    };
    const receiptLabels: Record<string, string> = {
      all: 'All',
      yes: 'Yes',
      no: 'No',
    };
    const typeLabels: Record<string, string> = {
      all: 'All',
      purchase: 'Purchase',
      return: 'Return',
    };
    const completenessLabels: Record<string, string> = {
      all: 'All',
      'needs-review': 'Needs Review',
      complete: 'Complete',
    };
    const categoryOptions = Object.entries(budgetCategories).map(([id, cat]) => ({
      key: id,
      label: cat.name,
    }));

    // Helper to normalize filter values to arrays
    const getStatusValues = () => {
      const value = activeFilters.status;
      if (!value || value === 'all') return [];
      return Array.isArray(value) ? value : [value];
    };
    const getReimbursementValues = () => {
      const value = activeFilters.reimbursement;
      if (!value || value === 'all') return [];
      return Array.isArray(value) ? value : [value];
    };
    const getReceiptValues = () => {
      const value = activeFilters.receipt;
      if (!value || value === 'all') return [];
      return Array.isArray(value) ? value : [value];
    };
    const getTypeValues = () => {
      const value = activeFilters.type;
      if (!value || value === 'all') return [];
      return Array.isArray(value) ? value : [value];
    };
    const getCompletenessValues = () => {
      const value = activeFilters.completeness;
      if (!value || value === 'all') return [];
      return Array.isArray(value) ? value : [value];
    };
    const getCategoryValues = () => {
      const value = activeFilters.budgetCategoryId;
      if (!value) return [];
      return Array.isArray(value) ? value : [value];
    };
    const getSourceValues = () => {
      const value = activeFilters.source;
      if (!value) return [];
      return Array.isArray(value) ? value : [value];
    };
    const getPurchasedByValues = () => {
      const value = activeFilters.purchasedBy;
      if (!value || value === 'all') return [];
      return Array.isArray(value) ? value : [value];
    };

    return [
      {
        key: 'status',
        label: 'Status',
        defaultSelectedSubactionKey: 'all',
        suppressDefaultCheckmark: true,
        subactions: statusOptions.map((opt) => {
          const selectedValues = getStatusValues();
          const isSelected = opt === 'all' ? selectedValues.length === 0 : selectedValues.includes(opt as any);
          return {
            key: opt,
            label: statusLabels[opt] ?? opt,
            icon: isSelected && opt !== 'all' ? 'check' : undefined,
            onPress: () => {
              if (opt === 'all') {
                setFilters({ ...activeFilters, status: 'all' });
                return;
              }
              const current = getStatusValues();
              const next = current.includes(opt as any)
                ? current.filter((v) => v !== opt)
                : [...current, opt as any];
              setFilters({ ...activeFilters, status: next.length > 0 ? next : 'all' });
            },
          };
        }),
      },
      {
        key: 'reimbursement',
        label: 'Reimbursement Status',
        defaultSelectedSubactionKey: 'all',
        suppressDefaultCheckmark: true,
        subactions: (['all', 'we-owe', 'client-owes'] as const).map((opt) => {
          const selectedValues = getReimbursementValues();
          const isSelected = opt === 'all' ? selectedValues.length === 0 : selectedValues.includes(opt as any);
          return {
            key: opt,
            label: reimbursementLabels[opt] ?? opt,
            icon: isSelected && opt !== 'all' ? 'check' : undefined,
            onPress: () => {
              if (opt === 'all') {
                setFilters({ ...activeFilters, reimbursement: 'all' });
                return;
              }
              const current = getReimbursementValues();
              const next = current.includes(opt as any)
                ? current.filter((v) => v !== opt)
                : [...current, opt as any];
              setFilters({ ...activeFilters, reimbursement: next.length > 0 ? next : 'all' });
            },
          };
        }),
      },
      {
        key: 'receipt',
        label: 'Email Receipt',
        defaultSelectedSubactionKey: 'all',
        suppressDefaultCheckmark: true,
        subactions: (['all', 'yes', 'no'] as const).map((opt) => {
          const selectedValues = getReceiptValues();
          const isSelected = opt === 'all' ? selectedValues.length === 0 : selectedValues.includes(opt as any);
          return {
            key: opt,
            label: receiptLabels[opt] ?? opt,
            icon: isSelected && opt !== 'all' ? 'check' : undefined,
            onPress: () => {
              if (opt === 'all') {
                setFilters({ ...activeFilters, receipt: 'all' });
                return;
              }
              const current = getReceiptValues();
              const next = current.includes(opt as any)
                ? current.filter((v) => v !== opt)
                : [...current, opt as any];
              setFilters({ ...activeFilters, receipt: next.length > 0 ? next : 'all' });
            },
          };
        }),
      },
      {
        key: 'type',
        label: 'Transaction Type',
        defaultSelectedSubactionKey: 'all',
        suppressDefaultCheckmark: true,
        subactions: (['all', 'purchase', 'return'] as const).map((opt) => {
          const selectedValues = getTypeValues();
          const isSelected = opt === 'all' ? selectedValues.length === 0 : selectedValues.includes(opt as any);
          return {
            key: opt,
            label: typeLabels[opt] ?? opt,
            icon: isSelected && opt !== 'all' ? 'check' : undefined,
            onPress: () => {
              if (opt === 'all') {
                setFilters({ ...activeFilters, type: 'all' });
                return;
              }
              const current = getTypeValues();
              const next = current.includes(opt as any)
                ? current.filter((v) => v !== opt)
                : [...current, opt as any];
              setFilters({ ...activeFilters, type: next.length > 0 ? next : 'all' });
            },
          };
        }),
      },
      {
        key: 'completeness',
        label: 'Completeness',
        defaultSelectedSubactionKey: 'all',
        suppressDefaultCheckmark: true,
        subactions: (['all', 'needs-review', 'complete'] as const).map((opt) => {
          const selectedValues = getCompletenessValues();
          const isSelected = opt === 'all' ? selectedValues.length === 0 : selectedValues.includes(opt as any);
          return {
            key: opt,
            label: completenessLabels[opt] ?? opt,
            icon: isSelected && opt !== 'all' ? 'check' : undefined,
            onPress: () => {
              if (opt === 'all') {
                setFilters({ ...activeFilters, completeness: 'all' });
                return;
              }
              const current = getCompletenessValues();
              const next = current.includes(opt as any)
                ? current.filter((v) => v !== opt)
                : [...current, opt as any];
              setFilters({ ...activeFilters, completeness: next.length > 0 ? next : 'all' });
            },
          };
        }),
      },
      ...(categoryOptions.length > 0
        ? [
            {
              key: 'budget-category',
              label: 'Budget Category',
              defaultSelectedSubactionKey: 'all',
              suppressDefaultCheckmark: true,
              subactions: [
                {
                  key: 'all',
                  label: 'All',
                  icon: undefined,
                  onPress: () => setFilters({ ...activeFilters, budgetCategoryId: undefined }),
                },
                ...categoryOptions.map((opt) => {
                  const selectedValues = getCategoryValues();
                  const isSelected = selectedValues.includes(opt.key);
                  return {
                    key: opt.key,
                    label: opt.label,
                    icon: isSelected ? 'check' : undefined,
                    onPress: () => {
                      const current = getCategoryValues();
                      const next = current.includes(opt.key)
                        ? current.filter((v) => v !== opt.key)
                        : [...current, opt.key];
                      setFilters({ ...activeFilters, budgetCategoryId: next.length > 0 ? next : undefined });
                    },
                  };
                }),
              ],
            },
          ]
        : []),
      {
        key: 'purchased-by',
        label: 'Purchased By',
        defaultSelectedSubactionKey: 'all',
        suppressDefaultCheckmark: true,
        subactions: (['all', 'client-card', 'design-business', 'missing'] as const).map((opt) => {
          const selectedValues = getPurchasedByValues();
          const isSelected = opt === 'all' ? selectedValues.length === 0 : selectedValues.includes(opt as any);
          const label =
            opt === 'client-card' ? 'Client' : opt === 'design-business' ? 'Design Business' : opt === 'missing' ? 'Not Set' : 'All';
          return {
            key: opt,
            label,
            icon: isSelected && opt !== 'all' ? 'check' : undefined,
            onPress: () => {
              if (opt === 'all') {
                setFilters({ ...activeFilters, purchasedBy: 'all' });
                return;
              }
              const current = getPurchasedByValues();
              const next = current.includes(opt as any)
                ? current.filter((v) => v !== opt)
                : [...current, opt as any];
              setFilters({ ...activeFilters, purchasedBy: next.length > 0 ? next : 'all' });
            },
          };
        }),
      },
      ...(sourceOptions.length > 0
        ? [
            {
              key: 'source',
              label: 'Source',
              defaultSelectedSubactionKey: 'all',
              suppressDefaultCheckmark: true,
              subactions: [
                {
                  key: 'all',
                  label: 'All',
                  icon: undefined,
                  onPress: () => setFilters({ ...activeFilters, source: undefined }),
                },
                ...sourceOptions.map((opt) => {
                  const selectedValues = getSourceValues();
                  const isSelected = selectedValues.includes(opt);
                  return {
                    key: opt,
                    label: opt,
                    icon: isSelected ? 'check' : undefined,
                    onPress: () => {
                      const current = getSourceValues();
                      const next = current.includes(opt)
                        ? current.filter((v) => v !== opt)
                        : [...current, opt];
                      setFilters({ ...activeFilters, source: next.length > 0 ? next : undefined });
                    },
                  };
                }),
              ],
            },
          ]
        : []),
    ];
  }, [
    activeFilters,
    budgetCategories,
    sourceOptions,
    scopeConfig.capabilities?.supportsInventoryOnlyStatusFilter,
    setFilters,
  ]);

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

  const addMenuItems: AnchoredMenuItem[] = useMemo(() => {
    const items: AnchoredMenuItem[] = [
      {
        key: 'create-new',
        label: 'Create New',
        icon: 'add-circle-outline',
        onPress: () => {
          setAddMenuVisible(false);
          handleCreateTransaction();
        },
      },
    ];

    if (scopeConfig.scope === 'project' && scopeConfig.projectId) {
      items.push({
        key: 'import-from-invoice',
        label: 'Import from Invoice',
        icon: 'description',
        actionOnly: true,
        subactions: [
          {
            key: 'import-amazon',
            label: 'Amazon',
            onPress: () => {
              setAddMenuVisible(false);
              router.push(`/project/${scopeConfig.projectId}/import-amazon`);
            },
          },
          {
            key: 'import-wayfair',
            label: 'Wayfair',
            onPress: () => {
              setAddMenuVisible(false);
              router.push(`/project/${scopeConfig.projectId}/import-wayfair`);
            },
          },
        ],
      });
    }

    return items;
  }, [handleCreateTransaction, router, scopeConfig.projectId, scopeConfig.scope]);

  const handleExportCsv = useCallback(async (ids?: string[]) => {
    if (!scopeConfig.capabilities?.canExportCsv) return;
    const targetIds = ids && ids.length ? new Set(ids) : null;
    const targetTransactions = targetIds ? transactions.filter((tx) => targetIds.has(tx.id)) : transactions;
    const headers = [
      'id',
      'date',
      'source',
      'amount',
      'categoryName',
      'budgetCategoryId',
      'inventorySaleDirection',
      'itemCategories',
    ];
    const rows = targetTransactions.map((tx) => {
      const categoryName =
        tx.budgetCategoryId && budgetCategories[tx.budgetCategoryId]
          ? budgetCategories[tx.budgetCategoryId].name
          : '';
      const isCanonical = isCanonicalInventorySaleTransaction(tx);
      const itemCategories = isCanonical
        ? ''
        : items
            .filter((item) => item.transactionId === tx.id && item.budgetCategoryId)
            .map((item) => item.budgetCategoryId)
            .filter(Boolean)
            .join('|');
      return [
        tx.id,
        tx.transactionDate ?? '',
        tx.source ?? '',
        typeof tx.amountCents === 'number' ? (tx.amountCents / 100).toFixed(2) : '',
        (categoryName || tx.budgetCategoryId) ?? '',
        tx.budgetCategoryId ?? '',
        tx.inventorySaleDirection ?? '',
        itemCategories,
      ];
    });
    const csv = [headers, ...rows].map((row) => row.map((cell) => `"${String(cell ?? '').replace(/"/g, '""')}"`).join(',')).join('\n');
    await Share.share({ message: csv, title: `${scopeConfig.scope}-transactions.csv` });
  }, [budgetCategories, items, scopeConfig.capabilities?.canExportCsv, scopeConfig.scope, transactions]);

  const selectedTotalCents = useMemo(() => {
    const selectedSet = new Set(selectedIds);
    return filtered.reduce((sum, row) => {
      if (!selectedSet.has(row.id)) return sum;
      return sum + (row.amountCents ?? 0);
    }, 0);
  }, [filtered, selectedIds]);

  const isSortActive = sortMode !== DEFAULT_SORT;
  const isFilterActive = (() => {
    if (activeFilters.status && activeFilters.status !== 'all') {
      const statusValues = Array.isArray(activeFilters.status) ? activeFilters.status : [activeFilters.status];
      if (statusValues.length > 0) return true;
    }
    if (activeFilters.reimbursement && activeFilters.reimbursement !== 'all') {
      const reimbursementValues = Array.isArray(activeFilters.reimbursement)
        ? activeFilters.reimbursement
        : [activeFilters.reimbursement];
      if (reimbursementValues.length > 0) return true;
    }
    if (activeFilters.receipt && activeFilters.receipt !== 'all') {
      const receiptValues = Array.isArray(activeFilters.receipt) ? activeFilters.receipt : [activeFilters.receipt];
      if (receiptValues.length > 0) return true;
    }
    if (activeFilters.type && activeFilters.type !== 'all') {
      const typeValues = Array.isArray(activeFilters.type) ? activeFilters.type : [activeFilters.type];
      if (typeValues.length > 0) return true;
    }
    if (activeFilters.completeness && activeFilters.completeness !== 'all') {
      const completenessValues = Array.isArray(activeFilters.completeness)
        ? activeFilters.completeness
        : [activeFilters.completeness];
      if (completenessValues.length > 0) return true;
    }
    if (activeFilters.budgetCategoryId) {
      const categoryValues = Array.isArray(activeFilters.budgetCategoryId)
        ? activeFilters.budgetCategoryId
        : [activeFilters.budgetCategoryId];
      if (categoryValues.length > 0) return true;
    }
    if (activeFilters.source) {
      const sourceValues = Array.isArray(activeFilters.source) ? activeFilters.source : [activeFilters.source];
      if (sourceValues.length > 0) return true;
    }
    if (activeFilters.purchasedBy && activeFilters.purchasedBy !== 'all') {
      const purchasedByValues = Array.isArray(activeFilters.purchasedBy)
        ? activeFilters.purchasedBy
        : [activeFilters.purchasedBy];
      if (purchasedByValues.length > 0) return true;
    }
    return false;
  })();

  return (
    <>
    <View style={styles.container}>
      <View style={styles.controlSection}>
        <ListControlBar
          search={query}
          onChangeSearch={setQuery}
          showSearch={showSearch}
          actions={[
            {
              title: '',
              variant: 'secondary',
              onPress: () => setShowSearch(!showSearch),
              iconName: 'search',
              active: showSearch,
            },
            {
              title: 'Sort',
              variant: 'secondary',
              onPress: handleToggleSort,
              iconName: 'sort',
              active: isSortActive,
            },
            {
              title: 'Filter',
              variant: 'secondary',
              onPress: () => setFiltersOpen(true),
              iconName: 'filter-list',
              active: isFilterActive,
            },
            { title: 'Add', variant: 'primary', onPress: () => setAddMenuVisible(true), iconName: 'add' },
            ...(scopeConfig.capabilities?.canExportCsv && scopeConfig.scope !== 'project'
              ? [
                  {
                    title: 'Export',
                    variant: 'secondary' as const,
                    onPress: () => {
                      void handleExportCsv();
                    },
                    iconName: 'file-download' as const,
                  },
                ]
              : []),
          ]}
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
      <SortMenu
        visible={sortOpen}
        onRequestClose={() => setSortOpen(false)}
        items={sortMenuItems}
        activeSubactionKey={sortMode}
      />
      <FilterMenu visible={filtersOpen} onRequestClose={() => setFiltersOpen(false)} items={filterMenuItems} />
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
          {scopeConfig.capabilities?.canExportCsv ? (
            <Pressable onPress={() => handleExportCsv(selectedIds)} style={styles.bulkActionButton}>
              <AppText variant="caption" style={primaryTextStyle}>
                Export CSV
              </AppText>
            </Pressable>
          ) : null}
        </View>
      </BottomSheet>
      <FlatList
        style={{ flex: 1 }}
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
          <TransactionCard
            id={item.transaction.id}
            source={item.label}
            amountCents={item.transaction.amountCents ?? null}
            transactionDate={item.transaction.transactionDate}
            notes={item.transaction.notes}
            budgetCategoryName={
              item.transaction.budgetCategoryId
                ? budgetCategories[item.transaction.budgetCategoryId]?.name
                : undefined
            }
            budgetCategoryColor={getBudgetCategoryColor(
              item.transaction.budgetCategoryId,
              budgetCategories
            )}
            transactionType={item.transaction.type as any}
            needsReview={item.transaction.needsReview}
            reimbursementType={item.transaction.reimbursementType as any}
            purchasedBy={item.transaction.purchasedBy}
            hasEmailReceipt={item.transaction.hasEmailReceipt}
            status={item.transaction.status as any}
            selected={selectedIds.includes(item.id)}
            onSelectedChange={() => toggleSelection(item.id)}
            onPress={() => {
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
            menuItems={[
              {
                key: 'edit',
                label: 'Edit',
                onPress: () => {
                  // TODO: Implement edit handler
                },
              },
              {
                key: 'duplicate',
                label: 'Duplicate',
                onPress: () => {
                  // TODO: Implement duplicate handler
                },
              },
              {
                key: 'delete',
                label: 'Delete',
                onPress: () => {
                  // TODO: Implement delete handler
                },
              },
            ]}
          />
        )}
      />
      {selectedIds.length > 0 ? (
        <View style={styles.bulkBar}>
          <View style={styles.bulkBarInfo}>
            <AppText variant="caption" style={styles.semiboldText}>
              {selectedIds.length} selected
            </AppText>
            <AppText variant="caption">
              ${(selectedTotalCents / 100).toFixed(2)}
            </AppText>
          </View>
          <View style={styles.bulkBarSpacer} />
          <View style={styles.bulkBarActions}>
            <AppButton title="Clear" variant="secondary" onPress={clearSelection} />
            <AppButton title="Bulk Actions" variant="primary" onPress={() => setBulkSheetOpen(true)} />
          </View>
        </View>
      ) : null}
    </View>
    <BottomSheetMenuList
      visible={addMenuVisible}
      onRequestClose={() => setAddMenuVisible(false)}
      items={addMenuItems}
      title="Add Transaction"
      showLeadingIcons
    />
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    gap: 16,
  },
  controlSection: {
    gap: 0,
  },
  selectButton: {
    width: 40,
    height: 40,
    borderRadius: BUTTON_BORDER_RADIUS,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  selectButtonDisabled: {
    opacity: 0.5,
  },
  list: {
    paddingBottom: layout.screenBodyTopMd.paddingTop,
    gap: 10,
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 12,
  },
  // row: {
  //   borderWidth: 1,
  //   borderRadius: 12,
  //   paddingVertical: 12,
  //   paddingHorizontal: 14,
  //   flexDirection: 'row',
  //   alignItems: 'center',
  //   gap: 12,
  // },
  // rowPressed: {
  //   opacity: 0.7,
  // },
  // selectorContainer: {
  //   padding: 2,
  // },
  // rowContent: {
  //   flex: 1,
  //   gap: 4,
  // },
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
  bulkActionButton: {
    paddingVertical: 6,
  },
  bulkBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 6,
  },
  bulkBarInfo: {
    gap: 2,
  },
  bulkBarSpacer: {
    flex: 1,
  },
  bulkBarActions: {
    flexDirection: 'row',
    gap: 8,
    alignItems: 'center',
  },
});
