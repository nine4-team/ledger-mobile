import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';
import { useUIKitTheme } from '@/theme/ThemeProvider';
import { getCardStyle, surface } from '../ui';
import { AppText } from './AppText';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import { DraggableCard } from './DraggableCard';
import { DraggableCardList } from './DraggableCardList';
import type { InfoDialogContent } from './InfoButton';
import { InfoButton } from './InfoButton';

export type TemplateToggleListItem = {
  id: string;
  name: string;
  disabled: boolean;
};

function bubbleDisabledToEnd(items: TemplateToggleListItem[]) {
  const enabled: TemplateToggleListItem[] = [];
  const disabled: TemplateToggleListItem[] = [];
  for (const it of items) {
    // Bubble down items where the toggle is OFF (disabled).
    if (it.disabled) disabled.push(it);
    else enabled.push(it);
  }
  return enabled.concat(disabled);
}

function sameIdOrder(a: TemplateToggleListItem[], b: TemplateToggleListItem[]) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i]?.id !== b[i]?.id) return false;
  }
  return true;
}

export type TemplateToggleListCardProps = {
  title: string;
  rightHeaderLabel?: string;
  items: TemplateToggleListItem[];
  onToggleDisabled?: (id: string, next: boolean) => void;
  onReorderItems?: (nextItems: TemplateToggleListItem[]) => void;
  onDragActiveChange?: (isDragging: boolean) => void;
  /**
   * Controls which items are draggable. Defaults to:
   * - draggable when toggle is ON (disabled === false).
   */
  isItemDraggable?: (item: TemplateToggleListItem) => boolean;
  /**
   * Optional normalization step applied any time items are set/reordered.
   * Defaults to bubbling items with toggle OFF (disabled) to the bottom.
   */
  normalizeOrder?: (items: TemplateToggleListItem[]) => TemplateToggleListItem[];
  /**
   * Preferred: provide content and the card will render a consistent info dialog.
   * If omitted, falls back to `onPressInfo` to preserve prior behavior.
   */
  getInfoContent?: (item: TemplateToggleListItem) => InfoDialogContent;
  onPressInfo?: (id: string) => void;
  /**
   * Preferred: provide menu items and this card will render a canonical bottom-sheet menu.
   * If omitted, falls back to `onPressMenu` to preserve prior behavior.
   */
  getMenuItems?: (item: TemplateToggleListItem) => AnchoredMenuItem[];
  /**
   * Optional title for the bottom-sheet menu.
   * Defaults to the item's name (or "Options").
   */
  getMenuTitle?: (item: TemplateToggleListItem) => string;
  onPressMenu?: (id: string) => void;
  onPressCreate?: () => void;
  createPlaceholderLabel?: string;
  style?: ViewStyle;
};

