import {
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
  isCanonicalInventorySale?: boolean | null;
  inventorySaleDirection?: 'business_to_project' | 'project_to_business' | null;
  itemIds?: string[] | null;
  status?: string | null;
  purchasedBy?: string | null;
  reimbursementType?: string | null;
  notes?: string | null;
  transactionType?: string | null;
  isCanceled?: boolean | null;
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

function normalizeTransactionFromFirestore(raw: unknown, id: string): Transaction {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return { ...(data as object), id } as Transaction;
}

export function createTransaction(
  accountId: string,
  data: Partial<Transaction>
): string {
  if (!isFirebaseConfigured || !db) {
    throw new Error(
      'Firebase is not configured. Add google-services.json / GoogleService-Info.plist and rebuild the dev client.'
    );
  }
  const now = serverTimestamp();
  const docRef = doc(collection(db, `accounts/${accountId}/transactions`));
  setDoc(docRef, {
    ...data,
    createdAt: now,
    updatedAt: now,
  }).catch(err => console.error('[transactions] create failed:', err));
  trackPendingWrite();
  return docRef.id;
}

export function updateTransaction(
  accountId: string,
  transactionId: string,
  data: Partial<Transaction>
): void {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  setDoc(
    doc(db, `accounts/${accountId}/transactions/${transactionId}`),
    {
      ...data,
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  ).catch(err => console.error('[transactions] updateTransaction failed:', err));
  trackPendingWrite();
}

export function deleteTransaction(accountId: string, transactionId: string): void {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  deleteDoc(doc(db, `accounts/${accountId}/transactions/${transactionId}`)).catch(err => console.error('[transactions] deleteTransaction failed:', err));
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
      return normalizeTransactionFromFirestore(snapshot.data(), snapshot.id);
    } catch {
      // try next
    }
  }
  const snapshot = await getDoc(ref);
  if (!snapshot.exists) {
    return null;
  }
  return normalizeTransactionFromFirestore(snapshot.data(), snapshot.id);
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
        onChange(normalizeTransactionFromFirestore(snapshot.data(), snapshot.id));
      },
      (error) => {
        console.warn('[transactionsService] transaction subscription failed', error);
        onChange(null);
      }
    );
}
