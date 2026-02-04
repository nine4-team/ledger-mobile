import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';

const STORAGE_KEY = 'ledger:listState:v1';
const MAX_ENTRIES = 20;
const PERSIST_DEBOUNCE_MS = 400;

export type ListRestoreHint = {
  anchorId?: string;
  scrollOffset?: number;
  updatedAtMs: number;
};

export type ListState = {
  search?: string;
  filters?: Record<string, unknown>;
  sort?: string;
  restore?: ListRestoreHint;
  updatedAtMs: number;
};

type ListStateRecord = Record<string, ListState>;

type ListStateStore = {
  isHydrated: boolean;
  listStateByKey: ListStateRecord;
  hydrate: () => Promise<void>;
  updateListState: (key: string, updater: (prev: ListState) => ListState) => void;
  clearListState: (key: string) => void;
  clearRestoreHint: (key: string) => void;
};

let persistTimer: ReturnType<typeof setTimeout> | null = null;

function schedulePersist(nextState: ListStateRecord) {
  if (persistTimer) {
    clearTimeout(persistTimer);
  }
  persistTimer = setTimeout(async () => {
    try {
      await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(nextState));
    } catch {
      // ignore persistence failures
    }
  }, PERSIST_DEBOUNCE_MS);
}

function pruneEntries(state: ListStateRecord): ListStateRecord {
  const entries = Object.entries(state);
  if (entries.length <= MAX_ENTRIES) return state;

  const sorted = entries.sort(([, a], [, b]) => a.updatedAtMs - b.updatedAtMs);
  const trimmed = sorted.slice(entries.length - MAX_ENTRIES);
  return Object.fromEntries(trimmed);
}

function safeParseState(raw: string | null): ListStateRecord {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as ListStateRecord;
    if (typeof parsed !== 'object' || parsed === null) {
      return {};
    }
    return parsed;
  } catch {
    return {};
  }
}

export const useListStateStore = create<ListStateStore>((set, get) => ({
  isHydrated: false,
  listStateByKey: {},
  hydrate: async () => {
    const stored = await AsyncStorage.getItem(STORAGE_KEY);
    const next = safeParseState(stored);
    set({ listStateByKey: next, isHydrated: true });
  },
  updateListState: (key, updater) => {
    const prev = get().listStateByKey[key] ?? { updatedAtMs: 0 };
    const nextState = updater(prev);
    const nextRecord = pruneEntries({
      ...get().listStateByKey,
      [key]: {
        ...nextState,
        updatedAtMs: Date.now(),
      },
    });
    set({ listStateByKey: nextRecord });
    schedulePersist(nextRecord);
  },
  clearListState: (key) => {
    const next = { ...get().listStateByKey };
    delete next[key];
    set({ listStateByKey: next });
    schedulePersist(next);
  },
  clearRestoreHint: (key) => {
    const prev = get().listStateByKey[key];
    if (!prev?.restore) return;
    const nextRecord = {
      ...get().listStateByKey,
      [key]: {
        ...prev,
        restore: undefined,
        updatedAtMs: Date.now(),
      },
    };
    set({ listStateByKey: nextRecord });
    schedulePersist(nextRecord);
  },
}));

export function useListState(key: string) {
  const listState = useListStateStore((state) => state.listStateByKey[key]);
  const updateListState = useListStateStore((state) => state.updateListState);
  const clearRestoreHint = useListStateStore((state) => state.clearRestoreHint);

  const state = listState ?? { updatedAtMs: 0 };

  return {
    state,
    setSearch: (search: string) =>
      updateListState(key, (prev) => ({ ...prev, search })),
    setFilters: (filters: Record<string, unknown>) =>
      updateListState(key, (prev) => ({ ...prev, filters })),
    setSort: (sort: string) =>
      updateListState(key, (prev) => ({ ...prev, sort })),
    setRestoreHint: (restore: Omit<ListRestoreHint, 'updatedAtMs'>) =>
      updateListState(key, (prev) => ({
        ...prev,
        restore: { ...restore, updatedAtMs: Date.now() },
      })),
    clearRestoreHint: () => clearRestoreHint(key),
  };
}
