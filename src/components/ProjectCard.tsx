import React, { useMemo } from 'react';
import { Image, Pressable, StyleSheet, View } from 'react-native';
import { AppText } from './AppText';
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
  projectId,
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

  // Determine if image should be rendered and resolve URI
  const { shouldShowImage, imageUri } = useMemo(() => {
    if (!mainImageUrl) {
      return { shouldShowImage: false, imageUri: null };
    }

    // For offline URLs, check if they can be resolved
    if (mainImageUrl.startsWith('offline://')) {
      const resolved = resolveAttachmentUri({ url: mainImageUrl, kind: 'image' });
      return {
        shouldShowImage: resolved !== null,
        imageUri: resolved,
      };
    }

    // For online URLs, try to resolve and fallback to original
    const resolved = resolveAttachmentUri({ url: mainImageUrl, kind: 'image' });
    return {
      shouldShowImage: true,
      imageUri: resolved ?? mainImageUrl,
    };
  }, [mainImageUrl]);

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.card,
        {
          borderColor: uiKitTheme.border.primary,
          backgroundColor: uiKitTheme.background.surface,
          opacity: pressed ? 0.8 : 1,
        },
      ]}
    >
      {/* Conditionally render image section */}
      {shouldShowImage && imageUri && (
        <Image
          source={{ uri: imageUri }}
          style={styles.image}
          resizeMode="cover"
        />
      )}

      {/* Project info */}
      <AppText variant="body" style={styles.title}>
        {name?.trim() || 'Project'}
      </AppText>

      <AppText variant="caption" style={styles.subtitle}>
        {clientName?.trim() || 'No client name'}
      </AppText>

      {/* Budget preview - uses BudgetProgressPreview */}
      <BudgetProgressPreview
        budgetCategories={budgetCategories}
        projectBudgetCategories={projectBudgetCategories}
        budgetProgress={budgetProgress}
        pinnedCategoryIds={pinnedCategoryIds}
        maxCategories={2}
      />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 14,
    gap: 6,
  },
  image: {
    width: '100%',
    height: 120,
    borderRadius: 10,
  },
  title: {
    fontWeight: '600',
  },
  subtitle: {
    marginTop: 4,
  },
});
