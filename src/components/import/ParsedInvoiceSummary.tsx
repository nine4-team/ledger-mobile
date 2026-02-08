import React, { useState } from 'react';
import { StyleSheet, TouchableOpacity, View } from 'react-native';
import { AppText } from '../AppText';
import { useTheme } from '../../theme/ThemeProvider';

type ParsedInvoiceSummaryProps = {
  vendor: 'amazon' | 'wayfair';
  orderNumber?: string;
  orderDate?: string;
  grandTotal?: string;
  itemCount: number;
  warnings: string[];
  /** Wayfair-specific fields */
  subtotal?: string;
  shippingTotal?: string;
  taxTotal?: string;
};

export function ParsedInvoiceSummary({
  vendor,
  orderNumber,
  orderDate,
  grandTotal,
  itemCount,
  warnings,
  subtotal,
  shippingTotal,
  taxTotal,
}: ParsedInvoiceSummaryProps) {
  const theme = useTheme();
  const [warningsExpanded, setWarningsExpanded] = useState(false);

  const vendorLabel = vendor === 'amazon' ? 'Amazon' : 'Wayfair';

  return (
    <View style={[styles.card, { backgroundColor: theme.colors.background, borderColor: theme.colors.border }]}>
      <AppText variant="h2" style={styles.title}>
        {vendorLabel} Invoice Summary
      </AppText>

      <SummaryRow label="Order #" value={orderNumber ?? '--'} theme={theme} />
      <SummaryRow label="Order Date" value={orderDate ?? '--'} theme={theme} />
      <SummaryRow label="Items" value={String(itemCount)} theme={theme} />

      {vendor === 'wayfair' && (
        <>
          <SummaryRow label="Subtotal" value={subtotal ? `$${subtotal}` : '--'} theme={theme} />
          <SummaryRow label="Shipping" value={shippingTotal ? `$${shippingTotal}` : '--'} theme={theme} />
          <SummaryRow label="Tax" value={taxTotal ? `$${taxTotal}` : '--'} theme={theme} />
        </>
      )}

      <SummaryRow
        label="Grand Total"
        value={grandTotal ? `$${grandTotal}` : '--'}
        theme={theme}
        bold
      />

      {warnings.length > 0 && (
        <View style={styles.warningsSection}>
          <TouchableOpacity
            onPress={() => setWarningsExpanded((prev) => !prev)}
            style={[styles.warningsHeader, { borderColor: theme.colors.border }]}
            activeOpacity={0.7}
          >
            <AppText variant="caption" style={{ color: theme.colors.error }}>
              {warnings.length} warning{warnings.length !== 1 ? 's' : ''} {warningsExpanded ? '(tap to collapse)' : '(tap to expand)'}
            </AppText>
          </TouchableOpacity>
          {warningsExpanded && (
            <View style={styles.warningsList}>
              {warnings.map((warning, idx) => (
                <AppText key={idx} variant="caption" style={{ color: theme.colors.error }}>
                  {'\u2022'} {warning}
                </AppText>
              ))}
            </View>
          )}
        </View>
      )}
    </View>
  );
}

type SummaryRowProps = {
  label: string;
  value: string;
  theme: ReturnType<typeof useTheme>;
  bold?: boolean;
};

function SummaryRow({ label, value, theme, bold }: SummaryRowProps) {
  return (
    <View style={styles.row}>
      <AppText variant="caption" style={styles.rowLabel}>
        {label}
      </AppText>
      <AppText
        variant="body"
        style={[styles.rowValue, bold && { fontWeight: '700', color: theme.colors.text }]}
      >
        {value}
      </AppText>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderWidth: 1,
    borderRadius: 12,
    padding: 16,
    gap: 6,
  },
  title: {
    marginBottom: 4,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  rowLabel: {
    flex: 1,
  },
  rowValue: {
    flex: 1,
    textAlign: 'right',
  },
  warningsSection: {
    marginTop: 8,
  },
  warningsHeader: {
    borderTopWidth: 1,
    paddingTop: 8,
  },
  warningsList: {
    marginTop: 4,
    gap: 2,
  },
});
