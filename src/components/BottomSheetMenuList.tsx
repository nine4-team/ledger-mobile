import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { useUIKitTheme } from '../theme/ThemeProvider';

import type { AnchoredMenuItem } from './AnchoredMenuList';
import { BottomSheet } from './BottomSheet';

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
}

export function BottomSheetMenuList({
  visible,
  onRequestClose,
  items,
  title,
  showLeadingIcons = true,
  maxContentHeight = 420,
}: BottomSheetMenuListProps) {
  const uiKitTheme = useUIKitTheme();
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
          <Text style={[styles.title, { color: uiKitTheme.text.primary }]} numberOfLines={1}>
            {title}
          </Text>
        </View>
      ) : null}

      <ScrollView
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
                        backgroundColor: uiKitTheme.background.tertiary ?? uiKitTheme.background.surface,
                      },
                    ]}
                  >
                    {subactions.map((sub, subIdx) => {
                      const showSubDivider = subIdx < subactions.length - 1;
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
                              onRequestClose();
                              sub.onPress();
                            }}
                            style={({ pressed }) => [styles.submenuItem, pressed && { opacity: 0.7 }]}
                          >
                            <View style={styles.menuItemLeft}>
                              {showLeadingIcons ? (
                                <MaterialIcons
                                  name={sub.icon ?? item.icon ?? 'build'}
                                  size={20}
                                  color={menuItemIconColor}
                                />
                              ) : null}
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
                  onRequestClose();
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
      </ScrollView>
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
    paddingHorizontal: 16,
    paddingVertical: 14,
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
    height: StyleSheet.hairlineWidth,
    opacity: 0.8,
  },
});

