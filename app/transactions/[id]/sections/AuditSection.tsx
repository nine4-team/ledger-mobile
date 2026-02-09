import { View, StyleSheet } from 'react-native';
import { Card } from '../../../../src/components/Card';
import { AppText } from '../../../../src/components/AppText';
import { useUIKitTheme } from '../../../../src/theme/ThemeProvider';
import { getTextSecondaryStyle } from '../../../../src/ui/styles/typography';
import type { Transaction } from '../../../../src/data/transactionsService';

type AuditSectionProps = {
  transaction: Transaction;
};

export function AuditSection({ transaction }: AuditSectionProps) {
  const uiKitTheme = useUIKitTheme();

  return (
    <Card>
      <View style={styles.auditPlaceholder}>
        <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
          Transaction audit section coming soon.
        </AppText>
        <AppText variant="caption" style={[styles.auditDescription, getTextSecondaryStyle(uiKitTheme)]}>
          This will show:
        </AppText>
        <View style={styles.auditFeaturesList}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            • Items total vs transaction subtotal
          </AppText>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            • Completeness indicators
          </AppText>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            • Missing price warnings
          </AppText>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            • Tax variance calculations
          </AppText>
        </View>
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  auditPlaceholder: {
    gap: 12,
    paddingVertical: 8,
  },
  auditDescription: {
    marginTop: 4,
  },
  auditFeaturesList: {
    gap: 6,
    marginTop: 8,
    paddingLeft: 8,
  },
});
