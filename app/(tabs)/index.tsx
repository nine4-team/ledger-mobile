import { Image, Pressable, RefreshControl, StyleSheet, View } from 'react-native';
import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'expo-router';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { AppText } from '../../src/components/AppText';
import { Screen } from '../../src/components/Screen';
import { BudgetProgress } from '../../src/components/BudgetProgress';
import { layout } from '../../src/ui';
import { AppButton } from '../../src/components/AppButton';
import { AppScrollView } from '../../src/components/AppScrollView';
import { ScreenTabItem, useScreenTabs } from '../../src/components/ScreenTabs';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { createRepository } from '../../src/data/repository';
import { useAuthStore } from '../../src/auth/authStore';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../../src/data/budgetCategoriesService';
import { fetchProjectPreferencesMap, ensureProjectPreferences } from '../../src/data/projectPreferencesService';
import { ProjectBudgetCategory } from '../../src/data/projectBudgetCategoriesService';
import { refreshProjectBudgetProgress } from '../../src/data/budgetProgressService';
import { resolveAttachmentUri } from '../../src/offline/media';

export default function ProjectsScreen() {
  return (
    <Screen
      title="Projects"
      tabs={PROJECT_TABS}
      hideBackButton={true}
      includeBottomInset={false}
      infoContent={{
        title: 'Projects',
        message: 'Manage your projects here. Create new projects, view active and archived projects, and track budgets.',
      }}
    >
      <ProjectsList />
    </Screen>
  );
}

const PROJECT_TABS: ScreenTabItem[] = [
  { key: 'active', label: 'Active', accessibilityLabel: 'Active projects' },
  { key: 'archived', label: 'Archived', accessibilityLabel: 'Archived projects' },
];

type ProjectSummary = {
  id: string;
  name?: string | null;
  clientName?: string | null;
  isArchived?: boolean | null;
  mainImageUrl?: string | null;
  budgetSummary?: {
    totalCents?: number | null;
    pinnedCategories?: { id: string; name?: string | null; spentCents?: number | null }[];
  } | null;
};

