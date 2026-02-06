import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';

export type DraggableCardProps = {
  title: string;
  disabled?: boolean;
  isActive?: boolean;
  dragHandleProps?: Record<string, unknown>;
  right?: React.ReactNode;
  style?: ViewStyle;
};

export function DraggableCard({
  title,
  disabled = false,
  isActive = false,
  dragHandleProps,
  right,
  style,
}: DraggableCardProps) {
  const uiKitTheme = useUIKitTheme();

  const themed = useMemo(
    () =>
      StyleSheet.create({
        title: {
          color: uiKitTheme.text.primary,
        },
        handleIcon: {
          color: uiKitTheme.primary.main,
        },
        handleIdle: {
          opacity: disabled ? 0.4 : 1,
        },
        handleActive: {
          opacity: 1,
        },
        titleDisabled: {
          opacity: 0.5,
        },
      }),
    [uiKitTheme, disabled]
  );

  return (
    <View style={[styles.row, style]}>
      <View style={styles.left}>
        <View
          accessibilityRole="button"
          accessibilityLabel={`Reorder ${title}`}
          // Note: drag behavior is attached via responder props from parent list.
          // We use a plain View (not Pressable) to avoid Pressable's internal responder logic
          // interfering with the ScrollView / responder system.
          {...(dragHandleProps ?? {})}
          style={[styles.iconButton, isActive ? themed.handleActive : themed.handleIdle]}
        >
          <MaterialIcons name="drag-indicator" size={20} color={themed.handleIcon.color} />
        </View>

        <AppText
          variant="body"
          style={[styles.title, themed.title, disabled && themed.titleDisabled]}
          numberOfLines={1}
        >
          {title}
        </AppText>
      </View>

      <View style={styles.right}>{right}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 4,
    height: 62,
  },
  left: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    minWidth: 0,
    gap: 8,
  },
  right: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginLeft: 10,
  },
  iconButton: {
    width: 36,
    height: 36,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: {
    flexShrink: 1,
    minWidth: 0,
    fontWeight: '500',
  },
});

