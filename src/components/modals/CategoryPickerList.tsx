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
      <View style={styles.list}>
        {sorted.map(([id, cat]) => {
          const isSelected = selectedId === id;
          return (
            <Pressable
              key={id}
              onPress={() => onSelect(id)}
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
              <AppText variant="body">{cat.name}</AppText>
            </Pressable>
          );
        })}
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
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
