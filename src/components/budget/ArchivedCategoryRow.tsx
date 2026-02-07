import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useMemo } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { ViewStyle } from 'react-native';

import { AppText } from '../AppText';

import { useUIKitTheme } from '@/theme/ThemeProvider';

export type ArchivedCategoryRowProps = {
  /**
   * Category ID for reference
   */
  id: string;
  /**
   * Category name to display
   */
  name: string;
  /**
   * Whether the category is itemized (shows badge)
   */
  isItemized?: boolean;
  /**
   * Whether the category is a fee (shows badge)
   */
  isFee?: boolean;
  /**
   * Whether the category is excluded from overall budget (shows badge)
   */
  excludeFromOverallBudget?: boolean;
  /**
   * Callback when unarchive action is pressed
   */
  onUnarchive?: () => void;
  /**
   * Optional style override
   */
  style?: ViewStyle;
};

/**
 * ArchivedCategoryRow component displays an archived budget category in a grayed-out style with an unarchive action.
 *
 * Features:
 * - Grayed-out appearance to indicate archived status
 * - Category name display
 * - Metadata badges (itemized, fee, excluded from overall)
 * - Unarchive action button
 *
 * @example
 * ```tsx
 * <ArchivedCategoryRow
 *   id="old-category"
 *   name="Old Category"
 *   isItemized={true}
 *   onUnarchive={() => handleUnarchive('old-category')}
 * />
 * ```
 */
export function ArchivedCategoryRow({
  id: _id,
  name,
  isItemized,
  isFee,
  excludeFromOverallBudget,
  onUnarchive,
  style,
}: ArchivedCategoryRowProps) {
  const uiKitTheme = useUIKitTheme();

  const themed = useMemo(
    () =>
      StyleSheet.create({
        title: {
          color: uiKitTheme.text.secondary,
        },
        badge: {
          backgroundColor: uiKitTheme.text.secondary + '10',
          borderColor: uiKitTheme.text.secondary + '20',
        },
        badgeText: {
          color: uiKitTheme.text.secondary,
        },
        icon: {
          color: uiKitTheme.button.icon.icon,
        },
      }),
    [uiKitTheme]
  );

  const hasBadges = isItemized || isFee || excludeFromOverallBudget;

  return (
    <View style={[styles.row, style]}>
      <View style={styles.left}>
        {/* Archive icon (non-interactive) */}
        <View style={styles.iconContainer}>
          <MaterialIcons name="archive" size={18} color={uiKitTheme.text.secondary} />
        </View>

        {/* Category name */}
        <View style={styles.nameContainer}>
          <AppText
            variant="body"
            style={[styles.title, themed.title]}
            numberOfLines={1}
          >
            {name}
          </AppText>

          {/* Metadata badges */}
          {hasBadges ? (
            <View style={styles.badgesRow}>
              {isItemized ? (
                <View style={[styles.badge, themed.badge]}>
                  <Text style={[styles.badgeText, themed.badgeText]} numberOfLines={1}>
                    Itemized
                  </Text>
                </View>
              ) : null}

              {isFee ? (
                <View style={[styles.badge, themed.badge]}>
                  <Text style={[styles.badgeText, themed.badgeText]} numberOfLines={1}>
                    Fee
                  </Text>
                </View>
              ) : null}

              {excludeFromOverallBudget ? (
                <View style={[styles.badge, themed.badge]}>
                  <Text style={[styles.badgeText, themed.badgeText]} numberOfLines={1}>
                    Excluded
                  </Text>
                </View>
              ) : null}
            </View>
          ) : null}
        </View>
      </View>

      {/* Unarchive button */}
      <View style={styles.right}>
        {onUnarchive ? (
          <Pressable
            onPress={onUnarchive}
            hitSlop={8}
            accessibilityRole="button"
            accessibilityLabel={`Unarchive ${name}`}
            style={({ pressed }) => [styles.actionButton, pressed && styles.pressed]}
          >
            <MaterialIcons name="unarchive" size={20} color={themed.icon.color} />
          </Pressable>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 4,
    minHeight: 56,
    opacity: 0.6,
  },
  left: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    minWidth: 0,
    gap: 8,
  },
  iconContainer: {
    width: 36,
    height: 36,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  nameContainer: {
    flex: 1,
    minWidth: 0,
    gap: 6,
  },
  title: {
    flexShrink: 1,
    minWidth: 0,
    fontWeight: '500',
  },
  badgesRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
    alignItems: 'center',
  },
  badge: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    borderWidth: 1,
  },
  badgeText: {
    fontSize: 11,
    fontWeight: '600',
    includeFontPadding: false,
  },
  right: {
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 10,
  },
  actionButton: {
    padding: 6,
    minWidth: 32,
    minHeight: 32,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
  },
  pressed: {
    opacity: 0.7,
  },
});
