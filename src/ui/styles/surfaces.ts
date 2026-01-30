import type { ViewStyle } from 'react-native';
import { StyleSheet } from 'react-native';

import { getCardBaseStyle, getCardBorderStyle, type ColorTheme } from '../kit';

/**
 * Shared surface styles for cards/tiles.
 *
 * TODO(ui-kit): Add a first-class `Card` surface helper that combines base + border + background.
 */
export const surface = StyleSheet.create({
  overflowHidden: {
    overflow: 'hidden',
  },
});

export function getCardStyle(
  theme: ColorTheme,
  opts?: {
    radius?: number;
    padding?: number;
  }
): ViewStyle {
  const style: ViewStyle = {
    backgroundColor: theme.background.surface,
    ...getCardBaseStyle({ radius: opts?.radius ?? 12 }),
    ...getCardBorderStyle(theme),
  };

  if (typeof opts?.padding === 'number') {
    style.padding = opts.padding;
  }

  return style;
}

