import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Image, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../../src/components/Screen';
import { useScreenTabs } from '../../../../src/components/ScreenTabs';
import { AppText } from '../../../../src/components/AppText';
import { AppButton } from '../../../../src/components/AppButton';
import { SharedItemPicker } from '../../../../src/components/SharedItemPicker';
import { layout } from '../../../../src/ui';
import { useTheme, useUIKitTheme } from '../../../../src/theme/ThemeProvider';
import { useAccountContextStore } from '../../../../src/auth/accountContextStore';
import { useAuthStore } from '../../../../src/auth/authStore';
import { subscribeToSpace, subscribeToSpaces, Space, updateSpace, deleteSpace, Checklist } from '../../../../src/data/spacesService';
import { createSpaceTemplate } from '../../../../src/data/spaceTemplatesService';
import { createProjectScopeConfig, getScopeId } from '../../../../src/data/scopeConfig';
import { useScopeSwitching } from '../../../../src/data/useScopeSwitching';
import { useScopedListeners } from '../../../../src/data/useScopedListeners';
import { subscribeToScopedItems, ScopedItem } from '../../../../src/data/scopedListData';
import { updateItem } from '../../../../src/data/itemsService';
import { createRepository } from '../../../../src/data/repository';
import { getTextInputStyle } from '../../../../src/ui/styles/forms';
import { deleteLocalMediaByUrl, resolveAttachmentState, resolveAttachmentUri, saveLocalMedia } from '../../../../src/offline/media';
import { useOutsideItems } from '../../../../src/hooks/useOutsideItems';
import { useOptionalIsFocused } from '../../../../src/hooks/useOptionalIsFocused';
import { resolveItemMove } from '../../../../src/data/resolveItemMove';

type SpaceParams = {
  projectId?: string;
  spaceId?: string;
};

type ItemPickerTab = 'current' | 'outside';

function randomId(prefix: string) {
  const cryptoApi = globalThis.crypto as { randomUUID?: () => string } | undefined;
  return cryptoApi?.randomUUID ? cryptoApi.randomUUID() : `${prefix}_${Date.now()}_${Math.random()}`;
}

