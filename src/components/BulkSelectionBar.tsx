import React from 'react';
import { StyleSheet, View } from 'react-native';
import { AppText } from './AppText';
import { AppButton } from './AppButton';
import { useTheme } from '../theme/ThemeProvider';

type BulkSelectionBarProps = {
  selectedCount: number;
  totalCents?: number;
  onBulkActionsPress: () => void;
  onClearSelection: () => void;
};

export function BulkSelectionBar({
  selectedCount,
  totalCents,
  onBulkActionsPress,
  onClearSelection,
}: BulkSelectionBarProps) {
  const theme = useTheme();

  if (selectedCount === 0) return null;

  return (
    <View
      style={[
        styles.container,
        {
          backgroundColor: theme.colors.background,
          borderTopColor: theme.colors.border,
        },
      ]}
    >
      <View style={styles.info}>
        <AppText variant="caption" style={styles.countText}>
          {selectedCount} selected
        </AppText>
        {typeof totalCents === 'number' && (
          <AppText variant="caption">
            ${(totalCents / 100).toFixed(2)}
          </AppText>
        )}
      </View>
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
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 6,
    borderTopWidth: 1,
    // Shadow for elevation
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 8,
  },
  info: {
    gap: 2,
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
