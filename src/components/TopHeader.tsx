import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useMemo, useRef, useState } from 'react';
import { Alert, Pressable, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { getScreenHeaderStyle } from '../ui';

import { AppText } from './AppText';
import { AnchoredMenuItem, AnchoredMenuList } from './AnchoredMenuList';

export interface TopHeaderProps {
  title: string;
  /**
   * Optional custom handler for the kebab button.
   * If omitted, a default example menu will open.
   */
  onPressMenu?: () => void;
  menuAccessibilityLabel?: string;
}

export function TopHeader({ title, onPressMenu, menuAccessibilityLabel }: TopHeaderProps) {
  const insets = useSafeAreaInsets();
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();

  const [menuVisible, setMenuVisible] = useState(false);
  const [menuButtonLayout, setMenuButtonLayout] = useState<{
    x: number;
    y: number;
    width: number;
    height: number;
  } | null>(null);
  const menuButtonRef = useRef<View>(null);

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
    menuButtonRef.current?.measureInWindow((x, y, width, height) => {
      setMenuButtonLayout({ x, y, width, height });
      setMenuVisible(true);
    });
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
      <View style={[styles.header, getScreenHeaderStyle(uiKitTheme, insets)]}>
        <View style={styles.leftSpacer} />
        <AppText variant="h2" style={styles.title}>
          {title}
        </AppText>

        <View ref={menuButtonRef} collapsable={false} style={styles.rightButtonOuter}>
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
        </View>
      </View>

      <AnchoredMenuList
        visible={menuVisible}
        anchorLayout={menuButtonLayout}
        onRequestClose={closeMenu}
        items={menuItems}
        showLeadingIcons={false}
      />
    </>
  );
}

const styles = StyleSheet.create({
  header: {
    justifyContent: 'space-between',
  },
  title: {
    flex: 1,
    textAlign: 'center',
  },
  leftSpacer: {
    width: 60,
  },
  rightButtonOuter: {
    width: 60,
    alignItems: 'flex-end',
    justifyContent: 'center',
    paddingRight: 4,
  },
  menuButton: {
    padding: 6,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 32,
    minHeight: 32,
  },
});
