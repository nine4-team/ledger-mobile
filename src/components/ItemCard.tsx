import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useMemo, useState } from 'react';
import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import type { ViewStyle } from 'react-native';

import { useUIKitTheme } from '../theme/ThemeProvider';
import { APP_CARD_PADDING, getCardBaseStyle, getCardBorderStyle } from '../ui';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import { SelectorCircle } from './SelectorCircle';

export type ItemCardProps = {
  description: string;
  sku?: string;
  sourceLabel?: string;
  locationLabel?: string;
  notes?: string;
  priceLabel?: string;
  indexLabel?: string; // e.g. "1/2" (used for grouped item cards)
  statusLabel?: string;
  thumbnailUri?: string;

  // Layout options
  // When true, SKU and source/transaction render on separate lines (instead of "SKU • Source").
  stackSkuAndSource?: boolean;

  selected?: boolean;
  defaultSelected?: boolean;
  onSelectedChange?: (selected: boolean) => void;

  bookmarked?: boolean;
  onBookmarkPress?: () => void;

  onAddImagePress?: () => void;
  onMenuPress?: () => void;
  menuItems?: AnchoredMenuItem[];
  onPress?: () => void;

  style?: ViewStyle;
};

export function ItemCard({
  description,
  sku,
  sourceLabel,
  locationLabel,
  notes,
  priceLabel,
  indexLabel,
  statusLabel,
  thumbnailUri,
  stackSkuAndSource,
  selected,
  defaultSelected,
  onSelectedChange,
  bookmarked,
  onBookmarkPress,
  onAddImagePress,
  onMenuPress,
  menuItems,
  onPress,
  style,
}: ItemCardProps) {
  const uiKitTheme = useUIKitTheme();
  const [internalSelected, setInternalSelected] = useState(Boolean(defaultSelected));
  const [menuVisible, setMenuVisible] = useState(false);
  const isSelected = typeof selected === 'boolean' ? selected : internalSelected;
  const stackedMeta = stackSkuAndSource ?? true;

  const themed = useMemo(
    () =>
      StyleSheet.create({
        card: {
          backgroundColor: uiKitTheme.background.surface,
          shadowColor: uiKitTheme.shadow,
          borderColor: isSelected ? uiKitTheme.primary.main : uiKitTheme.border.primary,
        },
        pill: {
          backgroundColor: uiKitTheme.primary.main + '1A',
          borderColor: uiKitTheme.primary.main + '33',
        },
        pillText: {
          color: uiKitTheme.primary.main,
        },
        description: {
          color: uiKitTheme.text.primary,
        },
        metaText: {
          color: uiKitTheme.text.secondary,
        },
        icon: {
          color: uiKitTheme.button.icon.icon,
        },
        placeholderBorder: {
          borderColor: uiKitTheme.border.secondary,
        },
      }),
    [uiKitTheme, isSelected]
  );

  const setSelected = (next: boolean) => {
    if (typeof selected !== 'boolean') setInternalSelected(next);
    onSelectedChange?.(next);
  };

  const showTopRow = Boolean(
    onSelectedChange ||
      typeof selected === 'boolean' ||
      defaultSelected ||
      priceLabel ||
      indexLabel ||
      statusLabel ||
      onBookmarkPress ||
      onMenuPress ||
      (menuItems && menuItems.length > 0)
  );

  const closeMenu = useCallback(() => {
    setMenuVisible(false);
  }, []);

  const handleMenuPress = useCallback(() => {
    if (onMenuPress) {
      onMenuPress();
      return;
    }
    if (menuItems && menuItems.length > 0) {
      setMenuVisible(true);
    }
  }, [menuItems, onMenuPress]);

  return (
    <>
      <Pressable
        onPress={onPress}
        disabled={!onPress}
        accessibilityRole={onPress ? 'button' : 'none'}
        accessibilityLabel={`Item card: ${description}`}
        style={({ pressed }) => [
          styles.card,
          getCardBaseStyle({ radius: 16 }),
          getCardBorderStyle(uiKitTheme),
          themed.card,
        pressed && onPress ? styles.cardPressed : null,
          style,
        ]}
      >
        <View style={styles.content}>
          {showTopRow ? (
            <View style={styles.topRow}>
              {(onSelectedChange || typeof selected === 'boolean' || defaultSelected) ? (
                <Pressable
                  onPress={(e) => {
                    e.stopPropagation();
                    setSelected(!isSelected);
                  }}
                  accessibilityRole="checkbox"
                  accessibilityLabel={`Select ${description}`}
                  accessibilityState={{ checked: isSelected }}
                  hitSlop={13}
                >
                  <SelectorCircle selected={isSelected} indicator="dot" />
                </Pressable>
              ) : null}

              {priceLabel ? (
                <Text style={[styles.price, themed.metaText]} accessibilityRole="text">
                  {priceLabel}
                </Text>
              ) : null}

              <View style={styles.topRowRight}>
                {indexLabel ? (
                  <View
                    style={[styles.pill, themed.pill]}
                    accessibilityRole="text"
                    accessibilityLabel={`Item ${indexLabel}`}
                  >
                    <Text style={[styles.pillText, themed.pillText]} numberOfLines={1}>
                      {indexLabel}
                    </Text>
                  </View>
                ) : null}
                {statusLabel ? (
                  <View
                    style={[styles.pill, themed.pill]}
                    accessibilityRole="text"
                    accessibilityLabel={`Status: ${statusLabel}`}
                  >
                    <Text style={[styles.pillText, themed.pillText]} numberOfLines={1}>
                      {statusLabel}
                    </Text>
                  </View>
                ) : null}

                {onBookmarkPress ? (
                  <Pressable
                    onPress={(e) => {
                      e.stopPropagation();
                      onBookmarkPress();
                    }}
                    hitSlop={8}
                    accessibilityRole="button"
                    accessibilityLabel={bookmarked ? 'Remove bookmark' : 'Add bookmark'}
                    style={styles.iconButton}
                  >
                    <MaterialIcons
                      name={bookmarked ? 'bookmark' : 'bookmark-border'}
                      size={20}
                      color={bookmarked ? uiKitTheme.status.missed.text : themed.icon.color}
                    />
                  </Pressable>
                ) : null}

                {onMenuPress || (menuItems && menuItems.length > 0) ? (
                  <Pressable
                    onPress={(e) => {
                      e.stopPropagation();
                      handleMenuPress();
                    }}
                    hitSlop={8}
                    accessibilityRole="button"
                    accessibilityLabel="More options"
                    style={styles.iconButton}
                  >
                    <MaterialIcons name="more-vert" size={20} color={themed.icon.color} />
                  </Pressable>
                ) : null}
              </View>
            </View>
          ) : null}

          <Text style={[styles.description, themed.description]} numberOfLines={3}>
            {description}
          </Text>

          <View style={styles.bottomRow}>
            <View style={styles.thumbCol}>
              {thumbnailUri ? (
                <Image
                  source={{ uri: thumbnailUri }}
                  style={[styles.thumb, themed.placeholderBorder]}
                  accessibilityIgnoresInvertColors
                />
              ) : (
                <Pressable
                  onPress={(e) => {
                    e.stopPropagation();
                    onAddImagePress?.();
                  }}
                  disabled={!onAddImagePress}
                  accessibilityRole={onAddImagePress ? 'button' : 'image'}
                  accessibilityLabel={onAddImagePress ? 'Add image' : 'No image'}
                  style={[
                    styles.thumbPlaceholder,
                    themed.placeholderBorder,
                    !onAddImagePress ? styles.addImageDisabled : null,
                  ]}
                >
                  <MaterialIcons name="photo-camera" size={24} color={uiKitTheme.text.secondary} />
                </Pressable>
              )}
            </View>

            <View style={styles.textCol}>
              {(sku || sourceLabel || locationLabel) ? (
                <View style={styles.metaCol}>
                  {sourceLabel ? (
                    <Text style={[styles.metaText, themed.metaText]} numberOfLines={1}>
                      <Text style={styles.metaStrong}>Source:</Text> {sourceLabel}
                    </Text>
                  ) : null}
                  {sku ? (
                    <Text style={[styles.metaText, themed.metaText]} numberOfLines={1}>
                      <Text style={styles.metaStrong}>SKU:</Text> {sku}
                    </Text>
                  ) : null}
                  {locationLabel ? (
                    <Text style={[styles.metaText, themed.metaText]} numberOfLines={2}>
                      <Text style={styles.metaStrong}>Location:</Text> {locationLabel}
                    </Text>
                  ) : null}
                </View>
              ) : null}
            </View>
          </View>
        </View>
      </Pressable>

      {!onMenuPress && menuItems && menuItems.length > 0 ? (
        <BottomSheetMenuList
          visible={menuVisible}
          onRequestClose={closeMenu}
          items={menuItems}
          title={description}
          showLeadingIcons={false}
        />
      ) : null}
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
  cardPressed: {
    opacity: 0.92,
  },
  content: {
    padding: APP_CARD_PADDING,
    gap: 12,
  },
  topRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  topRowRight: {
    marginLeft: 'auto',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  price: {
    fontSize: 13,
    fontWeight: '600',
    includeFontPadding: false,
  },
  pill: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 999,
    borderWidth: 1,
    maxWidth: 140,
  },
  pillText: {
    fontSize: 12,
    fontWeight: '600',
    includeFontPadding: false,
  },
  iconButton: {
    padding: 4,
    minWidth: 28,
    minHeight: 28,
    alignItems: 'center',
    justifyContent: 'center',
  },
  addImageDisabled: {
    opacity: 0.7,
  },
  bottomRow: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'flex-start',
  },
  thumbCol: {
    flexShrink: 0,
  },
  thumb: {
    width: 72,
    height: 72,
    borderRadius: 14,
    borderWidth: 1,
  },
  thumbPlaceholder: {
    width: 72,
    height: 72,
    borderRadius: 14,
    borderWidth: 1,
    borderStyle: 'dashed',
    alignItems: 'center',
    justifyContent: 'center',
  },
  textCol: {
    flex: 1,
    minWidth: 0,
    gap: 6,
  },
  description: {
    fontSize: 15,
    fontWeight: '600',
    includeFontPadding: false,
    lineHeight: 20,
    paddingVertical: 2,
  },
  metaRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
  },
  metaCol: {
    gap: 6,
  },
  metaText: {
    fontSize: 13,
    fontWeight: '500',
    includeFontPadding: false,
    lineHeight: 18,
  },
  metaStrong: {
    fontWeight: '700',
  },
});

