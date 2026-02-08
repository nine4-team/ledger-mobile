import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Alert, ScrollView, StyleSheet, View, useWindowDimensions } from 'react-native';
import { useRouter } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Screen } from '../components/Screen';
import { AppText } from '../components/AppText';
import { AppButton } from '../components/AppButton';
import { FormActions } from '../components/FormActions';
import { CategoryBudgetInput } from '../components/budget/CategoryBudgetInput';
import { useAccountContextStore } from '../auth/accountContextStore';
import { useUIKitTheme, useTheme } from '../theme/ThemeProvider';
import {
  BudgetCategory,
  subscribeToBudgetCategories,
} from '../data/budgetCategoriesService';
import {
  ProjectBudgetCategory,
  setProjectBudgetCategory,
  subscribeToProjectBudgetCategories,
} from '../data/projectBudgetCategoriesService';
import { getCardBaseStyle, CARD_PADDING } from '../ui';

export type ProjectBudgetFormProps = {
  projectId: string;
};

/**
 * ProjectBudgetForm Screen
 *
 * Per-project budget allocation screen with:
 * - Auto-calculated total budget display (prominent at top)
 * - Responsive grid of CategoryBudgetInput (2-column on tablet, 1-column on mobile)
 * - Enable/disable categories
 * - Save/cancel actions
 *
 * Features:
 * 1. Subscribe to budget categories and project budget categories
 * 2. Calculate total budget from all enabled categories
 * 3. Responsive grid layout (2-col on tablet ≥768px, 1-col on mobile)
 * 4. Save all budgets to Firestore
 *
 * @example
 * ```tsx
 * <ProjectBudgetForm projectId="project-123" />
 * ```
 */
