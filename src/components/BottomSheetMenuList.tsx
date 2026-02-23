import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';

import type { AnchoredMenuItem } from './AnchoredMenuList';
import { resolveMenuSelection } from './AnchoredMenuList';
import { BottomSheet } from './BottomSheet';
import { AppScrollView } from './AppScrollView';
import { InfoButton } from './InfoButton';

export interface BottomSheetMenuListProps {
  visible: boolean;
  onRequestClose: () => void;
  items: AnchoredMenuItem[];
  title?: string;
  showLeadingIcons?: boolean;
  /**
   * When provided, only the group containing this subaction
   * shows its selected value in the header.
   */
  activeSubactionKey?: string;
  /**
   * When true, hide the header value for default selections.
   */
  hideDefaultLabel?: boolean;
  /**
   * Max height for the sheet content area (excluding the handle).
   * Keeps menus usable on small screens and with long lists.
   */
  maxContentHeight?: number;
  /**
   * If true, subactions will close the sheet when pressed. Defaults to true.
   * Set to false for multi-select filters where users should be able to select multiple options.
   */
  closeOnSubactionPress?: boolean;
  /**
   * If true, top-level actions will close the sheet when pressed. Defaults to true.
   * Set to false for multi-select filters where users should be able to select multiple options.
   */
  closeOnItemPress?: boolean;
}

