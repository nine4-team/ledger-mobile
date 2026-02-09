import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, StyleSheet, TextInput, TouchableOpacity, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { AppButton } from '../../../src/components/AppButton';
import { AppScrollView } from '../../../src/components/AppScrollView';
import { TitledCard } from '../../../src/components/TitledCard';
import { BottomSheet } from '../../../src/components/BottomSheet';
import { BottomSheetMenuList } from '../../../src/components/BottomSheetMenuList';
import { NotesSection } from '../../../src/components/NotesSection';
import type { AnchoredMenuItem } from '../../../src/components/AnchoredMenuList';
import { SharedItemPicker } from '../../../src/components/SharedItemPicker';
import { showItemConflictDialog } from '../../../src/components/ItemConflictDialog';
import { ItemCard } from '../../../src/components/ItemCard';
import { ItemsListControlBar } from '../../../src/components/ItemsListControlBar';
import { SelectorCircle } from '../../../src/components/SelectorCircle';
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
import { useUIKitTheme } from '../../../src/theme/ThemeProvider';
import { createInventoryScopeConfig, createProjectScopeConfig } from '../../../src/data/scopeConfig';
import { ScopedItem, subscribeToScopedItems } from '../../../src/data/scopedListData';
import { updateItem, deleteItem, createItem } from '../../../src/data/itemsService';
import { saveLocalMedia, deleteLocalMediaByUrl, enqueueUpload, resolveAttachmentUri } from '../../../src/offline/media';
import type { AttachmentRef, AttachmentKind } from '../../../src/offline/media';
import { MediaGallerySection } from '../../../src/components/MediaGallerySection';
import { SpaceSelector } from '../../../src/components/SpaceSelector';
import { getTextInputStyle } from '../../../src/ui/styles/forms';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../../../src/data/budgetCategoriesService';
import { deleteTransaction, subscribeToTransaction, Transaction, updateTransaction } from '../../../src/data/transactionsService';
import { isCanonicalInventorySaleTransaction } from '../../../src/data/inventoryOperations';
import { useOutsideItems } from '../../../src/hooks/useOutsideItems';
import { resolveItemMove } from '../../../src/data/resolveItemMove';

type TransactionDetailParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
  listStateKey?: string;
};

type ItemPickerTab = 'suggested' | 'project' | 'outside';

type TransactionItemSortMode =
  | 'alphabetical-asc'
  | 'alphabetical-desc'
  | 'price-desc'
  | 'price-asc'
  | 'created-desc'
  | 'created-asc';