export function ProjectBudgetForm({ projectId }: ProjectBudgetFormProps) {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const { width: screenWidth } = useWindowDimensions();

  // State for budget categories and project budgets
  const [budgetCategories, setBudgetCategories] = useState<BudgetCategory[]>([]);
  const [projectBudgetCategories, setProjectBudgetCategories] = useState<
    Record<string, ProjectBudgetCategory>
  >({});
  const [localBudgets, setLocalBudgets] = useState<Record<string, number | null>>({});
  const [isSaving, setIsSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);

  // Loading and error states
  const [isLoadingCategories, setIsLoadingCategories] = useState(true);
  const [isLoadingProjectBudgets, setIsLoadingProjectBudgets] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  // Subscribe to budget categories (account-wide)
  useEffect(() => {
    if (!accountId) {
      setBudgetCategories([]);
      setIsLoadingCategories(false);
      return;
    }
    setIsLoadingCategories(true);
    setLoadError(null);
    try {
      const unsubscribe = subscribeToBudgetCategories(accountId, (categories) => {
        setBudgetCategories(categories);
        setIsLoadingCategories(false);
      });
      return unsubscribe;
    } catch (error) {
      console.error('[ProjectBudgetForm] Failed to load categories:', error);
      setLoadError('Failed to load budget categories');
      setIsLoadingCategories(false);
    }
  }, [accountId]);

  // Subscribe to project budget categories
  useEffect(() => {
    if (!accountId || !projectId) {
      setProjectBudgetCategories({});
      setIsLoadingProjectBudgets(false);
      return;
    }
    setIsLoadingProjectBudgets(true);
    try {
      const unsubscribe = subscribeToProjectBudgetCategories(accountId, projectId, (categories) => {
        const budgetsMap: Record<string, ProjectBudgetCategory> = {};
        categories.forEach((pbc) => {
          budgetsMap[pbc.id] = pbc;
        });
        setProjectBudgetCategories(budgetsMap);
        setIsLoadingProjectBudgets(false);
      });
      return unsubscribe;
    } catch (error) {
      console.error('[ProjectBudgetForm] Failed to load project budgets:', error);
      setLoadError('Failed to load project budgets');
      setIsLoadingProjectBudgets(false);
    }
  }, [accountId, projectId]);

  // Initialize local budgets from project budget categories
  useEffect(() => {
    const initial: Record<string, number | null> = {};
    Object.keys(projectBudgetCategories).forEach((categoryId) => {
      initial[categoryId] = projectBudgetCategories[categoryId].budgetCents;
    });
    setLocalBudgets(initial);
    setHasChanges(false);
  }, [projectBudgetCategories]);

  // Filter active (non-archived) categories
  const activeCategories = useMemo(() => {
    return budgetCategories.filter((cat) => !cat.isArchived);
  }, [budgetCategories]);

  // Get enabled categories (categories with budgets set in this project)
  const enabledCategories = useMemo(() => {
    return activeCategories.filter((cat) => localBudgets[cat.id] !== undefined);
  }, [activeCategories, localBudgets]);

  // Get disabled categories (categories not yet enabled for this project)
  const disabledCategories = useMemo(() => {
    return activeCategories.filter((cat) => localBudgets[cat.id] === undefined);
  }, [activeCategories, localBudgets]);

  // Calculate total budget from all enabled categories
  const totalBudgetCents = useMemo(() => {
    let total = 0;
    Object.values(localBudgets).forEach((budgetCents) => {
      if (budgetCents !== null && budgetCents !== undefined) {
        total += budgetCents;
      }
    });
    return total;
  }, [localBudgets]);

  // Determine number of columns based on screen width
  const numColumns = screenWidth >= 768 ? 2 : 1;

  // Handle budget change for a category
  const handleBudgetChange = useCallback(
    (categoryId: string, cents: number | null) => {
      setLocalBudgets((prev) => ({
        ...prev,
        [categoryId]: cents,
      }));
      setHasChanges(true);
    },
    []
  );

  // Enable a category (add it to local budgets with null value)
  const handleEnableCategory = useCallback((categoryId: string) => {
    setLocalBudgets((prev) => ({
      ...prev,
      [categoryId]: null,
    }));
    setHasChanges(true);
  }, []);

  // Disable a category (remove it from local budgets)
  const handleDisableCategory = useCallback((categoryId: string) => {
    setLocalBudgets((prev) => {
      const next = { ...prev };
      delete next[categoryId];
      return next;
    });
    setHasChanges(true);
  }, []);

  // Save all budgets to Firestore
  const handleSave = useCallback(async () => {
    if (!accountId || !projectId) return;

    setIsSaving(true);
    try {
      // Save all enabled categories
      const savePromises = Object.entries(localBudgets).map(([categoryId, budgetCents]) =>
        setProjectBudgetCategory(accountId, projectId, categoryId, { budgetCents })
      );

      await Promise.all(savePromises);

      // TODO: Delete disabled categories from Firestore
      // This would require a delete function in projectBudgetCategoriesService

      Alert.alert('Success', 'Budget saved successfully');
      setHasChanges(false);

      // Navigate back
      if (router.canGoBack()) {
        router.back();
      }
    } catch (error) {
      console.error('Failed to save budget:', error);
      Alert.alert('Error', 'Failed to save budget. Please try again.');
    } finally {
      setIsSaving(false);
    }
  }, [accountId, projectId, localBudgets, router]);

  // Handle cancel
  const handleCancel = useCallback(() => {
    if (hasChanges) {
      Alert.alert(
        'Discard changes?',
        'You have unsaved changes. Are you sure you want to discard them?',
        [
          { text: 'Keep Editing', style: 'cancel' },
          {
            text: 'Discard',
            style: 'destructive',
            onPress: () => {
              if (router.canGoBack()) {
                router.back();
              }
            },
          },
        ]
      );
    } else {
      if (router.canGoBack()) {
        router.back();
      }
    }
  }, [hasChanges, router]);

  const cardStyle = {
    ...getCardBaseStyle({ radius: 12 }),
    backgroundColor: uiKitTheme.background.surface,
    borderWidth: 1,
    borderColor: uiKitTheme.border.primary,
  };
  const isLoading = isLoadingCategories || isLoadingProjectBudgets;

  // Handle retry for errors
  const handleRetry = useCallback(() => {
    setLoadError(null);
    setIsLoadingCategories(true);
    setIsLoadingProjectBudgets(true);
  }, []);

  return (
    <Screen title="Project Budget" includeBottomInset={false}>
      <ScrollView style={styles.scrollView} contentContainerStyle={styles.scrollContent}>
        {/* Loading State */}
        {isLoading && (
          <View style={styles.loadingContainer}>
            <ActivityIndicator size="large" color={theme.colors.primary} />
            <AppText variant="body" style={[styles.loadingText, { color: uiKitTheme.text.secondary }]}>
              Loading budget data...
            </AppText>
          </View>
        )}

        {/* Error State */}
        {!isLoading && loadError && (
          <View style={styles.errorContainer}>
            <MaterialIcons name="error-outline" size={48} color={theme.colors.error} />
            <AppText variant="body" style={[styles.errorText, { color: theme.colors.error }]}>
              {loadError}
            </AppText>
            <AppButton
              title="Retry"
              variant="primary"
              onPress={handleRetry}
              style={styles.retryButton}
            />
          </View>
        )}

        {/* Content - only show when not loading and no error */}
        {!isLoading && !loadError && (
          <>
            {/* Total Budget Card */}
            <View style={[styles.totalCard, cardStyle, { padding: CARD_PADDING }]}>
              <AppText variant="caption" style={styles.totalLabel}>
                Total Budget
              </AppText>
              <AppText variant="title" style={styles.totalAmount}>
                ${(totalBudgetCents / 100).toFixed(2)}
              </AppText>
              <AppText variant="caption" style={styles.totalHint}>
                Sum of all enabled category budgets
              </AppText>
            </View>

            {/* Enabled Categories Section */}
            {enabledCategories.length > 0 && (
              <View style={styles.section}>
                <AppText variant="body" style={styles.sectionTitle}>
                  Budget Categories
                </AppText>

                {/* Responsive Grid */}
                <View style={[styles.grid, { gap: 16 }]}>
                  {enabledCategories.map((category, index) => (
                    <View
                      key={category.id}
                      style={[
                        styles.gridItem,
                        { width: numColumns === 2 ? `${(100 - 2) / 2}%` : '100%' },
                      ]}
                    >
                      <View style={styles.categoryInputWrapper}>
                        <CategoryBudgetInput
                          categoryName={category.name}
                          budgetCents={localBudgets[category.id]}
                          onChange={(cents) => handleBudgetChange(category.id, cents)}
                          disabled={isSaving}
                        />
                        <AppButton
                          title="Remove"
                          variant="secondary"
                          onPress={() => handleDisableCategory(category.id)}
                          disabled={isSaving}
                          style={styles.removeButton}
                        />
                      </View>
                    </View>
                  ))}
                </View>
              </View>
            )}

            {/* Empty State - No categories exist at all */}
            {activeCategories.length === 0 && (
              <View style={styles.emptyState}>
                <AppText variant="body" style={styles.emptyText}>
                  No budget categories created yet
                </AppText>
                <AppText variant="caption" style={styles.emptyHint}>
                  Create categories in Budget Category Management to start tracking budgets
                </AppText>
              </View>
            )}

            {/* Empty State - Categories exist but none enabled */}
            {activeCategories.length > 0 && enabledCategories.length === 0 && (
              <View style={styles.emptyState}>
                <AppText variant="body" style={styles.emptyText}>
                  No budget categories enabled yet
                </AppText>
                <AppText variant="caption" style={styles.emptyHint}>
                  Enable categories below to start setting budgets
                </AppText>
              </View>
            )}

            {/* Enable More Categories Button */}
            {disabledCategories.length > 0 && (
              <View style={styles.section}>
                <AppText variant="body" style={styles.sectionTitle}>
                  Available Categories
                </AppText>
                <View style={styles.availableCategories}>
                  {disabledCategories.map((category) => (
                    <View key={category.id} style={styles.availableCategory}>
                      <AppText variant="body" style={styles.availableCategoryName}>
                        {category.name}
                      </AppText>
                      <AppButton
                        title="Enable"
                        variant="secondary"
                        onPress={() => handleEnableCategory(category.id)}
                        disabled={isSaving}
                        style={styles.enableButton}
                      />
                    </View>
                  ))}
                </View>
              </View>
            )}

          </>
        )}
      </ScrollView>

      <FormActions>
        <AppButton
          title="Cancel"
          variant="secondary"
          onPress={handleCancel}
          disabled={isSaving}
          style={styles.actionButton}
        />
        <AppButton
          title={isSaving ? 'Saving...' : 'Save Budget'}
          onPress={handleSave}
          disabled={isSaving || !hasChanges}
          loading={isSaving}
          style={styles.actionButton}
        />
      </FormActions>
    </Screen>
  );
}

