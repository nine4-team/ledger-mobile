import React, { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import { AppText } from './AppText';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';

type BudgetProgressProps = {
  spentCents: number;
  budgetCents: number;
  compact?: boolean;
};

function formatCents(value: number) {
  return `$${(value / 100).toFixed(2)}`;
}

export function BudgetProgress({ spentCents, budgetCents, compact = false }: BudgetProgressProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const safeBudget = Math.max(budgetCents, 0);
  const ratio = safeBudget > 0 ? Math.min(Math.max(spentCents / safeBudget, 0), 1) : 0;
  const overBudget = safeBudget > 0 && spentCents > safeBudget;
  const barColor = overBudget
    ? uiKitTheme.status?.missed?.bar ?? uiKitTheme.primary.main
    : uiKitTheme.status?.inProgress?.bar ?? uiKitTheme.primary.main;

  const label = useMemo(() => {
    const spentLabel = formatCents(spentCents);
    const budgetLabel = formatCents(safeBudget);
    return compact ? `${spentLabel} / ${budgetLabel}` : `Spent ${spentLabel} of ${budgetLabel}`;
  }, [compact, safeBudget, spentCents]);

  return (
    <View style={styles.container}>
      <View style={styles.labelRow}>
        <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
          {label}
        </AppText>
        {!compact ? (
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {safeBudget > 0 ? `${Math.round((spentCents / safeBudget) * 100)}%` : '—'}
          </AppText>
        ) : null}
      </View>
      <View style={[styles.track, { backgroundColor: uiKitTheme.border.secondary }]}>
        <View style={[styles.fill, { width: `${ratio * 100}%`, backgroundColor: barColor }]} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 6,
  },
  labelRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  track: {
    height: 6,
    borderRadius: 999,
    overflow: 'hidden',
  },
  fill: {
    height: '100%',
    borderRadius: 999,
  },
});
