import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useUIKitTheme } from '@/theme/ThemeProvider';
import { FormBottomSheet } from '../FormBottomSheet';
import { FormField } from '../FormField';
import { AppText } from '../AppText';

export type CategoryFormData = {
  name: string;
  isItemized: boolean;
  isFee: boolean;
  excludeFromOverallBudget: boolean;
};

export type CategoryFormModalProps = {
  /**
   * Whether the modal is visible
   */
  visible: boolean;
  /**
   * Callback when the modal should close
   */
  onRequestClose: () => void;
  /**
   * Mode: 'create' or 'edit'
   */
  mode: 'create' | 'edit';
  /**
   * Initial form data (for edit mode)
   */
  initialData?: Partial<CategoryFormData>;
  /**
   * Callback when the form is saved
   */
  onSave: (data: CategoryFormData) => void | Promise<void>;
  /**
   * Whether the save operation is in progress
   */
  isSaving?: boolean;
  /**
   * Optional error message to display
   */
  error?: string;
};

/**
 * CategoryFormModal component provides a form for adding/editing budget categories.
 *
 * Features:
 * - Name field with validation (required, max 100 chars)
 * - Itemized toggle
 * - Fee toggle
 * - Exclude from overall budget toggle
 * - Mutually exclusive itemized/fee validation
 * - Modal UI with save/cancel actions
 *
 * Validation Rules:
 * - Name is required
 * - Name max length: 100 characters
 * - Itemized and Fee are mutually exclusive (cannot both be true)
 *
 * @example
 * ```tsx
 * <CategoryFormModal
 *   visible={isModalOpen}
 *   onRequestClose={() => setIsModalOpen(false)}
 *   mode="create"
 *   onSave={handleCreateCategory}
 *   isSaving={isSaving}
 * />
 * ```
 *
 * @example
 * ```tsx
 * <CategoryFormModal
 *   visible={isModalOpen}
 *   onRequestClose={() => setIsModalOpen(false)}
 *   mode="edit"
 *   initialData={{
 *     name: "Furnishings",
 *     isItemized: true,
 *     isFee: false,
 *     excludeFromOverallBudget: false,
 *   }}
 *   onSave={handleUpdateCategory}
 *   isSaving={isSaving}
 * />
 * ```
 */
