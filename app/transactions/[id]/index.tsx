import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, SectionList, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { AppButton } from '../../../src/components/AppButton';
import { BottomSheet } from '../../../src/components/BottomSheet';
import { BottomSheetMenuList } from '../../../src/components/BottomSheetMenuList';
import type { AnchoredMenuItem } from '../../../src/components/AnchoredMenuList';
import { SharedItemPicker } from '../../../src/components/SharedItemPicker';
import { showItemConflictDialog } from '../../../src/components/ItemConflictDialog';
import { ItemCard } from '../../../src/components/ItemCard';
import { BulkSelectionBar } from '../../../src/components/BulkSelectionBar';
import { ItemsListControlBar } from '../../../src/components/ItemsListControlBar';
import { SelectorCircle } from '../../../src/components/SelectorCircle';
import { CollapsibleSectionHeader } from '../../../src/components/CollapsibleSectionHeader';
import { SpaceSelector } from '../../../src/components/SpaceSelector';
import { getTextColorStyle, getTextSecondaryStyle, layout, getBulkSelectionBarContentPadding } from '../../../src/ui';
import { useItemsManager } from '../../../src/hooks/useItemsManager';
import { SharedItemsList } from '../../../src/components/SharedItemsList';
import { useProjectContextStore } from '../../../src/data/projectContextStore';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../../src/theme/ThemeProvider';
import { createInventoryScopeConfig, createProjectScopeConfig } from '../../../src/data/scopeConfig';
import { ScopedItem, subscribeToScopedItems } from '../../../src/data/scopedListData';
import { updateItem, deleteItem, createItem } from '../../../src/data/itemsService';
import { saveLocalMedia, deleteLocalMediaByUrl, enqueueUpload, resolveAttachmentUri } from '../../../src/offline/media';
import type { AttachmentRef, AttachmentKind } from '../../../src/offline/media';
import { getTextInputStyle } from '../../../src/ui/styles/forms';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../../../src/data/budgetCategoriesService';
import { deleteTransaction, subscribeToTransaction, Transaction, updateTransaction } from '../../../src/data/transactionsService';
import { isCanonicalInventorySaleTransaction } from '../../../src/data/inventoryOperations';
import { useOutsideItems } from '../../../src/hooks/useOutsideItems';
import { resolveItemMove } from '../../../src/data/resolveItemMove';
import { NotesSection } from '../../../src/components/NotesSection';
import {
  HeroSection,
  ReceiptsSection,
  OtherImagesSection,
  DetailsSection,
  AuditSection,
  type MediaHandlers,
} from './sections';

type TransactionDetailParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
  listStateKey?: string;
};

