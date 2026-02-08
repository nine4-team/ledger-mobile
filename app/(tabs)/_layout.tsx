import { Tabs } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { NetworkStatusBanner } from '../../src/components/NetworkStatusBanner';
import { SyncStatusBanner } from '../../src/components/SyncStatusBanner';
import { STATUS_BANNER_HEIGHT } from '../../src/components/StatusBanner';
import { useNetworkStatus } from '../../src/hooks/useNetworkStatus';
import { getTabBarStyle } from '../../src/ui';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';

export default function TabsLayout() {
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const { isOnline, isSlowConnection } = useNetworkStatus();
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
          name="components"
          options={{
            title: 'Components',
            tabBarLabel: 'Components',
            tabBarIcon: ({ color, size }) => (
              <MaterialIcons name="widgets" size={size || 24} color={color} />
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
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
});
