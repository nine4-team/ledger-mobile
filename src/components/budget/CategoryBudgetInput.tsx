import React, { useState, useEffect } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { AppText } from '../AppText';
import { useUIKitTheme } from '../../theme/ThemeProvider';
import { getTextInputStyle } from '../../ui/styles/forms';
import { getTextSecondaryStyle } from '../../ui/styles/typography';

export type CategoryBudgetInputProps = {
  /**
   * Category name to display as label
   */
  categoryName: string;
  /**
   * Current budget amount in cents
   * Null means no budget set
   */
  budgetCents: number | null;
  /**
   * Callback when budget value changes
   */
  onChange: (cents: number | null) => void;
  /**
   * Whether the input is disabled
   */
  disabled?: boolean;
};

/**
 * Format cents to currency string (e.g., 12345 -> "$123.45")
 */
function formatCurrency(cents: number | null): string {
  if (cents === null) return '';
  const dollars = cents / 100;
  return `$${dollars.toFixed(2)}`;
}

// Maximum budget amount in cents ($21,474,836.47 = 2^31 - 1 cents)
const MAX_BUDGET_CENTS = 2147483647;

/**
 * Parse currency string to cents
 * Handles formats like: "$123.45", "123.45", "$123", "123"
 * Returns null for invalid input
 * Validates:
 * - Non-negative amounts
 * - Maximum amount of $21,474,836.47 (2^31 - 1 cents)
 */
function parseCurrency(input: string): number | null {
  if (!input || input.trim() === '' || input.trim() === '$') return null;

  // Remove $ and commas
  const cleaned = input.replace(/[$,]/g, '').trim();

  // Parse as float
  const parsed = parseFloat(cleaned);

  // Return null if invalid or negative
  if (isNaN(parsed) || parsed < 0) return null;

  // Convert to cents
  const cents = Math.round(parsed * 100);

  // Cap at maximum value
  if (cents > MAX_BUDGET_CENTS) {
    return MAX_BUDGET_CENTS;
  }

  return cents;
}

/**
 * CategoryBudgetInput Component
 *
 * Input for entering budget amount for a single category.
 * Features:
 * - Currency formatting (auto-format on blur)
 * - Parse currency string to cents
 * - Validation for non-negative amounts
 *
 * @example
 * ```tsx
 * <CategoryBudgetInput
 *   categoryName="Furnishings"
 *   budgetCents={50000}
 *   onChange={(cents) => console.log('New budget:', cents)}
 * />
 * ```
 */
export function CategoryBudgetInput({
  categoryName,
  budgetCents,
  onChange,
  disabled = false,
}: CategoryBudgetInputProps) {
  const uiKitTheme = useUIKitTheme();
  const [inputValue, setInputValue] = useState(formatCurrency(budgetCents));
  const [isFocused, setIsFocused] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Update input value when budgetCents prop changes (external update)
  useEffect(() => {
    if (!isFocused) {
      setInputValue(formatCurrency(budgetCents));
    }
  }, [budgetCents, isFocused]);

  const handleFocus = () => {
    setIsFocused(true);
    // Remove formatting when user starts editing for easier input
    if (budgetCents !== null) {
      const dollars = (budgetCents / 100).toFixed(2);
      setInputValue(dollars);
    }
  };

  const handleBlur = () => {
    setIsFocused(false);
    setErrorMessage(null);

    // Check for empty input
    if (!inputValue || inputValue.trim() === '' || inputValue.trim() === '$') {
      onChange(null);
      setInputValue('');
      return;
    }

    // Remove $ and commas for validation
    const cleaned = inputValue.replace(/[$,]/g, '').trim();
    const parsed = parseFloat(cleaned);

    // Validate for negative amounts
    if (!isNaN(parsed) && parsed < 0) {
      setErrorMessage('Budget must be non-negative');
      setInputValue(formatCurrency(budgetCents));
      return;
    }

    // Validate for invalid input
    if (isNaN(parsed)) {
      setErrorMessage('Please enter a valid amount');
      setInputValue(formatCurrency(budgetCents));
      return;
    }

    // Parse and check for max value
    const cents = Math.round(parsed * 100);
    if (cents > MAX_BUDGET_CENTS) {
      setErrorMessage(`Budget cannot exceed $${(MAX_BUDGET_CENTS / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`);
      onChange(MAX_BUDGET_CENTS);
      setInputValue(formatCurrency(MAX_BUDGET_CENTS));
      return;
    }

    // Valid input
    onChange(cents);
    setInputValue(formatCurrency(cents));
  };

  const handleChangeText = (text: string) => {
    setInputValue(text);
  };

  const inputStyle = getTextInputStyle(uiKitTheme, {
    radius: 10,
    paddingVertical: 10,
    paddingHorizontal: 12,
  });

  return (
    <View style={styles.container}>
      <AppText variant="caption" style={[styles.label, getTextSecondaryStyle(uiKitTheme)]}>
        {categoryName}
      </AppText>
      <TextInput
        value={inputValue}
        onChangeText={handleChangeText}
        onFocus={handleFocus}
        onBlur={handleBlur}
        placeholder="$0.00"
        placeholderTextColor={uiKitTheme.input.placeholder}
        keyboardType="decimal-pad"
        editable={!disabled}
        style={[
          inputStyle,
          styles.input,
          disabled ? styles.disabledInput : null,
          errorMessage ? styles.inputError : null,
        ]}
      />
      {errorMessage && (
        <AppText variant="caption" style={styles.errorText}>
          {errorMessage}
        </AppText>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 6,
  },
  label: {
    fontSize: 14,
  },
  input: {
    fontSize: 16, // Prevents iOS zoom on focus
    minHeight: 44, // Minimum touch target height
  },
  disabledInput: {
    opacity: 0.6,
  },
  inputError: {
    borderColor: '#DC2626', // red-600
    borderWidth: 1,
  },
  errorText: {
    fontSize: 12,
    color: '#DC2626', // red-600
    marginTop: -2,
  },
});
