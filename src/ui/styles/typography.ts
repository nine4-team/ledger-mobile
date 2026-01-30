import type { TextStyle } from 'react-native';
import { StyleSheet } from 'react-native';

import type { ColorTheme } from '../kit';

/**
 * App-only shared typography emphasis styles.
 *
 * TODO(ui-kit): Add common emphasis variants (section label, link, value) to ui-kit typography.
 */
export const textEmphasis = StyleSheet.create({
  sectionLabel: {
    fontWeight: '600',
    letterSpacing: 0.2,
    textTransform: 'uppercase',
  },
  value: {
    fontWeight: '500',
  },
  strong: {
    fontWeight: '600',
  },
});

export function getTextColorStyle(color: string): TextStyle {
  return { color };
}

export function getTextSecondaryStyle(theme: ColorTheme): TextStyle {
  return { color: theme.text.secondary };
}

export function getTextPrimaryStyle(theme: ColorTheme): TextStyle {
  return { color: theme.text.primary };
}

export function getTextAccentStyle(theme: ColorTheme): TextStyle {
  return { color: theme.primary.main };
}

