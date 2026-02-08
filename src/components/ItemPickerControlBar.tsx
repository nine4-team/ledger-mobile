import React, { useMemo } from 'react';
import { StyleSheet, TextInput, TouchableOpacity, View } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { SelectorCircle } from './SelectorCircle';
import { AppButton } from './AppButton';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { BUTTON_BORDER_RADIUS } from '../ui';

type ItemPickerControlBarProps = {
  search: string;
  onChangeSearch: (value: string) => void;
  searchPlaceholder?: string;
  onSelectAll: () => void;
  allSelected: boolean;
  hasItems: boolean;
  onAddSelected: () => void;
  selectedCount: number;
  addButtonLabel?: string;
};

export function ItemPickerControlBar({
  search,
  onChangeSearch,
  searchPlaceholder = 'Search items',
  onSelectAll,
  allSelected,
  hasItems,
  onAddSelected,
  selectedCount,
  addButtonLabel = 'Add',
}: ItemPickerControlBarProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const themed = useMemo(
    () =>
      StyleSheet.create({
        container: {
          backgroundColor: 'transparent',
          borderColor: uiKitTheme.border.secondary,
        },
        selectButton: {
          backgroundColor: uiKitTheme.button.secondary.background,
          borderColor: uiKitTheme.border.primary,
        },
        searchInput: {
          backgroundColor: uiKitTheme.background.surface,
          borderColor: uiKitTheme.border.primary,
          color: theme.colors.text,
        },
      }),
    [theme, uiKitTheme]
  );

  return (
    <View style={[styles.container, themed.container]}>
      <View style={styles.controlRow}>
        {/* Select All Button */}
        <TouchableOpacity
          disabled={!hasItems}
          onPress={() => {
            if (!hasItems) return;
            onSelectAll();
          }}
          style={[
            styles.selectButton,
            themed.selectButton,
            !hasItems && styles.selectButtonDisabled,
          ]}
          accessibilityRole="checkbox"
          accessibilityState={{ checked: allSelected }}
          accessibilityLabel={allSelected ? 'Deselect all' : 'Select all visible items'}
        >
          <SelectorCircle selected={allSelected} indicator="check" />
        </TouchableOpacity>

        {/* Search Input */}
        <TextInput
          value={search}
          onChangeText={onChangeSearch}
          placeholder={searchPlaceholder}
          placeholderTextColor={theme.colors.textSecondary}
          style={[styles.searchInput, themed.searchInput]}
          accessibilityLabel="Search items"
        />

        {/* Add Selected Button */}
        <AppButton
          title={`${addButtonLabel} (${selectedCount})`}
          variant="primary"
          onPress={onAddSelected}
          disabled={selectedCount === 0}
          style={styles.addButton}
          leftIcon={
            <MaterialIcons
              name="add"
              size={18}
              color={uiKitTheme.button.primary.text}
            />
          }
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderRadius: 16,
    borderWidth: 1,
    padding: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  controlRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  selectButton: {
    borderRadius: BUTTON_BORDER_RADIUS,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 40,
    minWidth: 40,
    paddingVertical: 10,
    paddingHorizontal: 10,
    borderWidth: 1,
  },
  selectButtonDisabled: {
    opacity: 0.5,
  },
  searchInput: {
    flex: 1,
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 10,
    paddingVertical: 10,
    fontSize: 15,
  },
  addButton: {
    minHeight: 40,
    paddingVertical: 10,
    paddingHorizontal: 16,
  },
});
