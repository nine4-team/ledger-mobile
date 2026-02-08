import React, { useMemo } from 'react';
import { StyleSheet, TouchableOpacity, View } from 'react-native';
import { useRouter } from 'expo-router';
import { AppText } from '../AppText';
import { useTheme } from '../../theme/ThemeProvider';
import { OWED_TO_COMPANY, OWED_TO_CLIENT } from '../../constants/reimbursement';
import type { ScopedTransaction } from '../../data/scopedListData';

type AccountingOverviewProps = {
  transactions: ScopedTransaction[];
  projectId: string;
};

const formatUSD = (cents: number): string =>
  Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(cents / 100);

export function AccountingOverview({ transactions, projectId }: AccountingOverviewProps) {
  const theme = useTheme();
  const router = useRouter();

  const { owedToCompany, owedToClient } = useMemo(() => {
    let company = 0;
    let client = 0;
    for (const tx of transactions) {
      if (tx.isCanceled) continue;
      const amount = tx.amountCents ?? 0;
      if (tx.reimbursementType === OWED_TO_COMPANY) {
        company += amount;
      } else if (tx.reimbursementType === OWED_TO_CLIENT) {
        client += amount;
      }
    }
    return { owedToCompany: company, owedToClient: client };
  }, [transactions]);

  const reportButtons = useMemo(
    () => [
      {
        label: 'Property Management Summary',
        route: `/project/${projectId}/property-management-summary` as const,
      },
      {
        label: 'Client Summary',
        route: `/project/${projectId}/client-summary` as const,
      },
      {
        label: 'Invoice',
        route: `/project/${projectId}/invoice` as const,
      },
    ],
    [projectId]
  );

  return (
    <View style={styles.container}>
      {/* Summary Cards */}
      <View style={styles.cardsRow}>
        <View
          style={[
            styles.card,
            {
              backgroundColor: theme.colors.background,
              borderColor: theme.colors.border,
            },
          ]}
        >
          <AppText variant="caption" style={styles.cardLabel}>
            Owed to Design Business
          </AppText>
          <AppText variant="h2" style={[styles.cardAmount, { color: theme.colors.text }]}>
            {formatUSD(owedToCompany)}
          </AppText>
        </View>
        <View
          style={[
            styles.card,
            {
              backgroundColor: theme.colors.background,
              borderColor: theme.colors.border,
            },
          ]}
        >
          <AppText variant="caption" style={styles.cardLabel}>
            Owed to Client
          </AppText>
          <AppText variant="h2" style={[styles.cardAmount, { color: theme.colors.text }]}>
            {formatUSD(owedToClient)}
          </AppText>
        </View>
      </View>

      {/* Report Buttons */}
      <View style={styles.reportButtons}>
        {reportButtons.map((button) => (
          <TouchableOpacity
            key={button.route}
            style={[
              styles.reportButton,
              {
                backgroundColor: theme.colors.background,
                borderColor: theme.colors.border,
              },
            ]}
            activeOpacity={0.7}
            onPress={() => router.push(button.route)}
          >
            <AppText variant="body" style={[styles.reportButtonText, { color: theme.colors.primary }]}>
              {button.label}
            </AppText>
          </TouchableOpacity>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 16,
  },
  cardsRow: {
    flexDirection: 'row',
    gap: 12,
  },
  card: {
    flex: 1,
    borderWidth: 1,
    borderRadius: 12,
    padding: 16,
    gap: 4,
  },
  cardLabel: {
    fontSize: 13,
  },
  cardAmount: {
    fontSize: 20,
    fontWeight: '600',
  },
  reportButtons: {
    gap: 10,
  },
  reportButton: {
    borderWidth: 1,
    borderRadius: 10,
    paddingVertical: 14,
    paddingHorizontal: 16,
    alignItems: 'center',
  },
  reportButtonText: {
    fontWeight: '600',
    fontSize: 15,
  },
});
