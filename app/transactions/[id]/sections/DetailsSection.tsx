import { View, StyleSheet } from 'react-native';
import { Card } from '../../../../src/components/Card';
import { AppText } from '../../../../src/components/AppText';
import { useUIKitTheme } from '../../../../src/theme/ThemeProvider';
import { getTextSecondaryStyle } from '../../../../src/ui/styles/typography';
import { textEmphasis } from '../../../../src/ui';
import type { Transaction } from '../../../../src/data/transactionsService';
import type { BudgetCategories } from './types';

type DetailsSectionProps = {
  transaction: Transaction;
  budgetCategories: BudgetCategories;
};

function formatMoney(cents: number | null | undefined): string {
  if (typeof cents !== 'number') return '—';
  return `$${(cents / 100).toFixed(2)}`;
}

function formatDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  return dateStr;
}

export function DetailsSection({ transaction, budgetCategories }: DetailsSectionProps) {
  const uiKitTheme = useUIKitTheme();

  const budgetCategoryLabel = (() => {
    if (!transaction.budgetCategoryId) return 'None';
    const category = budgetCategories[transaction.budgetCategoryId];
    return category?.name?.trim() || transaction.budgetCategoryId;
  })();

  const hasReceiptLabel = transaction.hasEmailReceipt ? 'Yes' : 'No';

  return (
    <Card>
      <View style={styles.detailRows}>
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Source
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {transaction.source?.trim() || '—'}
          </AppText>
        </View>
        <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Date
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {formatDate(transaction.transactionDate)}
          </AppText>
        </View>
        <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Amount
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {formatMoney(transaction.amountCents)}
          </AppText>
        </View>
        <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Status
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {transaction.status?.trim() || '—'}
          </AppText>
        </View>
        <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Purchased by
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {transaction.purchasedBy?.trim() || '—'}
          </AppText>
        </View>
        <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Reimbursement type
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {transaction.reimbursementType?.trim() || '—'}
          </AppText>
        </View>
        <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Budget category
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {budgetCategoryLabel}
          </AppText>
        </View>
        <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Email receipt
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {hasReceiptLabel}
          </AppText>
        </View>
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  detailRows: {
    gap: 12,
  },
  detailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 12,
  },
  valueText: {
    flexShrink: 1,
    textAlign: 'right',
  },
  divider: {
    borderTopWidth: 1,
  },
});
