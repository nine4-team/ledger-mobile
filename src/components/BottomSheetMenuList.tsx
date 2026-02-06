import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';

import type { AnchoredMenuItem } from './AnchoredMenuList';
import { BottomSheet } from './BottomSheet';
import { AppScrollView } from './AppScrollView';

export interface BottomSheetMenuListProps {
  visible: boolean;
  onRequestClose: () => void;
  items: AnchoredMenuItem[];
  title?: string;
  showLeadingIcons?: boolean;
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
  maxContentHeight = 420,
  closeOnSubactionPress = true,
  closeOnItemPress = true,
}: BottomSheetMenuListProps) {
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const [expandedMenuKey, setExpandedMenuKey] = useState<string | null>(null);
  const [selectedSubactionByKey, setSelectedSubactionByKey] = useState<Record<string, string>>({});

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
          const showDivider = idx < computedItems.length - 1;
          const subactions = item.subactions ?? [];
          const isSubmenuItem = subactions.length > 0;
          const itemKey = item.key ?? `${item.label}-${idx}`;

          if (isSubmenuItem) {
            const currentKey =
              selectedSubactionByKey[itemKey] ??
              item.defaultSelectedSubactionKey ??
              subactions[0]?.key;
            const isDefaultSelection =
              item.defaultSelectedSubactionKey != null &&
              currentKey === item.defaultSelectedSubactionKey;
            const showCheckmark = !item.suppressDefaultCheckmark || !isDefaultSelection;
            const currentLabel = subactions.find((s) => s.key === currentKey)?.label ?? '';
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
                    <Text style={[styles.menuSectionTitle, { color: uiKitTheme.text.primary }]}>
                      {item.label}
                    </Text>
                  </View>
                  <View style={styles.menuSectionRight}>
                    {currentLabel ? (
                      <>
                        <Text style={[styles.menuSectionValue, { color: uiKitTheme.primary.main }]}>
                          {currentLabel}
                        </Text>
                        {showCheckmark ? (
                          <MaterialIcons name="check" size={20} color={uiKitTheme.primary.main} />
                        ) : null}
                      </>
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
                  <View
                    style={[
                      styles.menuSectionBody,
                      {
                        backgroundColor: uiKitTheme.background.tertiary ?? uiKitTheme.background.surface,
                      },
                    ]}
                  >
                    {subactions.map((sub, subIdx) => {
                      const showSubDivider = subIdx < subactions.length - 1;
                      const selectedSub = closeOnSubactionPress
                        ? currentKey === sub.key
                        : sub.icon === 'check';
                      const isSelected = sub.icon === 'check';

                      return (
                        <View key={sub.key}>
                          <Pressable
                            accessibilityRole="button"
                            accessibilityLabel={sub.label}
                            onPress={() => {
                              if (closeOnSubactionPress) {
                                setSelectedSubactionByKey((prev) => ({
                                  ...prev,
                                  [itemKey]: sub.key,
                                }));
                              }
                              if (closeOnSubactionPress) {
                                onRequestClose();
                              }
                              sub.onPress();
                            }}
                            style={({ pressed }) => [styles.submenuItem, pressed && { opacity: 0.7 }]}
                          >
                            <View style={styles.menuItemLeft}>
                              {showLeadingIcons ? (
                                <MaterialIcons
                                  name={sub.icon === 'check' ? 'check' : item.icon ?? 'build'}
                                  size={20}
                                  color={sub.icon === 'check' ? uiKitTheme.primary.main : menuItemIconColor}
                                />
                              ) : null}
                              <Text
                                style={[
                                  styles.menuItemText,
                                  { color: isSelected ? uiKitTheme.primary.main : uiKitTheme.text.primary },
                                ]}
                              >
                                {sub.label}
                              </Text>
                            </View>
                            {isSelected ? (
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
                  onRequestClose();
                }
                  item.onPress?.();
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

