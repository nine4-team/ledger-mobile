import React from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { AppButton } from './AppButton';
import { AppText } from './AppText';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';

type ListStateControlsProps = {
  search: string;
  onChangeSearch: (next: string) => void;
};

export function ListStateControls({
  search,
  onChangeSearch,
}: ListStateControlsProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  return (
    <View style={styles.container}>
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
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  input: {
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
});
