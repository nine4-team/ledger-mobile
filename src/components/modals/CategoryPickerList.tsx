import React, { useMemo } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { AppText } from '../AppText';
import { useTheme, useUIKitTheme } from '../../theme/ThemeProvider';

export interface CategoryPickerListProps {
  categories: Record<string, { name: string }>;
  selectedId: string | null;
  onSelect: (categoryId: string) => void;
  maxHeight?: number;
  emptyMessage?: string;
}

export function CategoryPickerList({
  categories,
  selectedId,
  onSelect,
  maxHeight = 200,
  emptyMessage = 'No categories available',
}: CategoryPickerListProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const sorted = useMemo(
    () => Object.entries(categories).sort(([, a], [, b]) => a.name.localeCompare(b.name)),
    [categories],
  );

  if (sorted.length === 0) {
    return <AppText variant="caption">{emptyMessage}</AppText>;
  }

  return (
    <ScrollView style={{ maxHeight }}>
      {sorted.map(([id, cat]) => (
        <Pressable
          key={id}
          onPress={() => onSelect(id)}
          style={[
            styles.option,
            selectedId === id && { backgroundColor: uiKitTheme.background.surface },
          ]}
        >
          <AppText variant="body">{cat.name}</AppText>
          {selectedId === id && (
            <AppText variant="body" style={{ color: theme.colors.primary }}>✓</AppText>
          )}
        </Pressable>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  option: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: 8,
  },
});
