import React, { useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { AppButton } from '../AppButton';
import { AppText } from '../AppText';
import { BottomSheet } from '../BottomSheet';
import { CategoryPickerList } from './CategoryPickerList';
import { useTheme } from '../../theme/ThemeProvider';

export interface SellToBusinessModalProps {
  visible: boolean;
  onRequestClose: () => void;
  /** Budget categories for the source category picker. */
  sourceBudgetCategories: Record<string, { name: string }>;
  /** Whether to show the source category picker (when some items lack budgetCategoryId). */
  showSourceCategoryPicker: boolean;
  /** Called with the selected source category. Caller does the sale operation. */
  onConfirm: (sourceCategoryId: string | null) => void;
  /** Optional subtitle like "3 items selected" */
  subtitle?: string;
}

export function SellToBusinessModal({
  visible,
  onRequestClose,
  sourceBudgetCategories,
  showSourceCategoryPicker,
  onConfirm,
  subtitle,
}: SellToBusinessModalProps) {
  const theme = useTheme();
  const [sourceCategoryId, setSourceCategoryId] = useState<string | null>(null);

  const handleClose = () => {
    setSourceCategoryId(null);
    onRequestClose();
  };

  const handleConfirm = () => {
    onConfirm(sourceCategoryId);
    setSourceCategoryId(null);
  };

  return (
    <BottomSheet visible={visible} onRequestClose={handleClose}>
      <View style={styles.titleRow}>
        <AppText variant="body" style={styles.title}>Sell to Business</AppText>
        {subtitle ? (
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {subtitle}
          </AppText>
        ) : null}
      </View>
      <View style={styles.content}>
        <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
          This will move items from the project into business inventory.
          A sale record will be created for financial tracking.
          If you're just fixing a misallocation, use Reassign instead.
        </AppText>

        {showSourceCategoryPicker && (
          <View style={styles.fieldGroup}>
            <AppText variant="caption" style={styles.fieldLabel}>
              Choose Budget Category (for uncategorized items)
            </AppText>
            <CategoryPickerList
              categories={sourceBudgetCategories}
              selectedId={sourceCategoryId}
              onSelect={setSourceCategoryId}
            />
          </View>
        )}

        <AppButton
          title="Confirm Sale"
          variant="primary"
          onPress={handleConfirm}
          style={styles.button}
        />
      </View>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  titleRow: {
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 12,
    gap: 4,
  },
  title: {
    fontWeight: '700',
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 16,
    gap: 12,
  },
  fieldGroup: {
    gap: 12,
    marginTop: 8,
  },
  fieldLabel: {
    fontWeight: '600',
  },
  button: {
    minHeight: 44,
  },
});
