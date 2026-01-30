import React, { createContext, useContext, useMemo, useState } from 'react';
import { ScrollView, StyleSheet, Text, TouchableOpacity, View, ViewStyle } from 'react-native';
import { useTheme } from '../theme/ThemeProvider';

export type ScreenTabItem = {
  key: string;
  label: string;
  accessibilityLabel?: string;
};

export const DEFAULT_SCREEN_TABS: ScreenTabItem[] = [
  { key: 'tab-one', label: 'Tab One', accessibilityLabel: 'Tab One' },
  { key: 'tab-two', label: 'Tab Two', accessibilityLabel: 'Tab Two' },
  { key: 'tab-three', label: 'Tab Three', accessibilityLabel: 'Tab Three' },
];

export interface ScreenTabsProps {
  tabs?: ScreenTabItem[];
  initialTabKey?: string;
  value?: string;
  onChange?: (tabKey: string) => void;
  containerStyle?: ViewStyle;
  contentContainerStyle?: ViewStyle;
}

type ScreenTabsContextValue = {
  selectedKey: string;
  setSelectedKey: (tabKey: string) => void;
  tabs: ScreenTabItem[];
};

const ScreenTabsContext = createContext<ScreenTabsContextValue | null>(null);

export function useScreenTabs(): ScreenTabsContextValue | null {
  return useContext(ScreenTabsContext);
}

export function ScreenTabsProvider({
  value,
  children,
}: {
  value: ScreenTabsContextValue;
  children: React.ReactNode;
}) {
  return <ScreenTabsContext.Provider value={value}>{children}</ScreenTabsContext.Provider>;
}

export function ScreenTabs({
  tabs = DEFAULT_SCREEN_TABS,
  initialTabKey,
  value,
  onChange,
  containerStyle,
  contentContainerStyle,
}: ScreenTabsProps) {
  const theme = useTheme();
  const defaultKey = useMemo(() => tabs[0]?.key ?? 'tab-one', [tabs]);
  const [uncontrolledSelectedKey, setUncontrolledSelectedKey] = useState<string>(initialTabKey ?? defaultKey);
  const selectedKey = value ?? uncontrolledSelectedKey;
  const themed = useMemo(
    () =>
      StyleSheet.create({
        container: {
          backgroundColor: theme.colors.background,
          borderBottomColor: theme.colors.border,
        },
        scrollContent: {
          paddingHorizontal: theme.spacing.screenPadding,
          paddingRight: theme.spacing.screenPadding + 16,
        },
        tabSelectedBorder: {
          borderBottomColor: theme.tabBar.activeTint,
        },
        tabTextSelected: {
          color: theme.tabBar.activeTint,
        },
        tabTextUnselected: {
          color: theme.colors.textSecondary,
        },
      }),
    [theme]
  );

  return (
    <View style={[styles.container, themed.container, containerStyle]}>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        scrollEnabled
        alwaysBounceHorizontal
        bounces
        directionalLockEnabled
        nestedScrollEnabled
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={[styles.scrollContent, themed.scrollContent, contentContainerStyle]}
      >
        {tabs.map((tab) => {
          const isSelected = tab.key === selectedKey;
          return (
            <TouchableOpacity
              key={tab.key}
              style={[styles.tab, isSelected && styles.tabSelected, isSelected && themed.tabSelectedBorder]}
              onPress={() => {
                onChange?.(tab.key);
                if (!value) setUncontrolledSelectedKey(tab.key);
              }}
              activeOpacity={0.7}
              accessibilityRole="tab"
              accessibilityState={{ selected: isSelected }}
              accessibilityLabel={tab.accessibilityLabel ?? tab.label}
            >
              <Text
                style={[
                  styles.tabText,
                  theme.typography.caption,
                  isSelected
                    ? [styles.tabTextSelected, themed.tabTextSelected]
                    : [styles.tabTextUnselected, themed.tabTextUnselected],
                ]}
              >
                {tab.label}
              </Text>
            </TouchableOpacity>
          );
        })}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderBottomWidth: 1,
  },
  scrollContent: {
    flexDirection: 'row',
    // IMPORTANT: keep this wrapping its children, otherwise the content width can
    // incorrectly clamp to the viewport width and prevent horizontal scrolling.
    flexGrow: 0,
  },
  tab: {
    paddingHorizontal: 12,
    paddingTop: 15,
    paddingBottom: 10,
    flexShrink: 0,
    marginRight: 8,
    marginBottom: -1,
    justifyContent: 'center',
    alignItems: 'center',
    borderBottomColor: 'transparent',
    borderBottomWidth: 3,
  },
  tabSelected: {
  },
  tabText: {
  },
  tabTextSelected: {
    fontWeight: '700',
  },
  tabTextUnselected: {
  },
});

