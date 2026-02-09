import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Screen } from '../../../../src/components/Screen';
import { AppText } from '../../../../src/components/AppText';
import { AppButton } from '../../../../src/components/AppButton';
import { ItemsListControlBar } from '../../../../src/components/ItemsListControlBar';
import { ItemCard } from '../../../../src/components/ItemCard';
import { SharedItemPicker } from '../../../../src/components/SharedItemPicker';
import { SpaceSelector } from '../../../../src/components/SpaceSelector';
import { ThumbnailGrid } from '../../../../src/components/ThumbnailGrid';
import { ImageGallery } from '../../../../src/components/ImageGallery';
import { ImagePickerButton } from '../../../../src/components/ImagePickerButton';
import { BottomSheet } from '../../../../src/components/BottomSheet';
import { BottomSheetMenuList } from '../../../../src/components/BottomSheetMenuList';
import { NotesSection } from '../../../../src/components/NotesSection';
import type { AnchoredMenuItem } from '../../../../src/components/AnchoredMenuList';
import { layout } from '../../../../src/ui';
import { useTheme, useUIKitTheme } from '../../../../src/theme/ThemeProvider';
import { useAccountContextStore } from '../../../../src/auth/accountContextStore';
import { useAuthStore } from '../../../../src/auth/authStore';
import { subscribeToSpace, Space, updateSpace, deleteSpace, Checklist } from '../../../../src/data/spacesService';
import { createSpaceTemplate } from '../../../../src/data/spaceTemplatesService';
import { createProjectScopeConfig, getScopeId } from '../../../../src/data/scopeConfig';
import { useScopeSwitching } from '../../../../src/data/useScopeSwitching';
import { useScopedListeners } from '../../../../src/data/useScopedListeners';
import { subscribeToScopedItems, ScopedItem } from '../../../../src/data/scopedListData';
import { updateItem } from '../../../../src/data/itemsService';
import { createRepository } from '../../../../src/data/repository';
import { getTextInputStyle } from '../../../../src/ui/styles/forms';
import { deleteLocalMediaByUrl, saveLocalMedia, resolveAttachmentUri } from '../../../../src/offline/media';
import type { AttachmentRef } from '../../../../src/offline/media';
import { useOutsideItems } from '../../../../src/hooks/useOutsideItems';
import { useOptionalIsFocused } from '../../../../src/hooks/useOptionalIsFocused';
import { resolveItemMove } from '../../../../src/data/resolveItemMove';

type SpaceParams = {
  projectId?: string;
  spaceId?: string;
};

type ItemPickerTab = 'current' | 'outside';

type SortMode = 'created-desc' | 'created-asc' | 'alphabetical-asc' | 'alphabetical-desc';

function randomId(prefix: string) {
  const cryptoApi = globalThis.crypto as { randomUUID?: () => string } | undefined;
  return cryptoApi?.randomUUID ? cryptoApi.randomUUID() : `${prefix}_${Date.now()}_${Math.random()}`;
}

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

export default function SpaceDetailScreen() {
  const params = useLocalSearchParams<SpaceParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const spaceId = Array.isArray(params.spaceId) ? params.spaceId[0] : params.spaceId;
  const [spaceName, setSpaceName] = useState('Space');
  const [spaceMenuVisible, setSpaceMenuVisible] = useState(false);

  if (!projectId || !spaceId) {
    return (
      <Screen title="Space">
        <View style={styles.container}>
          <AppText variant="body">Space not found.</AppText>
        </View>
      </Screen>
    );
  }

  return (
    <Screen
      title={spaceName}
      backTarget={`/project/${projectId}?tab=spaces`}
      onPressMenu={() => setSpaceMenuVisible(true)}
    >
      <SpaceDetailContent
        projectId={projectId}
        spaceId={spaceId}
        onSpaceNameChange={setSpaceName}
        spaceMenuVisible={spaceMenuVisible}
        onCloseSpaceMenu={() => setSpaceMenuVisible(false)}
      />
    </Screen>
  );
}

