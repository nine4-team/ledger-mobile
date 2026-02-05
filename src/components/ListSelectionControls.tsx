import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { AppText } from './AppText';
import { SelectorCircle } from './SelectorCircle';
import { useTheme } from '../theme/ThemeProvider';

type ListSelectionInfoProps = {
  text: string;
  onPress?: () => void;
};

type ListSelectAllRowProps = {
  disabled: boolean;
  onPress: () => void;
  checked: boolean;
  label?: string;
};

export function getSortFilterText(sortLabel: string, filterLabel: string) {
  return `Sort: ${sortLabel} • Filter: ${filterLabel}`;
}

export function ListSelectionInfo({ text, onPress }: ListSelectionInfoProps) {
  const theme = useTheme();

  const content = (
    <AppText variant="caption" style={[styles.selectionText, { color: theme.colors.textSecondary }]}>
      {text}
    </AppText>
  );

  if (!onPress) {
    return <View style={styles.selectionInfo}>{content}</View>;
  }

  return (
    <Pressable
      onPress={onPress}
      style={styles.selectionInfo}
      accessibilityRole="button"
      hitSlop={{ top: 6, bottom: 6, left: 6, right: 6 }}
    >
      {content}
    </Pressable>
  );
}

export function ListSelectAllRow({ disabled, onPress, checked, label = 'Select all' }: ListSelectAllRowProps) {
  const theme = useTheme();

  return (
    <Pressable
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [styles.selectAllRow, pressed && styles.selectAllPressed, disabled && styles.selectAllDisabled]}
      accessibilityRole="checkbox"
      accessibilityState={{ checked }}
      hitSlop={{ top: 13, bottom: 13, left: 13, right: 13 }}
    >
      <SelectorCircle selected={checked} indicator="check" />
      <Text style={[styles.selectAllLabel, { color: theme.colors.textSecondary }]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  selectAllRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginTop: -6,
    paddingVertical: 8,
    paddingHorizontal: 4,
  },
  selectAllPressed: {
    opacity: 0.6,
  },
  selectAllDisabled: {
    opacity: 0.4,
  },
  selectAllLabel: {
    fontSize: 14,
    fontWeight: '400',
  },
  selectionInfo: {
    paddingHorizontal: 4,
    paddingTop: 0,
    paddingBottom: 0,
    marginTop: 8,
  },
  selectionText: {
    fontSize: 11,
  },
});
