import { useMemo } from 'react';
import { View, StyleSheet } from 'react-native';
import { MaterialIcons } from '@expo/vector-icons';
import { Card } from '../../../../src/components/Card';
import { AppText } from '../../../../src/components/AppText';
import { ProgressBar } from '../../../../src/components/ProgressBar';
import { useTheme, useThemeContext } from '../../../../src/theme/ThemeProvider';
import { BUDGET_BAR_COLOR, getOverflowColor } from '../../../../src/utils/budgetColors';
import { computeTransactionCompleteness } from '../../../../src/utils/transactionCompleteness';
import type { Transaction } from '../../../../src/data/transactionsService';
import type { Item } from '../../../../src/data/itemsService';

type AuditSectionProps = {
  transaction: Transaction;
  items: Pick<Item, 'purchasePriceCents'>[];
  returnedItems?: Pick<Item, 'purchasePriceCents'>[];
  soldItems?: Pick<Item, 'purchasePriceCents'>[];
  incompleteReturnCount?: number;
};

export function AuditSection({ transaction, items, returnedItems, soldItems, incompleteReturnCount }: AuditSectionProps) {
  const { resolvedColorScheme } = useThemeContext();
  const isDark = resolvedColorScheme === 'dark';
  const theme = useTheme();

  const movedOutItems = useMemo(
    () =>
      returnedItems || soldItems
        ? { returned: returnedItems ?? [], sold: soldItems ?? [] }
        : undefined,
    [returnedItems, soldItems],
  );

  const completeness = useMemo(
    () => computeTransactionCompleteness(transaction, items, movedOutItems),
    [transaction, items, movedOutItems],
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

  const overflowColors = overflowPercentage ? getOverflowColor(isDark) : undefined;
  const warningColor = isDark ? '#FACC15' : '#CA8A04';

  // Format currency
  const formatCents = (cents: number): string =>
    `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

  // Status label and icon (FR-006)
  let statusLabel: string;
  let iconName: 'check-circle' | 'error-outline' | 'cancel';
  switch (completeness.status) {
    case 'complete':
      statusLabel = 'Complete';
      iconName = 'check-circle';
      break;
    case 'near':
      statusLabel = 'Nearly Complete';
      iconName = 'check-circle';
      break;
    case 'incomplete':
      statusLabel = 'Incomplete';
      iconName = 'error-outline';
      break;
    case 'over':
      statusLabel = 'Over';
      iconName = 'cancel';
      break;
  }

  // Calculate remaining amount
  const remainingCents = completeness.transactionSubtotalCents - completeness.itemsNetTotalCents;
  const remainingLabel = remainingCents >= 0
    ? `${formatCents(remainingCents)} remaining`
    : `Over by ${formatCents(Math.abs(remainingCents))}`;

  return (
    <Card>
      <View style={styles.container}>
        {/* Status line with icon + label on left, $x/$y on right */}
        <View style={styles.statusRow}>
          <View style={styles.statusLeft}>
            <MaterialIcons name={iconName} size={20} color={theme.colors.primary} />
            <AppText variant="title" style={{ color: theme.colors.primary }}>
              {statusLabel}
            </AppText>
          </View>
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {formatCents(completeness.itemsNetTotalCents)} / {formatCents(completeness.transactionSubtotalCents)}
          </AppText>
        </View>

        {/* ProgressBar (FR-005) */}
        <ProgressBar
          percentage={percentage}
          color={BUDGET_BAR_COLOR}
          overflowPercentage={overflowPercentage}
          overflowColor={overflowColors?.bar}
        />

        {/* Info below bar: "N items" on left, "$x remaining" on right */}
        <View style={styles.belowBarRow}>
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {completeness.itemsCount} items
          </AppText>
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {remainingLabel}
          </AppText>
        </View>

        {/* Returned/sold item breakdown */}
        {(completeness.returnedItemsCount > 0 || completeness.soldItemsCount > 0) && (
          <AppText variant="caption" style={{ color: theme.colors.textSecondary, marginTop: 4 }}>
            Includes{completeness.returnedItemsCount > 0 ? ` ${completeness.returnedItemsCount} returned` : ''}
            {completeness.returnedItemsCount > 0 && completeness.soldItemsCount > 0 ? ' and' : ''}
            {completeness.soldItemsCount > 0 ? ` ${completeness.soldItemsCount} sold` : ''} item(s)
          </AppText>
        )}

        {/* Missing price count (FR-007) */}
        {completeness.itemsMissingPriceCount > 0 && (
          <AppText variant="caption" style={{ color: warningColor, marginTop: 8 }}>
            ⚠ {completeness.itemsMissingPriceCount} item(s) missing purchase price
          </AppText>
        )}

        {/* Incomplete return warning */}
        {(incompleteReturnCount ?? 0) > 0 && (
          <AppText variant="caption" style={{ color: warningColor, marginTop: 4 }}>
            ⚠ {incompleteReturnCount} item(s) marked as returned but not linked to a return transaction
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
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  statusLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  belowBarRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
});
