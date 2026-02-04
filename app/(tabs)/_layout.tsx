import { Tabs } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { getTabBarStyle } from '../../src/ui';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';

export default function TabsLayout() {
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: theme.tabBar.activeTint,
        tabBarInactiveTintColor: theme.tabBar.inactiveTint,
        tabBarStyle: [
          getTabBarStyle(uiKitTheme, insets),
          {
            backgroundColor: theme.tabBar.background,
            borderTopWidth: 1,
            borderTopColor: theme.tabBar.border,
          },
        ],
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
        name="screen-three"
        options={{
          title: 'Templates',
          tabBarLabel: 'Templates',
          tabBarIcon: ({ color, size }) => (
            <MaterialIcons name="library-books" size={size || 24} color={color} />
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
  );
}
