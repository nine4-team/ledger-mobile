import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';

const STORAGE_KEY = 'ledger:pendingInviteToken';

interface InviteTokenState {
  pendingToken: string | null;
  isHydrated: boolean;
  setPendingToken: (token: string | null) => Promise<void>;
  clearPendingToken: () => Promise<void>;
  hydrate: () => Promise<void>;
}

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
    // ignore storage failures
  }
}

export const useInviteTokenStore = create<InviteTokenState>((set) => ({
  pendingToken: null,
  isHydrated: false,

  hydrate: async () => {
    const token = await safeGetString(STORAGE_KEY);
    set({ pendingToken: token, isHydrated: true });
  },

  setPendingToken: async (token: string | null) => {
    const trimmed = token?.trim() || null;
    set({ pendingToken: trimmed });
    await safeSetString(STORAGE_KEY, trimmed);
  },

  clearPendingToken: async () => {
    set({ pendingToken: null });
    await safeSetString(STORAGE_KEY, null);
  },
}));
