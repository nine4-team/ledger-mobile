import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';

import { Screen } from '../components/Screen';
import { AppText } from '../components/AppText';
import { AppScrollView } from '../components/AppScrollView';
import { useTheme } from '../theme/ThemeProvider';
import { useAccountContextStore } from '../auth/accountContextStore';
import { layout } from '../ui';

import { subscribeToProject, type Project } from '../data/projectService';
import {
  subscribeToBudgetCategories,
  mapBudgetCategories,
  type BudgetCategory,
} from '../data/budgetCategoriesService';
import { subscribeToBusinessProfile, type BusinessProfile } from '../data/businessProfileService';
import { createProjectScopeConfig } from '../data/scopeConfig';
import {
  subscribeToScopedTransactions,
  subscribeToScopedItems,
  type ScopedTransaction,
  type ScopedItem,
} from '../data/scopedListData';
import {
  computeInvoiceData,
  formatCents,
  type InvoiceReportData,
} from '../data/reportDataService';
import {
  generateInvoiceHtml,
  type ReportHeaderParams,
} from '../utils/reportHtml';

type Props = {
  projectId: string;
};

export function ProjectInvoiceReport({ projectId }: Props) {
  const router = useRouter();
  const theme = useTheme();
  const accountId = useAccountContextStore((s) => s.accountId);

  // Data state
  const [project, setProject] = useState<Project | null>(null);
  const [transactions, setTransactions] = useState<ScopedTransaction[]>([]);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, BudgetCategory>>({});
  const [businessProfile, setBusinessProfile] = useState<BusinessProfile | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const scopeConfig = useMemo(() => createProjectScopeConfig(projectId), [projectId]);

  // Subscriptions
  useEffect(() => {
    if (!accountId || !projectId) return;
    return subscribeToProject(accountId, projectId, (next) => {
      setProject(next);
      setIsLoading(false);
    });
  }, [accountId, projectId]);

  useEffect(() => {
    if (!accountId) return;
    return subscribeToBudgetCategories(accountId, (next) => {
      setBudgetCategories(mapBudgetCategories(next));
    });
  }, [accountId]);

  useEffect(() => {
    if (!accountId || !projectId) return;
    return subscribeToScopedTransactions(accountId, scopeConfig, setTransactions);
  }, [accountId, projectId, scopeConfig]);

  useEffect(() => {
    if (!accountId || !projectId) return;
    return subscribeToScopedItems(accountId, scopeConfig, setItems);
  }, [accountId, projectId, scopeConfig]);

  useEffect(() => {
    if (!accountId) return;
    return subscribeToBusinessProfile(accountId, setBusinessProfile);
  }, [accountId]);

  // Compute report data
  const reportData: InvoiceReportData | null = useMemo(() => {
    if (!project) return null;
    // Cast scoped types to the full types expected by computeInvoiceData
    return computeInvoiceData(
      transactions as any,
      items as any,
      budgetCategories,
    );
  }, [transactions, items, budgetCategories, project]);

  const headerParams: ReportHeaderParams | null = useMemo(() => {
    if (!project) return null;
    const logoUrl = businessProfile?.logo?.url ?? null;
    return {
      businessName: businessProfile?.businessName ?? '',
      logoUrl: logoUrl && !logoUrl.startsWith('offline://') ? logoUrl : null,
      projectName: project.name,
      clientName: project.clientName,
    };
  }, [project, businessProfile]);

  const htmlContent = useMemo(() => {
    if (!reportData || !headerParams) return null;
    return generateInvoiceHtml(reportData, headerParams);
  }, [reportData, headerParams]);

  // Actions
  const handleShare = useCallback(async () => {
    if (!htmlContent) return;
    try {
      const { uri } = await Print.printToFileAsync({ html: htmlContent });
      await Sharing.shareAsync(uri, { mimeType: 'application/pdf' });
    } catch (err) {
      console.warn('[ProjectInvoiceReport] share failed', err);
    }
  }, [htmlContent]);

  const handlePrint = useCallback(async () => {
    if (!htmlContent) return;
    try {
      await Print.printAsync({ html: htmlContent });
    } catch (err) {
      console.warn('[ProjectInvoiceReport] print failed', err);
    }
  }, [htmlContent]);

  const backTarget = `/project/${projectId}`;

  const rightActions = (
    <View style={styles.headerActions}>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Share report"
        onPress={handleShare}
        style={styles.headerButton}
        disabled={!htmlContent}
      >
        <MaterialIcons name="share" size={22} color={theme.colors.primary} />
      </Pressable>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Print report"
        onPress={handlePrint}
        style={styles.headerButton}
        disabled={!htmlContent}
      >
        <MaterialIcons name="print" size={22} color={theme.colors.primary} />
      </Pressable>
    </View>
  );

  return (
    <Screen title="Invoice Report" backTarget={backTarget} headerRight={rightActions}>
      {isLoading ? (
        <View style={styles.centered}>
          <ActivityIndicator size="small" color={theme.colors.primary} />
          <AppText variant="caption" style={{ marginTop: 8, color: theme.colors.textSecondary }}>
            Loading report data...
          </AppText>
        </View>
      ) : !reportData || !reportData.hasData ? (
        <View style={styles.centered}>
          <AppText variant="body" style={{ color: theme.colors.textSecondary, textAlign: 'center' }}>
            No invoiceable transactions found for this project.
          </AppText>
        </View>
      ) : (
        <AppScrollView contentContainerStyle={styles.container}>
          {/* Totals Summary */}
          <View style={[styles.card, { backgroundColor: theme.colors.background, borderColor: theme.colors.border }]}>
            <View style={styles.totalRow}>
              <AppText variant="caption">Charges</AppText>
              <AppText variant="body" style={{ fontWeight: '600' }}>
                {formatCents(reportData.chargesTotalCents)}
              </AppText>
            </View>
            <View style={styles.totalRow}>
              <AppText variant="caption">Credits</AppText>
              <AppText variant="body" style={{ fontWeight: '600' }}>
                ({formatCents(reportData.creditsTotalCents)})
              </AppText>
            </View>
            <View style={[styles.totalRow, styles.netRow, { borderTopColor: theme.colors.border }]}>
              <AppText variant="body" style={{ fontWeight: '700', color: theme.colors.primary }}>
                Net Amount Due
              </AppText>
              <AppText variant="body" style={{ fontWeight: '700', color: theme.colors.primary }}>
                {formatCents(reportData.netAmountDueCents)}
              </AppText>
            </View>
          </View>

          {/* Charges Section */}
          {reportData.chargeLines.length > 0 && (
            <>
              <AppText variant="h2" style={{ color: theme.colors.primary, marginTop: 16 }}>
                Charges
              </AppText>
              {reportData.chargeLines.map((line) => (
                <View
                  key={line.transactionId}
                  style={[styles.lineItem, { borderBottomColor: theme.colors.border }]}
                >
                  <View style={styles.lineHeader}>
                    <AppText variant="body" style={{ fontWeight: '600', flex: 1 }}>
                      {line.title}
                    </AppText>
                    <AppText variant="body" style={{ fontWeight: '600' }}>
                      {formatCents(line.amountCents)}
                    </AppText>
                  </View>
                  {line.date && (
                    <AppText variant="caption">{line.date}</AppText>
                  )}
                  {line.budgetCategoryName && (
                    <AppText variant="caption">{line.budgetCategoryName}</AppText>
                  )}
                  {line.hasMissingPrices && (
                    <AppText variant="caption" style={{ fontStyle: 'italic', color: '#c0392b' }}>
                      Contains missing project prices
                    </AppText>
                  )}
                  {line.items.map((item) => (
                    <View key={item.id} style={styles.subItem}>
                      <AppText variant="caption" style={{ flex: 1 }}>
                        {item.name}
                      </AppText>
                      <AppText
                        variant="caption"
                        style={item.isMissingPrice ? { fontStyle: 'italic', color: '#c0392b' } : undefined}
                      >
                        {formatCents(item.projectPriceCents)}
                        {item.isMissingPrice ? ' (missing)' : ''}
                      </AppText>
                    </View>
                  ))}
                </View>
              ))}
            </>
          )}

          {/* Credits Section */}
          {reportData.creditLines.length > 0 && (
            <>
              <AppText variant="h2" style={{ color: theme.colors.primary, marginTop: 16 }}>
                Credits
              </AppText>
              {reportData.creditLines.map((line) => (
                <View
                  key={line.transactionId}
                  style={[styles.lineItem, { borderBottomColor: theme.colors.border }]}
                >
                  <View style={styles.lineHeader}>
                    <AppText variant="body" style={{ fontWeight: '600', flex: 1 }}>
                      {line.title}
                    </AppText>
                    <AppText variant="body" style={{ fontWeight: '600' }}>
                      {formatCents(line.amountCents)}
                    </AppText>
                  </View>
                  {line.date && (
                    <AppText variant="caption">{line.date}</AppText>
                  )}
                  {line.budgetCategoryName && (
                    <AppText variant="caption">{line.budgetCategoryName}</AppText>
                  )}
                  {line.items.map((item) => (
                    <View key={item.id} style={styles.subItem}>
                      <AppText variant="caption" style={{ flex: 1 }}>
                        {item.name}
                      </AppText>
                      <AppText variant="caption">
                        {formatCents(item.projectPriceCents)}
                      </AppText>
                    </View>
                  ))}
                </View>
              ))}
            </>
          )}
        </AppScrollView>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 8,
    paddingTop: layout.screenBodyTopMd.paddingTop,
    paddingBottom: 40,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  headerButton: {
    padding: 8,
    minWidth: 40,
    minHeight: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
  card: {
    borderWidth: 1,
    borderRadius: 10,
    padding: 16,
    gap: 8,
  },
  totalRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  netRow: {
    borderTopWidth: 1,
    paddingTop: 10,
    marginTop: 4,
  },
  lineItem: {
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    gap: 2,
  },
  lineHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 8,
  },
  subItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingLeft: 12,
    marginTop: 2,
  },
});
