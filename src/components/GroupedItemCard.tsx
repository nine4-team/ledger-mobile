import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { ViewStyle } from 'react-native';

import { useUIKitTheme } from '../theme/ThemeProvider';
import { getCardBaseStyle, getCardBorderStyle } from '../ui';
import type { ItemCardProps } from './ItemCard';

export type GroupedItemListSummary = Pick<
  ItemCardProps,
  'description' | 'sku' | 'sourceLabel' | 'locationLabel' | 'notes' | 'thumbnailUri'
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
  defaultSelected?: boolean;
  onSelectedChange?: (selected: boolean) => void;

  onPress?: () => void; // optional group header press
  style?: ViewStyle;
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
  defaultSelected,
  onSelectedChange,
  onPress,
  style,
}: GroupedItemCardProps) {
  const uiKitTheme = useUIKitTheme();
  
  // Expansion state
  const [internalExpanded, setInternalExpanded] = useState(Boolean(defaultExpanded));
  const isExpanded = typeof expanded === 'boolean' ? expanded : internalExpanded;

  // Selection state
  const [internalSelected, setInternalSelected] = useState(Boolean(defaultSelected));
  const isSelected = typeof selected === 'boolean' ? selected : internalSelected;

  const themed = useMemo(
    () =>
      StyleSheet.create({
        card: {
          backgroundColor: uiKitTheme.background.surface,
          shadowColor: uiKitTheme.shadow,
          borderColor: isSelected ? uiKitTheme.primary.main : uiKitTheme.border.primary,
        },
        metaText: {
          color: uiKitTheme.text.secondary,
        },
        icon: {
          color: uiKitTheme.text.secondary,
        },
        childIndicator: {
          borderTopColor: uiKitTheme.border.secondary,
          borderTopWidth: 1,
        },
        selector: {
          borderColor: isSelected ? uiKitTheme.primary.main : uiKitTheme.border.secondary,
        },
        selectorInner: {
          backgroundColor: uiKitTheme.primary.main,
        },
      }),
    [uiKitTheme, isSelected]
  );

  const setExpanded = (next: boolean) => {
    if (typeof expanded !== 'boolean') setInternalExpanded(next);
    onExpandedChange?.(next);
  };

  const setSelected = (next: boolean) => {
    if (typeof selected !== 'boolean') setInternalSelected(next);
    onSelectedChange?.(next);
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
      accessibilityLabel={`Grouped item card: ${summary.description}`}
    >
      <Pressable
        onPress={handlePress}
        accessibilityRole="button"
        accessibilityLabel={`${isExpanded ? 'Collapse' : 'Expand'} group: ${summary.description}`}
        accessibilityState={{ expanded: isExpanded }}
        style={({ pressed }) => [styles.header, pressed ? { opacity: 0.95 } : null]}
      >
        {/* Top Row: Checkbox, Total, Count, Microcopy, Chevron */}
        <View style={[styles.headerTopRow, isExpanded ? { marginBottom: 0 } : null]}>
          {/* Checkbox */}
          {!isExpanded && (onSelectedChange || typeof selected === 'boolean' || defaultSelected) ? (
            <Pressable
              onPress={(e) => {
                e.stopPropagation();
                setSelected(!isSelected);
              }}
              style={[styles.selector, themed.selector]}
              accessibilityRole="checkbox"
              accessibilityLabel={`Select group`}
              accessibilityState={{ checked: isSelected }}
              hitSlop={8}
            >
              {isSelected ? (
                <View style={[styles.selectorInner, themed.selectorInner]} />
              ) : null}
            </Pressable>
          ) : null}

          {/* Total Price */}
          {totalLabel ? (
            <View style={styles.totalRow}>
              <Text style={[styles.total, themed.metaText]} numberOfLines={1}>
                {totalLabel}
              </Text>
              {perItemPriceLabel ? (
                <Text style={[styles.microcopy, themed.metaText, styles.perItemText]} numberOfLines={1}>
                  ({perItemPriceLabel} each)
                </Text>
              ) : null}
            </View>
          ) : null}

          {/* Right Side Controls */}
          <View style={styles.headerRight}>
            {countLabel ? (
              <View
                style={[
                  styles.countBadge,
                  {
                    backgroundColor: uiKitTheme.primary.main + '1A',
                    borderColor: uiKitTheme.primary.main + '33',
                  },
                ]}
                accessibilityRole="text"
                accessibilityLabel={`Count ${countLabel}`}
              >
                <Text style={[styles.countBadgeText, { color: uiKitTheme.primary.main }]} numberOfLines={1}>
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

        {/* Summary Content: Reusing ItemCard content via strict props */}
        {!isExpanded ? (
          <View style={styles.summary}>
            <Text style={[styles.summaryTitle, { color: uiKitTheme.text.primary }]} numberOfLines={3}>
              {summary.description}
            </Text>
            {(summary.sourceLabel || summary.sku || summary.locationLabel) ? (
              <View style={styles.summaryMeta}>
                {summary.sourceLabel ? (
                  <Text style={[styles.summaryMetaText, themed.metaText]} numberOfLines={1}>
                    <Text style={styles.metaStrong}>Source:</Text> {summary.sourceLabel}
                  </Text>
                ) : null}
                {summary.sku ? (
                  <Text style={[styles.summaryMetaText, themed.metaText]} numberOfLines={1}>
                    <Text style={styles.metaStrong}>SKU:</Text> {summary.sku}
                  </Text>
                ) : null}
                {summary.locationLabel ? (
                  <Text style={[styles.summaryMetaText, themed.metaText]} numberOfLines={2}>
                    <Text style={styles.metaStrong}>Location:</Text> {summary.locationLabel}
                  </Text>
                ) : null}
              </View>
            ) : null}
          </View>
        ) : null}
      </Pressable>

      {/* Expanded Children */}
      {isExpanded ? (
        <View style={[styles.childrenContainer, themed.childIndicator]}>
          {items.map((item, idx) => (
            <View key={`${item.description}-${idx}`} style={styles.childWrapper}>
              <ItemCard
                {...item}
                indexLabel={`${idx + 1}/${items.length}`}
                stackSkuAndSource
                style={[
                  idx < items.length - 1 ? { marginBottom: 12 } : null,
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
  },
  header: {
    padding: CARD_PADDING,
    gap: 0, // Gap handled by margin in summaryRow to match specific layout needs
  },
  headerTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: 8, // Spacing between top row and summary content
    minHeight: 24,
  },
  totalRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flexShrink: 1,
    minWidth: 0,
  },
  selector: {
    width: 18,
    height: 18,
    borderRadius: 9,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  selectorInner: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
  total: {
    fontSize: 13,
    fontWeight: '700',
    includeFontPadding: false,
  },
  perItemText: {
    fontStyle: 'normal',
    fontWeight: '500',
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 'auto',
    gap: 8,
  },
  countBadge: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
    borderWidth: 1,
  },
  countBadgeText: {
    fontSize: 12,
    fontWeight: '700',
    includeFontPadding: false,
  },
  microcopy: {
    fontSize: 12,
    fontWeight: '500',
    includeFontPadding: false,
    fontStyle: 'italic', // Often microcopy is italicized or distinct
  },
  chevron: {
    width: 22,
    height: 22,
    alignItems: 'center',
    justifyContent: 'center',
  },
  summaryRow: {
    // No specific styling needed, just container
  },
  summary: {
    gap: 8,
    paddingTop: 8,
  },
  summaryTitle: {
    fontSize: 15,
    fontWeight: '600',
    includeFontPadding: false,
    lineHeight: 20,
    paddingVertical: 2,
  },
  summaryMeta: {
    gap: 6,
  },
  summaryMetaText: {
    fontSize: 13,
    fontWeight: '500',
    includeFontPadding: false,
    lineHeight: 18,
  },
  metaStrong: {
    fontWeight: '700',
  },
  childrenContainer: {
    paddingTop: 12,
    paddingHorizontal: 12,
    paddingBottom: 12,
  },
  childWrapper: {
    // 
  },
});
