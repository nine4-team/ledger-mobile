import React from 'react';
import { Pressable, View, StyleSheet } from 'react-native';
import { AppText } from './AppText';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { getTextSecondaryStyle } from '../ui/styles/typography';
import { textEmphasis } from '../ui';

export type DetailRowProps = {
  label: string;
  value: string | React.ReactNode;
  showDivider?: boolean; // default: true
  onPress?: () => void; // optional tap action (copy, navigate)
};

export function DetailRow({
  label,
  value,
  showDivider = true,
  onPress,
}: DetailRowProps) {
  const uiKitTheme = useUIKitTheme();

  const content = (
    <>
      <View style={styles.row}>
        <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
          {label}
        </AppText>
        {typeof value === 'string' ? (
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {value}
          </AppText>
        ) : (
          <View style={styles.valueContainer}>{value}</View>
        )}
      </View>
      {showDivider && (
        <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
      )}
    </>
  );

  if (onPress) {
    return (
      <Pressable onPress={onPress} accessibilityRole="button">
        {content}
      </Pressable>
    );
  }

  return content;
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 12,
  },
  valueText: {
    flexShrink: 1,
    textAlign: 'right',
  },
  valueContainer: {
    flexShrink: 1,
    alignItems: 'flex-end',
  },
  divider: {
    borderTopWidth: 1,
  },
});
