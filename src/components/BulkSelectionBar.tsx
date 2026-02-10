import React from 'react';
import { StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { AppText } from './AppText';
import { AppButton } from './AppButton';
import { useTheme } from '../theme/ThemeProvider';
import { BULK_SELECTION_BAR } from '../ui';

type BulkSelectionBarProps = {
  selectedCount: number;
  onBulkActionsPress: () => void;
  onClearSelection: () => void;
};

export function BulkSelectionBar({
  selectedCount,
  onBulkActionsPress,
  onClearSelection,
}: BulkSelectionBarProps) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();

  if (selectedCount === 0) return null;

  return (
    <View
      style={[
        styles.container,
        {
          backgroundColor: theme.colors.background,
          borderTopColor: theme.colors.border,
          paddingBottom: Math.max(BULK_SELECTION_BAR.MIN_PADDING_BOTTOM, insets.bottom),
        },
      ]}
    >
      <AppText variant="caption" style={styles.countText}>
        {selectedCount} selected
      </AppText>
      <View style={styles.actions}>
        <AppButton
          title="Clear"
          variant="secondary"
          onPress={onClearSelection}
        />
        <AppButton
          title="Bulk Actions"
          variant="primary"
          onPress={onBulkActionsPress}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 6,
    borderTopWidth: 1,
    // Shadow for elevation
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 8,
  },
  countText: {
    fontWeight: '600',
  },
  actions: {
    flexDirection: 'row',
    gap: 8,
    alignItems: 'center',
  },
});
