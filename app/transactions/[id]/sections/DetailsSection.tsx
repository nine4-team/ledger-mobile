import { View, StyleSheet } from 'react-native';
import { Card } from '../../../../src/components/Card';
import { DetailRow } from '../../../../src/components/DetailRow';
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
  const budgetCategoryLabel = (() => {
    if (!transaction.budgetCategoryId) return 'None';
    const category = budgetCategories[transaction.budgetCategoryId];
    return category?.name?.trim() || transaction.budgetCategoryId;
  })();

  const hasReceiptLabel = transaction.hasEmailReceipt ? 'Yes' : 'No';

  return (
    <Card>
      <View style={styles.detailRows}>
        <DetailRow label="Source" value={transaction.source?.trim() || '—'} />
        <DetailRow label="Date" value={formatDate(transaction.transactionDate)} />
        <DetailRow label="Amount" value={formatMoney(transaction.amountCents)} />
        <DetailRow label="Status" value={transaction.status?.trim() || '—'} />
        <DetailRow label="Purchased by" value={transaction.purchasedBy?.trim() || '—'} />
        <DetailRow label="Reimbursement type" value={transaction.reimbursementType?.trim() || '—'} />
        <DetailRow label="Budget category" value={budgetCategoryLabel} />
        <DetailRow label="Email receipt" value={hasReceiptLabel} showDivider={false} />
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  detailRows: {
    gap: 12,
  },
});
