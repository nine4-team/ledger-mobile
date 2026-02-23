import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useMemo, useState } from 'react';
import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import type { StyleProp, ViewStyle } from 'react-native';

import { resolveAttachmentUri } from '../offline/media';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { CARD_PADDING, CARD_BORDER_WIDTH, getCardBaseStyle, getCardBorderStyle } from '../ui';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import { SelectorCircle } from './SelectorCircle';

export type ItemCardProps = {
  name: string;
  sku?: string;
  sourceLabel?: string;
  locationLabel?: string;
  notes?: string;
  priceLabel?: string;
  indexLabel?: string; // e.g. "1/2" (used for grouped item cards)
  statusLabel?: string;
  budgetCategoryName?: string;
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
  onStatusPress?: () => void;

  /**
   * Custom action element rendered in the card header (e.g., an "Add" button in item pickers).
   */
  headerAction?: React.ReactNode;

  style?: StyleProp<ViewStyle>;
};

export function ItemCard({
  name,
  sku,
  sourceLabel,
  locationLabel,
  notes,
  priceLabel,
  indexLabel,
  statusLabel,
  budgetCategoryName,
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
  onStatusPress,
  headerAction,
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
          borderWidth: CARD_BORDER_WIDTH,
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
        thumbBackground: {
          backgroundColor: uiKitTheme.background.tertiary,
        },
        header: {
          borderBottomColor: uiKitTheme.border.secondary,
        },
      }),
    [uiKitTheme, isSelected]
  );

  const setSelected = (next: boolean) => {
    if (typeof selected !== 'boolean') setInternalSelected(next);
    onSelectedChange?.(next);
  };

  const showTopRow = Boolean(name);

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
        accessibilityLabel={`Item card: ${name}`}
        style={({ pressed }) => [
          styles.card,
          getCardBaseStyle({ radius: 16 }),
          getCardBorderStyle(uiKitTheme),
          themed.card,
          pressed && onPress ? styles.cardPressed : null,
          style,
        ]}
      >
        <View style={[styles.header, themed.header]}>
          {(onSelectedChange || typeof selected === 'boolean' || defaultSelected) ? (
            <Pressable
              onPress={(e) => {
                e.stopPropagation();
                setSelected(!isSelected);
              }}
              accessibilityRole="checkbox"
              accessibilityLabel={`Select ${name}`}
              accessibilityState={{ checked: isSelected }}
              hitSlop={13}
              style={styles.selectorContainer}
            >
              <SelectorCircle selected={isSelected} indicator="dot" />
            </Pressable>
          ) : null}
          <View style={styles.headerSpacer} />
          <View style={styles.headerRight}>
            <View style={styles.headerBadges}>
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
              {budgetCategoryName ? (
                <View
                  style={[styles.pill, themed.pill]}
                  accessibilityRole="text"
                  accessibilityLabel={`Category: ${budgetCategoryName}`}
                >
                  <Text style={[styles.pillText, themed.pillText]} numberOfLines={1}>
                    {budgetCategoryName}
                  </Text>
                </View>
              ) : null}
              {statusLabel ? (
                <Pressable
                  onPress={(e) => {
                    e.stopPropagation();
                    onStatusPress?.();
                  }}
                  hitSlop={8}
                  style={[styles.pill, themed.pill, { flexDirection: 'row', alignItems: 'center', gap: 2 }]}
                  accessibilityRole={onStatusPress ? "button" : "text"}
                  accessibilityLabel={`Status: ${statusLabel}`}
                >
                  <Text style={[styles.pillText, themed.pillText]} numberOfLines={1}>
                    {statusLabel}
                  </Text>
                  <MaterialIcons
                    name="arrow-drop-down"
                    size={16}
                    color={uiKitTheme.primary.main}
                  />
                </Pressable>
              ) : null}
            </View>
            {headerAction ?? null}
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
                  size={24}
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
                <MaterialIcons name="more-vert" size={24} color={themed.icon.color} />
              </Pressable>
            ) : null}
          </View>
        </View>

        <View style={styles.content}>
          {showTopRow ? (
            <View style={styles.topRow}>
              <View style={styles.descriptionContainer}>
                <Text style={[styles.description, themed.description]} numberOfLines={3}>
                  {name}
                </Text>
              </View>
            </View>
          ) : null}

          <View style={styles.bottomRow}>
            <View style={styles.thumbCol}>
              {thumbnailUri && !thumbnailUri.startsWith('offline://') ? (
                <Image
                  source={{ uri: resolveAttachmentUri({ url: thumbnailUri, kind: 'image', contentType: 'image/jpeg' }) ?? thumbnailUri }}
                  style={[styles.thumb, themed.placeholderBorder, themed.thumbBackground]}
                  accessibilityIgnoresInvertColors
                />
              ) : thumbnailUri && thumbnailUri.startsWith('offline://') ? (
                (() => {
                  const resolved = resolveAttachmentUri({ url: thumbnailUri, kind: 'image', contentType: 'image/jpeg' });
                  return resolved ? (
                    <Image
                      source={{ uri: resolved }}
                      style={[styles.thumb, themed.placeholderBorder, themed.thumbBackground]}
                      accessibilityIgnoresInvertColors
                    />
                  ) : (
                    <View style={[styles.thumbPlaceholder, themed.placeholderBorder, themed.thumbBackground]}>
                      <MaterialIcons name="image-not-supported" size={24} color={uiKitTheme.text.secondary} />
                    </View>
                  );
                })()
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
                    themed.thumbBackground,
                    !onAddImagePress ? styles.addImageDisabled : null,
                  ]}
                >
                  <MaterialIcons name="photo-camera" size={24} color={uiKitTheme.text.secondary} />
                </Pressable>
              )}
            </View>

            <View style={styles.textCol}>
              <View style={styles.metaCol}>
                {priceLabel ? (
                  <Text style={[styles.description, themed.description]} numberOfLines={1}>
                    {priceLabel}
                  </Text>
                ) : null}
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
            </View>
          </View>
        </View>
      </Pressable>

      {!onMenuPress && menuItems && menuItems.length > 0 ? (
        <BottomSheetMenuList
          visible={menuVisible}
          onRequestClose={closeMenu}
          items={menuItems}
          title={name}
          showLeadingIcons={true}
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
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: CARD_PADDING,
    paddingVertical: 12,
    borderBottomWidth: 1,
    gap: 12,
  },
  headerSpacer: {
    flex: 1,
  },
  headerBadges: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  content: {
    padding: CARD_PADDING,
    gap: 12,
  },
  topRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  topRowLeft: {
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
    padding: 6,
    minWidth: 32,
    minHeight: 32,
    alignItems: 'center',
    justifyContent: 'center',
  },
  addImageDisabled: {
    opacity: 0.7,
  },
  bottomRow: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
  thumbCol: {
    flexShrink: 0,
  },
  thumb: {
    width: 108,
    height: 108,
    borderRadius: 21,
    borderWidth: 1,
  },
  thumbPlaceholder: {
    width: 108,
    height: 108,
    borderRadius: 21,
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
  selectorContainer: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  descriptionContainer: {
    flex: 1,
    alignItems: 'flex-start',
    justifyContent: 'center',
    minHeight: 0,
    marginBottom: 8,
  },
  description: {
    fontSize: 15,
    fontWeight: '600',
    includeFontPadding: false,
    lineHeight: 20,
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
