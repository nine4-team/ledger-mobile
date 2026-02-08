import { useState, useEffect, useMemo } from 'react';
import { StyleSheet, View, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { AppScrollView } from '../../src/components/AppScrollView';
import { FormActions } from '../../src/components/FormActions';
import { FormField } from '../../src/components/FormField';
import { MediaGallerySection } from '../../src/components/MediaGallerySection';
import { CategoryBudgetInput } from '../../src/components/budget/CategoryBudgetInput';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { useTheme } from '../../src/theme/ThemeProvider';
import { layout, CARD_PADDING, getCardBaseStyle } from '../../src/ui';
import { useNetworkStatus } from '../../src/hooks/useNetworkStatus';
import { createProject, updateProject } from '../../src/data/projectService';
import { subscribeToBudgetCategories, type BudgetCategory } from '../../src/data/budgetCategoriesService';
import { setProjectBudgetCategory } from '../../src/data/projectBudgetCategoriesService';
import { saveLocalMedia, enqueueUpload, processUploadQueue, deleteLocalMediaByUrl } from '../../src/offline/media';
import { resolveAttachmentState } from '../../src/offline/media/mediaStore';
import type { AttachmentRef, AttachmentKind } from '../../src/offline/media/types';

export default function NewProjectScreen() {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();
  const { isOnline } = useNetworkStatus();
  const [name, setName] = useState('');
  const [clientName, setClientName] = useState('');
  const [description, setDescription] = useState('');
  const [selectedImage, setSelectedImage] = useState<AttachmentRef | null>(null);
  const [budgetCategories, setBudgetCategories] = useState<BudgetCategory[]>([]);
  const [isLoadingCategories, setIsLoadingCategories] = useState(true);
  const [localBudgets, setLocalBudgets] = useState<Record<string, number | null>>({});
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Subscribe to budget categories
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

  // Calculate total budget
  const totalBudgetCents = useMemo(() => {
    return Object.values(localBudgets).reduce((sum, cents) => sum + (cents ?? 0), 0);
  }, [localBudgets]);

  // Image handlers
  const handleAddImage = async (localUri: string, kind: AttachmentKind) => {
    try {
      console.log('[NewProject] Adding image:', localUri);
      const result = await saveLocalMedia({
        localUri,
        mimeType: 'image/jpeg',
        ownerScope: 'temp:new-project',
        persistCopy: false,
      });
      console.log('[NewProject] Image saved, mediaId:', result.mediaId);
      setSelectedImage({ url: result.attachmentRef.url, kind, isPrimary: true });
    } catch (err) {
      console.error('[NewProject] Failed to add image:', err);
      setError('Failed to add image. Please try again.');
    }
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

  const handleSubmit = async () => {
    // Validation
    if (!accountId) {
      setError('Select an account before creating a project.');
      return;
    }
    if (!name.trim() || !clientName.trim()) {
      setError('Project name and client name are required.');
      return;
    }
    if (!isOnline) {
      setError('Go online to create a project.');
      return;
    }
    if (isLoadingCategories) {
      setError('Budget categories are still loading.');
      return;
    }

    setError(null);
    setIsSubmitting(true);

    try {
      // 1. Create project
      const result = await createProject({
        accountId,
        name: name.trim(),
        clientName: clientName.trim(),
        description: description.trim() || null,
      });
      const { projectId } = result;

      // 2. Upload image if selected (non-blocking)
      let uploadError: string | null = null;
      if (selectedImage?.url.startsWith('offline://')) {
        try {
          const mediaId = selectedImage.url.replace('offline://', '');
          const destinationPath = `projects/${accountId}/${projectId}/main-image/${mediaId}.jpg`;
          await enqueueUpload({
            mediaId,
            destinationPath,
            idempotencyKey: `project-${projectId}-main-image`,
          });
          await processUploadQueue();
          const mediaState = resolveAttachmentState(selectedImage);
          if (mediaState.status === 'uploaded' && mediaState.record?.remoteUrl) {
            await updateProject(accountId, projectId, {
              mainImageUrl: mediaState.record.remoteUrl,
            });
          } else {
            uploadError = 'Image upload failed. You can re-upload from edit screen.';
          }
        } catch (err) {
          uploadError = 'Image upload failed. You can re-upload from edit screen.';
        }
      }

      // 3. Save budget categories (non-blocking)
      const budgetPromises = Object.entries(localBudgets)
        .filter(([_, cents]) => cents !== null && cents !== undefined)
        .map(([categoryId, cents]) =>
          setProjectBudgetCategory(accountId, projectId, categoryId, { budgetCents: cents })
        );
      await Promise.allSettled(budgetPromises);

      // 4. Navigate with warning if needed
      if (uploadError) {
        Alert.alert('Project Created', `Project created successfully. ${uploadError}`);
      }
      router.replace(`/project/${projectId}?tab=items`);

    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to create project.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Screen title="New Project" backTarget="/(tabs)/index" hideMenu includeBottomInset={false}>
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
          title={isSubmitting ? 'Creating…' : 'Create project'}
          onPress={handleSubmit}
          disabled={isSubmitting || isLoadingCategories}
          style={styles.actionButton}
        />
      </FormActions>
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
