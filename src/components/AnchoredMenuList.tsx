import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useEffect, useMemo, useRef, useState } from 'react';
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
  /** When true, subactions are plain navigation/action items with no selection state, checkmarks, or header value display. */
  actionOnly?: boolean;
};

export type MenuSelectionOptions = {
  item: AnchoredMenuItem;
  itemKey: string;
  subactions: AnchoredMenuSubaction[];
  selectedSubactionByKey?: Record<string, string>;
  activeSubactionKey?: string;
  hideDefaultLabel?: boolean;
};

export function resolveMenuSelection({
  item,
  itemKey,
  subactions,
  selectedSubactionByKey,
  activeSubactionKey,
  hideDefaultLabel = false,
}: MenuSelectionOptions) {
  const selectedByIcon = subactions.find((sub) => sub.icon === 'check');
  const rawCurrentKey =
    item.selectedSubactionKey ??
    selectedSubactionByKey?.[itemKey] ??
    selectedByIcon?.key ??
    item.defaultSelectedSubactionKey ??
    subactions[0]?.key;
  const isActiveGroup = !activeSubactionKey || subactions.some((sub) => sub.key === activeSubactionKey);
  const currentKey = isActiveGroup ? rawCurrentKey : undefined;
  const isDefaultSelection =
    item.defaultSelectedSubactionKey != null && currentKey === item.defaultSelectedSubactionKey;
  const suppressDefaultCheckmark = item.suppressDefaultCheckmark ?? true;
  const showCheckmark = isActiveGroup && (!suppressDefaultCheckmark || !isDefaultSelection);
  const currentLabel =
    currentKey && !(hideDefaultLabel && isDefaultSelection)
      ? subactions.find((s) => s.key === currentKey)?.label ?? ''
      : '';

  return {
    currentKey,
    currentLabel,
    isDefaultSelection,
    showCheckmark,
    suppressDefaultCheckmark,
    isActiveGroup,
  };
}

export interface AnchoredMenuListProps {
  visible: boolean;
  anchorLayout: AnchorLayout | null;
  onRequestClose: () => void;
  items: AnchoredMenuItem[];
  showLeadingIcons?: boolean;
  width?: number;
  maxWidth?: number;
  offsetY?: number;
  /**
   * When provided, only the group containing this subaction
   * shows its selected value in the header.
   */
  activeSubactionKey?: string;
  /**
   * When true, hide the header value for default selections.
   */
  hideDefaultLabel?: boolean;
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
  activeSubactionKey,
  hideDefaultLabel = false,
}: AnchoredMenuListProps) {
  const uiKitTheme = useUIKitTheme();
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
    <AnchoredMenu
      visible={visible}
      anchorLayout={anchorLayout}
      onRequestClose={onRequestClose}
      width={width}
      maxWidth={maxWidth}
      offsetY={offsetY}
    >
      {computedItems.map((item, idx) => {
        const showDivider = true;
        const subactions = item.subactions ?? [];
        const isSubmenuItem = subactions.length > 0;
        const itemKey = item.key ?? `${item.label}-${idx}`;

        if (isSubmenuItem) {
          const { currentKey, currentLabel, showCheckmark, suppressDefaultCheckmark } = resolveMenuSelection({
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
                      { color: showCheckmark ? uiKitTheme.primary.main : uiKitTheme.text.primary },
                    ]}
                  >
                    {item.label}
                  </Text>
                </View>
                <View style={styles.menuSectionRight}>
                  {currentLabel ? (
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
                    const selectedSub = currentKey === sub.key;
                    const isDefaultSelected =
                      selectedSub &&
                      item.defaultSelectedSubactionKey != null &&
                      sub.key === item.defaultSelectedSubactionKey;
                    const allowCheck = !suppressDefaultCheckmark || !isDefaultSelected;
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
                            // Store action to execute after modal dismisses
                            pendingActionRef.current = sub.onPress;
                            onRequestClose();
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
                // Store action to execute after modal dismisses
                pendingActionRef.current = item.onPress ?? null;
                onRequestClose();
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
