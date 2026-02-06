import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useUIKitTheme } from '../theme/ThemeProvider';
import { AnchoredMenu, AnchorLayout } from './AnchoredMenu';

export type MenuIconName = React.ComponentProps<typeof MaterialIcons>['name'];

export type AnchoredMenuSubaction = {
  key: string;
  label: string;
  onPress: () => void;
  icon?: MenuIconName;
};

export type AnchoredMenuItem = {
  key?: string;
  label: string;
  onPress?: () => void;
  icon?: MenuIconName;
  subactions?: AnchoredMenuSubaction[];
  selectedSubactionKey?: string;
  defaultSelectedSubactionKey?: string;
  suppressDefaultCheckmark?: boolean;
  destructive?: boolean;
};

export interface AnchoredMenuListProps {
  visible: boolean;
  anchorLayout: AnchorLayout | null;
  onRequestClose: () => void;
  items: AnchoredMenuItem[];
  showLeadingIcons?: boolean;
  width?: number;
  maxWidth?: number;
  offsetY?: number;
}

export function AnchoredMenuList({
  visible,
  anchorLayout,
  onRequestClose,
  items,
  showLeadingIcons = true,
  width = 220,
  maxWidth = 280,
  offsetY = 4,
}: AnchoredMenuListProps) {
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
    <AnchoredMenu
      visible={visible}
      anchorLayout={anchorLayout}
      onRequestClose={onRequestClose}
      width={width}
      maxWidth={maxWidth}
      offsetY={offsetY}
    >
      {computedItems.map((item, idx) => {
        const showDivider = idx < computedItems.length - 1;
        const subactions = item.subactions ?? [];
        const isSubmenuItem = subactions.length > 0;
        const itemKey = item.key ?? `${item.label}-${idx}`;

        if (isSubmenuItem) {
          const currentKey =
            item.selectedSubactionKey ??
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
                  <Text
                    style={[
                      styles.menuSectionTitle,
                      { color: showCheckmark ? uiKitTheme.primary.main : uiKitTheme.text.primary },
                    ]}
                  >
                    {item.label}
                  </Text>
                </View>
                <View style={styles.menuSectionRight}>
                  <Text
                    style={[
                      styles.menuSectionValue,
                      { color: showCheckmark ? uiKitTheme.primary.main : uiKitTheme.text.secondary },
                    ]}
                  >
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
                    const isDefaultSelected =
                      selectedSub &&
                      item.defaultSelectedSubactionKey != null &&
                      sub.key === item.defaultSelectedSubactionKey;
                    const allowCheck = !item.suppressDefaultCheckmark || !isDefaultSelected;
                    const isHighlighted = selectedSub && allowCheck;

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
    </AnchoredMenu>
  );
}

const styles = StyleSheet.create({
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
