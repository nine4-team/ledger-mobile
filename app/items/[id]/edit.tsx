import { useEffect, useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { AppButton } from '../../../src/components/AppButton';
import { AppScrollView } from '../../../src/components/AppScrollView';
import { FormField } from '../../../src/components/FormField';
import { FormActions } from '../../../src/components/FormActions';
import { TitledCard } from '../../../src/components/TitledCard';
import { MediaGallerySection } from '../../../src/components/MediaGallerySection';
import { SpaceSelector } from '../../../src/components/SpaceSelector';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { layout } from '../../../src/ui';
import { Item, subscribeToItem, updateItem } from '../../../src/data/itemsService';
import { saveLocalMedia, enqueueUpload, deleteLocalMediaByUrl } from '../../../src/offline/media';
import type { AttachmentRef, AttachmentKind } from '../../../src/offline/media';
import { useEditForm } from '../../../src/hooks/useEditForm';

type EditItemParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
};

interface ItemFormValues {
  name: string;
  source: string | null;
  sku: string | null;
  status: string | null;
  purchasePriceCents: number | null;
  projectPriceCents: number | null;
  marketValueCents: number | null;
  notes: string | null;
  spaceId: string | null;
}

function formatCentsToDisplay(cents: number): string {
  return (cents / 100).toFixed(2);
}

function parseDisplayToCents(display: string): number | null {
  const cleaned = display.replace(/[^0-9.]/g, '');
  if (!cleaned) return null;
  const dollars = parseFloat(cleaned);
  if (isNaN(dollars)) return null;
  return Math.round(dollars * 100);
}

