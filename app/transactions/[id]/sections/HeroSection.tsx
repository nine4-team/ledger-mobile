import { View, StyleSheet } from 'react-native';
import { AppText } from '../../../../src/components/AppText';
import { CARD_PADDING, getCardStyle } from '../../../../src/ui';
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

export function HeroSection({ transaction }: HeroSectionProps) {
  const uiKitTheme = useUIKitTheme();

  return (
    <View style={[styles.card, getCardStyle(uiKitTheme, { padding: CARD_PADDING })]}>
      <View style={styles.heroHeader}>
        <AppText variant="h2" style={styles.heroTitle}>
          {transaction.source?.trim() || 'Untitled transaction'}
        </AppText>
        <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
          {formatMoney(transaction.amountCents)}
        </AppText>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {},
  heroHeader: {
    gap: 6,
  },
  heroTitle: {
    lineHeight: 26,
  },
});
