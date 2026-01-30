import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useMemo, useRef, useState } from 'react';
import { Alert, Modal, Pressable, StyleSheet, View, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { getScreenHeaderStyle, SCREEN_PADDING } from '../ui';

import { AppText } from './AppText';

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
  const { width: screenWidth } = useWindowDimensions();

  const menuItemIcon = 'build' as const;
  const menuItemIconColor = uiKitTheme.primary.main;

  const [menuVisible, setMenuVisible] = useState(false);
  const [action1Expanded, setAction1Expanded] = useState(false);
  const [selectedSubaction, setSelectedSubaction] = useState<'subaction-1' | 'subaction-2'>('subaction-1');
  const [menuButtonLayout, setMenuButtonLayout] = useState<{
    x: number;
    y: number;
    width: number;
    height: number;
  } | null>(null);
  const menuButtonRef = useRef<View>(null);

  const closeMenu = useCallback(() => {
    setMenuVisible(false);
    setAction1Expanded(false);
  }, []);

  const selectedSubactionLabel = useMemo(() => {
    return selectedSubaction === 'subaction-1' ? 'Subaction 1' : 'Subaction 2';
  }, [selectedSubaction]);

  const defaultMenuItems = useMemo(() => {
    return [
      {
        key: 'example-action-2',
        label: 'Action 2',
        onPress: () => Alert.alert('Menu action', 'Action 2 pressed'),
      },
      {
        key: 'example-edit',
        label: 'Edit',
        onPress: () => Alert.alert('Menu action', 'Edit pressed'),
      },
      {
        key: 'example-delete',
        label: 'Delete',
        onPress: () => Alert.alert('Menu action', 'Delete pressed'),
      },
    ];
  }, []);

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

      <Modal visible={menuVisible} transparent animationType="fade" onRequestClose={closeMenu}>
        <Pressable style={styles.menuOverlay} onPress={closeMenu}>
          {menuButtonLayout && (() => {
            const menuWidth = 220;
            const buttonRightEdge = menuButtonLayout.x + menuButtonLayout.width;
            let menuLeft = buttonRightEdge - menuWidth;
            menuLeft = Math.max(SCREEN_PADDING, Math.min(menuLeft, screenWidth - menuWidth - SCREEN_PADDING));

            return (
              <View
                style={[
                  styles.menuContainer,
                  {
                    backgroundColor: uiKitTheme.background.modal,
                    borderColor: uiKitTheme.border.secondary,
                    top: menuButtonLayout.y + menuButtonLayout.height + 4,
                    left: menuLeft,
                    width: menuWidth,
                  },
                ]}
                onStartShouldSetResponder={() => true}
              >
                {/* Action 1 (inline submenu) */}
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel="Action 1"
                  onPress={() => setAction1Expanded((prev) => !prev)}
                  style={({ pressed }) => [styles.menuSectionHeader, pressed && { opacity: 0.7 }]}
                >
                  <View style={styles.menuItemLeft}>
                    <MaterialIcons name={menuItemIcon} size={20} color={menuItemIconColor} />
                    <AppText variant="body" style={[styles.menuSectionTitle, { color: uiKitTheme.text.primary }]}>
                      Action 1
                    </AppText>
                  </View>
                  <View style={styles.menuSectionRight}>
                    <AppText variant="body" style={[styles.menuSectionValue, { color: uiKitTheme.text.secondary }]}>
                      {selectedSubactionLabel}
                    </AppText>
                    <MaterialIcons
                      name={action1Expanded ? 'expand-more' : 'chevron-right'}
                      size={22}
                      color={uiKitTheme.text.secondary}
                    />
                  </View>
                </Pressable>

                <View style={[styles.menuDivider, { backgroundColor: uiKitTheme.border.secondary }]} />

                {action1Expanded && (
                  <View
                    style={[
                      styles.menuSectionBody,
                      {
                        backgroundColor: uiKitTheme.background.tertiary ?? uiKitTheme.background.surface,
                      },
                    ]}
                  >
                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel="Subaction 1"
                      onPress={() => {
                        setSelectedSubaction('subaction-1');
                        closeMenu();
                        Alert.alert('Menu action', 'Subaction 1 pressed');
                      }}
                      style={({ pressed }) => [styles.submenuItem, pressed && { opacity: 0.7 }]}
                    >
                      <View style={styles.menuItemLeft}>
                        <MaterialIcons name={menuItemIcon} size={20} color={menuItemIconColor} />
                        <AppText variant="body" style={[styles.menuItemText, { color: uiKitTheme.text.primary }]}>
                          Subaction 1
                        </AppText>
                      </View>
                      {selectedSubaction === 'subaction-1' ? (
                        <MaterialIcons name="check" size={20} color={uiKitTheme.text.primary} />
                      ) : (
                        <View />
                      )}
                    </Pressable>

                    <View style={[styles.menuDivider, { backgroundColor: uiKitTheme.border.secondary }]} />

                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel="Subaction 2"
                      onPress={() => {
                        setSelectedSubaction('subaction-2');
                        closeMenu();
                        Alert.alert('Menu action', 'Subaction 2 pressed');
                      }}
                      style={({ pressed }) => [styles.submenuItem, pressed && { opacity: 0.7 }]}
                    >
                      <View style={styles.menuItemLeft}>
                        <MaterialIcons name={menuItemIcon} size={20} color={menuItemIconColor} />
                        <AppText variant="body" style={[styles.menuItemText, { color: uiKitTheme.text.primary }]}>
                          Subaction 2
                        </AppText>
                      </View>
                      {selectedSubaction === 'subaction-2' ? (
                        <MaterialIcons name="check" size={20} color={uiKitTheme.text.primary} />
                      ) : (
                        <View />
                      )}
                    </Pressable>
                  </View>
                )}

                {action1Expanded ? (
                  <View style={[styles.menuDivider, { backgroundColor: uiKitTheme.border.secondary }]} />
                ) : null}

                {defaultMenuItems.map((item, idx) => {
                  const showDivider = idx < defaultMenuItems.length - 1;
                  return (
                    <View key={item.key}>
                      <Pressable
                        accessibilityRole="button"
                        accessibilityLabel={item.label}
                        onPress={() => {
                          closeMenu();
                          item.onPress?.();
                        }}
                        style={({ pressed }) => [styles.menuActionItem, pressed && { opacity: 0.7 }]}
                      >
                        <View style={styles.menuItemLeft}>
                          <MaterialIcons
                            name={item.label === 'Edit' ? 'edit' : item.label === 'Delete' ? 'delete' : menuItemIcon}
                            size={20}
                            color={menuItemIconColor}
                          />
                          <AppText variant="body" style={[styles.menuItemText, { color: uiKitTheme.text.primary }]}>
                            {item.label}
                          </AppText>
                        </View>
                      </Pressable>
                      {showDivider ? (
                        <View style={[styles.menuDivider, { backgroundColor: uiKitTheme.border.secondary }]} />
                      ) : null}
                    </View>
                  );
                })}
              </View>
            );
          })()}
        </Pressable>
      </Modal>
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
  menuOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.1)',
  },
  menuContainer: {
    position: 'absolute',
    borderRadius: 8,
    borderWidth: 1,
    minWidth: 220,
    maxWidth: 280,
    shadowOpacity: 0.2,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 4 },
    elevation: 5,
    overflow: 'hidden',
  },
  menuSectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  menuSectionTitle: {
    fontSize: 14,
    fontWeight: '600',
  },
  menuSectionRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginLeft: 12,
  },
  menuSectionValue: {
    fontSize: 12,
    fontWeight: '500',
  },
  menuSectionBody: {
    paddingBottom: 8,
    paddingTop: 8,
  },
  submenuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 10,
    paddingLeft: 28,
  },
  menuActionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  menuItemLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  menuItemText: {
    fontSize: 14,
    fontWeight: '500',
  },
  menuDivider: {
    height: 1,
    opacity: 0.6,
  },
});
