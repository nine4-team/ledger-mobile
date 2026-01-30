import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useRef, useState } from 'react';
import {
  StyleSheet,
  Text,
  Pressable,
  TouchableOpacity,
  View,
  Modal,
  useWindowDimensions,
} from 'react-native';
import type { GestureResponderEvent } from 'react-native';

import { useUIKitTheme } from '../theme/ThemeProvider';
import { CARD_PADDING, getCardBorderStyle, getCardBaseStyle, SCREEN_PADDING } from '../ui';

type MaterialIconName = React.ComponentProps<typeof MaterialIcons>['name'];

export type ExpandableCardMenuSubaction = {
  key: string;
  label: string;
  onPress: () => void;
  icon?: MaterialIconName;
};

export type ExpandableCardMenuItem =
  | {
      key?: string;
      label: string;
      onPress: () => void;
      icon?: MaterialIconName;
    }
  | {
      key?: string;
      label: string;
      subactions: ExpandableCardMenuSubaction[];
      defaultSelectedSubactionKey?: string;
      icon?: MaterialIconName;
    };

export interface ExpandableCardProps {
  title: string;
  expandableRow1?: { label: string; value: string };
  expandableRow2?: { label: string; value: string };
  alwaysShowRow1?: { label: string; value: string };
  alwaysShowRow2?: { label: string; value: string };
  selected?: boolean;
  defaultSelected?: boolean;
  onSelectedChange?: (selected: boolean) => void;
  onMenuPress?: () => void;
  menuItems?: ExpandableCardMenuItem[];
  /**
   * Optional badge label displayed just left of the kebab menu button.
   * Use `menuBadgeEnabled` to toggle visibility without removing the label.
   */
  menuBadgeLabel?: string;
  /**
   * Controls whether the badge is shown. Defaults to false.
   */
  menuBadgeEnabled?: boolean;
}