export function BottomSheetMenuList({
  visible,
  onRequestClose,
  items,
  title,
  showLeadingIcons = false,
  activeSubactionKey,
  hideDefaultLabel = false,
  maxContentHeight = 420,
  closeOnSubactionPress = true,
  closeOnItemPress = true,
}: BottomSheetMenuListProps) {
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const [expandedMenuKey, setExpandedMenuKey] = useState<string | null>(null);
  const [selectedSubactionByKey, setSelectedSubactionByKey] = useState<Record<string, string>>({});

  // Store pending action to execute after modal dismisses
  const pendingActionRef = useRef<(() => void) | null>(null);
  const prevVisibleRef = useRef(visible);

  // Execute pending action after modal unmounts (visible transitions true → false)
  useEffect(() => {
    if (prevVisibleRef.current && !visible && pendingActionRef.current) {
      const action = pendingActionRef.current;
      pendingActionRef.current = null;
      // Wait one frame for native modal teardown to complete
      requestAnimationFrame(action);
    }
    prevVisibleRef.current = visible;
  }, [visible]);

  const menuItemIconColor = uiKitTheme.primary.main;

  const computedItems = useMemo(() => {
    return items.map((item, idx) => ({
      ...item,
      key: item.key ?? `${item.label}-${idx}`,
    }));
  }, [items]);

  return (
    <BottomSheet visible={visible} onRequestClose={onRequestClose}>
      {title ? (
        <View style={[styles.titleRow, { borderBottomColor: uiKitTheme.border.secondary }]}>
          <Text
            style={[
              styles.title,
              {
                color: uiKitTheme.text.primary,
                fontSize: (theme.typography.body?.fontSize ?? styles.title.fontSize ?? 14) + 2,
              },
            ]}
            numberOfLines={1}
          >
            {title}
          </Text>
        </View>
      ) : null}

      <AppScrollView
        style={{ maxHeight: maxContentHeight }}
        contentContainerStyle={styles.content}
        bounces={false}
      >
        {computedItems.map((item, idx) => {
          const showDivider = true;
          const subactions = item.subactions ?? [];
          const isSubmenuItem = subactions.length > 0;
          const itemKey = item.key ?? `${item.label}-${idx}`;

          if (isSubmenuItem) {
            const isActionOnly = item.actionOnly === true;
            const { currentKey, currentLabel, showCheckmark, suppressDefaultCheckmark } = isActionOnly
              ? { currentKey: '', currentLabel: '', showCheckmark: false, suppressDefaultCheckmark: false }
              : resolveMenuSelection({
                  item,
                  itemKey,
                  subactions,
                  selectedSubactionByKey,
                  activeSubactionKey,
                  hideDefaultLabel,
                });
            const isExpanded = expandedMenuKey === itemKey;

            return (
              <View key={itemKey}>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={item.label}
                  onPress={() => setExpandedMenuKey((prev) => (prev === itemKey ? null : itemKey))}
                  style={({ pressed }) => [styles.menuSectionHeader, pressed && { opacity: 0.7 }]}
                >
                  <View style={styles.menuItemLeft}>
                    {showLeadingIcons ? (
                      <MaterialIcons name={item.icon ?? 'build'} size={20} color={menuItemIconColor} />
                    ) : null}
                    <Text
                      style={[
                        styles.menuSectionTitle,
                        { color: !isActionOnly && showCheckmark ? uiKitTheme.primary.main : uiKitTheme.text.primary },
                      ]}
                    >
                      {item.label}
                    </Text>
                    {item.info ? (
                      <InfoButton
                        accessibilityLabel={`About ${item.label}`}
                        content={item.info}
                        iconSize={16}
                        iconColor={uiKitTheme.text.secondary}
                      />
                    ) : null}
                  </View>
                  <View style={styles.menuSectionRight}>
                    {!isActionOnly && currentLabel ? (
                      <Text
                        style={[
                          styles.menuSectionValue,
                          { color: showCheckmark ? uiKitTheme.primary.main : uiKitTheme.text.secondary },
                        ]}
                      >
                        {currentLabel}
                      </Text>
                    ) : null}
                    <MaterialIcons
                      name={isExpanded ? 'expand-more' : 'chevron-right'}
                      size={22}
                      color={uiKitTheme.text.secondary}
                    />
                  </View>
                </Pressable>

                <View style={[styles.menuDivider, { backgroundColor: uiKitTheme.border.secondary }]} />

                {isExpanded ? (
                  <View style={styles.menuSectionBody}>
                    {subactions.map((sub, subIdx) => {
                      const showSubDivider = subIdx < subactions.length - 1;
                      const selectedSub = isActionOnly
                        ? false
                        : closeOnSubactionPress
                          ? currentKey === sub.key
                          : sub.icon === 'check';
                      const isDefaultSelected =
                        selectedSub &&
                        item.defaultSelectedSubactionKey != null &&
                        sub.key === item.defaultSelectedSubactionKey;
                      const allowCheck = !suppressDefaultCheckmark || !isDefaultSelected;
                      const isHighlighted = !isActionOnly && selectedSub && allowCheck;

                      return (
                        <View key={sub.key}>
                          <Pressable
                            accessibilityRole="button"
                            accessibilityLabel={sub.label}
                            onPress={() => {
                              if (!isActionOnly && closeOnSubactionPress) {
                                setSelectedSubactionByKey((prev) => ({
                                  ...prev,
                                  [itemKey]: sub.key,
                                }));
                              }
                              if (closeOnSubactionPress) {
                                // Store action to execute after modal dismisses
                                pendingActionRef.current = sub.onPress;
                                onRequestClose();
                              } else {
                                // Execute immediately if not closing
                                sub.onPress();
                              }
                            }}
                            style={({ pressed }) => [styles.submenuItem, pressed && { opacity: 0.7 }]}
                          >
                            <View style={styles.menuItemLeft}>
                              {showLeadingIcons ? (
                                <MaterialIcons
                                  name={sub.icon ?? item.icon ?? 'build'}
                                  size={20}
                                  color={isHighlighted ? uiKitTheme.primary.main : menuItemIconColor}
                                />
                              ) : null}
                              <Text
                                style={[
                                  styles.menuItemText,
                                  { color: isHighlighted ? uiKitTheme.primary.main : uiKitTheme.text.primary },
                                ]}
                              >
                                {sub.label}
                              </Text>
                            </View>
                            {isHighlighted ? (
                              <MaterialIcons name="check" size={20} color={uiKitTheme.primary.main} />
                            ) : (
                              <View />
                            )}
                          </Pressable>
                          {showSubDivider ? (
                            <View style={[styles.menuDivider, { backgroundColor: uiKitTheme.border.secondary }]} />
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
                  if (closeOnItemPress) {
                    // Store action to execute after modal dismisses
                    pendingActionRef.current = item.onPress ?? null;
                    onRequestClose();
                  } else {
                    // Execute immediately if not closing
                    item.onPress?.();
                  }
                }}
                style={({ pressed }) => [styles.menuActionItem, pressed && { opacity: 0.7 }]}
                accessibilityRole="button"
                accessibilityLabel={item.label}
              >
                <View style={styles.menuItemLeft}>
                  {showLeadingIcons ? (
                    <MaterialIcons
                      name={item.icon ?? (item.label === 'Edit' ? 'edit' : item.label === 'Delete' ? 'delete' : 'build')}
                      size={20}
                      color={menuItemIconColor}
                    />
                  ) : null}
                  <Text
                    style={[
                      styles.menuItemText,
                      {
                        color:
                          !showLeadingIcons && item.icon === 'check'
                            ? uiKitTheme.primary.main
                            : uiKitTheme.text.primary,
                      },
                    ]}
                  >
                    {item.label}
                  </Text>
                </View>
                {!showLeadingIcons && item.icon === 'check' ? (
                  <MaterialIcons name="check" size={20} color={uiKitTheme.primary.main} />
                ) : null}
              </Pressable>
              {showDivider ? (
                <View style={[styles.menuDivider, { backgroundColor: uiKitTheme.border.secondary }]} />
              ) : null}
            </View>
          );
        })}
      </AppScrollView>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  titleRow: {
    paddingHorizontal: 16,
    paddingBottom: 10,
    paddingTop: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  title: {
    fontSize: 14,
    fontWeight: '700',
  },
  content: {
    paddingBottom: 6,
  },
  menuSectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
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
    paddingVertical: 12,
    paddingLeft: 28,
  },
  menuActionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  menuItemLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    flex: 1,
  },
  menuItemText: {
    fontSize: 14,
    fontWeight: '500',
  },
  menuDivider: {
    height: StyleSheet.hairlineWidth,
    opacity: 0.8,
  },
});

