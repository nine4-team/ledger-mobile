import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Image, StyleSheet, View } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useRouter } from 'expo-router';
import { Screen } from '../components/Screen';
import { useScreenTabs } from '../components/ScreenTabs';
import { AppText } from '../components/AppText';
import { AppButton } from '../components/AppButton';
import { SharedItemsList } from '../components/SharedItemsList';
import { SharedTransactionsList } from '../components/SharedTransactionsList';
import { useAccountContextStore } from '../auth/accountContextStore';
import { useAuthStore } from '../auth/authStore';
import { createProjectScopeConfig, getListStateKey } from '../data/scopeConfig';
import { useScopeSwitching } from '../data/useScopeSwitching';
import { Project, deleteProject, subscribeToProject } from '../data/projectService';
import { mapBudgetCategories, refreshBudgetCategories, subscribeToBudgetCategories } from '../data/budgetCategoriesService';
import { subscribeToProjectPreferences } from '../data/projectPreferencesService';
import { refreshProjectBudgetCategories, subscribeToProjectBudgetCategories } from '../data/projectBudgetCategoriesService';
import { refreshSpaces } from '../data/spacesService';
import { refreshScopedItems, refreshScopedTransactions } from '../data/scopedListData';
import { createRepository } from '../data/repository';
import { layout } from '../ui';
import { useNetworkStatus } from '../hooks/useNetworkStatus';
import { resolveAttachmentUri } from '../offline/media';
import { ProjectSpacesList } from './ProjectSpacesList';

type ProjectShellProps = {
  projectId: string;
  initialTabKey?: 'items' | 'transactions' | 'spaces';
};

export function ProjectShell({ projectId, initialTabKey }: ProjectShellProps) {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const userId = useAuthStore((store) => store.user?.uid ?? null);
  const { isOnline } = useNetworkStatus();
  const isFocused = useIsFocused();
  const [project, setProject] = useState<Project | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [refreshError, setRefreshError] = useState<string | null>(null);
  const [refreshToken, setRefreshToken] = useState(0);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { id: string; name: string }>>({});
  const [pinnedBudgetCategoryIds, setPinnedBudgetCategoryIds] = useState<string[]>([]);
  const [budgetTotalCents, setBudgetTotalCents] = useState<number | null>(null);
  const wasOnlineRef = useRef(isOnline);
  const scopeConfig = useMemo(() => createProjectScopeConfig(projectId), [projectId]);
  useScopeSwitching(scopeConfig, { isActive: isFocused });

  useEffect(() => {
    if (!accountId || !projectId) {
      setProject(null);
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    const unsubscribe = subscribeToProject(accountId, projectId, (next) => {
      setProject(next);
      setIsLoading(false);
    });
    return () => unsubscribe();
  }, [accountId, projectId]);

  useEffect(() => {
    if (!accountId) {
      setBudgetCategories({});
      return;
    }
    return subscribeToBudgetCategories(accountId, (next) => {
      setBudgetCategories(mapBudgetCategories(next));
    });
  }, [accountId]);

  useEffect(() => {
    if (!accountId || !userId || !projectId) {
      setPinnedBudgetCategoryIds([]);
      return;
    }
    return subscribeToProjectPreferences(accountId, userId, projectId, (prefs) => {
      setPinnedBudgetCategoryIds(prefs?.pinnedBudgetCategoryIds ?? []);
    });
  }, [accountId, projectId, userId]);

  useEffect(() => {
    if (!accountId || !projectId) {
      setBudgetTotalCents(null);
      return;
    }
    return subscribeToProjectBudgetCategories(accountId, projectId, (categories) => {
      const total = categories.reduce((sum, category) => sum + (category.budgetCents ?? 0), 0);
      setBudgetTotalCents(total);
    });
  }, [accountId, projectId]);

  const handleRefresh = useCallback(async () => {
    if (!accountId || isRefreshing) return;
    setIsRefreshing(true);
    setRefreshError(null);
    try {
      const repo = createRepository<Project>(`accounts/${accountId}/projects`, 'online');
      const next = await repo.get(projectId);
      setProject(next);
      await Promise.all([
        refreshScopedItems(accountId, scopeConfig, 'online'),
        refreshScopedTransactions(accountId, scopeConfig, 'online'),
        refreshSpaces(accountId, projectId, 'online'),
        refreshBudgetCategories(accountId, 'online'),
        refreshProjectBudgetCategories(accountId, projectId, 'online'),
      ]);
      setRefreshToken((prev) => prev + 1);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to refresh project.';
      setRefreshError(message);
    } finally {
      setIsRefreshing(false);
    }
  }, [accountId, isRefreshing, projectId, scopeConfig]);

  useEffect(() => {
    if (wasOnlineRef.current && isOnline) return;
    if (!wasOnlineRef.current && isOnline) {
      void handleRefresh();
    }
    wasOnlineRef.current = isOnline;
  }, [handleRefresh, isOnline]);

  const handleDelete = useCallback(() => {
    if (!accountId) return;
    Alert.alert('Delete project', 'This will permanently delete this project.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          await deleteProject(accountId, projectId);
          router.replace('/(tabs)');
        },
      },
    ]);
  }, [accountId, projectId, router]);

  return (
    <Screen
      title={project?.name?.trim() || 'Project'}
      tabs={[
        { key: 'items', label: 'Items', accessibilityLabel: 'Items tab' },
        { key: 'transactions', label: 'Transactions', accessibilityLabel: 'Transactions tab' },
        { key: 'spaces', label: 'Spaces', accessibilityLabel: 'Spaces tab' },
      ]}
      initialTabKey={initialTabKey ?? 'items'}
    >
      <ProjectShellContent
        projectId={projectId}
        project={project}
        isOnline={isOnline}
        isLoading={isLoading}
        isRefreshing={isRefreshing}
        refreshError={refreshError}
        refreshToken={refreshToken}
        onEdit={() => router.push(`/project/${projectId}/edit`)}
        onRefresh={handleRefresh}
        onDelete={handleDelete}
        scopeConfig={scopeConfig}
        budgetCategories={budgetCategories}
        pinnedBudgetCategoryIds={pinnedBudgetCategoryIds}
        budgetTotalCents={budgetTotalCents}
      />
    </Screen>
  );
}

