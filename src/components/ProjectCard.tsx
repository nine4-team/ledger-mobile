import React, { useMemo } from 'react';
import { AppText } from './AppText';
import { ImageCard } from './ImageCard';
import { BudgetProgressPreview } from './budget/BudgetProgressPreview';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { resolveAttachmentUri } from '../offline/media';
import type { BudgetCategory } from '../data/budgetCategoriesService';
import type { ProjectBudgetCategory } from '../data/projectBudgetCategoriesService';
import type { BudgetProgress } from '../data/budgetProgressService';

export type ProjectCardProps = {
  projectId: string;
  name?: string | null;
  clientName?: string | null;
  mainImageUrl?: string | null;
  budgetCategories: BudgetCategory[];
  projectBudgetCategories: Record<string, ProjectBudgetCategory>;
  budgetProgress: BudgetProgress;
  pinnedCategoryIds: string[];
  onPress: () => void;
};

export function ProjectCard({
  name,
  clientName,
  mainImageUrl,
  budgetCategories,
  projectBudgetCategories,
  budgetProgress,
  pinnedCategoryIds,
  onPress,
}: ProjectCardProps) {
  const uiKitTheme = useUIKitTheme();

  const imageUri = useMemo(() => {
    if (!mainImageUrl) return null;
    const resolved = resolveAttachmentUri({ url: mainImageUrl, kind: 'image' });
    return resolved ?? (mainImageUrl.startsWith('offline://') ? null : mainImageUrl);
  }, [mainImageUrl]);

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
