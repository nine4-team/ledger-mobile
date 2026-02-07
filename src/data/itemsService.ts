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
  /**
   * Canonical item label. May be an empty string for legacy/parity.
   */
  name: string;
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
  budgetCategoryId?: string | null;
};

export type ItemWrite = Omit<Partial<Item>, 'name'> & {
  /**
   * Allow legacy callers to pass null; we coerce it to "" when writing.
   */
  name?: string | null;
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

function normalizeItemFromFirestore(raw: unknown, id: string): Item {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  // Legacy: older docs used `description` as the primary label.
  // Canonical: the app should only use `name`.
  const legacyDescription = typeof data.description === 'string' ? data.description : null;
  const rawName = typeof data.name === 'string' ? data.name : null;
  const name = (rawName && rawName.trim().length > 0 ? rawName : legacyDescription) ?? '';

  // Drop `description` from the returned object so the rest of the app
  // can’t accidentally depend on it.
  const rest: Record<string, unknown> = { ...data };
  delete (rest as any).description;

  return { ...(rest as object), id, name } as Item;
}

function normalizeItemWrite(data: ItemWrite): Record<string, unknown> {
  const out: Record<string, unknown> = { ...(data as Record<string, unknown>) };
  if ('name' in out) {
    const raw = out.name;
    out.name = typeof raw === 'string' ? raw : '';
  }
  // Never persist legacy `description`.
  if ('description' in out) {
    delete out.description;
  }
  return out;
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
  return snapshot.docs.map((doc: any) => normalizeItemFromFirestore(doc.data(), doc.id));
}

export async function updateItem(
  accountId: string,
  itemId: string,
  data: ItemWrite
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  const uid = auth?.currentUser?.uid ?? null;
  await setDoc(
    doc(db, `accounts/${accountId}/items/${itemId}`),
    {
      ...normalizeItemWrite(data),
      updatedAt: serverTimestamp(),
      updatedBy: uid,
    },
    { merge: true }
  );
  trackPendingWrite();
}

export async function createItem(
  accountId: string,
  data: ItemWrite
): Promise<string> {
  if (!isFirebaseConfigured || !db) {
    throw new Error(
      'Firebase is not configured. Add google-services.json / GoogleService-Info.plist and rebuild the dev client.'
    );
  }
  const now = serverTimestamp();
  const uid = auth?.currentUser?.uid ?? null;
  const docRef = await addDoc(collection(db, `accounts/${accountId}/items`), {
    ...normalizeItemWrite(data),
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
        onChange(normalizeItemFromFirestore(snapshot.data(), snapshot.id));
      },
      (error) => {
        console.warn('[itemsService] item subscription failed', error);
        onChange(null);
      }
    );
}
