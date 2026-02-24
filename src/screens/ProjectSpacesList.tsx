import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, RefreshControl, StyleSheet, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { AppText } from '../components/AppText';
import { AppButton } from '../components/AppButton';
import { AppScrollView } from '../components/AppScrollView';
import { SpaceCard } from '../components/SpaceCard';
import { SpaceCardSkeleton } from '../components/SpaceCardSkeleton';
import { ErrorRetryView } from '../components/ErrorRetryView';
import { NetworkStatusBanner } from '../components/NetworkStatusBanner';
import { useScreenRefresh } from '../components/Screen';
import { BottomSheetMenuList } from '../components/BottomSheetMenuList';
import { EditSpaceDetailsModal } from '../components/modals/EditSpaceDetailsModal';
import type { AnchoredMenuItem } from '../components/AnchoredMenuList';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { useAccountContextStore } from '../auth/accountContextStore';
import { useAuthStore } from '../auth/authStore';
import { refreshSpaces, subscribeToSpaces, Space, updateSpace, deleteSpace } from '../data/spacesService';
import { createSpaceTemplate } from '../data/spaceTemplatesService';
import { createRepository } from '../data/repository';
import { getScopeId, createProjectScopeConfig } from '../data/scopeConfig';
import { useScopedListenersMultiple } from '../data/useScopedListeners';
import { refreshScopedItems, ScopedItem, subscribeToScopedItems } from '../data/scopedListData';
import { getTextInputStyle } from '../ui/styles/forms';
import { useDebouncedValue } from '../hooks/useDebouncedValue';
import { useNetworkStatus } from '../hooks/useNetworkStatus';
import { showToast } from '../components/toastStore';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';

type ProjectSpacesListProps = {
  projectId: string;
  refreshToken?: number;
};

