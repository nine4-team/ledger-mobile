export const BUDGET_COLORS = {
  standard: {
    green: { bar: '#22C55E', text: '#059669' },
    yellow: { bar: '#EAB308', text: '#CA8A04' },
    red: { bar: '#EF4444', text: '#DC2626' },
    overflow: { bar: '#991B1B', text: '#7F1D1D' },
  },
  fee: {
    green: { bar: '#22C55E', text: '#059669' },
    yellow: { bar: '#EAB308', text: '#CA8A04' },
    red: { bar: '#EF4444', text: '#DC2626' },
  },
};

export function getBudgetProgressColor(
  percentage: number,
  isFeeCategory: boolean
): { bar: string; text: string } {
  if (isFeeCategory) {
    // Inverted: green for high percentage (good)
    if (percentage >= 75) return BUDGET_COLORS.fee.green;
    if (percentage >= 50) return BUDGET_COLORS.fee.yellow;
    return BUDGET_COLORS.fee.red;
  } else {
    // Standard: red for high percentage (bad)
    if (percentage >= 75) return BUDGET_COLORS.standard.red;
    if (percentage >= 50) return BUDGET_COLORS.standard.yellow;
    return BUDGET_COLORS.standard.green;
  }
}

export function getOverflowColor(): { bar: string; text: string } {
  return BUDGET_COLORS.standard.overflow;
}
