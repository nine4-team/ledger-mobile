import React, { createContext, useContext, useCallback, useMemo, useState } from 'react';
import { StyleSheet, View, ViewStyle } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { getScreenContainerStyle, SCREEN_PADDING } from '../ui';
import { appTokens } from '../ui/tokens';
import { TopHeader } from './TopHeader';
import { ScreenTabItem, ScreenTabs, ScreenTabsProvider } from './ScreenTabs';
import type { InfoDialogContent } from './InfoButton';

interface ScreenProps {
  children: React.ReactNode;
  /**
   * Back-compat: this styles the padded content area (not the outer container).
   */
  style?: ViewStyle;
  containerStyle?: ViewStyle;
  contentStyle?: ViewStyle;
  title?: string;
  subtitle?: string;
  onPressMenu?: () => void;
  tabs?: ScreenTabItem[];
  initialTabKey?: string;
  refreshing?: boolean;
  onRefresh?: () => void;
  /**
   * Optional fallback target for back navigation when there's no navigation history.
   * If not provided and router.canGoBack() is false, back button will not be shown.
   */
  backTarget?: string;
  /**
   * Optional custom handler for back button press.
   * If provided, this will be used instead of the default back navigation logic.
   */
  onPressBack?: () => void;
  /**
   * Optional content rendered between the primary ScreenTabs and the padded content container.
   * Useful for secondary tab bars that should not live inside the screen content area.
   */
  renderBelowTabs?: (args: {
    selectedKey: string;
    setSelectedKey: (tabKey: string) => void;
    tabs: ScreenTabItem[];
  }) => React.ReactNode;
  /**
   * If true, hides the back button even if navigation history exists.
   * Useful for main tab screens that should never show a back button.
   */
  hideBackButton?: boolean;
  /**
   * Optional info content to display in an info modal.
   * If provided, an info icon will be shown on the left side of the header.
   */
  infoContent?: InfoDialogContent;
  /**
   * Optional actions rendered to the right of the title.
   */
  headerRight?: React.ReactNode;
  /**
   * Whether to include safe area bottom inset in the content padding.
   * Defaults to true. Set to false if the screen is inside a bottom tab navigator
   * that already handles the safe area.
   */
  includeBottomInset?: boolean;
}

type ScreenRefreshContextValue = {
  refreshing: boolean;
  onRefresh: () => void;
};

const ScreenRefreshContext = createContext<ScreenRefreshContextValue | null>(null);

export function useScreenRefresh() {
  return useContext(ScreenRefreshContext);
}

export const Screen: React.FC<ScreenProps> = ({
  children,
  style,
  containerStyle,
  contentStyle,
  title,
  subtitle,
  onPressMenu,
  tabs,
  initialTabKey,
  refreshing,
  onRefresh,
  backTarget,
  onPressBack,
  renderBelowTabs,
  hideBackButton = false,
  infoContent,
  headerRight,
  includeBottomInset = true,
}) => {
  const insets = useSafeAreaInsets();
  const uiKitTheme = useUIKitTheme();
  const router = useRouter();
  const resolvedTabs = useMemo(() => tabs ?? [], [tabs]);
  const defaultKey = useMemo(() => resolvedTabs[0]?.key ?? 'tab-one', [resolvedTabs]);
  const [selectedKey, setSelectedKey] = useState<string>(initialTabKey ?? defaultKey);
  const refreshContextValue = useMemo<ScreenRefreshContextValue | null>(() => {
    if (!onRefresh) return null;
    return { refreshing: Boolean(refreshing), onRefresh };
  }, [onRefresh, refreshing]);

  const hasTabs = Boolean(title) && resolvedTabs.length > 0;

  const handleBack = useCallback(() => {
    if (onPressBack) {
      onPressBack();
      return;
    }
    if (router.canGoBack()) {
      router.back();
      return;
    }
    if (backTarget) {
      router.replace(backTarget);
    }
  }, [onPressBack, router, backTarget]);

  const shouldShowBackButton = useMemo(() => {
    if (hideBackButton) return false;
    if (onPressBack) return true;
    if (router.canGoBack()) return true;
    if (backTarget) return true;
    return false;
  }, [hideBackButton, onPressBack, router, backTarget]);

  const contentPaddingTop = (appTokens.screen.contentPaddingTop ?? 0) + (title ? 0 : insets.top);

  const content = (
    <View style={[styles.container, getScreenContainerStyle(uiKitTheme), containerStyle]}>
      {title ? (
        <TopHeader
          title={title}
          subtitle={subtitle}
          onPressMenu={onPressMenu}
          onPressBack={shouldShowBackButton ? handleBack : undefined}
          hideBottomBorder={true}
          infoContent={infoContent}
          rightActions={headerRight}
        />
      ) : null}
      {hasTabs ? (
        <ScreenTabs
          tabs={resolvedTabs}
          value={selectedKey}
          onChange={setSelectedKey}
          initialTabKey={initialTabKey}
          containerStyle={title ? styles.tabsAfterTitle : undefined}
        />
      ) : null}
      {hasTabs ? renderBelowTabs?.({ selectedKey, setSelectedKey, tabs: resolvedTabs }) : null}
      <View
        style={[
          styles.content,
          // Local (app-owned) content padding so it can't be overridden by ui-kit defaults.
          {
            paddingHorizontal: SCREEN_PADDING,
            paddingTop: contentPaddingTop,
            paddingBottom: (appTokens.screen.contentPaddingBottom ?? 0) + (includeBottomInset ? insets.bottom : 0),
          },
          style,
          contentStyle,
        ]}
      >
        {children}
      </View>
    </View>
  );

  const withRefresh = (
    <ScreenRefreshContext.Provider value={refreshContextValue}>
      {content}
    </ScreenRefreshContext.Provider>
  );

  if (!hasTabs) return withRefresh;

  return (
    <ScreenTabsProvider value={{ selectedKey, setSelectedKey, tabs: resolvedTabs }}>
      {withRefresh}
    </ScreenTabsProvider>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    flex: 1,
    paddingBottom: appTokens.screen.contentPaddingBottom,
  },
  tabsAfterTitle: {
    marginTop: -4,
  },
});
