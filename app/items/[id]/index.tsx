import { useCallback, useEffect, useMemo, useState } from 'react';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Alert, Pressable, ScrollView, SectionList, StyleSheet, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { BottomSheetMenuList } from '../../../src/components/BottomSheetMenuList';
import type { AnchoredMenuItem } from '../../../src/components/AnchoredMenuList';
import { TitledCard } from '../../../src/components/TitledCard';
import { Card } from '../../../src/components/Card';
import { MediaGallerySection } from '../../../src/components/MediaGallerySection';
import { NotesSection } from '../../../src/components/NotesSection';
import { CollapsibleSectionHeader } from '../../../src/components/CollapsibleSectionHeader';
import { DetailRow } from '../../../src/components/DetailRow';
import { BottomSheet } from '../../../src/components/BottomSheet';
import { AppButton } from '../../../src/components/AppButton';
import { ProjectSelector } from '../../../src/components/ProjectSelector';
import {
  CARD_PADDING,
  getCardStyle,
  getTextColorStyle,
  getTextSecondaryStyle,
  layout,
} from '../../../src/ui';
import { useProjectContextStore } from '../../../src/data/projectContextStore';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../../src/theme/ThemeProvider';
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
import { ITEM_STATUSES, getItemStatusLabel } from '../../../src/constants/itemStatuses';
import { deleteLocalMediaByUrl, resolveAttachmentUri, saveLocalMedia, enqueueUpload } from '../../../src/offline/media';
import type { AttachmentRef, AttachmentKind } from '../../../src/offline/media';
import { useTransactionById } from '../../../src/hooks/useTransactionById';
import { useSpaceById } from '../../../src/hooks/useSpaceById';

type ItemDetailParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
  listStateKey?: string;
};

type ItemSectionKey = 'hero' | 'media' | 'notes' | 'details';

type ItemSection = {
  key: ItemSectionKey;
  title?: string;
  data: any[];
  badge?: string;
};

