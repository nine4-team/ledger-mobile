import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useMemo, useState } from 'react';
import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import type { ViewStyle } from 'react-native';

import { resolveAttachmentUri } from '../offline/media';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { CARD_PADDING, CARD_BORDER_WIDTH, getCardBaseStyle, getCardBorderStyle } from '../ui';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import { SelectorCircle } from './SelectorCircle';

export type ItemCardOpusPrototypeProps = {
  description: string;
  sku?: string;
  sourceLabel?: string;
  locationLabel?: string;
  notes?: string;
  priceLabel?: string;
  indexLabel?: string;
  statusLabel?: string;
  thumbnailUri?: string;

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

export function ItemCardOpusPrototype({
  description,
  sku,
  sourceLabel,
  locationLabel,
  notes,
  priceLabel,
  indexLabel,
  statusLabel,
  thumbnailUri,
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
}: ItemCardOpusPrototypeProps) {
  const uiKitTheme = useUIKitTheme();
  const [internalSelected, setInternalSelected] = useState(Boolean(defaultSelected));
  const [menuVisible, setMenuVisible] = useState(false);
  const isSelected = typeof selected === 'boolean' ? selected : internalSelected;

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
        price: {
          color: uiKitTheme.text.primary,
        },
        metaText: {
          color: uiKitTheme.text.secondary,
        },
        metaSeparator: {
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

  // Build the combined source/SKU line
  const combinedSourceSku = [sourceLabel, sku].filter(Boolean).join('  \u00B7  ');

  const showActions = Boolean(
    statusLabel ||
      indexLabel ||
      onBookmarkPress ||
      onMenuPress ||
      (menuItems && menuItems.length > 0)
  );

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
        {/* ── Title Row: selector + description ── */}
        <View style={styles.titleRow}>
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
              style={styles.selectorContainer}
            >
              <SelectorCircle selected={isSelected} indicator="dot" />
            </Pressable>
          ) : null}

          <Text style={[styles.description, themed.description]} numberOfLines={2}>
            {description}
          </Text>
        </View>

        {/* ── Detail Row: thumbnail + metadata + actions ── */}
        <View style={styles.detailRow}>
          {/* Thumbnail */}
          <View style={styles.thumbCol}>
            {thumbnailUri && !thumbnailUri.startsWith('offline://') ? (
              <Image
                source={{ uri: resolveAttachmentUri({ url: thumbnailUri, kind: 'image', contentType: 'image/jpeg' }) ?? thumbnailUri }}
                style={[styles.thumb, themed.placeholderBorder]}
                accessibilityIgnoresInvertColors
              />
            ) : thumbnailUri && thumbnailUri.startsWith('offline://') ? (
              (() => {
                const resolved = resolveAttachmentUri({ url: thumbnailUri, kind: 'image', contentType: 'image/jpeg' });
                return resolved ? (
                  <Image
                    source={{ uri: resolved }}
                    style={[styles.thumb, themed.placeholderBorder]}
                    accessibilityIgnoresInvertColors
                  />
                ) : (
                  <View style={[styles.thumbPlaceholder, themed.placeholderBorder]}>
                    <MaterialIcons name="image-not-supported" size={20} color={uiKitTheme.text.secondary} />
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
                  !onAddImagePress ? styles.addImageDisabled : null,
                ]}
              >
                <MaterialIcons name="photo-camera" size={20} color={uiKitTheme.text.secondary} />
              </Pressable>
            )}
          </View>

          {/* Metadata + actions */}
          <View style={styles.textCol}>
            {/* Price row with actions pinned right */}
            <View style={styles.priceActionsRow}>
              <View style={styles.priceContainer}>
                {priceLabel ? (
                  <Text style={[styles.price, themed.price]} numberOfLines={1}>
                    {priceLabel}
                  </Text>
                ) : null}
              </View>

              {showActions ? (
                <View style={styles.actionsCluster}>
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
                        size={18}
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
                      <MaterialIcons name="more-vert" size={18} color={themed.icon.color} />
                    </Pressable>
                  ) : null}
                </View>
              ) : null}
            </View>

            {/* Combined source · SKU line */}
            {combinedSourceSku ? (
              <Text style={[styles.metaText, themed.metaText]} numberOfLines={1}>
                {combinedSourceSku}
              </Text>
            ) : null}

            {/* Location with icon */}
            {locationLabel ? (
              <View style={styles.locationRow}>
                <MaterialIcons name="place" size={13} color={uiKitTheme.text.secondary} style={styles.locationIcon} />
                <Text style={[styles.metaText, themed.metaText]} numberOfLines={1}>
                  {locationLabel}
                </Text>
              </View>
            ) : null}

            {/* Notes preview */}
            {notes ? (
              <Text style={[styles.notesText, themed.metaText]} numberOfLines={1}>
                {notes}
              </Text>
            ) : null}
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
    padding: CARD_PADDING,
    shadowOpacity: 0.05,
    shadowRadius: 6,
    elevation: 2,
    gap: 14,
  },
  cardPressed: {
    opacity: 0.97,
    transform: [{ scale: 0.985 }],
  },

  /* ── Title row ── */
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  selectorContainer: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  description: {
    flex: 1,
    fontSize: 15,
    fontWeight: '600',
    includeFontPadding: false,
    lineHeight: 20,
  },

  /* ── Detail row ── */
  detailRow: {
    flexDirection: 'row',
    gap: 14,
    alignItems: 'flex-start',
  },

  /* Thumbnail */
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
  addImageDisabled: {
    opacity: 0.7,
  },

  /* Text column */
  textCol: {
    flex: 1,
    minWidth: 0,
    gap: 4,
  },

  /* Price + actions row */
  priceActionsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    minHeight: 24,
  },
  priceContainer: {
    flexShrink: 1,
    minWidth: 0,
  },
  price: {
    fontSize: 16,
    fontWeight: '700',
    includeFontPadding: false,
    letterSpacing: -0.2,
  },
  actionsCluster: {
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 'auto',
    gap: 6,
  },

  /* Pills */
  pill: {
    paddingHorizontal: 7,
    paddingVertical: 3,
    borderRadius: 999,
    borderWidth: 1,
    maxWidth: 120,
  },
  pillText: {
    fontSize: 11,
    fontWeight: '600',
    includeFontPadding: false,
  },

  /* Icon buttons */
  iconButton: {
    padding: 3,
    minWidth: 24,
    minHeight: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },

  /* Metadata */
  metaText: {
    fontSize: 13,
    fontWeight: '500',
    includeFontPadding: false,
    lineHeight: 18,
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
  },
  locationIcon: {
    marginTop: 1,
  },
  notesText: {
    fontSize: 12,
    fontWeight: '400',
    fontStyle: 'italic',
    includeFontPadding: false,
    lineHeight: 16,
    opacity: 0.8,
  },
});