export function TemplateToggleListCard({
  title,
  rightHeaderLabel,
  items,
  onToggleDisabled,
  onReorderItems,
  onDragActiveChange,
  isItemDraggable,
  normalizeOrder,
  getInfoContent,
  onPressInfo,
  getMenuItems,
  getMenuTitle,
  onPressMenu,
  onPressCreate,
  createPlaceholderLabel = 'Click to create new',
  style,
}: TemplateToggleListCardProps) {
  const uiKitTheme = useUIKitTheme();
  const [orderedItems, setOrderedItems] = useState(items);
  const [menuVisible, setMenuVisible] = useState(false);
  const [menuTarget, setMenuTarget] = useState<TemplateToggleListItem | null>(null);

  useEffect(() => {
    const next = (normalizeOrder ?? bubbleDisabledToEnd)(items);
    setOrderedItems(next);
    // Keep parent state consistent with the displayed order.
    if (onReorderItems && !sameIdOrder(items, next)) {
      onReorderItems(next);
    }
  }, [items, normalizeOrder, onReorderItems]);

  const themed = useMemo(
    () =>
      StyleSheet.create({
        card: getCardStyle(uiKitTheme, { radius: 12 }),
        divider: {
          borderTopColor: uiKitTheme.border.secondary,
        },
        rowText: {
          color: uiKitTheme.text.primary,
        },
        iconBrown: {
          color: uiKitTheme.primary.main,
        },
        icon: {
          color: uiKitTheme.text.secondary,
        },
        createText: {
          color: uiKitTheme.primary.main,
        },
        toggleOnBg: {
          backgroundColor: uiKitTheme.button.primary.background ?? uiKitTheme.primary.main,
        },
        toggleOffBg: {
          backgroundColor: uiKitTheme.border.secondary,
        },
        toggleThumb: {
          backgroundColor: uiKitTheme.background.screen,
          shadowColor: uiKitTheme.shadow,
        },
      }),
    [uiKitTheme]
  );

  const itemHeight = 62 + StyleSheet.hairlineWidth;
  const itemContainerStyle = useMemo(() => ({ height: itemHeight }), [itemHeight]);
  const menuItems: AnchoredMenuItem[] = useMemo(() => {
    if (!menuTarget) return [];
    if (getMenuItems) return getMenuItems(menuTarget);
    const name = menuTarget.name;
    return [
      {
        key: 'rename',
        label: 'Rename',
        onPress: () => Alert.alert('Rename', `Rename ${name}`),
      },
      {
        key: 'duplicate',
        label: 'Duplicate',
        onPress: () => Alert.alert('Duplicate', `Duplicate ${name}`),
      },
      {
        key: 'delete',
        label: 'Delete',
        onPress: () => Alert.alert('Delete', `Delete ${name}`),
      },
    ];
  }, [menuTarget]);

  const closeMenu = useCallback(() => {
    setMenuVisible(false);
    setMenuTarget(null);
  }, []);

  const handleMenuPress = useCallback(
    (item: TemplateToggleListItem) => {
      if (getMenuItems) {
        setMenuTarget(item);
        setMenuVisible(true);
        return;
      }
      // Back-compat: if a parent provides its own menu handler, defer to it.
      if (onPressMenu) return onPressMenu(item.id);
      setMenuTarget(item);
      setMenuVisible(true);
    },
    [getMenuItems, onPressMenu]
  );

  return (
    <View style={[surface.overflowHidden, themed.card, style]} accessibilityRole="none">
      <DraggableCardList
        items={orderedItems}
        getItemId={(it) => it.id}
        itemHeight={itemHeight}
        onReorder={(next) => {
          const normalized = (normalizeOrder ?? bubbleDisabledToEnd)(next);
          setOrderedItems(normalized);
          onReorderItems?.(normalized);
        }}
        onDragActiveChange={onDragActiveChange}
        isItemDraggable={(it) =>
          isItemDraggable ? isItemDraggable(it) : !it.disabled
        }
        renderItem={({ item, isActive, dragHandleProps }) => {
          const isDimmed = item.disabled;
          const iconColor = isDimmed ? uiKitTheme.text.secondary : themed.iconBrown.color;
          return (
            <View style={itemContainerStyle}>
              <DraggableCard
                title={item.name}
                disabled={isDimmed}
                isActive={isActive}
                dragHandleProps={dragHandleProps}
                right={
                  <View style={[styles.rightContent, isDimmed && styles.dimmedRight]}>
                    {onToggleDisabled ? (
                      <Pressable
                        accessibilityRole="switch"
                        accessibilityState={{ checked: !item.disabled, disabled: false }}
                        accessibilityLabel={`${rightHeaderLabel ?? ''} ${item.name}`}
                        disabled={false}
                        onPress={() => onToggleDisabled(item.id, !item.disabled)}
                        hitSlop={8}
                        style={({ pressed }) => [
                          styles.toggleContainer,
                          pressed && styles.pressed,
                        ]}
                      >
                        <View style={[styles.toggle, !item.disabled ? themed.toggleOnBg : themed.toggleOffBg]}>
                          <View
                            style={[
                              styles.toggleThumb,
                              themed.toggleThumb,
                              { transform: [{ translateX: !item.disabled ? 20 : 0 }] },
                            ]}
                          />
                        </View>
                      </Pressable>
                    ) : null}

                    {getInfoContent ? (
                      <InfoButton
                        accessibilityLabel={`Info for ${item.name}`}
                        content={getInfoContent(item)}
                        iconColor={iconColor}
                        iconSize={18}
                        style={styles.iconButton}
                        onPress={() => onPressInfo?.(item.id)}
                      />
                    ) : onPressInfo ? (
                      <Pressable
                        accessibilityRole="button"
                        accessibilityLabel={`Info for ${item.name}`}
                        hitSlop={10}
                        style={({ pressed }) => [styles.iconButton, pressed && styles.pressed]}
                        onPress={() => onPressInfo(item.id)}
                      >
                        <MaterialIcons name="info-outline" size={18} color={iconColor} />
                      </Pressable>
                    ) : null}

                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel={`More options for ${item.name}`}
                      hitSlop={10}
                      style={({ pressed }) => [styles.iconButton, pressed && styles.pressed]}
                      onPress={() => handleMenuPress(item)}
                    >
                      <MaterialIcons name="more-vert" size={20} color={iconColor} />
                    </Pressable>
                  </View>
                }
              />
              <View style={[styles.divider, themed.divider]} />
            </View>
          );
        }}
      />

      {onPressCreate ? (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Create new item"
          onPress={onPressCreate}
          style={({ pressed }) => [styles.createRow, pressed && styles.pressed]}
        >
          <View style={styles.createLeft}>
            <View style={styles.createPlus}>
              <MaterialIcons name="add-circle-outline" size={18} color={themed.iconBrown.color} />
            </View>
            <AppText variant="body" style={[styles.createLabel, themed.createText]} numberOfLines={1}>
              {createPlaceholderLabel}
            </AppText>
          </View>
          <View style={styles.createRight} />
        </Pressable>
      ) : null}

      {!onPressMenu || getMenuItems ? (
        <BottomSheetMenuList
          visible={menuVisible}
          onRequestClose={closeMenu}
          items={menuItems}
          title={menuTarget ? (getMenuTitle ? getMenuTitle(menuTarget) : menuTarget.name) : 'Options'}
        />
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  divider: {
    borderTopWidth: 1,
  },
  iconButton: {
    padding: 6,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  rightContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  dimmedRight: {
    opacity: 0.6,
  },
  toggleContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 4,
    paddingHorizontal: 2,
  },
  toggle: {
    width: 50,
    height: 30,
    borderRadius: 15,
    padding: 2,
    justifyContent: 'center',
  },
  toggleThumb: {
    width: 26,
    height: 26,
    borderRadius: 13,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
    elevation: 2,
  },
  pressed: {
    opacity: 0.7,
  },
  createRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 10,
    minHeight: 46,
  },
  createLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    minWidth: 0,
    gap: 10,
  },
  createPlus: {
    width: 32,
    height: 32,
    alignItems: 'center',
    justifyContent: 'center',
  },
  createLabel: {
    fontWeight: '500',
  },
  createRight: {
    width: 1,
  },
});

