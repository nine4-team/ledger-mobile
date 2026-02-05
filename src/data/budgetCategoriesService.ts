import {
  addDoc,
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

export type BudgetCategory = {
  id: string;
  name: string;
  slug?: string | null;
  isArchived?: boolean | null;
  order?: number | null;
  metadata?: {
    categoryType?: 'standard' | 'itemized' | 'fee';
    excludeFromOverallBudget?: boolean;
    legacy?: Record<string, unknown> | null;
  } | null;
};

type Unsubscribe = () => void;

export function subscribeToBudgetCategories(
  accountId: string,
  onChange: (categories: BudgetCategory[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }
  const collectionRef = collection(db, `accounts/${accountId}/presets/default/budgetCategories`);
  return onSnapshot(
    collectionRef,
      (snapshot) => {
        const next = snapshot.docs.map(
          (doc) => ({ ...(doc.data() as object), id: doc.id } as BudgetCategory)
        );
        onChange(next);
      },
      (error) => {
        console.warn('[budgetCategoriesService] subscription failed', error);
        onChange([]);
      }
    );
}

export async function refreshBudgetCategories(
  accountId: string,
  mode: 'online' | 'offline' = 'online'
): Promise<BudgetCategory[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const ref = collection(db, `accounts/${accountId}/presets/default/budgetCategories`);
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      const snapshot =
        source === 'cache' ? await getDocsFromCache(ref) : await getDocsFromServer(ref);
      return snapshot.docs.map(
        (doc: any) => ({ ...(doc.data() as object), id: doc.id } as BudgetCategory)
      );
    } catch {
      // try next
    }
  }
  const snapshot = await getDocs(ref);
  return snapshot.docs.map(
    (doc: any) => ({ ...(doc.data() as object), id: doc.id } as BudgetCategory)
  );
}

export function mapBudgetCategories(categories: BudgetCategory[]): Record<string, BudgetCategory> {
  return categories.reduce((acc, category) => {
    acc[category.id] = category;
    return acc;
  }, {} as Record<string, BudgetCategory>);
}

export async function createBudgetCategory(accountId: string, name: string): Promise<string> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const trimmed = name.trim();
  if (!trimmed) {
    throw new Error('Category name is required.');
  }
  const now = serverTimestamp();
  const ref = await addDoc(collection(db, `accounts/${accountId}/presets/default/budgetCategories`), {
    accountId,
    projectId: null,
    name: trimmed,
    slug: trimmed.toLowerCase().replace(/\s+/g, '-'),
    isArchived: false,
    order: Date.now(),
    createdAt: now,
    updatedAt: now,
  });
  return ref.id;
}

export async function updateBudgetCategory(
  accountId: string,
  categoryId: string,
  data: Partial<BudgetCategory>
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const now = serverTimestamp();
  await setDoc(
    doc(db, `accounts/${accountId}/presets/default/budgetCategories/${categoryId}`),
    {
      ...data,
      updatedAt: now,
    },
    { merge: true }
  );
}

export async function setBudgetCategoryArchived(
  accountId: string,
  categoryId: string,
  isArchived: boolean
): Promise<void> {
  await updateBudgetCategory(accountId, categoryId, { isArchived });
}

export async function setBudgetCategoryOrder(
  accountId: string,
  orderedIds: string[]
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const now = serverTimestamp();
  await Promise.all(
    orderedIds.map((id, index) =>
      setDoc(
        doc(db, `accounts/${accountId}/presets/default/budgetCategories/${id}`),
        {
          order: index,
          updatedAt: now,
        },
        { merge: true }
      )
    )
  );
}
