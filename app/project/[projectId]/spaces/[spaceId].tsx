import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Image, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../../src/components/Screen';
import { useScreenTabs } from '../../../../src/components/ScreenTabs';
import { AppText } from '../../../../src/components/AppText';
import { AppButton } from '../../../../src/components/AppButton';
import { ItemCard } from '../../../../src/components/ItemCard';
import { GroupedItemCard } from '../../../../src/components/GroupedItemCard';
import { SegmentedControl } from '../../../../src/components/SegmentedControl';
import { layout } from '../../../../src/ui';
import { useTheme, useUIKitTheme } from '../../../../src/theme/ThemeProvider';
import { useAccountContextStore } from '../../../../src/auth/accountContextStore';
import { useAuthStore } from '../../../../src/auth/authStore';
import { subscribeToSpace, subscribeToSpaces, Space, updateSpace, deleteSpace, Checklist } from '../../../../src/data/spacesService';
import { createSpaceTemplate } from '../../../../src/data/spaceTemplatesService';
import { createProjectScopeConfig, getScopeId } from '../../../../src/data/scopeConfig';
import { useScopeSwitching } from '../../../../src/data/useScopeSwitching';
import { useScopedListeners } from '../../../../src/data/useScopedListeners';
import { subscribeToScopedItems, ScopedItem, subscribeToProjects, ProjectSummary } from '../../../../src/data/scopedListData';
import { Item, listItemsByProject, subscribeToItem, updateItem } from '../../../../src/data/itemsService';
import { createRepository } from '../../../../src/data/repository';
import { getTextInputStyle } from '../../../../src/ui/styles/forms';
import { deleteLocalMediaByUrl, resolveAttachmentState, resolveAttachmentUri, saveLocalMedia } from '../../../../src/offline/media';
import {
  requestBusinessToProjectPurchase,
  requestProjectToProjectMove,
} from '../../../../src/data/inventoryOperations';

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
  const [pickerQuery, setPickerQuery] = useState('');
  const [pickerSelectedIds, setPickerSelectedIds] = useState<string[]>([]);
  const [outsideItems, setOutsideItems] = useState<Item[]>([]);
  const [outsideLoading, setOutsideLoading] = useState(false);
  const [outsideError, setOutsideError] = useState<string | null>(null);
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [bulkMode, setBulkMode] = useState(false);
  const [bulkSelectedIds, setBulkSelectedIds] = useState<string[]>([]);
  const [bulkTargetSpaceId, setBulkTargetSpaceId] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [localImageUri, setLocalImageUri] = useState('');
  const [templateError, setTemplateError] = useState<string | null>(null);
  const [canSaveTemplate, setCanSaveTemplate] = useState(false);

  const isFocused = useIsFocused();
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
    if (!accountId) {
      setProjects([]);
      return;
    }
    return subscribeToProjects(accountId, (next) => setProjects(next));
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
  const filteredAvailableItems = useMemo(() => {
    const needle = pickerQuery.trim().toLowerCase();
    if (!needle) return availableItems;
    return availableItems.filter((item) => {
      const label = item.name?.toLowerCase() ?? item.description?.toLowerCase() ?? '';
      return label.includes(needle);
    });
  }, [availableItems, pickerQuery]);

  const filteredOutsideItems = useMemo(() => {
    const needle = pickerQuery.trim().toLowerCase();
    if (!needle) return outsideItems;
    return outsideItems.filter((item) => {
      const label = item.name?.toLowerCase() ?? item.description?.toLowerCase() ?? '';
      return label.includes(needle);
    });
  }, [outsideItems, pickerQuery]);

  const activePickerItems = pickerTab === 'outside' ? filteredOutsideItems : filteredAvailableItems;

  const pickerGroups = useMemo(() => {
    const groups = new Map<string, ScopedItem[]>();
    activePickerItems.forEach((item) => {
      const label = item.name?.trim() || item.description?.trim() || 'Item';
      const key = label.toLowerCase();
      const list = groups.get(key) ?? [];
      list.push(item as ScopedItem);
      groups.set(key, list);
    });
    return Array.from(groups.entries());
  }, [activePickerItems]);

  const loadOutsideItems = useCallback(async () => {
    if (!accountId || !projectId) return;
    setOutsideLoading(true);
    setOutsideError(null);
    try {
      const otherProjects = projects.filter((project) => project.id !== projectId);
      const requests = [
        listItemsByProject(accountId, null, { mode: 'offline' }),
        ...otherProjects.map((project) => listItemsByProject(accountId, project.id, { mode: 'offline' })),
      ];
      const results = await Promise.all(requests);
      const flattened = results.flat();
      const unique = new Map(flattened.map((item) => [item.id, item]));
      setOutsideItems(Array.from(unique.values()));
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to load outside items.';
      setOutsideError(message);
    } finally {
      setOutsideLoading(false);
    }
  }, [accountId, projectId, projects]);

  useEffect(() => {
    if (!isPickingItems || pickerTab !== 'outside') return;
    void loadOutsideItems();
  }, [isPickingItems, pickerTab, loadOutsideItems]);

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
      { url: nextUrl, kind: 'image', isPrimary: !hasPrimary },
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

  const waitForScopeThenAssignSpace = useCallback(
    (itemId: string, targetProjectId: string | null, targetSpaceId: string | null) =>
      new Promise<void>((resolve) => {
        if (!accountId) {
          resolve();
          return;
        }
        let resolved = false;
        let unsubscribe: () => void = () => {};
        const timeoutId = setTimeout(() => {
          if (resolved) return;
          resolved = true;
          unsubscribe();
          resolve();
        }, 20000);
        unsubscribe = subscribeToItem(accountId, itemId, (item) => {
          if (!item || resolved) return;
          const matchesScope = targetProjectId ? item.projectId === targetProjectId : item.projectId == null;
          if (!matchesScope) return;
          resolved = true;
          clearTimeout(timeoutId);
          unsubscribe();
          void updateItem(accountId, itemId, { spaceId: targetSpaceId });
          resolve();
        });
      }),
    [accountId, spaceId]
  );

  const handleAddSelectedItems = useCallback(async () => {
    if (!accountId || pickerSelectedIds.length === 0 || !projectId) return;
    const sourceItems = pickerTab === 'outside' ? filteredOutsideItems : filteredAvailableItems;
    const selectedItems = sourceItems.filter((item) => pickerSelectedIds.includes(item.id));
    if (pickerTab !== 'outside') {
      await Promise.all(
        selectedItems.map((item) => updateItem(accountId, item.id, { spaceId }))
      );
      setPickerSelectedIds([]);
      setIsPickingItems(false);
      return;
    }

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
        if (item.transactionId) {
          return;
        }
        if (item.projectId === projectId) {
          await updateItem(accountId, item.id, { spaceId });
          return;
        }
        if (item.projectId == null) {
          await requestBusinessToProjectPurchase({
            accountId,
            targetProjectId: projectId,
            inheritedBudgetCategoryId: item.inheritedBudgetCategoryId ?? null,
            items: [{ id: item.id, projectId: item.projectId ?? null, transactionId: item.transactionId ?? null }],
          });
          await waitForScopeThenAssignSpace(item.id, projectId, spaceId ?? null);
          return;
        }
        await requestProjectToProjectMove({
          accountId,
          sourceProjectId: item.projectId,
          targetProjectId: projectId,
          inheritedBudgetCategoryId: item.inheritedBudgetCategoryId ?? null,
          items: [{ id: item.id, projectId: item.projectId ?? null, transactionId: item.transactionId ?? null }],
        });
        await waitForScopeThenAssignSpace(item.id, projectId, spaceId ?? null);
      })
    );
    setPickerSelectedIds([]);
    setIsPickingItems(false);
  }, [
    accountId,
    filteredAvailableItems,
    filteredOutsideItems,
    pickerSelectedIds,
    pickerTab,
    projectId,
    spaceId,
    waitForScopeThenAssignSpace,
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
              <View style={styles.pickerPanel}>
                <SegmentedControl
                  value={pickerTab}
                  options={[
                    { value: 'current', label: 'In this project', accessibilityLabel: 'In this project tab' },
                    { value: 'outside', label: 'Outside', accessibilityLabel: 'Outside items tab' },
                  ]}
                  onChange={(next) => {
                    setPickerTab(next);
                    setPickerSelectedIds([]);
                  }}
                  accessibilityLabel="Item picker tabs"
                />
                <TextInput
                  value={pickerQuery}
                  onChangeText={setPickerQuery}
                  placeholder="Search items"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 10, radius: 8 })}
                />
                <View style={styles.actions}>
                  <AppButton
                    title="Select all visible"
                    variant="secondary"
                    onPress={() =>
                      setPickerSelectedIds(
                        activePickerItems
                          .filter((item) => item.spaceId !== spaceId && !item.transactionId)
                          .map((item) => item.id)
                      )
                    }
                  />
                  <AppButton
                    title={`Add Selected (${pickerSelectedIds.length})`}
                    onPress={handleAddSelectedItems}
                    disabled={pickerSelectedIds.length === 0}
                  />
                </View>
                <View style={styles.list}>
                  {pickerGroups.map(([label, groupItems]) => {
                    const eligibleIds = groupItems
                      .filter((item) => item.spaceId !== spaceId && !item.transactionId)
                      .map((item) => item.id);
                    const groupAllSelected =
                      eligibleIds.length > 0 && eligibleIds.every((itemId) => pickerSelectedIds.includes(itemId));

                    if (groupItems.length > 1) {
                      return (
                        <GroupedItemCard
                          key={label}
                          summary={{ description: label }}
                          countLabel={`×${groupItems.length}`}
                          items={groupItems.map((item) => {
                            const description = item.name?.trim() || item.description || 'Item';
                            const locked = item.spaceId === spaceId || !!item.transactionId;
                            const statusLabel =
                              item.spaceId === spaceId ? 'Already here' : item.transactionId ? 'Linked' : undefined;
                            const selected = pickerSelectedIds.includes(item.id);

                            return {
                              description,
                              selected,
                              onSelectedChange: locked
                                ? undefined
                                : (next) =>
                                    setPickerSelectedIds((prev) => {
                                      if (next) return prev.includes(item.id) ? prev : [...prev, item.id];
                                      return prev.filter((entry) => entry !== item.id);
                                    }),
                              onPress: locked
                                ? undefined
                                : () =>
                                    setPickerSelectedIds((prev) =>
                                      prev.includes(item.id)
                                        ? prev.filter((entry) => entry !== item.id)
                                        : [...prev, item.id]
                                    ),
                              statusLabel,
                              style: locked ? { opacity: 0.6 } : undefined,
                            };
                          })}
                          selected={groupAllSelected}
                          onSelectedChange={
                            eligibleIds.length === 0
                              ? undefined
                              : (next) => {
                                  setPickerSelectedIds((prev) => {
                                    if (next) return Array.from(new Set([...prev, ...eligibleIds]));
                                    const remove = new Set(eligibleIds);
                                    return prev.filter((entry) => !remove.has(entry));
                                  });
                                }
                          }
                        />
                      );
                    }

                    const [only] = groupItems;
                    const description = only.name?.trim() || only.description || 'Item';
                    const locked = only.spaceId === spaceId || !!only.transactionId;
                    const selected = pickerSelectedIds.includes(only.id);
                    const statusLabel =
                      only.spaceId === spaceId ? 'Already here' : only.transactionId ? 'Linked' : undefined;

                    return (
                      <ItemCard
                        key={only.id}
                        description={description}
                        selected={selected}
                        onSelectedChange={locked ? undefined : (next) => {
                          setPickerSelectedIds((prev) => {
                            if (next) return prev.includes(only.id) ? prev : [...prev, only.id];
                            return prev.filter((entry) => entry !== only.id);
                          });
                        }}
                        onPress={locked ? undefined : () => {
                          setPickerSelectedIds((prev) =>
                            prev.includes(only.id) ? prev.filter((entry) => entry !== only.id) : [...prev, only.id]
                          );
                        }}
                        statusLabel={statusLabel}
                        style={locked ? { opacity: 0.6 } : undefined}
                      />
                    );
                  })}
                  {pickerGroups.length === 0 ? (
                    <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                      No items available.
                    </AppText>
                  ) : null}
                  {pickerTab === 'outside' && outsideLoading ? (
                    <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                      Loading outside items…
                    </AppText>
                  ) : null}
                  {pickerTab === 'outside' && outsideError ? (
                    <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                      {outsideError}
                    </AppText>
                  ) : null}
                </View>
              </View>
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
                          <AppText variant="body">{item.name?.trim() || item.description || 'Item'}</AppText>
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
                    {resolveAttachmentUri(image) ? (
                      <Image source={{ uri: resolveAttachmentUri(image) ?? image.url }} style={styles.spaceImage} />
                    ) : (
                      <View style={styles.spaceImage}>
                        <AppText variant="caption">Offline image</AppText>
                      </View>
                    )}
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
  pickerPanel: {
    gap: 12,
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
