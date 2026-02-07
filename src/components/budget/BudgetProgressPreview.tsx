import React, { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import { AppText } from '../AppText';
import { useTheme, useUIKitTheme } from '../../theme/ThemeProvider';
import type { BudgetCategory } from '../../data/budgetCategoriesService';
import type { ProjectBudgetCategory } from '../../data/projectBudgetCategoriesService';
import type { BudgetProgress } from '../../data/budgetProgressService';

type BudgetProgressPreviewProps = {
  budgetCategories: BudgetCategory[];
  projectBudgetCategories: Record<string, ProjectBudgetCategory>;
  budgetProgress: BudgetProgress;
  pinnedCategoryIds: string[];
  maxCategories?: number; // Default 2
};

function formatCurrency(cents: number): string {
  const dollars = Math.abs(cents / 100);
  return `$${dollars.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function getProgressColor(percentage: number, isFee: boolean): string {
  if (isFee) {
    // Inverted: green for high percentage (good for fees)
    if (percentage >= 75) return '#22C55E'; // green
    if (percentage >= 50) return '#EAB308'; // yellow
    return '#EF4444'; // red
  } else {
    // Standard: red for high percentage (bad for spending)
    if (percentage >= 75) return '#EF4444'; // red
    if (percentage >= 50) return '#EAB308'; // yellow
    return '#22C55E'; // green
  }
}

export function BudgetProgressPreview({
  budgetCategories,
  projectBudgetCategories,
  budgetProgress,
  pinnedCategoryIds,
  maxCategories = 2,
}: BudgetProgressPreviewProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  // Determine enabled categories (has budget OR has spend)
  const enabledCategories = useMemo(() => {
    return budgetCategories.filter((cat) => {
      const hasProjectBudget = projectBudgetCategories[cat.id] !== undefined;
      const hasSpend = (budgetProgress.spentByCategory[cat.id] ?? 0) !== 0;
      return (hasProjectBudget || hasSpend) && !cat.isArchived;
    });
  }, [budgetCategories, projectBudgetCategories, budgetProgress]);

  // Get pinned categories (in user-defined order)
  const pinnedCategories = useMemo(() => {
    return pinnedCategoryIds
      .map((id) => enabledCategories.find((c) => c.id === id))
      .filter((c): c is BudgetCategory => c !== undefined)
      .slice(0, maxCategories);
  }, [pinnedCategoryIds, enabledCategories, maxCategories]);

  // Calculate overall budget (for fallback when no pins)
  const overallBudget = useMemo(() => {
    let totalBudgetCents = 0;
    enabledCategories.forEach((cat) => {
      const shouldExclude = cat.metadata?.excludeFromOverallBudget === true;
      if (!shouldExclude) {
        const budget = projectBudgetCategories[cat.id]?.budgetCents ?? 0;
        totalBudgetCents += budget;
      }
    });
    return totalBudgetCents;
  }, [enabledCategories, projectBudgetCategories]);

  // Visible categories: pinned categories, or Overall Budget if no pins
  const visibleCategories = useMemo(() => {
    if (pinnedCategories.length > 0) {
      return pinnedCategories;
    }
    // Return synthetic "overall" category
    return [];
  }, [pinnedCategories]);

  const showOverall = pinnedCategories.length === 0 && overallBudget > 0;

  // If no categories and no overall budget, don't render anything
  if (visibleCategories.length === 0 && !showOverall) {
    return null;
  }

  return (
    <View style={styles.container}>
      {/* Show Overall Budget if no pins */}
      {showOverall && (
        <View style={styles.categoryRow}>
          <View style={styles.labelRow}>
            <AppText variant="caption" style={[styles.categoryName, { color: theme.colors.textSecondary }]}>
              Overall Budget
            </AppText>
            <View style={styles.amountRow}>
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                {formatCurrency(budgetProgress.spentCents)} / {formatCurrency(overallBudget)}
              </AppText>
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                {overallBudget > 0 ? `${Math.round((budgetProgress.spentCents / overallBudget) * 100)}%` : '—'}
              </AppText>
            </View>
          </View>
          <View style={[styles.track, { backgroundColor: uiKitTheme.border.secondary }]}>
            <View
              style={[
                styles.fill,
                {
                  width: `${Math.min((budgetProgress.spentCents / overallBudget) * 100, 100)}%`,
                  backgroundColor: getProgressColor(
                    (budgetProgress.spentCents / overallBudget) * 100,
                    false
                  ),
                },
              ]}
            />
          </View>
        </View>
      )}

      {/* Show pinned categories */}
      {visibleCategories.map((category) => {
        const spentCents = budgetProgress.spentByCategory[category.id] ?? 0;
        const budgetCents = projectBudgetCategories[category.id]?.budgetCents ?? 0;
        const percentage = budgetCents > 0 ? (spentCents / budgetCents) * 100 : 0;
        const isFee = category.metadata?.categoryType === 'fee';

        return (
          <View key={category.id} style={styles.categoryRow}>
            <View style={styles.labelRow}>
              <AppText variant="caption" style={[styles.categoryName, { color: theme.colors.textSecondary }]}>
                {category.name}
              </AppText>
              <View style={styles.amountRow}>
                <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                  {formatCurrency(spentCents)} / {formatCurrency(budgetCents)}
                </AppText>
                <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                  {budgetCents > 0 ? `${Math.round(percentage)}%` : '—'}
                </AppText>
              </View>
            </View>
            <View style={[styles.track, { backgroundColor: uiKitTheme.border.secondary }]}>
              <View
                style={[
                  styles.fill,
                  {
                    width: `${Math.min(percentage, 100)}%`,
                    backgroundColor: getProgressColor(percentage, isFee),
                  },
                ]}
              />
            </View>
          </View>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 8,
  },
  categoryRow: {
    gap: 4,
  },
  labelRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  categoryName: {
    flex: 1,
  },
  amountRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  track: {
    height: 4,
    borderRadius: 999,
    overflow: 'hidden',
  },
  fill: {
    height: '100%',
    borderRadius: 999,
  },
});
