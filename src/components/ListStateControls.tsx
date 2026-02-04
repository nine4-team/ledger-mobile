import React from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { AppButton } from './AppButton';
import { AppText } from './AppText';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';

type ListStateControlsProps = {
  title: string;
  search: string;
  onChangeSearch: (next: string) => void;
  sortLabel: string;
  onToggleSort: () => void;
};

export function ListStateControls({
  title,
  search,
  onChangeSearch,
  sortLabel,
  onToggleSort,
}: ListStateControlsProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  return (
    <View style={styles.container}>
      <AppText variant="body" style={styles.title}>
        {title}
      </AppText>
      <TextInput
        value={search}
        onChangeText={onChangeSearch}
        placeholder="Search"
        placeholderTextColor={theme.colors.textSecondary}
        style={[
          styles.input,
          { borderColor: uiKitTheme.border.primary, color: theme.colors.text },
        ]}
      />
      <View style={styles.sortRow}>
        <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
          Sort: {sortLabel}
        </AppText>
        <AppButton title="Toggle sort" variant="secondary" onPress={onToggleSort} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  title: {
    fontWeight: '600',
  },
  input: {
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  sortRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
});