export function ProjectSpacesList({ projectId, refreshToken }: ProjectSpacesListProps) {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const userId = useAuthStore((store) => store.user?.uid ?? null);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [spaces, setSpaces] = useState<Space[]>([]);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [query, setQuery] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const screenRefresh = useScreenRefresh();
  const debouncedQuery = useDebouncedValue(query, 350);
  const networkStatus = useNetworkStatus();

  // Kebab menu state
  const [menuSpace, setMenuSpace] = useState<Space | null>(null);
  const [menuVisible, setMenuVisible] = useState(false);
  const [editNameVisible, setEditNameVisible] = useState(false);
  const [canSaveTemplate, setCanSaveTemplate] = useState(false);

  const scopeConfig = useMemo(() => createProjectScopeConfig(projectId), [projectId]);
  const scopeId = useMemo(() => getScopeId(scopeConfig), [scopeConfig]);

  useEffect(() => {
    if (!accountId) {
      setSpaces([]);
      setIsLoading(false);
      setError(null);
    }
  }, [accountId]);

  const handleSpacesSubscribe = useCallback(() => {
    if (!accountId) {
      setSpaces([]);
      setIsLoading(false);
      setError(null);
      return () => {};
    }
    setIsLoading(true);
    setError(null);
    return subscribeToSpaces(accountId, projectId, (next) => {
      setSpaces(next);
      setIsLoading(false);
      setError(null);
    });
  }, [accountId, projectId]);

  const handleItemsSubscribe = useCallback(() => {
    if (!accountId) {
      setItems([]);
      return () => {};
    }
    return subscribeToScopedItems(accountId, scopeConfig, (next) => {
      setItems(next);
    });
  }, [accountId, scopeConfig]);

  useScopedListenersMultiple(scopeId, [handleSpacesSubscribe, handleItemsSubscribe]);

  const handleRetry = useCallback(() => {
    if (!accountId) return;
    setError(null);
    setIsLoading(true);
    refreshSpaces(accountId, projectId, 'online')
      .then(() => {
        setError(null);
      })
      .catch((err) => {
        setError(err instanceof Error ? err.message : 'Failed to load spaces');
        setIsLoading(false);
      });
    void refreshScopedItems(accountId, scopeConfig, 'online');
  }, [accountId, projectId, scopeConfig]);

  useEffect(() => {
    if (!accountId || refreshToken == null) return;
    void refreshSpaces(accountId, projectId, 'online').catch((err) => {
      setError(err instanceof Error ? err.message : 'Failed to load spaces');
    });
    void refreshScopedItems(accountId, scopeConfig, 'online');
  }, [accountId, projectId, refreshToken, scopeConfig]);

  // Use debounced query for filtering to improve performance
  const filteredSpaces = useMemo(() => {
    const needle = debouncedQuery.trim().toLowerCase();
    if (!needle) return spaces;
    return spaces.filter((space) => {
      const name = space.name?.toLowerCase() ?? '';
      const notes = space.notes?.toLowerCase() ?? '';
      return name.includes(needle) || notes.includes(needle);
    });
  }, [debouncedQuery, spaces]);

  // Memoize item counts calculation to avoid recalculating on every render
  const itemCountsBySpace = useMemo(() => {
    const counts: Record<string, number> = {};
    items.forEach((item) => {
      if (!item.spaceId) return;
      counts[item.spaceId] = (counts[item.spaceId] ?? 0) + 1;
    });
    return counts;
  }, [items]);

  // Memoize grid items with proper aspect ratio
  const gridItems = useMemo(() => {
    return filteredSpaces.map((space) => {
      const primaryImage = space.images?.find((img) => img.isPrimary) ?? space.images?.[0] ?? null;
      return {
        id: space.id,
        name: space.name,
        itemCount: itemCountsBySpace[space.id] ?? 0,
        primaryImage,
        checklists: space.checklists ?? null,
        notes: space.notes,
      };
    });
  }, [filteredSpaces, itemCountsBySpace]);

  const handleSpacePress = useCallback(
    (spaceId: string) => {
      router.push(`/project/${projectId}/spaces/${spaceId}`);
    },
    [router, projectId]
  );

  const handleAddSpace = useCallback(() => {
    router.push(`/project/${projectId}/spaces/new`);
  }, [router, projectId]);

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

  const handleMenuPress = useCallback((space: Space) => {
    setMenuSpace(space);
    setMenuVisible(true);
  }, []);

  const handleCloseMenu = useCallback(() => {
    setMenuVisible(false);
  }, []);

  const handleEditName = useCallback((name: string) => {
    if (!accountId || !menuSpace) return;
    updateSpace(accountId, menuSpace.id, { name });
    setEditNameVisible(false);
    showToast('Space name updated');
  }, [accountId, menuSpace]);

  const handleSaveTemplate = useCallback(() => {
    if (!accountId || !menuSpace) return;
    createSpaceTemplate(accountId, {
      name: menuSpace.name?.trim() || 'Untitled space',
      notes: menuSpace.notes ?? null,
      checklists: menuSpace.checklists ?? null,
    });
    Alert.alert('Success', 'Space saved as template successfully');
  }, [accountId, menuSpace]);

  const handleDeleteSpace = useCallback(() => {
    if (!accountId || !menuSpace) return;
    const spaceItems = items.filter((i) => i.spaceId === menuSpace.id);
    const itemCount = spaceItems.length;
    const message = itemCount > 0
      ? `This space has ${itemCount} item${itemCount === 1 ? '' : 's'}. Items will not be deleted, but their space assignment will be cleared.`
      : 'Are you sure you want to delete this space?';
    Alert.alert('Delete Space', message, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          deleteSpace(accountId, menuSpace.id);
          setMenuVisible(false);
        },
      },
    ]);
  }, [accountId, menuSpace, items]);

  const spaceMenuItems: AnchoredMenuItem[] = useMemo(() => {
    const menuItems: AnchoredMenuItem[] = [
      {
        key: 'edit',
        label: 'Edit Name',
        icon: 'edit',
        onPress: () => { handleCloseMenu(); setEditNameVisible(true); },
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
      onPress: handleDeleteSpace,
    });
    return menuItems;
  }, [canSaveTemplate, handleCloseMenu, handleDeleteSpace, handleSaveTemplate]);

  return (
    <>
      <AppScrollView
        style={styles.scroll}
        contentContainerStyle={[styles.container, styles.scrollContent]}
        refreshControl={
          screenRefresh ? (
            <RefreshControl refreshing={screenRefresh.refreshing} onRefresh={screenRefresh.onRefresh} />
          ) : undefined
        }
      >
        <View style={styles.controlSection}>
          <View style={[styles.controlBar, { backgroundColor: uiKitTheme.background.chrome, borderColor: uiKitTheme.border.secondary }]}>
            <TextInput
              value={query}
              onChangeText={setQuery}
              placeholder="Search spaces"
              placeholderTextColor={theme.colors.textSecondary}
              style={[getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 }), styles.searchInput]}
              accessibilityLabel="Search spaces"
              accessibilityHint="Type to filter spaces by name or notes"
              returnKeyType="search"
            />
            <AppButton
              title="Add"
              variant="primary"
              onPress={handleAddSpace}
              leftIcon={<MaterialIcons name="add" size={18} color={uiKitTheme.button.primary.text} />}
              accessibilityLabel="Add new space"
              style={styles.addButton}
            />
          </View>
        </View>

        {error ? (
          <ErrorRetryView
            message={error}
            onRetry={handleRetry}
            isOffline={!networkStatus.isOnline}
          />
        ) : isLoading ? (
          <View style={styles.list}>
            {Array.from({ length: 4 }).map((_, index) => (
              <SpaceCardSkeleton key={index} />
            ))}
          </View>
        ) : filteredSpaces.length === 0 ? (
          <View style={styles.emptyState}>
            <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
              {query.trim() ? 'No spaces found.' : 'No spaces yet.'}
            </AppText>
            {!query.trim() && (
              <AppText variant="caption" style={{ color: theme.colors.textSecondary, textAlign: 'center' }}>
                Create your first space to organize items by location
              </AppText>
            )}
          </View>
        ) : (
          <View style={styles.list}>
            {gridItems.map((item) => {
              const space = filteredSpaces.find((s) => s.id === item.id);
              return (
                <SpaceCard
                  key={item.id}
                  name={item.name}
                  itemCount={item.itemCount}
                  primaryImage={item.primaryImage}
                  checklists={item.checklists}
                  notes={item.notes}
                  onPress={() => handleSpacePress(item.id)}
                  onMenuPress={space ? () => handleMenuPress(space) : undefined}
                />
              );
            })}
          </View>
        )}
      </AppScrollView>

      {!networkStatus.isOnline && <NetworkStatusBanner />}

      <BottomSheetMenuList
        visible={menuVisible}
        onRequestClose={handleCloseMenu}
        items={spaceMenuItems}
        title={menuSpace?.name?.trim() || 'Space'}
        showLeadingIcons={true}
      />

      <EditSpaceDetailsModal
        visible={editNameVisible}
        onRequestClose={() => setEditNameVisible(false)}
        initialName={menuSpace?.name?.trim() ?? ''}
        onSave={handleEditName}
      />
    </>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  container: {
    gap: 16,
  },
  scrollContent: {
    flexGrow: 1,
    paddingBottom: 24,
  },
  controlSection: {
    gap: 0,
  },
  controlBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    padding: 8,
    borderRadius: 16,
    borderWidth: 1,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  searchInput: {
    flex: 1,
  },
  addButton: {
    minHeight: 40,
    paddingVertical: 10,
    paddingHorizontal: 16,
  },
  list: {
    gap: 12,
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 32,
    gap: 8,
  },
});
