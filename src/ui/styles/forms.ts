import type { TextStyle } from 'react-native';

import type { ColorTheme } from '../kit';

/**
 * Form / input styling helpers.
 *
 * TODO(ui-kit): Standardize app text inputs (radius/padding/borders) as a kit primitive.
 */
export function getTextInputStyle(
  theme: ColorTheme,
  opts?: {
    radius?: number;
    padding?: number;
    paddingVertical?: number;
    paddingHorizontal?: number;
    fontSize?: number;
  }
): TextStyle {
  const style: TextStyle = {
    backgroundColor: theme.background.surface,
    borderWidth: 1,
    borderColor: theme.border.primary,
    borderRadius: opts?.radius ?? 8,
    color: theme.text.primary,
    fontSize: opts?.fontSize ?? 16,
  };

  if (typeof opts?.padding === 'number') {
    style.padding = opts.padding;
  }
  if (typeof opts?.paddingVertical === 'number') {
    style.paddingVertical = opts.paddingVertical;
  }
  if (typeof opts?.paddingHorizontal === 'number') {
    style.paddingHorizontal = opts.paddingHorizontal;
  }

  return style;
}

