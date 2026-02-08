import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useMemo, useState } from 'react';
import { Alert, Pressable, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { getScreenHeaderStyle } from '../ui';

import { AppText } from './AppText';
import { AnchoredMenuItem } from './AnchoredMenuList';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import { InfoButton, InfoDialogContent } from './InfoButton';

export interface TopHeaderProps {
  title: string;
  /**
   * Optional subtitle displayed below the title in smaller, lighter text.
   */
  subtitle?: string;
  /**
   * Optional custom handler for the kebab button.
   * If omitted, a default example menu will open.
   */
  onPressMenu?: () => void;
  menuAccessibilityLabel?: string;
  /**
   * Optional handler for back button press.
   * If provided, a back button will be shown on the left side.
   */
  onPressBack?: () => void;
  backAccessibilityLabel?: string;
  /**
   * If true, removes the bottom border from the header.
   */
  hideBottomBorder?: boolean;
  /**
   * Optional info content to display in an info modal.
   * If provided, an info icon will be shown on the left side of the header.
   */
  infoContent?: InfoDialogContent;
  /**
   * Optional right-side actions rendered before the menu button.
   */
  rightActions?: React.ReactNode;
  /**
   * If true, hides the kebab menu button.
   */
  hideMenu?: boolean;
}

export function TopHeader({
  title,
  subtitle,
  onPressMenu,
  menuAccessibilityLabel,
  onPressBack,
  backAccessibilityLabel,
  hideBottomBorder = false,
  infoContent,
  rightActions,
  hideMenu = false,
}: TopHeaderProps) {
  const insets = useSafeAreaInsets();
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();

  const [menuVisible, setMenuVisible] = useState(false);
  const closeMenu = useCallback(() => {
    setMenuVisible(false);
  }, []);

  const menuItems: AnchoredMenuItem[] = useMemo(
    () => [
      {
        key: 'action-1',
        label: 'Action 1',
        defaultSelectedSubactionKey: 'subaction-1',
        subactions: [
          { key: 'subaction-1', label: 'Subaction 1', onPress: () => Alert.alert('Menu action', 'Subaction 1 pressed') },
          { key: 'subaction-2', label: 'Subaction 2', onPress: () => Alert.alert('Menu action', 'Subaction 2 pressed') },
        ],
      },
      { key: 'action-2', label: 'Action 2', onPress: () => Alert.alert('Menu action', 'Action 2 pressed') },
      { key: 'edit', label: 'Edit', onPress: () => Alert.alert('Menu action', 'Edit pressed') },
      { key: 'delete', label: 'Delete', onPress: () => Alert.alert('Menu action', 'Delete pressed') },
    ],
    [],
  );

  const handleDefaultMenuPress = useCallback(() => {
    setMenuVisible(true);
  }, []);

  const handleMenuButtonPress = useCallback(() => {
    if (onPressMenu) {
      onPressMenu();
      return;
    }
    handleDefaultMenuPress();
  }, [handleDefaultMenuPress, onPressMenu]);

  return (
    <>
      <View
        style={[
          styles.header,
          getScreenHeaderStyle(uiKitTheme, insets),
          // Force relative positioning so the header takes up space in the layout flow.
          // This prevents content from sliding under the header and getting clipped.
          styles.headerInFlow,
          // Keep header on chrome layer for clearer separation from screen background.
          { backgroundColor: uiKitTheme.background.chrome },
          hideBottomBorder && styles.headerNoBorder,
        ]}
      >
        <View style={styles.leftButtonOuter}>
          {infoContent ? (
            <InfoButton
              accessibilityLabel="Show info"
              content={infoContent}
              iconColor={uiKitTheme.button.icon.icon ?? theme.colors.textSecondary}
              iconSize={24}
              style={styles.infoButton}
            />
          ) : null}
          {onPressBack ? (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={backAccessibilityLabel ?? 'Go back'}
              hitSlop={10}
              onPress={onPressBack}
              style={styles.backButton}
            >
              <MaterialIcons
                name="arrow-back"
                size={24}
                color={uiKitTheme.button.icon.icon ?? theme.colors.textSecondary}
              />
            </Pressable>
          ) : null}
          {!infoContent && !onPressBack ? <View style={styles.leftSpacer} /> : null}
        </View>
        <View style={styles.titleContainer}>
          <AppText variant="h2" style={styles.title} numberOfLines={1}>
            {title}
          </AppText>
          {subtitle ? (
            <AppText variant="caption" style={styles.subtitle} numberOfLines={1}>
              {subtitle}
            </AppText>
          ) : null}
        </View>

        <View style={styles.rightButtonOuter}>
          {rightActions ? <View style={styles.rightActions}>{rightActions}</View> : null}
          {!hideMenu ? (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={menuAccessibilityLabel ?? 'Open menu'}
              hitSlop={10}
              onPress={handleMenuButtonPress}
              style={styles.menuButton}
            >
              <MaterialIcons
                name="more-vert"
                size={24}
                color={uiKitTheme.button.icon.icon ?? theme.colors.textSecondary}
              />
            </Pressable>
          ) : null}
        </View>
      </View>

      <BottomSheetMenuList
        visible={menuVisible}
        onRequestClose={closeMenu}
        items={menuItems}
        showLeadingIcons={false}
        title={title}
      />
    </>
  );
}

const styles = StyleSheet.create({
  header: {
    justifyContent: 'space-between',
    zIndex: 1, // Ensure header stays above content if there's any overlap
  },
  headerInFlow: {
    position: 'relative',
  },
  headerNoBorder: {
    borderBottomWidth: 0,
  },
  titleContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: {
    textAlign: 'center',
  },
  subtitle: {
    textAlign: 'center',
    opacity: 0.7,
    marginTop: 6,
  },
  leftSpacer: {
    width: 60,
  },
  leftButtonOuter: {
    width: 60,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-start',
    paddingLeft: 4,
    gap: 4,
  },
  infoButton: {
    padding: 12,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 48,
    minHeight: 48,
  },
  backButton: {
    padding: 12,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 48,
    minHeight: 48,
  },
  rightButtonOuter: {
    minWidth: 60,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    paddingRight: 4,
    gap: 4,
  },
  rightActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  menuButton: {
    padding: 12,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 48,
    minHeight: 48,
  },
  headerTransparent: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 10,
    borderBottomWidth: 0,
  },
  headerTransparent: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 10,
    borderBottomWidth: 0,
  },
});
