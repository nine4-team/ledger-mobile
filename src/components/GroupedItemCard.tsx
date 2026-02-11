import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useMemo, useState } from 'react';
import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import type { StyleProp, ViewStyle } from 'react-native';

import { resolveAttachmentUri } from '../offline/media';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { CARD_PADDING, CARD_BORDER_WIDTH, getCardBaseStyle, getCardBorderStyle } from '../ui';
import { ItemCard } from './ItemCard';
import type { ItemCardProps } from './ItemCard';
import { SelectorCircle } from './SelectorCircle';

export type GroupedItemListSummary = Pick<
  ItemCardProps,
  'name' | 'sku' | 'sourceLabel' | 'locationLabel' | 'notes' | 'thumbnailUri'
>;

export type GroupedItemCardProps = {
  summary: GroupedItemListSummary;
  countLabel?: string; // e.g. "×2"
  totalLabel?: string; // e.g. "$498.00"
  microcopyWhenCollapsed?: string; // e.g. "Expand to view all items"

  items: ItemCardProps[];

  expanded?: boolean;
  defaultExpanded?: boolean;
  onExpandedChange?: (expanded: boolean) => void;

  // Group level selection
  selected?: boolean;
  onSelectedChange?: (selected: boolean) => void;

  onPress?: () => void; // optional group header press
  style?: StyleProp<ViewStyle>;
};