type ProjectShellContentProps = {
  projectId: string;
  project: Project | null;
  isOnline: boolean;
  isLoading: boolean;
  isRefreshing: boolean;
  refreshError: string | null;
  refreshToken: number;
  onEdit: () => void;
  onRefresh: () => void;
  onDelete: () => void;
  scopeConfig: ReturnType<typeof createProjectScopeConfig>;
  budgetCategories: Record<string, { id: string; name: string }>;
  pinnedBudgetCategoryIds: string[];
  budgetTotalCents: number | null;
};

function ProjectShellContent({
  projectId,
  project,
  isOnline,
  isLoading,
  isRefreshing,
  refreshError,
  refreshToken,
  onEdit,
  onRefresh,
  onDelete,
  scopeConfig,
  budgetCategories,
  pinnedBudgetCategoryIds,
  budgetTotalCents,
}: ProjectShellContentProps) {
  const screenTabs = useScreenTabs();
  const selectedKey = screenTabs?.selectedKey ?? 'items';
  const listStateKeyItems = getListStateKey(scopeConfig, 'items');
  const listStateKeyTransactions = getListStateKey(scopeConfig, 'transactions');

  return (
    <>
      <View style={styles.projectHeader}>
        {project?.mainImageUrl ? (
          <Image
            source={{
              uri:
                resolveAttachmentUri({ url: project.mainImageUrl, kind: 'image' }) ??
                project.mainImageUrl,
            }}
            style={styles.projectImage}
          />
        ) : null}
        <AppText variant="title">{project?.name?.trim() || 'Project'}</AppText>
        <AppText variant="caption">
          {project?.clientName?.trim() ? project.clientName.trim() : 'No client name'}
        </AppText>
        <View style={styles.budgetPreview}>
          <AppText variant="caption">
            {typeof budgetTotalCents === 'number'
              ? `Budget: $${(budgetTotalCents / 100).toFixed(2)}`
              : 'Budget not set'}
          </AppText>
          {pinnedBudgetCategoryIds.length ? (
            <AppText variant="caption" style={styles.budgetPins}>
              {pinnedBudgetCategoryIds
                .slice(0, 2)
                .map((id) => budgetCategories[id]?.name ?? id)
                .join(' • ')}
            </AppText>
          ) : null}
        </View>
      </View>
      <View style={styles.headerRow}>
        <AppText variant="caption">
          {project?.clientName?.trim() ? project.clientName.trim() : 'No client name'}
        </AppText>
        <AppText variant="caption">
          {isOnline ? 'Online' : 'Offline'}
        </AppText>
      </View>
      <View style={styles.actions}>
        <AppButton title="Edit" variant="secondary" onPress={onEdit} />
        <AppButton
          title={isRefreshing ? 'Refreshing…' : 'Refresh'}
          variant="secondary"
          onPress={onRefresh}
          disabled={isRefreshing}
        />
        <AppButton title="Delete" variant="secondary" onPress={onDelete} />
      </View>
      {refreshError ? (
        <AppText variant="caption" style={styles.refreshError}>
          {isOnline ? refreshError : 'Offline. Refresh will run when you reconnect.'}
        </AppText>
      ) : null}
      {isLoading ? (
        <AppText variant="body">Loading project…</AppText>
      ) : !project ? (
        <AppText variant="body">
          {isOnline ? 'Project not found.' : 'Offline. Project data unavailable.'}
        </AppText>
      ) : selectedKey === 'items' && listStateKeyItems ? (
        <SharedItemsList
          scopeConfig={scopeConfig}
          listStateKey={listStateKeyItems}
          refreshToken={refreshToken}
        />
      ) : selectedKey === 'transactions' && listStateKeyTransactions ? (
        <SharedTransactionsList
          scopeConfig={scopeConfig}
          listStateKey={listStateKeyTransactions}
          refreshToken={refreshToken}
        />
      ) : (
        <ProjectSpacesList projectId={projectId} refreshToken={refreshToken} />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  projectHeader: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
    gap: 8,
  },
  projectImage: {
    width: '100%',
    height: 140,
    borderRadius: 12,
  },
  budgetPreview: {
    gap: 4,
  },
  budgetPins: {
    opacity: 0.8,
  },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 12,
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
    paddingVertical: 8,
  },
  refreshError: {
    paddingBottom: 8,
  },
});
