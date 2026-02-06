import React from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { getTextInputStyle } from '../ui';

type ListStateControlsProps = {
  search: string;
  onChangeSearch: (next: string) => void;
};

export function ListStateControls({
  search,
  onChangeSearch,
}: ListStateControlsProps) {
  const uiKitTheme = useUIKitTheme();

  return (
    <View style={styles.container}>
      <TextInput
        value={search}
        onChangeText={onChangeSearch}
        placeholder="Search"
        placeholderTextColor={uiKitTheme.input.placeholder}
        style={getTextInputStyle(uiKitTheme, {
          radius: 10,
          paddingHorizontal: 12,
          paddingVertical: 10,
        })}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
});
