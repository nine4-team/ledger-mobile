import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { getCardStyle, getTextSecondaryStyle, surface, textEmphasis } from '../ui';
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
  itemize: boolean;
  disabled?: boolean;
};

function bubbleDisabledToEnd(items: TemplateToggleListItem[]) {
  const enabled: TemplateToggleListItem[] = [];
  const disabled: TemplateToggleListItem[] = [];
  for (const it of items) {
    // Bubble down items where the toggle (itemize) is OFF.
    // Also respect the explicit disabled flag if present.
    if (!it.itemize || it.disabled) disabled.push(it);
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
  rightHeaderLabel: string;
  items: TemplateToggleListItem[];
  onToggleItemize: (id: string, next: boolean) => void;
  onReorderItems?: (nextItems: TemplateToggleListItem[]) => void;
  onDragActiveChange?: (isDragging: boolean) => void;
  /**
   * Controls which items are draggable. Defaults to:
   * - draggable when toggle is ON (itemize === true) and not disabled.
   */
  isItemDraggable?: (item: TemplateToggleListItem) => boolean;
  /**
   * Optional normalization step applied any time items are set/reordered.
   * Defaults to bubbling items with toggle OFF (or disabled) to the bottom.
   */
  normalizeOrder?: (items: TemplateToggleListItem[]) => TemplateToggleListItem[];
  /**
   * Preferred: provide content and the card will render a consistent info dialog.
   * If omitted, falls back to `onPressInfo` to preserve prior behavior.
   */
  getInfoContent?: (item: TemplateToggleListItem) => InfoDialogContent;
  onPressInfo?: (id: string) => void;
  onPressMenu?: (id: string) => void;
  onPressCreate?: () => void;
  createPlaceholderLabel?: string;
  style?: ViewStyle;
};

export function TemplateToggleListCard({
  title,
  rightHeaderLabel,
  items,
  onToggleItemize,
  onReorderItems,
  onDragActiveChange,
  isItemDraggable,
  normalizeOrder,
  getInfoContent,
  onPressInfo,
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
        headerBg: {
          backgroundColor: uiKitTheme.background.tertiary ?? uiKitTheme.background.screen,
        },
        divider: {
          backgroundColor: uiKitTheme.border.secondary,
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
          color: uiKitTheme.text.secondary,
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

  const itemHeight = 54 + StyleSheet.hairlineWidth;
  const menuItems: AnchoredMenuItem[] = useMemo(() => {
    if (!menuTarget) return [];
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
      if (onPressMenu) {
        onPressMenu(item.id);
        return;
      }
      setMenuTarget(item);
      setMenuVisible(true);
    },
    [onPressMenu]
  );

  return (
    <View style={[surface.overflowHidden, themed.card, style]} accessibilityRole="none">
      <View style={[styles.headerRow, themed.headerBg]}>
        <AppText
          variant="caption"
          style={[textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
          numberOfLines={1}
        >
          {title}
        </AppText>
        <AppText
          variant="caption"
          style={[textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
          numberOfLines={1}
        >
          {rightHeaderLabel}
        </AppText>
      </View>

      <View style={[styles.divider, themed.divider]} />

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
          isItemDraggable ? isItemDraggable(it) : it.itemize && !Boolean(it.disabled)
        }
        renderItem={({ item, isActive, dragHandleProps }) => {
          const disabled = Boolean(item.disabled);
          return (
            <View style={{ height: itemHeight }}>
              <DraggableCard
                title={item.name}
                disabled={disabled}
                isActive={isActive}
                dragHandleProps={dragHandleProps}
                right={
                  <>
                    <Pressable
                      accessibilityRole="switch"
                      accessibilityState={{ checked: item.itemize, disabled }}
                      accessibilityLabel={`${rightHeaderLabel} ${item.name}`}
                      disabled={disabled}
                      onPress={() => onToggleItemize(item.id, !item.itemize)}
                      hitSlop={8}
                      style={({ pressed }) => [styles.toggleContainer, pressed && !disabled && styles.pressed]}
                    >
                      <View style={[styles.toggle, item.itemize ? themed.toggleOnBg : themed.toggleOffBg]}>
                        <View
                          style={[
                            styles.toggleThumb,
                            themed.toggleThumb,
                            { transform: [{ translateX: item.itemize ? 20 : 0 }] },
                          ]}
                        />
                      </View>
                    </Pressable>

                    {getInfoContent ? (
                      <InfoButton
                        accessibilityLabel={`Info for ${item.name}`}
                        content={getInfoContent(item)}
                        iconColor={themed.iconBrown.color}
                        iconSize={18}
                        style={styles.iconButton}
                        onPress={() => onPressInfo?.(item.id)}
                      />
                    ) : (
                      <Pressable
                        accessibilityRole="button"
                        accessibilityLabel={`Info for ${item.name}`}
                        hitSlop={10}
                        style={({ pressed }) => [styles.iconButton, pressed && styles.pressed]}
                        onPress={() => onPressInfo?.(item.id)}
                      >
                        <MaterialIcons name="info-outline" size={18} color={themed.iconBrown.color} />
                      </Pressable>
                    )}

                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel={`More options for ${item.name}`}
                      hitSlop={10}
                      style={({ pressed }) => [styles.iconButton, pressed && styles.pressed]}
                      onPress={() => handleMenuPress(item)}
                    >
                      <MaterialIcons name="more-vert" size={20} color={themed.iconBrown.color} />
                    </Pressable>
                  </>
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
              <MaterialIcons name="add" size={18} color={themed.icon.color} />
            </View>
            <AppText variant="body" style={[styles.createLabel, themed.createText]} numberOfLines={1}>
              {createPlaceholderLabel}
            </AppText>
          </View>
          <View style={styles.createRight} />
        </Pressable>
      ) : null}

      {!onPressMenu ? (
        <BottomSheetMenuList
          visible={menuVisible}
          onRequestClose={closeMenu}
          items={menuItems}
          title={menuTarget?.name ?? 'Options'}
        />
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    opacity: 0.9,
  },
  iconButton: {
    padding: 6,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
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
    fontStyle: 'italic',
    fontWeight: '500',
  },
  createRight: {
    width: 1,
  },
});

