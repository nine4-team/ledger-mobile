import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { AppScrollView } from '../../src/components/AppScrollView';
import { TitledCard } from '../../src/components/TitledCard';
import { BottomSheetMenuList } from '../../src/components/BottomSheetMenuList';
import type { AnchoredMenuItem } from '../../src/components/AnchoredMenuList';
import { SharedItemPicker } from '../../src/components/SharedItemPicker';
import { showItemConflictDialog } from '../../src/components/ItemConflictDialog';
import { ItemCard } from '../../src/components/ItemCard';
import type { ItemCardProps } from '../../src/components/ItemCard';
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
import { createInventoryScopeConfig, createProjectScopeConfig } from '../../src/data/scopeConfig';
import { ScopedItem, subscribeToScopedItems } from '../../src/data/scopedListData';
import { Item, updateItem } from '../../src/data/itemsService';
import { saveLocalMedia, deleteLocalMediaByUrl, enqueueUpload, resolveAttachmentUri } from '../../src/offline/media';
import type { AttachmentRef } from '../../src/offline/media';
import { ThumbnailGrid } from '../../src/components/ThumbnailGrid';
import { ImageGallery } from '../../src/components/ImageGallery';
import { ImagePickerButton } from '../../src/components/ImagePickerButton';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../../src/data/budgetCategoriesService';
import { deleteTransaction, subscribeToTransaction, Transaction, updateTransaction } from '../../src/data/transactionsService';
import { isCanonicalInventorySaleTransaction } from '../../src/data/inventoryOperations';
import { useOutsideItems } from '../../src/hooks/useOutsideItems';
import { resolveItemMove } from '../../src/data/resolveItemMove';

type TransactionDetailParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
  listStateKey?: string;
};

type ItemPickerTab = 'suggested' | 'project' | 'outside';

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

function formatDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  return dateStr;
}

function formatPercent(pct: number | null | undefined): string {
  if (typeof pct !== 'number') return '—';
  return `${pct.toFixed(2)}%`;
}

