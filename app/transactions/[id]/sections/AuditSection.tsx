import { useMemo } from 'react';
import { View, StyleSheet } from 'react-native';
import { Card } from '../../../../src/components/Card';
import { AppText } from '../../../../src/components/AppText';
import { ProgressBar } from '../../../../src/components/ProgressBar';
import { useTheme, useThemeContext } from '../../../../src/theme/ThemeProvider';
import { BUDGET_COLORS, getBudgetProgressColor, getOverflowColor } from '../../../../src/utils/budgetColors';
import { computeTransactionCompleteness } from '../../../../src/utils/transactionCompleteness';
import type { Transaction } from '../../../../src/data/transactionsService';
import type { Item } from '../../../../src/data/itemsService';

type AuditSectionProps = {
  transaction: Transaction;
  items: Pick<Item, 'purchasePriceCents'>[];
};

export function AuditSection({ transaction, items }: AuditSectionProps) {
  const { resolvedColorScheme } = useThemeContext();
  const isDark = resolvedColorScheme === 'dark';
  const theme = useTheme();

  const completeness = useMemo(
    () => computeTransactionCompleteness(transaction, items),
    [transaction, items],
  );

  // Handle N/A state (FR-009)
  if (completeness === null) {
    return (
      <Card>
        <View style={styles.naContainer}>
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            Unable to calculate completeness — transaction has no subtotal.
          </AppText>
        </View>
      </Card>
    );
  }

  // Calculate ProgressBar props
  const percentage = Math.min(completeness.completenessRatio * 100, 100);
  const overflowPercentage = completeness.completenessRatio > 1
    ? (completeness.completenessRatio - 1) * 100
    : undefined;

  const progressColors = getBudgetProgressColor(
    completeness.completenessRatio * 100,
    true,  // isFeeCategory = true → inverted: high % = green (good)
    isDark,
  );
  const overflowColors = overflowPercentage ? getOverflowColor(isDark) : undefined;
  const warningColor = (isDark ? BUDGET_COLORS.dark : BUDGET_COLORS.light).standard.yellow.text;

  // Format currency
  const formatCents = (cents: number): string =>
    `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

  // Status message (FR-006)
  const pct = Math.round(completeness.completenessRatio * 100);
  let statusMessage: string;
  switch (completeness.completenessStatus) {
    case 'complete':
      statusMessage = '100% — Complete';
      break;
    case 'near':
      statusMessage = `${pct}% — Nearly Complete`;
      break;
    case 'incomplete':
      statusMessage = `${pct}% — Incomplete`;
      break;
    case 'over':
      statusMessage = `${pct}% — Over-itemized`;
      break;
  }

  return (
    <Card>
      <View style={styles.container}>
        {/* ProgressBar (FR-005) */}
        <ProgressBar
          percentage={percentage}
          color={progressColors.bar}
          overflowPercentage={overflowPercentage}
          overflowColor={overflowColors?.bar}
        />

        {/* Totals comparison row (FR-008) */}
        <View style={styles.totalsRow}>
          <View style={styles.totalColumn}>
            <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
              Items Total
            </AppText>
            <AppText variant="body">
              {formatCents(completeness.itemsNetTotal)}
            </AppText>
          </View>
          <View style={styles.totalColumn}>
            <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
              Transaction Subtotal
            </AppText>
            <AppText variant="body">
              {formatCents(completeness.transactionSubtotal)}
            </AppText>
          </View>
        </View>

        {/* Status message (FR-006) */}
        <AppText variant="body" style={{ color: progressColors.text, marginTop: 12 }}>
          {statusMessage}
        </AppText>

        {/* Missing price count (FR-007) */}
        {completeness.itemsMissingPriceCount > 0 && (
          <AppText variant="caption" style={{ color: warningColor, marginTop: 8 }}>
            ⚠ {completeness.itemsMissingPriceCount} item(s) missing purchase price
          </AppText>
        )}
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  naContainer: {
    paddingVertical: 8,
  },
  totalsRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 12,
  },
  totalColumn: {
    gap: 4,
  },
});
