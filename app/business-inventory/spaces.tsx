import { useCallback, useEffect, useMemo, useState } from 'react';
import { RefreshControl, StyleSheet, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { AppScrollView } from '../../src/components/AppScrollView';
import { Screen } from '../../src/components/Screen';
import { SpaceCard } from '../../src/components/SpaceCard';
import { SpaceCardSkeleton } from '../../src/components/SpaceCardSkeleton';
import { ErrorRetryView } from '../../src/components/ErrorRetryView';
import { SyncIndicator } from '../../src/components/SyncIndicator';
import { NetworkStatusBanner } from '../../src/components/NetworkStatusBanner';
import { useScreenRefresh } from '../../src/components/Screen';
import { layout } from '../../src/ui';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { refreshSpaces, subscribeToSpaces, Space } from '../../src/data/spacesService';
import { getScopeId, createBusinessInventoryScopeConfig } from '../../src/data/scopeConfig';
import { useScopedListenersMultiple } from '../../src/data/useScopedListeners';
import { refreshScopedItems, ScopedItem, subscribeToScopedItems } from '../../src/data/scopedListData';
import { getTextInputStyle } from '../../src/ui/styles/forms';
import { useDebouncedValue } from '../../src/hooks/useDebouncedValue';
import { useNetworkStatus } from '../../src/hooks/useNetworkStatus';

export default function BusinessInventorySpacesScreen() {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [spaces, setSpaces] = useState<Space[]>([]);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [query, setQuery] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const screenRefresh = useScreenRefresh();
  const debouncedQuery = useDebouncedValue(query, 350);
  const networkStatus = useNetworkStatus();

  const scopeConfig = useMemo(() => createBusinessInventoryScopeConfig(), []);
  const scopeId = useMemo(() => getScopeId(scopeConfig), [scopeConfig]);

  useEffect(() => {
    if (!accountId) {
      setSpaces([]);
      setIsLoading(false);
      setError(null);
    }
  }, [accountId]);

  const handleSpacesSubscribe = useCallback(() => {
    if (!accountId) {
      setSpaces([]);
      setIsLoading(false);
      setError(null);
      return () => {};
    }
    setIsLoading(true);
    setError(null);
    return subscribeToSpaces(accountId, null, (next) => {
      setSpaces(next);
      setIsLoading(false);
      setError(null);
    });
  }, [accountId]);

  const handleItemsSubscribe = useCallback(() => {
    if (!accountId) {
      setItems([]);
      return () => {};
    }
    return subscribeToScopedItems(accountId, scopeConfig, (next) => {
      setItems(next);
    });
  }, [accountId, scopeConfig]);

  useScopedListenersMultiple(scopeId, [handleSpacesSubscribe, handleItemsSubscribe]);

  const handleRetry = useCallback(() => {
    if (!accountId) return;
    setError(null);
    setIsLoading(true);
    refreshSpaces(accountId, null, 'online')
      .then(() => {
        setError(null);
      })
      .catch((err) => {
        setError(err instanceof Error ? err.message : 'Failed to load spaces');
        setIsLoading(false);
      });
    void refreshScopedItems(accountId, scopeConfig, 'online');
  }, [accountId, scopeConfig]);

  useEffect(() => {
    if (!accountId || screenRefresh?.refreshToken == null) return;
    void refreshSpaces(accountId, null, 'online').catch((err) => {
      setError(err instanceof Error ? err.message : 'Failed to load spaces');
    });
    void refreshScopedItems(accountId, scopeConfig, 'online');
  }, [accountId, screenRefresh?.refreshToken, scopeConfig]);

  const filteredSpaces = useMemo(() => {
    const needle = debouncedQuery.trim().toLowerCase();
    if (!needle) return spaces;
    return spaces.filter((space) => {
      const name = space.name?.toLowerCase() ?? '';
      const notes = space.notes?.toLowerCase() ?? '';
      return name.includes(needle) || notes.includes(needle);
    });
  }, [debouncedQuery, spaces]);

  const itemCountsBySpace = useMemo(() => {
    const counts: Record<string, number> = {};
    items.forEach((item) => {
      if (!item.spaceId) return;
      counts[item.spaceId] = (counts[item.spaceId] ?? 0) + 1;
    });
    return counts;
  }, [items]);

  const gridItems = useMemo(() => {
    return filteredSpaces.map((space) => {
      const primaryImage = space.images?.find((img) => img.isPrimary) ?? space.images?.[0] ?? null;
      return {
        id: space.id,
        name: space.name,
        itemCount: itemCountsBySpace[space.id] ?? 0,
        primaryImage,
        checklists: space.checklists ?? null,
      };
    });
  }, [filteredSpaces, itemCountsBySpace]);

  const handleSpacePress = useCallback(
    (spaceId: string) => {
      router.push(`/business-inventory/spaces/${spaceId}`);
    },
    [router]
  );

  const handleAddSpace = useCallback(() => {
    router.push('/business-inventory/spaces/new');
  }, [router]);

  return (
    <Screen title="Business Inventory Spaces">
      <AppScrollView
        style={styles.scroll}
        contentContainerStyle={[styles.container, styles.scrollContent]}
        refreshControl={
          screenRefresh ? (
            <RefreshControl refreshing={screenRefresh.refreshing} onRefresh={screenRefresh.onRefresh} />
          ) : undefined
        }
      >
        <View style={styles.header}>
          <AppText variant="body" style={styles.title}>
            Spaces
          </AppText>
          <SyncIndicator />
        </View>
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Search spaces"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
          accessibilityLabel="Search spaces"
          accessibilityHint="Type to filter spaces by name or notes"
          returnKeyType="search"
        />
        <View style={styles.actions}>
          <AppButton
            title="Add space"
            onPress={handleAddSpace}
            accessibilityLabel="Add new space"
            accessibilityHint="Tap to create a new space"
          />
        </View>

        {error ? (
          <ErrorRetryView
            message={error}
            onRetry={handleRetry}
            isOffline={!networkStatus.isOnline}
          />
        ) : isLoading ? (
          <View style={styles.list}>
            {Array.from({ length: 4 }).map((_, index) => (
              <SpaceCardSkeleton key={index} />
            ))}
          </View>
        ) : filteredSpaces.length === 0 ? (
          <View style={styles.emptyState}>
            <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
              {query.trim() ? 'No spaces found.' : 'No spaces yet.'}
            </AppText>
            {!query.trim() && (
              <AppText variant="caption" style={{ color: theme.colors.textSecondary, textAlign: 'center' }}>
                Create your first space to organize inventory items by location
              </AppText>
            )}
          </View>
        ) : (
          <View style={styles.list}>
            {gridItems.map((item) => (
              <SpaceCard
                key={item.id}
                name={item.name}
                itemCount={item.itemCount}
                primaryImage={item.primaryImage}
                checklists={item.checklists}
                onPress={() => handleSpacePress(item.id)}
              />
            ))}
          </View>
        )}
      </AppScrollView>

      {!networkStatus.isOnline && <NetworkStatusBanner />}
    </Screen>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  scrollContent: {
    flexGrow: 1,
    paddingBottom: 24,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  title: {
    fontWeight: '600',
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
  list: {
    gap: 12,
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 32,
    gap: 8,
  },
});
