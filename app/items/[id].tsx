import { useEffect, useMemo, useState } from 'react';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Alert, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { AppScrollView } from '../../src/components/AppScrollView';
import { BottomSheetMenuList } from '../../src/components/BottomSheetMenuList';
import type { AnchoredMenuItem } from '../../src/components/AnchoredMenuList';
import { TitledCard } from '../../src/components/TitledCard';
import { ThumbnailGrid } from '../../src/components/ThumbnailGrid';
import { ImageGallery } from '../../src/components/ImageGallery';
import {
  CARD_PADDING,
  getCardStyle,
  getTextColorStyle,
  getTextSecondaryStyle,
  layout,
  textEmphasis,
} from '../../src/ui';
import { useProjectContextStore } from '../../src/data/projectContextStore';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { getTextInputStyle } from '../../src/ui/styles/forms';
import { deleteItem, Item, subscribeToItem, updateItem } from '../../src/data/itemsService';
import {
  mapBudgetCategories,
  subscribeToBudgetCategories,
  type BudgetCategory,
} from '../../src/data/budgetCategoriesService';
import { subscribeToSpaces, type Space } from '../../src/data/spacesService';
import { getTransaction } from '../../src/data/transactionsService';
import {
  isCanonicalTransactionId,
  requestBusinessToProjectPurchase,
  requestProjectToBusinessSale,
  requestProjectToProjectMove,
} from '../../src/data/inventoryOperations';
import { deleteLocalMediaByUrl, resolveAttachmentUri, saveLocalMedia } from '../../src/offline/media';
import type { AttachmentRef } from '../../src/offline/media';

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

