import React, { useMemo } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { AppText } from '../../../../src/components/AppText';
import { useTheme, useUIKitTheme } from '../../../../src/theme/ThemeProvider';
import type { Transaction } from '../../../../src/data/transactionsService';
import type { EditTransactionDetailsField } from '../../../../src/components/modals/EditTransactionDetailsModal';
import { getCardStyle } from '../../../../src/ui';

const BRAND_COLOR = '#987e55';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type NextStep = {
  id: string;
  label: string;
  completed: boolean;
  icon: React.ComponentProps<typeof MaterialIcons>['name'];
  onPress?: () => void;
};

export type NextStepsSectionProps = {
  transaction: Transaction;
  itemCount: number;
  imageCount: number;
  budgetCategories: Record<string, { name: string; metadata?: any }>;
  onScrollToSection?: (section: string) => void;
  onEditDetails?: (field?: EditTransactionDetailsField) => void;
  onAddItem?: () => void;
};

// ---------------------------------------------------------------------------
// Step computation (pure function, testable)
// ---------------------------------------------------------------------------

export function computeNextSteps(
  transaction: Transaction,
  itemCount: number,
  imageCount: number,
  budgetCategories: Record<string, { name: string }>,
): Omit<NextStep, 'onPress'>[] {
  const steps: Omit<NextStep, 'onPress'>[] = [];

  // Budget category
  const hasBudgetCategory = !!transaction.budgetCategoryId && !!budgetCategories[transaction.budgetCategoryId];
  steps.push({
    id: 'budget-category',
    label: 'Categorize this transaction',
    completed: hasBudgetCategory,
    icon: 'category',
  });

  // Amount
  const hasAmount = typeof transaction.amountCents === 'number' && transaction.amountCents > 0;
  steps.push({
    id: 'amount',
    label: 'Enter the amount',
    completed: hasAmount,
    icon: 'attach-money',
  });

  // Receipt
  const hasReceipt = (transaction.receiptImages?.length ?? 0) > 0;
  steps.push({
    id: 'receipt',
    label: 'Add a receipt',
    completed: hasReceipt,
    icon: 'receipt',
  });

  const hasItems = itemCount > 0;
  steps.push({
    id: 'items',
    label: 'Add items',
    completed: hasItems,
    icon: 'inventory-2',
  });

  // Purchased by
  const hasPurchasedBy = !!transaction.purchasedBy?.trim();
  steps.push({
    id: 'purchased-by',
    label: 'Set purchased by',
    completed: hasPurchasedBy,
    icon: 'person',
  });

  // Tax rate (only if budget category is itemized)
  if (hasBudgetCategory && transaction.budgetCategoryId) {
    const cat = budgetCategories[transaction.budgetCategoryId] as { name: string; metadata?: any };
    if (cat?.metadata?.categoryType === 'itemized') {
      const hasTaxRate = typeof transaction.taxRatePct === 'number' && transaction.taxRatePct > 0;
      steps.push({
        id: 'tax-rate',
        label: 'Set tax rate',
        completed: hasTaxRate,
        icon: 'percent',
      });
    }
  }

  return steps;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function NextStepsSection({
  transaction,
  itemCount,
  imageCount,
  budgetCategories,
  onScrollToSection,
  onEditDetails,
  onAddItem,
}: NextStepsSectionProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const rawSteps = useMemo(
    () => computeNextSteps(transaction, itemCount, imageCount, budgetCategories),
    [transaction, itemCount, imageCount, budgetCategories],
  );

  // Wire up onPress for each step
  const steps: NextStep[] = useMemo(() => {
    return rawSteps.map((step) => {
      let onPress: (() => void) | undefined;
      switch (step.id) {
        case 'budget-category':
          onPress = onEditDetails ? () => onEditDetails('budgetCategory') : undefined;
          break;
        case 'amount':
          onPress = onEditDetails ? () => onEditDetails('amount') : undefined;
          break;
        case 'purchased-by':
          onPress = onEditDetails ? () => onEditDetails('purchasedBy') : undefined;
          break;
        case 'tax-rate':
          onPress = onEditDetails ? () => onEditDetails('taxRate') : undefined;
          break;
        case 'receipt':
          onPress = () => onScrollToSection?.('receipts');
          break;
        case 'items':
          onPress = onAddItem ?? (() => onScrollToSection?.('items'));
          break;
      }
      return { ...step, onPress };
    });
  }, [rawSteps, onEditDetails, onScrollToSection, onAddItem]);

  const completedCount = steps.filter((s) => s.completed).length;
  const totalCount = steps.length;

  // Hide if all steps are complete
  if (completedCount === totalCount) return null;

  const progress = totalCount > 0 ? completedCount / totalCount : 0;
  const incompleteSteps = steps.filter((s) => !s.completed);
  const completedSteps = steps.filter((s) => s.completed);

  return (
    <View style={[styles.container, getCardStyle(uiKitTheme, { radius: 12, padding: 16 })]}>
      {/* Header with progress ring */}
      <View style={styles.header}>
        <View style={styles.headerLeft}>
          <AppText variant="body" style={styles.headerTitle}>Next Steps</AppText>
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {completedCount}/{totalCount} complete
          </AppText>
        </View>
        <ProgressRing progress={progress} size={36} strokeWidth={3} />
      </View>

      {/* Incomplete steps */}
      <View style={styles.stepsList}>
        {incompleteSteps.map((step) => (
          <Pressable
            key={step.id}
            onPress={step.onPress}
            disabled={!step.onPress}
            style={({ pressed }) => [
              styles.stepRow,
              pressed && step.onPress ? { opacity: 0.7 } : null,
            ]}
          >
            <View style={[styles.checkbox, { borderColor: uiKitTheme.border.secondary }]}>
              <MaterialIcons name={step.icon} size={14} color={theme.colors.textSecondary} />
            </View>
            <AppText variant="body" style={styles.stepLabel}>{step.label}</AppText>
            {step.onPress && (
              <MaterialIcons name="chevron-right" size={18} color={theme.colors.textSecondary} />
            )}
          </Pressable>
        ))}
      </View>

      {/* Completed steps (compact) */}
      {completedSteps.length > 0 && (
        <View style={styles.completedList}>
          {completedSteps.map((step) => (
            <View key={step.id} style={styles.completedRow}>
              <MaterialIcons name="check-circle" size={16} color={BRAND_COLOR} />
              <AppText variant="caption" style={{ color: theme.colors.textSecondary, textDecorationLine: 'line-through' }}>
                {step.label}
              </AppText>
            </View>
          ))}
        </View>
      )}
    </View>
  );
}

// ---------------------------------------------------------------------------
// Progress ring
// ---------------------------------------------------------------------------

function ProgressRing({ progress, size, strokeWidth }: { progress: number; size: number; strokeWidth: number }) {
  const theme = useTheme();
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const filled = circumference * progress;
  const percentage = Math.round(progress * 100);

  return (
    <View style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
      {/* Simple circle visualization using border */}
      <View
        style={{
          width: size,
          height: size,
          borderRadius: size / 2,
          borderWidth: strokeWidth,
          borderColor: theme.colors.border,
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <AppText variant="caption" style={{ fontSize: 10, fontWeight: '700', color: BRAND_COLOR }}>
          {percentage}%
        </AppText>
      </View>
      {/* Overlay arc — simplified to a partial border for RN (no SVG dependency) */}
      {progress > 0 && (
        <View
          style={{
            position: 'absolute',
            width: size,
            height: size,
            borderRadius: size / 2,
            borderWidth: strokeWidth,
            borderColor: BRAND_COLOR,
            borderRightColor: progress < 0.75 ? 'transparent' : BRAND_COLOR,
            borderBottomColor: progress < 0.5 ? 'transparent' : BRAND_COLOR,
            borderLeftColor: progress < 0.25 ? 'transparent' : BRAND_COLOR,
            transform: [{ rotate: '-90deg' }],
          }}
        />
      )}
    </View>
  );
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerLeft: {
    gap: 2,
  },
  headerTitle: {
    fontWeight: '600',
  },
  stepsList: {
    gap: 4,
  },
  stepRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 8,
  },
  checkbox: {
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 1.5,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepLabel: {
    flex: 1,
  },
  completedList: {
    gap: 4,
    paddingTop: 4,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#E0E0E0',
  },
  completedRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 2,
  },
});
