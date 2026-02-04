import { useCallback, useEffect, useState } from 'react';
import { subscribeToProjects, ProjectSummary } from '../data/scopedListData';
import { Item, listItemsByProject } from '../data/itemsService';

export type UseOutsideItemsOptions = {
  accountId: string | null;
  currentProjectId: string | null;
  scope: 'project' | 'inventory';
  includeInventory?: boolean;
};

export type UseOutsideItemsResult = {
  items: Item[];
  loading: boolean;
  error: string | null;
  reload: () => Promise<void>;
};

/**
 * Hook to fetch items from outside the current scope (other projects + optional inventory).
 * Used by add-existing-item pickers to show items available from other contexts.
 */
export function useOutsideItems({
  accountId,
  currentProjectId,
  scope,
  includeInventory = true,
}: UseOutsideItemsOptions): UseOutsideItemsResult {
  const [items, setItems] = useState<Item[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [projects, setProjects] = useState<ProjectSummary[]>([]);

  // Subscribe to projects list
  useEffect(() => {
    if (!accountId) {
      setProjects([]);
      return;
    }
    return subscribeToProjects(accountId, (next) => setProjects(next));
  }, [accountId]);

  const loadItems = useCallback(async () => {
    if (!accountId) {
      setItems([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const otherProjects = projects.filter((project) => project.id !== currentProjectId);
      const requests: Promise<Item[]>[] = [];

      // Include inventory items if requested
      if (includeInventory && scope === 'project') {
        requests.push(listItemsByProject(accountId, null, { mode: 'offline' }));
      }

      // Include items from other projects
      requests.push(...otherProjects.map((project) => listItemsByProject(accountId, project.id, { mode: 'offline' })));

      const results = await Promise.all(requests);
      const flattened = results.flat().filter((item) => item.projectId !== currentProjectId);
      
      // Deduplicate by id
      const unique = new Map(flattened.map((item) => [item.id, item]));
      setItems(Array.from(unique.values()));
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to load outside items.';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [accountId, currentProjectId, projects, scope, includeInventory]);

  return {
    items,
    loading,
    error,
    reload: loadItems,
  };
}