export function CategoryFormModal({
  visible,
  onRequestClose,
  mode,
  initialData,
  onSave,
  isSaving,
  error,
}: CategoryFormModalProps) {
  const uiKitTheme = useUIKitTheme();

  // Form state
  const [name, setName] = useState('');
  const [isItemized, setIsItemized] = useState(false);
  const [isFee, setIsFee] = useState(false);
  const [excludeFromOverallBudget, setExcludeFromOverallBudget] = useState(false);

  // Validation state
  const [nameError, setNameError] = useState<string | undefined>(undefined);
  const [categoryTypeError, setCategoryTypeError] = useState<string | undefined>(undefined);

  // Initialize form data when modal opens or initialData changes
  useEffect(() => {
    if (visible) {
      setName(initialData?.name ?? '');
      setIsItemized(initialData?.isItemized ?? false);
      setIsFee(initialData?.isFee ?? false);
      setExcludeFromOverallBudget(initialData?.excludeFromOverallBudget ?? false);
      setNameError(undefined);
      setCategoryTypeError(undefined);
    }
  }, [visible, initialData]);

  // Validate name
  const validateName = useCallback((value: string): boolean => {
    if (!value.trim()) {
      setNameError('Category name is required');
      return false;
    }
    if (value.length > 100) {
      setNameError('Category name must be 100 characters or less');
      return false;
    }
    setNameError(undefined);
    return true;
  }, []);

  // Validate category type (itemized and fee are mutually exclusive)
  const validateCategoryType = useCallback((itemized: boolean, fee: boolean): boolean => {
    if (itemized && fee) {
      setCategoryTypeError('A category cannot be both Itemized and Fee');
      return false;
    }
    setCategoryTypeError(undefined);
    return true;
  }, []);

  // Handle name change
  const handleNameChange = useCallback((value: string) => {
    setName(value);
    if (nameError) {
      validateName(value);
    }
  }, [nameError, validateName]);

  // Handle itemized toggle
  const handleItemizedToggle = useCallback(() => {
    const nextItemized = !isItemized;
    setIsItemized(nextItemized);

    // If turning on itemized, turn off fee
    if (nextItemized && isFee) {
      setIsFee(false);
    }

    if (categoryTypeError) {
      validateCategoryType(nextItemized, isFee && !nextItemized);
    }
  }, [isItemized, isFee, categoryTypeError, validateCategoryType]);

  // Handle fee toggle
  const handleFeeToggle = useCallback(() => {
    const nextFee = !isFee;
    setIsFee(nextFee);

    // If turning on fee, turn off itemized
    if (nextFee && isItemized) {
      setIsItemized(false);
    }

    if (categoryTypeError) {
      validateCategoryType(isItemized && !nextFee, nextFee);
    }
  }, [isFee, isItemized, categoryTypeError, validateCategoryType]);

  // Handle exclude from overall budget toggle
  const handleExcludeToggle = useCallback(() => {
    setExcludeFromOverallBudget(!excludeFromOverallBudget);
  }, [excludeFromOverallBudget]);

  // Handle save
  const handleSave = useCallback(async () => {
    const isNameValid = validateName(name);
    const isCategoryTypeValid = validateCategoryType(isItemized, isFee);

    if (!isNameValid || !isCategoryTypeValid) {
      return;
    }

    await onSave({
      name: name.trim(),
      isItemized,
      isFee,
      excludeFromOverallBudget,
    });
  }, [name, isItemized, isFee, excludeFromOverallBudget, onSave, validateName, validateCategoryType]);

  // Compute whether form is valid
  const isValid = useMemo(() => {
    return (
      name.trim().length > 0 &&
      name.length <= 100 &&
      !(isItemized && isFee)
    );
  }, [name, isItemized, isFee]);

  // Themed styles
  const themedStyles = useMemo(
    () =>
      StyleSheet.create({
        toggleOnBg: {
          backgroundColor: uiKitTheme.button.primary.background ?? uiKitTheme.primary.main,
        },
        toggleOffBg: {
          backgroundColor: uiKitTheme.border.secondary,
        },
        toggleThumb: {
          backgroundColor: uiKitTheme.background.screen,
          shadowColor: uiKitTheme.shadow,
        },
        helperText: {
          color: uiKitTheme.text.secondary,
        },
        errorText: {
          color: uiKitTheme.status.missed.text,
        },
      }),
    [uiKitTheme]
  );

  const title = mode === 'create' ? 'New Budget Category' : 'Edit Budget Category';
  const saveButtonTitle = mode === 'create' ? 'Create' : 'Save';

  return (
    <FormBottomSheet
      visible={visible}
      onRequestClose={onRequestClose}
      title={title}
      primaryAction={{
        title: saveButtonTitle,
        onPress: handleSave,
        loading: isSaving,
        disabled: !isValid || isSaving,
      }}
      error={error}
    >
      {/* Name field */}
      <FormField
        label="Category Name"
        value={name}
        onChangeText={handleNameChange}
        placeholder="e.g., Furnishings, Install, Design Fee"
        errorText={nameError}
        inputProps={{
          maxLength: 100,
          autoFocus: mode === 'create',
        }}
      />

      {/* Itemized toggle */}
      <View style={styles.toggleField}>
        <View style={styles.toggleLabelRow}>
          <AppText variant="body" style={styles.toggleLabel}>
            Itemized
          </AppText>
          <Pressable
            accessibilityRole="switch"
            accessibilityState={{ checked: isItemized }}
            accessibilityLabel="Itemized toggle"
            onPress={handleItemizedToggle}
            hitSlop={8}
            style={({ pressed }) => [styles.toggleContainer, pressed && styles.pressed]}
          >
            <View style={[styles.toggle, isItemized ? themedStyles.toggleOnBg : themedStyles.toggleOffBg]}>
              <View
                style={[
                  styles.toggleThumb,
                  themedStyles.toggleThumb,
                  { transform: [{ translateX: isItemized ? 20 : 0 }] },
                ]}
              />
            </View>
          </Pressable>
        </View>
        <AppText variant="caption" style={[styles.helperText, themedStyles.helperText]}>
          Itemized categories track individual items and their costs
        </AppText>
      </View>

      {/* Fee toggle */}
      <View style={styles.toggleField}>
        <View style={styles.toggleLabelRow}>
          <AppText variant="body" style={styles.toggleLabel}>
            Fee
          </AppText>
          <Pressable
            accessibilityRole="switch"
            accessibilityState={{ checked: isFee }}
            accessibilityLabel="Fee toggle"
            onPress={handleFeeToggle}
            hitSlop={8}
            style={({ pressed }) => [styles.toggleContainer, pressed && styles.pressed]}
          >
            <View style={[styles.toggle, isFee ? themedStyles.toggleOnBg : themedStyles.toggleOffBg]}>
              <View
                style={[
                  styles.toggleThumb,
                  themedStyles.toggleThumb,
                  { transform: [{ translateX: isFee ? 20 : 0 }] },
                ]}
              />
            </View>
          </Pressable>
        </View>
        <AppText variant="caption" style={[styles.helperText, themedStyles.helperText]}>
          Fee categories track revenue (e.g., design fees, project fees)
        </AppText>
        {categoryTypeError ? (
          <AppText variant="caption" style={[styles.errorText, themedStyles.errorText]}>
            {categoryTypeError}
          </AppText>
        ) : null}
      </View>

      {/* Exclude from overall budget toggle */}
      <View style={styles.toggleField}>
        <View style={styles.toggleLabelRow}>
          <AppText variant="body" style={styles.toggleLabel}>
            Exclude from Overall Budget
          </AppText>
          <Pressable
            accessibilityRole="switch"
            accessibilityState={{ checked: excludeFromOverallBudget }}
            accessibilityLabel="Exclude from overall budget toggle"
            onPress={handleExcludeToggle}
            hitSlop={8}
            style={({ pressed }) => [styles.toggleContainer, pressed && styles.pressed]}
          >
            <View
              style={[
                styles.toggle,
                excludeFromOverallBudget ? themedStyles.toggleOnBg : themedStyles.toggleOffBg,
              ]}
            >
              <View
                style={[
                  styles.toggleThumb,
                  themedStyles.toggleThumb,
                  { transform: [{ translateX: excludeFromOverallBudget ? 20 : 0 }] },
                ]}
              />
            </View>
          </Pressable>
        </View>
        <AppText variant="caption" style={[styles.helperText, themedStyles.helperText]}>
          This category will not count toward the overall project budget
        </AppText>
      </View>
    </FormBottomSheet>
  );
}

const styles = StyleSheet.create({
  toggleField: {
    gap: 6,
  },
  toggleLabelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  toggleLabel: {
    fontWeight: '500',
  },
  toggleContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 4,
    paddingHorizontal: 2,
  },
  toggle: {
    width: 50,
    height: 30,
    borderRadius: 15,
    padding: 2,
    justifyContent: 'center',
  },
  toggleThumb: {
    width: 26,
    height: 26,
    borderRadius: 13,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
    elevation: 2,
  },
  pressed: {
    opacity: 0.7,
  },
  helperText: {
    marginTop: 2,
  },
  errorText: {
    marginTop: 4,
  },
});
