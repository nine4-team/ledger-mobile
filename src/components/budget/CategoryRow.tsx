import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useMemo } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { ViewStyle } from 'react-native';

import { useUIKitTheme } from '@/theme/ThemeProvider';
import { AppText } from '../AppText';

export type CategoryRowProps = {
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
   * Whether the category is archived (affects styling)
   */
  isArchived?: boolean;
  /**
   * Whether the row is currently being dragged
   */
  isActive?: boolean;
  /**
   * Props to attach to the drag handle for drag-and-drop functionality
   */
  dragHandleProps?: Record<string, unknown>;
  /**
   * Callback when edit action is pressed
   */
  onEdit?: () => void;
  /**
   * Callback when archive/unarchive action is pressed
   */
  onArchive?: () => void;
  /**
   * Optional style override
   */
  style?: ViewStyle;
};

/**
 * CategoryRow component displays a budget category with drag handle, name, metadata badges, and action buttons.
 *
 * Features:
 * - Drag handle for reordering
 * - Category name display
 * - Metadata badges (itemized, fee, excluded from overall)
 * - Edit and archive action buttons
 * - Dragging state styling
 *
 * @example
 * ```tsx
 * <CategoryRow
 *   id="furnishings"
 *   name="Furnishings"
 *   isItemized={true}
 *   excludeFromOverallBudget={false}
 *   onEdit={() => handleEdit('furnishings')}
 *   onArchive={() => handleArchive('furnishings')}
 * />
 * ```
 */
export function CategoryRow({
  id,
  name,
  isItemized,
  isFee,
  excludeFromOverallBudget,
  isArchived,
  isActive,
  dragHandleProps,
  onEdit,
  onArchive,
  style,
}: CategoryRowProps) {
  const uiKitTheme = useUIKitTheme();

  const themed = useMemo(
    () =>
      StyleSheet.create({
        title: {
          color: isArchived ? uiKitTheme.text.secondary : uiKitTheme.text.primary,
        },
        handleIcon: {
          color: uiKitTheme.primary.main,
        },
        handleIdle: {
          opacity: isArchived ? 0.4 : 1,
        },
        handleActive: {
          opacity: 1,
        },
        badge: {
          backgroundColor: uiKitTheme.primary.main + '1A',
          borderColor: uiKitTheme.primary.main + '33',
        },
        badgeText: {
          color: uiKitTheme.primary.main,
        },
        excludeBadge: {
          backgroundColor: uiKitTheme.text.secondary + '1A',
          borderColor: uiKitTheme.text.secondary + '33',
        },
        excludeBadgeText: {
          color: uiKitTheme.text.secondary,
        },
        icon: {
          color: uiKitTheme.button.icon.icon,
        },
      }),
    [uiKitTheme, isArchived]
  );

  const hasBadges = isItemized || isFee || excludeFromOverallBudget;

  return (
    <View style={[styles.row, style]}>
      <View style={styles.left}>
        {/* Drag handle */}
        <View
          accessibilityRole="button"
          accessibilityLabel={`Reorder ${name}`}
          {...(dragHandleProps ?? {})}
          style={[styles.iconButton, isActive ? themed.handleActive : themed.handleIdle]}
        >
          <MaterialIcons name="drag-indicator" size={20} color={themed.handleIcon.color} />
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
                <View style={[styles.badge, themed.excludeBadge]}>
                  <Text style={[styles.badgeText, themed.excludeBadgeText]} numberOfLines={1}>
                    Excluded
                  </Text>
                </View>
              ) : null}
            </View>
          ) : null}
        </View>
      </View>

      {/* Action buttons */}
      <View style={styles.right}>
        {onEdit ? (
          <Pressable
            onPress={onEdit}
            hitSlop={8}
            accessibilityRole="button"
            accessibilityLabel={`Edit ${name}`}
            style={({ pressed }) => [styles.actionButton, pressed && styles.pressed]}
          >
            <MaterialIcons name="edit" size={20} color={themed.icon.color} />
          </Pressable>
        ) : null}

        {onArchive ? (
          <Pressable
            onPress={onArchive}
            hitSlop={8}
            accessibilityRole="button"
            accessibilityLabel={isArchived ? `Unarchive ${name}` : `Archive ${name}`}
            style={({ pressed }) => [styles.actionButton, pressed && styles.pressed]}
          >
            <MaterialIcons
              name={isArchived ? 'unarchive' : 'archive'}
              size={20}
              color={themed.icon.color}
            />
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
    minHeight: 62,
  },
  left: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    minWidth: 0,
    gap: 8,
  },
  iconButton: {
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
    gap: 6,
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
