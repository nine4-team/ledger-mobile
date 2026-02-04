import { useEffect, useMemo, useState } from 'react';
import { Alert, StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { layout } from '../../src/ui';
import { useProjectContextStore } from '../../src/data/projectContextStore';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { getTextInputStyle } from '../../src/ui/styles/forms';
import { deleteItem, Item, subscribeToItem, updateItem } from '../../src/data/itemsService';
import { getTransaction } from '../../src/data/transactionsService';
import {
  isCanonicalTransactionId,
  requestBusinessToProjectPurchase,
  requestProjectToBusinessSale,
  requestProjectToProjectMove,
} from '../../src/data/inventoryOperations';
import { deleteLocalMediaByUrl, resolveAttachmentUri, saveLocalMedia } from '../../src/offline/media';

type ItemDetailParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
  listStateKey?: string;
};

function parseCurrency(value: string): number | null {
  const normalized = value.replace(/[^0-9.]/g, '');
  if (!normalized) return null;
  const num = Number.parseFloat(normalized);
  if (Number.isNaN(num)) return null;
  return Math.round(num * 100);
}

export default function ItemDetailScreen() {
  const router = useRouter();
  const { setProjectId } = useProjectContextStore();
  const accountId = useAccountContextStore((store) => store.accountId);
  const params = useLocalSearchParams<ItemDetailParams>();
  const id = Array.isArray(params.id) ? params.id[0] : params.id;
  const scope = Array.isArray(params.scope) ? params.scope[0] : params.scope;
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const backTarget = Array.isArray(params.backTarget) ? params.backTarget[0] : params.backTarget;
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [item, setItem] = useState<Item | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isEditing, setIsEditing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [source, setSource] = useState('');
  const [status, setStatus] = useState('');
  const [sku, setSku] = useState('');
  const [purchasePrice, setPurchasePrice] = useState('');
  const [projectPrice, setProjectPrice] = useState('');
  const [marketValue, setMarketValue] = useState('');
  const [transactionId, setTransactionId] = useState('');
  const [targetProjectId, setTargetProjectId] = useState('');
  const [targetCategoryId, setTargetCategoryId] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [localImageUri, setLocalImageUri] = useState('');

  useEffect(() => {
    if (scope === 'project' && projectId) {
      setProjectId(projectId);
    }
  }, [projectId, scope, setProjectId]);

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
        setDescription(next.description ?? '');
        setSource(next.source ?? '');
        setStatus(next.status ?? '');
        setSku(next.sku ?? '');
        setPurchasePrice(
          typeof next.purchasePriceCents === 'number' ? (next.purchasePriceCents / 100).toFixed(2) : ''
        );
        setProjectPrice(
          typeof next.projectPriceCents === 'number' ? (next.projectPriceCents / 100).toFixed(2) : ''
        );
        setMarketValue(
          typeof next.marketValueCents === 'number' ? (next.marketValueCents / 100).toFixed(2) : ''
        );
        setTransactionId(next.transactionId ?? '');
      }
    });
    return () => unsubscribe();
  }, [accountId, id]);

  const fallbackTarget = useMemo(() => {
    if (backTarget) return backTarget;
    if (scope === 'inventory') return '/(tabs)/screen-two?tab=items';
    if (scope === 'project' && projectId) return `/project/${projectId}?tab=items`;
    return '/(tabs)/index';
  }, [backTarget, projectId, scope]);

  const handleBack = () => {
    if (router.canGoBack()) {
      router.back();
      return;
    }
    router.replace(fallbackTarget);
  };

  const handleSave = async () => {
    if (!accountId || !id) return;
    const hasImages = (item?.images?.length ?? 0) > 0;
    if (!description.trim() && !sku.trim() && !hasImages) {
      setError('Add a description, SKU, or at least one image.');
      return;
    }
    const purchasePriceCents = parseCurrency(purchasePrice);
    const projectPriceCents = parseCurrency(projectPrice) ?? purchasePriceCents ?? null;
    const marketValueCents = parseCurrency(marketValue);
    setError(null);
    await updateItem(accountId, id, {
      name: name.trim() || null,
      description: description.trim() || null,
      sku: sku.trim() || null,
      source: source.trim() || null,
      status: status.trim() || null,
      purchasePriceCents,
      projectPriceCents,
      marketValueCents,
    });
    setIsEditing(false);
  };

  const handleLinkTransaction = async () => {
    if (!accountId || !id || !transactionId.trim()) return;
    const transaction = await getTransaction(accountId, transactionId.trim(), 'online');
    if (!transaction) {
      setError('Transaction not found.');
      return;
    }
    const isCanonical = isCanonicalTransactionId(transaction.id);
    const update: Partial<Item> = { transactionId: transaction.id };
    if (!isCanonical && transaction.budgetCategoryId) {
      update.inheritedBudgetCategoryId = transaction.budgetCategoryId;
    }
    await updateItem(accountId, id, update);
    setError(null);
  };

  const handleUnlinkTransaction = async () => {
    if (!accountId || !id) return;
    await updateItem(accountId, id, { transactionId: null });
  };

  const handleAddImage = async () => {
    if (!accountId || !id || !item) return;
    let nextUrl = imageUrl.trim();
    if (!nextUrl && localImageUri.trim()) {
      const result = await saveLocalMedia({
        localUri: localImageUri.trim(),
        mimeType: 'image/jpeg',
        ownerScope: `item:${id}`,
        persistCopy: false,
      });
      nextUrl = result.attachmentRef.url;
    }
    if (!nextUrl) return;
    const hasPrimary = (item.images ?? []).some((image) => image.isPrimary);
    const nextImages = [
      ...(item.images ?? []),
      { url: nextUrl, kind: 'image', isPrimary: !hasPrimary },
    ].slice(0, 5);
    await updateItem(accountId, id, { images: nextImages });
    setImageUrl('');
    setLocalImageUri('');
  };

  const handleRemoveImage = async (url: string) => {
    if (!accountId || !id || !item) return;
    const nextImages = (item.images ?? []).filter((image) => image.url !== url);
    if (url.startsWith('offline://')) {
      await deleteLocalMediaByUrl(url);
    }
    if (!nextImages.some((image) => image.isPrimary) && nextImages.length > 0) {
      nextImages[0] = { ...nextImages[0], isPrimary: true };
    }
    await updateItem(accountId, id, { images: nextImages });
  };

  const handleSetPrimaryImage = async (url: string) => {
    if (!accountId || !id || !item) return;
    const nextImages = (item.images ?? []).map((image) => ({
      ...image,
      isPrimary: image.url === url,
    }));
    await updateItem(accountId, id, { images: nextImages });
  };

  const handleToggleBookmark = async () => {
    if (!accountId || !id || !item) return;
    const next = !(item.bookmark ?? (item as any).isBookmarked);
    await updateItem(accountId, id, { bookmark: next });
  };

  const handleSellToInventory = async () => {
    if (!accountId || !id || !projectId) return;
    if (!item?.inheritedBudgetCategoryId) {
      setError(
        "Can’t move to Design Business Inventory yet. Link this item to a categorized transaction first."
      );
      return;
    }
    await requestProjectToBusinessSale({
      accountId,
      projectId,
      items: [item],
    });
    setError(null);
  };

  const handleMoveToInventoryCorrection = async () => {
    if (!accountId || !id || !item) return;
    if (item.transactionId) {
      setError('This item is tied to a transaction. Move the transaction instead.');
      return;
    }
    await updateItem(accountId, id, { projectId: null, transactionId: null, spaceId: null });
  };

  const handleAllocateToProject = async () => {
    if (!accountId || !id || !targetProjectId.trim() || !targetCategoryId.trim() || !item) return;
    await requestBusinessToProjectPurchase({
      accountId,
      targetProjectId: targetProjectId.trim(),
      inheritedBudgetCategoryId: targetCategoryId.trim(),
      items: [item],
    });
    setTargetProjectId('');
    setTargetCategoryId('');
  };

  const handleMoveToProject = async () => {
    if (!accountId || !id || !projectId || !targetProjectId.trim() || !targetCategoryId.trim() || !item) return;
    await requestProjectToProjectMove({
      accountId,
      sourceProjectId: projectId,
      targetProjectId: targetProjectId.trim(),
      inheritedBudgetCategoryId: targetCategoryId.trim(),
      items: [item],
    });
    setTargetProjectId('');
    setTargetCategoryId('');
  };

  const handleDelete = () => {
    if (!accountId || !id) return;
    Alert.alert('Delete item', 'This will permanently delete this item.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          await deleteItem(accountId, id);
          router.replace(fallbackTarget);
        },
      },
    ]);
  };

  return (
    <Screen title="Item">
      <View style={styles.container}>
        <AppButton title="Back" variant="secondary" onPress={handleBack} />
        <AppText variant="title">Item detail</AppText>
        {isLoading ? (
          <AppText variant="body">Loading item…</AppText>
        ) : item ? (
          <>
            <View style={styles.actions}>
              <AppButton
                title={isEditing ? 'Cancel edit' : 'Edit'}
                variant="secondary"
                onPress={() => setIsEditing((prev) => !prev)}
              />
              <AppButton title="Delete" variant="secondary" onPress={handleDelete} />
              <AppButton
                title={(item.bookmark ?? (item as any).isBookmarked) ? 'Bookmarked' : 'Bookmark'}
                variant="secondary"
                onPress={handleToggleBookmark}
              />
            </View>
            {isEditing ? (
              <>
                <AppText variant="body">Name</AppText>
                <TextInput
                  value={name}
                  onChangeText={setName}
                  placeholder="Item name"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <AppText variant="body">Description</AppText>
                <TextInput
                  value={description}
                  onChangeText={setDescription}
                  placeholder="Description"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                  multiline
                />
                <AppText variant="body">Source</AppText>
                <TextInput
                  value={source}
                  onChangeText={setSource}
                  placeholder="Source"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <AppText variant="body">SKU</AppText>
                <TextInput
                  value={sku}
                  onChangeText={setSku}
                  placeholder="SKU"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <AppText variant="body">Status</AppText>
                <TextInput
                  value={status}
                  onChangeText={setStatus}
                  placeholder="needs_review / complete"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <AppText variant="body">Purchase price</AppText>
                <TextInput
                  value={purchasePrice}
                  onChangeText={setPurchasePrice}
                  placeholder="$0.00"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <AppText variant="body">Project price</AppText>
                <TextInput
                  value={projectPrice}
                  onChangeText={setProjectPrice}
                  placeholder="$0.00"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <AppText variant="body">Market value</AppText>
                <TextInput
                  value={marketValue}
                  onChangeText={setMarketValue}
                  placeholder="$0.00"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <AppButton title="Save" onPress={handleSave} />
              </>
            ) : (
              <>
                <AppText variant="body">Name: {item.name?.trim() || 'Untitled item'}</AppText>
                <AppText variant="body">Description: {item.description?.trim() || '—'}</AppText>
                <AppText variant="body">Status: {item.status ?? '—'}</AppText>
                <AppText variant="body">Source: {item.source ?? '—'}</AppText>
                <AppText variant="body">SKU: {item.sku ?? '—'}</AppText>
                <AppText variant="body">
                  Purchase price:{' '}
                  {typeof item.purchasePriceCents === 'number' ? `$${(item.purchasePriceCents / 100).toFixed(2)}` : '—'}
                </AppText>
                <AppText variant="body">
                  Project price:{' '}
                  {typeof item.projectPriceCents === 'number' ? `$${(item.projectPriceCents / 100).toFixed(2)}` : '—'}
                </AppText>
                <AppText variant="body">
                  Market value:{' '}
                  {typeof item.marketValueCents === 'number' ? `$${(item.marketValueCents / 100).toFixed(2)}` : '—'}
                </AppText>
              </>
            )}
            <AppText variant="caption">Scope: {scope ?? 'Unknown'}</AppText>
            {item.projectId ? <AppText variant="caption">Project: {item.projectId}</AppText> : null}
            <AppText variant="body">Images</AppText>
            <TextInput
              value={imageUrl}
              onChangeText={setImageUrl}
              placeholder="Image URL"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
            />
            <TextInput
              value={localImageUri}
              onChangeText={setLocalImageUri}
              placeholder="Local image URI (offline)"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
            />
            <AppButton title="Add image" onPress={handleAddImage} />
            {item.images?.length ? (
              <View style={styles.imageList}>
                {item.images.map((image) => (
                  <View key={image.url} style={styles.row}>
                    <AppText variant="caption">
                      {resolveAttachmentUri(image) ?? (image.url.startsWith('offline://') ? 'Offline image' : image.url)}
                    </AppText>
                    <View style={styles.actions}>
                      <AppButton
                        title={image.isPrimary ? 'Primary' : 'Set primary'}
                        variant="secondary"
                        onPress={() => handleSetPrimaryImage(image.url)}
                      />
                      <AppButton title="Remove" variant="secondary" onPress={() => handleRemoveImage(image.url)} />
                    </View>
                  </View>
                ))}
              </View>
            ) : (
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                No images yet.
              </AppText>
            )}
            <AppText variant="body">Link transaction</AppText>
            <TextInput
              value={transactionId}
              onChangeText={setTransactionId}
              placeholder="Transaction id"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
            />
            <View style={styles.actions}>
              <AppButton title="Link" variant="secondary" onPress={handleLinkTransaction} />
              <AppButton title="Unlink" variant="secondary" onPress={handleUnlinkTransaction} />
            </View>
            {scope === 'inventory' ? (
              <>
                <AppText variant="body">Allocate to project</AppText>
                <TextInput
                  value={targetProjectId}
                  onChangeText={setTargetProjectId}
                  placeholder="Target project id"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <TextInput
                  value={targetCategoryId}
                  onChangeText={setTargetCategoryId}
                  placeholder="Destination category id"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <AppButton title="Allocate" onPress={handleAllocateToProject} />
              </>
            ) : (
              <>
                <AppButton
                  title="Move to Business Inventory"
                  variant="secondary"
                  onPress={handleMoveToInventoryCorrection}
                />
                <AppButton
                  title="Sell to Design Business"
                  variant="secondary"
                  onPress={handleSellToInventory}
                />
                <AppText variant="body">Move to another project</AppText>
                <TextInput
                  value={targetProjectId}
                  onChangeText={setTargetProjectId}
                  placeholder="Target project id"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <TextInput
                  value={targetCategoryId}
                  onChangeText={setTargetCategoryId}
                  placeholder="Destination category id"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <AppButton title="Move to project" onPress={handleMoveToProject} />
              </>
            )}
            {error ? (
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                {error}
              </AppText>
            ) : null}
          </>
        ) : (
          <AppText variant="body">Item not found.</AppText>
        )}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
  imageList: {
    gap: 8,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  },
});