function formatMoney(cents: number | null | undefined): string {
  if (typeof cents !== 'number') return '—';
  return `$${(cents / 100).toFixed(2)}`;
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
  const [menuVisible, setMenuVisible] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [source, setSource] = useState('');
  const [status, setStatus] = useState('');
  const [sku, setSku] = useState('');
  const [purchasePrice, setPurchasePrice] = useState('');
  const [projectPrice, setProjectPrice] = useState('');
  const [marketValue, setMarketValue] = useState('');
  const [transactionId, setTransactionId] = useState('');
  const [targetProjectId, setTargetProjectId] = useState('');
  const [targetCategoryId, setTargetCategoryId] = useState('');
  const [budgetCategories, setBudgetCategories] = useState<Record<string, BudgetCategory>>({});
  const [spaces, setSpaces] = useState<Record<string, Space>>({});
  const [imageUrl, setImageUrl] = useState('');
  const [localImageUri, setLocalImageUri] = useState('');
  const [galleryVisible, setGalleryVisible] = useState(false);
  const [galleryIndex, setGalleryIndex] = useState(0);

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

  useEffect(() => {
    if (!accountId) {
      setBudgetCategories({});
      return () => {};
    }
    return subscribeToBudgetCategories(accountId, (next) => {
      setBudgetCategories(mapBudgetCategories(next));
    });
  }, [accountId]);

  useEffect(() => {
    if (!accountId) {
      setSpaces({});
      return () => {};
    }
    return subscribeToSpaces(accountId, projectId ?? null, (next) => {
      const nextMap = next.reduce((acc, space) => {
        acc[space.id] = space;
        return acc;
      }, {} as Record<string, Space>);
      setSpaces(nextMap);
    });
  }, [accountId, projectId]);

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
    if (!name.trim() && !sku.trim() && !hasImages) {
      setError('Add a name, SKU, or at least one image.');
      return;
    }
    const purchasePriceCents = parseCurrency(purchasePrice);
    const projectPriceCents = parseCurrency(projectPrice);
    const marketValueCents = parseCurrency(marketValue);
    setError(null);
    await updateItem(accountId, id, {
      name: name.trim(),
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

  const handleOpenTransaction = () => {
    const nextId = transactionId.trim();
    if (!nextId) return;
    router.push({
      pathname: '/transactions/[id]',
      params: {
        id: nextId,
        scope: scope ?? '',
        projectId: projectId ?? '',
        backTarget: id ? `/items/${id}` : '',
      },
    });
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
    const newImage: AttachmentRef = { url: nextUrl, kind: 'image', isPrimary: !hasPrimary };
    const nextImages: AttachmentRef[] = [...(item.images ?? []), newImage].slice(0, 5);
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

  const statusLabel = item?.status?.trim() || '';
  const trimmedTransactionId = transactionId.trim();
  const transactionLabel = trimmedTransactionId
    ? trimmedTransactionId.length > 8
      ? `${trimmedTransactionId.slice(0, 8)}…`
      : trimmedTransactionId
    : 'None';
  const spaceLabel = item?.spaceId
    ? spaces[item.spaceId]?.name?.trim() || item.spaceId
    : 'None';
  const budgetCategoryLabel = item?.inheritedBudgetCategoryId
    ? budgetCategories[item.inheritedBudgetCategoryId]?.name?.trim() || item.inheritedBudgetCategoryId
    : 'None';
  const locationLabel = useMemo(() => {
    if (scope === 'inventory') return 'Inventory';
    if (scope === 'project') return projectId ? `Project ${projectId}` : 'Project';
    return projectId ? `Project ${projectId}` : '—';
  }, [projectId, scope]);
  const menuItems = useMemo<AnchoredMenuItem[]>(() => {
    const items: AnchoredMenuItem[] = [
      {
        label: isEditing ? 'Finish editing' : 'Edit details',
        onPress: () => setIsEditing((prev) => !prev),
        icon: 'edit',
      },
    ];

    if (isEditing) {
      items.push({
        label: 'Save changes',
        onPress: handleSave,
        icon: 'save',
      });
    }

    items.push(
      {
        label: 'Add image',
        onPress: handleAddImage,
        icon: 'add-photo-alternate',
      },
      {
        label: 'Transaction',
        icon: 'link',
        subactions: [
          { key: 'link', label: 'Link transaction', onPress: handleLinkTransaction, icon: 'link' },
          { key: 'unlink', label: 'Unlink transaction', onPress: handleUnlinkTransaction, icon: 'link-off' },
        ],
      }
    );

    if (scope === 'inventory') {
      items.push({
        label: 'Move',
        icon: 'swap-horiz',
        subactions: [
          { key: 'allocate', label: 'Allocate to project', onPress: handleAllocateToProject, icon: 'assignment' },
        ],
      });
    } else {
      items.push({
        label: 'Move',
        icon: 'swap-horiz',
        subactions: [
          {
            key: 'move-to-business',
            label: 'Move to Business Inventory',
            onPress: handleMoveToInventoryCorrection,
            icon: 'inventory',
          },
          {
            key: 'sell-to-business',
            label: 'Sell to Design Business',
            onPress: handleSellToInventory,
            icon: 'sell',
          },
          { key: 'move-to-project', label: 'Move to project', onPress: handleMoveToProject, icon: 'assignment' },
        ],
      });
    }

    items.push({
      label: 'Delete item',
      onPress: handleDelete,
      icon: 'delete',
    });

    return items;
  }, [
    handleAddImage,
    handleAllocateToProject,
    handleDelete,
    handleLinkTransaction,
    handleMoveToInventoryCorrection,
    handleMoveToProject,
    handleSave,
    handleSellToInventory,
    handleUnlinkTransaction,
    isEditing,
    scope,
  ]);

  const headerActions = (
    <View style={styles.headerRight}>
      {statusLabel ? (
        <View style={[styles.statusPill, { backgroundColor: `${uiKitTheme.primary.main}1A` }]}>
          <AppText variant="caption" style={[styles.statusText, { color: uiKitTheme.primary.main }]}>
            {statusLabel}
          </AppText>
        </View>
      ) : null}
      <Pressable
        onPress={handleToggleBookmark}
        hitSlop={8}
        accessibilityRole="button"
        accessibilityLabel={(item?.bookmark ?? (item as any)?.isBookmarked) ? 'Remove bookmark' : 'Add bookmark'}
        style={styles.iconButton}
      >
        <MaterialIcons
          name={(item?.bookmark ?? (item as any)?.isBookmarked) ? 'bookmark' : 'bookmark-border'}
          size={24}
          color={
            (item?.bookmark ?? (item as any)?.isBookmarked)
              ? uiKitTheme.status.missed.text
              : uiKitTheme.text.secondary
          }
        />
      </Pressable>
    </View>
  );

  return (
    <Screen
      title=" "
      backTarget={fallbackTarget}
      headerRight={headerActions}
      onPressMenu={() => setMenuVisible(true)}
      contentStyle={styles.screenContent}
    >
      <AppScrollView style={styles.scroll} contentContainerStyle={styles.content}>
        {isLoading ? (
          <AppText variant="body">Loading item…</AppText>
        ) : item ? (
          <>
            <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
              <View style={styles.heroHeader}>
                <AppText variant="h2" style={styles.heroTitle}>
                  {item.name?.trim() || 'Untitled item'}
                </AppText>
                <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                  {item.projectId ? `Project ${item.projectId}` : ''}
                </AppText>
              </View>
            </View>

            {error ? (
              <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
                <AppText variant="caption" style={[styles.errorText, getTextSecondaryStyle(uiKitTheme)]}>
                  {error}
                </AppText>
              </View>
            ) : null}

            <TitledCard title="Images">
              {isEditing && (
                <View style={styles.form}>
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
                </View>
              )}

              {item.images && item.images.length > 0 ? (
                <ThumbnailGrid
                  images={item.images}
                  maxImages={5}
                  size="md"
                  tileScale={1.5}
                  onImagePress={(image, index) => {
                    setGalleryIndex(index);
                    setGalleryVisible(true);
                  }}
                  onSetPrimary={(image) => handleSetPrimaryImage(image.url)}
                  onDelete={(image) => handleRemoveImage(image.url)}
                  onAddImage={
                    isEditing && item.images.length < 5
                      ? () => {
                          handleAddImage();
                        }
                      : undefined
                  }
                />
              ) : (
                <View style={styles.emptyState}>
                  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                    No images yet.
                  </AppText>
                  {isEditing && (
                    <AppButton
                      title="Add image"
                      variant="secondary"
                      onPress={handleAddImage}
                      style={styles.addImageButton}
                    />
                  )}
                </View>
              )}
            </TitledCard>

            {item.images && item.images.length > 0 && (
              <ImageGallery
                images={item.images}
                initialIndex={galleryIndex}
                visible={galleryVisible}
                onRequestClose={() => setGalleryVisible(false)}
              />
            )}

            <TitledCard title="Details">
              {isEditing ? (
                <View style={styles.form}>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Name
                    </AppText>
                    <TextInput
                      value={name}
                      onChangeText={setName}
                      placeholder="Item name"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                    />
                  </View>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Status
                    </AppText>
                    <TextInput
                      value={status}
                      onChangeText={setStatus}
                      placeholder="needs_review / complete"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                    />
                  </View>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Source
                    </AppText>
                    <TextInput
                      value={source}
                      onChangeText={setSource}
                      placeholder="Source"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                    />
                  </View>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      SKU
                    </AppText>
                    <TextInput
                      value={sku}
                      onChangeText={setSku}
                      placeholder="SKU"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                    />
                  </View>
                  <View style={styles.formRow}>
                    <View style={styles.formHalf}>
                      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                        Purchase price
                      </AppText>
                      <TextInput
                        value={purchasePrice}
                        onChangeText={setPurchasePrice}
                        placeholder="$0.00"
                        placeholderTextColor={theme.colors.textSecondary}
                        style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                      />
                    </View>
                    <View style={styles.formHalf}>
                      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                        Project price
                      </AppText>
                      <TextInput
                        value={projectPrice}
                        onChangeText={setProjectPrice}
                        placeholder="$0.00"
                        placeholderTextColor={theme.colors.textSecondary}
                        style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                      />
                    </View>
                  </View>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Market value
                    </AppText>
                    <TextInput
                      value={marketValue}
                      onChangeText={setMarketValue}
                      placeholder="$0.00"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                    />
                  </View>
                </View>
              ) : (
                <View style={styles.detailRows}>
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Source
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {item.source?.trim() || '—'}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      SKU
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {item.sku?.trim() || '—'}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Purchase price
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {formatMoney(item.purchasePriceCents)}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Project price
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {formatMoney(item.projectPriceCents)}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Market value
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {formatMoney(item.marketValueCents)}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Space
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {spaceLabel}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Budget category
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {budgetCategoryLabel}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Transaction
                    </AppText>
                    {trimmedTransactionId ? (
                      <Pressable accessibilityRole="link" onPress={handleOpenTransaction}>
                        <AppText
                          variant="body"
                          style={[
                            styles.valueText,
                            textEmphasis.value,
                            styles.linkText,
                            getTextColorStyle(uiKitTheme.link),
                          ]}
                        >
                          {transactionLabel}
                        </AppText>
                      </Pressable>
                    ) : (
                      <AppText
                        variant="body"
                        style={[styles.valueText, textEmphasis.value, getTextSecondaryStyle(uiKitTheme)]}
                      >
                        {transactionLabel}
                      </AppText>
                    )}
                  </View>
                </View>
              )}
            </TitledCard>

            {scope !== 'inventory' ? (
              <TitledCard title="Move item">
                  <View style={styles.form}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Move to another project
                    </AppText>
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
                  </View>
              </TitledCard>
            ) : null}
            <BottomSheetMenuList
              visible={menuVisible}
              onRequestClose={() => setMenuVisible(false)}
              items={menuItems}
              title="Item actions"
              showLeadingIcons={true}
            />
          </>
        ) : (
          <AppText variant="body">Item not found.</AppText>
        )}
      </AppScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  content: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
    paddingBottom: 24,
    gap: 18,
  },
  screenContent: {
    paddingTop: 0,
  },
  card: {},
  heroHeader: {
    gap: 6,
  },
  heroTitle: {
    // Let long names wrap, but keep the screen feeling deliberate.
    lineHeight: 26,
  },
  heroDescription: {
    marginTop: 10,
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  linkText: {
    textDecorationLine: 'underline',
  },
  iconButton: {
    padding: 6,
    minWidth: 32,
    minHeight: 32,
    alignItems: 'center',
    justifyContent: 'center',
  },
  statusPill: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 999,
    maxWidth: '70%',
  },
  statusText: {
    fontWeight: '600',
    textTransform: 'capitalize',
  },
  errorText: {
    lineHeight: 18,
  },
  form: {
    gap: 12,
  },
  formGroup: {
    gap: 8,
  },
  formRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
  },
  formHalf: {
    flex: 1,
  },
  detailRows: {
    gap: 12,
  },
  detailRow: {
    ...layout.rowBetween,
    alignItems: 'flex-start',
    gap: 12,
  },
  valueText: {
    flexShrink: 1,
    textAlign: 'right',
  },
  divider: {
    borderTopWidth: 1,
  },
  imageList: {
    gap: 8,
  },
  imageRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
    paddingVertical: 10,
  },
  imageText: {
    flex: 1,
    gap: 4,
  },
  imageUrl: {
    flexShrink: 1,
  },
  imageActions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
    justifyContent: 'flex-end',
    alignItems: 'center',
    maxWidth: 240,
  },
  emptyState: {
    alignItems: 'center',
    gap: 12,
    paddingVertical: 16,
  },
  addImageButton: {
    marginTop: 8,
  },
});
