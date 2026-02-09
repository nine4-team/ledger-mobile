import {
  collection,
  doc,
  getDocs,
  getDocsFromCache,
  getDocsFromServer,
  onSnapshot,
  serverTimestamp,
  setDoc,
} from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import { auth } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';

export type ProjectBudgetCategory = {
  id: string;
  budgetCents: number | null;
  createdAt?: unknown;
  updatedAt?: unknown;
  createdBy?: string;
  updatedBy?: string;
};

type Unsubscribe = () => void;

export function subscribeToProjectBudgetCategories(
  accountId: string,
  projectId: string,
  onChange: (categories: ProjectBudgetCategory[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }
  const collectionRef = collection(db, `accounts/${accountId}/projects/${projectId}/budgetCategories`);

  // Cache-first: getDocsFromCache gives an instant response so the UI doesn't
  // hang waiting for the server. onSnapshot in React Native Firebase waits for
  // a server round-trip on its first callback, causing a 5-7s delay without this.
  getDocsFromCache(collectionRef)
    .then(snapshot => {
      const next = snapshot.docs.map(
        (d) => ({ ...(d.data() as object), id: d.id } as ProjectBudgetCategory)
      );
      onChange(next);
    })
    .catch(() => {
      // Cache miss — onChange with empty so loading state can clear
      onChange([]);
    });

  // Real-time listener for subsequent updates
  return onSnapshot(
    collectionRef,
    (snapshot) => {
      const next = snapshot.docs.map(
        (d) => ({ ...(d.data() as object), id: d.id } as ProjectBudgetCategory)
      );
      onChange(next);
    },
    (error) => {
      console.warn('[projectBudgetCategoriesService] subscription failed', error);
      onChange([]);
    }
  );
}

export async function refreshProjectBudgetCategories(
  accountId: string,
  projectId: string,
  mode: 'online' | 'offline' = 'online'
): Promise<ProjectBudgetCategory[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const ref = collection(db, `accounts/${accountId}/projects/${projectId}/budgetCategories`);
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      const snapshot =
        source === 'cache' ? await getDocsFromCache(ref) : await getDocsFromServer(ref);
      return snapshot.docs.map(
        (doc: any) => ({ ...(doc.data() as object), id: doc.id } as ProjectBudgetCategory)
      );
    } catch {
      // try next
    }
  }
  const snapshot = await getDocs(ref);
  return snapshot.docs.map(
    (doc: any) => ({ ...(doc.data() as object), id: doc.id } as ProjectBudgetCategory)
  );
}

/**
 * Set a project budget category. Fire-and-forget: does not await the
 * Firestore write so the UI never blocks on network.  Uses `merge: true`
 * so both create and update work without an existence check.
 */
export function setProjectBudgetCategory(
  accountId: string,
  projectId: string,
  categoryId: string,
  data: Partial<ProjectBudgetCategory>
): void {
  if (!isFirebaseConfigured || !db) {
    return;
  }

  const uid = auth?.currentUser?.uid;
  const ref = doc(db, `accounts/${accountId}/projects/${projectId}/budgetCategories/${categoryId}`);

  const now = serverTimestamp();
  const payload: any = {
    ...data,
    updatedAt: now,
  };

  if (uid) {
    payload.updatedBy = uid;
  }

  // Fire-and-forget write — merge:true preserves existing fields on updates
  // Note: createdAt/createdBy are NOT included here; they should be set only
  // on first document creation (if needed), not on every update
  setDoc(ref, payload, { merge: true }).catch(err =>
    console.error('[projectBudgetCategories] set failed:', err)
  );
  trackPendingWrite();
}
