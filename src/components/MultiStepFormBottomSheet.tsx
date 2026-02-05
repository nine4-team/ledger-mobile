import React, { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';

import { BottomSheet } from './BottomSheet';
import { AppButton } from './AppButton';
import { AppText } from './AppText';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { getTextSecondaryStyle, textEmphasis } from '../ui/styles/typography';

export interface MultiStepFormBottomSheetProps {
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
   * Current step number (1-indexed).
   */
  currentStep: number;
  /**
   * Total number of steps.
   */
  totalSteps: number;
  /**
   * Primary action button configuration for the current step.
   */
  primaryAction: {
    title: string;
    onPress: () => void | Promise<void>;
    loading?: boolean;
    disabled?: boolean;
  };
  /**
   * Secondary action button configuration for the current step.
   * Typically "Cancel" on first step, "Back" on subsequent steps.
   */
  secondaryAction: {
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
 * A multi-step form bottom sheet component with step navigation.
 * Displays a step indicator below the action buttons with balanced spacing.
 *
 * @example
 * ```tsx
 * <MultiStepFormBottomSheet
 *   visible={isOpen}
 *   onRequestClose={() => setIsOpen(false)}
 *   title="New Budget Category"
 *   currentStep={1}
 *   totalSteps={2}
 *   primaryAction={{
 *     title: "Next",
 *     onPress: handleNextStep,
 *     disabled: !isValid,
 *   }}
 *   secondaryAction={{
 *     title: "Cancel",
 *     onPress: handleCancel,
 *   }}
 * >
 *   <FormField ... />
 * </MultiStepFormBottomSheet>
 * ```
 */
export function MultiStepFormBottomSheet({
  visible,
  onRequestClose,
  title,
  description,
  children,
  currentStep,
  totalSteps,
  primaryAction,
  secondaryAction,
  error,
  containerStyle,
}: MultiStepFormBottomSheetProps) {
  const uiKitTheme = useUIKitTheme();
  const themedStyles = useMemo(
    () => ({
      headerBorder: { borderBottomColor: uiKitTheme.border.secondary },
      actionsBorder: { borderTopColor: uiKitTheme.border.secondary },
      description: getTextSecondaryStyle(uiKitTheme),
      errorText: { color: uiKitTheme.status.missed.text },
      stepIndicator: getTextSecondaryStyle(uiKitTheme),
    }),
    [uiKitTheme]
  );

  return (
    <BottomSheet visible={visible} onRequestClose={onRequestClose} containerStyle={containerStyle}>
      <View style={[styles.header, themedStyles.headerBorder]}>
        <View style={styles.headerContent}>
          <AppText variant="body" style={[styles.title, textEmphasis.strong]}>
            {title}
          </AppText>
          {description ? (
            <AppText variant="caption" style={[styles.description, themedStyles.description]}>
              {description}
            </AppText>
          ) : null}
        </View>
      </View>

      <View style={styles.content}>
        {children}
      </View>

      {error ? (
        <View style={styles.errorContainer}>
          <AppText variant="caption" style={[styles.errorText, themedStyles.errorText]}>
            {error}
          </AppText>
        </View>
      ) : null}

      <View style={[styles.actions, themedStyles.actionsBorder]}>
        <AppButton
          title={secondaryAction.title}
          variant="secondary"
          onPress={secondaryAction.onPress}
          disabled={secondaryAction.disabled}
          style={styles.actionButton}
        />
        <AppButton
          title={primaryAction.title}
          onPress={primaryAction.onPress}
          loading={primaryAction.loading}
          disabled={primaryAction.disabled}
          style={styles.actionButton}
        />
      </View>

      <View style={styles.stepIndicatorContainer}>
        <AppText variant="caption" style={[styles.stepIndicator, themedStyles.stepIndicator]}>
          Step {currentStep} of {totalSteps}
        </AppText>
      </View>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  header: {
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  headerContent: {
    alignItems: 'center',
    width: '100%',
  },
  title: {
    fontWeight: '700',
    textAlign: 'center',
  },
  description: {
    marginTop: 4,
    textAlign: 'center',
  },
  content: {
    paddingHorizontal: 16,
    paddingTop: 24,
    paddingBottom: 24,
    gap: 16,
    minHeight: 80,
  },
  errorContainer: {
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 8,
  },
  errorText: {
    fontSize: 13,
  },
  actions: {
    flexDirection: 'row',
    gap: 8,
    paddingHorizontal: 16,
    paddingTop: 20,
    paddingBottom: 16,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  actionButton: {
    flex: 1,
  },
  stepIndicatorContainer: {
    paddingHorizontal: 16,
    paddingBottom: 20,
    alignItems: 'center',
  },
  stepIndicator: {
    fontSize: 13,
  },
});
