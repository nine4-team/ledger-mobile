/**
 * Budget color utilities.
 *
 * All budget progress bars use the app's primary (brand) color.
 * Overflow (over-budget) uses a distinct red to call attention.
 */

/** Brand color shared with the theme — used for all budget bar fills. */
export const BUDGET_BAR_COLOR = '#987e55';

const OVERFLOW_COLORS = {
  light: { bar: '#DC2626', text: '#DC2626' },
  dark: { bar: '#F87171', text: '#F87171' },
};

export function getOverflowColor(isDark = false): { bar: string; text: string } {
  return isDark ? OVERFLOW_COLORS.dark : OVERFLOW_COLORS.light;
}
