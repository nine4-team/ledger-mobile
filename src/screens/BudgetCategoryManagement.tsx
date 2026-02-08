import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, View } from 'react-native';

import { useAccountContextStore } from '@/auth/accountContextStore';
import { AppButton } from '@/components/AppButton';
import { AppText } from '@/components/AppText';
import { ArchivedCategoryRow } from '@/components/budget/ArchivedCategoryRow';
import { CategoryFormModal } from '@/components/budget/CategoryFormModal';
import type { CategoryFormData } from '@/components/budget/CategoryFormModal';
import { CategoryRow } from '@/components/budget/CategoryRow';
import { DraggableCardList } from '@/components/DraggableCardList';
import type { DraggableCardListRenderItemInfo } from '@/components/DraggableCardList';
import { MultiSelectPicker } from '@/components/MultiSelectPicker';
import type { MultiSelectPickerOption } from '@/components/MultiSelectPicker';
import { Screen } from '@/components/Screen';
import {
  AccountPresets,
  subscribeToAccountPresets,
  updateAccountPresets,
} from '@/data/accountPresetsService';
import {
  BudgetCategory,
  subscribeToBudgetCategories,
  createBudgetCategory,
  updateBudgetCategory,
  setBudgetCategoryArchived,
  setBudgetCategoryOrder,
} from '@/data/budgetCategoriesService';
import { useUIKitTheme } from '@/theme/ThemeProvider';
import { useTheme } from '@/theme/ThemeProvider';

const CATEGORY_ROW_HEIGHT = 70;

type EditingState =
  | { mode: 'create' }
  | { mode: 'edit'; category: BudgetCategory }
  | null;

/**
 * BudgetCategoryManagement screen provides account-wide management of budget categories.
 *
 * Features:
 * - Default category picker for the account
 * - Drag-and-drop reordering of active categories
 * - Add new categories
 * - Edit existing categories
 * - Archive/unarchive categories with transaction count warning
 * - Collapsible archived section
 *
 * @example
 * ```tsx
 * // In app router:
 * import { BudgetCategoryManagement } from '@/screens/BudgetCategoryManagement';
 *
 * export default function BudgetCategoriesScreen() {
 *   return <BudgetCategoryManagement />;
 * }
 * ```
 */