function ProjectsList() {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const userId = useAuthStore((store) => store.user?.uid ?? null);
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isHydrated, setIsHydrated] = useState(false);
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { id: string; name: string }>>({});
  const [projectPreferences, setProjectPreferences] = useState<Record<string, { pinnedBudgetCategoryIds: string[] }>>({});
  const [budgetTotals, setBudgetTotals] = useState<Record<string, number>>({});
  const [budgetSpentTotals, setBudgetSpentTotals] = useState<Record<string, number>>({});
  const screenTabs = useScreenTabs();
  const tabKey = screenTabs?.selectedKey === 'archived' ? 'archived' : 'active';
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  useEffect(() => {
    if (!accountId) {
      setProjects([]);
      setIsLoading(false);
    }
  }, [accountId]);

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
    if (!accountId) {
      setIsHydrated(true);
      return;
    }
    const storageKey = `projects:list:cache:${accountId}`;
    AsyncStorage.getItem(storageKey)
      .then((stored) => {
        if (!stored) return;
        try {
          const parsed = JSON.parse(stored) as ProjectSummary[];
          if (Array.isArray(parsed) && parsed.length > 0) {
            setProjects(parsed);
          }
        } catch {
          // ignore parse failures
        }
      })
      .finally(() => setIsHydrated(true));
  }, [accountId]);

  useEffect(() => {
    if (!accountId) {
      setProjects([]);
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    const repo = createRepository<ProjectSummary>(`accounts/${accountId}/projects`, 'offline');
    const unsubscribe = repo.subscribeList((next) => {
      setProjects(next);
      setIsLoading(false);
      const storageKey = `projects:list:cache:${accountId}`;
      void AsyncStorage.setItem(storageKey, JSON.stringify(next));
    });
    return () => unsubscribe();
  }, [accountId]);

  useEffect(() => {
    if (!accountId || !userId || projects.length === 0) {
      setProjectPreferences({});
      return;
    }
    const projectIds = projects.map((project) => project.id);
    fetchProjectPreferencesMap({ accountId, userId, projectIds })
      .then((prefs) => {
        setProjectPreferences(prefs);
        const furnishings = Object.values(budgetCategories).find(
          (category) => category.name.toLowerCase() === 'furnishings'
        );
        projectIds.forEach((projectId) => {
          if (!prefs[projectId]) {
            void ensureProjectPreferences(accountId, projectId, furnishings ? [furnishings.id] : []);
          }
        });
      })
      .catch(() => {
        setProjectPreferences({});
      });
  }, [accountId, budgetCategories, projects, userId]);

  useEffect(() => {
    if (!accountId || projects.length === 0) {
      setBudgetTotals({});
      return;
    }
    let cancelled = false;
    const loadTotals = async () => {
      const totals: Record<string, number> = {};
      await Promise.all(
        projects.map(async (project) => {
          const repo = createRepository<ProjectBudgetCategory>(
            `accounts/${accountId}/projects/${project.id}/budgetCategories`,
            'offline'
          );
          const categories = await repo.list();
          totals[project.id] = categories.reduce((sum, category) => sum + (category.budgetCents ?? 0), 0);
        })
      );
      if (!cancelled) {
        setBudgetTotals(totals);
      }
    };
    void loadTotals();
    return () => {
      cancelled = true;
    };
  }, [accountId, projects]);

  useEffect(() => {
    if (!accountId || projects.length === 0) {
      setBudgetSpentTotals({});
      return;
    }
    let cancelled = false;
    const loadSpentTotals = async () => {
      const totals: Record<string, number> = {};
      await Promise.all(
        projects.map(async (project) => {
          const progress = await refreshProjectBudgetProgress(accountId, project.id, 'offline');
          totals[project.id] = progress.spentCents;
        })
      );
      if (!cancelled) {
        setBudgetSpentTotals(totals);
      }
    };
    void loadSpentTotals();
    return () => {
      cancelled = true;
    };
  }, [accountId, projects]);

  const sortedProjects = useMemo(() => {
    const filtered =
      tabKey === 'archived'
        ? projects.filter((project) => project.isArchived)
        : projects.filter((project) => !project.isArchived);
    return [...filtered].sort((a, b) => {
      const nameA = a.name?.toLowerCase() ?? '';
      const nameB = b.name?.toLowerCase() ?? '';
      if (nameA && nameB) return nameA.localeCompare(nameB);
      if (nameA) return -1;
      if (nameB) return 1;
      return a.id.localeCompare(b.id);
    });
  }, [projects, tabKey]);

  const handleRefresh = async () => {
    if (!accountId || isRefreshing) return;
    setIsRefreshing(true);
    try {
      const repo = createRepository<ProjectSummary>(`accounts/${accountId}/projects`, 'online');
      const next = await repo.list();
      setProjects(next);
    } finally {
      setIsRefreshing(false);
    }
  };

  return (
    <AppScrollView
      style={styles.scroll}
      contentContainerStyle={[styles.placeholder, styles.scrollContent]}
      refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={handleRefresh} />}
    >
      {!accountId ? (
        <View style={styles.emptyState}>
          <AppText variant="body">
            No Account Selected.
          </AppText>
          <AppButton title="Choose account" onPress={() => router.replace('/account-select')} />
        </View>
      ) : isLoading && !isHydrated ? (
        <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
          Loading projects…
        </AppText>
      ) : (
        <>
          {sortedProjects.length === 0 ? (
            <View style={styles.emptyStateContainer}>
              <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                {tabKey === 'archived' ? 'No archived projects yet.' : 'No active projects yet.'}
              </AppText>
              {tabKey !== 'archived' && (
                <AppButton title="New project" onPress={() => router.push('/project/new')} />
              )}
            </View>
          ) : (
            <>
              <View style={styles.projectList}>
                {sortedProjects.map((project) => (
                  <Pressable
                    key={project.id}
                    onPress={() => router.push(`/project/${project.id}?tab=items`)}
                    style={({ pressed }) => [
                      styles.projectRow,
                      {
                        borderColor: uiKitTheme.border.primary,
                        backgroundColor: uiKitTheme.background.surface,
                        opacity: pressed ? 0.8 : 1,
                      },
                    ]}
                  >
                    {project.mainImageUrl && !project.mainImageUrl.startsWith('offline://') ? (
                      <Image
                        source={{ uri: resolveAttachmentUri({ url: project.mainImageUrl, kind: 'image' }) ?? project.mainImageUrl }}
                        style={styles.projectImage}
                      />
                    ) : project.mainImageUrl && project.mainImageUrl.startsWith('offline://') ? (
                      (() => {
                        const resolved = resolveAttachmentUri({ url: project.mainImageUrl, kind: 'image' });
                        return resolved ? (
                          <Image
                            source={{ uri: resolved }}
                            style={styles.projectImage}
                          />
                        ) : (
                          <View
                            style={[
                              styles.projectImage,
                              { backgroundColor: uiKitTheme.background.subtle ?? uiKitTheme.background.surface, alignItems: 'center', justifyContent: 'center' },
                            ]}
                          >
                            <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>Offline</AppText>
                          </View>
                        );
                      })()
                    ) : (
                      <View
                        style={[
                          styles.projectImage,
                          { backgroundColor: uiKitTheme.background.subtle ?? uiKitTheme.background.surface },
                        ]}
                      />
                    )}
                    <AppText variant="body" style={styles.projectTitle}>
                      {project.name?.trim() ? project.name.trim() : 'Project'}
                    </AppText>
                    <AppText variant="caption" style={styles.projectSub}>
                      {project.clientName?.trim() ? project.clientName.trim() : 'No client name'}
                    </AppText>
                    <View style={styles.budgetRow}>
                      <AppText variant="caption">
                        {typeof budgetTotals[project.id] === 'number'
                          ? `Budget: $${(budgetTotals[project.id] / 100).toFixed(2)}`
                          : 'Budget not set'}
                      </AppText>
                      {typeof budgetTotals[project.id] === 'number' ? (
                        <BudgetProgress
                          spentCents={budgetSpentTotals[project.id] ?? 0}
                          budgetCents={budgetTotals[project.id] ?? 0}
                          compact
                        />
                      ) : null}
                      {projectPreferences[project.id]?.pinnedBudgetCategoryIds?.length ? (
                        <AppText variant="caption" style={styles.budgetPins}>
                          {projectPreferences[project.id].pinnedBudgetCategoryIds
                            .slice(0, 2)
                            .map((categoryId) => budgetCategories[categoryId]?.name ?? categoryId)
                            .join(' • ')}
                        </AppText>
                      ) : null}
                      <AppText variant="caption" style={styles.openProject}>
                        Open Project
                      </AppText>
                    </View>
                  </Pressable>
                ))}
              </View>
              <View style={styles.actions}>
                <AppButton title="New project" onPress={() => router.push('/project/new')} />
              </View>
            </>
          )}
        </>
      )}
    </AppScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  placeholder: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
    gap: 12,
  },
  scrollContent: {
    flexGrow: 1,
  },
  actions: {
    alignItems: 'center',
    gap: 12,
  },
  emptyState: {
    gap: 12,
  },
  emptyStateContainer: {
    alignItems: 'center',
    gap: 12,
  },
  projectList: {
    gap: 10,
  },
  projectRow: {
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 14,
    gap: 6,
  },
  projectImage: {
    width: '100%',
    height: 120,
    borderRadius: 10,
  },
  projectTitle: {
    fontWeight: '600',
  },
  projectSub: {
    marginTop: 4,
  },
  budgetRow: {
    gap: 4,
  },
  budgetPins: {
    opacity: 0.8,
  },
  openProject: {
    marginTop: 4,
    opacity: 0.7,
  },
});
