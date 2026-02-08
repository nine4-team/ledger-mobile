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
import { subscribeToSpaces, type Space } from '../data/spacesService';
import { createProjectScopeConfig } from '../data/scopeConfig';
import {
  subscribeToScopedTransactions,
  subscribeToScopedItems,
  type ScopedTransaction,
  type ScopedItem,
} from '../data/scopedListData';
import {
  computeClientSummaryData,
  formatCents,
  type ClientSummaryData,
} from '../data/reportDataService';
import {
  generateClientSummaryHtml,
  type ReportHeaderParams,
} from '../utils/reportHtml';

type Props = {
  projectId: string;
};

export function ProjectClientSummaryReport({ projectId }: Props) {
  const router = useRouter();
  const theme = useTheme();
  const accountId = useAccountContextStore((s) => s.accountId);

  // Data state
  const [project, setProject] = useState<Project | null>(null);
  const [transactions, setTransactions] = useState<ScopedTransaction[]>([]);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [spaces, setSpaces] = useState<Space[]>([]);
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
    if (!accountId || !projectId) return;
    return subscribeToSpaces(accountId, projectId, setSpaces);
  }, [accountId, projectId]);

  useEffect(() => {
    if (!accountId) return;
    return subscribeToBusinessProfile(accountId, setBusinessProfile);
  }, [accountId]);

  // Compute report data
  const reportData: ClientSummaryData | null = useMemo(() => {
    if (!project) return null;
    return computeClientSummaryData(
      items as any,
      transactions as any,
      budgetCategories,
      spaces,
    );
  }, [items, transactions, budgetCategories, spaces, project]);

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
    return generateClientSummaryHtml(reportData, headerParams);
  }, [reportData, headerParams]);

  // Actions
  const handleShare = useCallback(async () => {
    if (!htmlContent) return;
    try {
      const { uri } = await Print.printToFileAsync({ html: htmlContent });
      await Sharing.shareAsync(uri, { mimeType: 'application/pdf' });
    } catch (err) {
      console.warn('[ProjectClientSummaryReport] share failed', err);
    }
  }, [htmlContent]);

  const handlePrint = useCallback(async () => {
    if (!htmlContent) return;
    try {
      await Print.printAsync({ html: htmlContent });
    } catch (err) {
      console.warn('[ProjectClientSummaryReport] print failed', err);
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
    <Screen title="Client Summary" backTarget={backTarget} headerRight={rightActions}>
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
            No items found for this project.
          </AppText>
        </View>
      ) : (
        <AppScrollView contentContainerStyle={styles.container}>
          {/* Overview Cards */}
          <View style={styles.overviewRow}>
            <View style={[styles.overviewCard, { backgroundColor: theme.colors.background, borderColor: theme.colors.border }]}>
              <AppText variant="caption">Total Spent</AppText>
              <AppText variant="h2">{formatCents(reportData.totalSpentCents)}</AppText>
            </View>
            <View style={[styles.overviewCard, { backgroundColor: theme.colors.background, borderColor: theme.colors.border }]}>
              <AppText variant="caption">Market Value</AppText>
              <AppText variant="h2">{formatCents(reportData.totalMarketValueCents)}</AppText>
            </View>
          </View>
          <View style={[styles.overviewCardFull, { backgroundColor: theme.colors.background, borderColor: theme.colors.border }]}>
            <AppText variant="caption">Total Saved</AppText>
            <AppText variant="h2" style={{ color: reportData.totalSavedCents >= 0 ? '#27ae60' : '#c0392b' }}>
              {formatCents(reportData.totalSavedCents)}
            </AppText>
          </View>

          {/* Category Breakdown */}
          {reportData.categoryBreakdown.length > 0 && (
            <>
              <AppText variant="h2" style={{ color: theme.colors.primary, marginTop: 16 }}>
                Category Breakdown
              </AppText>
              <View style={[styles.tableCard, { borderColor: theme.colors.border }]}>
                {reportData.categoryBreakdown.map((entry, index) => (
                  <View
                    key={entry.categoryName}
                    style={[
                      styles.tableRow,
                      index < reportData.categoryBreakdown.length - 1 && { borderBottomColor: theme.colors.border, borderBottomWidth: StyleSheet.hairlineWidth },
                    ]}
                  >
                    <AppText variant="body" style={{ flex: 1 }}>
                      {entry.categoryName}
                    </AppText>
                    <AppText variant="body" style={{ fontWeight: '600' }}>
                      {formatCents(entry.totalCents)}
                    </AppText>
                  </View>
                ))}
              </View>
            </>
          )}

          {/* Items List */}
          <AppText variant="h2" style={{ color: theme.colors.primary, marginTop: 16 }}>
            Items ({reportData.items.length})
          </AppText>
          {reportData.items.map((item) => (
            <View
              key={item.id}
              style={[styles.itemRow, { borderBottomColor: theme.colors.border }]}
            >
              <View style={styles.itemHeader}>
                <View style={{ flex: 1 }}>
                  <View style={styles.itemNameRow}>
                    <AppText variant="body" style={{ fontWeight: '600' }}>
                      {item.name}
                    </AppText>
                    {item.receiptLink && (
                      <View style={[styles.receiptBadge, { backgroundColor: theme.colors.primary + '18' }]}>
                        <AppText variant="caption" style={{ fontSize: 10, fontWeight: '600', color: theme.colors.primary }}>
                          {item.receiptLink.type === 'invoice'
                            ? 'Invoice'
                            : item.receiptLink.type === 'receipt-url'
                              ? 'Receipt'
                              : 'Pending'}
                        </AppText>
                      </View>
                    )}
                  </View>
                  {item.source && (
                    <AppText variant="caption">{item.source}</AppText>
                  )}
                  {item.spaceName && (
                    <AppText variant="caption">{item.spaceName}</AppText>
                  )}
                </View>
                <AppText variant="body" style={{ fontWeight: '600' }}>
                  {formatCents(item.projectPriceCents)}
                </AppText>
              </View>
            </View>
          ))}
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
  overviewRow: {
    flexDirection: 'row',
    gap: 10,
  },
  overviewCard: {
    flex: 1,
    borderWidth: 1,
    borderRadius: 10,
    padding: 14,
    gap: 4,
  },
  overviewCardFull: {
    borderWidth: 1,
    borderRadius: 10,
    padding: 14,
    gap: 4,
  },
  tableCard: {
    borderWidth: 1,
    borderRadius: 10,
    overflow: 'hidden',
  },
  tableRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  itemRow: {
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  itemHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 8,
  },
  itemNameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    flexWrap: 'wrap',
  },
  receiptBadge: {
    borderRadius: 4,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
});
