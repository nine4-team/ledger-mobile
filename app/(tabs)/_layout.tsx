import { Tabs, useRouter } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Pressable, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useCallback, useState } from 'react';
import { NetworkStatusBanner } from '../../src/components/NetworkStatusBanner';
import { SyncStatusBanner } from '../../src/components/SyncStatusBanner';
import { STATUS_BANNER_HEIGHT } from '../../src/components/StatusBanner';
import { BottomSheetMenuList } from '../../src/components/BottomSheetMenuList';
import { useNetworkStatus } from '../../src/hooks/useNetworkStatus';
import { getTabBarStyle } from '../../src/ui';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import type { AnchoredMenuItem } from '../../src/components/AnchoredMenuList';

const BRAND_COLOR = '#987e55';

export default function TabsLayout() {
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const router = useRouter();
  const { isOnline, isSlowConnection } = useNetworkStatus();
  const [addMenuVisible, setAddMenuVisible] = useState(false);

  const tabBarStyle = [
    getTabBarStyle(uiKitTheme, insets),
    {
      backgroundColor: theme.tabBar.background,
      borderTopWidth: 1,
      borderTopColor: theme.tabBar.border,
    },
  ];
  const flattenedTabBarStyle = StyleSheet.flatten(tabBarStyle);
  const tabBarHeight = typeof flattenedTabBarStyle?.height === 'number' ? flattenedTabBarStyle.height : 0;
  const networkBannerVisible = !isOnline || isSlowConnection;
  const syncBannerOffset = tabBarHeight + (networkBannerVisible ? STATUS_BANNER_HEIGHT : 0);

  const addMenuItems: AnchoredMenuItem[] = [
    {
      key: 'add-item',
      label: 'Create Item',
      icon: 'add-circle-outline',
      onPress: () => router.push('/items/new'),
    },
    {
      key: 'add-transaction',
      label: 'Create Transaction',
      icon: 'receipt-long',
      onPress: () => router.push('/transactions/new-universal'),
    },
  ];

  const handleAddPress = useCallback(() => {
    setAddMenuVisible(true);
  }, []);

  return (
    <View style={styles.root}>
      <Tabs
        screenOptions={{
          headerShown: false,
          tabBarActiveTintColor: theme.tabBar.activeTint,
          tabBarInactiveTintColor: theme.tabBar.inactiveTint,
          tabBarStyle,
          tabBarItemStyle: {
            flex: 1,
          },
          tabBarLabelStyle: {
            fontSize: 12,
            fontWeight: '500',
          },
          tabBarIconStyle: {
            marginTop: 4,
          },
        }}
      >
        <Tabs.Screen
          name="add"
          options={{
            title: 'Add',
            tabBarLabel: () => null,
            tabBarIconStyle: { marginTop: 14 },
            tabBarIcon: () => (
              <View style={styles.addButton}>
                <MaterialIcons name="add" size={24} color="#FFFFFF" />
              </View>
            ),
            tabBarButton: ({ children }) => (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Add new"
                onPress={handleAddPress}
                style={styles.addTabButton}
              >
                {children}
              </Pressable>
            ),
          }}
        />
        <Tabs.Screen
          name="index"
          options={{
            title: 'Projects',
            tabBarLabel: 'Projects',
            tabBarIcon: ({ color, size }) => (
              <MaterialIcons name="work" size={size || 24} color={color} />
            ),
          }}
        />
        <Tabs.Screen
          name="screen-two"
          options={{
            title: 'Inventory',
            tabBarLabel: 'Inventory',
            tabBarIcon: ({ color, size }) => (
              <MaterialIcons name="inventory" size={size || 24} color={color} />
            ),
          }}
        />
        <Tabs.Screen
          name="settings"
          options={{
            title: 'Settings',
            tabBarLabel: 'Settings',
            tabBarIcon: ({ color, size }) => (
              <MaterialIcons name="settings" size={size || 24} color={color} />
            ),
          }}
        />
      </Tabs>
      <NetworkStatusBanner bottomOffset={tabBarHeight} />
      <SyncStatusBanner bottomOffset={syncBannerOffset} />
      <BottomSheetMenuList
        visible={addMenuVisible}
        onRequestClose={() => setAddMenuVisible(false)}
        items={addMenuItems}
        title="Create New"
        showLeadingIcons
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  addButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: BRAND_COLOR,
    alignItems: 'center',
    justifyContent: 'center',
  },
  addTabButton: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
