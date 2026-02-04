import firestore from '@react-native-firebase/firestore';
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
      return await (query as any).get({ source });
    } catch {
      // try next
    }
  }
  return await (query as any).get();
}

export async function listItemsByProject(
  accountId: string,
  projectId: string | null,
  options: { limit?: number; mode?: 'online' | 'offline' } = {}
): Promise<Item[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const { limit = 200, mode = 'online' } = options;
  let query = db.collection(`accounts/${accountId}/items`).where('projectId', '==', projectId);
  query = query.orderBy('updatedAt', 'desc').limit(limit);
  const snapshot = await getQuerySnapshotWithPreference(query, mode);
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
  await db
    .collection(`accounts/${accountId}/items`)
    .doc(itemId)
    .set(
      {
        ...data,
        updatedAt: firestore.FieldValue.serverTimestamp(),
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
  const now = firestore.FieldValue.serverTimestamp();
  const uid = auth?.currentUser?.uid ?? null;
  const docRef = await db.collection(`accounts/${accountId}/items`).add({
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
  await db.collection(`accounts/${accountId}/items`).doc(itemId).delete();
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
  return db
    .collection(`accounts/${accountId}/items`)
    .doc(itemId)
    .onSnapshot(
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
