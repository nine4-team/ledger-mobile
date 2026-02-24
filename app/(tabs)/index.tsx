import { Pressable, RefreshControl, StyleSheet, View } from 'react-native';
import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'expo-router';
import AsyncStorage from '@react-native-async-storage/async-storage';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { AppText } from '../../src/components/AppText';
import { Screen } from '../../src/components/Screen';
import { layout } from '../../src/ui';
import { AppButton } from '../../src/components/AppButton';
import { AppScrollView } from '../../src/components/AppScrollView';
import { ScreenTabItem, useScreenTabs } from '../../src/components/ScreenTabs';
import { useTheme } from '../../src/theme/ThemeProvider';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { createRepository } from '../../src/data/repository';
import { useAuthStore } from '../../src/auth/authStore';
import { fetchProjectPreferencesMap, ensureProjectPreferences, type ProjectPreferences } from '../../src/data/projectPreferencesService';
import { ProjectCard } from '../../src/components/ProjectCard';
import type { ProjectBudgetSummary } from '../../src/data/projectService';

export default function ProjectsScreen() {
  const router = useRouter();
  const theme = useTheme();

  return (
    <Screen
      title="Projects"
      tabs={PROJECT_TABS}
      hideBackButton={true}
      includeBottomInset={false}
      hideMenu={true}
      headerRight={
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Search"
          hitSlop={10}
          onPress={() => router.push('/search')}
          style={({ pressed }) => [styles.headerIconButton, pressed && { opacity: 0.7 }]}
        >
          <MaterialIcons name="search" size={24} color={theme.colors.primary} />
        </Pressable>
      }
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
  budgetSummary?: ProjectBudgetSummary | null;
};

function ProjectsList() {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const userId = useAuthStore((store) => store.user?.uid ?? null);
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isHydrated, setIsHydrated] = useState(false);
  const [projectPreferences, setProjectPreferences] = useState<Record<string, { pinnedBudgetCategoryIds: string[] }>>({});
  const screenTabs = useScreenTabs();
  const tabKey = screenTabs?.selectedKey === 'archived' ? 'archived' : 'active';
  const theme = useTheme();

  useEffect(() => {
    if (!accountId) {
      setProjects([]);
      setIsLoading(false);
    }
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
      .then(async (prefs) => {
        setProjectPreferences(prefs);

        const missingIds = projectIds.filter((id) => !prefs[id]);
        if (missingIds.length === 0) return;

        const results = await Promise.all(
          missingIds.map((id) =>
            ensureProjectPreferences(accountId, id).catch(() => null)
          )
        );

        const seeded: Record<string, ProjectPreferences> = {};
        results.forEach((r) => {
          if (r) seeded[r.projectId] = r;
        });

        if (Object.keys(seeded).length > 0) {
          setProjectPreferences((prev) => ({ ...prev, ...seeded }));
        }
      })
      .catch(() => {
        setProjectPreferences({});
      });
  }, [accountId, projects, userId]);

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
          <AppButton title="Choose Account" onPress={() => router.replace('/account-select')} />
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
            </View>
          ) : (
            <View style={styles.projectList}>
              {sortedProjects.map((project) => (
                <ProjectCard
                  key={project.id}
                  projectId={project.id}
                  name={project.name}
                  clientName={project.clientName}
                  mainImageUrl={project.mainImageUrl}
                  budgetSummary={project.budgetSummary ?? null}
                  pinnedCategoryIds={projectPreferences[project.id]?.pinnedBudgetCategoryIds ?? []}
                  onPress={() => router.push(`/project/${project.id}?tab=items`)}
                />
              ))}
            </View>
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
  headerIconButton: {
    padding: 12,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 48,
    minHeight: 48,
  },
});
