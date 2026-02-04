import { StyleSheet, View, ScrollView, RefreshControl } from 'react-native';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useLocalSearchParams, usePathname } from 'expo-router';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Screen, useScreenRefresh } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { useScreenTabs } from '../../src/components/ScreenTabs';
import { layout, SCREEN_PADDING } from '../../src/ui';
import { SharedItemsList } from '../../src/components/SharedItemsList';
import { SharedTransactionsList } from '../../src/components/SharedTransactionsList';
import { createInventoryScopeConfig, getListStateKey } from '../../src/data/scopeConfig';
import { useScopeSwitching } from '../../src/data/useScopeSwitching';
import { refreshScopedItems, refreshScopedTransactions } from '../../src/data/scopedListData';
import { useAccountContextStore } from '../../src/auth/accountContextStore';

export default function ScreenTwo() {
  const params = useLocalSearchParams<{ tab?: string }>();
  const [storedTab, setStoredTab] = useState<string | null>(null);
  const accountId = useAccountContextStore((store) => store.accountId);
  const scopeConfig = useMemo(() => createInventoryScopeConfig(), []);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [refreshToken, setRefreshToken] = useState(0);
  const initialTabKey = useMemo(() => {
    const raw = Array.isArray(params.tab) ? params.tab[0] : params.tab;
    if (raw === 'items' || raw === 'transactions' || raw === 'spaces') {
      return raw;
    }
    if (storedTab === 'transactions' || storedTab === 'spaces') {
      return storedTab;
    }
    return 'items';
  }, [params.tab, storedTab]);

  useEffect(() => {
    AsyncStorage.getItem('inventory:last-tab').then((value) => setStoredTab(value));
  }, []);

  const handleRefresh = useCallback(async () => {
    if (!accountId || isRefreshing) return;
    setIsRefreshing(true);
    try {
      await Promise.all([
        refreshScopedItems(accountId, scopeConfig, 'online'),
        refreshScopedTransactions(accountId, scopeConfig, 'online'),
      ]);
      setRefreshToken((prev) => prev + 1);
    } finally {
      setIsRefreshing(false);
    }
  }, [accountId, isRefreshing, scopeConfig]);

  return (
    <Screen
      title="Inventory"
      refreshing={isRefreshing}
      onRefresh={handleRefresh}
      contentStyle={{ paddingTop: SCREEN_PADDING }}
      tabs={[
        { key: 'items', label: 'Items', accessibilityLabel: 'Items tab' },
        { key: 'transactions', label: 'Transactions', accessibilityLabel: 'Transactions tab' },
        { key: 'spaces', label: 'Spaces', accessibilityLabel: 'Spaces tab' },
      ]}
      initialTabKey={initialTabKey}
    >
      <InventoryScreenContent scopeConfig={scopeConfig} refreshToken={refreshToken} />
    </Screen>
  );
}

function InventoryScreenContent({
  scopeConfig,
  refreshToken,
}: {
  scopeConfig: ReturnType<typeof createInventoryScopeConfig>;
  refreshToken: number;
}) {
  const pathname = usePathname();
  const isFocused = pathname === '/screen-two';
  const screenTabs = useScreenTabs();
  const selectedKey = screenTabs?.selectedKey ?? 'items';
  const screenRefresh = useScreenRefresh();
  const refreshControl = screenRefresh ? (
    <RefreshControl refreshing={screenRefresh.refreshing} onRefresh={screenRefresh.onRefresh} />
  ) : undefined;
  useScopeSwitching(scopeConfig, { isActive: isFocused });

  useEffect(() => {
    if (!selectedKey) return;
    void AsyncStorage.setItem('inventory:last-tab', selectedKey);
  }, [selectedKey]);

  if (selectedKey === 'items') {
    const listStateKey = getListStateKey(scopeConfig, 'items');
    if (!listStateKey) {
      return (
        <ScrollView style={styles.scroll} contentContainerStyle={styles.placeholder} refreshControl={refreshControl}>
          <AppText variant="body">Inventory items go here.</AppText>
        </ScrollView>
      );
    }
    return (
      <View style={styles.content}>
        <SharedItemsList scopeConfig={scopeConfig} listStateKey={listStateKey} refreshToken={refreshToken} />
      </View>
    );
  }

  if (selectedKey === 'transactions') {
    const listStateKey = getListStateKey(scopeConfig, 'transactions');
    if (!listStateKey) {
      return (
        <ScrollView style={styles.scroll} contentContainerStyle={styles.placeholder} refreshControl={refreshControl}>
          <AppText variant="body">Inventory transactions go here.</AppText>
        </ScrollView>
      );
    }
    return (
      <View style={styles.content}>
        <SharedTransactionsList
          scopeConfig={scopeConfig}
          listStateKey={listStateKey}
          refreshToken={refreshToken}
        />
      </View>
    );
  }

  return (
    <ScrollView style={styles.scroll} contentContainerStyle={styles.placeholder} refreshControl={refreshControl}>
      <AppText variant="body">Inventory spaces go here.</AppText>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  placeholder: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  content: {
    flex: 1,
    gap: 12,
  },
});
