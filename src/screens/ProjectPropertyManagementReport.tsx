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
import { subscribeToBusinessProfile, type BusinessProfile } from '../data/businessProfileService';
import { subscribeToSpaces, type Space } from '../data/spacesService';
import { createProjectScopeConfig } from '../data/scopeConfig';
import {
  subscribeToScopedItems,
  type ScopedItem,
} from '../data/scopedListData';
import {
  computePropertyManagementData,
  formatCents,
  type PropertyManagementData,
} from '../data/reportDataService';
import {
  generatePropertyManagementHtml,
  type ReportHeaderParams,
} from '../utils/reportHtml';

type Props = {
  projectId: string;
};

export function ProjectPropertyManagementReport({ projectId }: Props) {
  const router = useRouter();
  const theme = useTheme();
  const accountId = useAccountContextStore((s) => s.accountId);

  // Data state
  const [project, setProject] = useState<Project | null>(null);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [spaces, setSpaces] = useState<Space[]>([]);
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
  const reportData: PropertyManagementData | null = useMemo(() => {
    if (!project) return null;
    return computePropertyManagementData(items as any, spaces);
  }, [items, spaces, project]);

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
    return generatePropertyManagementHtml(reportData, headerParams);
  }, [reportData, headerParams]);

  // Actions
  const handleShare = useCallback(async () => {
    if (!htmlContent) return;
    try {
      const { uri } = await Print.printToFileAsync({ html: htmlContent });
      await Sharing.shareAsync(uri, { mimeType: 'application/pdf' });
    } catch (err) {
      console.warn('[ProjectPropertyManagementReport] share failed', err);
    }
  }, [htmlContent]);

  const handlePrint = useCallback(async () => {
    if (!htmlContent) return;
    try {
      await Print.printAsync({ html: htmlContent });
    } catch (err) {
      console.warn('[ProjectPropertyManagementReport] print failed', err);
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
    <Screen title="Property Management" backTarget={backTarget} headerRight={rightActions}>
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
          {/* Summary Cards */}
          <View style={styles.overviewRow}>
            <View style={[styles.overviewCard, { backgroundColor: theme.colors.background, borderColor: theme.colors.border }]}>
              <AppText variant="caption">Total Items</AppText>
              <AppText variant="h2">{reportData.totalItems}</AppText>
            </View>
            <View style={[styles.overviewCard, { backgroundColor: theme.colors.background, borderColor: theme.colors.border }]}>
              <AppText variant="caption">Market Value</AppText>
              <AppText variant="h2">{formatCents(reportData.totalMarketValueCents)}</AppText>
            </View>
          </View>

          {/* Items List */}
          <AppText variant="h2" style={{ color: theme.colors.primary, marginTop: 16 }}>
            Items
          </AppText>
          {reportData.items.map((item) => (
            <View
              key={item.id}
              style={[styles.itemRow, { borderBottomColor: theme.colors.border }]}
            >
              <View style={styles.itemHeader}>
                <View style={{ flex: 1 }}>
                  <AppText variant="body" style={{ fontWeight: '600' }}>
                    {item.name}
                  </AppText>
                  <View style={styles.metaRow}>
                    {item.source && (
                      <AppText variant="caption">{item.source}</AppText>
                    )}
                    {item.sku && (
                      <AppText variant="caption">SKU: {item.sku}</AppText>
                    )}
                    {item.spaceName && (
                      <AppText variant="caption">{item.spaceName}</AppText>
                    )}
                  </View>
                </View>
                <View style={styles.valueColumn}>
                  {item.hasNoMarketValue ? (
                    <AppText
                      variant="caption"
                      style={{ fontStyle: 'italic', color: theme.colors.textSecondary }}
                    >
                      No market value
                    </AppText>
                  ) : (
                    <AppText variant="body" style={{ fontWeight: '600' }}>
                      {formatCents(item.marketValueCents)}
                    </AppText>
                  )}
                </View>
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
  metaRow: {
    gap: 1,
    marginTop: 2,
  },
  valueColumn: {
    alignItems: 'flex-end',
    flexShrink: 0,
  },
});
