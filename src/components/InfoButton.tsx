import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useMemo, useState } from 'react';
import { Modal, Pressable, StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';
import { useTheme, useUIKitTheme } from '@/theme/ThemeProvider';
import { getCardStyle, getTextPrimaryStyle, getTextSecondaryStyle } from '../ui';
import { AppButton } from './AppButton';
import { AppText } from './AppText';

export type InfoDialogContent = {
  title: string;
  message: string;
};

export type InfoButtonProps = {
  accessibilityLabel: string;
  content: InfoDialogContent;
  iconColor?: string;
  iconSize?: number;
  hitSlop?: number;
  style?: ViewStyle;
  /**
   * Optional hook for analytics/logging. Called when the button is tapped
   * (before the dialog opens).
   */
  onPress?: () => void;
};

export function InfoButton({
  accessibilityLabel,
  content,
  iconColor,
  iconSize = 18,
  hitSlop = 10,
  style,
  onPress,
}: InfoButtonProps) {
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const [visible, setVisible] = useState(false);

  const themed = useMemo(
    () =>
      StyleSheet.create({
        backdrop: {
          flex: 1,
          backgroundColor: 'rgba(0,0,0,0.45)',
          alignItems: 'center',
          justifyContent: 'center',
          padding: theme.spacing.lg,
        },
        dialog: {
          width: '100%',
          maxWidth: 460,
          ...getCardStyle(uiKitTheme, { radius: 14, padding: theme.spacing.lg }),
        },
        headerRow: {
          flexDirection: 'row',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 12,
          marginBottom: 10,
        },
        titleRow: {
          flexDirection: 'row',
          alignItems: 'center',
          gap: 10,
          flex: 1,
          minWidth: 0,
        },
        title: {
          flexShrink: 1,
          minWidth: 0,
          fontWeight: '700',
          ...getTextPrimaryStyle(uiKitTheme),
        },
        message: {
          ...getTextSecondaryStyle(uiKitTheme),
          marginBottom: theme.spacing.lg,
        },
        closeIconButton: {
          padding: 6,
          borderRadius: 10,
          alignItems: 'center',
          justifyContent: 'center',
        },
        iconButton: {
          padding: 6,
          borderRadius: 8,
          alignItems: 'center',
          justifyContent: 'center',
        },
        pressed: {
          opacity: 0.7,
        },
      }),
    [theme.spacing.lg, uiKitTheme]
  );

  return (
    <>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        hitSlop={hitSlop}
        style={({ pressed }) => [themed.iconButton, pressed && themed.pressed, style]}
        onPress={() => {
          onPress?.();
          setVisible(true);
        }}
      >
        <MaterialIcons name="info-outline" size={iconSize} color={iconColor ?? uiKitTheme.primary.main} />
      </Pressable>

      <Modal
        visible={visible}
        transparent
        animationType="fade"
        onRequestClose={() => setVisible(false)}
      >
        <Pressable style={themed.backdrop} onPress={() => setVisible(false)}>
          <View
            style={themed.dialog}
            accessibilityLabel={content.title}
            accessibilityHint="Info dialog"
            accessibilityViewIsModal
          >
            <View style={themed.headerRow}>
              <View style={themed.titleRow}>
                <MaterialIcons name="info-outline" size={20} color={uiKitTheme.primary.main} />
                <AppText variant="body" style={themed.title} numberOfLines={2}>
                  {content.title}
                </AppText>
              </View>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Close info"
                hitSlop={10}
                style={({ pressed }) => [themed.closeIconButton, pressed && themed.pressed]}
                onPress={() => setVisible(false)}
              >
                <MaterialIcons name="close" size={20} color={uiKitTheme.text.secondary} />
              </Pressable>
            </View>

            <AppText variant="body" style={themed.message}>
              {content.message}
            </AppText>

            <AppButton title="Got it" variant="secondary" onPress={() => setVisible(false)} />
          </View>
        </Pressable>
      </Modal>
    </>
  );
}

