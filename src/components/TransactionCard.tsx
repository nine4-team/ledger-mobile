import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { StyleProp, ViewStyle } from 'react-native';

import { useUIKitTheme } from '../theme/ThemeProvider';
import { CARD_PADDING, CARD_BORDER_WIDTH, getCardBaseStyle, getCardBorderStyle } from '../ui';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import { SelectorCircle } from './SelectorCircle';

export type TransactionCardProps = {
  // Core transaction data
  id: string;
  source: string;
  amountCents: number | null;
  transactionDate?: string;
  notes?: string;

  // Status and categorization
  budgetCategoryName?: string;
  budgetCategoryColor?: string; // Hex color for category badge
  transactionType?: 'purchase' | 'return' | 'sale' | 'to-inventory';
  needsReview?: boolean;
  reimbursementType?: 'owed-to-client' | 'owed-to-company';
  purchasedBy?: string; // 'client-card' | 'design-business' | etc.

  // Receipt and status
  hasEmailReceipt?: boolean;
  status?: 'pending' | 'completed' | 'canceled';

  // Interaction
  selected?: boolean;
  defaultSelected?: boolean;
  onSelectedChange?: (selected: boolean) => void;

  bookmarked?: boolean;
  onBookmarkPress?: () => void;

  onMenuPress?: () => void;
  menuItems?: AnchoredMenuItem[];
  onPress?: () => void;

  style?: StyleProp<ViewStyle>;
};

function formatCurrency(cents: number | null): string {
  if (cents === null || cents === undefined) return 'No amount';
  return `$${(cents / 100).toFixed(2)}`;
}

function formatDate(dateString?: string): string {
  if (!dateString) return 'No date';
  try {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  } catch {
    return dateString;
  }
}


