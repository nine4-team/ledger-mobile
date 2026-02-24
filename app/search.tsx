import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { AppText } from '../src/components/AppText';
import { ItemCard } from '../src/components/ItemCard';
import { TransactionCard } from '../src/components/TransactionCard';
import { SpaceCard } from '../src/components/SpaceCard';
import { useAccountContextStore } from '../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../src/theme/ThemeProvider';
import {
  subscribeToAllItems,
  subscribeToAllTransactions,
  subscribeToProjects,
  type ScopedItem,
  type ScopedTransaction,
  type ProjectSummary,
} from '../src/data/scopedListData';
import { subscribeToSpaces, type Space } from '../src/data/spacesService';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../src/data/budgetCategoriesService';
import { getTransactionDisplayName } from '../src/utils/transactionDisplayName';
import { resolveAttachmentUri } from '../src/offline/media';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type SearchTab = 'items' | 'transactions' | 'spaces';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function matchesQuery(query: string, ...fields: (string | null | undefined)[]): boolean {
  const q = query.toLowerCase();
  return fields.some((f) => f?.toLowerCase().includes(q));
}

function formatCents(cents: number | null | undefined): string | undefined {
  if (cents == null) return undefined;
  return `$${(cents / 100).toFixed(2)}`;
}

const AMOUNT_QUERY_PATTERN = /^[0-9\s,().$-]+$/;

/**
 * Amount prefix-range matching ported from legacy web app.
 * Typing "40" matches $40.00–$40.99; "40.0" matches $40.00–$40.09; "40.00" matches exactly.
 */
function getAmountPrefixRange(raw: string): { minCents: number; maxCents: number } | null {
  const t = raw.trim();
  if (!t || !/\d/.test(t) || !AMOUNT_QUERY_PATTERN.test(t) || /[-()]/.test(t)) return null;
  const cleaned = t.replace(/[^\d.]/g, '');
  if (!cleaned) return null;
  const parts = cleaned.split('.');
  if (parts.length > 2) return null;
  const whole = parts[0];
  if (!whole) return null;
  const fractional = parts[1] ?? '';
  const wholeValue = parseInt(whole, 10);
  if (!Number.isFinite(wholeValue)) return null;

  if (!fractional) return { minCents: wholeValue * 100, maxCents: wholeValue * 100 + 99 };
  if (fractional.length === 1) {
    const digit = parseInt(fractional, 10);
    if (!Number.isFinite(digit)) return null;
    return { minCents: wholeValue * 100 + digit * 10, maxCents: wholeValue * 100 + digit * 10 + 9 };
  }
  const cents = Math.round(parseFloat(`${whole}.${fractional}`) * 100);
  if (!Number.isFinite(cents)) return null;
  return { minCents: cents, maxCents: cents };
}

function matchesAmountRange(range: { minCents: number; maxCents: number }, ...amounts: (number | null | undefined)[]): boolean {
  return amounts.some((c) => c != null && c >= range.minCents && c <= range.maxCents);
}