type TransactionItemFilterMode =
  | 'all'
  | 'bookmarked'
  | 'no-sku'
  | 'no-name'
  | 'no-price'
  | 'no-image';

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
  const uiKitTheme = useUIKitTheme();
  const [transaction, setTransaction] = useState<Transaction | null>(null);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string; metadata?: any }>>({});
  const [isPickingItems, setIsPickingItems] = useState(false);
  const [pickerTab, setPickerTab] = useState<ItemPickerTab>('suggested');
  const [pickerSelectedIds, setPickerSelectedIds] = useState<string[]>([]);
  const [menuVisible, setMenuVisible] = useState(false);
  const [addMenuVisible, setAddMenuVisible] = useState(false);

  // Sort/filter/search state
  const [sortMode, setSortMode] = useState<TransactionItemSortMode>('created-desc');
  const [sortMenuVisible, setSortMenuVisible] = useState(false);
  const [filterMode, setFilterMode] = useState<TransactionItemFilterMode>('all');
  const [filterMenuVisible, setFilterMenuVisible] = useState(false);
  const [showSearch, setShowSearch] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  // Bulk selection state
  const [selectedItemIds, setSelectedItemIds] = useState<Set<string>>(new Set());
  const [bulkMenuVisible, setBulkMenuVisible] = useState(false);

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

  const isCanonical = isCanonicalInventorySaleTransaction(transaction);
  const linkedItems = useMemo(() => items.filter((item) => item.transactionId === id), [id, items]);

  // Filtered and sorted transaction items
  const filteredAndSortedItems = useMemo(() => {
    let result = linkedItems;

    // Apply filter
    result = result.filter((item) => {
      if (filterMode === 'bookmarked') return Boolean(item.bookmark);
      if (filterMode === 'no-sku') return !item.sku?.trim();
      if (filterMode === 'no-name') return !item.name?.trim();
      if (filterMode === 'no-price') return !item.purchasePriceCents || item.purchasePriceCents === 0;
      if (filterMode === 'no-image') return !item.images || item.images.length === 0;
      return true; // 'all'
    });

    // Apply search
    const needle = searchQuery.trim().toLowerCase();
    if (needle) {
      result = result.filter((item) => {
        const haystack = [
          item.name ?? '',
          item.sku ?? '',
          item.source ?? '',
          item.notes ?? '',
        ].join(' ').toLowerCase();
        return haystack.includes(needle);
      });
    }

    // Apply sort
    return [...result].sort((a, b) => {
      if (sortMode === 'alphabetical-asc') return (a.name ?? '').localeCompare(b.name ?? '');
      if (sortMode === 'alphabetical-desc') return (b.name ?? '').localeCompare(a.name ?? '');
      if (sortMode === 'price-desc') return (b.purchasePriceCents ?? 0) - (a.purchasePriceCents ?? 0);
      if (sortMode === 'price-asc') return (a.purchasePriceCents ?? 0) - (b.purchasePriceCents ?? 0);
      if (sortMode === 'created-asc') return String(a.createdAt ?? '').localeCompare(String(b.createdAt ?? ''));
      return String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? '')); // 'created-desc'
    });
  }, [linkedItems, searchQuery, sortMode, filterMode]);

  const selectedCategory = transaction?.budgetCategoryId ? budgetCategories[transaction.budgetCategoryId] : undefined;
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
    if (!isPickingItems) return;
    void outsideItemsHook.reload();
  }, [isPickingItems, outsideItemsHook]);

  const handlePickReceiptAttachment = async (localUri: string, kind: AttachmentKind) => {
    if (!accountId || !id || !transaction) return;

    const mimeType = kind === 'pdf' ? 'application/pdf' : 'image/jpeg';
    const result = await saveLocalMedia({
      localUri,
      mimeType,
      ownerScope: `transaction:${id}`,
      persistCopy: true,
    });

    const currentAttachments = transaction.receiptImages ?? [];
    const hasPrimary = currentAttachments.some((att) => att.isPrimary);

    const newAttachment: AttachmentRef = {
      url: result.attachmentRef.url,
      kind,
      isPrimary: !hasPrimary && kind === 'image',
    };

    const nextAttachments = [...currentAttachments, newAttachment].slice(0, 10);
    updateTransaction(accountId, id, { receiptImages: nextAttachments, transactionImages: nextAttachments });

    // Enqueue upload in background
    await enqueueUpload({ mediaId: result.mediaId });
  };

  const handleRemoveReceiptAttachment = async (attachment: AttachmentRef) => {
    if (!accountId || !id || !transaction) return;

    const currentAttachments = transaction.receiptImages ?? [];
    const nextAttachments = currentAttachments.filter((att) => att.url !== attachment.url);

    // Delete offline attachment if applicable
    if (attachment.url.startsWith('offline://')) {
      await deleteLocalMediaByUrl(attachment.url);
    }

    // Ensure at least one primary
    if (!nextAttachments.some((att) => att.isPrimary) && nextAttachments.length > 0) {
      nextAttachments[0] = { ...nextAttachments[0], isPrimary: true };
    }

    updateTransaction(accountId, id, { receiptImages: nextAttachments, transactionImages: nextAttachments });
  };

  const handleSetPrimaryReceiptAttachment = (attachment: AttachmentRef) => {
    if (!accountId || !id || !transaction) return;

    const nextAttachments = (transaction.receiptImages ?? []).map((att) => ({
      ...att,
      isPrimary: att.url === attachment.url,
    }));

    updateTransaction(accountId, id, { receiptImages: nextAttachments, transactionImages: nextAttachments });
  };

  const handlePickOtherImage = async (localUri: string, kind: AttachmentKind) => {
    if (!accountId || !id || !transaction) return;

    const mimeType = kind === 'pdf' ? 'application/pdf' : 'image/jpeg';
    const result = await saveLocalMedia({
      localUri,
      mimeType,
      ownerScope: `transaction:${id}`,
      persistCopy: true,
    });

    const currentImages = transaction.otherImages ?? [];
    const hasPrimary = currentImages.some((img) => img.isPrimary);

    const newImage: AttachmentRef = {
      url: result.attachmentRef.url,
      kind,
      isPrimary: !hasPrimary && kind === 'image',
    };

    const nextImages = [...currentImages, newImage].slice(0, 5);
    updateTransaction(accountId, id, { otherImages: nextImages });

    // Enqueue upload in background
    await enqueueUpload({ mediaId: result.mediaId });
  };

  const handleRemoveOtherImage = async (attachment: AttachmentRef) => {
    if (!accountId || !id || !transaction) return;

    const currentImages = transaction.otherImages ?? [];
    const nextImages = currentImages.filter((img) => img.url !== attachment.url);

    // Delete offline image if applicable
    if (attachment.url.startsWith('offline://')) {
      await deleteLocalMediaByUrl(attachment.url);
    }

    // Ensure at least one primary
    if (!nextImages.some((img) => img.isPrimary) && nextImages.length > 0) {
      nextImages[0] = { ...nextImages[0], isPrimary: true };
    }

    updateTransaction(accountId, id, { otherImages: nextImages });
  };

  const handleSetPrimaryOtherImage = (attachment: AttachmentRef) => {
    if (!accountId || !id || !transaction) return;

    const nextImages = (transaction.otherImages ?? []).map((img) => ({
      ...img,
      isPrimary: img.url === attachment.url,
    }));

    updateTransaction(accountId, id, { otherImages: nextImages });
  };

  const handleAddSelectedItems = useCallback(() => {
    if (!accountId || !id || pickerSelectedIds.length === 0) return;
    const selectedItems = activePickerItems.filter((item) => pickerSelectedIds.includes(item.id));
    const conflicts = selectedItems.filter((item) => item.transactionId && item.transactionId !== id);

    const performAdd = () => {
      selectedItems.forEach((item) => {
        const targetProjectId = scope === 'inventory' ? null : projectId ?? null;
        const budgetCategoryId =
          scope === 'inventory'
            ? item.budgetCategoryId ?? null
            : !isCanonical && transaction?.budgetCategoryId
              ? transaction.budgetCategoryId
              : undefined;

        const result = resolveItemMove(item, {
          accountId,
          itemId: item.id,
          targetProjectId,
          targetSpaceId: null,
          targetTransactionId: id,
          budgetCategoryId,
        });

        if (!result.success) {
          console.warn(`[items] move failed for ${item.id}: ${result.error}`);
        }
      });
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
    performAdd();
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

  const handleRemoveLinkedItem = (itemId: string) => {
    if (!accountId) return;
    updateItem(accountId, itemId, { transactionId: null });
  };

  // Bulk selection handlers
  const handleItemSelectionChange = (itemId: string, selected: boolean) => {
    setSelectedItemIds(prev => {
      const next = new Set(prev);
      if (selected) next.add(itemId);
      else next.delete(itemId);
      return next;
    });
  };

  const handleSelectAll = () => {
    if (selectedItemIds.size === filteredAndSortedItems.length) {
      // Deselect all
      setSelectedItemIds(new Set());
    } else {
      // Select all filtered items
      setSelectedItemIds(new Set(filteredAndSortedItems.map(item => item.id)));
    }
  };

  // Bulk operation state
  const [bulkSpacePickerVisible, setBulkSpacePickerVisible] = useState(false);
  const [bulkStatusPickerVisible, setBulkStatusPickerVisible] = useState(false);
  const [bulkSKUInputVisible, setBulkSKUInputVisible] = useState(false);
  const [bulkSKUValue, setBulkSKUValue] = useState('');

  // Bulk operation handlers
  const handleBulkSetSpace = () => {
    setBulkMenuVisible(false);
    // Delay to allow menu to close
    setTimeout(() => setBulkSpacePickerVisible(true), 300);
  };

  const handleBulkSetStatus = () => {
    setBulkMenuVisible(false);
    // Delay to allow menu to close
    setTimeout(() => setBulkStatusPickerVisible(true), 300);
  };

  const handleBulkSetSKU = () => {
    setBulkMenuVisible(false);
    setBulkSKUValue('');
    // Delay to allow menu to close
    setTimeout(() => setBulkSKUInputVisible(true), 300);
  };

  const handleBulkRemove = () => {
    if (!accountId || selectedItemIds.size === 0) return;

    setBulkMenuVisible(false);

    Alert.alert(
      'Remove from transaction',
      `Remove ${selectedItemIds.size} item${selectedItemIds.size === 1 ? '' : 's'} from this transaction?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Remove',
          style: 'destructive',
          onPress: () => {
            selectedItemIds.forEach((itemId) => {
              updateItem(accountId, itemId, { transactionId: null });
            });
            setSelectedItemIds(new Set());
          },
        },
      ]
    );
  };

  const handleBulkDelete = () => {
    if (!accountId || selectedItemIds.size === 0) return;

    setBulkMenuVisible(false);

    Alert.alert(
      'Delete items',
      `Permanently delete ${selectedItemIds.size} item${selectedItemIds.size === 1 ? '' : 's'}? This cannot be undone.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            selectedItemIds.forEach((itemId) => {
              deleteItem(accountId, itemId);
            });
            setSelectedItemIds(new Set());
          },
        },
      ]
    );
  };

  const handleBulkSpaceConfirm = (spaceId: string | null) => {
    if (!accountId || selectedItemIds.size === 0) return;

    selectedItemIds.forEach((itemId) => {
      updateItem(accountId, itemId, { spaceId });
    });

    setBulkSpacePickerVisible(false);
    setSelectedItemIds(new Set());
  };

  const handleBulkStatusConfirm = (status: string) => {
    if (!accountId || selectedItemIds.size === 0) return;

    selectedItemIds.forEach((itemId) => {
      updateItem(accountId, itemId, { status });
    });

    setBulkStatusPickerVisible(false);
    setSelectedItemIds(new Set());
  };

  const handleBulkSKUConfirm = () => {
    if (!accountId || selectedItemIds.size === 0) return;

    const sku = bulkSKUValue.trim();
    selectedItemIds.forEach((itemId) => {
      updateItem(accountId, itemId, { sku });
    });

    setBulkSKUInputVisible(false);
    setBulkSKUValue('');
    setSelectedItemIds(new Set());
  };

  // Single item operation state
  const [singleItemSpacePickerVisible, setSingleItemSpacePickerVisible] = useState(false);
  const [singleItemOperationId, setSingleItemOperationId] = useState<string | null>(null);

  // Enhanced item menu handlers (Phase C & D)
  const handleDuplicateItem = (itemId: string) => {
    if (!accountId) return;

    const item = filteredAndSortedItems.find((i) => i.id === itemId);
    if (!item) return;

    Alert.alert(
      'Make copies',
      'How many copies would you like to create?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: '1 copy',
          onPress: () => {
            createItem(accountId, {
              name: item.name ?? '',
              notes: item.notes,
              status: item.status,
              source: item.source,
              sku: item.sku,
              transactionId: item.transactionId,
              purchasePriceCents: item.purchasePriceCents,
              projectPriceCents: item.projectPriceCents,
              marketValueCents: item.marketValueCents,
              purchasedBy: item.purchasedBy,
              budgetCategoryId: item.budgetCategoryId,
              projectId: item.projectId,
              spaceId: item.spaceId,
            });
          },
        },
        {
          text: '3 copies',
          onPress: () => {
            const newItem = {
              name: item.name ?? '',
              notes: item.notes,
              status: item.status,
              source: item.source,
              sku: item.sku,
              transactionId: item.transactionId,
              purchasePriceCents: item.purchasePriceCents,
              projectPriceCents: item.projectPriceCents,
              marketValueCents: item.marketValueCents,
              purchasedBy: item.purchasedBy,
              budgetCategoryId: item.budgetCategoryId,
              projectId: item.projectId,
              spaceId: item.spaceId,
            };
            for (let i = 0; i < 3; i++) {
              createItem(accountId, newItem);
            }
          },
        },
        {
          text: '5 copies',
          onPress: () => {
            const newItem = {
              name: item.name ?? '',
              notes: item.notes,
              status: item.status,
              source: item.source,
              sku: item.sku,
              transactionId: item.transactionId,
              purchasePriceCents: item.purchasePriceCents,
              projectPriceCents: item.projectPriceCents,
              marketValueCents: item.marketValueCents,
              purchasedBy: item.purchasedBy,
              budgetCategoryId: item.budgetCategoryId,
              projectId: item.projectId,
              spaceId: item.spaceId,
            };
            for (let i = 0; i < 5; i++) {
              createItem(accountId, newItem);
            }
          },
        },
      ]
    );
  };

  const handleSetSpace = (itemId: string) => {
    setSingleItemOperationId(itemId);
    setSingleItemSpacePickerVisible(true);
  };

  const handleSetStatus = (itemId: string, status: string) => {
    if (!accountId) return;
    updateItem(accountId, itemId, { status });
  };

  const handleSellToDesign = (_itemId: string) => {
    if (!accountId) return;
    Alert.alert(
      'Sell to Design Business',
      'This feature will be available soon.',
      [{ text: 'OK' }]
    );
  };

  const handleSellToProject = (_itemId: string) => {
    if (!accountId) return;
    Alert.alert(
      'Sell to Project',
      'This feature will be available soon.',
      [{ text: 'OK' }]
    );
  };

  const handleMoveToDesign = (_itemId: string) => {
    if (!accountId) return;
    Alert.alert(
      'Move to Design Business',
      'This feature will be available soon.',
      [{ text: 'OK' }]
    );
  };

  const handleMoveToProject = (_itemId: string) => {
    if (!accountId) return;
    Alert.alert(
      'Move to Project',
      'This feature will be available soon.',
      [{ text: 'OK' }]
    );
  };

  const handleDeleteItem = (itemId: string) => {
    if (!accountId) return;

    Alert.alert(
      'Delete item',
      'Permanently delete this item? This cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            deleteItem(accountId, itemId);
          },
        },
      ]
    );
  };

  const handleSingleItemSpaceConfirm = (spaceId: string | null) => {
    if (!accountId || !singleItemOperationId) return;
    updateItem(accountId, singleItemOperationId, { spaceId });
    setSingleItemSpacePickerVisible(false);
    setSingleItemOperationId(null);
  };

  // Enhanced item context menu (Phase C)
  const getItemMenuItems = useCallback((item: ScopedItem): AnchoredMenuItem[] => [
    {
      label: 'View item',
      onPress: () => router.push(`/items/${item.id}`),
      icon: 'open-in-new',
    },
    {
      label: 'Edit',
      onPress: () => router.push(`/items/${item.id}/edit`),
      icon: 'edit',
    },
    {
      label: 'Make copies',
      onPress: () => handleDuplicateItem(item.id),
      icon: 'content-copy',
    },
    {
      label: 'Set space',
      onPress: () => handleSetSpace(item.id),
      icon: 'place',
    },
    {
      label: 'Remove from transaction',
      onPress: () => handleRemoveLinkedItem(item.id),
      icon: 'remove-circle-outline',
      destructive: true,
    },
    {
      label: 'Status',
      subactions: [
        {
          key: 'to-purchase',
          label: 'To Purchase',
          onPress: () => handleSetStatus(item.id, 'to-purchase'),
        },
        {
          key: 'purchased',
          label: 'Purchased',
          onPress: () => handleSetStatus(item.id, 'purchased'),
        },
        {
          key: 'to-return',
          label: 'To Return',
          onPress: () => handleSetStatus(item.id, 'to-return'),
        },
        {
          key: 'returned',
          label: 'Returned',
          onPress: () => handleSetStatus(item.id, 'returned'),
        },
      ],
      selectedSubactionKey: item.status ?? undefined,
    },
    {
      label: 'Sell',
      actionOnly: true,
      subactions: [
        {
          key: 'sell-to-design',
          label: 'Sell to Design Business',
          onPress: () => handleSellToDesign(item.id),
        },
        {
          key: 'sell-to-project',
          label: 'Sell to Project',
          onPress: () => handleSellToProject(item.id),
        },
      ],
    },
    {
      label: 'Move',
      actionOnly: true,
      subactions: [
        {
          key: 'move-to-design',
          label: 'Move to Design Business',
          onPress: () => handleMoveToDesign(item.id),
        },
        {
          key: 'move-to-project',
          label: 'Move to Project',
          onPress: () => handleMoveToProject(item.id),
        },
      ],
    },
    {
      label: 'Delete',
      onPress: () => handleDeleteItem(item.id),
      icon: 'delete',
      destructive: true,
    },
  ], [router]);

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

  const addMenuItems: AnchoredMenuItem[] = useMemo(() => [
    {
      key: 'create',
      label: 'Create Item',
      icon: 'add' as const,
      onPress: handleCreateItem,
    },
    {
      key: 'add-existing',
      label: 'Add Existing Items',
      icon: 'playlist-add' as const,
      onPress: () => {
        setAddMenuVisible(false);
        setTimeout(() => {
          setIsPickingItems(true);
          setPickerTab('suggested');
          setPickerSelectedIds([]);
        }, 300);
      },
    },
  ], [handleCreateItem]);

  // Sort menu items
  const sortMenuItems = useMemo<AnchoredMenuItem[]>(() => [
    {
      key: 'alphabetical-asc',
      label: 'Name A → Z',
      onPress: () => {
        setSortMode('alphabetical-asc');
        setSortMenuVisible(false);
      },
      icon: sortMode === 'alphabetical-asc' ? 'check' : undefined,
    },
    {
      key: 'alphabetical-desc',
      label: 'Name Z → A',
      onPress: () => {
        setSortMode('alphabetical-desc');
        setSortMenuVisible(false);
      },
      icon: sortMode === 'alphabetical-desc' ? 'check' : undefined,
    },
    {
      key: 'price-desc',
      label: 'Price high → low',
      onPress: () => {
        setSortMode('price-desc');
        setSortMenuVisible(false);
      },
      icon: sortMode === 'price-desc' ? 'check' : undefined,
    },
    {
      key: 'price-asc',
      label: 'Price low → high',
      onPress: () => {
        setSortMode('price-asc');
        setSortMenuVisible(false);
      },
      icon: sortMode === 'price-asc' ? 'check' : undefined,
    },
    {
      key: 'created-desc',
      label: 'Newest first',
      onPress: () => {
        setSortMode('created-desc');
        setSortMenuVisible(false);
      },
      icon: sortMode === 'created-desc' ? 'check' : undefined,
    },
    {
      key: 'created-asc',
      label: 'Oldest first',
      onPress: () => {
        setSortMode('created-asc');
        setSortMenuVisible(false);
      },
      icon: sortMode === 'created-asc' ? 'check' : undefined,
    },
  ], [sortMode]);

  // Filter menu items
  const filterMenuItems = useMemo<AnchoredMenuItem[]>(() => [
    {
      key: 'all',
      label: 'All items',
      onPress: () => {
        setFilterMode('all');
        setFilterMenuVisible(false);
      },
      icon: filterMode === 'all' ? 'check' : undefined,
    },
    {
      key: 'bookmarked',
      label: 'Bookmarked',
      onPress: () => {
        setFilterMode('bookmarked');
        setFilterMenuVisible(false);
      },
      icon: filterMode === 'bookmarked' ? 'check' : undefined,
    },
    {
      key: 'no-sku',
      label: 'No SKU',
      onPress: () => {
        setFilterMode('no-sku');
        setFilterMenuVisible(false);
      },
      icon: filterMode === 'no-sku' ? 'check' : undefined,
    },
    {
      key: 'no-name',
      label: 'No name',
      onPress: () => {
        setFilterMode('no-name');
        setFilterMenuVisible(false);
      },
      icon: filterMode === 'no-name' ? 'check' : undefined,
    },
    {
      key: 'no-price',
      label: 'No project price',
      onPress: () => {
        setFilterMode('no-price');
        setFilterMenuVisible(false);
      },
      icon: filterMode === 'no-price' ? 'check' : undefined,
    },
    {
      key: 'no-image',
      label: 'No image',
      onPress: () => {
        setFilterMode('no-image');
        setFilterMenuVisible(false);
      },
      icon: filterMode === 'no-image' ? 'check' : undefined,
    },
  ], [filterMode]);

  // Bulk menu items
  const bulkMenuItems = useMemo<AnchoredMenuItem[]>(() => [
    {
      key: 'set-space',
      label: 'Set space',
      onPress: handleBulkSetSpace,
    },
    {
      key: 'set-status',
      label: 'Set status',
      onPress: handleBulkSetStatus,
    },
    {
      key: 'set-sku',
      label: 'Set SKU',
      onPress: handleBulkSetSKU,
    },
    {
      key: 'remove-from-transaction',
      label: 'Remove from transaction',
      onPress: handleBulkRemove,
      destructive: true,
    },
    {
      key: 'delete',
      label: 'Delete',
      onPress: handleBulkDelete,
      destructive: true,
    },
    {
      key: 'clear-selection',
      label: 'Clear selection',
      onPress: () => {
        setSelectedItemIds(new Set());
        setBulkMenuVisible(false);
      },
    },
  ], [selectedItemIds.size]);

  const handleDelete = () => {
    if (!accountId || !id) return;
    Alert.alert('Delete transaction', 'This will permanently delete this transaction.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          deleteTransaction(accountId, id);
          router.replace(fallbackTarget);
        },
      },
    ]);
  };

  const menuItems = useMemo<AnchoredMenuItem[]>(() => {
    const items: AnchoredMenuItem[] = [
      {
        label: 'Edit details',
        onPress: () => {
          router.push({
            pathname: '/transactions/[id]/edit',
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
      label: 'Delete transaction',
      onPress: handleDelete,
      icon: 'delete',
    });

    return items;
  }, [handleDelete, id, projectId, router, scope]);

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

            {/* Receipts Section */}
            <MediaGallerySection
              title="Receipts"
              attachments={transaction.receiptImages ?? []}
              maxAttachments={10}
              allowedKinds={['image', 'pdf']}
              onAddAttachment={handlePickReceiptAttachment}
              onRemoveAttachment={handleRemoveReceiptAttachment}
              onSetPrimary={handleSetPrimaryReceiptAttachment}
              emptyStateMessage="No receipts yet."
              pickerLabel="Add receipt"
              size="md"
              tileScale={1.5}
            />

            {/* Other Images Section */}
            <MediaGallerySection
              title="Other Images"
              attachments={transaction.otherImages ?? []}
              maxAttachments={5}
              allowedKinds={['image']}
              onAddAttachment={handlePickOtherImage}
              onRemoveAttachment={handleRemoveOtherImage}
              onSetPrimary={handleSetPrimaryOtherImage}
              emptyStateMessage="No other images yet."
              pickerLabel="Add image"
              size="md"
              tileScale={1.5}
            />

            <NotesSection notes={transaction.notes} expandable={true} />

            <TitledCard title="Details">
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
            </TitledCard>

            {itemizationEnabled ? (
              <TitledCard title="Tax & Itemization">
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
              </TitledCard>
            ) : null}

            {/* Transaction Items Section */}
            <View style={styles.itemsSection}>
              <AppText variant="caption" style={styles.sectionHeader}>
                TRANSACTION ITEMS
              </AppText>

              {!itemizationEnabled && linkedItems.length > 0 ? (
                <AppText variant="caption" style={[styles.warningText, getTextSecondaryStyle(uiKitTheme)]}>
                  Itemization is off, but this transaction already has items.
                </AppText>
              ) : null}

              <ItemsListControlBar
                search={searchQuery}
                onChangeSearch={setSearchQuery}
                showSearch={showSearch}
                onToggleSearch={() => setShowSearch(!showSearch)}
                onSort={() => setSortMenuVisible(true)}
                isSortActive={sortMode !== 'created-desc'}
                onFilter={() => setFilterMenuVisible(true)}
                isFilterActive={filterMode !== 'all'}
                onAdd={selectedItemIds.size > 0 ? () => setBulkMenuVisible(true) : () => setAddMenuVisible(true)}
                leftElement={
                  <TouchableOpacity
                    onPress={handleSelectAll}
                    style={[
                      styles.selectButton,
                      {
                        backgroundColor: uiKitTheme.button.secondary.background,
                        borderColor: uiKitTheme.border.primary,
                      },
                    ]}
                    accessibilityRole="checkbox"
                    accessibilityState={{ checked: selectedItemIds.size === filteredAndSortedItems.length }}
                  >
                    <SelectorCircle
                      selected={selectedItemIds.size === filteredAndSortedItems.length}
                      indicator="check"
                    />
                  </TouchableOpacity>
                }
              />

              {filteredAndSortedItems.length > 0 ? (
                <View style={styles.list}>
                  {filteredAndSortedItems.map((item) => {
                    const primaryImage = item.images?.find((img) => img.isPrimary) ?? item.images?.[0];
                    const thumbnailUri = primaryImage ? resolveAttachmentUri(primaryImage) ?? primaryImage.url : undefined;
                    const priceLabel = typeof item.purchasePriceCents === 'number'
                      ? `$${(item.purchasePriceCents / 100).toFixed(2)}`
                      : undefined;

                    return (
                      <ItemCard
                        key={item.id}
                        name={item.name?.trim() || 'Untitled item'}
                        sku={item.sku ?? undefined}
                        priceLabel={priceLabel}
                        thumbnailUri={thumbnailUri}
                        bookmarked={item.bookmark ?? undefined}
                        selected={selectedItemIds.has(item.id)}
                        onSelectedChange={(selected) => handleItemSelectionChange(item.id, selected)}
                        onPress={() => router.push(`/items/${item.id}`)}
                        menuItems={getItemMenuItems(item)}
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
            </View>

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

            {/* Add item menu */}
            <BottomSheetMenuList
              visible={addMenuVisible}
              onRequestClose={() => setAddMenuVisible(false)}
              items={addMenuItems}
              title="Add Item"
              showLeadingIcons={true}
            />

            {/* Sort menu */}
            <BottomSheetMenuList
              visible={sortMenuVisible}
              onRequestClose={() => setSortMenuVisible(false)}
              items={sortMenuItems}
              title="Sort by"
              showLeadingIcons={false}
            />

            {/* Filter menu */}
            <BottomSheetMenuList
              visible={filterMenuVisible}
              onRequestClose={() => setFilterMenuVisible(false)}
              items={filterMenuItems}
              title="Filter items"
              showLeadingIcons={false}
            />

            {/* Bulk actions menu */}
            <BottomSheetMenuList
              visible={bulkMenuVisible}
              onRequestClose={() => setBulkMenuVisible(false)}
              items={bulkMenuItems}
              title="Bulk actions"
              showLeadingIcons={false}
            />

            {/* Add existing items picker modal */}
            <BottomSheet
              visible={isPickingItems}
              onRequestClose={() => {
                setIsPickingItems(false);
                setPickerSelectedIds([]);
              }}
              containerStyle={styles.pickerSheet}
            >
              <View style={styles.pickerContent}>
                <AppText variant="h2" style={styles.pickerTitle}>Add Existing Items</AppText>
                <SharedItemPicker
                  tabs={pickerTabOptions}
                  tabCounts={{
                    suggested: suggestedItems.length,
                    ...(projectId ? { project: projectItems.length } : {}),
                    outside: outsideItemsHook.items.length,
                  }}
                  selectedTab={pickerTab}
                  onTabChange={(next) => {
                    setPickerTab(next as ItemPickerTab);
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
              </View>
            </BottomSheet>

            {/* Bulk space picker */}
            <BottomSheet
              visible={bulkSpacePickerVisible}
              onRequestClose={() => setBulkSpacePickerVisible(false)}
            >
              <View style={styles.pickerContent}>
                <AppText variant="h2" style={styles.pickerTitle}>Set Space</AppText>
                <AppText variant="caption" style={[styles.pickerSubtitle, getTextSecondaryStyle(uiKitTheme)]}>
                  {selectedItemIds.size} item{selectedItemIds.size === 1 ? '' : 's'} selected
                </AppText>
                <SpaceSelector
                  projectId={projectId ?? null}
                  value={null}
                  onChange={handleBulkSpaceConfirm}
                  allowCreate={true}
                  placeholder="Select space"
                />
              </View>
            </BottomSheet>

            {/* Bulk status picker */}
            <BottomSheetMenuList
              visible={bulkStatusPickerVisible}
              onRequestClose={() => setBulkStatusPickerVisible(false)}
              items={[
                {
                  key: 'to-purchase',
                  label: 'To Purchase',
                  onPress: () => handleBulkStatusConfirm('to-purchase'),
                },
                {
                  key: 'purchased',
                  label: 'Purchased',
                  onPress: () => handleBulkStatusConfirm('purchased'),
                },
                {
                  key: 'to-return',
                  label: 'To Return',
                  onPress: () => handleBulkStatusConfirm('to-return'),
                },
                {
                  key: 'returned',
                  label: 'Returned',
                  onPress: () => handleBulkStatusConfirm('returned'),
                },
              ]}
              title={`Set Status (${selectedItemIds.size} item${selectedItemIds.size === 1 ? '' : 's'})`}
              showLeadingIcons={false}
            />

            {/* Bulk SKU input */}
            <BottomSheet
              visible={bulkSKUInputVisible}
              onRequestClose={() => {
                setBulkSKUInputVisible(false);
                setBulkSKUValue('');
              }}
            >
              <View style={styles.pickerContent}>
                <AppText variant="h2" style={styles.pickerTitle}>Set SKU</AppText>
                <AppText variant="caption" style={[styles.pickerSubtitle, getTextSecondaryStyle(uiKitTheme)]}>
                  {selectedItemIds.size} item{selectedItemIds.size === 1 ? '' : 's'} selected
                </AppText>
                <View style={styles.inputContainer}>
                  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                    SKU
                  </AppText>
                  <TextInput
                    value={bulkSKUValue}
                    onChangeText={setBulkSKUValue}
                    placeholder="Enter SKU"
                    placeholderTextColor={uiKitTheme.text.secondary}
                    style={[
                      styles.textInput,
                      getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 }),
                      getTextColorStyle(uiKitTheme.text.primary),
                    ]}
                    autoCapitalize="characters"
                    autoCorrect={false}
                    returnKeyType="done"
                    onSubmitEditing={handleBulkSKUConfirm}
                  />
                </View>
                <View style={styles.buttonRow}>
                  <AppButton
                    title="Cancel"
                    variant="secondary"
                    onPress={() => {
                      setBulkSKUInputVisible(false);
                      setBulkSKUValue('');
                    }}
                    style={styles.button}
                  />
                  <AppButton
                    title="Apply"
                    variant="primary"
                    onPress={handleBulkSKUConfirm}
                    style={styles.button}
                  />
                </View>
              </View>
            </BottomSheet>

            {/* Single item space picker */}
            <BottomSheet
              visible={singleItemSpacePickerVisible}
              onRequestClose={() => {
                setSingleItemSpacePickerVisible(false);
                setSingleItemOperationId(null);
              }}
            >
              <View style={styles.pickerContent}>
                <AppText variant="h2" style={styles.pickerTitle}>Set Space</AppText>
                <SpaceSelector
                  projectId={projectId ?? null}
                  value={null}
                  onChange={handleSingleItemSpaceConfirm}
                  allowCreate={true}
                  placeholder="Select space"
                />
              </View>
            </BottomSheet>
          </>
        ) : (
          <AppText variant="body">Transaction not found.</AppText>
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
    lineHeight: 26,
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
  list: {
    gap: 8,
    marginTop: 12,
  },
  itemRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingVertical: 8,
  },
  warningText: {
    marginBottom: 12,
  },
  pickerSheet: {
    height: '85%',
  },
  pickerContent: {
    flex: 1,
    paddingHorizontal: 16,
    paddingBottom: 8,
    gap: 12,
  },
  pickerTitle: {
    textAlign: 'center',
  },
  pickerSubtitle: {
    textAlign: 'center',
    marginTop: -8,
  },
  inputContainer: {
    gap: 8,
    marginTop: 8,
  },
  textInput: {
    minHeight: 44,
  },
  buttonRow: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 16,
  },
  button: {
    flex: 1,
  },
  selectButton: {
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 40,
    minWidth: 40,
    paddingVertical: 10,
    paddingHorizontal: 10,
    borderWidth: 1,
  },
  itemsSection: {
    gap: 12,
    marginTop: 24,
  },
  sectionHeader: {
    letterSpacing: 0.5,
    textTransform: 'uppercase',
    fontWeight: '600',
  },
});
