import { StyleSheet, View } from 'react-native';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useIsFocused } from '@react-navigation/native';
import { useLocalSearchParams } from 'expo-router';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { useScreenTabs } from '../../src/components/ScreenTabs';
import { layout } from '../../src/ui';
import { SharedItemsList } from '../../src/components/SharedItemsList';
import { SharedTransactionsList } from '../../src/components/SharedTransactionsList';
import { createInventoryScopeConfig, getListStateKey } from '../../src/data/scopeConfig';
import { useScopeSwitching } from '../../src/data/useScopeSwitching';
import { refreshScopedItems, refreshScopedTransactions } from '../../src/data/scopedListData';
import { useAccountContextStore } from '../../src/auth/accountContextStore';

export default function ScreenTwo() {
  const params = useLocalSearchParams<{ tab?: string }>();
  const [storedTab, setStoredTab] = useState<string | null>(null);
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

  return (
    <Screen
      title="Inventory"
      tabs={[
        { key: 'items', label: 'Items', accessibilityLabel: 'Items tab' },
        { key: 'transactions', label: 'Transactions', accessibilityLabel: 'Transactions tab' },
        { key: 'spaces', label: 'Spaces', accessibilityLabel: 'Spaces tab' },
      ]}
      initialTabKey={initialTabKey}
    >
      <InventoryScreenContent />
    </Screen>
  );
}

function InventoryScreenContent() {
  const accountId = useAccountContextStore((store) => store.accountId);
  const isFocused = useIsFocused();
  const screenTabs = useScreenTabs();
  const selectedKey = screenTabs?.selectedKey ?? 'items';
  const scopeConfig = createInventoryScopeConfig();
  useScopeSwitching(scopeConfig, { isActive: isFocused });
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [refreshToken, setRefreshToken] = useState(0);
  const [refreshError, setRefreshError] = useState<string | null>(null);

  useEffect(() => {
    if (!selectedKey) return;
    void AsyncStorage.setItem('inventory:last-tab', selectedKey);
  }, [selectedKey]);

  const handleRefresh = useCallback(async () => {
    if (!accountId || isRefreshing) return;
    setIsRefreshing(true);
    setRefreshError(null);
    try {
      await Promise.all([
        refreshScopedItems(accountId, scopeConfig, 'online'),
        refreshScopedTransactions(accountId, scopeConfig, 'online'),
      ]);
      setRefreshToken((prev) => prev + 1);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to refresh inventory.';
      setRefreshError(message);
    } finally {
      setIsRefreshing(false);
    }
  }, [accountId, isRefreshing, scopeConfig]);

  const refreshAction = (
    <View style={styles.refreshRow}>
      <AppButton
        title={isRefreshing ? 'Refreshing…' : 'Refresh'}
        variant="secondary"
        onPress={handleRefresh}
        disabled={isRefreshing}
      />
      {refreshError ? (
        <AppText variant="caption" style={styles.refreshError}>
          {refreshError}
        </AppText>
      ) : null}
    </View>
  );

  if (selectedKey === 'items') {
    const listStateKey = getListStateKey(scopeConfig, 'items');
    if (!listStateKey) {
      return (
        <View style={styles.placeholder}>
          <AppText variant="body">Inventory items go here.</AppText>
        </View>
      );
    }
    return (
      <View style={styles.content}>
        {refreshAction}
        <SharedItemsList scopeConfig={scopeConfig} listStateKey={listStateKey} refreshToken={refreshToken} />
      </View>
    );
  }

  if (selectedKey === 'transactions') {
    const listStateKey = getListStateKey(scopeConfig, 'transactions');
    if (!listStateKey) {
      return (
        <View style={styles.placeholder}>
          <AppText variant="body">Inventory transactions go here.</AppText>
        </View>
      );
    }
    return (
      <View style={styles.content}>
        {refreshAction}
        <SharedTransactionsList
          scopeConfig={scopeConfig}
          listStateKey={listStateKey}
          refreshToken={refreshToken}
        />
      </View>
    );
  }

  return (
    <View style={styles.placeholder}>
      <AppText variant="body">Inventory spaces go here.</AppText>
    </View>
  );
}

const styles = StyleSheet.create({
  placeholder: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  content: {
    flex: 1,
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  refreshRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  refreshError: {
    flex: 1,
  },
});
