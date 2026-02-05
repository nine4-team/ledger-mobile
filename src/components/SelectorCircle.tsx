import React, { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';

import { useUIKitTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';

type SelectorCircleProps = {
  selected?: boolean;
  indicator?: 'dot' | 'check';
  size?: number;
  style?: ViewStyle;
};

export function SelectorCircle({
  selected = false,
  indicator = 'dot',
  size = 18,
  style,
}: SelectorCircleProps) {
  const uiKitTheme = useUIKitTheme();
  const dotSize = Math.max(6, Math.round(size * 0.56));
  const checkmarkSize = Math.max(10, Math.round(size * 0.65));
  const checkmarkLineHeight = Math.max(12, Math.round(size * 0.82));

  const themed = useMemo(
    () =>
      StyleSheet.create({
        base: {
          width: size,
          height: size,
          borderRadius: size / 2,
          borderWidth: 1,
          borderColor: uiKitTheme.border.primary,
          alignItems: 'center',
          justifyContent: 'center',
          backgroundColor: selected && indicator === 'check' ? uiKitTheme.primary.main : 'transparent',
        },
        dot: {
          width: dotSize,
          height: dotSize,
          borderRadius: dotSize / 2,
          backgroundColor: uiKitTheme.primary.main,
        },
        checkmark: {
          fontSize: checkmarkSize,
          lineHeight: checkmarkLineHeight,
          fontWeight: '700',
          color: '#FFFFFF',
        },
      }),
    [checkmarkLineHeight, checkmarkSize, dotSize, indicator, selected, size, uiKitTheme]
  );

  return (
    <View style={[themed.base, style]}>
      {selected ? (
        indicator === 'check' ? (
          <AppText style={themed.checkmark}>✓</AppText>
        ) : (
          <View style={themed.dot} />
        )
      ) : null}
    </View>
  );
}
