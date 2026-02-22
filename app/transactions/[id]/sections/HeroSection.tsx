import { View, StyleSheet } from 'react-native';
import { AppText } from '../../../../src/components/AppText';
import { CARD_PADDING, getCardStyle, textEmphasis } from '../../../../src/ui';
import { useUIKitTheme } from '../../../../src/theme/ThemeProvider';
import { getTextSecondaryStyle } from '../../../../src/ui/styles/typography';
import type { Transaction } from '../../../../src/data/transactionsService';

type HeroSectionProps = {
  transaction: Transaction;
};

function formatMoney(cents: number | null | undefined): string {
  if (typeof cents !== 'number') return '—';
  return `$${(cents / 100).toFixed(2)}`;
}

function formatDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  const date = new Date(dateStr);
  if (isNaN(date.getTime())) return '—';
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export function HeroSection({ transaction }: HeroSectionProps) {
  const uiKitTheme = useUIKitTheme();

  return (
    <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
      <View style={styles.heroHeader}>
        <AppText variant="h2" style={styles.heroTitle}>
          {transaction.source?.trim() || 'Untitled transaction'}
        </AppText>
        <View style={styles.infoRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Amount:
          </AppText>
          <AppText variant="body" style={textEmphasis.value}>
            {formatMoney(transaction.amountCents)}
          </AppText>
        </View>
        <View style={styles.infoRow}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Date:
          </AppText>
          <AppText variant="body" style={textEmphasis.value}>
            {formatDate(transaction.transactionDate)}
          </AppText>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {},
  heroHeader: {
    gap: 8,
  },
  heroTitle: {
    lineHeight: 26,
  },
  infoRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 6,
  },
});
