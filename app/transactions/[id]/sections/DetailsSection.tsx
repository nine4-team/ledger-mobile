import { View, StyleSheet } from 'react-native';
import { Card } from '../../../../src/components/Card';
import { DetailRow } from '../../../../src/components/DetailRow';
import type { Transaction } from '../../../../src/data/transactionsService';
import type { BudgetCategories } from './types';

type DetailsSectionProps = {
  transaction: Transaction;
  budgetCategories: BudgetCategories;
  itemizationEnabled: boolean;
};

function formatMoney(cents: number | null | undefined): string {
  if (typeof cents !== 'number') return '—';
  return `$${(cents / 100).toFixed(2)}`;
}

function formatDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  return dateStr;
}

function formatPercent(pct: number | null | undefined): string {
  if (typeof pct !== 'number') return '—';
  return `${pct.toFixed(2)}%`;
}

export function DetailsSection({ transaction, budgetCategories, itemizationEnabled }: DetailsSectionProps) {
  const budgetCategoryLabel = (() => {
    if (!transaction.budgetCategoryId) return 'None';
    const category = budgetCategories[transaction.budgetCategoryId];
    return category?.name?.trim() || transaction.budgetCategoryId;
  })();

  const hasReceiptLabel = transaction.hasEmailReceipt ? 'Yes' : 'No';

  // Calculate tax amount for display
  const taxAmount = typeof transaction.amountCents === 'number' && typeof transaction.subtotalCents === 'number'
    ? formatMoney(transaction.amountCents - transaction.subtotalCents)
    : '—';

  // Build detail rows array with conditional tax rows
  const detailRows = [
    { label: 'Source', value: transaction.source?.trim() || '—' },
    { label: 'Date', value: formatDate(transaction.transactionDate) },
    { label: 'Amount', value: formatMoney(transaction.amountCents) },
    { label: 'Status', value: transaction.status?.trim() || '—' },
    { label: 'Purchased by', value: transaction.purchasedBy?.trim() || '—' },
    { label: 'Reimbursement type', value: transaction.reimbursementType?.trim() || '—' },
    { label: 'Budget category', value: budgetCategoryLabel },
    { label: 'Email receipt', value: hasReceiptLabel },
    // Conditionally include tax rows when itemization is enabled
    ...(itemizationEnabled ? [
      { label: 'Subtotal', value: formatMoney(transaction.subtotalCents) },
      { label: 'Tax rate', value: formatPercent(transaction.taxRatePct) },
      { label: 'Tax amount', value: taxAmount },
    ] : []),
  ];

  return (
    <Card>
      <View style={styles.detailRows}>
        {detailRows.map((row, index) => (
          <DetailRow
            key={row.label}
            label={row.label}
            value={row.value}
            showDivider={index < detailRows.length - 1}
          />
        ))}
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  detailRows: {
    gap: 12,
  },
});