type BulkAction = {
  id: string;
  label: string;
  onPress: (selectedIds: string[]) => void;
  destructive?: boolean;
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

type SectionKey = 'hero' | 'receipts' | 'otherImages' | 'notes' | 'details' | 'items' | 'audit';

const SECTION_HEADER_MARKER = '__sectionHeader__';

type TransactionSection = {
  key: SectionKey;
  title?: string;
  data: any[];
  badge?: string;
};

export default function TransactionDetailScreen() {
  const router = useRouter();
  const { setProjectId } = useProjectContextStore();
  const accountId = useAccountContextStore((store) => store.accountId);
  const params = useLocalSearchParams<TransactionDetailParams>();
  const id = Array.isArray(params.id) ? params.id[0] : params.id;
  const scope = Array.isArray(params.scope) ? params.scope[0] : params.scope;
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const backTarget = Array.isArray(params.backTarget) ? params.backTarget[0] : params.backTarget;
  const insets = useSafeAreaInsets();
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const [transaction, setTransaction] = useState<Transaction | null>(null);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string; metadata?: any }>>({});
  const [isPickingItems, setIsPickingItems] = useState(false);
  const [pickerTab, setPickerTab] = useState<ItemPickerTab>('suggested');
  const [pickerSelectedIds, setPickerSelectedIds] = useState<string[]>([]);
  const [menuVisible, setMenuVisible] = useState(false);
  const [addMenuVisible, setAddMenuVisible] = useState(false);
  const [bulkActionsSheetVisible, setBulkActionsSheetVisible] = useState(false);

  // Collapsible sections state (Phase 2)
  const [collapsedSections, setCollapsedSections] = useState<Record<string, boolean>>({
    receipts: false,    // Default EXPANDED
    otherImages: true,  // Default collapsed
    notes: true,        // Default collapsed
    details: true,      // Default collapsed
    items: true,        // Default collapsed
    audit: true,        // Default collapsed
  });

  const handleToggleSection = useCallback((key: string) => {
    setCollapsedSections(prev => ({ ...prev, [key]: !prev[key] }));
  }, []);

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

  // Helper to get primary image URI
  const getPrimaryImageUri = (item: ScopedItem) => {
    const primaryImage = item.images?.find((img) => img.isPrimary) ?? item.images?.[0];
    return primaryImage ? resolveAttachmentUri(primaryImage) ?? primaryImage.url : undefined;
  };

  // Initialize items manager with transaction-specific configuration
  const itemsManager = useItemsManager({
    items: linkedItems,
    defaultSort: 'created-desc',
    defaultFilter: 'all',
    sortModes: ['created-desc', 'created-asc', 'alphabetical-asc', 'alphabetical-desc', 'price-asc', 'price-desc'],
    filterModes: ['all', 'bookmarked', 'no-sku', 'no-name', 'no-price', 'no-image'],
    filterFn: (item, mode) => {
      switch (mode) {
        case 'bookmarked': return Boolean(item.bookmark);
        case 'no-sku': return !item.sku?.trim();
        case 'no-name': return !item.name?.trim();
        case 'no-price': return item.purchasePriceCents == null || item.purchasePriceCents === 0;
        case 'no-image': return !item.images || item.images.length === 0;
        default: return true;
      }
    },
    sortFn: (a, b, mode) => {
      switch (mode) {
        case 'price-asc':
          return (a.purchasePriceCents ?? 0) - (b.purchasePriceCents ?? 0);
        case 'price-desc':
          return (b.purchasePriceCents ?? 0) - (a.purchasePriceCents ?? 0);
        default:
          return 0;
      }
    },
  });

  const selectedCategory = transaction?.budgetCategoryId ? budgetCategories[transaction.budgetCategoryId] : undefined;
  const itemizationEnabled = selectedCategory?.metadata?.categoryType === 'itemized';
  const normalizedSource = transaction?.source?.trim().toLowerCase() ?? '';
  const statusLabel = transaction?.status?.trim() || '';

  // Compute sections array for SectionList
  const sections = useMemo<TransactionSection[]>(() => {
    if (!transaction) return [];

    const result: TransactionSection[] = [
      { key: 'hero', data: [transaction] },
      // All collapsible sections now render header + content together via SECTION_HEADER_MARKER
      { key: 'receipts', title: 'RECEIPTS', data: [SECTION_HEADER_MARKER] },
      { key: 'otherImages', title: 'OTHER IMAGES', data: [SECTION_HEADER_MARKER] },
      { key: 'notes', title: 'NOTES', data: [SECTION_HEADER_MARKER] },
      { key: 'details', title: 'DETAILS', data: [SECTION_HEADER_MARKER] },
    ];

    result.push({
      key: 'items',
      title: 'TRANSACTION ITEMS',
      data: collapsedSections.items ? [] : ['items-content'],
      badge: `${itemsManager.filteredAndSortedItems.length}`,
    });

    if (itemizationEnabled) {
      result.push({
        key: 'audit',
        title: 'TRANSACTION AUDIT',
        data: [SECTION_HEADER_MARKER],
      });
    }

    return result;
  }, [transaction, itemsManager.filteredAndSortedItems, itemizationEnabled, collapsedSections]);

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

  // Bulk operation state
  const [bulkSpacePickerVisible, setBulkSpacePickerVisible] = useState(false);
  const [bulkStatusPickerVisible, setBulkStatusPickerVisible] = useState(false);
  const [bulkSKUInputVisible, setBulkSKUInputVisible] = useState(false);
  const [bulkSKUValue, setBulkSKUValue] = useState('');

  const handleBulkSpaceConfirm = (spaceId: string | null) => {
    if (!accountId || itemsManager.selectionCount === 0) return;

    itemsManager.selectedIds.forEach((itemId) => {
      updateItem(accountId, itemId, { spaceId });
    });

    setBulkSpacePickerVisible(false);
    itemsManager.clearSelection();
  };

  const handleBulkStatusConfirm = (status: string) => {
    if (!accountId || itemsManager.selectionCount === 0) return;

    itemsManager.selectedIds.forEach((itemId) => {
      updateItem(accountId, itemId, { status });
    });

    setBulkStatusPickerVisible(false);
    itemsManager.clearSelection();
  };

  const handleBulkSKUConfirm = () => {
    if (!accountId || itemsManager.selectionCount === 0) return;

    const sku = bulkSKUValue.trim();
    itemsManager.selectedIds.forEach((itemId) => {
      updateItem(accountId, itemId, { sku });
    });

    setBulkSKUInputVisible(false);
    setBulkSKUValue('');
    itemsManager.clearSelection();
  };

  // Unified bulk action handler for ItemsSection
  const handleBulkAction = useCallback((actionId: string, _ids: string[]) => {
    switch (actionId) {
      case 'set-space':
        setBulkSpacePickerVisible(true);
        break;
      case 'set-status':
        setBulkStatusPickerVisible(true);
        break;
      case 'set-sku':
        setBulkSKUValue('');
        setBulkSKUInputVisible(true);
        break;
      case 'remove':
        if (!accountId || itemsManager.selectionCount === 0) return;
        Alert.alert(
          'Remove from transaction',
          `Remove ${itemsManager.selectionCount} item${itemsManager.selectionCount === 1 ? '' : 's'} from this transaction?`,
          [
            { text: 'Cancel', style: 'cancel' },
            {
              text: 'Remove',
              style: 'destructive',
              onPress: () => {
                itemsManager.selectedIds.forEach((itemId) => {
                  updateItem(accountId, itemId, { transactionId: null });
                });
                itemsManager.clearSelection();
              },
            },
          ]
        );
        break;
      case 'delete':
        if (!accountId || itemsManager.selectionCount === 0) return;
        Alert.alert(
          'Delete items',
          `Permanently delete ${itemsManager.selectionCount} item${itemsManager.selectionCount === 1 ? '' : 's'}? This cannot be undone.`,
          [
            { text: 'Cancel', style: 'cancel' },
            {
              text: 'Delete',
              style: 'destructive',
              onPress: () => {
                itemsManager.selectedIds.forEach((itemId) => {
                  deleteItem(accountId, itemId);
                });
                itemsManager.clearSelection();
              },
            },
          ]
        );
        break;
    }
  }, [accountId, itemsManager]);

  // Single item operation state
  const [singleItemSpacePickerVisible, setSingleItemSpacePickerVisible] = useState(false);
  const [singleItemOperationId, setSingleItemOperationId] = useState<string | null>(null);

  // Enhanced item menu handlers (Phase C & D)
  const handleDuplicateItem = (itemId: string) => {
    if (!accountId) return;

    const item = linkedItems.find((i) => i.id === itemId);
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
        itemsManager.setSortMode('alphabetical-asc');
        itemsManager.setSortMenuVisible(false);
      },
      icon: itemsManager.sortMode === 'alphabetical-asc' ? 'check' : undefined,
    },
    {
      key: 'alphabetical-desc',
      label: 'Name Z → A',
      onPress: () => {
        itemsManager.setSortMode('alphabetical-desc');
        itemsManager.setSortMenuVisible(false);
      },
      icon: itemsManager.sortMode === 'alphabetical-desc' ? 'check' : undefined,
    },
    {
      key: 'price-desc',
      label: 'Price high → low',
      onPress: () => {
        itemsManager.setSortMode('price-desc');
        itemsManager.setSortMenuVisible(false);
      },
      icon: itemsManager.sortMode === 'price-desc' ? 'check' : undefined,
    },
    {
      key: 'price-asc',
      label: 'Price low → high',
      onPress: () => {
        itemsManager.setSortMode('price-asc');
        itemsManager.setSortMenuVisible(false);
      },
      icon: itemsManager.sortMode === 'price-asc' ? 'check' : undefined,
    },
    {
      key: 'created-desc',
      label: 'Newest first',
      onPress: () => {
        itemsManager.setSortMode('created-desc');
        itemsManager.setSortMenuVisible(false);
      },
      icon: itemsManager.sortMode === 'created-desc' ? 'check' : undefined,
    },
    {
      key: 'created-asc',
      label: 'Oldest first',
      onPress: () => {
        itemsManager.setSortMode('created-asc');
        itemsManager.setSortMenuVisible(false);
      },
      icon: itemsManager.sortMode === 'created-asc' ? 'check' : undefined,
    },
  ], [itemsManager]);

  // Filter menu items
  const filterMenuItems = useMemo<AnchoredMenuItem[]>(() => [
    {
      key: 'all',
      label: 'All items',
      onPress: () => {
        itemsManager.setFilterMode('all');
        itemsManager.setFilterMenuVisible(false);
      },
      icon: itemsManager.filterMode === 'all' ? 'check' : undefined,
    },
    {
      key: 'bookmarked',
      label: 'Bookmarked',
      onPress: () => {
        itemsManager.setFilterMode('bookmarked');
        itemsManager.setFilterMenuVisible(false);
      },
      icon: itemsManager.filterMode === 'bookmarked' ? 'check' : undefined,
    },
    {
      key: 'no-sku',
      label: 'No SKU',
      onPress: () => {
        itemsManager.setFilterMode('no-sku');
        itemsManager.setFilterMenuVisible(false);
      },
      icon: itemsManager.filterMode === 'no-sku' ? 'check' : undefined,
    },
    {
      key: 'no-name',
      label: 'No name',
      onPress: () => {
        itemsManager.setFilterMode('no-name');
        itemsManager.setFilterMenuVisible(false);
      },
      icon: itemsManager.filterMode === 'no-name' ? 'check' : undefined,
    },
    {
      key: 'no-price',
      label: 'No project price',
      onPress: () => {
        itemsManager.setFilterMode('no-price');
        itemsManager.setFilterMenuVisible(false);
      },
      icon: itemsManager.filterMode === 'no-price' ? 'check' : undefined,
    },
    {
      key: 'no-image',
      label: 'No image',
      onPress: () => {
        itemsManager.setFilterMode('no-image');
        itemsManager.setFilterMenuVisible(false);
      },
      icon: itemsManager.filterMode === 'no-image' ? 'check' : undefined,
    },
  ], [itemsManager]);

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


  // Section renderers for SectionList
  // Only items gets a real section header (so it sticks). All other sections
  // render their headers as the first data item via SECTION_HEADER_MARKER.
  const renderSectionHeader = useCallback(({ section }: { section: TransactionSection }) => {
    if (section.key !== 'items') return null;

    const collapsed = collapsedSections.items ?? true;

    return (
      <View style={{ backgroundColor: theme.colors.background }}>
        <CollapsibleSectionHeader
          title={section.title!}
          collapsed={collapsed}
          onToggle={() => handleToggleSection('items')}
          badge={section.badge}
        />
        {!collapsed && (
          <View
            style={{
              paddingBottom: 12,
              borderBottomWidth: 1,
              borderBottomColor: uiKitTheme.border.secondary,
            }}
          >
            <ItemsListControlBar
              search={itemsManager.searchQuery}
              onChangeSearch={itemsManager.setSearchQuery}
              showSearch={itemsManager.showSearch}
              onToggleSearch={itemsManager.toggleSearch}
              onSort={() => itemsManager.setSortMenuVisible(true)}
              isSortActive={itemsManager.isSortActive}
              onFilter={() => itemsManager.setFilterMenuVisible(true)}
              isFilterActive={itemsManager.isFilterActive}
              onAdd={() => itemsManager.hasSelection ? setBulkActionsSheetVisible(true) : setAddMenuVisible(true)}
              leftElement={
                <TouchableOpacity
                  onPress={() => {
                    if (itemsManager.allSelected) {
                      itemsManager.clearSelection();
                    } else {
                      itemsManager.selectAll();
                    }
                  }}
                  style={[
                    styles.selectButton,
                    {
                      backgroundColor: uiKitTheme.button.secondary.background,
                      borderColor: uiKitTheme.border.primary,
                    },
                  ]}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: itemsManager.allSelected }}
                >
                  <SelectorCircle
                    selected={itemsManager.allSelected}
                    indicator="check"
                  />
                </TouchableOpacity>
              }
            />
          </View>
        )}
      </View>
    );
  }, [collapsedSections, handleToggleSection, itemsManager, theme.colors.background, uiKitTheme]);

  // Prepare media handlers object for MediaSection
  const mediaHandlers: MediaHandlers = useMemo(() => ({
    handlePickReceiptAttachment,
    handleRemoveReceiptAttachment,
    handleSetPrimaryReceiptAttachment,
    handlePickOtherImage,
    handleRemoveOtherImage,
    handleSetPrimaryOtherImage,
  }), [
    handlePickReceiptAttachment,
    handleRemoveReceiptAttachment,
    handleSetPrimaryReceiptAttachment,
    handlePickOtherImage,
    handleRemoveOtherImage,
    handleSetPrimaryOtherImage,
  ]);

  const renderItem = useCallback(({ item, section }: { item: any; section: TransactionSection }) => {
    if (!transaction) return null;

    // Render section headers that were moved into data (so they don't stick)
    // Wrap header + content in View with gap: 12 for proper spacing
    if (item === SECTION_HEADER_MARKER) {
      const collapsed = collapsedSections[section.key] ?? false;

      if (section.key === 'audit') {
        const showWarning = transaction.needsReview === true;

        return (
          <View style={{ gap: 12 }}>
            <TouchableOpacity
              onPress={() => handleToggleSection(section.key)}
              style={styles.sectionHeader}
              accessibilityRole="button"
              accessibilityLabel={`${section.title} section, ${collapsed ? 'collapsed' : 'expanded'}`}
            >
              <View style={styles.sectionHeaderContent}>
                <MaterialIcons
                  name={collapsed ? 'chevron-right' : 'expand-more'}
                  size={24}
                  color={uiKitTheme.text.secondary}
                />
                <AppText variant="caption" style={[styles.sectionHeaderTitle, { color: uiKitTheme.text.secondary }]}>
                  {section.title}
                </AppText>
                {showWarning && (
                  <View style={styles.reviewBadge}>
                    <Text style={styles.reviewBadgeText} numberOfLines={1}>
                      Needs Review
                    </Text>
                  </View>
                )}
              </View>
            </TouchableOpacity>
            {!collapsed && <AuditSection transaction={transaction} items={linkedItems} />}
          </View>
        );
      }

      // For other sections, wrap header + content together
      const renderSectionContent = () => {
        switch (section.key) {
          case 'receipts':
            return <ReceiptsSection transaction={transaction} handlers={mediaHandlers} />;
          case 'otherImages':
            return <OtherImagesSection transaction={transaction} handlers={mediaHandlers} />;
          case 'notes':
            return <NotesSection transaction={transaction} />;
          case 'details':
            return <DetailsSection transaction={transaction} budgetCategories={budgetCategories} itemizationEnabled={itemizationEnabled} />;
          default:
            return null;
        }
      };

      return (
        <View style={{ gap: 12 }}>
          <CollapsibleSectionHeader
            title={section.title!}
            collapsed={collapsed}
            onToggle={() => handleToggleSection(section.key)}
            badge={section.badge}
          />
          {!collapsed && renderSectionContent()}
        </View>
      );
    }

    // Non-header items (hero, items sections that don't use SECTION_HEADER_MARKER pattern)
    switch (section.key) {
      case 'hero':
        return <HeroSection transaction={item} />;

      case 'items': {
        // Define bulk actions for transaction detail
        const bulkActions: BulkAction[] = [
          { id: 'set-space', label: 'Set Space', onPress: (ids) => handleBulkAction('set-space', ids) },
          { id: 'set-status', label: 'Set Status', onPress: (ids) => handleBulkAction('set-status', ids) },
          { id: 'set-sku', label: 'Set SKU', onPress: (ids) => handleBulkAction('set-sku', ids) },
          { id: 'remove', label: 'Remove from Transaction', onPress: (ids) => handleBulkAction('remove', ids) },
          { id: 'delete', label: 'Delete Items', onPress: (ids) => handleBulkAction('delete', ids), destructive: true },
        ];

        // Create adapter for SharedItemsList embedded mode
        // Convert Set<string> to string[] and adapt methods
        const manager = {
          selectedIds: Array.from(itemsManager.selectedIds),
          selectAll: () => {
            const allItemIds = itemsManager.filteredAndSortedItems.map(item => item.id);
            const allSelected = allItemIds.length > 0 &&
              allItemIds.every(id => itemsManager.selectedIds.has(id));

            if (allSelected) {
              itemsManager.clearSelection();
            } else {
              itemsManager.selectAll();
            }
          },
          clearSelection: itemsManager.clearSelection,
          setItemSelected: (id: string, selected: boolean) => {
            const isCurrentlySelected = itemsManager.selectedIds.has(id);
            if (selected !== isCurrentlySelected) {
              itemsManager.toggleSelection(id);
            }
          },
          setGroupSelection: (ids: string[], selected: boolean) => {
            ids.forEach(id => {
              const isCurrentlySelected = itemsManager.selectedIds.has(id);
              if (selected !== isCurrentlySelected) {
                itemsManager.toggleSelection(id);
              }
            });
          },
        };

        return (
          <View style={{ flex: 1 }}>
            <SharedItemsList
              embedded={true}
              manager={manager}
              items={itemsManager.filteredAndSortedItems}
              bulkActions={bulkActions}
              onItemPress={(id) => router.push(`/items/${id}`)}
              getItemMenuItems={getItemMenuItems}
              emptyMessage={itemsManager.searchQuery.trim() ? 'No items match this search.' : 'No items in this transaction.'}
            />
          </View>
        );
      }

      default:
        return null;
    }
  }, [transaction, budgetCategories, mediaHandlers, itemsManager, router, getItemMenuItems, handleBulkAction, accountId, collapsedSections, handleToggleSection, uiKitTheme, linkedItems, itemizationEnabled]);

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
      includeBottomInset={false}
    >
      {isLoading ? (
        <View style={styles.loadingContainer}>
          <AppText variant="body">Loading transaction…</AppText>
        </View>
      ) : transaction ? (
        <>
          <SectionList
            sections={sections}
            renderSectionHeader={renderSectionHeader}
            renderItem={renderItem}
            stickySectionHeadersEnabled={true}
            keyExtractor={(item, index) => item.id ?? `section-${index}`}
            contentContainerStyle={[
              styles.content,
              itemsManager.selectionCount > 0 ? { paddingBottom: getBulkSelectionBarContentPadding(insets.bottom) } : undefined
            ]}
            showsVerticalScrollIndicator={false}
            ItemSeparatorComponent={({ section }) =>
              section.key === 'items' ? <View style={styles.itemSeparator} /> : null
            }
          />

          <BulkSelectionBar
            selectedCount={itemsManager.selectionCount}
            onBulkActionsPress={() => setBulkActionsSheetVisible(true)}
            onClearSelection={itemsManager.clearSelection}
          />

          {/* Bulk actions sheet for items section */}
          <BottomSheetMenuList
            visible={bulkActionsSheetVisible}
            onRequestClose={() => setBulkActionsSheetVisible(false)}
            items={[
              {
                key: 'set-space',
                label: 'Set Space',
                onPress: () => {
                  setBulkActionsSheetVisible(false);
                  handleBulkAction('set-space', []);
                },
              },
              {
                key: 'set-status',
                label: 'Set Status',
                onPress: () => {
                  setBulkActionsSheetVisible(false);
                  handleBulkAction('set-status', []);
                },
              },
              {
                key: 'set-sku',
                label: 'Set SKU',
                onPress: () => {
                  setBulkActionsSheetVisible(false);
                  handleBulkAction('set-sku', []);
                },
              },
              {
                key: 'remove',
                label: 'Remove from Transaction',
                onPress: () => {
                  setBulkActionsSheetVisible(false);
                  handleBulkAction('remove', []);
                },
              },
              {
                key: 'delete',
                label: 'Delete Items',
                onPress: () => {
                  setBulkActionsSheetVisible(false);
                  handleBulkAction('delete', []);
                },
              },
            ]}
            title={`Bulk Actions (${itemsManager.selectionCount})`}
            showLeadingIcons={false}
          />

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
              visible={itemsManager.sortMenuVisible}
              onRequestClose={() => itemsManager.setSortMenuVisible(false)}
              items={sortMenuItems}
              title="Sort by"
              showLeadingIcons={false}
            />

            {/* Filter menu */}
            <BottomSheetMenuList
              visible={itemsManager.filterMenuVisible}
              onRequestClose={() => itemsManager.setFilterMenuVisible(false)}
              items={filterMenuItems}
              title="Filter items"
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
                  {itemsManager.selectionCount} item{itemsManager.selectionCount === 1 ? '' : 's'} selected
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
              title={`Set Status (${itemsManager.selectionCount} item${itemsManager.selectionCount === 1 ? '' : 's'})`}
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
                  {itemsManager.selectionCount} item{itemsManager.selectionCount === 1 ? '' : 's'} selected
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
          <View style={styles.loadingContainer}>
            <AppText variant="body">Transaction not found.</AppText>
          </View>
        )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
    paddingBottom: 24,
    gap: 4,  // Section-to-section spacing (tight)
  },
  screenContent: {
    paddingTop: 0,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  itemSeparator: {
    height: 10,
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
  sectionHeader: {
    minHeight: 44,
    justifyContent: 'center',
    paddingHorizontal: 0,
  },
  sectionHeaderContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  sectionHeaderTitle: {
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    fontWeight: '600',
  },
  reviewBadge: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 999,
    borderWidth: 1,
    maxWidth: 160,
    marginLeft: 'auto',
    backgroundColor: '#b9452014',
    borderColor: '#b9452033',
  },
  reviewBadgeText: {
    fontSize: 12,
    fontWeight: '600',
    lineHeight: 16,
    color: '#b94520',
  },
});
