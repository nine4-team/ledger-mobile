import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useState } from 'react';
import { StyleSheet, Text, Pressable, TouchableOpacity, View } from 'react-native';
import type { GestureResponderEvent } from 'react-native';

import { useUIKitTheme } from '../theme/ThemeProvider';
import { CARD_PADDING, getCardBorderStyle, getCardBaseStyle } from '../ui';
import { AnchoredMenuItem, AnchoredMenuSubaction } from './AnchoredMenuList';
import { BottomSheetMenuList } from './BottomSheetMenuList';

export type ExpandableCardMenuSubaction = AnchoredMenuSubaction;
export type ExpandableCardMenuItem = AnchoredMenuItem;

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
  const [menuVisible, setMenuVisible] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [internalSelected, setInternalSelected] = useState(Boolean(defaultSelected));

  const isSelected = typeof selected === 'boolean' ? selected : internalSelected;

  const closeMenu = useCallback(() => {
    setMenuVisible(false);
  }, []);

  const handleMenuPress = useCallback((e: GestureResponderEvent) => {
    e.stopPropagation();
    if (onMenuPress) {
      onMenuPress();
      return;
    }
    setMenuVisible(true);
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
                  <View>
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
        <BottomSheetMenuList
          visible={menuVisible}
          onRequestClose={closeMenu}
          items={menuItems}
          title={title}
        />
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
});
