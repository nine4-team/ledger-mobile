import React, { useCallback, useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { AppButton } from '../AppButton';
import { AppText } from '../AppText';
import { BottomSheet } from '../BottomSheet';
import { ProjectSelector } from '../ProjectSelector';
import { CategoryPickerList } from './CategoryPickerList';
import { useTheme } from '../../theme/ThemeProvider';

export interface SellToProjectModalProps {
  visible: boolean;
  onRequestClose: () => void;
  accountId: string;
  excludeProjectId?: string;
  /** Budget categories available in the destination project. Updated by caller via onTargetProjectChange. */
  destBudgetCategories: Record<string, { name: string }>;
  /** Budget categories for the source project (used for uncategorized items). */
  sourceBudgetCategories: Record<string, { name: string }>;
  /** Whether the source category picker should be shown. */
  showSourceCategoryPicker: boolean;
  /** Whether the destination category picker should be shown. */
  showDestCategoryPicker: boolean;
  /** Called with all selections. Caller does the sale operation(s). */
  onConfirm: (params: {
    targetProjectId: string;
    destCategoryId: string | null;
    sourceCategoryId: string | null;
  }) => void;
  /** Optional subtitle like "3 items selected" */
  subtitle?: string;
  /** Called when the user picks a target project — caller should load dest budget categories. */
  onTargetProjectChange?: (projectId: string | null) => void;
}

export function SellToProjectModal({
  visible,
  onRequestClose,
  accountId,
  excludeProjectId,
  destBudgetCategories,
  sourceBudgetCategories,
  showSourceCategoryPicker,
  showDestCategoryPicker,
  onConfirm,
  subtitle,
  onTargetProjectChange,
}: SellToProjectModalProps) {
  const theme = useTheme();
  const [targetProjectId, setTargetProjectId] = useState<string | null>(null);
  const [destCategoryId, setDestCategoryId] = useState<string | null>(null);
  const [sourceCategoryId, setSourceCategoryId] = useState<string | null>(null);

  const handleClose = () => {
    setTargetProjectId(null);
    setDestCategoryId(null);
    setSourceCategoryId(null);
    onRequestClose();
  };

  const handleTargetChange = useCallback((projectId: string | null) => {
    setTargetProjectId(projectId);
    setDestCategoryId(null);
    onTargetProjectChange?.(projectId);
  }, [onTargetProjectChange]);

  const handleConfirm = () => {
    if (!targetProjectId) return;
    onConfirm({ targetProjectId, destCategoryId, sourceCategoryId });
    setTargetProjectId(null);
    setDestCategoryId(null);
    setSourceCategoryId(null);
  };

  return (
    <BottomSheet visible={visible} onRequestClose={handleClose}>
      <View style={styles.titleRow}>
        <AppText variant="body" style={styles.title}>Sell to Project</AppText>
        {subtitle ? (
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {subtitle}
          </AppText>
        ) : null}
      </View>
      <View style={styles.content}>
        <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
          Sale and purchase records will be created for financial tracking.
          If you're just fixing a misallocation, use Reassign instead.
        </AppText>

        <View style={styles.fieldGroup}>
          <AppText variant="caption" style={styles.fieldLabel}>
            Target project
          </AppText>
          <ProjectSelector
            accountId={accountId}
            value={targetProjectId}
            onChange={handleTargetChange}
            excludeProjectId={excludeProjectId}
          />
        </View>

        {targetProjectId && showDestCategoryPicker && (
          <View style={styles.fieldGroup}>
            <AppText variant="caption" style={styles.fieldLabel}>
              Destination category
            </AppText>
            <CategoryPickerList
              categories={destBudgetCategories}
              selectedId={destCategoryId}
              onSelect={setDestCategoryId}
              maxHeight={150}
              emptyMessage="Loading categories..."
            />
          </View>
        )}

        {targetProjectId && showSourceCategoryPicker && (
          <View style={styles.fieldGroup}>
            <AppText variant="caption" style={styles.fieldLabel}>
              Source category (for uncategorized items)
            </AppText>
            <CategoryPickerList
              categories={sourceBudgetCategories}
              selectedId={sourceCategoryId}
              onSelect={setSourceCategoryId}
              maxHeight={150}
              emptyMessage="Loading categories..."
            />
          </View>
        )}

        <AppButton
          title="Confirm Sale"
          variant="primary"
          disabled={!targetProjectId}
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
    gap: 8,
  },
  fieldLabel: {
    fontWeight: '600',
  },
  button: {
    minHeight: 44,
  },
});
