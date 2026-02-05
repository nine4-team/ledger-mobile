import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDocs,
  getDocsFromCache,
  getDocsFromServer,
  limit,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  where,
} from '@react-native-firebase/firestore';
import { auth, db, isFirebaseConfigured } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';
import type { AttachmentRef } from '../offline/media';

export type Item = {
  id: string;
  accountId?: string;
  projectId?: string | null;
  spaceId?: string | null;
  name?: string | null;
  description?: string | null;
  notes?: string | null;
  status?: string | null;
  source?: string | null;
  sku?: string | null;
  transactionId?: string | null;
  purchasePriceCents?: number | null;
  projectPriceCents?: number | null;
  marketValueCents?: number | null;
  purchasedBy?: string | null;
  bookmark?: boolean | null;
  images?: AttachmentRef[] | null;
  inheritedBudgetCategoryId?: string | null;
};

async function getQuerySnapshotWithPreference(
  query: unknown,
  mode: 'online' | 'offline'
): Promise<any> {
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      return source === 'cache' ? await getDocsFromCache(query as any) : await getDocsFromServer(query as any);
    } catch {
      // try next
    }
  }
  return await getDocs(query as any);
}

export async function listItemsByProject(
  accountId: string,
  projectId: string | null,
  options: { limit?: number; mode?: 'online' | 'offline' } = {}
): Promise<Item[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const { limit: limitCount = 200, mode = 'online' } = options;
  const baseQuery = query(
    collection(db, `accounts/${accountId}/items`),
    where('projectId', '==', projectId),
    orderBy('updatedAt', 'desc'),
    limit(limitCount)
  );
  const snapshot = await getQuerySnapshotWithPreference(baseQuery, mode);
  return snapshot.docs.map((doc: any) => ({ ...(doc.data() as object), id: doc.id } as Item));
}

export async function updateItem(
  accountId: string,
  itemId: string,
  data: Partial<Item>
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  const uid = auth?.currentUser?.uid ?? null;
  await setDoc(
    doc(db, `accounts/${accountId}/items/${itemId}`),
    {
      ...data,
      updatedAt: serverTimestamp(),
      updatedBy: uid,
    },
    { merge: true }
  );
  trackPendingWrite();
}

export async function createItem(
  accountId: string,
  data: Partial<Item>
): Promise<string> {
  if (!isFirebaseConfigured || !db) {
    throw new Error(
      'Firebase is not configured. Add google-services.json / GoogleService-Info.plist and rebuild the dev client.'
    );
  }
  const now = serverTimestamp();
  const uid = auth?.currentUser?.uid ?? null;
  const docRef = await addDoc(collection(db, `accounts/${accountId}/items`), {
    ...data,
    createdAt: now,
    updatedAt: now,
    createdBy: uid,
    updatedBy: uid,
  });
  trackPendingWrite();
  return docRef.id;
}

export async function deleteItem(accountId: string, itemId: string): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  await deleteDoc(doc(db, `accounts/${accountId}/items/${itemId}`));
  trackPendingWrite();
}

export function subscribeToItem(
  accountId: string,
  itemId: string,
  onChange: (item: Item | null) => void
): () => void {
  if (!isFirebaseConfigured || !db) {
    onChange(null);
    return () => {};
  }
  const ref = doc(db, `accounts/${accountId}/items/${itemId}`);
  return onSnapshot(
    ref,
      (snapshot) => {
        if (!snapshot.exists) {
          onChange(null);
          return;
        }
        onChange({ ...(snapshot.data() as object), id: snapshot.id } as Item);
      },
      (error) => {
        console.warn('[itemsService] item subscription failed', error);
        onChange(null);
      }
    );
}
