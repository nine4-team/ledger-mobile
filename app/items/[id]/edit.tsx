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

type EditItemParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
};

function parseCurrency(value: string): number | null {
  const normalized = value.replace(/[^0-9.]/g, '');
  if (!normalized) return null;
  const num = Number.parseFloat(normalized);
  if (Number.isNaN(num)) return null;
  return Math.round(num * 100);
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
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form state
  const [name, setName] = useState('');
  const [source, setSource] = useState('');
  const [sku, setSku] = useState('');
  const [status, setStatus] = useState('');
  const [purchasePrice, setPurchasePrice] = useState('');
  const [projectPrice, setProjectPrice] = useState('');
  const [marketValue, setMarketValue] = useState('');
  const [notes, setNotes] = useState('');
  const [spaceId, setSpaceId] = useState<string | null>(null);

  const fallbackTarget = useMemo(() => {
    if (backTarget) return backTarget;
    if (id) return `/items/${id}`;
    if (scope === 'inventory') return '/(tabs)/screen-two?tab=items';
    if (scope === 'project' && projectId) return `/project/${projectId}?tab=items`;
    return '/(tabs)/index';
  }, [backTarget, id, projectId, scope]);

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
      if (next) {
        setName(next.name ?? '');
        setSource(next.source ?? '');
        setSku(next.sku ?? '');
        setStatus(next.status ?? '');
        setPurchasePrice(
          typeof next.purchasePriceCents === 'number' ? (next.purchasePriceCents / 100).toFixed(2) : ''
        );
        setProjectPrice(
          typeof next.projectPriceCents === 'number' ? (next.projectPriceCents / 100).toFixed(2) : ''
        );
        setMarketValue(
          typeof next.marketValueCents === 'number' ? (next.marketValueCents / 100).toFixed(2) : ''
        );
        setNotes(next.notes ?? '');
        setSpaceId(next.spaceId ?? null);
      }
    });
    return () => unsubscribe();
  }, [accountId, id]);

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
    await updateItem(accountId, id, { images: nextImages });
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
    await updateItem(accountId, id, { images: nextImages });
  };

  const handleSetPrimaryImage = async (attachment: AttachmentRef) => {
    if (!accountId || !id || !item) return;
    const nextImages = (item.images ?? []).map((image) => ({
      ...image,
      isPrimary: image.url === attachment.url,
    }));
    await updateItem(accountId, id, { images: nextImages });
  };

  const handleSave = async () => {
    if (!accountId || !id) return;
    const hasImages = (item?.images?.length ?? 0) > 0;
    if (!name.trim() && !sku.trim() && !hasImages) {
      setError('Add a name, SKU, or at least one image.');
      return;
    }
    setError(null);
    setIsSubmitting(true);
    try {
      await updateItem(accountId, id, {
        name: name.trim(),
        sku: sku.trim() || null,
        source: source.trim() || null,
        status: status.trim() || null,
        purchasePriceCents: parseCurrency(purchasePrice),
        projectPriceCents: parseCurrency(projectPrice),
        marketValueCents: parseCurrency(marketValue),
        notes: notes.trim() || null,
        spaceId,
      });
      router.replace(fallbackTarget);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to save item.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
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
                <FormField label="Name" value={name} onChangeText={setName} placeholder="Item name" />
                <FormField label="Source" value={source} onChangeText={setSource} placeholder="Source" />
                <FormField label="SKU" value={sku} onChangeText={setSku} placeholder="SKU" />
                <FormField label="Status" value={status} onChangeText={setStatus} placeholder="Status" />
              </View>
            </TitledCard>

            <TitledCard title="Pricing">
              <View style={styles.fieldGroup}>
                <FormField
                  label="Purchase price"
                  value={purchasePrice}
                  onChangeText={setPurchasePrice}
                  placeholder="$0.00"
                  inputProps={{ keyboardType: 'decimal-pad' }}
                />
                <FormField
                  label="Project price"
                  value={projectPrice}
                  onChangeText={setProjectPrice}
                  placeholder="$0.00"
                  inputProps={{ keyboardType: 'decimal-pad' }}
                />
                <FormField
                  label="Market value"
                  value={marketValue}
                  onChangeText={setMarketValue}
                  placeholder="$0.00"
                  inputProps={{ keyboardType: 'decimal-pad' }}
                />
              </View>
            </TitledCard>

            <TitledCard title="Location">
              <SpaceSelector
                projectId={item.projectId ?? null}
                value={spaceId}
                onChange={setSpaceId}
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
                value={notes}
                onChangeText={setNotes}
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
              title={isSubmitting ? 'Saving...' : 'Save'}
              onPress={handleSave}
              disabled={isSubmitting}
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
