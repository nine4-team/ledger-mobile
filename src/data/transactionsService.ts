import {
  addDoc,
  collection,
  deleteDoc,
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
import type { AttachmentRef } from '../offline/media';

export type Transaction = {
  id: string;
  projectId?: string | null;
  transactionDate?: string | null;
  amountCents?: number | null;
  source?: string | null;
  isCanonicalInventory?: boolean | null;
  canonicalKind?: string | null;
  itemIds?: string[] | null;
  status?: string | null;
  purchasedBy?: string | null;
  reimbursementType?: string | null;
  notes?: string | null;
  type?: string | null;
  budgetCategoryId?: string | null;
  hasEmailReceipt?: boolean | null;
  receiptImages?: AttachmentRef[] | null;
  otherImages?: AttachmentRef[] | null;
  transactionImages?: AttachmentRef[] | null;
  needsReview?: boolean | null;
  taxRatePct?: number | null;
  subtotalCents?: number | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

export async function createTransaction(
  accountId: string,
  data: Partial<Transaction>
): Promise<string> {
  if (!isFirebaseConfigured || !db) {
    throw new Error(
      'Firebase is not configured. Add google-services.json / GoogleService-Info.plist and rebuild the dev client.'
    );
  }
  const now = serverTimestamp();
  const docRef = await addDoc(collection(db, `accounts/${accountId}/transactions`), {
    ...data,
    createdAt: now,
    updatedAt: now,
  });
  trackPendingWrite();
  return docRef.id;
}

export async function updateTransaction(
  accountId: string,
  transactionId: string,
  data: Partial<Transaction>
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  await setDoc(
    doc(db, `accounts/${accountId}/transactions/${transactionId}`),
    {
      ...data,
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  );
  trackPendingWrite();
}

export async function deleteTransaction(accountId: string, transactionId: string): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  await deleteDoc(doc(db, `accounts/${accountId}/transactions/${transactionId}`));
  trackPendingWrite();
}

export async function getTransaction(
  accountId: string,
  transactionId: string,
  mode: 'online' | 'offline' = 'offline'
): Promise<Transaction | null> {
  if (!isFirebaseConfigured || !db) {
    return null;
  }
  const ref = doc(db, `accounts/${accountId}/transactions/${transactionId}`);
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      const snapshot =
        source === 'cache' ? await getDocFromCache(ref) : await getDocFromServer(ref);
      if (!snapshot.exists) {
        return null;
      }
      return { ...(snapshot.data() as object), id: snapshot.id } as Transaction;
    } catch {
      // try next
    }
  }
  const snapshot = await getDoc(ref);
  if (!snapshot.exists) {
    return null;
  }
  return { ...(snapshot.data() as object), id: snapshot.id } as Transaction;
}

export function subscribeToTransaction(
  accountId: string,
  transactionId: string,
  onChange: (transaction: Transaction | null) => void
): () => void {
  if (!isFirebaseConfigured || !db) {
    onChange(null);
    return () => {};
  }
  const ref = doc(db, `accounts/${accountId}/transactions/${transactionId}`);
  return onSnapshot(
    ref,
      (snapshot) => {
        if (!snapshot.exists) {
          onChange(null);
          return;
        }
        onChange({ ...(snapshot.data() as object), id: snapshot.id } as Transaction);
      },
      (error) => {
        console.warn('[transactionsService] transaction subscription failed', error);
        onChange(null);
      }
    );
}