const styles = StyleSheet.create({
  scrollView: {
    flex: 1,
  },
  scrollContent: {},
  totalCard: {
    marginBottom: 24,
    alignItems: 'center',
  },
  totalLabel: {
    fontSize: 14,
    opacity: 0.7,
    marginBottom: 4,
  },
  totalAmount: {
    fontSize: 32,
    fontWeight: '700',
    marginBottom: 4,
  },
  totalHint: {
    fontSize: 12,
    opacity: 0.6,
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 16,
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  gridItem: {
    marginBottom: 16,
  },
  categoryInputWrapper: {
    gap: 8,
  },
  removeButton: {
    minHeight: 36,
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 32,
    gap: 8,
  },
  emptyText: {
    fontSize: 16,
    fontWeight: '500',
  },
  emptyHint: {
    fontSize: 14,
    opacity: 0.6,
  },
  availableCategories: {
    gap: 12,
  },
  availableCategory: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 8,
  },
  availableCategoryName: {
    flex: 1,
    fontSize: 16,
  },
  enableButton: {
    minWidth: 100,
    minHeight: 36,
  },
  actionButton: {
    flex: 1,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 60,
    gap: 16,
  },
  loadingText: {
    fontSize: 16,
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 60,
    paddingHorizontal: 32,
    gap: 16,
  },
  errorText: {
    fontSize: 16,
    textAlign: 'center',
  },
  retryButton: {
    minWidth: 120,
    marginTop: 8,
  },
});