type SpaceDetailContentProps = {
  projectId: string;
  spaceId: string;
  onSpaceNameChange: (name: string) => void;
  spaceMenuVisible: boolean;
  onCloseSpaceMenu: () => void;
};

function SpaceDetailContent({
  projectId,
  spaceId,
  onSpaceNameChange,
  spaceMenuVisible,
  onCloseSpaceMenu,
}: SpaceDetailContentProps) {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const userId = useAuthStore((store) => store.user?.uid ?? null);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const [space, setSpace] = useState<Space | null>(null);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [checklists, setChecklists] = useState<Checklist[]>([]);
  const [isPickingItems, setIsPickingItems] = useState(false);
  const [pickerTab, setPickerTab] = useState<ItemPickerTab>('current');
  const [pickerSelectedIds, setPickerSelectedIds] = useState<string[]>([]);

  // Items tab controls
  const [showSearch, setShowSearch] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortMode, setSortMode] = useState<SortMode>('created-desc');
  const [sortMenuVisible, setSortMenuVisible] = useState(false);
  const [filterMode, setFilterMode] = useState<'all' | 'bookmarked' | 'no-sku' | 'no-image'>('all');
  const [filterMenuVisible, setFilterMenuVisible] = useState(false);
  const [addMenuVisible, setAddMenuVisible] = useState(false);

  const outsideItemsHook = useOutsideItems({
    accountId,
    currentProjectId: projectId,
    scope: 'project',
    includeInventory: true,
  });
  const [bulkMode, setBulkMode] = useState(false);
  const [bulkSelectedIds, setBulkSelectedIds] = useState<string[]>([]);
  const [bulkTargetSpaceId, setBulkTargetSpaceId] = useState<string | null>(null);
  const [canSaveTemplate, setCanSaveTemplate] = useState(false);
  const [galleryVisible, setGalleryVisible] = useState(false);
  const [galleryIndex, setGalleryIndex] = useState(0);

  const isFocused = useOptionalIsFocused(true);
  const scopeConfig = useMemo(() => createProjectScopeConfig(projectId), [projectId]);
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

  // Search, filter, and sort items
  const isFilterActive = filterMode !== 'all';
  const filteredSpaceItems = useMemo(() => {
    let result = spaceItems;

    // Apply filter
    if (filterMode === 'bookmarked') {
      result = result.filter((item) => Boolean((item as any).bookmark));
    } else if (filterMode === 'no-sku') {
      result = result.filter((item) => !(item as any).sku?.trim());
    } else if (filterMode === 'no-image') {
      result = result.filter((item) => !((item as any).images?.length > 0));
    }

    // Apply search
    const needle = searchQuery.trim().toLowerCase();
    if (needle) {
      result = result.filter((item) => {
        const haystack = [
          item.name ?? '',
          (item as any).sku ?? '',
          (item as any).source ?? '',
          (item as any).notes ?? '',
        ].join(' ').toLowerCase();
        return haystack.includes(needle);
      });
    }

    return [...result].sort((a, b) => {
      if (sortMode === 'alphabetical-asc') return (a.name ?? '').localeCompare(b.name ?? '');
      if (sortMode === 'alphabetical-desc') return (b.name ?? '').localeCompare(a.name ?? '');
      if (sortMode === 'created-asc') return String((a as any).createdAt ?? '').localeCompare(String((b as any).createdAt ?? ''));
      return String((b as any).createdAt ?? '').localeCompare(String((a as any).createdAt ?? ''));
    });
  }, [spaceItems, searchQuery, sortMode, filterMode]);

  const activePickerItems = pickerTab === 'outside' ? outsideItemsHook.items : availableItems;

  useEffect(() => {
    if (!isPickingItems) return;
    void outsideItemsHook.reload();
  }, [isPickingItems, outsideItemsHook]);

  // --- Handlers ---

  const handleSaveChecklists = useCallback(
    (next: Checklist[]) => {
      if (!accountId || !spaceId) return;
      setChecklists(next);
      updateSpace(accountId, spaceId, { checklists: next }).catch((err) => {
        console.warn('[spaces] checklist update failed:', err);
      });
    },
    [accountId, spaceId]
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
    updateSpace(accountId, spaceId, { images: nextImages }).catch((err) => {
      console.warn('[spaces] image add failed:', err);
    });
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
      updateSpace(accountId, spaceId, { images: nextImages }).catch((err) => {
        console.warn('[spaces] image remove failed:', err);
      });
    },
    [accountId, space, spaceId]
  );

  const handleSetPrimaryImage = useCallback(
    (image: AttachmentRef) => {
      if (!accountId || !spaceId) return;
      const nextImages = (space?.images ?? []).map((img) => ({
        ...img,
        isPrimary: img.url === image.url,
      }));
      updateSpace(accountId, spaceId, { images: nextImages }).catch((err) => {
        console.warn('[spaces] set primary image failed:', err);
      });
    },
    [accountId, space?.images, spaceId]
  );

  const handleAddSelectedItems = useCallback(() => {
    if (!accountId || pickerSelectedIds.length === 0 || !projectId) return;
    const selectedItems = activePickerItems.filter((item) => pickerSelectedIds.includes(item.id));

    if (pickerTab !== 'outside') {
      selectedItems.forEach((item) => {
        updateItem(accountId, item.id, { spaceId }).catch((err) => {
          console.warn(`[spaces] move item ${item.id} failed:`, err);
        });
      });
      setPickerSelectedIds([]);
      setIsPickingItems(false);
      return;
    }

    const missingCategory = selectedItems.filter((item) => !item.budgetCategoryId);
    if (missingCategory.length > 0) {
      Alert.alert(
        'Missing category',
        'Some items are missing a budget category and cannot be moved. Update them first and try again.'
      );
      return;
    }

    selectedItems.forEach((item) => {
      if (item.transactionId) return;
      const result = resolveItemMove(item, {
        accountId,
        itemId: item.id,
        targetProjectId: projectId,
        targetSpaceId: spaceId,
        budgetCategoryId: item.budgetCategoryId ?? null,
      });
      if (!result.success) {
        console.warn(`[items] move failed for ${item.id}: ${result.error}`);
      }
    });
    setPickerSelectedIds([]);
    setIsPickingItems(false);
  }, [accountId, activePickerItems, pickerSelectedIds, pickerTab, projectId, spaceId]);

  const handleAddSingleItem = useCallback((item: ScopedItem | { id: string; transactionId?: string | null; budgetCategoryId?: string | null; projectId?: string | null; [key: string]: any }) => {
    if (!accountId || !projectId) return;
    const isOutside = pickerTab === 'outside';
    if (!isOutside) {
      updateItem(accountId, item.id, { spaceId }).catch((err) => {
        console.warn(`[spaces] move item ${item.id} failed:`, err);
      });
    } else {
      if (item.transactionId) return;
      const result = resolveItemMove(item as any, {
        accountId,
        itemId: item.id,
        targetProjectId: projectId,
        targetSpaceId: spaceId,
        budgetCategoryId: item.budgetCategoryId ?? null,
      });
      if (!result.success) {
        console.warn(`[items] move failed for ${item.id}: ${result.error}`);
      }
    }
  }, [accountId, pickerTab, projectId, spaceId]);

  const spaceItemIds = useMemo(() => new Set(spaceItems.map((item) => item.id)), [spaceItems]);

  const handleBulkRemove = useCallback(() => {
    if (!accountId || bulkSelectedIds.length === 0) return;
    bulkSelectedIds.forEach((itemId) => {
      updateItem(accountId, itemId, { spaceId: null }).catch((err) => {
        console.warn(`[spaces] bulk remove item ${itemId} failed:`, err);
      });
    });
    setBulkSelectedIds([]);
  }, [accountId, bulkSelectedIds]);

  const handleBulkMove = useCallback(() => {
    if (!accountId || bulkSelectedIds.length === 0 || !bulkTargetSpaceId) return;
    bulkSelectedIds.forEach((itemId) => {
      updateItem(accountId, itemId, { spaceId: bulkTargetSpaceId }).catch((err) => {
        console.warn(`[spaces] bulk move item ${itemId} failed:`, err);
      });
    });
    setBulkSelectedIds([]);
    setBulkTargetSpaceId(null);
  }, [accountId, bulkSelectedIds, bulkTargetSpaceId]);

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
          deleteSpace(accountId, spaceId).catch((err) => {
            console.warn('[spaces] delete failed:', err);
          });
          router.replace(`/project/${projectId}?tab=spaces`);
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
        scope: 'project',
        projectId,
        spaceId,
        backTarget: `/project/${projectId}/spaces/${spaceId}`,
      },
    });
  }, [projectId, router, spaceId]);

  // --- Kebab menu items ---

  const spaceMenuItems: AnchoredMenuItem[] = useMemo(() => {
    const menuItems: AnchoredMenuItem[] = [
      {
        key: 'edit',
        label: 'Edit',
        icon: 'edit',
        onPress: () => router.push(`/project/${projectId}/spaces/${spaceId}/edit`),
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

  // --- Sort menu items ---

  const sortMenuItems: AnchoredMenuItem[] = useMemo(() => [
    {
      label: 'Sort by',
      subactions: [
        { key: 'created-desc', label: 'Newest first', onPress: () => setSortMode('created-desc') },
        { key: 'created-asc', label: 'Oldest first', onPress: () => setSortMode('created-asc') },
        { key: 'alphabetical-asc', label: 'A → Z', onPress: () => setSortMode('alphabetical-asc') },
        { key: 'alphabetical-desc', label: 'Z → A', onPress: () => setSortMode('alphabetical-desc') },
      ],
      selectedSubactionKey: sortMode,
    },
  ], [sortMode]);

  // --- Filter menu items ---

  const filterMenuItems: AnchoredMenuItem[] = useMemo(() => [
    { key: 'all', label: 'All', onPress: () => setFilterMode('all'), icon: filterMode === 'all' ? 'check' as const : undefined },
    { key: 'bookmarked', label: 'Bookmarked', onPress: () => setFilterMode('bookmarked'), icon: filterMode === 'bookmarked' ? 'check' as const : undefined },
    { key: 'no-sku', label: 'No SKU', onPress: () => setFilterMode('no-sku'), icon: filterMode === 'no-sku' ? 'check' as const : undefined },
    { key: 'no-image', label: 'No image', onPress: () => setFilterMode('no-image'), icon: filterMode === 'no-image' ? 'check' as const : undefined },
  ], [filterMode]);

  // --- Add menu items (bottom sheet) ---

  const addMenuItems: AnchoredMenuItem[] = useMemo(() => [
    {
      key: 'create',
      label: 'Create item',
      icon: 'add' as const,
      onPress: handleCreateItemInSpace,
    },
    {
      key: 'add-existing',
      label: 'Add existing item',
      icon: 'playlist-add' as const,
      onPress: () => {
        setAddMenuVisible(false);
        // Delay opening picker until the add-menu modal has fully dismissed
        setTimeout(() => {
          setIsPickingItems(true);
          setPickerTab('current');
          setPickerSelectedIds([]);
        }, 300);
      },
    },
  ], [handleCreateItemInSpace]);

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
      <ScrollView contentContainerStyle={styles.scrollContent}>
        {/* Images */}
        <View style={styles.section}>
          <AppText variant="h2">Images</AppText>
          {space.images && space.images.length > 0 ? (
            <>
              <ThumbnailGrid
                images={space.images}
                size="lg"
                tileScale={1}
                onImagePress={(_image, index) => {
                  setGalleryIndex(index);
                  setGalleryVisible(true);
                }}
                onSetPrimary={handleSetPrimaryImage}
                onDelete={handleRemoveImage}
              />
              {space.images.length < 50 && (
                <ImagePickerButton
                  onFilePicked={handleAddImage}
                  maxFiles={50}
                  currentFileCount={space.images.length}
                  style={styles.imagePickerButton}
                />
              )}
            </>
          ) : (
            <ImagePickerButton
              onFilePicked={handleAddImage}
              maxFiles={50}
              currentFileCount={0}
              style={styles.imagePickerButton}
            />
          )}
        </View>

        {/* Info / Notes */}
        <NotesSection notes={space.notes} expandable={true} />

        {/* Items */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <AppText variant="h2">Items</AppText>
          </View>
          <ItemsListControlBar
            search={searchQuery}
            onChangeSearch={setSearchQuery}
            showSearch={showSearch}
            onToggleSearch={() => setShowSearch((prev) => !prev)}
            onSort={() => setSortMenuVisible(true)}
            isSortActive={sortMode !== 'created-desc'}
            onFilter={() => setFilterMenuVisible(true)}
            isFilterActive={isFilterActive}
            onAdd={() => setAddMenuVisible(true)}
          />

          {bulkMode ? (
            <View style={styles.bulkPanel}>
              <View style={styles.bulkHeader}>
                <AppText variant="caption">{bulkSelectedIds.length} selected</AppText>
                <AppButton
                  title="Done"
                  variant="secondary"
                  onPress={() => {
                    setBulkMode(false);
                    setBulkSelectedIds([]);
                  }}
                />
              </View>
              <SpaceSelector
                projectId={projectId}
                value={bulkTargetSpaceId}
                onChange={setBulkTargetSpaceId}
                allowCreate={false}
                placeholder="Move to space…"
              />
              <View style={styles.bulkActions}>
                <AppButton
                  title="Move"
                  variant="secondary"
                  onPress={handleBulkMove}
                  disabled={!bulkTargetSpaceId || bulkSelectedIds.length === 0}
                />
                <AppButton
                  title="Remove from space"
                  variant="secondary"
                  onPress={handleBulkRemove}
                  disabled={bulkSelectedIds.length === 0}
                />
              </View>
            </View>
          ) : null}

          {filteredSpaceItems.length === 0 ? (
            <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
              {searchQuery.trim() ? 'No items match this search.' : 'No items assigned.'}
            </AppText>
          ) : (
            <View style={styles.list}>
              {filteredSpaceItems.map((item) => {
                const itemMenuItems: AnchoredMenuItem[] = [
                  {
                    key: 'open',
                    label: 'Open',
                    onPress: () =>
                      router.push({
                        pathname: '/items/[id]',
                        params: {
                          id: item.id,
                          scope: 'project',
                          projectId,
                          backTarget: `/project/${projectId}/spaces/${spaceId}`,
                        },
                      }),
                  },
                  {
                    key: 'remove-from-space',
                    label: 'Remove from Space',
                    onPress: () => {
                      if (!accountId) return;
                      updateItem(accountId, item.id, { spaceId: null }).catch((err) => {
                        console.warn(`[spaces] remove item from space failed:`, err);
                      });
                    },
                  },
                ];

                return (
                  <ItemCard
                    key={item.id}
                    name={item.name?.trim() || 'Untitled item'}
                    sku={(item as any).sku ?? undefined}
                    sourceLabel={(item as any).source ?? undefined}
                    priceLabel={getDisplayPrice(item)}
                    statusLabel={(item as any).status ?? undefined}
                    thumbnailUri={getPrimaryImageUri(item)}
                    selected={bulkMode ? bulkSelectedIds.includes(item.id) : undefined}
                    onSelectedChange={
                      bulkMode
                        ? (next) =>
                            setBulkSelectedIds((prev) =>
                              next ? [...prev, item.id] : prev.filter((id) => id !== item.id)
                            )
                        : undefined
                    }
                    menuItems={bulkMode ? undefined : itemMenuItems}
                    bookmarked={Boolean((item as any).bookmark)}
                    onBookmarkPress={() => {
                      if (!accountId) return;
                      updateItem(accountId, item.id, { bookmark: !(item as any).bookmark }).catch((err) => {
                        console.warn(`[spaces] bookmark toggle failed:`, err);
                      });
                    }}
                    onPress={() => {
                      if (bulkMode) {
                        setBulkSelectedIds((prev) =>
                          prev.includes(item.id)
                            ? prev.filter((id) => id !== item.id)
                            : [...prev, item.id]
                        );
                        return;
                      }
                      router.push({
                        pathname: '/items/[id]',
                        params: {
                          id: item.id,
                          scope: 'project',
                          projectId,
                          backTarget: `/project/${projectId}/spaces/${spaceId}`,
                        },
                      });
                    }}
                  />
                );
              })}
            </View>
          )}

          {!bulkMode && spaceItems.length > 0 ? (
            <Pressable
              onPress={() => {
                setBulkMode(true);
                setBulkSelectedIds([]);
              }}
              style={styles.bulkModeToggle}
            >
              <AppText variant="caption" style={{ color: theme.colors.primary }}>
                Select multiple items…
              </AppText>
            </Pressable>
          ) : null}
        </View>

        {/* Checklists */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <AppText variant="h2">Checklists</AppText>
          </View>
          <AppButton
            title="Add checklist"
            onPress={() =>
              handleSaveChecklists([
                ...checklists,
                { id: randomId('checklist'), name: 'Checklist', items: [] },
              ])
            }
            accessibilityLabel="Add new checklist"
            accessibilityHint="Create a new checklist for this space"
          />
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
                  <View style={styles.checklistHeader}>
                    <TextInput
                      value={checklist.name}
                      onChangeText={(text) => {
                        const next = [...checklists];
                        next[checklistIndex] = { ...checklist, name: text };
                        setChecklists(next);
                      }}
                      onBlur={() => handleSaveChecklists(checklists)}
                      style={[getTextInputStyle(uiKitTheme, { padding: 10, radius: 8 }), styles.checklistNameInput]}
                    />
                    <Pressable
                      onPress={() => {
                        Alert.alert(
                          'Delete checklist',
                          `Delete "${checklist.name}"?`,
                          [
                            { text: 'Cancel', style: 'cancel' },
                            {
                              text: 'Delete',
                              style: 'destructive',
                              onPress: () => {
                                const next = checklists.filter((_, i) => i !== checklistIndex);
                                handleSaveChecklists(next);
                              },
                            },
                          ]
                        );
                      }}
                      hitSlop={8}
                      accessibilityRole="button"
                      accessibilityLabel={`Delete ${checklist.name} checklist`}
                      style={styles.deleteButton}
                    >
                      <MaterialIcons name="delete-outline" size={20} color={theme.colors.textSecondary} />
                    </Pressable>
                  </View>
                  <View style={styles.list}>
                    {checklist.items.map((item, itemIndex) => (
                      <View key={item.id} style={styles.checklistItem}>
                        <Pressable
                          onPress={() => {
                            const next = [...checklists];
                            const itemsNext = [...checklist.items];
                            itemsNext[itemIndex] = {
                              ...item,
                              isChecked: !item.isChecked,
                            };
                            next[checklistIndex] = { ...checklist, items: itemsNext };
                            handleSaveChecklists(next);
                          }}
                          style={[
                            styles.checkbox,
                            { borderColor: uiKitTheme.border.primary },
                            item.isChecked && { backgroundColor: uiKitTheme.primary.main },
                          ]}
                          accessibilityRole="checkbox"
                          accessibilityState={{ checked: item.isChecked }}
                          accessibilityLabel={item.text}
                          accessibilityHint="Tap to toggle checklist item"
                        >
                          {item.isChecked ? (
                            <MaterialIcons name="check" size={14} color="#fff" />
                          ) : null}
                        </Pressable>
                        <TextInput
                          value={item.text}
                          onChangeText={(text) => {
                            const next = [...checklists];
                            const itemsNext = [...checklist.items];
                            itemsNext[itemIndex] = { ...item, text };
                            next[checklistIndex] = { ...checklist, items: itemsNext };
                            setChecklists(next);
                          }}
                          onBlur={() => handleSaveChecklists(checklists)}
                          style={[
                            getTextInputStyle(uiKitTheme, { padding: 8, radius: 8 }),
                            styles.checklistItemInput,
                            item.isChecked && styles.checklistItemChecked,
                          ]}
                        />
                        <Pressable
                          onPress={() => {
                            const next = [...checklists];
                            const itemsNext = checklist.items.filter((_, i) => i !== itemIndex);
                            next[checklistIndex] = { ...checklist, items: itemsNext };
                            handleSaveChecklists(next);
                          }}
                          hitSlop={8}
                          accessibilityRole="button"
                          accessibilityLabel={`Delete ${item.text}`}
                        >
                          <MaterialIcons name="close" size={18} color={theme.colors.textSecondary} />
                        </Pressable>
                      </View>
                    ))}
                  </View>
                  <AppButton
                    title="Add item"
                    variant="secondary"
                    onPress={() => {
                      const next = [...checklists];
                      const itemsNext = [
                        ...checklist.items,
                        { id: randomId('item'), text: 'Item', isChecked: false },
                      ];
                      next[checklistIndex] = { ...checklist, items: itemsNext };
                      handleSaveChecklists(next);
                    }}
                  />
                </View>
              ))}
            </View>
          )}
        </View>
      </ScrollView>

      {/* Image gallery lightbox */}
      {space.images && space.images.length > 0 && (
        <ImageGallery
          images={space.images}
          initialIndex={galleryIndex}
          visible={galleryVisible}
          onRequestClose={() => setGalleryVisible(false)}
        />
      )}

      {/* Kebab menu */}
      <BottomSheetMenuList
        visible={spaceMenuVisible}
        onRequestClose={onCloseSpaceMenu}
        items={spaceMenuItems}
        title={space.name?.trim() || 'Space'}
      />

      {/* Sort menu */}
      <BottomSheetMenuList
        visible={sortMenuVisible}
        onRequestClose={() => setSortMenuVisible(false)}
        items={sortMenuItems}
        title="Sort"
      />

      {/* Filter menu */}
      <BottomSheetMenuList
        visible={filterMenuVisible}
        onRequestClose={() => setFilterMenuVisible(false)}
        items={filterMenuItems}
        title="Filter"
      />

      {/* Add item menu */}
      <BottomSheetMenuList
        visible={addMenuVisible}
        onRequestClose={() => setAddMenuVisible(false)}
        items={addMenuItems}
        title="Add item"
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
            tabs={[
              { value: 'current', label: 'Project', accessibilityLabel: 'Project items tab' },
              { value: 'outside', label: 'Outside', accessibilityLabel: 'Outside items tab' },
            ]}
            tabCounts={{ current: availableItems.length, outside: outsideItemsHook.items.length }}
            selectedTab={pickerTab}
            onTabChange={(next) => {
              setPickerTab(next as ItemPickerTab);
              setPickerSelectedIds([]);
            }}
            items={activePickerItems}
            selectedIds={pickerSelectedIds}
            onSelectionChange={setPickerSelectedIds}
            eligibilityCheck={{
              isEligible: (item) => item.spaceId !== spaceId && !item.transactionId,
              getStatusLabel: (item) => {
                if (item.spaceId === spaceId) return 'Already here';
                if (item.transactionId) return 'Linked';
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
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scrollContent: {
    gap: 20,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  section: {
    gap: 12,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  list: {
    gap: 10,
  },
  bulkPanel: {
    gap: 10,
  },
  bulkHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  bulkActions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
  bulkModeToggle: {
    paddingVertical: 8,
    alignItems: 'center',
  },
  imagePickerButton: {
    width: '100%',
  },
  checklists: {
    gap: 12,
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
  checklistNameInput: {
    flex: 1,
  },
  deleteButton: {
    padding: 4,
  },
  checklistItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  checklistItemInput: {
    flex: 1,
  },
  checklistItemChecked: {
    textDecorationLine: 'line-through',
    opacity: 0.6,
  },
  checkbox: {
    width: 22,
    height: 22,
    borderWidth: 1,
    borderRadius: 4,
    alignItems: 'center',
    justifyContent: 'center',
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
});
