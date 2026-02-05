import React, { useMemo } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import type { TextInputProps } from 'react-native';

import { AppText } from './AppText';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { getTextInputStyle } from '../ui/styles/forms';
import { getTextSecondaryStyle } from '../ui/styles/typography';

export interface FormFieldProps {
  /**
   * Label text shown above the input.
   */
  label: string;
  /**
   * Current value of the input.
   */
  value: string;
  /**
   * Callback when the value changes.
   */
  onChangeText: (text: string) => void;
  /**
   * Placeholder text.
   */
  placeholder?: string;
  /**
   * Whether the input is disabled.
   */
  disabled?: boolean;
  /**
   * Optional error message shown below the input.
   */
  errorText?: string;
  /**
   * Optional helper text shown below the input (when no error).
   */
  helperText?: string;
  /**
   * Additional TextInput props.
   */
  inputProps?: Omit<TextInputProps, 'value' | 'onChangeText' | 'editable' | 'placeholder' | 'style'>;
}

/**
 * A standardized form field component with label, input, and optional error/helper text.
 *
 * @example
 * ```tsx
 * <FormField
 *   label="Category Name"
 *   value={name}
 *   onChangeText={setName}
 *   placeholder="Enter category name"
 *   errorText={errors.name}
 *   helperText="This will appear in budget reports"
 * />
 * ```
 */
export function FormField({
  label,
  value,
  onChangeText,
  placeholder,
  disabled,
  errorText,
  helperText,
  inputProps,
}: FormFieldProps) {
  const uiKitTheme = useUIKitTheme();

  const inputStyle = useMemo(
    () =>
      getTextInputStyle(uiKitTheme, {
        radius: 10,
        paddingVertical: 10,
        paddingHorizontal: 12,
      }),
    [uiKitTheme]
  );

  return (
    <View style={styles.container}>
      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
        {label}
      </AppText>
      <TextInput
        placeholder={placeholder}
        value={value}
        onChangeText={onChangeText}
        editable={!disabled}
        style={[
          inputStyle,
          disabled ? styles.disabledInput : null,
          errorText ? { borderColor: uiKitTheme.status.missed.text } : null,
        ]}
        placeholderTextColor={uiKitTheme.input.placeholder}
        autoCorrect={false}
        {...inputProps}
      />
      {errorText ? (
        <AppText variant="caption" style={[styles.helperText, { color: uiKitTheme.status.missed.text }]}>
          {errorText}
        </AppText>
      ) : helperText ? (
        <AppText variant="caption" style={[styles.helperText, getTextSecondaryStyle(uiKitTheme)]}>
          {helperText}
        </AppText>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 6,
  },
  disabledInput: {
    opacity: 0.6,
  },
  helperText: {
    marginTop: 2,
  },
});
