import {
  collection,
  deleteDoc,
  doc,
  getDocs,
  getDocsFromCache,
  getDocsFromServer,
  onSnapshot,
  serverTimestamp,
  setDoc,
} from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';

export type BudgetCategoryType = 'general' | 'itemized' | 'fee';


export type BudgetCategory = {
  id: string;
  accountId?: string | null;
  projectId?: string | null;
  name: string;
  slug?: string | null;
  isArchived?: boolean | null;
  order?: number | null;
  metadata?: {
    categoryType?: BudgetCategoryType;
    excludeFromOverallBudget?: boolean;
    legacy?: Record<string, unknown> | null;
  } | null;
  createdAt?: unknown;
  updatedAt?: unknown;
  createdBy?: string | null;
  updatedBy?: string | null;
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
    const legacyId =
      category.metadata && category.metadata.legacy && typeof category.metadata.legacy === 'object'
        ? (category.metadata.legacy as any).sourceCategoryId
        : null;
    if (typeof legacyId === 'string' && legacyId.trim().length > 0) {
      // Allow lookups by legacy UUID (migrated-from server exports).
      // If collisions ever happen, we keep the first value.
      if (!acc[legacyId]) {
        acc[legacyId] = category;
      }
    }
    return acc;
  }, {} as Record<string, BudgetCategory>);
}

export function createBudgetCategory(
  accountId: string,
  name: string,
  options?: {
    metadata?: BudgetCategory['metadata'];
  }
): string {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const firestore = db;
  const trimmed = name.trim();
  if (!trimmed) {
    throw new Error('Category name is required.');
  }
  const now = serverTimestamp();
  const hasMetadataOption = Object.prototype.hasOwnProperty.call(options ?? {}, 'metadata');
  const docRef = doc(collection(firestore, `accounts/${accountId}/presets/default/budgetCategories`));
  setDoc(docRef, {
    accountId,
    projectId: null,
    name: trimmed,
    slug: trimmed.toLowerCase().replace(/\s+/g, '-'),
    isArchived: false,
    order: Date.now(),
    ...(hasMetadataOption ? { metadata: options?.metadata ?? null } : {}),
    createdAt: now,
    updatedAt: now,
  }).catch(err => console.error('[budgetCategories] create failed:', err));
  trackPendingWrite();
  return docRef.id;
}

export async function updateBudgetCategory(
  accountId: string,
  categoryId: string,
  data: Partial<BudgetCategory>
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const firestore = db;
  const now = serverTimestamp();
  const hasMetadata = Object.prototype.hasOwnProperty.call(data, 'metadata');
  await setDoc(
    doc(firestore, `accounts/${accountId}/presets/default/budgetCategories/${categoryId}`),
    {
      ...data,
      ...(hasMetadata ? { metadata: data.metadata ?? null } : {}),
      updatedAt: now,
    },
    { merge: true }
  );
  trackPendingWrite();
}

export async function setBudgetCategoryArchived(
  accountId: string,
  categoryId: string,
  isArchived: boolean
): Promise<void> {
  await updateBudgetCategory(accountId, categoryId, { isArchived });
}

export async function deleteBudgetCategory(accountId: string, categoryId: string): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  await deleteDoc(doc(db, `accounts/${accountId}/presets/default/budgetCategories/${categoryId}`));
  trackPendingWrite();
}

export async function setBudgetCategoryOrder(
  accountId: string,
  orderedIds: string[]
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const firestore = db;
  const now = serverTimestamp();
  await Promise.all(
    orderedIds.map((id, index) =>
      setDoc(
        doc(firestore, `accounts/${accountId}/presets/default/budgetCategories/${id}`),
        {
          order: index,
          updatedAt: now,
        },
        { merge: true }
      )
    )
  );
  trackPendingWrite();
}
