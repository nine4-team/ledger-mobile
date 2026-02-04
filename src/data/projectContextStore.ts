import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';

const STORAGE_KEY = 'ledger:lastSelectedProjectId';

type ProjectContextState = {
  projectId: string | null;
  isHydrated: boolean;
  hydrate: () => Promise<void>;
  setProjectId: (projectId: string | null) => Promise<void>;
  clearProjectId: () => Promise<void>;
};

async function safeGetString(key: string): Promise<string | null> {
  try {
    return await AsyncStorage.getItem(key);
  } catch {
    return null;
  }
}

async function safeSetString(key: string, value: string | null): Promise<void> {
  try {
    if (value == null) {
      await AsyncStorage.removeItem(key);
      return;
    }
    await AsyncStorage.setItem(key, value);
  } catch {
    // ignore persistence failures
  }
}

export const useProjectContextStore = create<ProjectContextState>((set) => ({
  projectId: null,
  isHydrated: false,
  hydrate: async () => {
    const lastSelected = await safeGetString(STORAGE_KEY);
    set({ projectId: lastSelected ?? null, isHydrated: true });
  },
  setProjectId: async (projectId) => {
    const next = projectId?.trim() ? projectId.trim() : null;
    set({ projectId: next });
    await safeSetString(STORAGE_KEY, next);
  },
  clearProjectId: async () => {
    set({ projectId: null });
    await safeSetString(STORAGE_KEY, null);
  },
}));
