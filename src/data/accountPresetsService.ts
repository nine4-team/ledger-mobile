import {
  doc,
  getDoc,
  getDocFromCache,
  getDocFromServer,
  onSnapshot,
  serverTimestamp,
  setDoc,
} from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';

export type AccountPresets = {
  id: string;
  accountId: string;
  defaultBudgetCategoryId?: string | null;
  budgetCategoryOrder?: string[] | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

type Unsubscribe = () => void;

function normalizeAccountPresetsFromFirestore(raw: unknown, id: string): AccountPresets {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const order = Array.isArray(data.budgetCategoryOrder)
    ? data.budgetCategoryOrder
    : (data.budgetCategoryOrder === null ? null : []);
  return { ...(data as object), id, budgetCategoryOrder: order } as AccountPresets;
}

export function subscribeToAccountPresets(
  accountId: string,
  onChange: (presets: AccountPresets | null) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange(null);
    return () => {};
  }
  const ref = doc(db, `accounts/${accountId}/presets/default`);
  return onSnapshot(
    ref,
    (snapshot) => {
      if (!snapshot.exists) {
        onChange(null);
        return;
      }
      onChange(normalizeAccountPresetsFromFirestore(snapshot.data(), snapshot.id));
    },
    (error) => {
      console.warn('[accountPresetsService] subscription failed', error);
      onChange(null);
    }
  );
}

export async function refreshAccountPresets(
  accountId: string,
  mode: 'online' | 'offline' = 'online'
): Promise<AccountPresets | null> {
  if (!isFirebaseConfigured || !db) {
    return null;
  }
  const ref = doc(db, `accounts/${accountId}/presets/default`);
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      const snapshot =
        source === 'cache' ? await getDocFromCache(ref) : await getDocFromServer(ref);
      if (!snapshot.exists) {
        return null;
      }
      return normalizeAccountPresetsFromFirestore(snapshot.data(), snapshot.id);
    } catch {
      // try next
    }
  }
  const snapshot = await getDoc(ref);
  if (!snapshot.exists) {
    return null;
  }
  return normalizeAccountPresetsFromFirestore(snapshot.data(), snapshot.id);
}

export function updateAccountPresets(
  accountId: string,
  data: Partial<Omit<AccountPresets, 'id' | 'accountId' | 'createdAt' | 'updatedAt'>>
): void {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const now = serverTimestamp();
  setDoc(
    doc(db, `accounts/${accountId}/presets/default`),
    {
      ...data,
      updatedAt: now,
    },
    { merge: true }
  ).catch(err => console.error('[accountPresets] updateAccountPresets failed:', err));
  trackPendingWrite();
}
