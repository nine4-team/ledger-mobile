import { useEffect, useMemo, useState } from 'react';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Alert, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { AppScrollView } from '../../../src/components/AppScrollView';
import { BottomSheetMenuList } from '../../../src/components/BottomSheetMenuList';
import type { AnchoredMenuItem } from '../../../src/components/AnchoredMenuList';
import { TitledCard } from '../../../src/components/TitledCard';
import { MediaGallerySection } from '../../../src/components/MediaGallerySection';
import { NotesSection } from '../../../src/components/NotesSection';
import {
  CARD_PADDING,
  getCardStyle,
  getTextColorStyle,
  getTextSecondaryStyle,
  layout,
  textEmphasis,
} from '../../../src/ui';
import { useProjectContextStore } from '../../../src/data/projectContextStore';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../../src/theme/ThemeProvider';
import { getTextInputStyle } from '../../../src/ui/styles/forms';
import { deleteItem, Item, subscribeToItem, updateItem } from '../../../src/data/itemsService';
import {
  mapBudgetCategories,
  subscribeToBudgetCategories,
  type BudgetCategory,
} from '../../../src/data/budgetCategoriesService';
import { subscribeToSpaces, type Space } from '../../../src/data/spacesService';
import { getTransaction } from '../../../src/data/transactionsService';
import {
  isCanonicalTransactionId,
  requestBusinessToProjectPurchase,
  requestProjectToBusinessSale,
  requestProjectToProjectMove,
} from '../../../src/data/inventoryOperations';
import { deleteLocalMediaByUrl, resolveAttachmentUri, saveLocalMedia, enqueueUpload } from '../../../src/offline/media';
import type { AttachmentRef, AttachmentKind } from '../../../src/offline/media';

type ItemDetailParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
  listStateKey?: string;
};

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
  const [menuVisible, setMenuVisible] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [transactionId, setTransactionId] = useState('');
  const [targetProjectId, setTargetProjectId] = useState('');
  const [targetCategoryId, setTargetCategoryId] = useState('');
  const [budgetCategories, setBudgetCategories] = useState<Record<string, BudgetCategory>>({});
  const [spaces, setSpaces] = useState<Record<string, Space>>({});

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

  const handleLinkTransaction = async () => {
    if (!accountId || !id || !transactionId.trim()) return;
    const transaction = await getTransaction(accountId, transactionId.trim(), 'offline');
    if (!transaction) {
      setError('Transaction not found.');
      return;
    }
    const isCanonical = isCanonicalTransactionId(transaction.id);
    const update: Partial<Item> = { transactionId: transaction.id };
    if (!isCanonical && transaction.budgetCategoryId) {
      update.budgetCategoryId = transaction.budgetCategoryId;
    }
    updateItem(accountId, id, update);
    setError(null);
  };

  const handleUnlinkTransaction = () => {
    if (!accountId || !id) return;
    updateItem(accountId, id, { transactionId: null });
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

    // Enqueue upload in background
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

  const handleToggleBookmark = () => {
    if (!accountId || !id || !item) return;
    const next = !(item.bookmark ?? (item as any).isBookmarked);
    updateItem(accountId, id, { bookmark: next });
  };

  const handleSellToInventory = async () => {
    if (!accountId || !id || !projectId) return;
    if (!item?.budgetCategoryId) {
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

  const handleMoveToInventoryCorrection = () => {
    if (!accountId || !id || !item) return;
    if (item.transactionId) {
      setError('This item is tied to a transaction. Move the transaction instead.');
      return;
    }
    updateItem(accountId, id, { projectId: null, transactionId: null, spaceId: null });
  };

  const handleAllocateToProject = async () => {
    if (!accountId || !id || !targetProjectId.trim() || !targetCategoryId.trim() || !item) return;
    await requestBusinessToProjectPurchase({
      accountId,
      targetProjectId: targetProjectId.trim(),
      budgetCategoryId: targetCategoryId.trim(),
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
      budgetCategoryId: targetCategoryId.trim(),
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
        onPress: () => {
          deleteItem(accountId, id);
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
    ? spaces[item.spaceId]?.name?.trim() || 'Unknown space'
    : 'None';
  const budgetCategoryLabel = item?.budgetCategoryId
    ? budgetCategories[item.budgetCategoryId]?.name?.trim() || item.budgetCategoryId
    : 'None';
  const locationLabel = useMemo(() => {
    if (scope === 'inventory') return 'Inventory';
    if (scope === 'project') return projectId ? `Project ${projectId}` : 'Project';
    return projectId ? `Project ${projectId}` : '—';
  }, [projectId, scope]);
  const menuItems = useMemo<AnchoredMenuItem[]>(() => {
    const items: AnchoredMenuItem[] = [
      {
        label: 'Edit details',
        onPress: () => {
          router.push({
            pathname: '/items/[id]/edit',
            params: {
              id: id!,
              scope: scope ?? '',
              projectId: projectId ?? '',
            },
          });
        },
        icon: 'edit',
      },
    ];

    items.push({
      label: 'Transaction',
      icon: 'link',
      subactions: [
        { key: 'link', label: 'Link transaction', onPress: handleLinkTransaction, icon: 'link' },
        { key: 'unlink', label: 'Unlink transaction', onPress: handleUnlinkTransaction, icon: 'link-off' },
      ],
    });

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
    handleAllocateToProject,
    handleDelete,
    handleLinkTransaction,
    handleMoveToInventoryCorrection,
    handleMoveToProject,
    handleSellToInventory,
    handleUnlinkTransaction,
    id,
    projectId,
    router,
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
                <View style={styles.heroSubtitle}>
                  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                    Transaction:{' '}
                  </AppText>
                  {trimmedTransactionId ? (
                    <Pressable accessibilityRole="link" onPress={handleOpenTransaction}>
                      <AppText
                        variant="caption"
                        style={[
                          styles.linkText,
                          getTextColorStyle(uiKitTheme.link),
                        ]}
                      >
                        {transactionLabel}
                      </AppText>
                    </Pressable>
                  ) : (
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      None
                    </AppText>
                  )}
                </View>
              </View>
            </View>

            {error ? (
              <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
                <AppText variant="caption" style={[styles.errorText, getTextSecondaryStyle(uiKitTheme)]}>
                  {error}
                </AppText>
              </View>
            ) : null}

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

            <NotesSection notes={item.notes} expandable={true} />

            <TitledCard title="Details">
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
              </View>
            </TitledCard>

            {scope !== 'inventory' ? (
              <TitledCard title="Move item">
                  <View style={styles.moveForm}>
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
  heroSubtitle: {
    flexDirection: 'row',
    alignItems: 'center',
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
  moveForm: {
    gap: 12,
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
