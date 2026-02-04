import firestore from '@react-native-firebase/firestore';
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
  const now = firestore.FieldValue.serverTimestamp();
  const docRef = await db.collection(`accounts/${accountId}/transactions`).add({
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
  await db
    .collection(`accounts/${accountId}/transactions`)
    .doc(transactionId)
    .set(
      {
        ...data,
        updatedAt: firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  trackPendingWrite();
}

export async function deleteTransaction(accountId: string, transactionId: string): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  await db.collection(`accounts/${accountId}/transactions`).doc(transactionId).delete();
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
  const ref = db.collection(`accounts/${accountId}/transactions`).doc(transactionId);
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      const snapshot = await (ref as any).get({ source });
      if (!snapshot.exists) {
        return null;
      }
      return { ...(snapshot.data() as object), id: snapshot.id } as Transaction;
    } catch {
      // try next
    }
  }
  const snapshot = await ref.get();
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
  return db
    .collection(`accounts/${accountId}/transactions`)
    .doc(transactionId)
    .onSnapshot(
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