export function BudgetCategoryManagement() {
  const accountId = useAccountContextStore((s) => s.accountId);
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();

  // Data subscriptions
  const [categories, setCategories] = useState<BudgetCategory[]>([]);
  const [accountPresets, setAccountPresets] = useState<AccountPresets | null>(null);

  // UI state
  const [showArchived, setShowArchived] = useState(false);
  const [editingState, setEditingState] = useState<EditingState>(null);
  const [saveError, setSaveError] = useState<string | undefined>(undefined);

  // Loading and error states
  const [isLoadingCategories, setIsLoadingCategories] = useState(true);
  const [isLoadingPresets, setIsLoadingPresets] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  // Subscribe to budget categories
  useEffect(() => {
    if (!accountId) {
      setCategories([]);
      setIsLoadingCategories(false);
      return;
    }
    setIsLoadingCategories(true);
    setLoadError(null);
    try {
      const unsubscribe = subscribeToBudgetCategories(accountId, (nextCategories) => {
        setCategories(nextCategories);
        setIsLoadingCategories(false);
      });
      return unsubscribe;
    } catch (error) {
      console.error('[BudgetCategoryManagement] Failed to load categories:', error);
      setLoadError('Failed to load budget categories');
      setIsLoadingCategories(false);
    }
  }, [accountId]);

  // Subscribe to account presets
  useEffect(() => {
    if (!accountId) {
      setAccountPresets(null);
      setIsLoadingPresets(false);
      return;
    }
    setIsLoadingPresets(true);
    try {
      const unsubscribe = subscribeToAccountPresets(accountId, (nextPresets) => {
        setAccountPresets(nextPresets);
        setIsLoadingPresets(false);
      });
      return unsubscribe;
    } catch (error) {
      console.error('[BudgetCategoryManagement] Failed to load account presets:', error);
      setIsLoadingPresets(false);
    }
  }, [accountId]);

  // Separate active and archived categories
  const activeCategories = useMemo(
    () => categories.filter((c) => !c.isArchived).sort((a, b) => (a.order ?? 0) - (b.order ?? 0)),
    [categories]
  );

  const archivedCategories = useMemo(
    () => categories.filter((c) => c.isArchived).sort((a, b) => (a.order ?? 0) - (b.order ?? 0)),
    [categories]
  );

  // Default category options
  const defaultCategoryOptions: MultiSelectPickerOption<string>[] = useMemo(
    () =>
      activeCategories.map((cat) => ({
        value: cat.id,
        label: cat.name,
      })),
    [activeCategories]
  );

  // Handle reordering
  const handleReorder = useCallback(
    (reorderedCategories: BudgetCategory[]) => {
      if (!accountId) return;
      const orderedIds = reorderedCategories.map((c) => c.id);
      setBudgetCategoryOrder(accountId, orderedIds).catch((error) => {
        console.error('[BudgetCategoryManagement] Reorder failed:', error);
      });
    },
    [accountId]
  );

  // Handle default category change
  const handleDefaultCategoryChange = useCallback(
    (categoryId: string) => {
      if (!accountId) return;
      updateAccountPresets(accountId, { defaultBudgetCategoryId: categoryId }).catch((error) => {
        console.error('[BudgetCategoryManagement] Failed to update default category:', error);
      });
    },
    [accountId]
  );

  // Handle archive with confirmation
  const handleArchive = useCallback(
    (category: BudgetCategory) => {
      if (!accountId) return;

      Alert.alert(
        'Archive Category?',
        'This category will be hidden from the active list but can be restored later.',
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Archive',
            style: 'destructive',
            onPress: () => {
              setBudgetCategoryArchived(accountId, category.id, true).catch((error) => {
                console.error('[BudgetCategoryManagement] Archive failed:', error);
              });
            },
          },
        ]
      );
    },
    [accountId]
  );

  // Handle unarchive
  const handleUnarchive = useCallback(
    (categoryId: string) => {
      if (!accountId) return;
      setBudgetCategoryArchived(accountId, categoryId, false).catch((error) => {
        console.error('[BudgetCategoryManagement] Unarchive failed:', error);
      });
    },
    [accountId]
  );

  // Handle form save
  const handleSave = useCallback(
    (data: CategoryFormData) => {
      if (!accountId || !editingState) return;

      setSaveError(undefined);

      if (editingState.mode === 'create') {
        // createBudgetCategory is now synchronous
        createBudgetCategory(accountId, data.name, {
          metadata: {
            categoryType: data.isItemized ? 'itemized' : data.isFee ? 'fee' : 'general',
            excludeFromOverallBudget: data.excludeFromOverallBudget,
          },
        });
      } else {
        // Fire-and-forget: update existing category
        const category = editingState.category;
        updateBudgetCategory(accountId, category.id, {
          name: data.name,
          metadata: {
            categoryType: data.isItemized ? 'itemized' : data.isFee ? 'fee' : 'general',
            excludeFromOverallBudget: data.excludeFromOverallBudget,
          },
        }).catch((error) => {
          console.error('[BudgetCategoryManagement] Update failed:', error);
        });
      }
      setEditingState(null);
    },
    [accountId, editingState]
  );

  // Render draggable category row
  const renderCategoryRow = useCallback(
    ({ item, isActive, dragHandleProps }: DraggableCardListRenderItemInfo<BudgetCategory>) => {
      return (
        <CategoryRow
          id={item.id}
          name={item.name}
          isItemized={item.metadata?.categoryType === 'itemized'}
          isFee={item.metadata?.categoryType === 'fee'}
          excludeFromOverallBudget={item.metadata?.excludeFromOverallBudget}
          isActive={isActive}
          dragHandleProps={dragHandleProps}
          onEdit={() => setEditingState({ mode: 'edit', category: item })}
          onArchive={() => handleArchive(item)}
        />
      );
    },
    [handleArchive]
  );

  // Handle retry for errors
  const handleRetry = useCallback(() => {
    setLoadError(null);
    setIsLoadingCategories(true);
    setIsLoadingPresets(true);
  }, []);

  if (!accountId) {
    return (
      <Screen title="Budget Categories">
        <View style={styles.emptyContainer}>
          <AppText variant="body" style={{ color: uiKitTheme.text.secondary }}>
            No account selected
          </AppText>
        </View>
      </Screen>
    );
  }

  const isLoading = isLoadingCategories || isLoadingPresets;

  return (
    <>
      <Screen title="Budget Categories">
        {/* Loading State */}
        {isLoading && (
          <View style={styles.loadingContainer}>
            <ActivityIndicator size="large" color={theme.colors.primary} />
            <AppText variant="body" style={[styles.loadingText, { color: uiKitTheme.text.secondary }]}>
              Loading budget categories...
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
            {/* Default Category Picker */}
            {activeCategories.length > 0 && (
              <View style={styles.section}>
                <AppText variant="caption" style={[styles.sectionLabel, { color: uiKitTheme.text.secondary }]}>
                  Account-Wide Default
                </AppText>
                <MultiSelectPicker
                  value={accountPresets?.defaultBudgetCategoryId || ''}
                  onChange={(value) => handleDefaultCategoryChange(value as string)}
                  options={defaultCategoryOptions}
                  accessibilityLabel="Select default budget category"
                />
                <AppText variant="caption" style={[styles.helperText, { color: uiKitTheme.text.secondary }]}>
                  This category will be pre-selected when creating new transactions
                </AppText>
              </View>
            )}

            {/* Active Categories Section */}
            <View style={styles.section}>
              <AppText variant="body" style={[styles.sectionTitle, { color: uiKitTheme.text.primary }]}>
                Active Categories
              </AppText>

              {activeCategories.length > 0 ? (
                <DraggableCardList
                  items={activeCategories}
                  getItemId={(item) => item.id}
                  itemHeight={CATEGORY_ROW_HEIGHT}
                  renderItem={renderCategoryRow}
                  onReorder={handleReorder}
                  style={styles.draggableList}
                />
              ) : (
                <View style={styles.emptyState}>
                  <AppText variant="body" style={{ color: uiKitTheme.text.secondary }}>
                    No active categories. Add your first category below.
                  </AppText>
                </View>
              )}
            </View>

            {/* Add Category Button */}
            <AppButton
              title="Add Category"
              variant="primary"
              onPress={() => setEditingState({ mode: 'create' })}
              leftIcon={<MaterialIcons name="add" size={18} color={uiKitTheme.button.primary.text} />}
              style={styles.addButton}
            />

            {/* Archived Section */}
            {archivedCategories.length > 0 && (
              <View style={styles.section}>
                <Pressable
                  onPress={() => setShowArchived(!showArchived)}
                  style={({ pressed }) => [
                    styles.archivedToggle,
                    { borderTopColor: uiKitTheme.border.secondary },
                    pressed && styles.pressed,
                  ]}
                  accessibilityRole="button"
                  accessibilityLabel={showArchived ? 'Hide archived categories' : 'Show archived categories'}
                >
                  <MaterialIcons
                    name={showArchived ? 'expand-less' : 'expand-more'}
                    size={20}
                    color={uiKitTheme.text.secondary}
                  />
                  <AppText variant="body" style={{ color: uiKitTheme.text.secondary }}>
                    Archived ({archivedCategories.length})
                  </AppText>
                </Pressable>

                {showArchived && (
                  <View style={styles.archivedList}>
                    {archivedCategories.map((cat) => (
                      <ArchivedCategoryRow
                        key={cat.id}
                        id={cat.id}
                        name={cat.name}
                        isItemized={cat.metadata?.categoryType === 'itemized'}
                        isFee={cat.metadata?.categoryType === 'fee'}
                        excludeFromOverallBudget={cat.metadata?.excludeFromOverallBudget}
                        onUnarchive={() => handleUnarchive(cat.id)}
                      />
                    ))}
                  </View>
                )}
              </View>
            )}
          </>
        )}
      </Screen>

      {/* Category Form Modal */}
      {editingState && (
        <CategoryFormModal
          visible={true}
          onRequestClose={() => setEditingState(null)}
          mode={editingState.mode}
          initialData={
            editingState.mode === 'edit'
              ? {
                  name: editingState.category.name,
                  isItemized: editingState.category.metadata?.categoryType === 'itemized',
                  isFee: editingState.category.metadata?.categoryType === 'fee',
                  excludeFromOverallBudget: editingState.category.metadata?.excludeFromOverallBudget || false,
                }
              : undefined
          }
          onSave={handleSave}
          isSaving={false}
          error={saveError}
        />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  section: {
    marginBottom: 24,
    gap: 12,
  },
  sectionLabel: {
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
  },
  helperText: {
    fontSize: 12,
    lineHeight: 16,
  },
  draggableList: {
    marginHorizontal: -10,
  },
  addButton: {
    marginBottom: 24,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 40,
  },
  emptyState: {
    paddingVertical: 32,
    paddingHorizontal: 16,
    alignItems: 'center',
  },
  archivedToggle: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 12,
    paddingTop: 24,
    borderTopWidth: 1,
  },
  archivedList: {
    gap: 8,
  },
  pressed: {
    opacity: 0.7,
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
