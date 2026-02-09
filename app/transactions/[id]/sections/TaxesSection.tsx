import { View, StyleSheet } from 'react-native';
import { Card } from '../../../../src/components/Card';
import { AppText } from '../../../../src/components/AppText';
import { useUIKitTheme } from '../../../../src/theme/ThemeProvider';
import { getTextSecondaryStyle } from '../../../../src/ui/styles/typography';
import { textEmphasis } from '../../../../src/ui';
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
  const uiKitTheme = useUIKitTheme();

  return (
    <Card>
      <View style={styles.detailRows}>
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Subtotal
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {formatMoney(transaction.subtotalCents)}
          </AppText>
        </View>
        <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Tax rate
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {formatPercent(transaction.taxRatePct)}
          </AppText>
        </View>
        <View style={[styles.divider, { borderTopColor: uiKitTheme.border.secondary }]} />
        <View style={styles.detailRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Tax amount
          </AppText>
          <AppText variant="body" style={[styles.valueText, textEmphasis.value]}>
            {typeof transaction.amountCents === 'number' && typeof transaction.subtotalCents === 'number'
              ? formatMoney(transaction.amountCents - transaction.subtotalCents)
              : '—'}
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