/** Normalize SKU to alphanumeric for fuzzy matching (e.g. "ABC-123" matches "abc123") */
const normalizeAlphanumeric = (v: string) => v.replace(/[^a-z0-9]/g, '');

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export default function SearchScreen() {
  const router = useRouter();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const insets = useSafeAreaInsets();
  const accountId = useAccountContextStore((store) => store.accountId);
  const inputRef = useRef<TextInput>(null);

  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [activeTab, setActiveTab] = useState<SearchTab>('items');

  // Data state
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [transactions, setTransactions] = useState<ScopedTransaction[]>([]);
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [allSpaces, setAllSpaces] = useState<Space[]>([]);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string; metadata?: any }>>({});

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedQuery(query), 300);
    return () => clearTimeout(timer);
  }, [query]);

  // Auto-focus search input
  useEffect(() => {
    const timer = setTimeout(() => inputRef.current?.focus(), 100);
    return () => clearTimeout(timer);
  }, []);

  // Subscribe to ALL items across inventory + projects
  useEffect(() => {
    if (!accountId) return;
    return subscribeToAllItems(accountId, setItems);
  }, [accountId]);

  // Subscribe to ALL transactions across inventory + projects
  useEffect(() => {
    if (!accountId) return;
    return subscribeToAllTransactions(accountId, setTransactions);
  }, [accountId]);

  // Subscribe to projects
  useEffect(() => {
    if (!accountId) return;
    return subscribeToProjects(accountId, setProjects);
  }, [accountId]);

  // Subscribe to spaces from all projects
  useEffect(() => {
    if (!accountId || projects.length === 0) return;
    const unsubs: (() => void)[] = [];
    const spacesByProject: Record<string, Space[]> = {};

    for (const project of projects) {
      const unsub = subscribeToSpaces(accountId, project.id, (spaces) => {
        spacesByProject[project.id] = spaces;
        setAllSpaces(Object.values(spacesByProject).flat());
      });
      unsubs.push(unsub);
    }

    return () => unsubs.forEach((fn) => fn());
  }, [accountId, projects]);

  // Subscribe to budget categories
  useEffect(() => {
    if (!accountId) return;
    return subscribeToBudgetCategories(accountId, (next) => setBudgetCategories(mapBudgetCategories(next)));
  }, [accountId]);

  // ---------------------------------------------------------------------------
  // Filtered results
  // ---------------------------------------------------------------------------

  const filteredItems = useMemo(() => {
    const q = debouncedQuery.trim();
    if (!q) return [];
    const amountRange = getAmountPrefixRange(q);
    const qLower = q.toLowerCase();
    const normalizedSkuQuery = normalizeAlphanumeric(qLower);

    return items.filter((item) => {
      // Text match: name, source, sku (exact + normalized), notes, budget category name
      const matchesText =
        matchesQuery(q, item.name, item.source, item.sku, item.notes,
          item.budgetCategoryId ? budgetCategories[item.budgetCategoryId]?.name : undefined) ||
        (normalizedSkuQuery && item.sku
          ? normalizeAlphanumeric(item.sku.toLowerCase()).includes(normalizedSkuQuery)
          : false);

      // Amount match: all price fields
      const matchesAmount = amountRange
        ? matchesAmountRange(amountRange, item.purchasePriceCents, item.projectPriceCents, item.marketValueCents)
        : false;

      return matchesText || matchesAmount;
    });
  }, [items, debouncedQuery, budgetCategories]);

  const filteredTransactions = useMemo(() => {
    const q = debouncedQuery.trim();
    if (!q) return [];
    const amountRange = getAmountPrefixRange(q);

    return transactions.filter((tx) => {
      // Text match: display name (handles canonical inventory sales), type, notes, purchasedBy, budget category
      const displayName = getTransactionDisplayName({
        source: tx.source,
        id: tx.id,
        isCanonicalInventorySale: tx.isCanonicalInventorySale,
        inventorySaleDirection: tx.inventorySaleDirection,
      });
      const matchesText = matchesQuery(q, displayName, tx.transactionType, tx.notes, tx.purchasedBy,
        tx.budgetCategoryId ? budgetCategories[tx.budgetCategoryId]?.name : undefined);

      // Amount match
      const matchesAmount = amountRange
        ? matchesAmountRange(amountRange, tx.amountCents)
        : false;

      return matchesText || matchesAmount;
    });
  }, [transactions, debouncedQuery, budgetCategories]);

  const filteredSpaces = useMemo(() => {
    if (!debouncedQuery.trim()) return [];
    return allSpaces.filter((space) =>
      matchesQuery(debouncedQuery, space.name, space.notes),
    );
  }, [allSpaces, debouncedQuery]);

  // ---------------------------------------------------------------------------
  // Tab badge counts
  // ---------------------------------------------------------------------------

  const itemCount = filteredItems.length;
  const txCount = filteredTransactions.length;
  const spaceCount = filteredSpaces.length;

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  const handleItemPress = useCallback(
    (id: string) => {
      router.push({
        pathname: '/items/[id]',
        params: { id, backTarget: '/search' },
      });
    },
    [router],
  );

  const handleTransactionPress = useCallback(
    (tx: ScopedTransaction) => {
      router.push({
        pathname: '/transactions/[id]',
        params: {
          id: tx.id,
          scope: tx.projectId ? 'project' : 'inventory',
          projectId: tx.projectId ?? '',
          backTarget: '/search',
        },
      });
    },
    [router],
  );

  const handleSpacePress = useCallback(
    (space: Space) => {
      if (space.projectId) {
        router.push(`/project/${space.projectId}/space/${space.id}` as any);
      }
    },
    [router],
  );

  // ---------------------------------------------------------------------------
  // Project name map (for space labels)
  // ---------------------------------------------------------------------------

  const projectNameMap = useMemo(() => {
    const map: Record<string, string> = {};
    for (const p of projects) {
      map[p.id] = p.name ?? 'Untitled';
    }
    return map;
  }, [projects]);

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  const tabs: { key: SearchTab; label: string; count: number }[] = [
    { key: 'items', label: 'Items', count: itemCount },
    { key: 'transactions', label: 'Transactions', count: txCount },
    { key: 'spaces', label: 'Spaces', count: spaceCount },
  ];

  return (
    <View style={[styles.root, { backgroundColor: uiKitTheme.background.screen }]}>
      {/* Header with search bar */}
      <View style={[styles.header, { paddingTop: insets.top + 8, backgroundColor: uiKitTheme.background.chrome, borderBottomColor: uiKitTheme.border.secondary }]}>
        <View style={styles.searchRow}>
          <View style={[styles.searchInputContainer, { backgroundColor: uiKitTheme.background.surface, borderColor: uiKitTheme.border.secondary }]}>
            <MaterialIcons name="search" size={20} color={theme.colors.textSecondary} />
            <TextInput
              ref={inputRef}
              value={query}
              onChangeText={setQuery}
              placeholder="Search items, transactions, spaces..."
              placeholderTextColor={theme.colors.textSecondary}
              style={[styles.searchInput, { color: theme.colors.text }]}
              returnKeyType="search"
              autoCorrect={false}
              autoCapitalize="none"
            />
            {query.length > 0 && (
              <Pressable onPress={() => setQuery('')} hitSlop={10}>
                <MaterialIcons name="close" size={18} color={theme.colors.textSecondary} />
              </Pressable>
            )}
          </View>
          <Pressable onPress={() => router.back()} hitSlop={10}>
            <AppText variant="body" style={{ color: theme.colors.primary }}>Cancel</AppText>
          </Pressable>
        </View>

        {/* Tabs */}
        <View style={styles.tabRow}>
          {tabs.map((tab) => {
            const isActive = activeTab === tab.key;
            return (
              <Pressable
                key={tab.key}
                onPress={() => setActiveTab(tab.key)}
                style={[
                  styles.tab,
                  isActive && { borderBottomColor: theme.colors.primary, borderBottomWidth: 2 },
                ]}
              >
                <AppText
                  variant="caption"
                  style={[styles.tabLabel, { color: isActive ? theme.colors.primary : theme.colors.textSecondary }]}
                >
                  {tab.label}
                  {debouncedQuery.trim() ? ` (${tab.count})` : ''}
                </AppText>
              </Pressable>
            );
          })}
        </View>
      </View>

      {/* Results */}
      <View style={styles.content}>
        {!debouncedQuery.trim() ? (
          <View style={styles.emptyState}>
            <MaterialIcons name="search" size={48} color={theme.colors.textSecondary} style={{ opacity: 0.4 }} />
            <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
              Start typing to search
            </AppText>
          </View>
        ) : activeTab === 'items' ? (
          filteredItems.length === 0 ? (
            <EmptyResult label="No items found" />
          ) : (
            <FlatList
              data={filteredItems}
              keyExtractor={(item) => item.id}
              contentContainerStyle={styles.listContent}
              renderItem={({ item }) => {
                const thumbnailUri = item.images?.[0]
                  ? resolveAttachmentUri(item.images[0]) ?? undefined
                  : undefined;
                return (
                  <ItemCard
                    name={item.name ?? 'Unnamed'}
                    sku={item.sku ?? undefined}
                    sourceLabel={item.source ?? undefined}
                    priceLabel={formatCents(item.purchasePriceCents)}
                    statusLabel={item.status ?? undefined}
                    thumbnailUri={thumbnailUri}
                    onPress={() => handleItemPress(item.id)}
                  />
                );
              }}
            />
          )
        ) : activeTab === 'transactions' ? (
          filteredTransactions.length === 0 ? (
            <EmptyResult label="No transactions found" />
          ) : (
            <FlatList
              data={filteredTransactions}
              keyExtractor={(item) => item.id}
              contentContainerStyle={styles.listContent}
              renderItem={({ item }) => (
                <TransactionCard
                  id={item.id}
                  source={getTransactionDisplayName({
                    source: item.source,
                    id: item.id,
                    isCanonicalInventorySale: item.isCanonicalInventorySale,
                    inventorySaleDirection: item.inventorySaleDirection,
                  })}
                  amountCents={item.amountCents ?? null}
                  transactionDate={item.transactionDate ?? undefined}
                  notes={item.notes ?? undefined}
                  budgetCategoryName={
                    item.budgetCategoryId
                      ? budgetCategories[item.budgetCategoryId]?.name
                      : undefined
                  }
                  transactionType={item.transactionType as any}
                  needsReview={item.needsReview ?? undefined}
                  reimbursementType={item.reimbursementType as any}
                  purchasedBy={item.purchasedBy ?? undefined}
                  itemCount={item.itemIds?.length ?? 0}
                  hasEmailReceipt={item.hasEmailReceipt ?? undefined}
                  status={item.status as any}
                  onPress={() => handleTransactionPress(item)}
                />
              )}
            />
          )
        ) : activeTab === 'spaces' ? (
          filteredSpaces.length === 0 ? (
            <EmptyResult label="No spaces found" />
          ) : (
            <FlatList
              data={filteredSpaces}
              keyExtractor={(item) => item.id}
              contentContainerStyle={styles.listContent}
              renderItem={({ item }) => (
                <View>
                  {item.projectId && projectNameMap[item.projectId] ? (
                    <AppText variant="caption" style={[styles.spaceProjectLabel, { color: theme.colors.textSecondary }]}>
                      {projectNameMap[item.projectId]}
                    </AppText>
                  ) : null}
                  <SpaceCard
                    name={item.name}
                    itemCount={0}
                    primaryImage={item.images?.[0] ?? null}
                    checklists={item.checklists}
                    notes={item.notes}
                    onPress={() => handleSpacePress(item)}
                  />
                </View>
              )}
            />
          )
        ) : null}
      </View>
    </View>
  );
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function EmptyResult({ label }: { label: string }) {
  const theme = useTheme();
  return (
    <View style={styles.emptyState}>
      <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
        {label}
      </AppText>
    </View>
  );
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  header: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    gap: 8,
    paddingHorizontal: 16,
    paddingBottom: 0,
  },
  searchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  searchInputContainer: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 10,
    gap: 8,
    height: 40,
  },
  searchInput: {
    flex: 1,
    fontSize: 16,
    paddingVertical: 0,
  },
  tabRow: {
    flexDirection: 'row',
  },
  tab: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 10,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabLabel: {
    fontWeight: '600',
  },
  content: {
    flex: 1,
    paddingHorizontal: 16,
  },
  listContent: {
    paddingTop: 12,
    gap: 10,
    paddingBottom: 24,
  },
  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    paddingBottom: 60,
  },
  spaceProjectLabel: {
    marginBottom: 4,
    fontSize: 11,
    fontWeight: '500',
  },
});