export default function SpaceDetailScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<SpaceParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
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

  const outsideItemsHook = useOutsideItems({
    accountId,
    currentProjectId: projectId ?? null,
    scope: 'project',
    includeInventory: true,
  });
  const [bulkMode, setBulkMode] = useState(false);
  const [bulkSelectedIds, setBulkSelectedIds] = useState<string[]>([]);
  const [bulkTargetSpaceId, setBulkTargetSpaceId] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [localImageUri, setLocalImageUri] = useState('');
  const [templateError, setTemplateError] = useState<string | null>(null);
  const [canSaveTemplate, setCanSaveTemplate] = useState(false);

  const isFocused = useOptionalIsFocused(true);
  const scopeConfig = useMemo(() => (projectId ? createProjectScopeConfig(projectId) : null), [projectId]);
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
    if (!accountId || !projectId) {
      setSpaces([]);
      return;
    }
    const unsubscribe = subscribeToSpaces(accountId, projectId, (next) => {
      setSpaces(next);
    });
    return () => unsubscribe();
  }, [accountId, projectId]);


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

  const handleAddImage = useCallback(async () => {
    if (!accountId || !spaceId || !space) return;
    let nextUrl = imageUrl.trim();
    if (!nextUrl && localImageUri.trim()) {
      const result = await saveLocalMedia({
        localUri: localImageUri.trim(),
        mimeType: 'image/jpeg',
        ownerScope: `space:${spaceId}`,
        persistCopy: false,
      });
      nextUrl = result.attachmentRef.url;
    }
    if (!nextUrl) return;
    const hasPrimary = (space.images ?? []).some((image) => image.isPrimary);
    const nextImages = [
      ...(space.images ?? []),
      { url: nextUrl, kind: 'image' as const, isPrimary: !hasPrimary },
    ].slice(0, 20);
    setImageUrl('');
    setLocalImageUri('');
    await updateSpace(accountId, spaceId, { images: nextImages });
  }, [accountId, imageUrl, localImageUri, space, spaceId]);

  const handleRemoveImage = useCallback(
    async (url: string) => {
      if (!accountId || !spaceId || !space) return;
      const nextImages = (space.images ?? []).filter((image) => image.url !== url);
      if (url.startsWith('offline://')) {
        await deleteLocalMediaByUrl(url);
      }
      if (!nextImages.some((image) => image.isPrimary) && nextImages.length > 0) {
        nextImages[0] = { ...nextImages[0], isPrimary: true };
      }
      await updateSpace(accountId, spaceId, { images: nextImages });
    },
    [accountId, space, spaceId]
  );

  const handleSetPrimaryImage = useCallback(
    async (url: string) => {
      if (!accountId || !spaceId) return;
      const nextImages = (space?.images ?? []).map((image) => ({
        ...image,
        isPrimary: image.url === url,
      }));
      await updateSpace(accountId, spaceId, { images: nextImages });
    },
    [accountId, space?.images, spaceId]
  );

  const handleAddSelectedItems = useCallback(async () => {
    if (!accountId || pickerSelectedIds.length === 0 || !projectId) return;
    const selectedItems = activePickerItems.filter((item) => pickerSelectedIds.includes(item.id));
    
    if (pickerTab !== 'outside') {
      // Items already in the project, just assign to space
      await Promise.all(
        selectedItems.map((item) => updateItem(accountId, item.id, { spaceId }))
      );
      setPickerSelectedIds([]);
      setIsPickingItems(false);
      return;
    }

    // Items from outside need to be moved first
    const missingCategory = selectedItems.filter((item) => !item.inheritedBudgetCategoryId);
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

        // Use resolveItemMove to handle project moves and space assignment
        const result = await resolveItemMove(item, {
          accountId,
          itemId: item.id,
          targetProjectId: projectId,
          targetSpaceId: spaceId ?? null,
          inheritedBudgetCategoryId: item.inheritedBudgetCategoryId ?? null,
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
    projectId,
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
    if (!accountId || !projectId || !spaceId) return;
    const hasItems = spaceItems.length > 0;
    const message = hasItems
      ? 'This space has items. Deleting it will clear their space assignments, but items will remain.'
      : 'This will permanently delete this space.';
    Alert.alert('Delete space', message, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          await deleteSpace(accountId, spaceId);
          router.replace(`/project/${projectId}?tab=spaces`);
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
      title={space?.name?.trim() || 'Space'}
      tabs={[
        { key: 'items', label: 'Items', accessibilityLabel: 'Items tab' },
        { key: 'images', label: 'Images', accessibilityLabel: 'Images tab' },
        { key: 'checklists', label: 'Checklists', accessibilityLabel: 'Checklists tab' },
      ]}
      initialTabKey="items"
    >
      <View style={styles.container}>
        <View style={styles.actions}>
          <AppButton title="Edit" variant="secondary" onPress={() => router.push(`/project/${projectId}/spaces/${spaceId}/edit`)} />
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
                  { value: 'current', label: 'In this project', accessibilityLabel: 'In this project tab' },
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
                              scope: 'project',
                              projectId: projectId ?? '',
                              backTarget: projectId ? `/project/${projectId}?tab=spaces` : '/(tabs)',
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
          <View style={styles.list}>
            <AppText variant="body">Images</AppText>
            {space?.images?.some((image) => resolveAttachmentState(image).status !== 'uploaded') ? (
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                Uploading images…
              </AppText>
            ) : null}
            <TextInput
              value={imageUrl}
              onChangeText={setImageUrl}
              placeholder="Image URL"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 10, radius: 8 })}
            />
            <TextInput
              value={localImageUri}
              onChangeText={setLocalImageUri}
              placeholder="Local image URI (offline)"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 10, radius: 8 })}
            />
            <AppButton title="Add image" onPress={handleAddImage} />
            {space?.images?.length ? (
              <View style={styles.list}>
                {space.images.map((image) => (
                  <View key={image.url} style={styles.imageRow}>
                    {(() => {
                      const resolved = resolveAttachmentUri(image);
                      if (resolved) {
                        return <Image source={{ uri: resolved }} style={styles.spaceImage} />;
                      }
                      if (!image.url.startsWith('offline://')) {
                        return <Image source={{ uri: image.url }} style={styles.spaceImage} />;
                      }
                      return (
                        <View style={styles.spaceImage}>
                          <AppText variant="caption">Offline image</AppText>
                        </View>
                      );
                    })()}
                    <View style={styles.actions}>
                      <AppButton
                        title={image.isPrimary ? 'Primary' : 'Set primary'}
                        variant="secondary"
                        onPress={() => handleSetPrimaryImage(image.url)}
                      />
                      <AppButton title="Remove" variant="secondary" onPress={() => handleRemoveImage(image.url)} />
                    </View>
                  </View>
                ))}
              </View>
            ) : (
              <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                No images uploaded.
              </AppText>
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
  imageRow: {
    gap: 8,
  },
  spaceImage: {
    width: '100%',
    height: 160,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
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