export default function EditItemScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<EditItemParams>();
  const id = Array.isArray(params.id) ? params.id[0] : params.id;
  const scope = Array.isArray(params.scope) ? params.scope[0] : params.scope;
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const backTarget = Array.isArray(params.backTarget) ? params.backTarget[0] : params.backTarget;
  const accountId = useAccountContextStore((store) => store.accountId);

  const [item, setItem] = useState<Item | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Form state - using useEditForm hook for data model values
  const form = useEditForm<ItemFormValues>(
    item ? {
      name: item.name || '',
      source: item.source ?? null,
      sku: item.sku ?? null,
      status: item.status ?? null,
      purchasePriceCents: item.purchasePriceCents ?? null,
      projectPriceCents: item.projectPriceCents ?? null,
      marketValueCents: item.marketValueCents ?? null,
      notes: item.notes ?? null,
      spaceId: item.spaceId ?? null,
    } : null
  );

  // Display strings for price fields (UI-only state)
  const [purchasePriceDisplay, setPurchasePriceDisplay] = useState('');
  const [projectPriceDisplay, setProjectPriceDisplay] = useState('');
  const [marketValueDisplay, setMarketValueDisplay] = useState('');

  const fallbackTarget = useMemo(() => {
    if (backTarget) return backTarget;
    if (id) return `/items/${id}`;
    if (scope === 'inventory') return '/(tabs)/screen-two?tab=items';
    if (scope === 'project' && projectId) return `/project/${projectId}?tab=items`;
    return '/(tabs)/index';
  }, [backTarget, id, projectId, scope]);

  // Price change handlers - convert display string to cents and update form
  const handlePurchasePriceChange = (displayValue: string) => {
    setPurchasePriceDisplay(displayValue);
    const centsValue = parseDisplayToCents(displayValue);
    form.setField('purchasePriceCents', centsValue);
  };

  const handleProjectPriceChange = (displayValue: string) => {
    setProjectPriceDisplay(displayValue);
    const centsValue = parseDisplayToCents(displayValue);
    form.setField('projectPriceCents', centsValue);
  };

  const handleMarketValueChange = (displayValue: string) => {
    setMarketValueDisplay(displayValue);
    const centsValue = parseDisplayToCents(displayValue);
    form.setField('marketValueCents', centsValue);
  };

  useEffect(() => {
    if (!accountId || !id) {
      setItem(null);
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    const unsubscribe = subscribeToItem(accountId, id, (next) => {
      setItem(next);
      setIsLoading(false);
    });
    return () => unsubscribe();
  }, [accountId, id]);

  // Initialize and update display strings from item data (only when accepting subscription data)
  useEffect(() => {
    if (item && form.shouldAcceptSubscriptionData) {
      // Update display strings from cents values
      setPurchasePriceDisplay(
        item.purchasePriceCents !== null && item.purchasePriceCents !== undefined
          ? formatCentsToDisplay(item.purchasePriceCents)
          : ''
      );
      setProjectPriceDisplay(
        item.projectPriceCents !== null && item.projectPriceCents !== undefined
          ? formatCentsToDisplay(item.projectPriceCents)
          : ''
      );
      setMarketValueDisplay(
        item.marketValueCents !== null && item.marketValueCents !== undefined
          ? formatCentsToDisplay(item.marketValueCents)
          : ''
      );
    }
  }, [item, form.shouldAcceptSubscriptionData]);

  const handleAddImage = async (localUri: string, kind: AttachmentKind) => {
    if (!accountId || !id || !item) return;
    const mimeType = kind === 'pdf' ? 'application/pdf' : 'image/jpeg';
    const result = await saveLocalMedia({
      localUri,
      mimeType,
      ownerScope: `item:${id}`,
      persistCopy: false,
    });
    const hasPrimary = (item.images ?? []).some((image) => image.isPrimary);
    const newImage: AttachmentRef = {
      url: result.attachmentRef.url,
      kind,
      isPrimary: !hasPrimary && kind === 'image',
    };
    const nextImages: AttachmentRef[] = [...(item.images ?? []), newImage].slice(0, 5);
    updateItem(accountId, id, { images: nextImages });
    await enqueueUpload({ mediaId: result.mediaId });
  };

  const handleRemoveImage = async (attachment: AttachmentRef) => {
    if (!accountId || !id || !item) return;
    const nextImages = (item.images ?? []).filter((image) => image.url !== attachment.url);
    if (attachment.url.startsWith('offline://')) {
      await deleteLocalMediaByUrl(attachment.url);
    }
    if (!nextImages.some((image) => image.isPrimary) && nextImages.length > 0) {
      nextImages[0] = { ...nextImages[0], isPrimary: true };
    }
    updateItem(accountId, id, { images: nextImages });
  };

  const handleSetPrimaryImage = (attachment: AttachmentRef) => {
    if (!accountId || !id || !item) return;
    const nextImages = (item.images ?? []).map((image) => ({
      ...image,
      isPrimary: image.url === attachment.url,
    }));
    updateItem(accountId, id, { images: nextImages });
  };

  const handleSave = () => {
    if (!accountId || !id) return;

    // Check if there are any changes
    if (!form.hasChanges) {
      // No changes - skip write, just navigate
      router.replace(fallbackTarget);
      return;
    }

    // Get only changed fields
    const changedFields = form.getChangedFields();

    // Validate required fields - at least name, sku, or images
    const hasImages = (item?.images?.length ?? 0) > 0;
    const currentName = changedFields.name !== undefined ? changedFields.name : form.values.name;
    const currentSku = changedFields.sku !== undefined ? changedFields.sku : form.values.sku;

    if (!currentName.trim() && !currentSku?.trim() && !hasImages) {
      setError('Add a name, SKU, or at least one image.');
      return;
    }

    setError(null);

    // Fire-and-forget Firestore write (offline-first)
    updateItem(accountId, id, changedFields);

    // Navigate immediately
    router.replace(fallbackTarget);
  };

  if (!id) {
    return (
      <Screen title="Edit Item" backTarget={fallbackTarget} hideMenu>
        <View style={styles.container}>
          <AppText variant="body">Item not found.</AppText>
        </View>
      </Screen>
    );
  }

  return (
    <Screen title="Edit Item" backTarget={fallbackTarget} hideMenu includeBottomInset={false}>
      {isLoading ? (
        <View style={styles.container}>
          <AppText variant="body">Loading item...</AppText>
        </View>
      ) : !item ? (
        <View style={styles.container}>
          <AppText variant="body">Item not found.</AppText>
        </View>
      ) : (
        <>
          <AppScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent}>
            <TitledCard title="Details">
              <View style={styles.fieldGroup}>
                <FormField
                  label="Name"
                  value={form.values.name}
                  onChangeText={(val) => form.setField('name', val)}
                  placeholder="Item name"
                />
                <FormField
                  label="Source"
                  value={form.values.source ?? ''}
                  onChangeText={(val) => form.setField('source', val || null)}
                  placeholder="Source"
                />
                <FormField
                  label="SKU"
                  value={form.values.sku ?? ''}
                  onChangeText={(val) => form.setField('sku', val || null)}
                  placeholder="SKU"
                />
                <FormField
                  label="Status"
                  value={form.values.status ?? ''}
                  onChangeText={(val) => form.setField('status', val || null)}
                  placeholder="Status"
                />
              </View>
            </TitledCard>

            <TitledCard title="Pricing">
              <View style={styles.fieldGroup}>
                <FormField
                  label="Purchase price"
                  value={purchasePriceDisplay}
                  onChangeText={handlePurchasePriceChange}
                  placeholder="$0.00"
                  inputProps={{ keyboardType: 'decimal-pad' }}
                />
                <FormField
                  label="Project price"
                  value={projectPriceDisplay}
                  onChangeText={handleProjectPriceChange}
                  placeholder="$0.00"
                  inputProps={{ keyboardType: 'decimal-pad' }}
                />
                <FormField
                  label="Market value"
                  value={marketValueDisplay}
                  onChangeText={handleMarketValueChange}
                  placeholder="$0.00"
                  inputProps={{ keyboardType: 'decimal-pad' }}
                />
              </View>
            </TitledCard>

            <TitledCard title="Location">
              <SpaceSelector
                projectId={item.projectId ?? null}
                value={form.values.spaceId}
                onChange={(val) => form.setField('spaceId', val)}
                allowCreate={true}
                placeholder="Select space (optional)"
              />
            </TitledCard>

            <TitledCard title="Images">
              <MediaGallerySection
                title="Images"
                attachments={item.images ?? []}
                maxAttachments={5}
                allowedKinds={['image']}
                onAddAttachment={handleAddImage}
                onRemoveAttachment={handleRemoveImage}
                onSetPrimary={handleSetPrimaryImage}
                emptyStateMessage="No images yet."
                pickerLabel="Add image"
                size="md"
                tileScale={1.5}
              />
            </TitledCard>

            <TitledCard title="Notes">
              <FormField
                label="Notes"
                value={form.values.notes ?? ''}
                onChangeText={(val) => form.setField('notes', val || null)}
                placeholder="Add notes about this item..."
                inputProps={{ multiline: true, numberOfLines: 4, textAlignVertical: 'top' }}
              />
            </TitledCard>

            {error ? <AppText variant="caption" style={{ color: 'red' }}>{error}</AppText> : null}
          </AppScrollView>

          <FormActions>
            <AppButton
              title="Cancel"
              variant="secondary"
              onPress={() => router.back()}
              style={styles.actionButton}
            />
            <AppButton
              title="Save"
              onPress={handleSave}
              style={styles.actionButton}
            />
          </FormActions>
        </>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
    gap: 18,
  },
  fieldGroup: {
    gap: 12,
  },
  actionButton: {
    flex: 1,
  },
});
