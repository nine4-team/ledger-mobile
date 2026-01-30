import { create } from 'zustand';
import { doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import { appConfig } from '../config/appConfig';
import { useAuthStore } from '../auth/authStore';
import { useBillingStore } from '../billing/billingStore';

interface QuotaState {
  counters: Record<string, number>;
  loadCounters: (uid: string) => Promise<void>;
  incrementCounter: (uid: string, objectKey: string) => Promise<void>;
  getCounter: (uid: string, objectKey: string) => Promise<number>;
}

export const useQuotaStore = create<QuotaState>((set, get) => ({
  counters: {},
  loadCounters: async (uid: string) => {
    if (!isFirebaseConfigured || !db) {
      set({ counters: {} });
      return;
    }
    const counters: Record<string, number> = {};
    const quotaKeys = Object.keys(appConfig.quotas);

    await Promise.all(
      quotaKeys.map(async (key) => {
        const quotaRef = doc(db, `users/${uid}/quota/${key}`);
        const snap = await getDoc(quotaRef);
        counters[key] = snap.exists() ? (snap.data()?.count as number) || 0 : 0;
      })
    );

    set({ counters });
  },
  incrementCounter: async (uid: string, objectKey: string) => {
    if (!isFirebaseConfigured || !db) {
      return;
    }
    const quotaRef = doc(db, `users/${uid}/quota/${objectKey}`);
    const current = get().counters[objectKey] || 0;

    await setDoc(
      quotaRef,
      {
        count: current + 1,
        updatedAt: serverTimestamp(),
      },
      { merge: true }
    );

    set((state) => ({
      counters: { ...state.counters, [objectKey]: current + 1 },
    }));
  },
  getCounter: async (uid: string, objectKey: string) => {
    if (!isFirebaseConfigured || !db) {
      return 0;
    }
    const quotaRef = doc(db, `users/${uid}/quota/${objectKey}`);
    const snap = await getDoc(quotaRef);
    return snap.exists() ? (snap.data()?.count as number) || 0 : 0;
  },
}));

/**
 * Check if user can create an object of the given type
 */
export const canCreate = (objectKey: string): boolean => {
  const user = useAuthStore.getState().user;
  const isPro = useBillingStore.getState().isPro;
  if (!user || isPro) {
    return true; // Pro users bypass quotas
  }

  const quota = appConfig.quotas[objectKey];
  if (!quota) {
    return true; // No quota defined = unlimited
  }

  const current = useQuotaStore.getState().counters[objectKey] || 0;
  return current < quota.freeLimit;
};

/**
 * Assert that user can create an object, throw if not
 */
export const assertCanCreate = (objectKey: string): void => {
  if (!canCreate(objectKey)) {
    const quota = appConfig.quotas[objectKey];
    throw new Error(
      `Quota exceeded for ${quota?.displayName || objectKey}. Free limit: ${quota?.freeLimit || 0}`
    );
  }
};

/**
 * Require Pro or quota check - returns true if allowed, false if paywall needed
 */
export const requireProOrQuota = (objectKey: string): boolean => {
  const isPro = useBillingStore.getState().isPro;
  if (isPro) {
    return true;
  }
  return canCreate(objectKey);
};
