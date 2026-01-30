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
          title: 'Components',
          tabBarLabel: 'Components',
          tabBarIcon: ({ color, size }) => (
            <MaterialIcons name="widgets" size={size || 24} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="screen-two"
        options={{
          title: 'Screen Two',
          tabBarLabel: 'Screen Two',
          tabBarIcon: ({ color, size }) => (
            <MaterialIcons name="looks-two" size={size || 24} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="screen-three"
        options={{
          title: 'Screen Three',
          tabBarLabel: 'Screen Three',
          tabBarIcon: ({ color, size }) => (
            <MaterialIcons name="looks-3" size={size || 24} color={color} />
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
