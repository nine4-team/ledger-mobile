import React, { useMemo } from 'react';
import { Pressable, StyleSheet, View, ViewStyle } from 'react-native';
import { AppText } from './AppText';
import { SelectorCircle } from './SelectorCircle';
import { useUIKitTheme } from '../theme/ThemeProvider';

export type MultiSelectPickerOption<T extends string> = {
  value: T;
  label: string;
  description?: string;
  icon?: React.ReactNode;
  accessibilityLabel?: string;
};

type Props<T extends string> = {
  /**
   * Selected value(s). For single-select mode, this is a single string.
   * For multi-select mode, this is an array of strings.
   */
  value: T | T[];
  /**
   * Available options to choose from.
   */
  options: readonly MultiSelectPickerOption<T>[];
  /**
   * Callback when selection changes.
   * For single-select mode, receives a single value.
   * For multi-select mode, receives an array of selected values.
   */
  onChange: (next: T | T[]) => void;
  /**
   * Whether multiple selections are allowed.
   * @default false
   */
  multiSelect?: boolean;
  /**
   * Optional label shown above the picker.
   */
  label?: string;
  /**
   * Optional helper text shown below the picker.
   */
  helperText?: string;
  /**
   * Accessibility label for the picker container.
   */
  accessibilityLabel?: string;
  /**
   * Optional style override for the container.
   */
  style?: ViewStyle;
};

/**
 * A modern, sleek multi-select picker component that can also be used for single-select.
 * Displays options as cards with selection indicators.
 *
 * @example
 * ```tsx
 * // Single-select mode
 * <MultiSelectPicker
 *   value={selectedType}
 *   onChange={setSelectedType}
 *   options={[
 *     { value: 'standard', label: 'Standard' },
 *     { value: 'itemized', label: 'Itemized' },
 *   ]}
 * />
 *
 * // Multi-select mode
 * <MultiSelectPicker
 *   value={selectedIds}
 *   onChange={setSelectedIds}
 *   multiSelect
 *   options={categories}
 * />
 * ```
 */
export function MultiSelectPicker<T extends string>({
  value,
  options,
  onChange,
  multiSelect = false,
  label,
  helperText,
  accessibilityLabel,
  style,
}: Props<T>) {
  const uiKitTheme = useUIKitTheme();

  const themedStyles = useMemo(
    () =>
      StyleSheet.create({
        optionCard: {
          backgroundColor: uiKitTheme.background.surface,
          borderColor: uiKitTheme.border.primary,
        },
        optionCardSelected: {
          backgroundColor: uiKitTheme.background.surface,
          borderColor: uiKitTheme.primary.main,
          borderWidth: 2,
        },
        optionCardPressed: {
          opacity: 0.7,
        },
        label: {
          color: uiKitTheme.text.secondary,
        },
        helperText: {
          color: uiKitTheme.text.secondary,
        },
        optionLabel: {
          color: uiKitTheme.text.primary,
        },
        optionDescription: {
          color: uiKitTheme.text.secondary,
        },
      }),
    [uiKitTheme]
  );

  const handleOptionPress = (optionValue: T) => {
    if (multiSelect) {
      const currentValues = Array.isArray(value) ? value : [];
      const isSelected = currentValues.includes(optionValue);
      if (isSelected) {
        // Deselect
        onChange(currentValues.filter((v) => v !== optionValue) as T[]);
      } else {
        // Select
        onChange([...currentValues, optionValue] as T[]);
      }
    } else {
      // Single-select mode
      onChange(optionValue);
    }
  };

  const isOptionSelected = (optionValue: T): boolean => {
    if (multiSelect) {
      return Array.isArray(value) && value.includes(optionValue);
    }
    return value === optionValue;
  };

  return (
    <View style={style} accessibilityLabel={accessibilityLabel}>
      {label ? (
        <AppText variant="caption" style={[styles.label, themedStyles.label]}>
          {label}
        </AppText>
      ) : null}
      <View style={styles.optionsContainer}>
        {options.map((option) => {
          const selected = isOptionSelected(option.value);
          return (
            <Pressable
              key={option.value}
              accessibilityRole={multiSelect ? 'checkbox' : 'radio'}
              accessibilityLabel={option.accessibilityLabel ?? option.label}
              accessibilityState={{ selected }}
              onPress={() => handleOptionPress(option.value)}
              style={({ pressed }) => [
                styles.optionCard,
                themedStyles.optionCard,
                selected && themedStyles.optionCardSelected,
                pressed && themedStyles.optionCardPressed,
              ]}
            >
              <View style={styles.optionContent}>
                <View style={styles.optionLeft}>
                  {option.icon ? <View style={styles.optionIcon}>{option.icon}</View> : null}
                  <View style={styles.optionTextContainer}>
                    <AppText variant="body" style={[styles.optionLabel, themedStyles.optionLabel]}>
                      {option.label}
                    </AppText>
                    {option.description ? (
                      <AppText variant="caption" style={[styles.optionDescription, themedStyles.optionDescription]}>
                        {option.description}
                      </AppText>
                    ) : null}
                  </View>
                </View>
                <SelectorCircle selected={selected} indicator="check" />
              </View>
            </Pressable>
          );
        })}
      </View>
      {helperText ? (
        <AppText variant="caption" style={[styles.helperText, themedStyles.helperText]}>
          {helperText}
        </AppText>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  label: {
    marginBottom: 8,
    fontSize: 13,
    fontWeight: '500',
  },
  optionsContainer: {
    gap: 10,
  },
  optionCard: {
    borderRadius: 12,
    borderWidth: 1,
    padding: 14,
    minHeight: 56,
  },
  optionContent: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  optionLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    marginRight: 12,
  },
  optionIcon: {
    marginRight: 12,
  },
  optionTextContainer: {
    flex: 1,
    gap: 4,
  },
  optionLabel: {
    fontSize: 15,
    fontWeight: '500',
  },
  optionDescription: {
    fontSize: 13,
    lineHeight: 18,
  },
  helperText: {
    marginTop: 8,
    fontSize: 13,
    lineHeight: 18,
  },
});
