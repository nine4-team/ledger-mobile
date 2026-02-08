import { useEffect, useState, useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { AppButton } from '../../../src/components/AppButton';
import { AppScrollView } from '../../../src/components/AppScrollView';
import { FormActions } from '../../../src/components/FormActions';
import { FormField } from '../../../src/components/FormField';
import { MediaGallerySection } from '../../../src/components/MediaGallerySection';
import { CategoryBudgetInput } from '../../../src/components/budget/CategoryBudgetInput';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { useTheme } from '../../../src/theme/ThemeProvider';
import { getCardBaseStyle } from '../../../src/ui/kit';
import { layout, CARD_PADDING } from '../../../src/ui';
import { Project, subscribeToProject, updateProject } from '../../../src/data/projectService';
import { subscribeToBudgetCategories } from '../../../src/data/budgetCategoriesService';
import { subscribeToProjectBudgetCategories, setProjectBudgetCategory } from '../../../src/data/projectBudgetCategoriesService';
import { saveLocalMedia, enqueueUpload, processUploadQueue, deleteLocalMediaByUrl, resolveAttachmentState } from '../../../src/offline/media';
import type { AttachmentRef, AttachmentKind, BudgetCategory, ProjectBudgetCategory } from '../../../src/data/types';

type EditParams = {
  projectId?: string;
};

export default function EditProjectScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<EditParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();

  // Form state
  const [project, setProject] = useState<Project | null>(null);
  const [name, setName] = useState('');
  const [clientName, setClientName] = useState('');
  const [description, setDescription] = useState('');
  const [selectedImage, setSelectedImage] = useState<AttachmentRef | null>(null);
  const [originalMainImageUrl, setOriginalMainImageUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Budget state
  const [budgetCategories, setBudgetCategories] = useState<BudgetCategory[]>([]);
  const [projectBudgetCategories, setProjectBudgetCategories] = useState<Record<string, ProjectBudgetCategory>>({});
  const [localBudgets, setLocalBudgets] = useState<Record<string, number | null>>({});

  // Loading state
  const [isLoadingProject, setIsLoadingProject] = useState(true);
  const [isLoadingCategories, setIsLoadingCategories] = useState(true);
  const [isLoadingProjectBudgets, setIsLoadingProjectBudgets] = useState(true);

  // Project data subscription
  useEffect(() => {
    if (!accountId || !projectId) return;
    setIsLoadingProject(true);
    const unsubscribe = subscribeToProject(accountId, projectId, (next) => {
      setProject(next);
      setName(next?.name ?? '');
      setClientName(next?.clientName ?? '');
      setDescription(next?.description ?? '');
      setOriginalMainImageUrl(next?.mainImageUrl ?? null);
      if (next?.mainImageUrl) {
        setSelectedImage({ url: next.mainImageUrl, kind: 'image', isPrimary: true });
      }
      setIsLoadingProject(false);
    });
    return unsubscribe;
  }, [accountId, projectId]);

  // Project budget categories subscription
  useEffect(() => {
    if (!accountId || !projectId) return;
    setIsLoadingProjectBudgets(true);
    const unsubscribe = subscribeToProjectBudgetCategories(accountId, projectId, (categories) => {
      const budgetsMap: Record<string, ProjectBudgetCategory> = {};
      const budgets: Record<string, number | null> = {};
      categories.forEach(pbc => {
        budgetsMap[pbc.id] = pbc;
        budgets[pbc.id] = pbc.budgetCents;
      });
      setProjectBudgetCategories(budgetsMap);
      setLocalBudgets(budgets);
      setIsLoadingProjectBudgets(false);
    });
    return unsubscribe;
  }, [accountId, projectId]);

  // Budget categories subscription
  useEffect(() => {
    if (!accountId) {
      setBudgetCategories([]);
      setIsLoadingCategories(false);
      return;
    }
    setIsLoadingCategories(true);
    const unsubscribe = subscribeToBudgetCategories(accountId, (categories) => {
      const active = categories.filter(c => !c.isArchived);
      setBudgetCategories(active);
      setIsLoadingCategories(false);
    });
    return unsubscribe;
  }, [accountId]);

  // Total budget calculation
  const totalBudgetCents = useMemo(() => {
    return Object.values(localBudgets).reduce((sum, cents) => sum + (cents ?? 0), 0);
  }, [localBudgets]);

  // Image handlers
  const handleAddImage = async (localUri: string, kind: AttachmentKind) => {
    const result = await saveLocalMedia({
      localUri,
      mimeType: 'image/jpeg',
      ownerScope: `projects/${accountId}/${projectId}`,
      persistCopy: false,
    });
    setSelectedImage({ url: result.attachmentRef.url, kind, isPrimary: true });
  };

  const handleRemoveImage = () => {
    if (selectedImage?.url.startsWith('offline://')) {
      deleteLocalMediaByUrl(selectedImage.url);
    }
    setSelectedImage(null);
  };

  // Budget handler
  const handleBudgetChange = (categoryId: string, cents: number | null) => {
    setLocalBudgets(prev => ({ ...prev, [categoryId]: cents }));
  };

  // Submit handler with change detection
  const handleSubmit = async () => {
    if (!accountId || !projectId) return;
    if (!name.trim() || !clientName.trim()) {
      setError('Project name and client name are required.');
      return;
    }

    setError(null);

    try {
      // 1. Update basic fields (fire-and-forget, only if changed)
      const updates: Partial<Project> = {};
      if (name.trim() !== project?.name) updates.name = name.trim();
      if (clientName.trim() !== project?.clientName) updates.clientName = clientName.trim();
      if (description.trim() !== (project?.description || '')) {
        updates.description = description.trim() || null;
      }
      if (Object.keys(updates).length > 0) {
        updateProject(accountId, projectId, updates)
          .catch(err => console.error('[projects] update failed:', err));
      }

      // 2. Handle image changes (keep await on Storage upload)
      const hasNewImage = selectedImage?.url.startsWith('offline://');
      const imageRemoved = originalMainImageUrl && !selectedImage;

      if (hasNewImage) {
        const mediaId = selectedImage!.url.replace('offline://', '');
        const destinationPath = `projects/${accountId}/${projectId}/main-image/${mediaId}.jpg`;
        try {
          await enqueueUpload({
            mediaId,
            destinationPath,
            idempotencyKey: `project-${projectId}-main-image`,
          });
          await processUploadQueue();
          const mediaState = resolveAttachmentState(selectedImage!);
          if (mediaState.status === 'uploaded' && mediaState.record?.remoteUrl) {
            updateProject(accountId, projectId, { mainImageUrl: mediaState.record.remoteUrl })
              .catch(err => console.error('[projects] update mainImageUrl failed:', err));
          }
        } catch (err) {
          console.error('[projects] image upload failed:', err);
        }
      } else if (imageRemoved) {
        updateProject(accountId, projectId, { mainImageUrl: null })
          .catch(err => console.error('[projects] clear mainImageUrl failed:', err));
      }

      // 3. Save changed budget categories (fire-and-forget)
      const changedBudgets = Object.entries(localBudgets).filter(([categoryId, cents]) => {
        const existing = projectBudgetCategories[categoryId]?.budgetCents;
        return cents !== existing;
      });
      const budgetPromises = changedBudgets.map(([categoryId, cents]) =>
        setProjectBudgetCategory(accountId, projectId, categoryId, { budgetCents: cents })
      );
      Promise.allSettled(budgetPromises).catch(err =>
        console.error('[projects] budget category writes failed:', err)
      );

      // 4. Navigate immediately
      router.replace(`/project/${projectId}?tab=items`);

    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to update project.';
      setError(message);
    }
  };

  const backTarget = projectId ? `/project/${projectId}?tab=items` : undefined;

  if (!projectId) {
    return (
      <Screen title="Edit Project" backTarget={backTarget} hideMenu>
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      </Screen>
    );
  }

  return (
    <Screen title="Edit Project" backTarget={backTarget} hideMenu includeBottomInset={false}>
      {isLoadingProject || isLoadingCategories || isLoadingProjectBudgets ? (
        <View style={styles.container}>
          <AppText variant="body">Loading project...</AppText>
        </View>
      ) : !project ? (
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      ) : (
        <>
        <AppScrollView style={styles.scroll} contentContainerStyle={styles.container}>
          {/* Section 1: Basic Info */}
          <FormField
            label="Project name"
            value={name}
            onChangeText={setName}
            placeholder="Enter project name"
          />
          <FormField
            label="Client name"
            value={clientName}
            onChangeText={setClientName}
            placeholder="Enter client name"
          />

          {/* Section 2: Description */}
          <FormField
            label="Description (optional)"
            value={description}
            onChangeText={setDescription}
            placeholder="Brief project description"
            inputProps={{ multiline: true, numberOfLines: 3, textAlignVertical: 'top' }}
          />

          {/* Section 3: Main Image */}
          <MediaGallerySection
            title="Main Project Image"
            attachments={selectedImage ? [selectedImage] : []}
            maxAttachments={1}
            allowedKinds={['image']}
            onAddAttachment={handleAddImage}
            onRemoveAttachment={handleRemoveImage}
            emptyStateMessage="Add a project image"
          />

          {/* Section 4: Budget Categories */}
          <View style={styles.budgetSection}>
            <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
              BUDGET ALLOCATION
            </AppText>

            {/* Total Budget Display */}
            <View style={[getCardBaseStyle(theme), styles.totalBudgetCard]}>
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                Total Budget
              </AppText>
              <AppText variant="h2">${(totalBudgetCents / 100).toFixed(2)}</AppText>
            </View>

            {/* Category Inputs */}
            {isLoadingCategories ? (
              <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                Loading budget categories...
              </AppText>
            ) : budgetCategories.length === 0 ? (
              <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                No budget categories created yet.
              </AppText>
            ) : (
              budgetCategories.map(category => (
                <CategoryBudgetInput
                  key={category.id}
                  categoryName={category.name}
                  budgetCents={localBudgets[category.id] ?? null}
                  onChange={(cents) => handleBudgetChange(category.id, cents)}
                />
              ))
            )}
          </View>

          {/* Error Display */}
          {error ? <AppText variant="caption" style={{ color: 'red' }}>{error}</AppText> : null}
        </AppScrollView>

        <FormActions>
          <AppButton title="Cancel" variant="secondary" onPress={() => router.back()} style={styles.actionButton} />
          <AppButton
            title="Save"
            onPress={handleSubmit}
            disabled={isLoadingCategories}
            style={styles.actionButton}
          />
        </FormActions>
        </>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  container: {
    gap: 16,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  budgetSection: {
    gap: 12,
  },
  totalBudgetCard: {
    padding: CARD_PADDING,
    gap: 4,
  },
  actionButton: {
    flex: 1,
  },
});
