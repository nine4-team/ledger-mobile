import React, { useMemo, useState } from 'react';
import { StyleSheet, View, ViewStyle } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { getScreenContainerStyle, SCREEN_PADDING } from '../ui';
import { appTokens } from '../ui/tokens';
import { TopHeader } from './TopHeader';
import { DEFAULT_SCREEN_TABS, ScreenTabItem, ScreenTabs, ScreenTabsProvider } from './ScreenTabs';

interface ScreenProps {
  children: React.ReactNode;
  /**
   * Back-compat: this styles the padded content area (not the outer container).
   */
  style?: ViewStyle;
  containerStyle?: ViewStyle;
  contentStyle?: ViewStyle;
  title?: string;
  onPressMenu?: () => void;
  tabs?: ScreenTabItem[];
  initialTabKey?: string;
  /**
   * Optional content rendered between the primary ScreenTabs and the padded content container.
   * Useful for secondary tab bars that should not live inside the screen content area.
   */
  renderBelowTabs?: (args: {
    selectedKey: string;
    setSelectedKey: (tabKey: string) => void;
    tabs: ScreenTabItem[];
  }) => React.ReactNode;
}

export const Screen: React.FC<ScreenProps> = ({
  children,
  style,
  containerStyle,
  contentStyle,
  title,
  onPressMenu,
  tabs,
  initialTabKey,
  renderBelowTabs,
}) => {
  const insets = useSafeAreaInsets();
  const uiKitTheme = useUIKitTheme();
  const resolvedTabs = useMemo(() => tabs ?? DEFAULT_SCREEN_TABS, [tabs]);
  const defaultKey = useMemo(() => resolvedTabs[0]?.key ?? 'tab-one', [resolvedTabs]);
  const [selectedKey, setSelectedKey] = useState<string>(initialTabKey ?? defaultKey);

  const content = (
    <View style={[styles.container, getScreenContainerStyle(uiKitTheme), containerStyle]}>
      {title ? <TopHeader title={title} onPressMenu={onPressMenu} /> : null}
      {title ? (
        <ScreenTabs tabs={resolvedTabs} value={selectedKey} onChange={setSelectedKey} initialTabKey={initialTabKey} />
      ) : null}
      {title ? renderBelowTabs?.({ selectedKey, setSelectedKey, tabs: resolvedTabs }) : null}
      <View
        style={[
          styles.content,
          // Local (app-owned) content padding so it can't be overridden by ui-kit defaults.
          {
            paddingHorizontal: SCREEN_PADDING,
            paddingBottom: (appTokens.screen.contentPaddingBottom ?? 0) + insets.bottom,
          },
          style,
          contentStyle,
        ]}
      >
        {children}
      </View>
    </View>
  );

  if (!title) return content;

  return (
    <ScreenTabsProvider value={{ selectedKey, setSelectedKey, tabs: resolvedTabs }}>
      {content}
    </ScreenTabsProvider>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    flex: 1,
    paddingTop: appTokens.screen.contentPaddingTop,
    paddingBottom: appTokens.screen.contentPaddingBottom,
  },
});