export function GroupedItemCard({
  summary,
  countLabel,
  totalLabel,
  microcopyWhenCollapsed = 'View All',
  items,
  expanded,
  defaultExpanded,
  onExpandedChange,
  selected,
  onSelectedChange,
  onPress,
  style,
}: GroupedItemCardProps) {
  const uiKitTheme = useUIKitTheme();

  // Expansion state
  const [internalExpanded, setInternalExpanded] = useState(Boolean(defaultExpanded));
  const isExpanded = typeof expanded === 'boolean' ? expanded : internalExpanded;

  // Selection state
  // Compute group selection based on child items
  const derivedSelected = useMemo(() => {
    if (items.length === 0) return false;
    // Group is selected if all items are selected
    const selectableItems = items.filter((item) => item.onSelectedChange !== undefined || typeof item.selected === 'boolean');
    if (selectableItems.length === 0) return false;
    return selectableItems.every((item) => item.selected === true);
  }, [items]);

  const isSelected = typeof selected === 'boolean' ? selected : derivedSelected;

  const countBadgeStyle = useMemo(
    () => ({
      backgroundColor: uiKitTheme.primary.main + '1A',
      borderColor: uiKitTheme.primary.main + '33',
    }),
    [uiKitTheme]
  );
  const countBadgeTextStyle = useMemo(() => ({ color: uiKitTheme.primary.main }), [uiKitTheme]);

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
        childIndicator: {
          borderTopColor: uiKitTheme.border.secondary,
          borderTopWidth: 1,
        },
      }),
    [uiKitTheme, isSelected]
  );

  const setExpanded = (next: boolean) => {
    if (typeof expanded !== 'boolean') setInternalExpanded(next);
    onExpandedChange?.(next);
  };

  const setSelected = (next: boolean) => {
    // If there's an external selection handler (e.g., SharedItemsList),
    // let it handle the update. The parent will update its state and re-render children
    // with new `selected` props, avoiding duplicate/conflicting updates.
    if (onSelectedChange) {
      onSelectedChange(next);
    } else {
      // No external handler: propagate selection directly to all child items.
      // This allows GroupedItemCard to work standalone without a parent managing state.
      items.forEach((item) => {
        if (item.onSelectedChange) {
          item.onSelectedChange(next);
        }
      });
    }
  };

  const handlePress = () => {
    if (onPress) {
      onPress();
      return;
    }
    setExpanded(!isExpanded);
  };

  const perItemPriceLabel = useMemo(() => {
    if (!items.length) return null;
    const unique = new Set(items.map((i) => i.priceLabel).filter(Boolean));
    if (unique.size !== 1) return null;
    const [only] = Array.from(unique);
    return only ?? null;
  }, [items]);

  const collapsedPriceLabel = totalLabel ?? perItemPriceLabel;
  const perItemSuffix = totalLabel && perItemPriceLabel ? ` (${perItemPriceLabel} each)` : null;

  return (
    <View
      style={[
        styles.card,
        getCardBaseStyle({ radius: 16 }),
        getCardBorderStyle(uiKitTheme),
        themed.card,
        style,
      ]}
      accessibilityRole="none"
      accessibilityLabel={`Grouped item card: ${summary.name}`}
    >
      <Pressable
        onPress={handlePress}
        accessibilityRole="button"
        accessibilityLabel={`${isExpanded ? 'Collapse' : 'Expand'} group: ${summary.name}`}
        accessibilityState={{ expanded: isExpanded }}
        style={({ pressed }) => [
          pressed ? styles.cardPressed : null,
        ]}
      >
        <View style={[styles.header, themed.header]}>
          {(onSelectedChange || typeof selected === 'boolean') ? (
            <Pressable
              onPress={(e) => {
                e.stopPropagation();
                setSelected(!isSelected);
              }}
              accessibilityRole="checkbox"
              accessibilityLabel="Select group"
              accessibilityState={{ checked: isSelected }}
              hitSlop={13}
              style={styles.selectorContainer}
            >
              <SelectorCircle selected={isSelected} indicator="dot" />
            </Pressable>
          ) : null}

          <View style={styles.headerSpacer} />

          <View style={styles.headerRight}>
            {countLabel ? (
              <View
                style={[styles.pill, countBadgeStyle]}
                accessibilityRole="text"
                accessibilityLabel={`Count ${countLabel}`}
              >
                <Text style={[styles.pillText, countBadgeTextStyle]} numberOfLines={1}>
                  {countLabel}
                </Text>
              </View>
            ) : null}

            {!isExpanded && microcopyWhenCollapsed ? (
              <Text style={[styles.microcopy, themed.metaText]} numberOfLines={1}>
                {microcopyWhenCollapsed}
              </Text>
            ) : null}

            <View style={styles.chevron}>
              <MaterialIcons
                name={isExpanded ? 'keyboard-arrow-down' : 'chevron-right'}
                size={22}
                color={themed.icon.color}
              />
            </View>
          </View>
        </View>

        {!isExpanded ? (
          <View style={styles.content}>
            <View style={styles.descriptionContainer}>
              <Text style={[styles.description, themed.description]} numberOfLines={3}>
                {summary.name}
              </Text>
            </View>

            <View style={styles.bottomRow}>
              <View style={styles.thumbCol}>
                {summary.thumbnailUri && !summary.thumbnailUri.startsWith('offline://') ? (
                  <Image
                    source={{ uri: resolveAttachmentUri({ url: summary.thumbnailUri, kind: 'image', contentType: 'image/jpeg' }) ?? summary.thumbnailUri }}
                    style={[styles.thumb, themed.placeholderBorder, themed.thumbBackground]}
                    accessibilityIgnoresInvertColors
                  />
                ) : summary.thumbnailUri && summary.thumbnailUri.startsWith('offline://') ? (
                  (() => {
                    const resolved = resolveAttachmentUri({ url: summary.thumbnailUri, kind: 'image', contentType: 'image/jpeg' });
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
                ) : null}
              </View>

              <View style={styles.textCol}>
                <View style={styles.metaCol}>
                  {collapsedPriceLabel ? (
                    <Text style={[styles.description, themed.description]} numberOfLines={1}>
                      {collapsedPriceLabel}
                      {perItemSuffix ? (
                        <Text style={[styles.perItemText, themed.metaText]}>{perItemSuffix}</Text>
                      ) : null}
                    </Text>
                  ) : null}
                  {summary.sourceLabel ? (
                    <Text style={[styles.metaText, themed.metaText]} numberOfLines={1}>
                      <Text style={styles.metaStrong}>Source:</Text> {summary.sourceLabel}
                    </Text>
                  ) : null}
                  {summary.sku ? (
                    <Text style={[styles.metaText, themed.metaText]} numberOfLines={1}>
                      <Text style={styles.metaStrong}>SKU:</Text> {summary.sku}
                    </Text>
                  ) : null}
                  {summary.locationLabel ? (
                    <Text style={[styles.metaText, themed.metaText]} numberOfLines={2}>
                      <Text style={styles.metaStrong}>Location:</Text> {summary.locationLabel}
                    </Text>
                  ) : null}
                </View>
              </View>
            </View>
          </View>
        ) : null}
      </Pressable>

      {isExpanded ? (
        <View style={[styles.childrenContainer, themed.childIndicator]}>
          {items.map((item, idx) => (
            <View key={`${item.name}-${idx}`} style={styles.childWrapper}>
              <ItemCard
                {...item}
                indexLabel={`${idx + 1}/${items.length}`}
                stackSkuAndSource
                style={[
                  idx < items.length - 1 ? styles.itemRowSpacing : null,
                ]}
              />
            </View>
          ))}
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    padding: 0,
    overflow: 'hidden',
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
    paddingVertical: CARD_PADDING,
    borderBottomWidth: 1,
    gap: 12,
  },
  selectorContainer: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerSpacer: {
    flex: 1,
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flexShrink: 0,
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
  microcopy: {
    fontSize: 12,
    fontWeight: '500',
    includeFontPadding: false,
    fontStyle: 'italic',
  },
  chevron: {
    width: 22,
    height: 22,
    alignItems: 'center',
    justifyContent: 'center',
  },
  content: {
    padding: CARD_PADDING,
    gap: 12,
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
  perItemText: {
    fontSize: 13,
    fontWeight: '500',
    includeFontPadding: false,
  },
  childrenContainer: {
    paddingTop: 12,
    paddingHorizontal: 12,
    paddingBottom: 12,
  },
  childWrapper: {
    // 
  },
  itemRowSpacing: {
    marginBottom: 12,
  },
});
