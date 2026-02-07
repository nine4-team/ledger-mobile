export const BUDGET_COLORS = {
  light: {
    standard: {
      green: { bar: '#22C55E', text: '#059669' },
      yellow: { bar: '#EAB308', text: '#CA8A04' },
      red: { bar: '#EF4444', text: '#DC2626' },
      overflow: { bar: '#991B1B', text: '#991B1B' },
    },
    fee: {
      green: { bar: '#22C55E', text: '#059669' },
      yellow: { bar: '#EAB308', text: '#CA8A04' },
      red: { bar: '#EF4444', text: '#DC2626' },
    },
  },
  dark: {
    standard: {
      green: { bar: '#22C55E', text: '#4ADE80' },
      yellow: { bar: '#EAB308', text: '#FACC15' },
      red: { bar: '#EF4444', text: '#F87171' },
      overflow: { bar: '#B91C1C', text: '#FCA5A5' },
    },
    fee: {
      green: { bar: '#22C55E', text: '#4ADE80' },
      yellow: { bar: '#EAB308', text: '#FACC15' },
      red: { bar: '#EF4444', text: '#F87171' },
    },
  },
};

export function getBudgetProgressColor(
  percentage: number,
  isFeeCategory: boolean,
  isDark = false,
): { bar: string; text: string } {
  const palette = isDark ? BUDGET_COLORS.dark : BUDGET_COLORS.light;
  if (isFeeCategory) {
    if (percentage >= 75) return palette.fee.green;
    if (percentage >= 50) return palette.fee.yellow;
    return palette.fee.red;
  } else {
    if (percentage >= 75) return palette.standard.red;
    if (percentage >= 50) return palette.standard.yellow;
    return palette.standard.green;
  }
}

export function getOverflowColor(isDark = false): { bar: string; text: string } {
  return isDark
    ? BUDGET_COLORS.dark.standard.overflow
    : BUDGET_COLORS.light.standard.overflow;
}
