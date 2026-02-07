import React, { useMemo, useState } from 'react';
import { ActivityIndicator, StyleSheet, TouchableOpacity, View } from 'react-native';
import { AppText } from '../AppText';
import { AppButton } from '../AppButton';
import { useTheme } from '../../theme/ThemeProvider';
import { BudgetCategoryTracker } from './BudgetCategoryTracker';
import type { BudgetCategory } from '../../data/budgetCategoriesService';
import type { ProjectBudgetCategory } from '../../data/projectBudgetCategoriesService';
import type { BudgetProgress } from '../../data/budgetProgressService';
import type { AccountPresets } from '../../data/accountPresetsService';

type BudgetProgressDisplayProps = {
  projectId: string;
  budgetCategories: BudgetCategory[];
  projectBudgetCategories: Record<string, ProjectBudgetCategory>;
  budgetProgress: BudgetProgress;
  pinnedCategoryIds: string[];
  accountPresets: AccountPresets | null;
  onPinToggle?: (categoryId: string) => void;
  onCategoryPress?: (categoryId: string) => void;
  onSetBudget?: () => void;
  isLoading?: boolean;
  error?: string | null;
};

export function BudgetProgressDisplay({
  projectId,
  budgetCategories,
  projectBudgetCategories,
  budgetProgress,
  pinnedCategoryIds,
  accountPresets,
  onPinToggle,
  onCategoryPress,
  onSetBudget,
  isLoading = false,
  error = null,
}: BudgetProgressDisplayProps) {
  const theme = useTheme();
  const [isExpanded, setIsExpanded] = useState(false);

  // Loading state
  if (isLoading) {
    return (
      <View style={styles.container}>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="small" color={theme.colors.primary} />
          <AppText variant="caption" style={{ color: theme.colors.textSecondary, marginLeft: 8 }}>
            Loading budget data...
          </AppText>
        </View>
      </View>
    );
  }

  // Error state
  if (error) {
    return (
      <View style={styles.container}>
        <View style={styles.errorState}>
          <AppText variant="body" style={{ color: theme.colors.error, textAlign: 'center' }}>
            {error}
          </AppText>
        </View>
      </View>
    );
  }

  // Determine enabled categories (has budget OR has spend)
  const enabledCategories = useMemo(() => {
    return budgetCategories.filter((cat) => {
      const hasProjectBudget = projectBudgetCategories[cat.id] !== undefined;
      const hasSpend = (budgetProgress.spentByCategory[cat.id] ?? 0) !== 0;
      const isArchived = cat.isArchived === true;
      return (hasProjectBudget || hasSpend) && !isArchived;
    });
  }, [budgetCategories, projectBudgetCategories, budgetProgress]);

  // Sort categories: pinned → custom order → alphabetical → fees last
  const sortedCategories = useMemo(() => {
    const pinned = pinnedCategoryIds
      .map((id) => enabledCategories.find((c) => c.id === id))
      .filter((c): c is BudgetCategory => !!c);

    const unpinned = enabledCategories.filter(
      (c) => !pinnedCategoryIds.includes(c.id) && c.metadata?.categoryType !== 'fee'
    );

    const fees = enabledCategories.filter((c) => c.metadata?.categoryType === 'fee');

    const customOrder = accountPresets?.budgetCategoryOrder ?? [];
    unpinned.sort((a, b) => {
      const aIndex = customOrder.indexOf(a.id);
      const bIndex = customOrder.indexOf(b.id);
      if (aIndex !== -1 && bIndex !== -1) return aIndex - bIndex;
      if (aIndex !== -1) return -1;
      if (bIndex !== -1) return 1;
      return a.name.localeCompare(b.name);
    });

    return [...pinned, ...unpinned, ...fees];
  }, [enabledCategories, pinnedCategoryIds, accountPresets]);

  // Visible categories based on expanded state
  const visibleCategories = useMemo(() => {
    if (isExpanded) return sortedCategories;
    // Collapsed: show pinned categories
    const pinned = sortedCategories.filter((c) => pinnedCategoryIds.includes(c.id));
    if (pinned.length > 0) return pinned;
    // No pins: show the first non-fee category as a default preview
    const firstNonFee = sortedCategories.find((c) => c.metadata?.categoryType !== 'fee');
    return firstNonFee ? [firstNonFee] : sortedCategories.slice(0, 1);
  }, [isExpanded, sortedCategories, pinnedCategoryIds]);

  // Calculate Overall Budget
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

  // Show toggle if there are more categories than visible
  const showToggle = useMemo(() => {
    return sortedCategories.length > visibleCategories.length || overallBudget > 0;
  }, [sortedCategories, visibleCategories, overallBudget]);

  // Empty state: no budget categories exist at all
  if (budgetCategories.length === 0) {
    return null;
  }

  // Empty state: no categories enabled for this project
  if (enabledCategories.length === 0) {
    return null;
  }

  return (
    <View style={styles.container}>
      {/* Visible categories */}
      {visibleCategories.map((cat) => (
        <BudgetCategoryTracker
          key={cat.id}
          categoryName={cat.name}
          categoryType={cat.metadata?.categoryType ?? 'general'}
          spentCents={budgetProgress.spentByCategory[cat.id] ?? 0}
          budgetCents={projectBudgetCategories[cat.id]?.budgetCents ?? null}
          isPinned={!isExpanded && pinnedCategoryIds.includes(cat.id)}
          onPress={onCategoryPress ? () => onCategoryPress(cat.id) : undefined}
          onLongPress={onPinToggle ? () => onPinToggle(cat.id) : undefined}
        />
      ))}

      {/* Expanded: Overall Budget at end */}
      {isExpanded && overallBudget > 0 && (
        <BudgetCategoryTracker
          categoryName="Overall"
          categoryType="general"
          spentCents={budgetProgress.spentCents}
          budgetCents={overallBudget}
          isOverallBudget={true}
        />
      )}

      {/* Toggle button */}
      {showToggle && (
        <TouchableOpacity
          onPress={() => setIsExpanded(!isExpanded)}
          style={styles.toggleButton}
        >
          <AppText variant="caption" style={{ color: theme.colors.primary }}>
            {isExpanded ? 'Show Less' : 'Show All Budget Categories'}
          </AppText>
        </TouchableOpacity>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  toggleButton: {
    alignItems: 'center',
    paddingVertical: 4,
  },
  emptyState: {
    gap: 16,
    padding: 24,
    alignItems: 'center',
  },
  emptyButton: {
    marginTop: 8,
  },
  loadingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 16,
  },
  errorState: {
    padding: 16,
    alignItems: 'center',
  },
});
