import { useCallback, useEffect, useMemo, useState } from 'react';
import { Image, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { AppText } from '../components/AppText';
import { AppButton } from '../components/AppButton';
import { layout } from '../ui';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { useAccountContextStore } from '../auth/accountContextStore';
import { refreshSpaces, subscribeToSpaces, Space } from '../data/spacesService';
import { getScopeId, createProjectScopeConfig } from '../data/scopeConfig';
import { useScopedListenersMultiple } from '../data/useScopedListeners';
import { refreshScopedItems, ScopedItem, subscribeToScopedItems } from '../data/scopedListData';
import { getTextInputStyle } from '../ui/styles/forms';
import { resolveAttachmentUri } from '../offline/media';

type ProjectSpacesListProps = {
  projectId: string;
  refreshToken?: number;
};

export function ProjectSpacesList({ projectId, refreshToken }: ProjectSpacesListProps) {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [spaces, setSpaces] = useState<Space[]>([]);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [query, setQuery] = useState('');
  const [isLoading, setIsLoading] = useState(true);

  const scopeConfig = useMemo(() => createProjectScopeConfig(projectId), [projectId]);
  const scopeId = useMemo(() => getScopeId(scopeConfig), [scopeConfig]);

  useEffect(() => {
    if (!accountId) {
      setSpaces([]);
      setIsLoading(false);
    }
  }, [accountId]);

  const handleSpacesSubscribe = useCallback(() => {
    if (!accountId) {
      setSpaces([]);
      setIsLoading(false);
      return () => {};
    }
    setIsLoading(true);
    return subscribeToSpaces(accountId, projectId, (next) => {
      setSpaces(next);
      setIsLoading(false);
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

  useEffect(() => {
    if (!accountId || refreshToken == null) return;
    void refreshSpaces(accountId, projectId, 'online');
    void refreshScopedItems(accountId, scopeConfig, 'online');
  }, [accountId, projectId, refreshToken, scopeConfig]);

  const filteredSpaces = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return spaces;
    return spaces.filter((space) => {
      const name = space.name?.toLowerCase() ?? '';
      const notes = space.notes?.toLowerCase() ?? '';
      return name.includes(needle) || notes.includes(needle);
    });
  }, [query, spaces]);

  const itemCountsBySpace = useMemo(() => {
    const counts: Record<string, number> = {};
    items.forEach((item) => {
      if (!item.spaceId) return;
      counts[item.spaceId] = (counts[item.spaceId] ?? 0) + 1;
    });
    return counts;
  }, [items]);

  return (
    <View style={styles.container}>
      <AppText variant="body" style={styles.title}>
        Spaces
      </AppText>
      <TextInput
        value={query}
        onChangeText={setQuery}
        placeholder="Search spaces"
        placeholderTextColor={theme.colors.textSecondary}
        style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
      />
      <View style={styles.actions}>
        <AppButton title="Add space" onPress={() => router.push(`/project/${projectId}/spaces/new`)} />
      </View>
      {isLoading ? (
        <AppText variant="body">Loading spaces…</AppText>
      ) : filteredSpaces.length === 0 ? (
        <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
          {query.trim() ? 'No spaces found.' : 'No spaces yet.'}
        </AppText>
      ) : (
        <View style={styles.list}>
          {filteredSpaces.map((space) => (
            <Pressable
              key={space.id}
              onPress={() => router.push(`/project/${projectId}/spaces/${space.id}`)}
              style={({ pressed }) => [
                styles.row,
                {
                  borderColor: uiKitTheme.border.primary,
                  backgroundColor: uiKitTheme.background.surface,
                  opacity: pressed ? 0.8 : 1,
                },
              ]}
            >
              {space.images?.length ? (
                <Image
                  source={{ uri: resolveAttachmentUri(space.images[0]) ?? space.images[0].url }}
                  style={styles.previewImage}
                />
              ) : (
                <View style={[styles.previewImage, { backgroundColor: uiKitTheme.background.surface }]} />
              )}
              <AppText variant="body" style={styles.rowTitle}>
                {space.name?.trim() || 'Untitled space'}
              </AppText>
              <AppText variant="caption">
                {itemCountsBySpace[space.id] ?? 0} items
              </AppText>
            </Pressable>
          ))}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  title: {
    fontWeight: '600',
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
  list: {
    gap: 10,
  },
  row: {
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 14,
    gap: 8,
  },
  previewImage: {
    width: '100%',
    height: 120,
    borderRadius: 10,
  },
  rowTitle: {
    fontWeight: '600',
  },
});
