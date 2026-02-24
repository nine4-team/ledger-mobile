import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, SectionList, StyleSheet, TouchableOpacity, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { AppText } from './AppText';
import { ItemsListControlBar } from './ItemsListControlBar';
import { ItemCard } from './ItemCard';
import { MediaGallerySection, type MediaGallerySectionRef } from './MediaGallerySection';
import { BottomSheet } from './BottomSheet';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import { NotesSection } from './NotesSection';
import { CollapsibleSectionHeader } from './CollapsibleSectionHeader';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { SetSpaceModal } from './modals/SetSpaceModal';
import { ReassignToProjectModal } from './modals/ReassignToProjectModal';
import { SellToProjectModal } from './modals/SellToProjectModal';
import { SellToBusinessModal } from './modals/SellToBusinessModal';
import { TransactionPickerModal } from './modals/TransactionPickerModal';
import { ReturnTransactionPickerModal } from './modals/ReturnTransactionPickerModal';
import { EditNotesModal } from './modals/EditNotesModal';
import { EditSpaceDetailsModal } from './modals/EditSpaceDetailsModal';
import { EditChecklistModal } from './modals/EditChecklistModal';
import { buildSingleItemMenu, buildBulkMenu } from '../actions/itemMenuBuilder';
import { executeSellToBusiness, executeSellToProject, executeBulkReassignToInventory, executeBulkReassignToProject } from '../actions/itemActionHandlers';
import { layout } from '../ui';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { useAccountContextStore } from '../auth/accountContextStore';
import { useAuthStore } from '../auth/authStore';
import { subscribeToSpace, Space, updateSpace, deleteSpace, Checklist } from '../data/spacesService';
import { createSpaceTemplate } from '../data/spaceTemplatesService';
import { createInventoryScopeConfig, createProjectScopeConfig, getScopeId } from '../data/scopeConfig';
import { useScopeSwitching } from '../data/useScopeSwitching';
import { useScopedListeners } from '../data/useScopedListeners';
import { subscribeToScopedItems, ScopedItem } from '../data/scopedListData';
import { updateItem, deleteItem } from '../data/itemsService';
import { reassignItemToInventory, reassignItemToProject } from '../data/reassignService';
import { subscribeToBudgetCategories, mapBudgetCategories } from '../data/budgetCategoriesService';
import { createRepository } from '../data/repository';
import { deleteLocalMediaByUrl, saveLocalMedia, resolveAttachmentUri } from '../offline/media';
import type { AttachmentRef } from '../offline/media';
import { useOutsideItems } from '../hooks/useOutsideItems';
import { useOptionalIsFocused } from '../hooks/useOptionalIsFocused';
import { resolveItemMove } from '../data/resolveItemMove';
import { useItemsManager } from '../hooks/useItemsManager';
import { useReturnTransactionPicker } from '../hooks/useReturnTransactionPicker';
import { SharedItemsList } from './SharedItemsList';
import { BulkSelectionBar } from './BulkSelectionBar';
import { SelectorCircle } from './SelectorCircle';
import { showToast } from './toastStore';

// --- Types ---

export type SpaceScope = {
  projectId: string | null; // null = business inventory
  spaceId: string;
};

export type SpaceDetailContentProps = {
  scope: SpaceScope;
  onSpaceNameChange: (name: string) => void;
  spaceMenuVisible: boolean;
  onCloseSpaceMenu: () => void;
};

type ItemPickerTab = 'current' | 'outside';

type SpaceSectionKey = 'media' | 'notes' | 'items' | 'checklists';

type SpaceSection = {
  key: SpaceSectionKey;
  title: string;
  data: any[];
  badge?: string;
};

const SECTION_HEADER_MARKER = '__sectionHeader__';

// --- Helpers ---

function getPrimaryImageUri(item: ScopedItem): string | undefined {
  const images = (item as any).images as AttachmentRef[] | undefined;
  if (!images || images.length === 0) return undefined;
  const primary = images.find((img) => img.isPrimary) ?? images[0];
  return resolveAttachmentUri(primary) ?? primary.url;
}

function formatCents(value?: number | null): string | undefined {
  if (typeof value !== 'number') return undefined;
  return `$${(value / 100).toFixed(2)}`;
}

function getDisplayPrice(item: ScopedItem): string | undefined {
  const projectPrice = (item as any).projectPriceCents as number | undefined;
  const purchasePrice = (item as any).purchasePriceCents as number | undefined;
  if (typeof projectPrice === 'number') return formatCents(projectPrice);
  if (typeof purchasePrice === 'number') return formatCents(purchasePrice);
  return undefined;
}

// --- Route helpers ---

function getDeleteTarget(projectId: string | null): string {
  return projectId
    ? `/project/${projectId}?tab=spaces`
    : '/business-inventory/spaces';
}

function getSpaceBackTarget(projectId: string | null, spaceId: string): string {
  return projectId
    ? `/project/${projectId}/spaces/${spaceId}`
    : `/business-inventory/spaces/${spaceId}`;
}

function getItemDetailParams(
  projectId: string | null,
  spaceId: string,
  itemId: string,
): { pathname: string; params: Record<string, string> } {
  return {
    pathname: '/items/[id]',
    params: {
      id: itemId,
      scope: projectId ? 'project' : 'inventory',
      ...(projectId ? { projectId } : {}),
      backTarget: getSpaceBackTarget(projectId, spaceId),
    },
  };
}

// --- Component ---

