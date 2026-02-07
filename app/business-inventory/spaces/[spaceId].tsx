import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { useScreenTabs } from '../../../src/components/ScreenTabs';
import { AppText } from '../../../src/components/AppText';
import { AppButton } from '../../../src/components/AppButton';
import { SharedItemPicker } from '../../../src/components/SharedItemPicker';
import { ThumbnailGrid } from '../../../src/components/ThumbnailGrid';
import { ImageGallery } from '../../../src/components/ImageGallery';
import { ImagePickerButton } from '../../../src/components/ImagePickerButton';
import { layout } from '../../../src/ui';
import { useTheme, useUIKitTheme } from '../../../src/theme/ThemeProvider';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { useAuthStore } from '../../../src/auth/authStore';
import { subscribeToSpace, subscribeToSpaces, Space, updateSpace, deleteSpace, Checklist } from '../../../src/data/spacesService';
import { createSpaceTemplate } from '../../../src/data/spaceTemplatesService';
import { createBusinessInventoryScopeConfig, getScopeId } from '../../../src/data/scopeConfig';
import { useScopeSwitching } from '../../../src/data/useScopeSwitching';
import { useScopedListeners } from '../../../src/data/useScopedListeners';
import { subscribeToScopedItems, ScopedItem } from '../../../src/data/scopedListData';
import { updateItem } from '../../../src/data/itemsService';
import { createRepository } from '../../../src/data/repository';
import { getTextInputStyle } from '../../../src/ui/styles/forms';
import { deleteLocalMediaByUrl, saveLocalMedia } from '../../../src/offline/media';
import type { AttachmentRef } from '../../../src/offline/media';
import { useOutsideItems } from '../../../src/hooks/useOutsideItems';
import { useOptionalIsFocused } from '../../../src/hooks/useOptionalIsFocused';
import { resolveItemMove } from '../../../src/data/resolveItemMove';

type SpaceParams = {
  spaceId?: string;
};

type ItemPickerTab = 'current' | 'outside';

function randomId(prefix: string) {
  const cryptoApi = globalThis.crypto as { randomUUID?: () => string } | undefined;
  return cryptoApi?.randomUUID ? cryptoApi.randomUUID() : `${prefix}_${Date.now()}_${Math.random()}`;
}

export default function BusinessInventorySpaceDetailScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<SpaceParams>();
  const spaceId = Array.isArray(params.spaceId) ? params.spaceId[0] : params.spaceId;
  const accountId = useAccountContextStore((store) => store.accountId);
  const userId = useAuthStore((store) => store.user?.uid ?? null);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const screenTabs = useScreenTabs();
  const selectedKey = screenTabs?.selectedKey ?? 'items';
  const [space, setSpace] = useState<Space | null>(null);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [checklists, setChecklists] = useState<Checklist[]>([]);
  const [spaces, setSpaces] = useState<Space[]>([]);
  const [isPickingItems, setIsPickingItems] = useState(false);
  const [pickerTab, setPickerTab] = useState<ItemPickerTab>('current');
  const [pickerSelectedIds, setPickerSelectedIds] = useState<string[]>([]);

  // Business Inventory context: scope = 'inventory', includeInventory = false (only BI items)
  const outsideItemsHook = useOutsideItems({
    accountId,
    currentProjectId: null,
    scope: 'inventory',
    includeInventory: false,
  });
  const [bulkMode, setBulkMode] = useState(false);
  const [bulkSelectedIds, setBulkSelectedIds] = useState<string[]>([]);
  const [bulkTargetSpaceId, setBulkTargetSpaceId] = useState('');
  const [templateError, setTemplateError] = useState<string | null>(null);
  const [canSaveTemplate, setCanSaveTemplate] = useState(false);
  const [galleryVisible, setGalleryVisible] = useState(false);
  const [galleryIndex, setGalleryIndex] = useState(0);

  const isFocused = useOptionalIsFocused(true);
  // Business Inventory scope config
  const scopeConfig = useMemo(() => createBusinessInventoryScopeConfig(), []);
  const scopeId = useMemo(() => (scopeConfig ? getScopeId(scopeConfig) : null), [scopeConfig]);
  useScopeSwitching(scopeConfig, { isActive: isFocused });

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
      setIsLoading(false);
    });
    return () => unsubscribe();
  }, [accountId, spaceId]);

  useEffect(() => {
    if (!accountId) {
      setSpaces([]);
      return;
    }
    // Subscribe to BI spaces (projectId = null)
    const unsubscribe = subscribeToSpaces(accountId, null, (next) => {
      setSpaces(next);
    });
    return () => unsubscribe();
  }, [accountId]);

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

  const activePickerItems = pickerTab === 'outside' ? outsideItemsHook.items : availableItems;

  useEffect(() => {
    if (!isPickingItems || pickerTab !== 'outside') return;
    void outsideItemsHook.reload();
  }, [isPickingItems, pickerTab, outsideItemsHook]);

  const handleSaveChecklists = useCallback(
    async (next: Checklist[]) => {
      if (!accountId || !spaceId) return;
      setChecklists(next);
      await updateSpace(accountId, spaceId, { checklists: next });
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
    await updateSpace(accountId, spaceId, { images: nextImages });
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
      await updateSpace(accountId, spaceId, { images: nextImages });
    },
    [accountId, space, spaceId]
  );

  const handleSetPrimaryImage = useCallback(
    async (image: AttachmentRef) => {
      if (!accountId || !spaceId) return;
      const nextImages = (space?.images ?? []).map((img) => ({
        ...img,
        isPrimary: img.url === image.url,
      }));
      await updateSpace(accountId, spaceId, { images: nextImages });
    },
    [accountId, space?.images, spaceId]
  );

  const handleAddSelectedItems = useCallback(async () => {
    if (!accountId || pickerSelectedIds.length === 0) return;
    const selectedItems = activePickerItems.filter((item) => pickerSelectedIds.includes(item.id));

    if (pickerTab !== 'outside') {
      // Items already in BI, just assign to space
      await Promise.all(
        selectedItems.map((item) => updateItem(accountId, item.id, { spaceId }))
      );
      setPickerSelectedIds([]);
      setIsPickingItems(false);
      return;
    }

    // Items from outside (projects) need to be moved to BI first
    const missingCategory = selectedItems.filter((item) => !item.budgetCategoryId);
    if (missingCategory.length > 0) {
      Alert.alert(
        'Missing category',
        'Some items are missing a budget category and cannot be moved. Update them first and try again.'
      );
      return;
    }

    await Promise.all(
      selectedItems.map(async (item) => {
        // Block items linked to transactions
        if (item.transactionId) {
          return;
        }

        // Use resolveItemMove to handle moves to BI and space assignment
        const result = await resolveItemMove(item, {
          accountId,
          itemId: item.id,
          targetProjectId: null, // Moving to Business Inventory
          targetSpaceId: spaceId ?? null,
          budgetCategoryId: item.budgetCategoryId ?? null,
        });

        if (!result.success) {
          console.error(`Failed to move item ${item.id}: ${result.error}`);
        }
      })
    );
    setPickerSelectedIds([]);
    setIsPickingItems(false);
  }, [
    accountId,
    activePickerItems,
    pickerSelectedIds,
    pickerTab,
    spaceId,
  ]);

  const handleBulkRemove = useCallback(async () => {
    if (!accountId || bulkSelectedIds.length === 0) return;
    await Promise.all(bulkSelectedIds.map((itemId) => updateItem(accountId, itemId, { spaceId: null })));
    setBulkSelectedIds([]);
  }, [accountId, bulkSelectedIds]);

  const handleBulkMove = useCallback(async () => {
    if (!accountId || bulkSelectedIds.length === 0 || !bulkTargetSpaceId.trim()) return;
    await Promise.all(
      bulkSelectedIds.map((itemId) => updateItem(accountId, itemId, { spaceId: bulkTargetSpaceId.trim() }))
    );
    setBulkSelectedIds([]);
    setBulkTargetSpaceId('');
  }, [accountId, bulkSelectedIds, bulkTargetSpaceId]);

  const handleDelete = () => {
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
        onPress: async () => {
          await deleteSpace(accountId, spaceId);
          router.replace('/business-inventory/spaces');
        },
      },
    ]);
  };

  const handleSaveTemplate = useCallback(async () => {
    if (!accountId || !space) return;
    setTemplateError(null);
    try {
      await createSpaceTemplate(accountId, {
        name: space.name?.trim() || 'Untitled space',
        notes: space.notes ?? null,
        checklists: space.checklists ?? null,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to save template.';
      setTemplateError(message);
    }
  }, [accountId, space]);

  if (!spaceId) {
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
      title={space?.name?.trim() || 'Space'}
      tabs={[
        { key: 'items', label: 'Items', accessibilityLabel: 'Items tab' },
        { key: 'images', label: 'Images', accessibilityLabel: 'Images tab' },
        { key: 'checklists', label: 'Checklists', accessibilityLabel: 'Checklists tab' },
      ]}
      initialTabKey="items"
      backTarget="/business-inventory/spaces"
    >
      <View style={styles.container}>
        <View style={styles.actions}>
          <AppButton title="Edit" variant="secondary" onPress={() => router.push(`/business-inventory/spaces/${spaceId}/edit`)} />
          {canSaveTemplate ? (
            <AppButton title="Save as template" variant="secondary" onPress={handleSaveTemplate} />
          ) : null}
          <AppButton title="Delete" variant="secondary" onPress={handleDelete} />
        </View>
        {templateError ? (
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {templateError}
          </AppText>
        ) : null}
        {isLoading ? (
          <AppText variant="body">Loading space…</AppText>
        ) : !space ? (
          <AppText variant="body">Space not found.</AppText>
        ) : selectedKey === 'items' ? (
          <>
            <View style={styles.actions}>
              <AppButton
                title={isPickingItems ? 'Close picker' : 'Add existing items'}
                variant="secondary"
                onPress={() => {
                  setIsPickingItems((prev) => !prev);
                  setPickerTab('current');
                  setPickerSelectedIds([]);
                }}
              />
              <AppButton
                title={bulkMode ? 'Done' : 'Bulk edit'}
                variant="secondary"
                onPress={() => {
                  setBulkMode((prev) => !prev);
                  setBulkSelectedIds([]);
                }}
              />
            </View>
            {isPickingItems ? (
              <SharedItemPicker
                tabs={[
                  { value: 'current', label: 'In Business Inventory', accessibilityLabel: 'In Business Inventory tab' },
                  { value: 'outside', label: 'Outside', accessibilityLabel: 'Outside items tab' },
                ]}
                selectedTab={pickerTab}
                onTabChange={(next) => {
                  setPickerTab(next);
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
                outsideLoading={pickerTab === 'outside' ? outsideItemsHook.loading : false}
                outsideError={pickerTab === 'outside' ? outsideItemsHook.error : null}
              />
            ) : (
              <>
                {bulkMode ? (
                  <View style={styles.bulkPanel}>
                    <AppText variant="caption">{bulkSelectedIds.length} selected</AppText>
                    <TextInput
                      value={bulkTargetSpaceId}
                      onChangeText={setBulkTargetSpaceId}
                      placeholder="Move to space id"
                      placeholderTextColor={theme.colors.textSecondary}
                      style={getTextInputStyle(uiKitTheme, { padding: 10, radius: 8 })}
                    />
                    <View style={styles.actions}>
                      <AppButton
                        title="Move"
                        variant="secondary"
                        onPress={handleBulkMove}
                        disabled={!bulkTargetSpaceId.trim()}
                      />
                      <AppButton title="Remove" variant="secondary" onPress={handleBulkRemove} />
                    </View>
                  </View>
                ) : null}
                {spaceItems.length === 0 ? (
                  <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                    No items assigned.
                  </AppText>
                ) : (
                  <View style={styles.list}>
                    {spaceItems.map((item) => (
                      <Pressable
                        key={item.id}
                        onPress={() => {
                          if (bulkMode) {
                            setBulkSelectedIds((prev) =>
                              prev.includes(item.id) ? prev.filter((id) => id !== item.id) : [...prev, item.id]
                            );
                            return;
                          }
                          router.push({
                            pathname: '/items/[id]',
                            params: {
                              id: item.id,
                              scope: 'inventory',
                              backTarget: '/business-inventory/spaces',
                            },
                          });
                        }}
                        style={[
                          styles.row,
                          {
                            borderColor: uiKitTheme.border.primary,
                            backgroundColor: uiKitTheme.background.surface,
                          },
                        ]}
                      >
                        <View style={styles.rowHeader}>
                          <AppText variant="body">{item.name?.trim() || 'Item'}</AppText>
                          {bulkMode ? (
                            <AppText variant="caption">
                              {bulkSelectedIds.includes(item.id) ? 'Selected' : 'Tap to select'}
                            </AppText>
                          ) : null}
                        </View>
                        {!bulkMode ? (
                          <AppButton
                            title="Remove"
                            variant="secondary"
                            onPress={() => accountId && updateItem(accountId, item.id, { spaceId: null })}
                          />
                        ) : null}
                      </Pressable>
                    ))}
                  </View>
                )}
              </>
            )}
          </>
        ) : selectedKey === 'images' ? (
          <View style={styles.imagesContainer}>
            {space?.images && space.images.length > 0 ? (
              <>
                <ThumbnailGrid
                  images={space.images}
                  maxFiles={50}
                  size="lg"
                  tileScale={1}
                  onImagePress={(image, index) => {
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
              <View style={styles.emptyImagesState}>
                <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                  No images yet.
                </AppText>
                <ImagePickerButton
                  onFilePicked={handleAddImage}
                  maxFiles={50}
                  currentFileCount={0}
                  style={styles.imagePickerButton}
                />
              </View>
            )}
          </View>
        ) : (
          <View style={styles.checklists}>
            <AppButton
              title="Add checklist"
              onPress={() =>
                handleSaveChecklists([
                  ...checklists,
                  { id: randomId('checklist'), name: 'Checklist', items: [] },
                ])
              }
            />
            {checklists.length === 0 ? (
              <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                No checklists yet.
              </AppText>
            ) : (
              <View style={styles.list}>
                {checklists.map((checklist, checklistIndex) => (
                  <View key={checklist.id} style={styles.checklistCard}>
                    <TextInput
                      value={checklist.name}
                      onChangeText={(text) => {
                        const next = [...checklists];
                        next[checklistIndex] = { ...checklist, name: text };
                        setChecklists(next);
                      }}
                      onBlur={() => handleSaveChecklists(checklists)}
                      style={getTextInputStyle(uiKitTheme, { padding: 10, radius: 8 })}
                    />
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
                              item.isChecked && styles.checkboxChecked,
                            ]}
                          />
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
                            style={getTextInputStyle(uiKitTheme, { padding: 8, radius: 8 })}
                          />
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
        )}
      </View>

      {space?.images && space.images.length > 0 && (
        <ImageGallery
          images={space.images}
          initialIndex={galleryIndex}
          visible={galleryVisible}
          onRequestClose={() => setGalleryVisible(false)}
        />
      )}
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
  list: {
    gap: 10,
  },
  bulkPanel: {
    gap: 10,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 10,
    paddingHorizontal: 12,
  },
  rowHeader: {
    flex: 1,
    gap: 4,
  },
  imagesContainer: {
    gap: 12,
  },
  emptyImagesState: {
    gap: 16,
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
  checklistItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  checkbox: {
    width: 20,
    height: 20,
    borderWidth: 1,
    borderRadius: 4,
  },
  checkboxChecked: {
    backgroundColor: '#4c6ef5',
  },
});
