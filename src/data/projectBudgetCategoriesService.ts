import {
  collection,
  doc,
  getDoc,
  getDocs,
  getDocsFromCache,
  getDocsFromServer,
  onSnapshot,
  serverTimestamp,
  setDoc,
} from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import { auth } from '../firebase/firebase';

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
  return onSnapshot(
    collectionRef,
      (snapshot) => {
        const next = snapshot.docs.map(
          (doc) => ({ ...(doc.data() as object), id: doc.id } as ProjectBudgetCategory)
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

export async function setProjectBudgetCategory(
  accountId: string,
  projectId: string,
  categoryId: string,
  data: Partial<ProjectBudgetCategory>
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }

  const uid = auth?.currentUser?.uid;
  const ref = doc(db, `accounts/${accountId}/projects/${projectId}/budgetCategories/${categoryId}`);

  // Check if document exists to determine if we need createdAt
  const snapshot = await getDoc(ref);
  const exists = snapshot.exists;

  const now = serverTimestamp();
  const payload: any = {
    ...data,
    updatedAt: now,
  };

  if (uid) {
    payload.updatedBy = uid;
  }

  if (!exists) {
    payload.createdAt = now;
    if (uid) {
      payload.createdBy = uid;
    }
  }

  await setDoc(ref, payload, { merge: true });
}
