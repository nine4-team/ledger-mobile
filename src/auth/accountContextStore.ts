import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { auth, db, isFirebaseConfigured } from '../firebase/firebase';

const STORAGE_KEYS = {
  lastSelectedAccountId: 'ledger:lastSelectedAccountId',
  lastValidatedAccountId: 'ledger:lastValidatedAccountId',
  lastValidatedAtMs: 'ledger:lastValidatedAtMs',
} as const;

type AccountContextState = {
  accountId: string | null;
  isHydrated: boolean;
  lastValidatedAtMs: number | null;
  noAccess: boolean;

  hydrate: () => Promise<void>;
  setAccountId: (accountId: string | null) => Promise<void>;
  clearAccountId: () => Promise<void>;
  listAccountsForCurrentUser: () => Promise<Array<{ accountId: string; name?: string }>>;

  /**
   * Revalidate membership for the currently selected account.
   *
   * - If the server definitively says the user is not a member, clears accountId.
   * - If the server is unreachable, keeps current accountId (can't prove invalid).
   */
  revalidateMembership: () => Promise<void>;
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
    // ignore storage failures; app can proceed without persisted account selection
  }
}

async function safeSetNumber(key: string, value: number | null): Promise<void> {
  await safeSetString(key, value == null ? null : String(value));
}

async function safeGetNumber(key: string): Promise<number | null> {
  const raw = await safeGetString(key);
  if (raw == null) return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
}

async function getDocWithPreference(ref: any) {
  // Mirror the repo approach: try server then cache.
  for (const source of ['server', 'cache'] as const) {
    try {
      return await ref.get({ source });
    } catch {
      // try next source
    }
  }
  return await ref.get();
}

async function getDocsWithPreference(query: any) {
  // Mirror the repo approach: try server then cache.
  for (const source of ['server', 'cache'] as const) {
    try {
      return await query.get({ source });
    } catch {
      // try next source
    }
  }
  return await query.get();
}

export const useAccountContextStore = create<AccountContextState>((set, get) => ({
  accountId: null,
  isHydrated: false,
  lastValidatedAtMs: null,
  noAccess: false,

  hydrate: async () => {
    const [lastSelected, lastValidated, lastValidatedAtMs] = await Promise.all([
      safeGetString(STORAGE_KEYS.lastSelectedAccountId),
      safeGetString(STORAGE_KEYS.lastValidatedAccountId),
      safeGetNumber(STORAGE_KEYS.lastValidatedAtMs),
    ]);

    // Prefer the last validated account id if available; otherwise fall back to last selected.
    const accountId = (lastValidated || lastSelected || null) as string | null;
    set({ accountId, isHydrated: true, lastValidatedAtMs, noAccess: false });
  },

  setAccountId: async (accountId) => {
    const next = accountId?.trim() ? accountId.trim() : null;
    set({ accountId: next, noAccess: false });
    await safeSetString(STORAGE_KEYS.lastSelectedAccountId, next);
  },

  clearAccountId: async () => {
    set({ accountId: null, lastValidatedAtMs: null, noAccess: false });
    await Promise.all([
      safeSetString(STORAGE_KEYS.lastSelectedAccountId, null),
      safeSetString(STORAGE_KEYS.lastValidatedAccountId, null),
      safeSetNumber(STORAGE_KEYS.lastValidatedAtMs, null),
    ]);
  },

  listAccountsForCurrentUser: async () => {
    const uid = auth?.currentUser?.uid;

    // If Firebase isn't configured (or user isn't signed in), safely report "no accounts".
    if (!uid || !isFirebaseConfigured || !db) {
      return [];
    }

    try {
      // Membership docs live at: accounts/{accountId}/users/{uid}
      // IMPORTANT (RN Firebase native): for collectionGroup queries, filtering by documentId requires a full
      // document path, not just an id, so we use a real `uid` field on membership docs.
      const membershipQuery = db.collectionGroup('users').where('uid', '==', uid);

      const membershipSnap = await getDocsWithPreference(membershipQuery);
      const accountIds = Array.from(
        new Set(
          membershipSnap.docs
            .map((doc: any) => doc?.ref?.parent?.parent?.id as string | undefined)
            .filter(Boolean)
        )
      ) as string[];

      const lastSelected = await safeGetString(STORAGE_KEYS.lastSelectedAccountId);

      // Back-compat safety: if the membership docs don't have `uid` yet, fall back to the last-selected
      // account (if its membership doc exists). This preserves offline boot for existing sessions.
      if (accountIds.length === 0 && lastSelected) {
        try {
          const membershipRef = db.doc(`accounts/${lastSelected}/users/${uid}`);
          const membershipSnap = await getDocWithPreference(membershipRef);
          if (membershipSnap?.exists) {
            accountIds.push(lastSelected);
          }
        } catch {
          // ignore
        }
      }

      const accounts = await Promise.all(
        accountIds.map(async (accountId) => {
          try {
            const accountSnap = await getDocWithPreference(db.doc(`accounts/${accountId}`));
            const data = typeof accountSnap?.data === 'function' ? accountSnap.data() : undefined;
            return { accountId, name: data?.name as string | undefined };
          } catch {
            return { accountId };
          }
        })
      );

      if (lastSelected) {
        accounts.sort((a, b) => (a.accountId === lastSelected ? -1 : b.accountId === lastSelected ? 1 : 0));
      }

      console.log('[accountContext] listAccountsForCurrentUser', { count: accounts.length });
      return accounts;
    } catch (error) {
      console.warn('[accountContext] listAccountsForCurrentUser failed');
      return [];
    }
  },

  revalidateMembership: async () => {
    const accountId = get().accountId;
    const uid = auth?.currentUser?.uid;

    if (!accountId || !uid) {
      return;
    }

    // If Firebase isn't configured, we can't validate; keep the selection.
    if (!isFirebaseConfigured || !db) {
      return;
    }

    try {
      const ref = db.doc(`accounts/${accountId}/users/${uid}`);
      const snapshot = await getDocWithPreference(ref);

      // Only clear if we can definitively say "does not exist".
      if (!snapshot.exists) {
        set({ accountId: null, lastValidatedAtMs: null, noAccess: true });
        await Promise.all([
          safeSetString(STORAGE_KEYS.lastSelectedAccountId, null),
          safeSetString(STORAGE_KEYS.lastValidatedAccountId, null),
          safeSetNumber(STORAGE_KEYS.lastValidatedAtMs, null),
        ]);
        return;
      }

      const now = Date.now();
      set({ lastValidatedAtMs: now, noAccess: false });
      await Promise.all([
        safeSetString(STORAGE_KEYS.lastValidatedAccountId, accountId),
        safeSetNumber(STORAGE_KEYS.lastValidatedAtMs, now),
      ]);
    } catch {
      // Server/cache failures shouldn't blow up startup; keep current accountId.
    }
  },
}));

