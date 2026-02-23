import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';

import { AppText } from '../AppText';
import { useTheme, useUIKitTheme } from '../../theme/ThemeProvider';
import { useAccountContextStore } from '../../auth/accountContextStore';
import { getTextInputStyle } from '../../ui/styles/forms';
import { createSpace, subscribeToSpaces, type Space } from '../../data/spacesService';

export interface SpacePickerListProps {
  projectId: string | null;
  selectedId: string | null;
  onSelect: (spaceId: string | null) => void;
  maxHeight?: number;
  emptyMessage?: string;
  allowCreate?: boolean;
}

export function SpacePickerList({
  projectId,
  selectedId,
  onSelect,
  maxHeight = 200,
  emptyMessage = 'No spaces available',
  allowCreate = false,
}: SpacePickerListProps) {
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const [spaces, setSpaces] = useState<Space[]>([]);
  const [searchText, setSearchText] = useState('');

  useEffect(() => {
    if (!accountId) {
      setSpaces([]);
      return () => {};
    }
    return subscribeToSpaces(accountId, projectId, (next) => {
      setSpaces(next);
    });
  }, [accountId, projectId]);

  const filtered = useMemo(() => {
    const sorted = [...spaces].sort((a, b) => a.name.localeCompare(b.name));
    if (!searchText.trim()) return sorted;
    const lower = searchText.toLowerCase();
    return sorted.filter((s) => s.name.toLowerCase().includes(lower));
  }, [spaces, searchText]);

  const hasExactMatch = useMemo(() => {
    const trimmed = searchText.trim();
    if (!trimmed) return false;
    return filtered.some((s) => s.name.toLowerCase() === trimmed.toLowerCase());
  }, [filtered, searchText]);

  const showCreateOption = allowCreate && searchText.trim() && !hasExactMatch;

  const handleCreate = useCallback(() => {
    if (!accountId || !searchText.trim()) return;
    const newId = createSpace(accountId, {
      name: searchText.trim(),
      notes: '',
      projectId,
    });
    onSelect(newId);
    setSearchText('');
  }, [accountId, searchText, projectId, onSelect]);

  const showSearch = spaces.length > 5 || allowCreate;

  return (
    <View>
      {showSearch && (
        <View style={styles.searchRow}>
          <MaterialIcons
            name="search"
            size={18}
            color={uiKitTheme.text.secondary}
          />
          <TextInput
            value={searchText}
            onChangeText={setSearchText}
            placeholder={allowCreate ? 'Search or create...' : 'Search spaces...'}
            placeholderTextColor={theme.colors.textSecondary}
            style={[
              styles.searchInput,
              getTextInputStyle(uiKitTheme, { padding: 8, radius: 8 }),
            ]}
            autoCapitalize="words"
            autoCorrect={false}
          />
        </View>
      )}

      <ScrollView style={{ maxHeight }}>
        <View style={styles.list}>
          {/* None option to clear */}
          {selectedId !== null && (
            <Pressable
              onPress={() => onSelect(null)}
              style={[
                styles.option,
                {
                  borderColor: uiKitTheme.border.secondary,
                  backgroundColor: 'transparent',
                },
              ]}
            >
              <View
                style={[
                  styles.radio,
                  { borderColor: uiKitTheme.border.secondary },
                ]}
              />
              <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                None
              </AppText>
            </Pressable>
          )}

          {/* Create option */}
          {showCreateOption && (
            <Pressable
              onPress={handleCreate}
              style={[
                styles.option,
                {
                  borderColor: theme.colors.primary,
                  backgroundColor: 'transparent',
                },
              ]}
            >
              <MaterialIcons
                name="add-circle-outline"
                size={20}
                color={theme.colors.primary}
              />
              <AppText variant="body" style={{ color: theme.colors.primary }}>
                Create "{searchText.trim()}"
              </AppText>
            </Pressable>
          )}

          {/* Space list */}
          {filtered.length > 0 ? (
            filtered.map((space) => {
              const isSelected = selectedId === space.id;
              return (
                <Pressable
                  key={space.id}
                  onPress={() => onSelect(space.id)}
                  style={[
                    styles.option,
                    {
                      borderColor: isSelected
                        ? theme.colors.primary
                        : uiKitTheme.border.secondary,
                      backgroundColor: isSelected
                        ? uiKitTheme.background.surface
                        : 'transparent',
                    },
                  ]}
                >
                  <View
                    style={[
                      styles.radio,
                      {
                        borderColor: isSelected
                          ? theme.colors.primary
                          : uiKitTheme.border.secondary,
                      },
                    ]}
                  >
                    {isSelected && (
                      <View
                        style={[
                          styles.radioFill,
                          { backgroundColor: theme.colors.primary },
                        ]}
                      />
                    )}
                  </View>
                  <AppText variant="body">{space.name}</AppText>
                </Pressable>
              );
            })
          ) : searchText.trim() && !showCreateOption ? (
            <AppText variant="caption">{emptyMessage}</AppText>
          ) : !searchText.trim() && spaces.length === 0 ? (
            <AppText variant="caption">{emptyMessage}</AppText>
          ) : null}
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  searchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 8,
  },
  searchInput: {
    flex: 1,
    minHeight: 36,
  },
  list: {
    gap: 6,
  },
  option: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 14,
    borderRadius: 10,
    borderWidth: 1,
    gap: 12,
  },
  radio: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  radioFill: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
});
