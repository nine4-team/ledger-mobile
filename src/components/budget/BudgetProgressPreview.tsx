import React, { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import { AppText } from '../AppText';
import { ProgressBar } from '../ProgressBar';
import { useThemeContext } from '../../theme/ThemeProvider';
import { BUDGET_BAR_COLOR, getOverflowColor } from '../../utils/budgetColors';
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
  return `$${dollars.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`;
}

export function BudgetProgressPreview({
  budgetCategories,
  projectBudgetCategories,
  budgetProgress,
  pinnedCategoryIds,
  maxCategories = 2,
}: BudgetProgressPreviewProps) {
  const { theme, resolvedColorScheme } = useThemeContext();
  const isDark = resolvedColorScheme === 'dark';
  const overflowColors = useMemo(() => getOverflowColor(isDark), [isDark]);

  // Determine enabled categories (has non-zero budget OR has spend)
  const enabledCategories = useMemo(() => {
    return budgetCategories.filter((cat) => {
      const budgetCents = projectBudgetCategories[cat.id]?.budgetCents ?? 0;
      const hasNonZeroBudget = budgetCents > 0;
      const hasSpend = (budgetProgress.spentByCategory[cat.id] ?? 0) !== 0;
      return (hasNonZeroBudget || hasSpend) && !cat.isArchived;
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

  // Fallback categories: top 1-2 by spend percentage when nothing is pinned
  const fallbackCategories = useMemo(() => {
    if (pinnedCategories.length > 0) return [];
    // Pick categories that have any budget activity
    const withActivity = enabledCategories.filter((cat) => {
      const spent = budgetProgress.spentByCategory[cat.id] ?? 0;
      const budget = projectBudgetCategories[cat.id]?.budgetCents ?? 0;
      return spent > 0 || budget > 0;
    });
    // Sort by spend percentage descending (highest usage first)
    return withActivity
      .sort((a, b) => {
        const aSpent = budgetProgress.spentByCategory[a.id] ?? 0;
        const aBudget = projectBudgetCategories[a.id]?.budgetCents ?? 0;
        const bSpent = budgetProgress.spentByCategory[b.id] ?? 0;
        const bBudget = projectBudgetCategories[b.id]?.budgetCents ?? 0;
        const aPct = aBudget > 0 ? aSpent / aBudget : aSpent > 0 ? Infinity : 0;
        const bPct = bBudget > 0 ? bSpent / bBudget : bSpent > 0 ? Infinity : 0;
        return bPct - aPct;
      })
      .slice(0, maxCategories);
  }, [pinnedCategories, enabledCategories, budgetProgress, projectBudgetCategories, maxCategories]);

  // Visible categories: pinned categories, or top active categories as fallback
  const visibleCategories = useMemo(() => {
    if (pinnedCategories.length > 0) {
      return pinnedCategories;
    }
    return fallbackCategories;
  }, [pinnedCategories, fallbackCategories]);

  const showOverall = pinnedCategories.length === 0 && visibleCategories.length === 0 && overallBudget > 0;

  // If no categories and no overall budget, don't render anything
  if (visibleCategories.length === 0 && !showOverall) {
    return null;
  }

  return (
    <View style={styles.container}>
      {/* Show Overall Budget if no pins */}
      {showOverall && (() => {
        const percentage = overallBudget > 0 ? (budgetProgress.spentCents / overallBudget) * 100 : 0;
        const isOver = budgetProgress.spentCents > overallBudget;
        const overflowPct = isOver ? ((budgetProgress.spentCents - overallBudget) / overallBudget) * 100 : 0;
        const remaining = overallBudget - budgetProgress.spentCents;
        return (
          <View style={styles.categoryRow}>
            <AppText variant="body" style={styles.categoryTitle}>
              Overall Budget
            </AppText>
            <View style={styles.labelRow}>
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                {formatCurrency(budgetProgress.spentCents)} spent
              </AppText>
              <AppText variant="caption" style={{ color: isOver ? overflowColors.text : theme.colors.textSecondary }}>
                {isOver
                  ? `${formatCurrency(Math.abs(remaining))} over`
                  : `${formatCurrency(remaining)} remaining`}
              </AppText>
            </View>
            <ProgressBar
              percentage={Math.min(percentage, 100)}
              color={BUDGET_BAR_COLOR}
              overflowPercentage={isOver ? Math.min(overflowPct, 100) : undefined}
              overflowColor={isOver ? overflowColors.bar : undefined}
            />
          </View>
        );
      })()}

      {/* Show pinned categories */}
      {visibleCategories.map((category) => {
        const spentCents = budgetProgress.spentByCategory[category.id] ?? 0;
        const budgetCents = projectBudgetCategories[category.id]?.budgetCents ?? 0;
        const percentage = budgetCents > 0 ? (spentCents / budgetCents) * 100 : 0;
        const isFee = category.metadata?.categoryType === 'fee';
        const isOver = budgetCents > 0 && spentCents > budgetCents;
        const overflowPct = isOver ? ((spentCents - budgetCents) / budgetCents) * 100 : 0;
        const remaining = budgetCents - spentCents;

        return (
          <View key={category.id} style={styles.categoryRow}>
            <AppText variant="body" style={styles.categoryTitle}>
              {category.name}
            </AppText>
            <View style={styles.labelRow}>
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                {isFee
                  ? `${formatCurrency(spentCents)} received`
                  : `${formatCurrency(spentCents)} spent`}
              </AppText>
              <AppText variant="caption" style={{ color: isOver ? overflowColors.text : theme.colors.textSecondary }}>
                {isFee
                  ? isOver
                    ? `${formatCurrency(Math.abs(remaining))} over received`
                    : `${formatCurrency(remaining)} remaining`
                  : isOver
                    ? `${formatCurrency(Math.abs(remaining))} over`
                    : `${formatCurrency(remaining)} remaining`}
              </AppText>
            </View>
            <ProgressBar
              percentage={Math.min(percentage, 100)}
              color={BUDGET_BAR_COLOR}
              overflowPercentage={isOver ? Math.min(overflowPct, 100) : undefined}
              overflowColor={isOver ? overflowColors.bar : undefined}
            />
          </View>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 8,
    marginTop: 16,
  },
  categoryRow: {
    gap: 4,
  },
  categoryTitle: {
    fontSize: 15,
    fontWeight: '500',
  },
  labelRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
});