export default function TransactionDetailScreen() {
  const router = useRouter();
  const { setProjectId } = useProjectContextStore();
  const accountId = useAccountContextStore((store) => store.accountId);
  const params = useLocalSearchParams<TransactionDetailParams>();
  const id = Array.isArray(params.id) ? params.id[0] : params.id;
  const scope = Array.isArray(params.scope) ? params.scope[0] : params.scope;
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const backTarget = Array.isArray(params.backTarget) ? params.backTarget[0] : params.backTarget;
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [transaction, setTransaction] = useState<Transaction | null>(null);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isEditing, setIsEditing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [source, setSource] = useState('');
  const [transactionDate, setTransactionDate] = useState('');
  const [amount, setAmount] = useState('');
  const [status, setStatus] = useState('');
  const [purchasedBy, setPurchasedBy] = useState('');
  const [reimbursementType, setReimbursementType] = useState('');
  const [notes, setNotes] = useState('');
  const [type, setType] = useState('');
  const [budgetCategoryId, setBudgetCategoryId] = useState('');
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string; metadata?: any }>>({});
  const [hasEmailReceipt, setHasEmailReceipt] = useState(false);
  const [taxRatePct, setTaxRatePct] = useState('');
  const [subtotal, setSubtotal] = useState('');
  const [taxAmount, setTaxAmount] = useState('');
  const [isPickingItems, setIsPickingItems] = useState(false);
  const [pickerTab, setPickerTab] = useState<ItemPickerTab>('suggested');
  const [pickerSelectedIds, setPickerSelectedIds] = useState<string[]>([]);
  const [menuVisible, setMenuVisible] = useState(false);
  const [receiptGalleryVisible, setReceiptGalleryVisible] = useState(false);
  const [receiptGalleryIndex, setReceiptGalleryIndex] = useState(0);
  const [otherGalleryVisible, setOtherGalleryVisible] = useState(false);
  const [otherGalleryIndex, setOtherGalleryIndex] = useState(0);

  const outsideItemsHook = useOutsideItems({
    accountId,
    currentProjectId: projectId ?? null,
    scope: scope ?? 'project',
    includeInventory: scope === 'project',
  });

  useEffect(() => {
    if (scope === 'project' && projectId) {
      setProjectId(projectId);
    }
  }, [projectId, scope, setProjectId]);

  useEffect(() => {
    if (!accountId || !id) {
      setTransaction(null);
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    const unsubscribe = subscribeToTransaction(accountId, id, (next) => {
      setTransaction(next);
      setIsLoading(false);
      if (next) {
        setSource(next.source ?? '');
        setTransactionDate(next.transactionDate ?? '');
        setAmount(
          typeof next.amountCents === 'number' ? (next.amountCents / 100).toFixed(2) : ''
        );
        setStatus(next.status ?? '');
        setPurchasedBy(next.purchasedBy ?? '');
        setReimbursementType(next.reimbursementType ?? '');
        setNotes(next.notes ?? '');
        setType(next.type ?? '');
        setBudgetCategoryId(next.budgetCategoryId ?? '');
        setHasEmailReceipt(!!next.hasEmailReceipt);
        setTaxRatePct(
          typeof next.taxRatePct === 'number' ? next.taxRatePct.toFixed(2) : ''
        );
        setSubtotal(
          typeof next.subtotalCents === 'number' ? (next.subtotalCents / 100).toFixed(2) : ''
        );
      }
    });
    return () => unsubscribe();
  }, [accountId, id]);

  useEffect(() => {
    if (!accountId) {
      setBudgetCategories({});
      return;
    }
    return subscribeToBudgetCategories(accountId, (next) => setBudgetCategories(mapBudgetCategories(next)));
  }, [accountId]);


  useEffect(() => {
    if (!accountId || !id || !scope) {
      setItems([]);
      return;
    }
    const scopeConfig =
      scope === 'inventory' ? createInventoryScopeConfig() : projectId ? createProjectScopeConfig(projectId) : null;
    if (!scopeConfig) {
      setItems([]);
      return;
    }
    const unsubscribe = subscribeToScopedItems(accountId, scopeConfig, (next) => {
      setItems(next);
    });
    return () => unsubscribe();
  }, [accountId, id, projectId, scope]);

  const fallbackTarget = useMemo(() => {
    if (backTarget) return backTarget;
    if (scope === 'inventory') return '/(tabs)/screen-two?tab=transactions';
    if (scope === 'project' && projectId) return `/project/${projectId}?tab=transactions`;
    return '/(tabs)/index';
  }, [backTarget, projectId, scope]);

  const handleBack = () => {
    if (router.canGoBack()) {
      router.back();
      return;
    }
    router.replace(fallbackTarget);
  };

  const isCanonical = isCanonicalInventorySaleTransaction(transaction);
  const linkedItems = useMemo(() => items.filter((item) => item.transactionId === id), [id, items]);
  const selectedCategory = budgetCategories[budgetCategoryId];
  const itemizationEnabled = selectedCategory?.metadata?.categoryType === 'itemized';
  const normalizedSource = transaction?.source?.trim().toLowerCase() ?? '';

  const suggestedItems = useMemo(() => {
    if (!normalizedSource) return [];
    return items.filter((item) => {
      const itemSource = item.source?.trim().toLowerCase() ?? '';
      return itemSource === normalizedSource && !item.transactionId;
    });
  }, [items, normalizedSource]);

  const projectItems = useMemo(() => (projectId ? items : []), [items, projectId]);

  const activePickerItems = useMemo(() => {
    if (pickerTab === 'suggested') return suggestedItems;
    if (pickerTab === 'project') return projectItems;
    return outsideItemsHook.items;
  }, [pickerTab, suggestedItems, projectItems, outsideItemsHook.items]);

  const pickerTabOptions = useMemo(() => {
    const options: Array<{ value: ItemPickerTab; label: string; accessibilityLabel?: string }> = [
      { value: 'suggested', label: 'Suggested', accessibilityLabel: 'Suggested items tab' },
    ];
    if (projectId) options.push({ value: 'project', label: 'Project', accessibilityLabel: 'Project items tab' });
    options.push({ value: 'outside', label: 'Outside', accessibilityLabel: 'Outside items tab' });
    return options;
  }, [projectId]);

  const budgetCategoryLabel = useMemo(() => {
    if (!transaction?.budgetCategoryId) return 'None';
    const category = budgetCategories[transaction.budgetCategoryId];
    return category?.name?.trim() || transaction.budgetCategoryId;
  }, [transaction, budgetCategories]);

  const hasReceiptLabel = transaction?.hasEmailReceipt ? 'Yes' : 'No';
  const statusLabel = transaction?.status?.trim() || '';

  useEffect(() => {
    if (!isPickingItems || pickerTab !== 'outside') return;
    void outsideItemsHook.reload();
  }, [isPickingItems, pickerTab, outsideItemsHook]);

  const handleSave = async () => {
    if (!accountId || !id) return;
    if (isCanonical) {
      setError('Canonical transactions cannot be edited.');
      return;
    }
    const amountCents = parseCurrency(amount);
    const hasReceipt = (transaction?.receiptImages?.length ?? 0) > 0;
    const hasSource = !!source.trim();
    const hasAmount = typeof amountCents === 'number' && amountCents > 0;
    if (!hasReceipt && (!hasSource || !hasAmount)) {
      setError('Add a receipt or provide source and amount.');
      return;
    }
    setError(null);
    let subtotalCents: number | null = null;
    let taxRateValue: number | null = null;
    if (itemizationEnabled) {
      const amountValue = typeof amountCents === 'number' ? amountCents : null;
      if (amountValue != null) {
        const parsedSubtotal = parseCurrency(subtotal);
        const parsedTaxAmount = parseCurrency(taxAmount);
        const parsedTaxRate = Number.parseFloat(taxRatePct);
        if (Number.isFinite(parsedTaxRate) && parsedTaxRate > 0) {
          const rate = parsedTaxRate / 100;
          subtotalCents = Math.round(amountValue / (1 + rate));
          taxRateValue = parsedTaxRate;
        } else if (parsedSubtotal != null && parsedSubtotal > 0 && parsedSubtotal <= amountValue) {
          subtotalCents = parsedSubtotal;
          const taxCents = amountValue - parsedSubtotal;
          taxRateValue = taxCents > 0 ? (taxCents / parsedSubtotal) * 100 : 0;
        } else if (parsedTaxAmount != null && parsedTaxAmount >= 0 && parsedTaxAmount < amountValue) {
          subtotalCents = amountValue - parsedTaxAmount;
          taxRateValue = subtotalCents > 0 ? (parsedTaxAmount / subtotalCents) * 100 : 0;
        }
      }
    }
    const nextCategoryId = budgetCategoryId.trim() || null;
    const categoryChanged = nextCategoryId !== (transaction?.budgetCategoryId ?? null);
    await updateTransaction(accountId, id, {
      source: source.trim() || null,
      transactionDate: transactionDate.trim() || null,
      amountCents: amountCents ?? null,
      status: status.trim() || null,
      purchasedBy: purchasedBy.trim() || null,
      reimbursementType: reimbursementType.trim() || null,
      notes: notes.trim() || null,
      type: type.trim() || null,
      budgetCategoryId: nextCategoryId,
      hasEmailReceipt,
      taxRatePct: taxRateValue,
      subtotalCents,
    });
    if (categoryChanged && nextCategoryId) {
      await Promise.all(
        linkedItems.map((item) => updateItem(accountId, item.id, { budgetCategoryId: nextCategoryId }))
      );
    }
    setIsEditing(false);
  };

  const handlePickReceiptImage = async (localUri: string) => {
    if (!accountId || !id || !transaction) return;

    const result = await saveLocalMedia({
      localUri,
      mimeType: 'image/jpeg',
      ownerScope: `transaction:${id}`,
      persistCopy: true,
    });

    const currentImages = transaction.receiptImages ?? [];
    const hasPrimary = currentImages.some((img) => img.isPrimary);

    const newImage: AttachmentRef = {
      url: result.attachmentRef.url,
      kind: 'image',
      isPrimary: !hasPrimary,
    };

    const nextImages = [...currentImages, newImage].slice(0, 5);
    await updateTransaction(accountId, id, { receiptImages: nextImages, transactionImages: nextImages });

    // Enqueue upload in background
    await enqueueUpload({ mediaId: result.mediaId });
  };

  const handleRemoveReceiptImage = async (url: string) => {
    if (!accountId || !id || !transaction) return;

    const currentImages = transaction.receiptImages ?? [];
    const nextImages = currentImages.filter((img) => img.url !== url);

    // Delete offline image if applicable
    if (url.startsWith('offline://')) {
      await deleteLocalMediaByUrl(url);
    }

    // Ensure at least one primary
    if (!nextImages.some((img) => img.isPrimary) && nextImages.length > 0) {
      nextImages[0] = { ...nextImages[0], isPrimary: true };
    }

    await updateTransaction(accountId, id, { receiptImages: nextImages, transactionImages: nextImages });
  };

  const handleSetPrimaryReceiptImage = async (url: string) => {
    if (!accountId || !id || !transaction) return;

    const nextImages = (transaction.receiptImages ?? []).map((img) => ({
      ...img,
      isPrimary: img.url === url,
    }));

    await updateTransaction(accountId, id, { receiptImages: nextImages, transactionImages: nextImages });
  };

  const handlePickOtherImage = async (localUri: string) => {
    if (!accountId || !id || !transaction) return;

    const result = await saveLocalMedia({
      localUri,
      mimeType: 'image/jpeg',
      ownerScope: `transaction:${id}`,
      persistCopy: true,
    });

    const currentImages = transaction.otherImages ?? [];
    const hasPrimary = currentImages.some((img) => img.isPrimary);

    const newImage: AttachmentRef = {
      url: result.attachmentRef.url,
      kind: 'image',
      isPrimary: !hasPrimary,
    };

    const nextImages = [...currentImages, newImage].slice(0, 5);
    await updateTransaction(accountId, id, { otherImages: nextImages });

    // Enqueue upload in background
    await enqueueUpload({ mediaId: result.mediaId });
  };

  const handleRemoveOtherImage = async (url: string) => {
    if (!accountId || !id || !transaction) return;

    const currentImages = transaction.otherImages ?? [];
    const nextImages = currentImages.filter((img) => img.url !== url);

    // Delete offline image if applicable
    if (url.startsWith('offline://')) {
      await deleteLocalMediaByUrl(url);
    }

    // Ensure at least one primary
    if (!nextImages.some((img) => img.isPrimary) && nextImages.length > 0) {
      nextImages[0] = { ...nextImages[0], isPrimary: true };
    }

    await updateTransaction(accountId, id, { otherImages: nextImages });
  };

  const handleSetPrimaryOtherImage = async (url: string) => {
    if (!accountId || !id || !transaction) return;

    const nextImages = (transaction.otherImages ?? []).map((img) => ({
      ...img,
      isPrimary: img.url === url,
    }));

    await updateTransaction(accountId, id, { otherImages: nextImages });
  };

  const handleAddSelectedItems = useCallback(async () => {
    if (!accountId || !id || pickerSelectedIds.length === 0) return;
    const selectedItems = activePickerItems.filter((item) => pickerSelectedIds.includes(item.id));
    const conflicts = selectedItems.filter((item) => item.transactionId && item.transactionId !== id);
    
    const performAdd = async () => {
      await Promise.all(
        selectedItems.map(async (item) => {
          const targetProjectId = scope === 'inventory' ? null : projectId ?? null;
          const budgetCategoryId =
            scope === 'inventory'
              ? item.budgetCategoryId ?? null
              : !isCanonical && transaction?.budgetCategoryId
                ? transaction.budgetCategoryId
                : undefined;

          const result = await resolveItemMove(item, {
            accountId,
            itemId: item.id,
            targetProjectId,
            targetSpaceId: null,
            targetTransactionId: id,
            budgetCategoryId,
          });

          if (!result.success) {
            console.error(`Failed to move item ${item.id}: ${result.error}`);
          }
        })
      );
      setPickerSelectedIds([]);
      setIsPickingItems(false);
    };

    if (conflicts.length > 0) {
      const conflictNames = conflicts.map((item) => item.name?.trim() || 'Item');
      showItemConflictDialog({
        conflictItemNames: conflictNames,
        onConfirm: performAdd,
      });
      return;
    }
    await performAdd();
  }, [
    accountId,
    activePickerItems,
    id,
    isCanonical,
    pickerSelectedIds,
    projectId,
    scope,
    transaction?.budgetCategoryId,
  ]);

  const handleRemoveLinkedItem = async (itemId: string) => {
    if (!accountId) return;
    await updateItem(accountId, itemId, { transactionId: null });
  };

  const handleCreateItem = () => {
    router.push({
      pathname: '/items/new',
      params: {
        scope,
        projectId: projectId ?? '',
        transactionId: id ?? '',
        backTarget: fallbackTarget,
      },
    });
  };

  const handleDelete = () => {
    if (!accountId || !id) return;
    Alert.alert('Delete transaction', 'This will permanently delete this transaction.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          await deleteTransaction(accountId, id);
          router.replace(fallbackTarget);
        },
      },
    ]);
  };

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

    items.push({
      label: 'Delete transaction',
      onPress: handleDelete,
      icon: 'delete',
    });

    return items;
  }, [isEditing]);

  const headerActions = statusLabel ? (
    <View style={styles.headerRight}>
      <View style={[styles.statusPill, { backgroundColor: `${uiKitTheme.primary.main}1A` }]}>
        <AppText variant="caption" style={[styles.statusText, { color: uiKitTheme.primary.main }]}>
          {statusLabel}
        </AppText>
      </View>
    </View>
  ) : undefined;

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
          <AppText variant="body">Loading transaction…</AppText>
        ) : transaction ? (
          <>
            {/* Hero Header Card */}
            <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
              <View style={styles.heroHeader}>
                <AppText variant="h2" style={styles.heroTitle}>
                  {transaction.source?.trim() || 'Untitled transaction'}
                </AppText>
                <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                  {formatMoney(transaction.amountCents)}
                </AppText>
              </View>
            </View>

            {/* Error Card */}
            {error ? (
              <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
                <AppText variant="caption" style={[styles.errorText, getTextSecondaryStyle(uiKitTheme)]}>
                  {error}
                </AppText>
              </View>
            ) : null}

            {/* Receipt Images Section */}
            {(transaction.receiptImages && transaction.receiptImages.length > 0) || isEditing ? (
              <TitledCard title="Receipt Images">
                {transaction.receiptImages && transaction.receiptImages.length > 0 ? (
                  <>
                    <ThumbnailGrid
                      images={transaction.receiptImages}
                      maxImages={5}
                      size="md"
                      tileScale={1.5}
                      onImagePress={(image, index) => {
                        setReceiptGalleryIndex(index);
                        setReceiptGalleryVisible(true);
                      }}
                      onSetPrimary={(image) => handleSetPrimaryReceiptImage(image.url)}
                      onDelete={(image) => handleRemoveReceiptImage(image.url)}
                    />
                    {isEditing && transaction.receiptImages.length < 5 && (
                      <ImagePickerButton
                        onImagePicked={handlePickReceiptImage}
                        maxImages={5}
                        currentImageCount={transaction.receiptImages.length}
                        style={styles.imagePicker}
                      />
                    )}
                  </>
                ) : (
                  <View style={styles.emptyState}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      No receipt images yet.
                    </AppText>
                    {isEditing && (
                      <ImagePickerButton
                        onImagePicked={handlePickReceiptImage}
                        maxImages={5}
                        currentImageCount={0}
                        style={styles.imagePicker}
                      />
                    )}
                  </View>
                )}
              </TitledCard>
            ) : null}

            {/* Other Images Section */}
            {(transaction.otherImages && transaction.otherImages.length > 0) || isEditing ? (
              <TitledCard title="Other Images">
                {transaction.otherImages && transaction.otherImages.length > 0 ? (
                  <>
                    <ThumbnailGrid
                      images={transaction.otherImages}
                      maxImages={5}
                      size="md"
                      tileScale={1.5}
                      onImagePress={(image, index) => {
                        setOtherGalleryIndex(index);
                        setOtherGalleryVisible(true);
                      }}
                      onSetPrimary={(image) => handleSetPrimaryOtherImage(image.url)}
                      onDelete={(image) => handleRemoveOtherImage(image.url)}
                    />
                    {isEditing && transaction.otherImages.length < 5 && (
                      <ImagePickerButton
                        onImagePicked={handlePickOtherImage}
                        maxImages={5}
                        currentImageCount={transaction.otherImages.length}
                        style={styles.imagePicker}
                      />
                    )}
                  </>
                ) : (
                  <View style={styles.emptyState}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      No other images yet.
                    </AppText>
                    {isEditing && (
                      <ImagePickerButton
                        onImagePicked={handlePickOtherImage}
                        maxImages={5}
                        currentImageCount={0}
                        style={styles.imagePicker}
                      />
                    )}
                  </View>
                )}
              </TitledCard>
            ) : null}

            {/* Transaction Details Section */}
            <TitledCard title="Details">
              {isEditing ? (
                <View style={styles.form}>
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
                      Date
                    </AppText>
                    <TextInput
                      value={transactionDate}
                      onChangeText={setTransactionDate}
                      placeholder="YYYY-MM-DD"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                    />
                  </View>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Amount
                    </AppText>
                    <TextInput
                      value={amount}
                      onChangeText={setAmount}
                      placeholder="$0.00"
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
                      Purchased by
                    </AppText>
                    <TextInput
                      value={purchasedBy}
                      onChangeText={setPurchasedBy}
                      placeholder="Purchased by"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                    />
                  </View>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Reimbursement type
                    </AppText>
                    <TextInput
                      value={reimbursementType}
                      onChangeText={setReimbursementType}
                      placeholder="Reimbursement type"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                    />
                  </View>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Notes
                    </AppText>
                    <TextInput
                      value={notes}
                      onChangeText={setNotes}
                      placeholder="Notes"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                      multiline
                    />
                  </View>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Budget category id
                    </AppText>
                    <TextInput
                      value={budgetCategoryId}
                      onChangeText={setBudgetCategoryId}
                      placeholder="Budget category id"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                    />
                  </View>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Transaction type
                    </AppText>
                    <TextInput
                      value={type}
                      onChangeText={setType}
                      placeholder="Transaction type"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                    />
                  </View>
                  <View style={styles.formGroup}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Email receipt
                    </AppText>
                    <AppButton
                      title={hasEmailReceipt ? 'Email receipt: yes' : 'Email receipt: no'}
                      variant="secondary"
                      onPress={() => setHasEmailReceipt((prev) => !prev)}
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
                      {transaction.source?.trim() || '—'}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Date
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {formatDate(transaction.transactionDate)}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Amount
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {formatMoney(transaction.amountCents)}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Status
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {transaction.status?.trim() || '—'}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Purchased by
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {transaction.purchasedBy?.trim() || '—'}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Reimbursement type
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {transaction.reimbursementType?.trim() || '—'}
                    </AppText>
                  </View>
                  <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                  <View style={styles.detailRow}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Notes
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {transaction.notes?.trim() || '—'}
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
                      Email receipt
                    </AppText>
                    <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                      {hasReceiptLabel}
                    </AppText>
                  </View>
                </View>
              )}
            </TitledCard>

            {/* Tax & Itemization Section */}
            {itemizationEnabled ? (
              <TitledCard title="Tax & Itemization">
                {isEditing ? (
                  <View style={styles.form}>
                    <View style={styles.formGroup}>
                      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                        Tax rate (%)
                      </AppText>
                      <TextInput
                        value={taxRatePct}
                        onChangeText={setTaxRatePct}
                        placeholder="0"
                        placeholderTextColor={theme.colors.textSecondary}
                        style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                        keyboardType="numeric"
                      />
                    </View>
                    <View style={styles.formGroup}>
                      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                        Subtotal
                      </AppText>
                      <TextInput
                        value={subtotal}
                        onChangeText={setSubtotal}
                        placeholder="$0.00"
                        placeholderTextColor={theme.colors.textSecondary}
                        style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                      />
                    </View>
                    <View style={styles.formGroup}>
                      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                        Tax amount
                      </AppText>
                      <TextInput
                        value={taxAmount}
                        onChangeText={setTaxAmount}
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
                        Subtotal
                      </AppText>
                      <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                        {formatMoney(transaction.subtotalCents)}
                      </AppText>
                    </View>
                    <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                    <View style={styles.detailRow}>
                      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                        Tax rate
                      </AppText>
                      <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                        {formatPercent(transaction.taxRatePct)}
                      </AppText>
                    </View>
                    <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
                    <View style={styles.detailRow}>
                      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                        Tax amount
                      </AppText>
                      <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
                        {typeof transaction.amountCents === 'number' && typeof transaction.subtotalCents === 'number'
                          ? formatMoney(transaction.amountCents - transaction.subtotalCents)
                          : '—'}
                      </AppText>
                    </View>
                  </View>
                )}
              </TitledCard>
            ) : null}

            {/* Transaction Items Section */}
            <TitledCard title="Transaction Items">
              {itemizationEnabled && (
                <View style={styles.infoRow}>
                  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                    Itemization enabled
                  </AppText>
                </View>
              )}
              {!itemizationEnabled && linkedItems.length > 0 ? (
                <AppText variant="caption" style={[styles.warningText, getTextSecondaryStyle(uiKitTheme)]}>
                  Itemization is off, but this transaction already has items.
                </AppText>
              ) : null}

              <View style={styles.actions}>
                <AppButton title="Create item" variant="secondary" onPress={handleCreateItem} disabled={isCanonical} />
                <AppButton
                  title={isPickingItems ? 'Close picker' : 'Add existing items'}
                  variant="secondary"
                  onPress={() => {
                    setIsPickingItems((prev) => !prev);
                    setPickerSelectedIds([]);
                    setPickerTab('suggested');
                  }}
                  disabled={isCanonical}
                />
              </View>

              {isPickingItems ? (
                <SharedItemPicker
                  tabs={pickerTabOptions}
                  selectedTab={pickerTab}
                  onTabChange={(next) => {
                    setPickerTab(next);
                    setPickerSelectedIds([]);
                  }}
                  items={activePickerItems}
                  selectedIds={pickerSelectedIds}
                  onSelectionChange={setPickerSelectedIds}
                  eligibilityCheck={{
                    isEligible: (item) => item.transactionId !== id,
                    getStatusLabel: (item) => {
                      if (item.transactionId === id) return 'Already linked';
                      if (item.transactionId) return 'Linked elsewhere';
                      return undefined;
                    },
                  }}
                  onAddSelected={handleAddSelectedItems}
                  outsideLoading={pickerTab === 'outside' ? outsideItemsHook.loading : false}
                  outsideError={pickerTab === 'outside' ? outsideItemsHook.error : null}
                />
              ) : null}

              {linkedItems.length > 0 ? (
                <View style={styles.list}>
                  {linkedItems.map((item) => {
                    const primaryImage = item.images?.find((img) => img.isPrimary) ?? item.images?.[0];
                    const thumbnailUri = primaryImage ? resolveAttachmentUri(primaryImage) ?? primaryImage.url : undefined;
                    const priceLabel = typeof item.purchasePriceCents === 'number'
                      ? `$${(item.purchasePriceCents / 100).toFixed(2)}`
                      : undefined;

                    return (
                      <ItemCard
                        key={item.id}
                        name={item.name?.trim() || 'Untitled item'}
                        sku={item.sku}
                        priceLabel={priceLabel}
                        thumbnailUri={thumbnailUri}
                        bookmarked={item.bookmarked}
                        onPress={() => router.push(`/items/${item.id}`)}
                        menuItems={[
                          {
                            label: 'View item',
                            onPress: () => router.push(`/items/${item.id}`),
                            icon: 'open-in-new',
                          },
                          {
                            label: 'Remove from transaction',
                            onPress: () => handleRemoveLinkedItem(item.id),
                            icon: 'remove-circle-outline',
                          },
                        ]}
                      />
                    );
                  })}
                </View>
              ) : (
                <View style={styles.emptyState}>
                  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                    No items linked yet.
                  </AppText>
                </View>
              )}
            </TitledCard>

            {/* Transaction Audit Section - Placeholder */}
            <TitledCard title="Transaction Audit">
              <View style={styles.auditPlaceholder}>
                <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                  Transaction audit section coming soon.
                </AppText>
                <AppText variant="caption" style={[styles.auditDescription, getTextSecondaryStyle(uiKitTheme)]}>
                  This will show:
                </AppText>
                <View style={styles.auditFeaturesList}>
                  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                    • Items total vs transaction subtotal
                  </AppText>
                  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                    • Completeness indicators
                  </AppText>
                  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                    • Missing price warnings
                  </AppText>
                  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                    • Tax variance calculations
                  </AppText>
                </View>
              </View>
            </TitledCard>
            {/* TODO: Full implementation required
             * See: docs/specs/transaction_audit_spec.md
             * Reference: /Users/benjaminmackenzie/Dev/ledger/src/components/ui/TransactionAudit.tsx
             */}

            {/* Bottom Sheet Menu */}
            <BottomSheetMenuList
              visible={menuVisible}
              onRequestClose={() => setMenuVisible(false)}
              items={menuItems}
              title="Transaction actions"
              showLeadingIcons={true}
            />
          </>
        ) : (
          <AppText variant="body">Transaction not found.</AppText>
        )}
      </AppScrollView>

      {/* Image Galleries */}
      {transaction && transaction.receiptImages && transaction.receiptImages.length > 0 && (
        <ImageGallery
          images={transaction.receiptImages}
          initialIndex={receiptGalleryIndex}
          visible={receiptGalleryVisible}
          onRequestClose={() => setReceiptGalleryVisible(false)}
        />
      )}

      {transaction && transaction.otherImages && transaction.otherImages.length > 0 && (
        <ImageGallery
          images={transaction.otherImages}
          initialIndex={otherGalleryIndex}
          visible={otherGalleryVisible}
          onRequestClose={() => setOtherGalleryVisible(false)}
        />
      )}
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
    lineHeight: 26,
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
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  statusPill: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 999,
  },
  statusText: {
    fontWeight: '600',
    textTransform: 'capitalize',
  },
  errorText: {
    lineHeight: 18,
  },
  emptyState: {
    alignItems: 'center',
    gap: 12,
    paddingVertical: 16,
  },
  imagePicker: {
    marginTop: 12,
  },
  auditPlaceholder: {
    gap: 12,
    paddingVertical: 8,
  },
  auditDescription: {
    marginTop: 4,
  },
  auditFeaturesList: {
    gap: 6,
    marginTop: 8,
    paddingLeft: 8,
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
  list: {
    gap: 8,
  },
  itemRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingVertical: 8,
  },
  infoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 12,
  },
  warningText: {
    marginBottom: 12,
  },
});
