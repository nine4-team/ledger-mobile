import { View, StyleSheet } from 'react-native';
import { Card } from '../../../../src/components/Card';
import { DetailRow } from '../../../../src/components/DetailRow';
import type { Transaction } from '../../../../src/data/transactionsService';

type TaxesSectionProps = {
  transaction: Transaction;
};

function formatMoney(cents: number | null | undefined): string {
  if (typeof cents !== 'number') return '—';
  return `$${(cents / 100).toFixed(2)}`;
}

function formatPercent(pct: number | null | undefined): string {
  if (typeof pct !== 'number') return '—';
  return `${pct.toFixed(2)}%`;
}

export function TaxesSection({ transaction }: TaxesSectionProps) {
  const taxAmount = typeof transaction.amountCents === 'number' && typeof transaction.subtotalCents === 'number'
    ? formatMoney(transaction.amountCents - transaction.subtotalCents)
    : '—';

  return (
    <Card>
      <View style={styles.detailRows}>
        <DetailRow label="Subtotal" value={formatMoney(transaction.subtotalCents)} />
        <DetailRow label="Tax rate" value={formatPercent(transaction.taxRatePct)} />
        <DetailRow label="Tax amount" value={taxAmount} showDivider={false} />
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  detailRows: {
    gap: 12,
  },
});
