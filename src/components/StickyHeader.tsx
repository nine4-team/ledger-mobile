import React from 'react';
import { View, ViewProps } from 'react-native';
import { useTheme } from '../theme/ThemeProvider';

/**
 * Wrapper component for content that should stick to the top of a ScrollView.
 * Provides an opaque background so content doesn't bleed through when sticky.
 *
 * Usage: Wrap any component you want to be sticky inside AppScrollView.
 * AppScrollView will auto-detect StickyHeader children and apply stickyHeaderIndices.
 */
export function StickyHeader({ children, style, ...props }: ViewProps) {
  const theme = useTheme();

  return (
    <View
      style={[
        {
          backgroundColor: theme.colors.background,
          zIndex: 1,
        },
        style,
      ]}
      {...props}
    >
      {children}
    </View>
  );
}