const SECTION_HEADER_MARKER = '__sectionHeader__';

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
  const [sellToProjectVisible, setSellToProjectVisible] = useState(false);
  const [sellTargetProjectId, setSellTargetProjectId] = useState<string | null>(null);
  const [sellDestCategoryId, setSellDestCategoryId] = useState<string | null>(null);
  const [sellSourceCategoryId, setSellSourceCategoryId] = useState<string | null>(null);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, BudgetCategory>>({});
  const [spaces, setSpaces] = useState<Record<string, Space>>({});
  const [collapsedSections, setCollapsedSections] = useState<Record<string, boolean>>({
    media: false,
    notes: true,
    details: true,
  });
  const [statusMenuVisible, setStatusMenuVisible] = useState(false);

  // Load transaction data for hero card (cache-first for offline-first pattern)
  const transactionData = useTransactionById(accountId, item?.transactionId ?? null, { mode: 'offline' });

  // Load space data for hero card (cache-first for offline-first pattern)
  const spaceData = useSpaceById(accountId, item?.spaceId ?? null, { mode: 'offline' });

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

  const handleSellToInventory = () => {
    if (!accountId || !id || !projectId) return;
    if (!item?.budgetCategoryId) {
      setError(
        "Can’t sell to Business Inventory yet. Link this item to a categorized transaction first."
      );
      return;
    }
    requestProjectToBusinessSale({
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

  const handleStatusChange = (newStatus: string) => {
    if (!accountId || !id) return;
    updateItem(accountId, id, { status: newStatus });
  };

  const statusLabel = getItemStatusLabel(item?.status);
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

  const handleToggleSection = useCallback((key: string) => {
    setCollapsedSections(prev => ({ ...prev, [key]: !prev[key] }));
  }, []);

  const sections: ItemSection[] = useMemo(() => {
    if (isLoading || !item) return [];

    const result: ItemSection[] = [];

    // Hero section — always visible, no header, no collapse
    result.push({
      key: 'hero',
      data: ['hero-content'],
    });

    // Media section (non-sticky, collapsible)
    result.push({
      key: 'media',
      title: 'IMAGES',
      data: collapsedSections.media
        ? [SECTION_HEADER_MARKER]
        : [SECTION_HEADER_MARKER, 'media-content'],
    });

    // Notes section (non-sticky, collapsible)
    result.push({
      key: 'notes',
      title: 'NOTES',
      data: collapsedSections.notes
        ? [SECTION_HEADER_MARKER]
        : [SECTION_HEADER_MARKER, 'notes-content'],
    });

    // Details section (non-sticky, collapsible)
    result.push({
      key: 'details',
      title: 'DETAILS',
      data: collapsedSections.details
        ? [SECTION_HEADER_MARKER]
        : [SECTION_HEADER_MARKER, 'details-content'],
    });

    return result;
  }, [isLoading, item, collapsedSections]);

  const menuItems = useMemo<AnchoredMenuItem[]>(() => {
    const items: AnchoredMenuItem[] = [
      {
        label: 'Edit Details',
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
      actionOnly: true,
      subactions: [
        { key: 'link', label: 'Link Transaction', onPress: handleLinkTransaction, icon: 'link' },
        { key: 'unlink', label: 'Unlink Transaction', onPress: handleUnlinkTransaction, icon: 'link-off' },
      ],
    });

    if (scope === 'inventory') {
      items.push({
        label: 'Sell',
        icon: 'sell',
        actionOnly: true,
        subactions: [
          { key: 'sell-to-project', label: 'Sell to Project', onPress: () => setSellToProjectVisible(true), icon: 'assignment' },
        ],
      });
    } else {
      items.push({
        label: 'Sell',
        icon: 'sell',
        actionOnly: true,
        subactions: [
          { key: 'sell-to-business', label: 'Sell to Business', onPress: handleSellToInventory, icon: 'inventory' },
          { key: 'sell-to-project', label: 'Sell to Project', onPress: () => setSellToProjectVisible(true), icon: 'assignment' },
        ],
      });
      items.push({
        label: 'Move',
        icon: 'swap-horiz',
        actionOnly: true,
        subactions: [
          { key: 'move-to-inventory', label: 'Move to Inventory', onPress: handleMoveToInventoryCorrection, icon: 'inventory' },
        ],
      });
    }

    items.push({
      label: 'Delete Item',
      onPress: handleDelete,
      icon: 'delete',
    });

    return items;
  }, [
    handleDelete,
    handleLinkTransaction,
    handleMoveToInventoryCorrection,
    handleSellToInventory,
    handleUnlinkTransaction,
    id,
    projectId,
    router,
    scope,
  ]);

  const statusMenuItems: AnchoredMenuItem[] = useMemo(() => {
    return [
      ...ITEM_STATUSES.map(s => ({
        key: s.key,
        label: s.label,
        onPress: () => {
          handleStatusChange(s.key);
          setStatusMenuVisible(false);
        },
      })),
      {
        key: 'clear',
        label: 'Clear Status',
        onPress: () => {
          handleStatusChange('');
          setStatusMenuVisible(false);
        },
      },
    ];
  }, [handleStatusChange]);

  const renderItem = useCallback(({ item: dataItem, section }: { item: any; section: ItemSection }) => {
    if (!item) return null;

    // Non-sticky section headers
    if (dataItem === SECTION_HEADER_MARKER) {
      if (!section.title) return null; // hero has no header
      return (
        <CollapsibleSectionHeader
          title={section.title}
          collapsed={collapsedSections[section.key] ?? false}
          onToggle={() => handleToggleSection(section.key)}
          badge={section.badge}
        />
      );
    }

    switch (section.key) {
      case 'hero':
        return (
          <>
            {/* Hero card — name + transaction + space info */}
            <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
              <View style={styles.heroHeader}>
                <AppText variant="h2" style={styles.heroTitle}>
                  {item.name?.trim() || 'Untitled item'}
                </AppText>

                {/* Transaction info (separate row) */}
                <View style={{ flexDirection: 'row', alignItems: 'baseline', flexWrap: 'wrap' }}>
                  <AppText variant="caption">Transaction: </AppText>
                  {item.transactionId ? (
                    transactionData.data ? (
                      <AppText
                        variant="body"
                        style={{ color: theme.colors.primary }}
                        onPress={() => router.push({
                          pathname: '/transactions/[id]',
                          params: {
                            id: item.transactionId!,
                            scope: scope ?? '',
                            projectId: projectId ?? '',
                            backTarget: id ? `/items/${id}` : '',
                          },
                        })}
                      >
                        {transactionData.data.source || 'Untitled'} - {formatMoney(transactionData.data.amountCents)}
                      </AppText>
                    ) : transactionData.loading ? (
                      <AppText variant="body">Loading...</AppText>
                    ) : (
                      <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                        [Deleted]
                      </AppText>
                    )
                  ) : (
                    <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                      None
                    </AppText>
                  )}
                </View>

                {/* Budget category info (separate row) */}
                <View style={{ flexDirection: 'row', alignItems: 'baseline', flexWrap: 'wrap' }}>
                  <AppText variant="caption">Budget Category: </AppText>
                  <AppText variant="body">
                    {item.budgetCategoryId
                      ? budgetCategories[item.budgetCategoryId]?.name?.trim() || item.budgetCategoryId
                      : 'None'}
                  </AppText>
                </View>

                {/* Space info (separate row) */}
                <View style={{ flexDirection: 'row', alignItems: 'baseline', flexWrap: 'wrap' }}>
                  <AppText variant="caption">Space: </AppText>
                  {item.spaceId ? (
                    spaceData.data ? (
                      <AppText variant="body">{spaceData.data.name}</AppText>
                    ) : spaceData.loading ? (
                      <AppText variant="body">Loading...</AppText>
                    ) : (
                      <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                        Unknown space
                      </AppText>
                    )
                  ) : (
                    <AppText variant="body">None</AppText>
                  )}
                </View>
              </View>
            </View>
            {/* Error banner (conditional) */}
            {error ? (
              <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
                <AppText variant="caption" style={[styles.errorText, getTextSecondaryStyle(uiKitTheme)]}>
                  {error}
                </AppText>
              </View>
            ) : null}
          </>
        );

      case 'media':
        return (
          <MediaGallerySection
            title="Images"
            hideTitle={true}
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
        );

      case 'notes':
        return <NotesSection notes={item.notes} expandable={true} />;

      case 'details':
        return (
          <Card>
            <View style={styles.detailRows}>
              <DetailRow label="Source" value={item.source?.trim() || '—'} />
              <DetailRow label="SKU" value={item.sku?.trim() || '—'} />
              <DetailRow label="Purchase price" value={formatMoney(item.purchasePriceCents)} />
              <DetailRow label="Project price" value={formatMoney(item.projectPriceCents)} />
              <DetailRow label="Market value" value={formatMoney(item.marketValueCents)} showDivider={false} />
            </View>
          </Card>
        );

      default:
        return null;
    }
  }, [item, error, collapsedSections, handleToggleSection, uiKitTheme,
      handleAddImage, handleRemoveImage, handleSetPrimaryImage,
      trimmedTransactionId, transactionLabel, handleOpenTransaction,
      spaceLabel, budgetCategoryLabel]);

  // Removed inline move form - now accessed via kebab menu
  const listFooter = null;

  const headerActions = (
    <View style={styles.headerRight}>
      {/* Status badge with chevron */}
      {statusLabel && (
        <Pressable
          onPress={() => setStatusMenuVisible(true)}
          style={[styles.statusPill, { flexDirection: 'row', alignItems: 'center', gap: 2, backgroundColor: `${uiKitTheme.primary.main}1A` }]}
        >
          <AppText variant="caption" style={[styles.statusText, { color: uiKitTheme.primary.main }]}>
            {statusLabel}
          </AppText>
          <MaterialIcons
            name="arrow-drop-down"
            size={16}
            color={uiKitTheme.primary.main}
            style={{ marginLeft: 2 }}
          />
        </Pressable>
      )}

      {/* Bookmark button */}
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
      {isLoading ? (
        <View style={styles.loadingContainer}>
          <AppText variant="body">Loading item…</AppText>
        </View>
      ) : !item ? (
        <View style={styles.loadingContainer}>
          <AppText variant="body">Item not found.</AppText>
        </View>
      ) : (
        <SectionList
          sections={sections}
          renderItem={renderItem}
          renderSectionHeader={() => null}
          stickySectionHeadersEnabled={false}
          keyExtractor={(dataItem, index) =>
            dataItem === SECTION_HEADER_MARKER ? `header-${index}` : `item-${index}`
          }
          contentContainerStyle={styles.content}
          showsVerticalScrollIndicator={false}
          ListFooterComponent={listFooter}
        />
      )}
      <BottomSheetMenuList
        visible={menuVisible}
        onRequestClose={() => setMenuVisible(false)}
        items={menuItems}
        title="Item Actions"
        showLeadingIcons={true}
      />

      {/* Sell to Project modal */}
      <BottomSheet visible={sellToProjectVisible} onRequestClose={() => setSellToProjectVisible(false)}>
        <View style={[styles.moveForm, { paddingHorizontal: 16, paddingBottom: 16, paddingTop: 8, gap: 12 }]}>
          <AppText variant="body" style={{ fontWeight: '700' }}>
            Sell to Project
          </AppText>
          {accountId && (
            <View style={{ gap: 8 }}>
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                Target project
              </AppText>
              <ProjectSelector
                accountId={accountId}
                value={sellTargetProjectId}
                onChange={setSellTargetProjectId}
                excludeProjectId={projectId}
              />
            </View>
          )}
          {sellTargetProjectId && (
            <View style={{ gap: 8 }}>
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                Destination category
              </AppText>
              {Object.entries(budgetCategories).length === 0 ? (
                <AppText variant="caption">Loading categories...</AppText>
              ) : (
                <ScrollView style={{ maxHeight: 200 }}>
                  {Object.entries(budgetCategories)
                    .sort(([, a], [, b]) => a.name.localeCompare(b.name))
                    .map(([catId, cat]) => (
                      <Pressable
                        key={catId}
                        onPress={() => setSellDestCategoryId(catId)}
                        style={{
                          flexDirection: 'row',
                          justifyContent: 'space-between',
                          alignItems: 'center',
                          paddingVertical: 10,
                          paddingHorizontal: 12,
                          borderRadius: 8,
                          backgroundColor: sellDestCategoryId === catId ? uiKitTheme.background.surface : undefined,
                        }}
                      >
                        <AppText variant="body">{cat.name}</AppText>
                        {sellDestCategoryId === catId && (
                          <AppText variant="body" style={{ color: theme.colors.primary }}>✓</AppText>
                        )}
                      </Pressable>
                    ))}
                </ScrollView>
              )}
            </View>
          )}
          {sellTargetProjectId && scope === 'project' && item && !item.budgetCategoryId && (
            <View style={{ gap: 8 }}>
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                Source category (item is uncategorized)
              </AppText>
              {Object.entries(budgetCategories).length === 0 ? (
                <AppText variant="caption">Loading categories...</AppText>
              ) : (
                <ScrollView style={{ maxHeight: 150 }}>
                  {Object.entries(budgetCategories)
                    .sort(([, a], [, b]) => a.name.localeCompare(b.name))
                    .map(([catId, cat]) => (
                      <Pressable
                        key={catId}
                        onPress={() => setSellSourceCategoryId(catId)}
                        style={{
                          flexDirection: 'row',
                          justifyContent: 'space-between',
                          alignItems: 'center',
                          paddingVertical: 10,
                          paddingHorizontal: 12,
                          borderRadius: 8,
                          backgroundColor: sellSourceCategoryId === catId ? uiKitTheme.background.surface : undefined,
                        }}
                      >
                        <AppText variant="body">{cat.name}</AppText>
                        {sellSourceCategoryId === catId && (
                          <AppText variant="body" style={{ color: theme.colors.primary }}>✓</AppText>
                        )}
                      </Pressable>
                    ))}
                </ScrollView>
              )}
            </View>
          )}
          <AppButton
            title="Confirm Sale"
            variant="primary"
            disabled={!sellTargetProjectId || !sellDestCategoryId}
            onPress={() => {
              if (!accountId || !sellTargetProjectId || !sellDestCategoryId || !item) return;
              if (scope === 'project' && projectId) {
                // Flow C: Project → Project
                const sourceCatId = item.budgetCategoryId ?? sellSourceCategoryId;
                if (!sourceCatId) return;
                requestProjectToProjectMove({
                  accountId,
                  sourceProjectId: projectId,
                  targetProjectId: sellTargetProjectId,
                  destinationBudgetCategoryId: sellDestCategoryId,
                  items: [{ ...item, budgetCategoryId: sourceCatId }],
                });
              } else {
                // Flow B: Inventory → Project
                requestBusinessToProjectPurchase({
                  accountId,
                  targetProjectId: sellTargetProjectId,
                  budgetCategoryId: sellDestCategoryId,
                  items: [item],
                });
              }
              setSellToProjectVisible(false);
              setSellTargetProjectId(null);
              setSellDestCategoryId(null);
              setSellSourceCategoryId(null);
            }}
            style={{ minHeight: 44 }}
          />
        </View>
      </BottomSheet>

      {/* Status Change Menu */}
      <BottomSheetMenuList
        visible={statusMenuVisible}
        onRequestClose={() => setStatusMenuVisible(false)}
        items={statusMenuItems}
        title="Change Status"
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
    paddingBottom: 24,
    gap: 4,
  },
  screenContent: {
    paddingTop: 0,
  },
  loadingContainer: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
    paddingHorizontal: 20,
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