export function SpaceDetailContent({
  scope,
  onSpaceNameChange,
  spaceMenuVisible,
  onCloseSpaceMenu,
}: SpaceDetailContentProps) {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const userId = useAuthStore((store) => store.user?.uid ?? null);
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const { projectId, spaceId } = scope;

  const [space, setSpace] = useState<Space | null>(null);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [checklists, setChecklists] = useState<Checklist[]>([]);
  const [isPickingItems, setIsPickingItems] = useState(false);
  const [pickerTab, setPickerTab] = useState<ItemPickerTab>('current');

  const [addMenuVisible, setAddMenuVisible] = useState(false);
  const [bulkActionsSheetVisible, setBulkActionsSheetVisible] = useState(false);

  const outsideItemsHook = useOutsideItems({
    accountId,
    currentProjectId: projectId ?? null,
    scope: projectId ? 'project' : 'inventory',
    includeInventory: projectId ? true : false,
  });
  const [bulkMoveSheetVisible, setBulkMoveSheetVisible] = useState(false);
  const [canSaveTemplate, setCanSaveTemplate] = useState(false);

  // Sell/Reassign modal state
  const [sellToBusinessVisible, setSellToBusinessVisible] = useState(false);
  const [sellToProjectVisible, setSellToProjectVisible] = useState(false);
  const [reassignToProjectVisible, setReassignToProjectVisible] = useState(false);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string }>>({});
  // Status picker state
  const [bulkStatusPickerVisible, setBulkStatusPickerVisible] = useState(false);

  const mediaRef = useRef<MediaGallerySectionRef>(null);
  const pendingMediaAdd = useRef(false);

  // Single-item modal state
  const [singleItemId, setSingleItemId] = useState<string | null>(null);
  const [singleItemSpacePickerVisible, setSingleItemSpacePickerVisible] = useState(false);
  const [singleItemTransactionPickerVisible, setSingleItemTransactionPickerVisible] = useState(false);
  const [singleItemSellToBusinessVisible, setSingleItemSellToBusinessVisible] = useState(false);
  const [singleItemSellToProjectVisible, setSingleItemSellToProjectVisible] = useState(false);
  const [singleItemReassignToProjectVisible, setSingleItemReassignToProjectVisible] = useState(false);

  // Bulk transaction picker state
  const [bulkTransactionPickerVisible, setBulkTransactionPickerVisible] = useState(false);

  const [editNameVisible, setEditNameVisible] = useState(false);
  const [editNotesVisible, setEditNotesVisible] = useState(false);

  // Checklist modal state
  const [checklistModalVisible, setChecklistModalVisible] = useState(false);
  const [checklistModalTarget, setChecklistModalTarget] = useState<Checklist | null>(null);
  const [checklistMenuId, setChecklistMenuId] = useState<string | null>(null);

  // Collapsible sections state
  const [collapsedSections, setCollapsedSections] = useState<Record<SpaceSectionKey, boolean>>({
    media: false,       // Default EXPANDED — users want to see images
    notes: true,        // Default collapsed
    items: true,        // Default collapsed (per FR-011)
    checklists: true,   // Default collapsed
  });

  const handleToggleSection = useCallback((key: SpaceSectionKey) => {
    setCollapsedSections(prev => ({ ...prev, [key]: !prev[key] }));
  }, []);

  // Fire deferred triggerAdd once media section is expanded
  useEffect(() => {
    if (!collapsedSections.media && pendingMediaAdd.current) {
      pendingMediaAdd.current = false;
      mediaRef.current?.triggerAdd();
    }
  }, [collapsedSections.media]);

  const handleSaveSpaceName = useCallback((name: string) => {
    if (!accountId || !spaceId) return;
    updateSpace(accountId, spaceId, { name });
    setEditNameVisible(false);
    showToast('Space name updated');
  }, [accountId, spaceId]);

  const handleSaveNotes = useCallback((notes: string) => {
    if (!accountId || !spaceId) return;
    updateSpace(accountId, spaceId, { notes });
    setEditNotesVisible(false);
    showToast('Notes updated');
  }, [accountId, spaceId]);

  const isFocused = useOptionalIsFocused(true);
  const scopeConfig = useMemo(
    () => projectId
      ? createProjectScopeConfig(projectId)
      : createInventoryScopeConfig(),
    [projectId],
  );
  const scopeId = useMemo(() => getScopeId(scopeConfig), [scopeConfig]);
  useScopeSwitching(scopeConfig, { isActive: isFocused });

  // Subscribe to space
  useEffect(() => {
    if (!accountId || !spaceId) {
      setSpace(null);
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    const unsubscribe = subscribeToSpace(accountId, spaceId, (next) => {
      setSpace(next);
      setChecklists(next?.checklists ?? []);
      onSpaceNameChange(next?.name?.trim() || 'Space');
      setIsLoading(false);
    });
    return () => unsubscribe();
  }, [accountId, spaceId, onSpaceNameChange]);

  // Check admin role for template saving
  useEffect(() => {
    if (!accountId || !userId) {
      setCanSaveTemplate(false);
      return;
    }
    const repo = createRepository<{ id: string; role?: string }>(`accounts/${accountId}/users`, 'offline');
    return repo.subscribe(userId, (member) => {
      const role = member?.role ?? '';
      setCanSaveTemplate(role === 'owner' || role === 'admin');
    });
  }, [accountId, userId]);

  // Subscribe to budget categories (account-level, shared by sell modals)
  useEffect(() => {
    if (!accountId) return;
    const unsub = subscribeToBudgetCategories(accountId, (cats) => {
      setBudgetCategories(mapBudgetCategories(cats));
    });
    return unsub;
  }, [accountId]);

  // Subscribe to items
  const handleItemsSubscribe = useCallback(() => {
    if (!accountId || !scopeConfig) {
      setItems([]);
      return () => {};
    }
    return subscribeToScopedItems(accountId, scopeConfig, (next) => {
      setItems(next);
    });
  }, [accountId, scopeConfig]);

  useScopedListeners(scopeId, handleItemsSubscribe);

  const spaceItems = useMemo(() => items.filter((item) => item.spaceId === spaceId), [items, spaceId]);
  const availableItems = useMemo(() => items.filter((item) => item.spaceId !== spaceId), [items, spaceId]);

  // Initialize items manager
  const itemsManager = useItemsManager({
    items: spaceItems,
    defaultSort: 'created-desc',
    defaultFilter: 'all',
    sortModes: ['created-desc', 'created-asc', 'alphabetical-asc', 'alphabetical-desc'],
    filterModes: ['all', 'bookmarked', 'no-sku', 'no-image'],
    filterFn: (item, mode) => {
      switch (mode) {
        case 'bookmarked': return Boolean((item as any).bookmark);
        case 'no-sku': return !(item as any).sku?.trim();
        case 'no-image': return !((item as any).images?.length > 0);
        default: return true;
      }
    },
  });

  const returnPicker = useReturnTransactionPicker({
    accountId,
    scopeConfig: scopeConfig ?? null,
    getItemTransactionId: (itemId) =>
      itemsManager.filteredAndSortedItems.find(i => i.id === itemId)?.transactionId ?? null,
    projectId: projectId ?? null,
    onComplete: () => itemsManager.clearSelection(),
  });

  // Compute sections array for SectionList
  const sections: SpaceSection[] = useMemo(() => {
    const result: SpaceSection[] = [];

    // Media section (non-sticky header)
    const mediaCollapsed = collapsedSections.media;
    result.push({
      key: 'media',
      title: 'IMAGES',
      data: mediaCollapsed ? [SECTION_HEADER_MARKER] : [SECTION_HEADER_MARKER, 'media-content'],
    });

    // Notes section (non-sticky header)
    const notesCollapsed = collapsedSections.notes;
    result.push({
      key: 'notes',
      title: 'NOTES',
      data: notesCollapsed ? [SECTION_HEADER_MARKER] : [SECTION_HEADER_MARKER, 'notes-content'],
    });

    // Items section (STICKY header — uses renderSectionHeader)
    const itemsCollapsed = collapsedSections.items;
    const itemCount = itemsManager.filteredAndSortedItems.length;
    result.push({
      key: 'items',
      title: 'ITEMS',
      data: itemsCollapsed ? [] : ['items-content'],
      badge: itemCount > 0 ? String(itemCount) : undefined,
    });

    // Checklists section (non-sticky header)
    const checklistsCollapsed = collapsedSections.checklists;
    result.push({
      key: 'checklists',
      title: 'CHECKLISTS',
      data: checklistsCollapsed ? [SECTION_HEADER_MARKER] : [SECTION_HEADER_MARKER, 'checklists-content'],
    });

    return result;
  }, [collapsedSections, itemsManager.filteredAndSortedItems]);

  const activePickerItems = pickerTab === 'outside' ? outsideItemsHook.items : availableItems;

  // Initialize picker manager
  const pickerManager = useItemsManager({
    items: activePickerItems,
    defaultSort: 'created-desc',
    defaultFilter: 'all',
    sortModes: ['created-desc'],
    filterModes: ['all'],
  });

  // Create adapter for picker manager to match SharedItemsList's expected interface
  const pickerManagerAdapter = useMemo(() => ({
    ...pickerManager,
    selectedIds: Array.from(pickerManager.selectedIds), // Convert Set to Array for usePickerMode
    setItemSelected: (id: string, selected: boolean) => {
      const isCurrentlySelected = pickerManager.selectedIds.has(id);
      if (selected !== isCurrentlySelected) {
        pickerManager.toggleSelection(id);
      }
    },
    setGroupSelection: (ids: string[], selected: boolean) => {
      ids.forEach((id) => {
        const isCurrentlySelected = pickerManager.selectedIds.has(id);
        if (selected !== isCurrentlySelected) {
          pickerManager.toggleSelection(id);
        }
      });
    },
  }), [pickerManager]);

  useEffect(() => {
    if (!isPickingItems) return;
    void outsideItemsHook.reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- reload is a stable useCallback ref; depending on the full hook object causes a reload loop
  }, [isPickingItems, outsideItemsHook.reload]);

  // --- Handlers ---

  const handleSaveChecklists = useCallback(
    (next: Checklist[]) => {
      if (!accountId || !spaceId) return;
      setChecklists(next);
      updateSpace(accountId, spaceId, { checklists: next });
    },
    [accountId, spaceId],
  );

  const handleAddImage = useCallback(async (localUri: string, kind: 'image' | 'pdf' | 'file' = 'image') => {
    if (!accountId || !spaceId || !space) return;
    const mimeType = kind === 'pdf' ? 'application/pdf' : 'image/jpeg';
    const result = await saveLocalMedia({
      localUri,
      mimeType,
      ownerScope: `space:${spaceId}`,
      persistCopy: false,
    });
    const hasPrimary = (space.images ?? []).some((image) => image.isPrimary);
    const newImage: AttachmentRef = {
      url: result.attachmentRef.url,
      kind,
      isPrimary: !hasPrimary && kind === 'image',
    };
    const nextImages = [...(space.images ?? []), newImage].slice(0, 50);
    updateSpace(accountId, spaceId, { images: nextImages });
  }, [accountId, space, spaceId]);

  const handleAddImages = useCallback(async (localUris: string[], kind: 'image' | 'pdf' | 'file' = 'image') => {
    if (!accountId || !spaceId || !space) return;
    const mimeType = kind === 'pdf' ? 'application/pdf' : 'image/jpeg';
    let currentImages = space.images ?? [];

    for (const uri of localUris) {
      if (currentImages.length >= 100) break;

      const result = await saveLocalMedia({
        localUri: uri,
        mimeType,
        ownerScope: `space:${spaceId}`,
        persistCopy: false,
      });
      const hasPrimary = currentImages.some((image) => image.isPrimary);
      const newImage: AttachmentRef = {
        url: result.attachmentRef.url,
        kind,
        isPrimary: !hasPrimary && kind === 'image',
      };
      currentImages = [...currentImages, newImage];

      updateSpace(accountId, spaceId, { images: currentImages });
    }
  }, [accountId, space, spaceId]);

  const handleRemoveImage = useCallback(
    async (image: AttachmentRef) => {
      if (!accountId || !spaceId || !space) return;
      const nextImages = (space.images ?? []).filter((img) => img.url !== image.url);
      if (image.url.startsWith('offline://')) {
        await deleteLocalMediaByUrl(image.url);
      }
      if (!nextImages.some((img) => img.isPrimary) && nextImages.length > 0) {
        nextImages[0] = { ...nextImages[0], isPrimary: true };
      }
      updateSpace(accountId, spaceId, { images: nextImages });
    },
    [accountId, space, spaceId],
  );

  const handleSetPrimaryImage = useCallback(
    (image: AttachmentRef) => {
      if (!accountId || !spaceId) return;
      const nextImages = (space?.images ?? []).map((img) => ({
        ...img,
        isPrimary: img.url === image.url,
      }));
      updateSpace(accountId, spaceId, { images: nextImages });
    },
    [accountId, space?.images, spaceId],
  );

  const handleAddSelectedItems = useCallback(() => {
    if (!accountId || pickerManager.selectedIds.size === 0) return;
    const selectedItems = activePickerItems.filter((item) => pickerManager.selectedIds.has(item.id));

    if (pickerTab !== 'outside') {
      selectedItems.forEach((item) => {
        updateItem(accountId, item.id, { spaceId });
      });
      pickerManager.clearSelection();
      setIsPickingItems(false);
      return;
    }

    const missingCategory = selectedItems.filter((item) => !item.budgetCategoryId);
    if (missingCategory.length > 0) {
      Alert.alert(
        'Missing category',
        'Some items are missing a budget category and cannot be moved. Update them first and try again.',
      );
      return;
    }

    selectedItems.forEach((item) => {
      if (item.transactionId) return;
      const result = resolveItemMove(item, {
        accountId,
        itemId: item.id,
        targetProjectId: projectId ?? null,
        targetSpaceId: spaceId,
        budgetCategoryId: item.budgetCategoryId ?? null,
      });
      if (!result.success) {
        console.warn(`[items] move failed for ${item.id}: ${result.error}`);
      }
    });
    pickerManager.clearSelection();
    setIsPickingItems(false);
  }, [accountId, activePickerItems, pickerManager, pickerTab, projectId, spaceId]);

  const handleAddSingleItem = useCallback((item: ScopedItem | { id: string; transactionId?: string | null; budgetCategoryId?: string | null; [key: string]: any }) => {
    if (!accountId) return;
    const isOutside = pickerTab === 'outside';
    if (!isOutside) {
      updateItem(accountId, item.id, { spaceId });
    } else {
      if (item.transactionId) return;
      const result = resolveItemMove(item as any, {
        accountId,
        itemId: item.id,
        targetProjectId: (projectId ?? null) as any,
        targetSpaceId: spaceId,
        budgetCategoryId: item.budgetCategoryId ?? null,
      });
      if (!result.success) {
        console.warn(`[items] move failed for ${item.id}: ${result.error}`);
      }
    }
  }, [accountId, pickerTab, projectId, spaceId]);

  const spaceItemIds = useMemo(() => new Set(spaceItems.map((item) => item.id)), [spaceItems]);

  // Bulk status handler
  const handleBulkStatusConfirm = useCallback((status: string) => {
    if (!accountId) return;
    const selectedIds = itemsManager.selectedIds;
    const count = selectedIds.size;
    selectedIds.forEach((itemId) => {
      updateItem(accountId, itemId, { status });
    });
    setBulkStatusPickerVisible(false);
    showToast(`Status updated for ${count} item${count === 1 ? '' : 's'}`);
    if (status === 'returned') {
      returnPicker.openForItems(Array.from(selectedIds));
    } else {
      itemsManager.clearSelection();
    }
  }, [accountId, itemsManager, returnPicker]);

  const handleBulkClearTransaction = useCallback(() => {
    if (!accountId) return;
    const ids = Array.from(itemsManager.selectedIds);
    ids.forEach(id => updateItem(accountId, id, { transactionId: null }));
    itemsManager.clearSelection();
    showToast(`Transaction unlinked from ${ids.length} item${ids.length === 1 ? '' : 's'}`);
  }, [accountId, itemsManager]);

  const handleBulkRemoveFromSpace = useCallback(() => {
    if (!accountId) return;
    const ids = Array.from(itemsManager.selectedIds);
    Alert.alert(
      'Remove Items',
      `Remove ${ids.length} item${ids.length === 1 ? '' : 's'} from this space?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Remove',
          style: 'destructive',
          onPress: () => {
            ids.forEach(id => updateItem(accountId, id, { spaceId: null }));
            itemsManager.clearSelection();
            showToast(`${ids.length} item${ids.length === 1 ? '' : 's'} removed from space`);
          },
        },
      ]
    );
  }, [accountId, itemsManager]);

  const handleBulkReassignToInventory = useCallback(() => {
    if (!accountId) return;
    const ids = Array.from(itemsManager.selectedIds);
    const selected = itemsManager.filteredAndSortedItems.filter(i => ids.includes(i.id));
    const result = executeBulkReassignToInventory({ accountId, items: selected });
    if (result.blocked > 0) {
      Alert.alert(
        'Reassign to Inventory',
        `${result.executed} item${result.executed === 1 ? '' : 's'} reassigned. ${result.blocked} item${result.blocked === 1 ? '' : 's'} linked to transactions were skipped.`,
      );
    } else {
      showToast(`${result.executed} item${result.executed === 1 ? '' : 's'} reassigned to inventory`);
    }
    itemsManager.clearSelection();
  }, [accountId, itemsManager]);

  const handleBulkDelete = useCallback(() => {
    if (!accountId) return;
    const ids = Array.from(itemsManager.selectedIds);
    Alert.alert(
      'Delete Items',
      `Permanently delete ${ids.length} item${ids.length === 1 ? '' : 's'}? This cannot be undone.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            ids.forEach(id => deleteItem(accountId, id));
            itemsManager.clearSelection();
            showToast(`${ids.length} item${ids.length === 1 ? '' : 's'} deleted`);
          },
        },
      ]
    );
  }, [accountId, itemsManager]);

  const handleDelete = useCallback(() => {
    if (!accountId || !spaceId) return;
    const itemCount = spaceItems.length;
    const message = itemCount > 0
      ? `This space has ${itemCount} item${itemCount === 1 ? '' : 's'}. Items will not be deleted, but their space assignment will be cleared.`
      : 'Are you sure you want to delete this space?';
    Alert.alert('Delete space', message, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          deleteSpace(accountId, spaceId);
          router.replace(getDeleteTarget(projectId));
        },
      },
    ]);
  }, [accountId, projectId, router, spaceId, spaceItems.length]);

  const handleSaveTemplate = useCallback(() => {
    if (!accountId || !space) return;
    createSpaceTemplate(accountId, {
      name: space.name?.trim() || 'Untitled space',
      notes: space.notes ?? null,
      checklists: space.checklists ?? null,
    });
    Alert.alert('Success', 'Space saved as template successfully');
  }, [accountId, space]);

  const handleCreateItemInSpace = useCallback(() => {
    router.push({
      pathname: '/items/new',
      params: {
        scope: projectId ? 'project' : 'inventory',
        ...(projectId ? { projectId } : {}),
        spaceId,
        backTarget: getSpaceBackTarget(projectId, spaceId),
      },
    });
  }, [projectId, router, spaceId]);

  // --- Menu items ---

  const pickerTabLabel = projectId ? 'Project' : 'In Business Inventory';

  const spaceMenuItems: AnchoredMenuItem[] = useMemo(() => {
    const menuItems: AnchoredMenuItem[] = [
      {
        key: 'edit',
        label: 'Edit Name',
        icon: 'edit',
        onPress: () => { onCloseSpaceMenu(); setEditNameVisible(true); },
      },
    ];
    if (canSaveTemplate) {
      menuItems.push({
        key: 'save-template',
        label: 'Save as Template',
        icon: 'save',
        onPress: handleSaveTemplate,
      });
    }
    menuItems.push({
      key: 'delete',
      label: 'Delete',
      icon: 'delete',
      destructive: true,
      onPress: handleDelete,
    });
    return menuItems;
  }, [canSaveTemplate, handleDelete, handleSaveTemplate, projectId, router, spaceId]);

  const sortMenuItems: AnchoredMenuItem[] = useMemo(() => [
    {
      label: 'Sort by',
      subactions: [
        { key: 'created-desc', label: 'Newest First', onPress: () => { itemsManager.setSortMode('created-desc'); itemsManager.setSortMenuVisible(false); } },
        { key: 'created-asc', label: 'Oldest First', onPress: () => { itemsManager.setSortMode('created-asc'); itemsManager.setSortMenuVisible(false); } },
        { key: 'alphabetical-asc', label: 'A \u2192 Z', onPress: () => { itemsManager.setSortMode('alphabetical-asc'); itemsManager.setSortMenuVisible(false); } },
        { key: 'alphabetical-desc', label: 'Z \u2192 A', onPress: () => { itemsManager.setSortMode('alphabetical-desc'); itemsManager.setSortMenuVisible(false); } },
      ],
      selectedSubactionKey: itemsManager.sortMode,
    },
  ], [itemsManager]);

  const filterMenuItems: AnchoredMenuItem[] = useMemo(() => [
    { key: 'all', label: 'All', onPress: () => { itemsManager.setFilterMode('all'); itemsManager.setFilterMenuVisible(false); }, icon: itemsManager.filterMode === 'all' ? 'check' as const : undefined },
    { key: 'bookmarked', label: 'Bookmarked', onPress: () => { itemsManager.setFilterMode('bookmarked'); itemsManager.setFilterMenuVisible(false); }, icon: itemsManager.filterMode === 'bookmarked' ? 'check' as const : undefined },
    { key: 'no-sku', label: 'No SKU', onPress: () => { itemsManager.setFilterMode('no-sku'); itemsManager.setFilterMenuVisible(false); }, icon: itemsManager.filterMode === 'no-sku' ? 'check' as const : undefined },
    { key: 'no-image', label: 'No Image', onPress: () => { itemsManager.setFilterMode('no-image'); itemsManager.setFilterMenuVisible(false); }, icon: itemsManager.filterMode === 'no-image' ? 'check' as const : undefined },
  ], [itemsManager]);

  const addMenuItems: AnchoredMenuItem[] = useMemo(() => [
    {
      key: 'create',
      label: 'Create Item Manually',
      icon: 'add' as const,
      onPress: handleCreateItemInSpace,
    },
    {
      key: 'add-existing',
      label: 'Add Existing Item',
      icon: 'playlist-add' as const,
      onPress: () => {
        setIsPickingItems(true);
        setPickerTab('current');
        pickerManager.clearSelection();
      },
    },
  ], [handleCreateItemInSpace, pickerManager]);

  // Bulk actions for space detail items (single definition used by both SharedItemsList and BulkSelectionBar sheet)
  const bulkActions = useMemo(() => [
    {
      id: 'move',
      label: 'Move to Another Space',
      onPress: (_selectedIds: string[]) => {
        setBulkMoveSheetVisible(true);
      },
    },
    {
      id: 'remove',
      label: 'Remove from Space',
      onPress: (selectedIds: string[]) => {
        if (!accountId) return;
        Alert.alert(
          'Remove Items',
          `Remove ${selectedIds.length} item${selectedIds.length === 1 ? '' : 's'} from this space?`,
          [
            { text: 'Cancel', style: 'cancel' },
            {
              text: 'Remove',
              style: 'destructive',
              onPress: () => {
                selectedIds.forEach(id => {
                  updateItem(accountId, id, { spaceId: null });
                });
                itemsManager.clearSelection();
              },
            },
          ]
        );
      },
      destructive: true,
    },
    {
      id: 'set-status',
      label: 'Set Status',
      onPress: (_selectedIds: string[]) => {
        setBulkStatusPickerVisible(true);
      },
    },
    ...(scopeConfig?.scope === 'project' ? [{
      id: 'sell-to-business',
      label: 'Sell to Business',
      onPress: (_selectedIds: string[]) => {
        setSellToBusinessVisible(true);
      },
    }] : []),
    {
      id: 'sell-to-project',
      label: 'Sell to Project',
      onPress: (_selectedIds: string[]) => {
        setSellToProjectVisible(true);
      },
    },
    ...(scopeConfig?.scope === 'project' ? [{
      id: 'reassign-to-inventory',
      label: 'Reassign to Inventory',
      onPress: (selectedIds: string[]) => {
        if (!accountId) return;
        const selected = itemsManager.filteredAndSortedItems.filter(i => selectedIds.includes(i.id));
        const eligible = selected.filter(i => !i.transactionId);
        const blocked = selected.length - eligible.length;
        const msg = blocked > 0
          ? `${eligible.length} item${eligible.length === 1 ? '' : 's'} will be reassigned to inventory. ${blocked} item${blocked === 1 ? '' : 's'} linked to transactions will be skipped.`
          : `Reassign ${eligible.length} item${eligible.length === 1 ? '' : 's'} to business inventory? No sale or purchase records will be created.`;
        Alert.alert('Reassign to Inventory', msg, [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Reassign',
            onPress: () => {
              eligible.forEach(item => {
                reassignItemToInventory(accountId, item.id);
              });
              itemsManager.clearSelection();
              showToast(`${eligible.length} item${eligible.length === 1 ? '' : 's'} reassigned to inventory`);
            },
          },
        ]);
      },
    }] : []),
    {
      id: 'reassign-to-project',
      label: 'Reassign to Project',
      onPress: (_selectedIds: string[]) => {
        setReassignToProjectVisible(true);
      },
    },
    {
      id: 'delete',
      label: 'Delete Items',
      onPress: (selectedIds: string[]) => {
        if (!accountId) return;
        Alert.alert(
          'Delete Items',
          `Permanently delete ${selectedIds.length} item${selectedIds.length === 1 ? '' : 's'}? This cannot be undone.`,
          [
            { text: 'Cancel', style: 'cancel' },
            {
              text: 'Delete',
              style: 'destructive',
              onPress: () => {
                selectedIds.forEach(id => {
                  deleteItem(accountId, id);
                });
                itemsManager.clearSelection();
              },
            },
          ]
        );
      },
      destructive: true,
    },
  ], [accountId, itemsManager, scopeConfig]);

  // Bulk menu items for BottomSheetMenuList (with icons and submenus)
  const bulkMenuItems = useMemo<AnchoredMenuItem[]>(() => {
    if (!scopeConfig) return [];
    return buildBulkMenu({
      context: 'space',
      scopeConfig,
      callbacks: {
        onStatusChange: (status) => { setBulkActionsSheetVisible(false); handleBulkStatusConfirm(status); },
        onSetTransaction: () => { setBulkActionsSheetVisible(false); setBulkTransactionPickerVisible(true); },
        onClearTransaction: () => { setBulkActionsSheetVisible(false); handleBulkClearTransaction(); },
        onSetSpace: () => { setBulkActionsSheetVisible(false); setBulkMoveSheetVisible(true); },
        onClearSpace: () => { setBulkActionsSheetVisible(false); handleBulkRemoveFromSpace(); },
        onSellToBusiness: scopeConfig.scope === 'project' ? () => { setBulkActionsSheetVisible(false); setSellToBusinessVisible(true); } : undefined,
        onSellToProject: () => { setBulkActionsSheetVisible(false); setSellToProjectVisible(true); },
        onReassignToInventory: scopeConfig.scope === 'project' ? () => { setBulkActionsSheetVisible(false); handleBulkReassignToInventory(); } : undefined,
        onReassignToProject: () => { setBulkActionsSheetVisible(false); setReassignToProjectVisible(true); },
        onMoveToReturnTransaction: () => { setBulkActionsSheetVisible(false); returnPicker.openForItems(Array.from(itemsManager.selectedIds)); },
        onDelete: () => { setBulkActionsSheetVisible(false); handleBulkDelete(); },
      },
    });
  }, [scopeConfig, handleBulkStatusConfirm, handleBulkClearTransaction, handleBulkRemoveFromSpace, handleBulkReassignToInventory, handleBulkDelete, returnPicker, itemsManager]);

  // --- SectionList render callbacks ---

  const renderSectionHeader = useCallback(({ section }: { section: SpaceSection }) => {
    // Only items section gets a real (sticky) section header
    if (section.key !== 'items') return null;

    const collapsed = collapsedSections.items;

    return (
      <View style={{ backgroundColor: theme.colors.background }}>
        <CollapsibleSectionHeader
          title={section.title}
          collapsed={collapsed}
          onToggle={() => handleToggleSection('items')}
          badge={section.badge}
          onAdd={() => setAddMenuVisible(true)}
        />
        {!collapsed && (
          <View style={{
            paddingBottom: 12,
            borderBottomWidth: 1,
            borderBottomColor: uiKitTheme.border.secondary,
          }}>
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
  }, [collapsedSections, handleToggleSection, itemsManager,
      theme.colors.background, uiKitTheme.border.secondary, uiKitTheme.button.secondary.background,
      uiKitTheme.border.primary, setBulkActionsSheetVisible, setAddMenuVisible]);

  const renderItem = useCallback(({ item, section }: { item: any; section: SpaceSection }) => {
    // Handle section header markers (non-sticky sections)
    if (item === SECTION_HEADER_MARKER) {
      return (
        <CollapsibleSectionHeader
          title={section.title}
          collapsed={collapsedSections[section.key] ?? false}
          onToggle={() => handleToggleSection(section.key)}
          badge={section.badge}
          onEdit={section.key === 'notes' ? () => setEditNotesVisible(true) : undefined}
          onAdd={
            section.key === 'media' ? () => {
              if (collapsedSections.media) {
                pendingMediaAdd.current = true;
                handleToggleSection('media');
              } else {
                mediaRef.current?.triggerAdd();
              }
            } :
            section.key === 'checklists' ? () => { setChecklistModalTarget(null); setChecklistModalVisible(true); } :
            undefined
          }
        />
      );
    }

    switch (section.key) {
      case 'media':
        return (
          <View>
            <MediaGallerySection
              ref={mediaRef}
              title="Images"
              hideTitle={true}
              attachments={space?.images ?? []}
              maxAttachments={100}
              allowedKinds={['image']}
              onAddAttachment={handleAddImage}
              onAddAttachments={handleAddImages}
              onRemoveAttachment={handleRemoveImage}
              onSetPrimary={handleSetPrimaryImage}
              emptyStateMessage="No images yet."
              pickerLabel="Add image"
              size="md"
              tileScale={1.5}
            />
          </View>
        );

      case 'notes':
        return <NotesSection notes={space?.notes} />;

      case 'items': {
        // Get menu items for individual item
        const getItemMenuItems = (item: ScopedItem): AnchoredMenuItem[] => {
          if (!scopeConfig) return [];
          const itemDetailParams = getItemDetailParams(projectId, spaceId, item.id);
          return buildSingleItemMenu({
            context: 'space',
            scopeConfig,
            callbacks: {
              onEditOrOpen: () => router.push(itemDetailParams),
              onStatusChange: (status) => { if (accountId) { updateItem(accountId, item.id, { status }); showToast('Status updated'); if (status === 'returned') { returnPicker.openForItem(item.id); } } },
              onSetTransaction: () => { setSingleItemId(item.id); setSingleItemTransactionPickerVisible(true); },
              onClearTransaction: () => { if (accountId) { updateItem(accountId, item.id, { transactionId: null }); showToast('Transaction unlinked'); } },
              onSetSpace: () => { setSingleItemId(item.id); setSingleItemSpacePickerVisible(true); },
              onClearSpace: () => { if (accountId) { updateItem(accountId, item.id, { spaceId: null }); showToast('Space cleared'); } },
              onSellToBusiness: scopeConfig.scope === 'project' ? () => { setSingleItemId(item.id); setSingleItemSellToBusinessVisible(true); } : undefined,
              onSellToProject: () => { setSingleItemId(item.id); setSingleItemSellToProjectVisible(true); },
              onReassignToInventory: scopeConfig.scope === 'project' ? () => {
                if (!accountId) return;
                if (item.transactionId) {
                  Alert.alert('Cannot Reassign', 'This item is linked to a transaction and cannot be reassigned.');
                  return;
                }
                Alert.alert('Reassign to Inventory', 'Reassign this item to business inventory? No sale or purchase records will be created.', [
                  { text: 'Cancel', style: 'cancel' },
                  { text: 'Reassign', onPress: () => { reassignItemToInventory(accountId, item.id); showToast('Item reassigned to inventory'); } },
                ]);
              } : undefined,
              onReassignToProject: scopeConfig.scope === 'project' ? () => {
                if (item.transactionId) {
                  Alert.alert('Cannot Reassign', 'This item is linked to a transaction and cannot be reassigned.');
                  return;
                }
                setSingleItemId(item.id);
                setSingleItemReassignToProjectVisible(true);
              } : undefined,
              onDelete: () => {
                Alert.alert('Delete Item', 'Permanently delete this item? This cannot be undone.', [
                  { text: 'Cancel', style: 'cancel' },
                  { text: 'Delete', style: 'destructive', onPress: () => { if (accountId) { deleteItem(accountId, item.id); showToast('Item deleted'); } } },
                ]);
              },
            },
          });
        };

        // Create adapter for SharedItemsList manager interface
        const managerAdapter = {
          selectedIds: Array.from(itemsManager.selectedIds),
          selectAll: itemsManager.selectAll,
          clearSelection: itemsManager.clearSelection,
          setItemSelected: (id: string, selected: boolean) => {
            if (selected && !itemsManager.selectedIds.has(id)) {
              itemsManager.toggleSelection(id);
            } else if (!selected && itemsManager.selectedIds.has(id)) {
              itemsManager.toggleSelection(id);
            }
          },
          setGroupSelection: (ids: string[], selected: boolean) => {
            ids.forEach(id => {
              const isSelected = itemsManager.selectedIds.has(id);
              if (selected && !isSelected) {
                itemsManager.toggleSelection(id);
              } else if (!selected && isSelected) {
                itemsManager.toggleSelection(id);
              }
            });
          },
        };

        return (
          <View>
            <SharedItemsList
              embedded={true}
              manager={managerAdapter}
              items={itemsManager.filteredAndSortedItems}
              bulkActions={bulkActions}
              onItemPress={(id) => {
                const itemDetailParams = getItemDetailParams(projectId, spaceId, id);
                router.push(itemDetailParams);
              }}
              getItemMenuItems={getItemMenuItems}
              emptyMessage={itemsManager.searchQuery.trim() ? 'No items match this search.' : 'No items assigned.'}
            />
          </View>
        );
      }

      case 'checklists':
        return (
          <View style={styles.section}>
            {checklists.length === 0 ? (
              <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                No checklists yet.
              </AppText>
            ) : (
              <View style={styles.list}>
                {checklists.map((checklist, checklistIndex) => (
                  <View
                    key={checklist.id}
                    style={[styles.checklistCard, { borderColor: uiKitTheme.border.primary }]}
                  >
                    {/* Header: name + kebab */}
                    <View style={styles.checklistHeader}>
                      <AppText variant="body" style={styles.checklistNameText}>
                        {checklist.name}
                      </AppText>
                      <Pressable
                        onPress={() => setChecklistMenuId(checklist.id)}
                        hitSlop={8}
                        accessibilityRole="button"
                        accessibilityLabel={`Options for ${checklist.name}`}
                        style={styles.kebabButton}
                      >
                        <MaterialIcons name="more-vert" size={20} color={theme.colors.primary} />
                      </Pressable>
                    </View>
                    {/* Items — read-only with circle toggles */}
                    {checklist.items.length > 0 ? (
                      <View style={styles.list}>
                        {checklist.items.map((checklistItem, itemIndex) => (
                          <View key={checklistItem.id} style={styles.checklistItem}>
                            <Pressable
                              onPress={() => {
                                const next = [...checklists];
                                const itemsNext = [...checklist.items];
                                itemsNext[itemIndex] = {
                                  ...checklistItem,
                                  isChecked: !checklistItem.isChecked,
                                };
                                next[checklistIndex] = { ...checklist, items: itemsNext };
                                handleSaveChecklists(next);
                              }}
                              style={[
                                styles.checklistCircle,
                                { borderColor: uiKitTheme.border.primary },
                                checklistItem.isChecked && { backgroundColor: uiKitTheme.primary.main, borderColor: uiKitTheme.primary.main },
                              ]}
                              accessibilityRole="checkbox"
                              accessibilityState={{ checked: checklistItem.isChecked }}
                              accessibilityLabel={checklistItem.text}
                              accessibilityHint="Tap to toggle checklist item"
                            >
                              {checklistItem.isChecked ? (
                                <MaterialIcons name="check" size={13} color="#fff" />
                              ) : null}
                            </Pressable>
                            <AppText
                              variant="body"
                              style={[
                                styles.checklistItemText,
                                checklistItem.isChecked && styles.checklistItemChecked,
                              ]}
                            >
                              {checklistItem.text}
                            </AppText>
                          </View>
                        ))}
                      </View>
                    ) : (
                      <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                        No items. Tap ⋮ to edit.
                      </AppText>
                    )}
                  </View>
                ))}
              </View>
            )}
          </View>
        );

      default:
        return null;
    }
  }, [space, collapsedSections, handleToggleSection, itemsManager,
      accountId, projectId, spaceId, router, scopeConfig,
      theme.colors.textSecondary, theme.colors.background, uiKitTheme.border.primary,
      uiKitTheme.border.secondary, uiKitTheme.primary.main, checklists,
      handleSaveChecklists, handleAddImage, handleAddImages, handleRemoveImage, handleSetPrimaryImage,
      setChecklistModalTarget, setChecklistModalVisible, setChecklistMenuId]);

  // --- Render ---

  if (isLoading) {
    return (
      <View style={styles.container}>
        <View style={styles.loadingContainer} accessibilityRole="progressbar" accessibilityLabel="Loading space details">
          <ActivityIndicator size="large" color={theme.colors.primary} />
          <AppText variant="body">Loading space…</AppText>
        </View>
      </View>
    );
  }

  if (!space) {
    return (
      <View style={styles.container}>
        <AppText variant="body" accessibilityRole="alert">Space not found.</AppText>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <SectionList
        style={{ flex: 1 }}
        sections={sections}
        renderSectionHeader={renderSectionHeader}
        renderItem={renderItem}
        stickySectionHeadersEnabled={true}
        keyExtractor={(item, index) => {
          if (item === SECTION_HEADER_MARKER) return `header-${index}`;
          if (typeof item === 'string') return item;
          return item.id ?? `item-${index}`;
        }}
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        ItemSeparatorComponent={({ section }) =>
          section.key === 'items' ? <View style={styles.itemSeparator} /> : null
        }
      />

      <BulkSelectionBar
        selectedCount={itemsManager.selectionCount}
        onBulkActionsPress={() => setBulkActionsSheetVisible(true)}
        onClearSelection={itemsManager.clearSelection}
      />

      {/* Bulk actions sheet (with icons and submenus) */}
      <BottomSheetMenuList
        visible={bulkActionsSheetVisible}
        onRequestClose={() => setBulkActionsSheetVisible(false)}
        items={bulkMenuItems}
        title={`Bulk Actions (${itemsManager.selectionCount})`}
        showLeadingIcons={true}
      />

      {/* Kebab menu */}
      <BottomSheetMenuList
        visible={spaceMenuVisible}
        onRequestClose={onCloseSpaceMenu}
        items={spaceMenuItems}
        title={space.name?.trim() || 'Space'}
        showLeadingIcons={true}
      />

      {/* Sort menu */}
      <BottomSheetMenuList
        visible={itemsManager.sortMenuVisible}
        onRequestClose={() => itemsManager.setSortMenuVisible(false)}
        items={sortMenuItems}
        title="Sort"
      />

      {/* Filter menu */}
      <BottomSheetMenuList
        visible={itemsManager.filterMenuVisible}
        onRequestClose={() => itemsManager.setFilterMenuVisible(false)}
        items={filterMenuItems}
        title="Filter"
      />

      {/* Add item menu */}
      <BottomSheetMenuList
        visible={addMenuVisible}
        onRequestClose={() => setAddMenuVisible(false)}
        items={addMenuItems}
        title="Add Item"
        showLeadingIcons={true}
      />

      {/* Bulk move — SetSpaceModal */}
      <SetSpaceModal
        visible={bulkMoveSheetVisible}
        onRequestClose={() => setBulkMoveSheetVisible(false)}
        projectId={projectId ?? null}
        title="Move to Another Space"
        subtitle={`${itemsManager.selectionCount} item${itemsManager.selectionCount === 1 ? '' : 's'} selected`}
        onConfirm={(spaceId) => {
          if (!accountId || !spaceId) return;
          const selectedIds = itemsManager.selectedIds;
          const count = selectedIds.size;
          selectedIds.forEach((itemId) => {
            updateItem(accountId, itemId, { spaceId });
          });
          setBulkMoveSheetVisible(false);
          itemsManager.clearSelection();
          showToast(`${count} item${count === 1 ? '' : 's'} moved to space`);
        }}
      />

      {/* Sell to Business (project scope only) */}
      {scopeConfig?.scope === 'project' && (
        <SellToBusinessModal
          visible={sellToBusinessVisible}
          onRequestClose={() => setSellToBusinessVisible(false)}
          sourceBudgetCategories={budgetCategories}
          showSourceCategoryPicker={
            Array.from(itemsManager.selectedIds).some(id => {
              const item = itemsManager.filteredAndSortedItems.find(i => i.id === id);
              return item && !item.budgetCategoryId;
            })
          }
          subtitle={`${itemsManager.selectionCount} item${itemsManager.selectionCount === 1 ? '' : 's'} selected`}
          onConfirm={(scId) => {
            if (!accountId || !projectId) return;
            const selectedIds = itemsManager.selectedIds;
            const selected = itemsManager.filteredAndSortedItems.filter(i => selectedIds.has(i.id));
            executeSellToBusiness({
              accountId,
              projectId,
              items: selected,
              sourceCategoryId: scId,
            });
            setSellToBusinessVisible(false);
            itemsManager.clearSelection();
            showToast(`${selected.length} item${selected.length === 1 ? '' : 's'} sold to business`);
          }}
        />
      )}

      {/* Sell to Project */}
      <SellToProjectModal
        visible={sellToProjectVisible}
        onRequestClose={() => setSellToProjectVisible(false)}
        accountId={accountId!}
        excludeProjectId={projectId ?? undefined}
        destBudgetCategories={budgetCategories}
        sourceBudgetCategories={budgetCategories}
        showSourceCategoryPicker={
          scopeConfig?.scope === 'project' &&
          Array.from(itemsManager.selectedIds).some(id => {
            const item = itemsManager.filteredAndSortedItems.find(i => i.id === id);
            return item && !item.budgetCategoryId;
          })
        }
        showDestCategoryPicker={true}
        subtitle={`${itemsManager.selectionCount} item${itemsManager.selectionCount === 1 ? '' : 's'} selected`}
        onConfirm={({ targetProjectId: tpId, destCategoryId: dcId, sourceCategoryId: scId }) => {
          if (!accountId || !tpId || !dcId) return;
          const selectedIds = itemsManager.selectedIds;
          const selected = itemsManager.filteredAndSortedItems.filter(i => selectedIds.has(i.id));
          executeSellToProject({
            accountId,
            scope: scopeConfig?.scope ?? 'inventory',
            sourceProjectId: projectId ?? undefined,
            targetProjectId: tpId,
            items: selected,
            sourceCategoryId: scId,
            destCategoryId: dcId,
            validDestCategoryIds: new Set(Object.keys(budgetCategories)),
          });
          setSellToProjectVisible(false);
          itemsManager.clearSelection();
          showToast(`${selected.length} item${selected.length === 1 ? '' : 's'} sold to project`);
        }}
      />

      {/* Reassign to Project */}
      <ReassignToProjectModal
        visible={reassignToProjectVisible}
        onRequestClose={() => setReassignToProjectVisible(false)}
        accountId={accountId!}
        excludeProjectId={projectId ?? undefined}
        bulkInfo={(() => {
          const selectedIds = itemsManager.selectedIds;
          const selected = itemsManager.filteredAndSortedItems.filter(i => selectedIds.has(i.id));
          const eligible = selected.filter(i => !i.transactionId).map(i => i.id);
          const blockedCount = selected.length - eligible.length;
          return { eligibleCount: eligible.length, blockedCount };
        })()}
        onConfirm={(tpId) => {
          if (!accountId) return;
          const selectedIds = itemsManager.selectedIds;
          const selected = itemsManager.filteredAndSortedItems.filter(i => selectedIds.has(i.id));
          executeBulkReassignToProject({ accountId, items: selected, targetProjectId: tpId });
          setReassignToProjectVisible(false);
          itemsManager.clearSelection();
          showToast(`${selected.length} item${selected.length === 1 ? '' : 's'} reassigned to project`);
        }}
      />

      {/* Single-item Set Space */}
      <SetSpaceModal
        visible={singleItemSpacePickerVisible}
        onRequestClose={() => { setSingleItemSpacePickerVisible(false); setSingleItemId(null); }}
        projectId={projectId ?? null}
        onConfirm={(newSpaceId) => {
          if (!accountId || !singleItemId || !newSpaceId) return;
          updateItem(accountId, singleItemId, { spaceId: newSpaceId });
          setSingleItemSpacePickerVisible(false);
          setSingleItemId(null);
          showToast('Space updated');
        }}
      />

      {/* Single-item Set Transaction */}
      {scopeConfig && (
        <TransactionPickerModal
          visible={singleItemTransactionPickerVisible}
          onRequestClose={() => { setSingleItemTransactionPickerVisible(false); setSingleItemId(null); }}
          accountId={accountId!}
          scopeConfig={scopeConfig}
          onConfirm={(transaction) => {
            if (!accountId || !singleItemId) return;
            const update: Record<string, unknown> = { transactionId: transaction.id };
            if (transaction.budgetCategoryId) {
              update.budgetCategoryId = transaction.budgetCategoryId;
            }
            updateItem(accountId, singleItemId, update);
            setSingleItemTransactionPickerVisible(false);
            setSingleItemId(null);
            showToast('Transaction linked');
          }}
        />
      )}

      {/* Bulk Set Transaction */}
      {scopeConfig && (
        <TransactionPickerModal
          visible={bulkTransactionPickerVisible}
          onRequestClose={() => setBulkTransactionPickerVisible(false)}
          accountId={accountId!}
          scopeConfig={scopeConfig}
          subtitle={`${itemsManager.selectionCount} item${itemsManager.selectionCount === 1 ? '' : 's'} selected`}
          onConfirm={(transaction) => {
            if (!accountId) return;
            const ids = Array.from(itemsManager.selectedIds);
            ids.forEach((itemId) => {
              const update: Record<string, unknown> = { transactionId: transaction.id };
              if (transaction.budgetCategoryId) {
                update.budgetCategoryId = transaction.budgetCategoryId;
              }
              updateItem(accountId, itemId, update);
            });
            setBulkTransactionPickerVisible(false);
            itemsManager.clearSelection();
            showToast(`Transaction linked to ${ids.length} item${ids.length === 1 ? '' : 's'}`);
          }}
        />
      )}

      {/* Return Transaction Picker */}
      {scopeConfig && (
        <ReturnTransactionPickerModal
          visible={returnPicker.visible}
          onRequestClose={returnPicker.close}
          accountId={accountId!}
          scopeConfig={scopeConfig}
          onConfirm={returnPicker.handleConfirm}
          onCreateNew={returnPicker.handleCreateNew}
          subtitle={returnPicker.subtitle}
        />
      )}

      {/* Single-item Sell to Business (project scope only) */}
      {scopeConfig?.scope === 'project' && (
        <SellToBusinessModal
          visible={singleItemSellToBusinessVisible}
          onRequestClose={() => { setSingleItemSellToBusinessVisible(false); setSingleItemId(null); }}
          sourceBudgetCategories={budgetCategories}
          showSourceCategoryPicker={(() => {
            if (!singleItemId) return false;
            const item = itemsManager.filteredAndSortedItems.find(i => i.id === singleItemId);
            return item ? !item.budgetCategoryId : false;
          })()}
          onConfirm={(scId) => {
            if (!accountId || !projectId || !singleItemId) return;
            const item = itemsManager.filteredAndSortedItems.find(i => i.id === singleItemId);
            if (!item) return;
            executeSellToBusiness({
              accountId,
              projectId,
              items: [item],
              sourceCategoryId: scId,
            });
            setSingleItemSellToBusinessVisible(false);
            setSingleItemId(null);
            showToast('Item sold to business');
          }}
        />
      )}

      {/* Single-item Sell to Project */}
      <SellToProjectModal
        visible={singleItemSellToProjectVisible}
        onRequestClose={() => { setSingleItemSellToProjectVisible(false); setSingleItemId(null); }}
        accountId={accountId!}
        excludeProjectId={projectId ?? undefined}
        destBudgetCategories={budgetCategories}
        sourceBudgetCategories={budgetCategories}
        showSourceCategoryPicker={(() => {
          if (!singleItemId || scopeConfig?.scope !== 'project') return false;
          const item = itemsManager.filteredAndSortedItems.find(i => i.id === singleItemId);
          return item ? !item.budgetCategoryId : false;
        })()}
        showDestCategoryPicker={true}
        onConfirm={({ targetProjectId: tpId, destCategoryId: dcId, sourceCategoryId: scId }) => {
          if (!accountId || !tpId || !dcId || !singleItemId) return;
          const item = itemsManager.filteredAndSortedItems.find(i => i.id === singleItemId);
          if (!item) return;
          executeSellToProject({
            accountId,
            scope: scopeConfig?.scope ?? 'inventory',
            sourceProjectId: projectId ?? undefined,
            targetProjectId: tpId,
            items: [item],
            sourceCategoryId: scId,
            destCategoryId: dcId,
            validDestCategoryIds: new Set(Object.keys(budgetCategories)),
          });
          setSingleItemSellToProjectVisible(false);
          setSingleItemId(null);
          showToast('Item sold to project');
        }}
      />

      {/* Single-item Reassign to Project */}
      <ReassignToProjectModal
        visible={singleItemReassignToProjectVisible}
        onRequestClose={() => { setSingleItemReassignToProjectVisible(false); setSingleItemId(null); }}
        accountId={accountId!}
        excludeProjectId={projectId ?? undefined}
        onConfirm={(tpId) => {
          if (!accountId || !singleItemId) return;
          reassignItemToProject(accountId, singleItemId, tpId);
          setSingleItemReassignToProjectVisible(false);
          setSingleItemId(null);
          showToast('Item reassigned to project');
        }}
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

          {/* Tab bar */}
          <View
            style={[styles.pickerTabBar, { borderBottomColor: uiKitTheme.border.secondary }]}
            accessibilityRole="tablist"
            accessibilityLabel="Item picker tabs"
          >
            {[
              { value: 'current' as const, label: pickerTabLabel, accessibilityLabel: projectId ? 'Project items tab' : 'In Business Inventory tab' },
              { value: 'outside' as const, label: 'Outside', accessibilityLabel: 'Outside items tab' },
            ].map((tab) => {
              const isSelected = pickerTab === tab.value;
              const count = tab.value === 'current' ? availableItems.length : outsideItemsHook.items.length;

              return (
                <TouchableOpacity
                  key={tab.value}
                  style={[
                    styles.pickerTab,
                    isSelected && { borderBottomColor: theme.colors.primary, borderBottomWidth: 2 },
                  ]}
                  onPress={() => {
                    setPickerTab(tab.value);
                    pickerManager.clearSelection();
                  }}
                  activeOpacity={0.7}
                  accessibilityRole="tab"
                  accessibilityState={{ selected: isSelected }}
                  accessibilityLabel={tab.accessibilityLabel}
                >
                  <AppText
                    variant="body"
                    style={[
                      isSelected && { color: theme.colors.primary, fontWeight: '700' },
                      !isSelected && { color: theme.colors.textSecondary },
                    ]}
                  >
                    {tab.label}
                  </AppText>
                  <View
                    style={[
                      styles.pickerTabCount,
                      {
                        backgroundColor: isSelected
                          ? theme.colors.primary + '1A'
                          : uiKitTheme.background.tertiary,
                      },
                    ]}
                  >
                    <AppText
                      variant="caption"
                      style={{
                        color: isSelected
                          ? theme.colors.primary
                          : theme.colors.textSecondary,
                        fontSize: 12,
                      }}
                    >
                      {count}
                    </AppText>
                  </View>
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
              isEligible: (item) => item.spaceId !== spaceId,
              getStatusLabel: (item) => {
                if (item.spaceId === spaceId) return 'Already here';
                return undefined;
              },
            }}
            onAddSelected={handleAddSelectedItems}
            onAddSingle={handleAddSingleItem}
            addedIds={spaceItemIds}
            outsideLoading={pickerTab === 'outside' ? outsideItemsHook.loading : false}
            outsideError={pickerTab === 'outside' ? outsideItemsHook.error : null}
          />
        </View>
      </BottomSheet>

      {/* Edit Space Name Modal */}
      <EditSpaceDetailsModal
        visible={editNameVisible}
        onRequestClose={() => setEditNameVisible(false)}
        initialName={space?.name ?? ''}
        onSave={handleSaveSpaceName}
      />

      {/* Edit Notes Modal */}
      <EditNotesModal
        visible={editNotesVisible}
        onRequestClose={() => setEditNotesVisible(false)}
        initialNotes={space?.notes ?? ''}
        onSave={handleSaveNotes}
      />

      {/* Add / Edit Checklist Modal */}
      <EditChecklistModal
        visible={checklistModalVisible}
        onRequestClose={() => setChecklistModalVisible(false)}
        checklist={checklistModalTarget}
        onSave={(saved) => {
          const exists = checklists.some((c) => c.id === saved.id);
          const next = exists
            ? checklists.map((c) => (c.id === saved.id ? saved : c))
            : [...checklists, saved];
          handleSaveChecklists(next);
          setChecklistModalVisible(false);
          setChecklistModalTarget(null);
        }}
      />

      {/* Per-checklist kebab menu */}
      <BottomSheetMenuList
        visible={checklistMenuId !== null}
        onRequestClose={() => setChecklistMenuId(null)}
        title={checklists.find((c) => c.id === checklistMenuId)?.name ?? 'Checklist'}
        showLeadingIcons={true}
        items={[
          {
            key: 'edit',
            label: 'Edit',
            icon: 'edit',
            onPress: () => {
              const target = checklists.find((c) => c.id === checklistMenuId) ?? null;
              setChecklistMenuId(null);
              setChecklistModalTarget(target);
              setChecklistModalVisible(true);
            },
          },
          {
            key: 'delete',
            label: 'Delete',
            icon: 'delete-outline',
            destructive: true,
            onPress: () => {
              const target = checklists.find((c) => c.id === checklistMenuId);
              setChecklistMenuId(null);
              if (!target) return;
              Alert.alert(
                'Delete Checklist',
                `Delete "${target.name}"?`,
                [
                  { text: 'Cancel', style: 'cancel' },
                  {
                    text: 'Delete',
                    style: 'destructive',
                    onPress: () => {
                      handleSaveChecklists(checklists.filter((c) => c.id !== target.id));
                    },
                  },
                ],
              );
            },
          },
        ]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    gap: 4,
    paddingTop: layout.screenBodyTopMd.paddingTop,
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
  section: {
    gap: 12,
  },
  list: {
    gap: 10,
  },
  itemSeparator: {
    height: 10,
  },
  emptyState: {
    paddingVertical: 16,
    paddingHorizontal: 20,
  },
  checklistCard: {
    borderWidth: 1,
    borderRadius: 12,
    padding: 12,
    gap: 10,
  },
  checklistHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  checklistNameText: {
    flex: 1,
    fontWeight: '600',
  },
  kebabButton: {
    padding: 4,
  },
  checklistItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  checklistItemText: {
    flex: 1,
  },
  checklistItemChecked: {
    textDecorationLine: 'line-through',
    opacity: 0.5,
  },
  checklistCircle: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 1.5,
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  loadingContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    paddingVertical: 32,
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
    borderBottomWidth: 1,
    gap: 16,
  },
  pickerTab: {
    paddingVertical: 12,
    paddingHorizontal: 4,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  pickerTabCount: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 12,
    minWidth: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
