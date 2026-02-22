import React, { useMemo } from 'react';
import { AppText } from './AppText';
import { ImageCard } from './ImageCard';
import { BudgetProgressPreview } from './budget/BudgetProgressPreview';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { resolveAttachmentUri } from '../offline/media';
import type { BudgetCategory } from '../data/budgetCategoriesService';
import type { ProjectBudgetCategory } from '../data/projectBudgetCategoriesService';
import type { BudgetProgress } from '../data/budgetProgressService';
import type { ProjectBudgetSummary } from '../data/projectService';

export type ProjectCardProps = {
  projectId: string;
  name?: string | null;
  clientName?: string | null;
  mainImageUrl?: string | null;
  budgetSummary: ProjectBudgetSummary | null;
  pinnedCategoryIds: string[];
  onPress: () => void;
};

export function ProjectCard({
  name,
  clientName,
  mainImageUrl,
  budgetSummary,
  pinnedCategoryIds,
  onPress,
}: ProjectCardProps) {
  const uiKitTheme = useUIKitTheme();

  const imageUri = useMemo(() => {
    if (!mainImageUrl) return null;
    const resolved = resolveAttachmentUri({ url: mainImageUrl, kind: 'image' });
    return resolved ?? (mainImageUrl.startsWith('offline://') ? null : mainImageUrl);
  }, [mainImageUrl]);

  // Adapt denormalized budgetSummary into the shapes BudgetProgressPreview expects
  const { budgetCategories, projectBudgetCategories, budgetProgress } = useMemo(() => {
    if (!budgetSummary) {
      return {
        budgetCategories: [] as BudgetCategory[],
        projectBudgetCategories: {} as Record<string, ProjectBudgetCategory>,
        budgetProgress: { spentCents: 0, spentByCategory: {} } as BudgetProgress,
      };
    }

    const cats: BudgetCategory[] = [];
    const projBudgetCats: Record<string, ProjectBudgetCategory> = {};
    const spentByCategory: Record<string, number> = {};

    for (const [catId, catData] of Object.entries(budgetSummary.categories)) {
      cats.push({
        id: catId,
        name: catData.name,
        isArchived: catData.isArchived,
        metadata: {
          categoryType: catData.categoryType as 'general' | 'itemized' | 'fee' | undefined,
          excludeFromOverallBudget: catData.excludeFromOverallBudget,
        },
      });
      projBudgetCats[catId] = {
        id: catId,
        budgetCents: catData.budgetCents,
      };
      spentByCategory[catId] = catData.spentCents;
    }

    return {
      budgetCategories: cats,
      projectBudgetCategories: projBudgetCats,
      budgetProgress: {
        spentCents: budgetSummary.spentCents,
        spentByCategory,
      },
    };
  }, [budgetSummary]);

  return (
    <ImageCard
      imageUri={imageUri}
      showPlaceholder={true}
      onPress={onPress}
      accessibilityLabel={`${name?.trim() || 'Project'}, ${clientName?.trim() || 'No client name'}`}
      accessibilityHint="Tap to view project"
    >
      <AppText variant="body" style={{ fontWeight: '600' }}>
        {name?.trim() || 'Project'}
      </AppText>
      <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
        {clientName?.trim() || 'No client name'}
      </AppText>
      <BudgetProgressPreview
        budgetCategories={budgetCategories}
        projectBudgetCategories={projectBudgetCategories}
        budgetProgress={budgetProgress}
        pinnedCategoryIds={pinnedCategoryIds}
        maxCategories={2}
      />
    </ImageCard>
  );
}