export function ExpandableCard({
  title,
  expandableRow1,
  expandableRow2,
  alwaysShowRow1,
  alwaysShowRow2,
  selected,
  defaultSelected,
  onSelectedChange,
  onMenuPress,
  menuItems = [],
  menuBadgeLabel,
  menuBadgeEnabled = false,
}: ExpandableCardProps) {
  const uiKitTheme = useUIKitTheme();
  const { width: screenWidth } = useWindowDimensions();
  const [menuVisible, setMenuVisible] = useState(false);
  const [menuButtonLayout, setMenuButtonLayout] = useState<{ x: number; y: number; width: number; height: number } | null>(null);
  const menuButtonRef = useRef<View>(null);
  const [expanded, setExpanded] = useState(false);
  const [internalSelected, setInternalSelected] = useState(Boolean(defaultSelected));
  const [expandedMenuKey, setExpandedMenuKey] = useState<string | null>(null);
  const [selectedSubactionByKey, setSelectedSubactionByKey] = useState<Record<string, string>>({});

  const isSelected = typeof selected === 'boolean' ? selected : internalSelected;

  const closeMenu = useCallback(() => {
    setMenuVisible(false);
    setExpandedMenuKey(null);
  }, []);

  const handleMenuPress = useCallback((e: GestureResponderEvent) => {
    e.stopPropagation();
    if (onMenuPress) {
      onMenuPress();
    } else {
      // Measure button position when opening menu
      menuButtonRef.current?.measureInWindow((x: number, y: number, width: number, height: number) => {
        setMenuButtonLayout({ x, y, width, height });
        setMenuVisible(true);
      });
    }
  }, [onMenuPress]);

  const handleToggleExpand = useCallback((e: GestureResponderEvent) => {
    e.stopPropagation();
    setExpanded((prev) => !prev);
  }, []);

  const handleToggleSelected = useCallback((e: GestureResponderEvent) => {
    e.stopPropagation();
    const next = !isSelected;
    if (typeof selected !== 'boolean') {
      setInternalSelected(next);
    }
    onSelectedChange?.(next);
  }, [isSelected, onSelectedChange, selected]);

  const showMenu = menuItems.length > 0 || onMenuPress;
  const menuItemIconColor = uiKitTheme.primary.main;

  return (
    <>
      <Pressable
        style={({ pressed }) => [
          styles.card,
          getCardBaseStyle({ radius: 16 }),
          getCardBorderStyle(uiKitTheme),
          { 
            backgroundColor: uiKitTheme.background.surface, 
            shadowColor: uiKitTheme.shadow,
            opacity: pressed ? 0.9 : 1,
          },
          isSelected ? { borderColor: uiKitTheme.primary.main } : null,
        ]}
        accessibilityRole="button"
        accessibilityLabel={`Card: ${title}`}
      >
        <View style={styles.cardContent}>
          {/* Top container (always above divider) */}
          <View style={styles.topContainer}>
            {/* Title Row: Title + Expand Control + Kebab Menu */}
            <View style={styles.topRow}>
              <View style={styles.titleRow}>
                <Pressable
                  onPress={handleToggleSelected}
                  style={[
                    styles.selector,
                    { borderColor: isSelected ? uiKitTheme.primary.main : uiKitTheme.border.secondary },
                  ]}
                  accessibilityRole="checkbox"
                  accessibilityLabel={`Select ${title}`}
                  accessibilityState={{ checked: isSelected }}
                  hitSlop={8}
                >
                  {isSelected && (
                    <View style={[styles.selectorInner, { backgroundColor: uiKitTheme.primary.main }]} />
                  )}
                </Pressable>
                <Text
                  style={[styles.title, { color: uiKitTheme.text.primary }]}
                  numberOfLines={1}
                  accessibilityLabel={`Title: ${title}`}
                >
                  {title}
                </Text>
                <TouchableOpacity
                  onPress={handleToggleExpand}
                  style={styles.expandButton}
                  accessibilityRole="button"
                  accessibilityLabel={
                    expanded
                      ? `Hide details for ${title}`
                      : `Show details for ${title}`
                  }
                >
                  <MaterialIcons
                    name={expanded ? 'expand-less' : 'expand-more'}
                    size={22}
                    color={uiKitTheme.text.secondary}
                  />
                </TouchableOpacity>
              </View>
              {showMenu && (
                <View style={styles.menuArea}>
                  {menuBadgeEnabled && menuBadgeLabel ? (
                    <View
                      style={[
                        styles.menuBadge,
                        {
                          backgroundColor:
                            uiKitTheme.background.tertiary ?? uiKitTheme.background.surface,
                          borderColor: uiKitTheme.border.secondary,
                        },
                      ]}
                      accessibilityRole="text"
                      accessibilityLabel={`Badge: ${menuBadgeLabel}`}
                    >
                      <Text
                        style={[styles.menuBadgeText, { color: uiKitTheme.text.secondary }]}
                        numberOfLines={1}
                      >
                        {menuBadgeLabel}
                      </Text>
                    </View>
                  ) : null}
                  <View ref={menuButtonRef} collapsable={false}>
                    <TouchableOpacity
                      onPress={handleMenuPress}
                      style={styles.menuButton}
                      accessibilityRole="button"
                      accessibilityLabel={`More options for ${title}`}
                    >
                      <MaterialIcons name="more-vert" size={20} color={uiKitTheme.button.icon.icon} />
                    </TouchableOpacity>
                  </View>
                </View>
              )}
            </View>

            {/* Expandable rows live in the TOP container (above divider) */}
            {expanded && (
              <View style={styles.expandableRows}>
                {expandableRow1 && (
                  <View style={styles.row}>
                    <Text style={[styles.rowLabel, { color: uiKitTheme.text.secondary }]}>
                      {expandableRow1.label}
                    </Text>
                    <Text style={[styles.rowValue, { color: uiKitTheme.text.primary }]}>
                      {expandableRow1.value}
                    </Text>
                  </View>
                )}
                {expandableRow2 && (
                  <View style={styles.row}>
                    <Text style={[styles.rowLabel, { color: uiKitTheme.text.secondary }]}>
                      {expandableRow2.label}
                    </Text>
                    <Text style={[styles.rowValue, { color: uiKitTheme.text.primary }]}>
                      {expandableRow2.value}
                    </Text>
                  </View>
                )}
              </View>
            )}
          </View>

          {/* Always Showing Rows */}
          <View style={[styles.alwaysShowSection, { borderTopColor: uiKitTheme.border.secondary }]}>
            {alwaysShowRow1 && (
              <View style={styles.row}>
                <Text style={[styles.rowLabel, { color: uiKitTheme.text.secondary }]}>
                  {alwaysShowRow1.label}
                </Text>
                <Text style={[styles.rowValue, { color: uiKitTheme.text.primary }]}>
                  {alwaysShowRow1.value}
                </Text>
              </View>
            )}
            {alwaysShowRow2 && (
              <View style={styles.row}>
                <Text style={[styles.rowLabel, { color: uiKitTheme.text.secondary }]}>
                  {alwaysShowRow2.label}
                </Text>
                <Text style={[styles.rowValue, { color: uiKitTheme.text.primary }]}>
                  {alwaysShowRow2.value}
                </Text>
              </View>
            )}
          </View>
        </View>
      </Pressable>

      {/* Menu Modal */}
      {showMenu && !onMenuPress && (
        <Modal
          visible={menuVisible}
          transparent={true}
          animationType="fade"
          onRequestClose={closeMenu}
        >
          <Pressable
            style={styles.menuOverlay}
            onPress={closeMenu}
          >
            {menuButtonLayout && (() => {
              const menuWidth = 220;
              const buttonRightEdge = menuButtonLayout.x + menuButtonLayout.width;
              // Align menu's right edge with button's right edge
              let menuLeft = buttonRightEdge - menuWidth;
              // Ensure menu doesn't go off the left or right edge of screen
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
                  {menuItems.map((item, idx) => {
                    const showDivider = idx < menuItems.length - 1;
                    const isSubmenuItem = 'subactions' in item;
                    const itemKey = item.key ?? `${item.label}-${idx}`;

                    if (isSubmenuItem) {
                      const currentKey =
                        selectedSubactionByKey[itemKey] ??
                        item.defaultSelectedSubactionKey ??
                        item.subactions[0]?.key;
                      const currentLabel =
                        item.subactions.find((s) => s.key === currentKey)?.label ?? '';
                      const isExpanded = expandedMenuKey === itemKey;

                      return (
                        <View key={itemKey}>
                          <Pressable
                            accessibilityRole="button"
                            accessibilityLabel={item.label}
                            onPress={() =>
                              setExpandedMenuKey((prev) => (prev === itemKey ? null : itemKey))
                            }
                            style={({ pressed }) => [
                              styles.menuSectionHeader,
                              pressed && { opacity: 0.7 },
                            ]}
                          >
                            <View style={styles.menuItemLeft}>
                              <MaterialIcons
                                name={item.icon ?? 'build'}
                                size={20}
                                color={menuItemIconColor}
                              />
                              <Text style={[styles.menuSectionTitle, { color: uiKitTheme.text.primary }]}>
                                {item.label}
                              </Text>
                            </View>
                            <View style={styles.menuSectionRight}>
                              <Text style={[styles.menuSectionValue, { color: uiKitTheme.text.secondary }]}>
                                {currentLabel}
                              </Text>
                              <MaterialIcons
                                name={isExpanded ? 'expand-more' : 'chevron-right'}
                                size={22}
                                color={uiKitTheme.text.secondary}
                              />
                            </View>
                          </Pressable>

                          <View style={[styles.menuDivider, { backgroundColor: uiKitTheme.border.secondary }]} />

                          {isExpanded ? (
                            <View
                              style={[
                                styles.menuSectionBody,
                                {
                                  backgroundColor:
                                    uiKitTheme.background.tertiary ?? uiKitTheme.background.surface,
                                },
                              ]}
                            >
                              {item.subactions.map((sub, subIdx) => {
                                const showSubDivider = subIdx < item.subactions.length - 1;
                                const selectedSub = currentKey === sub.key;

                                return (
                                  <View key={sub.key}>
                                    <Pressable
                                      accessibilityRole="button"
                                      accessibilityLabel={sub.label}
                                      onPress={() => {
                                        setSelectedSubactionByKey((prev) => ({
                                          ...prev,
                                          [itemKey]: sub.key,
                                        }));
                                        closeMenu();
                                        sub.onPress();
                                      }}
                                      style={({ pressed }) => [
                                        styles.submenuItem,
                                        pressed && { opacity: 0.7 },
                                      ]}
                                    >
                                      <View style={styles.menuItemLeft}>
                                        <MaterialIcons
                                          name={sub.icon ?? item.icon ?? 'build'}
                                          size={20}
                                          color={menuItemIconColor}
                                        />
                                        <Text style={[styles.menuItemText, { color: uiKitTheme.text.primary }]}>
                                          {sub.label}
                                        </Text>
                                      </View>
                                      {selectedSub ? (
                                        <MaterialIcons name="check" size={20} color={uiKitTheme.text.primary} />
                                      ) : (
                                        <View />
                                      )}
                                    </Pressable>
                                    {showSubDivider ? (
                                      <View
                                        style={[
                                          styles.menuDivider,
                                          { backgroundColor: uiKitTheme.border.secondary },
                                        ]}
                                      />
                                    ) : null}
                                  </View>
                                );
                              })}
                            </View>
                          ) : null}

                          {isExpanded ? (
                            <View style={[styles.menuDivider, { backgroundColor: uiKitTheme.border.secondary }]} />
                          ) : null}

                          {showDivider ? (
                            <View style={[styles.menuDivider, { backgroundColor: uiKitTheme.border.secondary }]} />
                          ) : null}
                        </View>
                      );
                    }

                    return (
                      <View key={itemKey}>
                        <Pressable
                          onPress={() => {
                            closeMenu();
                            item.onPress();
                          }}
                          style={({ pressed }) => [styles.menuActionItem, pressed && { opacity: 0.7 }]}
                          accessibilityRole="button"
                          accessibilityLabel={item.label}
                        >
                          <View style={styles.menuItemLeft}>
                            <MaterialIcons
                              name={item.icon ?? (item.label === 'Edit' ? 'edit' : item.label === 'Delete' ? 'delete' : 'build')}
                              size={20}
                              color={menuItemIconColor}
                            />
                            <Text style={[styles.menuItemText, { color: uiKitTheme.text.primary }]}>
                              {item.label}
                            </Text>
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
      )}
    </>
  );
}

const styles = StyleSheet.create({
  card: {
    padding: 0,
    shadowOpacity: 0.05,
    shadowRadius: 6,
    elevation: 2,
  },
  cardContent: {
    gap: 0,
  },
  topContainer: {
    // Anything that can expand/collapse stays above the divider
  },
  topRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: CARD_PADDING,
    gap: 12,
  },
  titleRow: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    minWidth: 0,
  },
  selector: {
    width: 18,
    height: 18,
    borderRadius: 9,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  selectorInner: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
  menuButton: {
    padding: 6,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 32,
    minHeight: 32,
  },
  menuArea: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  menuBadge: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 999,
    borderWidth: 1,
    maxWidth: 120,
  },
  menuBadgeText: {
    fontSize: 12,
    fontWeight: '600',
    includeFontPadding: false,
  },
  title: {
    fontSize: 16,
    fontWeight: '600',
    includeFontPadding: false,
    textAlignVertical: 'center',
    lineHeight: 20,
    flexShrink: 1,
  },
  expandButton: {
    padding: 2,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 28,
    minHeight: 28,
  },
  expandableRows: {
    paddingHorizontal: CARD_PADDING,
    paddingBottom: CARD_PADDING,
    gap: 12,
  },
  alwaysShowSection: {
    padding: CARD_PADDING,
    borderTopWidth: 1,
    gap: 12,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  rowLabel: {
    fontSize: 14,
    fontWeight: '500',
  },
  rowValue: {
    fontSize: 14,
    fontWeight: '500',
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