export function TransactionCard({
  id,
  source,
  amountCents,
  transactionDate,
  notes,
  budgetCategoryName,
  budgetCategoryColor,
  transactionType,
  needsReview,
  reimbursementType,
  purchasedBy,
  hasEmailReceipt,
  status,
  selected,
  defaultSelected,
  onSelectedChange,
  bookmarked,
  onBookmarkPress,
  onMenuPress,
  menuItems,
  onPress,
  style,
}: TransactionCardProps) {
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
        header: {
          borderBottomColor: uiKitTheme.border.secondary,
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
        amount: {
          color: uiKitTheme.text.primary,
        },
        divider: {
          borderBottomColor: uiKitTheme.border.secondary,
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

  // Badge colors based on transaction type
  const typeBadgeStyle = useMemo(() => {
    switch (transactionType) {
      case 'purchase':
        return {
          backgroundColor: '#10b98133', // green with opacity
          borderColor: '#10b98166',
          textColor: '#059669',
        };
      case 'sale':
        return {
          backgroundColor: '#3b82f633', // blue with opacity
          borderColor: '#3b82f666',
          textColor: '#2563eb',
        };
      case 'return':
        return {
          backgroundColor: '#ef444433', // red with opacity
          borderColor: '#ef444466',
          textColor: '#dc2626',
        };
      case 'to-inventory':
        return {
          backgroundColor: uiKitTheme.primary.main + '1A',
          borderColor: uiKitTheme.primary.main + '33',
          textColor: uiKitTheme.primary.main,
        };
      default:
        return null;
    }
  }, [transactionType, uiKitTheme.primary.main]);

  const categoryBadgeStyle = useMemo(() => {
    if (!budgetCategoryColor) {
      return {
        backgroundColor: uiKitTheme.primary.main + '1A',
        borderColor: uiKitTheme.primary.main + '33',
        textColor: uiKitTheme.primary.main,
      };
    }
    return {
      backgroundColor: budgetCategoryColor + '33',
      borderColor: budgetCategoryColor + '66',
      textColor: budgetCategoryColor,
    };
  }, [budgetCategoryColor, uiKitTheme.primary.main]);

  const getTypeLabel = () => {
    if (!transactionType) return null;
    switch (transactionType) {
      case 'purchase':
        return 'Purchase';
      case 'sale':
        return 'Sale';
      case 'return':
        return 'Return';
      case 'to-inventory':
        return 'To Inventory';
      default:
        return null;
    }
  };

  const amountLabel = formatCurrency(amountCents);
  const dateLabel = formatDate(transactionDate);
  const typeLabel = getTypeLabel();

  return (
    <>
      <Pressable
        onPress={onPress}
        disabled={!onPress}
        accessibilityRole={onPress ? 'button' : 'none'}
        accessibilityLabel={`Transaction card: ${source}`}
        style={({ pressed }) => [
          styles.card,
          getCardBaseStyle({ radius: 16 }),
          getCardBorderStyle(uiKitTheme),
          themed.card,
          pressed && onPress ? styles.cardPressed : null,
          style,
        ]}
      >
        {/* Header with selector, badges, and actions */}
        <View style={[styles.header, themed.header]}>
          {(onSelectedChange || typeof selected === 'boolean' || defaultSelected) ? (
            <Pressable
              onPress={(e) => {
                e.stopPropagation();
                setSelected(!isSelected);
              }}
              accessibilityRole="checkbox"
              accessibilityLabel={`Select ${source}`}
              accessibilityState={{ checked: isSelected }}
              hitSlop={13}
              style={styles.selectorContainer}
            >
              <SelectorCircle selected={isSelected} indicator="dot" />
            </Pressable>
          ) : null}

          <View style={styles.headerSpacer} />

          {/* Badges in header - right side, specific order */}
          {(budgetCategoryName || typeLabel || needsReview || reimbursementType || hasEmailReceipt) ? (
            <View style={styles.headerBadgesRow}>
              {typeLabel && typeBadgeStyle ? (
                <View
                  style={[
                    styles.badge,
                    {
                      backgroundColor: typeBadgeStyle.backgroundColor,
                      borderColor: typeBadgeStyle.borderColor,
                    },
                  ]}
                >
                  <Text style={[styles.badgeText, { color: typeBadgeStyle.textColor }]} numberOfLines={1}>
                    {typeLabel}
                  </Text>
                </View>
              ) : null}

              {reimbursementType === 'owed-to-client' ? (
                <View
                  style={[
                    styles.badge,
                    {
                      backgroundColor: '#f59e0b33',
                      borderColor: '#f59e0b66',
                    },
                  ]}
                >
                  <Text style={[styles.badgeText, { color: '#d97706' }]} numberOfLines={1}>
                    Owed to Client
                  </Text>
                </View>
              ) : null}

              {reimbursementType === 'owed-to-company' ? (
                <View
                  style={[
                    styles.badge,
                    {
                      backgroundColor: '#f59e0b33',
                      borderColor: '#f59e0b66',
                    },
                  ]}
                >
                  <Text style={[styles.badgeText, { color: '#d97706' }]} numberOfLines={1}>
                    Owed to Business
                  </Text>
                </View>
              ) : null}

              {hasEmailReceipt ? (
                <View
                  style={[
                    styles.badge,
                    {
                      backgroundColor: uiKitTheme.primary.main + '1A',
                      borderColor: uiKitTheme.primary.main + '33',
                    },
                  ]}
                >
                  <Text style={[styles.badgeText, { color: uiKitTheme.primary.main }]} numberOfLines={1}>
                    Receipt
                  </Text>
                </View>
              ) : null}

              {needsReview ? (
                <View
                  style={[
                    styles.badge,
                    {
                      backgroundColor: '#ef444433',
                      borderColor: '#ef444466',
                    },
                  ]}
                >
                  <Text style={[styles.badgeText, { color: '#ef4444' }]} numberOfLines={1}>
                    Needs Review
                  </Text>
                </View>
              ) : null}

              {budgetCategoryName ? (
                <View
                  style={[
                    styles.badge,
                    {
                      backgroundColor: categoryBadgeStyle.backgroundColor,
                      borderColor: categoryBadgeStyle.borderColor,
                    },
                  ]}
                >
                  <Text
                    style={[styles.badgeText, { color: categoryBadgeStyle.textColor }]}
                    numberOfLines={1}
                  >
                    {budgetCategoryName}
                  </Text>
                </View>
              ) : null}
            </View>
          ) : null}

          <View style={styles.headerRight}>
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

        {/* Main content area */}
        <View style={styles.content}>
          {/* Source/Title row with amount */}
          <View style={styles.topRow}>
            <View style={styles.sourceContainer}>
              <Text style={[styles.source, themed.description]} numberOfLines={2}>
                {source || `Transaction ${id.slice(0, 6)}`}
              </Text>
            </View>
            <Text style={[styles.amount, themed.amount]} numberOfLines={1}>
              {amountLabel}
            </Text>
          </View>

          {/* Transaction details row */}
          <View style={styles.detailsRow}>
            <Text style={[styles.metaText, themed.metaText]} numberOfLines={1}>
              {dateLabel}
            </Text>
          </View>

          {/* Notes if present */}
          {notes ? (
            <Text style={[styles.notes, themed.metaText]} numberOfLines={2}>
              {notes}
            </Text>
          ) : null}
        </View>
      </Pressable>

      {!onMenuPress && menuItems && menuItems.length > 0 ? (
        <BottomSheetMenuList
          visible={menuVisible}
          onRequestClose={closeMenu}
          items={menuItems}
          title={source}
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
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: CARD_PADDING,
    paddingVertical: 12,
    borderBottomWidth: 1,
    gap: 12,
  },
  headerBadgesRow: {
    flexDirection: 'row',
    gap: 8,
    alignItems: 'center',
  },
  headerSpacer: {
    flex: 1,
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  iconButton: {
    padding: 6,
    minWidth: 32,
    minHeight: 32,
    alignItems: 'center',
    justifyContent: 'center',
  },
  selectorContainer: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  content: {
    padding: CARD_PADDING,
    gap: 12,
  },
  topRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
  },
  sourceContainer: {
    flex: 1,
    minWidth: 0,
  },
  source: {
    fontSize: 16,
    fontWeight: '600',
    includeFontPadding: false,
    lineHeight: 22,
  },
  amount: {
    fontSize: 16,
    fontWeight: '700',
    includeFontPadding: false,
    lineHeight: 22,
    flexShrink: 0,
  },
  detailsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
  },
  metaText: {
    fontSize: 13,
    fontWeight: '500',
    includeFontPadding: false,
    lineHeight: 18,
  },
  notes: {
    fontSize: 13,
    fontWeight: '400',
    includeFontPadding: false,
    lineHeight: 18,
    fontStyle: 'italic',
  },
  badge: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 999,
    borderWidth: 1,
    maxWidth: 160,
  },
  badgeText: {
    fontSize: 12,
    fontWeight: '600',
    includeFontPadding: false,
  },
});
