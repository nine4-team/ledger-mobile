import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';

import { BottomSheet } from './BottomSheet';
import { AppButton } from './AppButton';
import { AppText } from './AppText';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { getTextSecondaryStyle, textEmphasis } from '../ui/styles/typography';

export interface FormModalProps {
  visible: boolean;
  onRequestClose: () => void;
  title: string;
  /**
   * Optional description text shown below the title.
   */
  description?: string;
  /**
   * Form content (fields, inputs, etc.)
   */
  children: React.ReactNode;
  /**
   * Primary action button configuration.
   */
  primaryAction: {
    title: string;
    onPress: () => void | Promise<void>;
    loading?: boolean;
    disabled?: boolean;
  };
  /**
   * Optional secondary action button (typically Cancel).
   * If not provided, a default Cancel button will be shown that calls onRequestClose.
   */
  secondaryAction?: {
    title: string;
    onPress: () => void;
    disabled?: boolean;
  };
  /**
   * Optional error message to display above the action buttons.
   */
  error?: string;
  /**
   * Optional style override for the sheet container.
   */
  containerStyle?: ViewStyle;
}

/**
 * A standardized modal form component for creating/editing simple objects.
 * Provides consistent header, form content area, and action buttons.
 *
 * @example
 * ```tsx
 * <FormModal
 *   visible={isOpen}
 *   onRequestClose={() => setIsOpen(false)}
 *   title="New Budget Category"
 *   primaryAction={{
 *     title: "Create",
 *     onPress: handleCreate,
 *     loading: isSaving,
 *     disabled: !isValid,
 *   }}
 * >
 *   <TextInput ... />
 * </FormModal>
 * ```
 */
export function FormModal({
  visible,
  onRequestClose,
  title,
  description,
  children,
  primaryAction,
  secondaryAction,
  error,
  containerStyle,
}: FormModalProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const handleSecondary = secondaryAction?.onPress ?? onRequestClose;
  const secondaryTitle = secondaryAction?.title ?? 'Cancel';

  return (
    <BottomSheet visible={visible} onRequestClose={onRequestClose} containerStyle={containerStyle}>
      <View style={[styles.header, { borderBottomColor: uiKitTheme.border.secondary }]}>
        <View style={styles.headerContent}>
          <AppText variant="body" style={[styles.title, textEmphasis.strong]}>
            {title}
          </AppText>
          {description ? (
            <AppText variant="caption" style={[styles.description, getTextSecondaryStyle(uiKitTheme)]}>
              {description}
            </AppText>
          ) : null}
        </View>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Close"
          hitSlop={10}
          onPress={onRequestClose}
          style={({ pressed }) => [styles.closeButton, pressed && styles.pressed]}
        >
          <MaterialIcons name="close" size={22} color={theme.colors.textSecondary} />
        </Pressable>
      </View>

      <View style={styles.content}>
        {children}
      </View>

      {error ? (
        <View style={styles.errorContainer}>
          <AppText variant="caption" style={[styles.errorText, { color: uiKitTheme.status.missed.text }]}>
            {error}
          </AppText>
        </View>
      ) : null}

      <View style={styles.actions}>
        <AppButton
          title={secondaryTitle}
          variant="secondary"
          onPress={handleSecondary}
          disabled={secondaryAction?.disabled}
        />
        <AppButton
          title={primaryAction.title}
          onPress={primaryAction.onPress}
          loading={primaryAction.loading}
          disabled={primaryAction.disabled}
        />
      </View>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingTop: 6,
    paddingBottom: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  headerContent: {
    flex: 1,
    marginRight: 12,
  },
  title: {
    fontWeight: '700',
  },
  description: {
    marginTop: 4,
  },
  closeButton: {
    padding: 6,
    borderRadius: 999,
  },
  pressed: {
    opacity: 0.7,
  },
  content: {
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 6,
    gap: 12,
  },
  errorContainer: {
    paddingHorizontal: 16,
    paddingBottom: 6,
  },
  errorText: {
    fontSize: 13,
  },
  actions: {
    flexDirection: 'row',
    gap: 8,
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 6,
  },
});
