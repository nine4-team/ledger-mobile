import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, SectionList, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { MaterialIcons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { BottomSheet } from '../../../src/components/BottomSheet';
import { BottomSheetMenuList } from '../../../src/components/BottomSheetMenuList';
import type { AnchoredMenuItem, AnchoredMenuSubaction } from '../../../src/components/AnchoredMenuList';
import { showItemConflictDialog } from '../../../src/components/ItemConflictDialog';
import { ItemCard } from '../../../src/components/ItemCard';
import { BulkSelectionBar } from '../../../src/components/BulkSelectionBar';
import { ItemsListControlBar } from '../../../src/components/ItemsListControlBar';
import { SelectorCircle } from '../../../src/components/SelectorCircle';
import { CollapsibleSectionHeader } from '../../../src/components/CollapsibleSectionHeader';
import { layout } from '../../../src/ui';
import { useItemsManager } from '../../../src/hooks/useItemsManager';
import { SharedItemsList } from '../../../src/components/SharedItemsList';
import { useProjectContextStore } from '../../../src/data/projectContextStore';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../../src/theme/ThemeProvider';
import { createInventoryScopeConfig, createProjectScopeConfig } from '../../../src/data/scopeConfig';
import { ScopedItem, subscribeToScopedItems, subscribeToTransactionItems } from '../../../src/data/scopedListData';
import { updateItem, deleteItem, createItem } from '../../../src/data/itemsService';
import { saveLocalMedia, deleteLocalMediaByUrl, enqueueUpload, processUploadQueue, resolveAttachmentUri } from '../../../src/offline/media';
import type { AttachmentRef, AttachmentKind } from '../../../src/offline/media';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../../../src/data/budgetCategoriesService';
import { deleteTransaction, subscribeToTransaction, Transaction, updateTransaction } from '../../../src/data/transactionsService';
import {
  isCanonicalInventorySaleTransaction,
  requestProjectToBusinessSale,
  requestProjectToProjectMove,
  requestBusinessToProjectPurchase,
} from '../../../src/data/inventoryOperations';
import { useOutsideItems } from '../../../src/hooks/useOutsideItems';
import { resolveItemMove } from '../../../src/data/resolveItemMove';
import {
  validateTransactionReassign,
  reassignTransactionToInventory,
  reassignTransactionToProject,
  validateItemReassign,
  reassignItemToInventory,
  reassignItemToProject,
} from '../../../src/data/reassignService';
import { NotesSection } from '../../../src/components/NotesSection';
import { SetSpaceModal } from '../../../src/components/modals/SetSpaceModal';
import { ReassignToProjectModal } from '../../../src/components/modals/ReassignToProjectModal';
import { SellToProjectModal } from '../../../src/components/modals/SellToProjectModal';
import { SellToBusinessModal } from '../../../src/components/modals/SellToBusinessModal';
import {
  HeroSection,
  ReceiptsSection,
  OtherImagesSection,
  DetailsSection,
  AuditSection,
  NextStepsSection,
  type MediaHandlers,
} from './sections';
import type { MediaGallerySectionRef } from '../../../src/components/MediaGallerySection';
import { buildSingleItemMenu } from '../../../src/actions/itemMenuBuilder';
import { showToast } from '../../../src/components/toastStore';
import { subscribeToEdgesFromTransaction } from '../../../src/data/lineageEdgesService';
import type { ItemLineageEdge } from '../../../src/data/lineageEdgesService';
import { useItemsByIds } from '../../../src/hooks/useItemsByIds';
import { findIncompleteReturns } from '../../../src/utils/incompleteReturnDetection';
import { useReturnTransactionPicker } from '../../../src/hooks/useReturnTransactionPicker';
import { ReturnTransactionPickerModal } from '../../../src/components/modals/ReturnTransactionPickerModal';
import { EditNotesModal } from '../../../src/components/modals/EditNotesModal';
import { CreateItemsFromListModal } from '../../../src/components/modals/CreateItemsFromListModal';
import type { ParsedReceiptItem } from '../../../src/utils/receiptListParser';
import { EditTransactionDetailsModal } from '../../../src/components/modals/EditTransactionDetailsModal';
import type { EditTransactionDetailsField } from '../../../src/components/modals/EditTransactionDetailsModal';
import { MovedItemsSection } from './sections/MovedItemsSection';

type TransactionDetailParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
  listStateKey?: string;
  showNextSteps?: string;
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

type SectionKey = 'hero' | 'nextSteps' | 'receipts' | 'otherImages' | 'notes' | 'details' | 'items' | 'returnedItems' | 'soldItems' | 'audit';

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
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();
  const [transaction, setTransaction] = useState<Transaction | null>(null);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string; metadata?: any }>>({});
  const [isPickingItems, setIsPickingItems] = useState(false);
  const [pickerTab, setPickerTab] = useState<ItemPickerTab>('suggested');
  const [menuVisible, setMenuVisible] = useState(false);
  const [addMenuVisible, setAddMenuVisible] = useState(false);
  const [listImportVisible, setListImportVisible] = useState(false);
  const [bulkActionsSheetVisible, setBulkActionsSheetVisible] = useState(false);
  const [reassignToProjectVisible, setReassignToProjectVisible] = useState(false);
  const [singleItemReassignProjectVisible, setSingleItemReassignProjectVisible] = useState(false);
  const [singleItemReassignId, setSingleItemReassignId] = useState<string | null>(null);

  // Lineage edges state
  const [edgesFromTransaction, setEdgesFromTransaction] = useState<ItemLineageEdge[]>([]);

  const scopeConfig = useMemo(
    () => scope === 'inventory' ? createInventoryScopeConfig() : projectId ? createProjectScopeConfig(projectId) : null,
    [scope, projectId],
  );

  // Return transaction picker hook
  const returnPicker = useReturnTransactionPicker({
    accountId,
    scopeConfig: scopeConfig ?? null,
    fromTransactionId: id ?? null,
    projectId: projectId ?? null,
    onComplete: () => itemsManager.clearSelection(),
  });

  // Sell-to-business modal state
  const [singleItemSellToBusinessVisible, setSingleItemSellToBusinessVisible] = useState(false);
  const [singleItemSellId, setSingleItemSellId] = useState<string | null>(null);

  // Sell-to-project modal state
  const [singleItemSellToProjectVisible, setSingleItemSellToProjectVisible] = useState(false);
  const [sellTargetProjectId, setSellTargetProjectId] = useState<string | null>(null);
  const [sellDestBudgetCategories, setSellDestBudgetCategories] = useState<Record<string, { name: string }>>({});

  const [editDetailsVisible, setEditDetailsVisible] = useState(false);
  const [editDetailsFocusField, setEditDetailsFocusField] = useState<EditTransactionDetailsField | undefined>();
  const [editNotesVisible, setEditNotesVisible] = useState(false);

  // Collapsible sections state (Phase 2)
  const [collapsedSections, setCollapsedSections] = useState<Record<string, boolean>>({
    receipts: false,    // Default EXPANDED
    otherImages: true,  // Default collapsed
    notes: true,        // Default collapsed
    details: true,      // Default collapsed
    items: true,        // Default collapsed
    returnedItems: true, // Default collapsed
    soldItems: true,     // Default collapsed
    audit: true,        // Default collapsed
  });

  const sectionListRef = useRef<SectionList<any, TransactionSection>>(null);
  const receiptsRef = useRef<MediaGallerySectionRef>(null);
  const otherImagesRef = useRef<MediaGallerySectionRef>(null);

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

  // Subscribe to lineage edges from this transaction
  useEffect(() => {
    if (!accountId || !id) {
      setEdgesFromTransaction([]);
      return;
    }
    return subscribeToEdgesFromTransaction(accountId, id, setEdgesFromTransaction);
  }, [accountId, id]);

  // Subscribe to destination project budget categories for sell-to-project modal
  useEffect(() => {
    if (!accountId || !sellTargetProjectId) {
      setSellDestBudgetCategories({});
      return;
    }
    const unsub = subscribeToBudgetCategories(accountId, (raw) => {
      setSellDestBudgetCategories(mapBudgetCategories(raw));
    });
    return unsub;
  }, [accountId, sellTargetProjectId]);

  const isCanonicalTx = isCanonicalInventorySaleTransaction(transaction);

  useEffect(() => {
    if (!accountId || !id || !scope) {
      setItems([]);
      return;
    }
    // Canonical sale items may have a different projectId than the transaction,
    // so query by transactionId directly instead of by scope.
    if (isCanonicalTx) {
      const unsubscribe = subscribeToTransactionItems(accountId, id, (next) => {
        setItems(next);
      });
      return () => unsubscribe();
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
  }, [accountId, id, isCanonicalTx, projectId, scope]);

  const fallbackTarget = useMemo(() => {
    if (backTarget) return backTarget;
    if (scope === 'inventory') return '/(tabs)/screen-two?tab=transactions';
    if (scope === 'project' && projectId) return `/project/${projectId}?tab=transactions`;
    return '/(tabs)/index';
  }, [backTarget, projectId, scope]);

  const isCanonical = isCanonicalTx;
  const linkedItems = useMemo(() => items.filter((item) => item.transactionId === id), [id, items]);

  // Derive returned/sold item IDs from lineage edges
  const returnedItemIds = useMemo(
    () => edgesFromTransaction
      .filter((e) => e.movementKind === 'returned')
      .map((e) => e.itemId),
    [edgesFromTransaction],
  );
  const soldItemIds = useMemo(
    () => edgesFromTransaction
      .filter((e) => e.movementKind === 'sold')
      .map((e) => e.itemId),
    [edgesFromTransaction],
  );

  // Subscribe to returned/sold items for display
  const { items: returnedItems } = useItemsByIds(accountId, returnedItemIds);
  const { items: soldItems } = useItemsByIds(accountId, soldItemIds);

  // Compute incomplete returns (items marked as returned but not linked to a return transaction)
  const incompleteReturnItemIds = useMemo(() => {
    if (!transaction) return new Set<string>();
    return new Set(findIncompleteReturns(linkedItems, transaction, edgesFromTransaction));
  }, [linkedItems, transaction, edgesFromTransaction]);

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

  // Compute badge info for header (mirrors TransactionCard badges)
  const transactionType = transaction?.transactionType;
  const needsReview = transaction?.needsReview;
  const reimbursementType = transaction?.reimbursementType;
  const hasEmailReceipt = transaction?.hasEmailReceipt;
  const budgetCategoryName = selectedCategory?.name?.trim();

  // Compute sections array for SectionList
  const sections = useMemo<TransactionSection[]>(() => {
    if (!transaction) return [];

    const result: TransactionSection[] = [
      { key: 'hero', data: [transaction] },
      { key: 'nextSteps', data: [transaction] },
      // All collapsible sections now render header + content together via SECTION_HEADER_MARKER
      { key: 'receipts', title: 'RECEIPTS', data: [SECTION_HEADER_MARKER] },
      { key: 'otherImages', title: 'OTHER IMAGES', data: [SECTION_HEADER_MARKER] },
      { key: 'notes', title: 'NOTES', data: [SECTION_HEADER_MARKER] },
      { key: 'details', title: 'DETAILS', data: [SECTION_HEADER_MARKER] },
    ];

    result.push({
      key: 'items',
      title: 'ITEMS',
      data: collapsedSections.items ? [] : ['items-content'],
      badge: `${itemsManager.filteredAndSortedItems.length}`,
    });

    if (returnedItems.length > 0) {
      result.push({
        key: 'returnedItems',
        title: 'RETURNED ITEMS',
        data: [SECTION_HEADER_MARKER],
        badge: `${returnedItems.length}`,
      });
    }

    if (soldItems.length > 0) {
      result.push({
        key: 'soldItems',
        title: 'SOLD ITEMS',
        data: [SECTION_HEADER_MARKER],
        badge: `${soldItems.length}`,
      });
    }

    if (itemizationEnabled) {
      result.push({
        key: 'audit',
        title: 'TRANSACTION AUDIT',
        data: [SECTION_HEADER_MARKER],
      });
    }

    return result;
  }, [transaction, itemsManager.filteredAndSortedItems, itemizationEnabled, collapsedSections, returnedItems, soldItems]);

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

  const pickerManager = useItemsManager({
    items: activePickerItems,
    sortModes: ['created-desc'],
    filterModes: ['all'],
  });

  const pickerManagerAdapter = useMemo(() => ({
    ...pickerManager,
    setGroupSelection: (ids: string[], selected: boolean) => {
      ids.forEach(id => {
        const isCurrentlySelected = pickerManager.selectedIds.has(id);
        if (selected !== isCurrentlySelected) {
          pickerManager.toggleSelection(id);
        }
      });
    },
    setItemSelected: (id: string, selected: boolean) => {
      const isCurrentlySelected = pickerManager.selectedIds.has(id);
      if (selected !== isCurrentlySelected) {
        pickerManager.toggleSelection(id);
      }
    },
  }), [pickerManager]);

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
    processUploadQueue().catch(console.error);
  };

  const handlePickReceiptAttachments = async (localUris: string[], kind: AttachmentKind) => {
    if (!accountId || !id || !transaction) return;

    const mimeType = kind === 'pdf' ? 'application/pdf' : 'image/jpeg';
    let currentAttachments = transaction.receiptImages ?? [];
    const mediaIds: string[] = [];

    // Process each image sequentially so thumbnails appear one by one
    for (const uri of localUris) {
      if (currentAttachments.length >= 10) break;

      const result = await saveLocalMedia({
        localUri: uri,
        mimeType,
        ownerScope: `transaction:${id}`,
        persistCopy: true,
      });
      mediaIds.push(result.mediaId);

      const hasPrimary = currentAttachments.some((att) => att.isPrimary);
      const newAttachment: AttachmentRef = {
        url: result.attachmentRef.url,
        kind,
        isPrimary: !hasPrimary && kind === 'image',
      };
      currentAttachments = [...currentAttachments, newAttachment];

      // Update after each image so the thumbnail appears immediately
      updateTransaction(accountId, id, {
        receiptImages: currentAttachments,
        transactionImages: currentAttachments,
      });
    }

    // Enqueue all uploads then process the queue
    for (const mediaId of mediaIds) {
      await enqueueUpload({ mediaId });
    }
    processUploadQueue().catch(console.error);
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
    processUploadQueue().catch(console.error);
  };

  const handlePickOtherImages = async (localUris: string[], kind: AttachmentKind) => {
    if (!accountId || !id || !transaction) return;

    const mimeType = kind === 'pdf' ? 'application/pdf' : 'image/jpeg';
    let currentImages = transaction.otherImages ?? [];
    const mediaIds: string[] = [];

    for (const uri of localUris) {
      if (currentImages.length >= 5) break;

      const result = await saveLocalMedia({
        localUri: uri,
        mimeType,
        ownerScope: `transaction:${id}`,
        persistCopy: true,
      });
      mediaIds.push(result.mediaId);

      const hasPrimary = currentImages.some((img) => img.isPrimary);
      const newImage: AttachmentRef = {
        url: result.attachmentRef.url,
        kind,
        isPrimary: !hasPrimary && kind === 'image',
      };
      currentImages = [...currentImages, newImage];

      updateTransaction(accountId, id, { otherImages: currentImages });
    }

    for (const mediaId of mediaIds) {
      await enqueueUpload({ mediaId });
    }
    processUploadQueue().catch(console.error);
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
    if (!accountId || !id || pickerManager.selectionCount === 0) return;
    const selectedItems = activePickerItems.filter((item) => pickerManager.selectedIds.has(item.id));
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
      pickerManager.clearSelection();
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
    pickerManager,
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
    if (status === 'returned' && transaction?.transactionType !== 'return') {
      returnPicker.openForItems(Array.from(itemsManager.selectedIds));
    } else {
      itemsManager.clearSelection();
    }
  };

  // Unified bulk action handler for ItemsSection
  const handleBulkAction = useCallback((actionId: string, _ids: string[]) => {
    switch (actionId) {
      case 'set-space':
        setBulkSpacePickerVisible(true);
        break;
      case 'clear-space':
        if (!accountId || itemsManager.selectionCount === 0) return;
        itemsManager.selectedIds.forEach((itemId) => {
          updateItem(accountId, itemId, { spaceId: null });
        });
        itemsManager.clearSelection();
        break;
      case 'set-status':
        setBulkStatusPickerVisible(true);
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
      case 'move-to-return':
        returnPicker.openForItems(Array.from(itemsManager.selectedIds));
        break;
    }
  }, [accountId, itemsManager, returnPicker]);

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
    if (status === 'returned' && transaction?.transactionType !== 'return') {
      returnPicker.openForItem(itemId);
    }
  };

  const handleMoveToReturnTransaction = (itemId: string) => {
    returnPicker.openForItem(itemId);
  };

  const handleSellToDesign = (itemId: string) => {
    if (!accountId) return;
    setSingleItemSellId(itemId);
    setSingleItemSellToBusinessVisible(true);
  };

  const handleSellToProject = (itemId: string) => {
    if (!accountId) return;
    setSingleItemSellId(itemId);
    setSingleItemSellToProjectVisible(true);
  };

  const handleReassignItemToInventory = (itemId: string) => {
    if (!accountId) return;
    const item = linkedItems.find((i) => i.id === itemId);
    if (!item) return;
    const result = validateItemReassign(item, null);
    if (!result.valid) {
      Alert.alert("Cannot Reassign", result.error, [{ text: "OK" }]);
      return;
    }
    Alert.alert(
      "Reassign to Inventory?",
      "This item will be moved to business inventory.\nNo sale or purchase records will be created.\n\nUse this to fix items that were added to the wrong project.\nIf this is a real business transfer, use Sell instead.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Reassign",
          onPress: () => {
            reassignItemToInventory(accountId, itemId);
            showToast('Item reassigned to inventory');
          },
        },
      ]
    );
  };

  const handleReassignItemToProject = (itemId: string) => {
    if (!accountId) return;
    setSingleItemReassignId(itemId);
    setSingleItemReassignProjectVisible(true);
  };

  const handleTransactionReassignToInventory = () => {
    if (!accountId || !id || !transaction) return;
    const result = validateTransactionReassign(transaction, null);
    if (!result.valid) {
      Alert.alert("Cannot Reassign", result.error, [{ text: "OK" }]);
      return;
    }
    const itemIds = linkedItems.map((i) => i.id);
    Alert.alert(
      "Reassign to Inventory?",
      "This transaction and all its items will be moved to business inventory.\nNo sale or purchase records will be created.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Reassign",
          onPress: () => {
            reassignTransactionToInventory(accountId, id, itemIds);
          },
        },
      ]
    );
  };

  const handleTransactionReassignToProjectConfirm = (targetProjectId: string) => {
    if (!accountId || !id || !transaction) return;
    const result = validateTransactionReassign(transaction, targetProjectId);
    if (!result.valid) {
      Alert.alert("Cannot Reassign", result.error, [{ text: "OK" }]);
      return;
    }
    const itemIds = linkedItems.map((i) => i.id);
    Alert.alert(
      "Reassign to Project?",
      "This transaction and all its items will be moved to the selected project.\nNo sale or purchase records will be created.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Reassign",
          onPress: () => {
            reassignTransactionToProject(accountId, id, targetProjectId, itemIds);
            setReassignToProjectVisible(false);
          },
        },
      ]
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

  const handleClearSpace = (itemId: string) => {
    if (!accountId) return;
    updateItem(accountId, itemId, { spaceId: null });
  };

  // Item context menu — uses canonical builder for consistency across all contexts
  const getItemMenuItems = useCallback((item: ScopedItem): AnchoredMenuItem[] => {
    if (!scopeConfig) return [];
    return buildSingleItemMenu({
      context: 'transaction',
      scopeConfig,
      selectedStatus: item.status ?? null,
      callbacks: {
        onViewItem: () => router.push(`/items/${item.id}`),
        onEditOrOpen: () => router.push(`/items/${item.id}`),
        onMakeCopies: () => handleDuplicateItem(item.id),
        onStatusChange: (status) => handleSetStatus(item.id, status),
        onSetTransaction: () => {},
        onClearTransaction: () => handleRemoveLinkedItem(item.id),
        onSetSpace: () => handleSetSpace(item.id),
        onClearSpace: () => handleClearSpace(item.id),
        onSellToBusiness: scopeConfig.scope === 'project' ? () => handleSellToDesign(item.id) : undefined,
        onSellToProject: () => handleSellToProject(item.id),
        onReassignToInventory: scopeConfig.scope === 'project' ? () => handleReassignItemToInventory(item.id) : undefined,
        onReassignToProject: () => handleReassignItemToProject(item.id),
        onMoveToReturnTransaction: () => handleMoveToReturnTransaction(item.id),
        onDelete: () => handleDeleteItem(item.id),
      },
    });
  }, [scopeConfig, router, handleDuplicateItem, handleSetStatus, handleRemoveLinkedItem,
      handleSetSpace, handleClearSpace, handleSellToDesign, handleSellToProject,
      handleReassignItemToInventory, handleReassignItemToProject, handleMoveToReturnTransaction, handleDeleteItem]);

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

  const handleCreateItemsFromList = useCallback(
    (parsedItems: ParsedReceiptItem[]) => {
      if (!accountId || !id) return;
      const isCanonical = isCanonicalInventorySaleTransaction(transaction);
      const budgetCategoryId = !isCanonical ? (transaction?.budgetCategoryId ?? null) : null;
      for (const parsed of parsedItems) {
        createItem(accountId, {
          name: parsed.name,
          sku: parsed.sku,
          purchasePriceCents: parsed.priceCents,
          projectPriceCents: parsed.priceCents,
          projectId: scope === 'project' ? (projectId ?? null) : null,
          transactionId: id,
          budgetCategoryId,
          spaceId: null,
          source: null,
        });
      }
      showToast(`Created ${parsedItems.length} item${parsedItems.length !== 1 ? 's' : ''}`);
    },
    [accountId, id, scope, projectId, transaction],
  );

  const hasOtherImages = (transaction?.otherImages?.length ?? 0) > 0;

  const addMenuItems: AnchoredMenuItem[] = useMemo(() => {
    const items: AnchoredMenuItem[] = [
      {
        key: 'add-existing',
        label: 'Add Existing Items',
        icon: 'playlist-add' as const,
        onPress: () => {
          setAddMenuVisible(false);
          setTimeout(() => {
            setIsPickingItems(true);
            setPickerTab('suggested');
            pickerManager.clearSelection();
          }, 300);
        },
      },
    ];
    if (hasOtherImages) {
      items.push({
        key: 'from-photos',
        label: 'Create From Photos',
        icon: 'photo-library' as const,
        onPress: () => {
          setAddMenuVisible(false);
          setTimeout(() => {
            const idx = sections.findIndex((s) => s.key === 'otherImages');
            if (idx >= 0) {
              sectionListRef.current?.scrollToLocation({ sectionIndex: idx, itemIndex: 0, animated: true });
            }
          }, 300);
        },
      });
    }
    items.push({
      key: 'from-list',
      label: 'Create Items from List',
      icon: 'receipt-long' as const,
      onPress: () => {
        setAddMenuVisible(false);
        setTimeout(() => setListImportVisible(true), 300);
      },
    });
    items.push({
      key: 'create',
      label: 'Create Item Manually',
      icon: 'add' as const,
      onPress: handleCreateItem,
    });
    return items;
  }, [handleCreateItem, hasOtherImages, sections]);

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
      label: 'Price High → Low',
      onPress: () => {
        itemsManager.setSortMode('price-desc');
        itemsManager.setSortMenuVisible(false);
      },
      icon: itemsManager.sortMode === 'price-desc' ? 'check' : undefined,
    },
    {
      key: 'price-asc',
      label: 'Price Low → High',
      onPress: () => {
        itemsManager.setSortMode('price-asc');
        itemsManager.setSortMenuVisible(false);
      },
      icon: itemsManager.sortMode === 'price-asc' ? 'check' : undefined,
    },
    {
      key: 'created-desc',
      label: 'Newest First',
      onPress: () => {
        itemsManager.setSortMode('created-desc');
        itemsManager.setSortMenuVisible(false);
      },
      icon: itemsManager.sortMode === 'created-desc' ? 'check' : undefined,
    },
    {
      key: 'created-asc',
      label: 'Oldest First',
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
      label: 'All Items',
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
      label: 'No Name',
      onPress: () => {
        itemsManager.setFilterMode('no-name');
        itemsManager.setFilterMenuVisible(false);
      },
      icon: itemsManager.filterMode === 'no-name' ? 'check' : undefined,
    },
    {
      key: 'no-price',
      label: 'No Project Price',
      onPress: () => {
        itemsManager.setFilterMode('no-price');
        itemsManager.setFilterMenuVisible(false);
      },
      icon: itemsManager.filterMode === 'no-price' ? 'check' : undefined,
    },
    {
      key: 'no-image',
      label: 'No Image',
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

  const handleSaveTransactionDetails = (changes: Partial<Transaction>) => {
    if (!accountId || !id) return;
    updateTransaction(accountId, id, changes);
    setEditDetailsVisible(false);
    setEditDetailsFocusField(undefined);
    showToast('Transaction updated');
  };

  const handleSaveNotes = (notes: string) => {
    if (!accountId || !id) return;
    updateTransaction(accountId, id, { notes });
    setEditNotesVisible(false);
    showToast('Notes updated');
  };

  const menuItems = useMemo<AnchoredMenuItem[]>(() => {
    const items: AnchoredMenuItem[] = [];

    if (!isCanonical) {
      const reassignSubactions: AnchoredMenuSubaction[] = [];
      if (transaction?.projectId) {
        reassignSubactions.push({
          key: 'reassign-to-inventory',
          label: 'Reassign to Inventory',
          onPress: handleTransactionReassignToInventory,
          icon: 'inventory',
        });
      }
      reassignSubactions.push({
        key: 'reassign-to-project',
        label: 'Reassign to Project',
        onPress: () => setReassignToProjectVisible(true),
        icon: 'assignment',
      });
      items.push({
        label: 'Reassign',
        icon: 'swap-horiz',
        actionOnly: true,
        info: { title: 'About Reassign', message: 'Use when something was added to the wrong place and you need to move it. No financial records are created, as opposed to the Sell action.' },
        subactions: reassignSubactions,
      });
    }

    items.push({
      label: 'Delete Transaction',
      onPress: handleDelete,
      icon: 'delete',
    });

    return items;
  }, [handleDelete, handleTransactionReassignToInventory, id, isCanonical, projectId, router, scope, transaction?.projectId]);


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
          onAdd={() => setAddMenuVisible(true)}
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
    handlePickReceiptAttachments,
    handleRemoveReceiptAttachment,
    handleSetPrimaryReceiptAttachment,
    handlePickOtherImage,
    handlePickOtherImages,
    handleRemoveOtherImage,
    handleSetPrimaryOtherImage,
  }), [
    handlePickReceiptAttachment,
    handlePickReceiptAttachments,
    handleRemoveReceiptAttachment,
    handleSetPrimaryReceiptAttachment,
    handlePickOtherImage,
    handlePickOtherImages,
    handleRemoveOtherImage,
    handleSetPrimaryOtherImage,
  ]);

  const renderItem = useCallback(({ item, section }: { item: any; section: TransactionSection }) => {
    if (!transaction) return null;

    // Render section headers that were moved into data (so they don't stick)
    // Wrap header + content in View with gap: 12 for proper spacing
    if (item === SECTION_HEADER_MARKER) {
      const collapsed = collapsedSections[section.key] ?? false;

      if (section.key === 'returnedItems' || section.key === 'soldItems') {
        const collapsed = collapsedSections[section.key] ?? true;
        const sectionItems = section.key === 'returnedItems' ? returnedItems : soldItems;

        return (
          <View style={{ gap: 12 }}>
            <CollapsibleSectionHeader
              title={section.title!}
              collapsed={collapsed}
              onToggle={() => handleToggleSection(section.key)}
              badge={section.badge}
            />
            {!collapsed && <MovedItemsSection items={sectionItems} />}
          </View>
        );
      }

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
            {!collapsed && (
              <AuditSection
                transaction={transaction}
                items={linkedItems}
                returnedItems={returnedItems}
                soldItems={soldItems}
                incompleteReturnCount={incompleteReturnItemIds.size}
              />
            )}
          </View>
        );
      }

      // For other sections, wrap header + content together
      const renderSectionContent = () => {
        switch (section.key) {
          case 'receipts':
            return <ReceiptsSection ref={receiptsRef} transaction={transaction} handlers={mediaHandlers} />;
          case 'otherImages':
            return <OtherImagesSection ref={otherImagesRef} transaction={transaction} handlers={mediaHandlers} />;
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
            onEdit={
              !isCanonical && section.key === 'notes' ? () => setEditNotesVisible(true)
              : !isCanonical && section.key === 'details' ? () => setEditDetailsVisible(true)
              : undefined
            }
            onAdd={
              !isCanonical && section.key === 'receipts' ? () => receiptsRef.current?.triggerAdd()
              : !isCanonical && section.key === 'otherImages' ? () => otherImagesRef.current?.triggerAdd()
              : undefined
            }
          />
          {!collapsed && renderSectionContent()}
        </View>
      );
    }

    // Non-header items (hero, items sections that don't use SECTION_HEADER_MARKER pattern)
    switch (section.key) {
      case 'hero':
        return <HeroSection transaction={item} />;

      case 'nextSteps':
        return (
          <NextStepsSection
            transaction={transaction!}
            itemCount={itemsManager.filteredAndSortedItems.length}
            imageCount={(transaction!.otherImages?.length ?? 0)}
            budgetCategories={budgetCategories}
            onScrollToSection={(sectionKey) => {
              // Find the section index and scroll to it
              const idx = sections.findIndex((s) => s.key === sectionKey);
              if (idx >= 0) {
                sectionListRef.current?.scrollToLocation({ sectionIndex: idx, itemIndex: 0, animated: true });
              }
            }}
            onEditDetails={(field) => {
              setEditDetailsFocusField(field);
              setEditDetailsVisible(true);
            }}
            onAddItem={() => setAddMenuVisible(true)}
          />
        );

      case 'items': {
        // Define bulk actions for transaction detail
        const bulkActions: BulkAction[] = [
          { id: 'remove', label: 'Clear Transaction', onPress: (ids) => handleBulkAction('remove', ids) },
          { id: 'set-space', label: 'Set Space', onPress: (ids) => handleBulkAction('set-space', ids) },
          { id: 'clear-space', label: 'Clear Space', onPress: (ids) => handleBulkAction('clear-space', ids) },
          { id: 'set-status', label: 'Set Status', onPress: (ids) => handleBulkAction('set-status', ids) },
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
              getItemWarning={(item) =>
                incompleteReturnItemIds.has(item.id)
                  ? 'This item is marked as returned but not linked to a return transaction.'
                  : undefined
              }
            />
          </View>
        );
      }

      default:
        return null;
    }
  }, [transaction, budgetCategories, mediaHandlers, itemsManager, router, getItemMenuItems, handleBulkAction, accountId, collapsedSections, handleToggleSection, uiKitTheme, linkedItems, itemizationEnabled, returnedItems, soldItems, incompleteReturnItemIds]);

  // Helper to get type label
  const getTypeLabel = () => {
    if (!transactionType) return null;
    switch (transactionType) {
      case 'purchase':
        return 'Purchase';
      case 'sale':
        return 'Sale';
      case 'return':
        return 'Return';
      case 'to-inventory':
        return 'To Inventory';
      default:
        return null;
    }
  };

  // Badge style helpers (mirrors TransactionCard)
  const getTypeBadgeStyle = () => {
    switch (transactionType) {
      case 'purchase':
        return {
          backgroundColor: '#10b98133',
          borderColor: '#10b98166',
          textColor: '#059669',
        };
      case 'sale':
        return {
          backgroundColor: '#3b82f633',
          borderColor: '#3b82f666',
          textColor: '#2563eb',
        };
      case 'return':
        return {
          backgroundColor: '#ef444433',
          borderColor: '#ef444466',
          textColor: '#dc2626',
        };
      case 'to-inventory':
        return {
          backgroundColor: uiKitTheme.primary.main + '1A',
          borderColor: uiKitTheme.primary.main + '33',
          textColor: uiKitTheme.primary.main,
        };
      default:
        return null;
    }
  };

  const categoryBadgeStyle = {
    backgroundColor: uiKitTheme.primary.main + '1A',
    borderColor: uiKitTheme.primary.main + '33',
    textColor: uiKitTheme.primary.main,
  };

  const typeLabel = getTypeLabel();
  const typeBadgeStyle = getTypeBadgeStyle();

  // Render header badges (mirrors TransactionCard headerBadgesRow)
  const hasBadges = typeLabel || needsReview || reimbursementType || hasEmailReceipt || budgetCategoryName;

  const headerActions = hasBadges ? (
    <View style={styles.headerBadgesRow}>
      {typeLabel && typeBadgeStyle ? (
        <View
          style={[
            styles.badge,
            {
              backgroundColor: typeBadgeStyle.backgroundColor,
              borderColor: typeBadgeStyle.borderColor,
            },
          ]}
        >
          <Text style={[styles.badgeText, { color: typeBadgeStyle.textColor }]} numberOfLines={1}>
            {typeLabel}
          </Text>
        </View>
      ) : null}

      {reimbursementType === 'owed-to-client' ? (
        <View
          style={[
            styles.badge,
            {
              backgroundColor: '#f59e0b33',
              borderColor: '#f59e0b66',
            },
          ]}
        >
          <Text style={[styles.badgeText, { color: '#d97706' }]} numberOfLines={1}>
            Owed to Client
          </Text>
        </View>
      ) : null}

      {reimbursementType === 'owed-to-company' ? (
        <View
          style={[
            styles.badge,
            {
              backgroundColor: '#f59e0b33',
              borderColor: '#f59e0b66',
            },
          ]}
        >
          <Text style={[styles.badgeText, { color: '#d97706' }]} numberOfLines={1}>
            Owed to Business
          </Text>
        </View>
      ) : null}

      {hasEmailReceipt ? (
        <View
          style={[
            styles.badge,
            {
              backgroundColor: uiKitTheme.primary.main + '1A',
              borderColor: uiKitTheme.primary.main + '33',
            },
          ]}
        >
          <Text style={[styles.badgeText, { color: uiKitTheme.primary.main }]} numberOfLines={1}>
            Receipt
          </Text>
        </View>
      ) : null}

      {needsReview ? (
        <View
          style={[
            styles.badge,
            {
              backgroundColor: '#b9452014',
              borderColor: '#b9452033',
            },
          ]}
        >
          <Text style={[styles.badgeText, { color: '#b94520' }]} numberOfLines={1}>
            Needs Review
          </Text>
        </View>
      ) : null}

      {budgetCategoryName ? (
        <View
          style={[
            styles.badge,
            {
              backgroundColor: categoryBadgeStyle.backgroundColor,
              borderColor: categoryBadgeStyle.borderColor,
            },
          ]}
        >
          <Text style={[styles.badgeText, { color: categoryBadgeStyle.textColor }]} numberOfLines={1}>
            {budgetCategoryName}
          </Text>
        </View>
      ) : null}
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
      {isLoading ? (
        <View style={styles.loadingContainer}>
          <AppText variant="body">Loading transaction…</AppText>
        </View>
      ) : transaction ? (
        <>
          <SectionList
            ref={sectionListRef}
            style={{ flex: 1 }}
            sections={sections}
            renderSectionHeader={renderSectionHeader}
            renderItem={renderItem}
            stickySectionHeadersEnabled={true}
            keyExtractor={(item, index) => item.id ?? `section-${index}`}
            contentContainerStyle={styles.content}
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
                key: 'transaction',
                label: 'Transaction',
                icon: 'link',
                actionOnly: true,
                subactions: [
                  {
                    key: 'clear-transaction',
                    label: 'Clear Transaction',
                    icon: 'link-off',
                    onPress: () => {
                      setBulkActionsSheetVisible(false);
                      handleBulkAction('remove', []);
                    },
                  },
                  {
                    key: 'move-to-return-transaction',
                    label: 'Move to Return Transaction',
                    icon: 'assignment-return',
                    onPress: () => {
                      setBulkActionsSheetVisible(false);
                      handleBulkAction('move-to-return', []);
                    },
                  },
                ],
              },
              {
                key: 'space',
                label: 'Space',
                icon: 'place',
                actionOnly: true,
                subactions: [
                  {
                    key: 'set-space',
                    label: 'Set Space',
                    icon: 'place',
                    onPress: () => {
                      setBulkActionsSheetVisible(false);
                      handleBulkAction('set-space', []);
                    },
                  },
                  {
                    key: 'clear-space',
                    label: 'Clear Space',
                    icon: 'close',
                    onPress: () => {
                      setBulkActionsSheetVisible(false);
                      handleBulkAction('clear-space', []);
                    },
                  },
                ],
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
                key: 'delete',
                label: 'Delete Items',
                icon: 'delete',
                onPress: () => {
                  setBulkActionsSheetVisible(false);
                  handleBulkAction('delete', []);
                },
              },
            ]}
            title={`Bulk Actions (${itemsManager.selectionCount})`}
            showLeadingIcons={true}
          />

          <BottomSheetMenuList
              visible={menuVisible}
              onRequestClose={() => setMenuVisible(false)}
              items={menuItems}
              title="Transaction Actions"
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
              title="Filter Items"
              showLeadingIcons={false}
            />

            {/* Add existing items picker modal */}
            <BottomSheet
              visible={isPickingItems}
              onRequestClose={() => {
                setIsPickingItems(false);
                pickerManager.clearSelection();
              }}
              containerStyle={styles.pickerSheet}
            >
              <View style={styles.pickerContent}>
                <AppText variant="h2" style={styles.pickerTitle}>Add Existing Items</AppText>
                <View style={styles.pickerTabBar}>
                  {pickerTabOptions.map((tab) => {
                    const count = tab.value === 'suggested'
                      ? suggestedItems.length
                      : tab.value === 'project'
                        ? projectItems.length
                        : outsideItemsHook.items.length;
                    const isActive = pickerTab === tab.value;

                    return (
                      <TouchableOpacity
                        key={tab.value}
                        onPress={() => {
                          setPickerTab(tab.value as ItemPickerTab);
                          pickerManager.clearSelection();
                        }}
                        style={[
                          styles.pickerTab,
                          isActive && { backgroundColor: theme.colors.primary + '20' },
                        ]}
                        accessibilityRole="tab"
                        accessibilityState={{ selected: isActive }}
                      >
                        <AppText
                          variant="body"
                          style={[
                            styles.pickerTabText,
                            isActive && { color: theme.colors.primary },
                          ]}
                        >
                          {tab.label} ({count})
                        </AppText>
                      </TouchableOpacity>
                    );
                  })}
                </View>
                <SharedItemsList
                  embedded={true}
                  picker={true}
                  items={activePickerItems}
                  manager={pickerManagerAdapter}
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
            <SetSpaceModal
              visible={bulkSpacePickerVisible}
              onRequestClose={() => setBulkSpacePickerVisible(false)}
              projectId={projectId ?? null}
              subtitle={`${itemsManager.selectionCount} item${itemsManager.selectionCount === 1 ? '' : 's'} selected`}
              onConfirm={(spaceId) => {
                handleBulkSpaceConfirm(spaceId);
              }}
            />

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

            {/* Single item space picker */}
            <SetSpaceModal
              visible={singleItemSpacePickerVisible}
              onRequestClose={() => setSingleItemSpacePickerVisible(false)}
              projectId={projectId ?? null}
              onConfirm={(spaceId) => {
                if (!accountId || !singleItemOperationId) return;
                updateItem(accountId, singleItemOperationId, { spaceId });
                setSingleItemSpacePickerVisible(false);
                setSingleItemOperationId(null);
              }}
            />

            {/* Reassign transaction to project picker */}
            <ReassignToProjectModal
              visible={reassignToProjectVisible}
              onRequestClose={() => setReassignToProjectVisible(false)}
              accountId={accountId!}
              excludeProjectId={projectId}
              description={`All ${linkedItems.length} item${linkedItems.length === 1 ? '' : 's'} in this transaction will be moved to the selected project.`}
              onConfirm={(tpId) => {
                handleTransactionReassignToProjectConfirm(tpId);
              }}
            />

            {/* Reassign single item to project picker */}
            <ReassignToProjectModal
              visible={singleItemReassignProjectVisible}
              onRequestClose={() => {
                setSingleItemReassignProjectVisible(false);
                setSingleItemReassignId(null);
              }}
              accountId={accountId!}
              excludeProjectId={projectId}
              onConfirm={(tpId) => {
                if (!accountId || !singleItemReassignId) return;
                const item = linkedItems.find((i) => i.id === singleItemReassignId);
                if (!item) return;
                const result = validateItemReassign(item, tpId);
                if (!result.valid) {
                  Alert.alert("Cannot Reassign", result.error, [{ text: "OK" }]);
                  return;
                }
                Alert.alert(
                  "Reassign to Project?",
                  "This item will be moved directly to the selected project.\nNo sale or purchase records will be created.",
                  [
                    { text: "Cancel", style: "cancel" },
                    {
                      text: "Reassign",
                      onPress: () => {
                        reassignItemToProject(accountId, singleItemReassignId, tpId);
                        setSingleItemReassignProjectVisible(false);
                        setSingleItemReassignId(null);
                        showToast('Item reassigned to project');
                      },
                    },
                  ]
                );
              }}
            />

            {/* Sell to Business modal */}
            <SellToBusinessModal
              visible={singleItemSellToBusinessVisible}
              onRequestClose={() => {
                setSingleItemSellToBusinessVisible(false);
                setSingleItemSellId(null);
              }}
              sourceBudgetCategories={budgetCategories}
              showSourceCategoryPicker={(() => {
                const item = linkedItems.find(i => i.id === singleItemSellId);
                return !!item && !item.budgetCategoryId;
              })()}
              onConfirm={(scId) => {
                if (!accountId || !singleItemSellId || !projectId) return;
                const item = linkedItems.find(i => i.id === singleItemSellId);
                if (!item) return;
                const sourceCatId = item.budgetCategoryId ?? scId;
                if (!sourceCatId) return;
                requestProjectToBusinessSale({
                  accountId,
                  projectId,
                  items: [{ ...item, budgetCategoryId: sourceCatId }],
                });
                setSingleItemSellToBusinessVisible(false);
                setSingleItemSellId(null);
                showToast('Item sold to business');
              }}
            />

            {/* Sell to Project modal */}
            <SellToProjectModal
              visible={singleItemSellToProjectVisible}
              onRequestClose={() => {
                setSingleItemSellToProjectVisible(false);
                setSingleItemSellId(null);
              }}
              accountId={accountId!}
              excludeProjectId={projectId}
              destBudgetCategories={sellDestBudgetCategories}
              sourceBudgetCategories={budgetCategories}
              showSourceCategoryPicker={(() => {
                const item = linkedItems.find(i => i.id === singleItemSellId);
                return scope === 'project' && !!item && !item.budgetCategoryId;
              })()}
              showDestCategoryPicker={true}
              onTargetProjectChange={(pid) => setSellTargetProjectId(pid)}
              onConfirm={({ targetProjectId: tpId, destCategoryId: dcId, sourceCategoryId: scId }) => {
                if (!accountId || !tpId || !dcId || !singleItemSellId) return;
                const item = linkedItems.find(i => i.id === singleItemSellId);
                if (!item) return;
                if (scope === 'project' && projectId) {
                  const sourceCatId = item.budgetCategoryId ?? scId;
                  if (!sourceCatId) return;
                  requestProjectToProjectMove({
                    accountId,
                    sourceProjectId: projectId,
                    targetProjectId: tpId,
                    destinationBudgetCategoryId: dcId,
                    items: [{ ...item, budgetCategoryId: sourceCatId }],
                  });
                } else {
                  requestBusinessToProjectPurchase({
                    accountId,
                    targetProjectId: tpId,
                    budgetCategoryId: dcId,
                    items: [item],
                  });
                }
                setSingleItemSellToProjectVisible(false);
                setSingleItemSellId(null);
                showToast('Item sold to project');
              }}
            />

            {/* Return Transaction Picker modal */}
            <ReturnTransactionPickerModal
              visible={returnPicker.visible}
              onRequestClose={returnPicker.close}
              accountId={accountId!}
              scopeConfig={scopeConfig!}
              onConfirm={returnPicker.handleConfirm}
              onCreateNew={returnPicker.handleCreateNew}
              subtitle={returnPicker.subtitle}
            />

            {/* Edit Notes Modal */}
            {transaction && (
              <EditNotesModal
                visible={editNotesVisible}
                onRequestClose={() => setEditNotesVisible(false)}
                initialNotes={transaction.notes ?? ''}
                onSave={handleSaveNotes}
              />
            )}

            {/* Edit Transaction Details Modal */}
            {transaction && (
              <EditTransactionDetailsModal
                visible={editDetailsVisible}
                onRequestClose={() => {
                  setEditDetailsVisible(false);
                  setEditDetailsFocusField(undefined);
                }}
                transaction={transaction}
                budgetCategories={budgetCategories}
                itemizationEnabled={itemizationEnabled}
                onSave={handleSaveTransactionDetails}
                accountId={accountId!}
                focusField={editDetailsFocusField}
              />
            )}

            {/* Create Items from List Modal */}
            <CreateItemsFromListModal
              visible={listImportVisible}
              onRequestClose={() => setListImportVisible(false)}
              onCreateItems={handleCreateItemsFromList}
            />
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
  headerBadgesRow: {
    flexDirection: 'row',
    gap: 8,
    alignItems: 'center',
  },
  badge: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 999,
    borderWidth: 1,
    maxWidth: 160,
  },
  badgeText: {
    fontSize: 12,
    fontWeight: '600',
    includeFontPadding: false,
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
  pickerTabBar: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingVertical: 8,
    gap: 12,
  },
  pickerTab: {
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: 8,
  },
  pickerTabActive: {
    // Will be computed with theme.colors.primary + '20'
  },
  pickerTabText: {
    // Color will be set inline based on active state
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
