import {
  collection,
  getDocs,
  getDocsFromCache,
  getDocsFromServer,
  onSnapshot,
  query,
  where,
} from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import type { Transaction } from './transactionsService';

export type BudgetProgress = {
  spentCents: number;
  spentByCategory: Record<string, number>;
};

type Unsubscribe = () => void;

async function getQuerySnapshotWithPreference(queryRef: unknown, mode: 'online' | 'offline') {
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      return source === 'cache' ? await getDocsFromCache(queryRef as any) : await getDocsFromServer(queryRef as any);
    } catch {
      // try next source
    }
  }
  return await getDocs(queryRef as any);
}

function normalizeSpendAmount(tx: Transaction): number {
  if (tx.status === 'canceled') return 0;
  if (typeof tx.amountCents !== 'number') return 0;
  const amount = tx.amountCents;
  const type = tx.type?.trim().toLowerCase();
  if (type === 'return') {
    return -Math.abs(amount);
  }
  return amount;
}

function buildBudgetProgress(transactions: Transaction[]): BudgetProgress {
  const spentByCategory: Record<string, number> = {};
  let spentCents = 0;
  transactions.forEach((tx) => {
    const categoryId = tx.budgetCategoryId?.trim();
    if (!categoryId) return;
    const amount = normalizeSpendAmount(tx);
    if (!amount) return;
    spentCents += amount;
    spentByCategory[categoryId] = (spentByCategory[categoryId] ?? 0) + amount;
  });
  return { spentCents, spentByCategory };
}

export function subscribeToProjectBudgetProgress(
  accountId: string,
  projectId: string,
  onChange: (progress: BudgetProgress) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange({ spentCents: 0, spentByCategory: {} });
    return () => {};
  }
  const collectionRef = collection(db, `accounts/${accountId}/transactions`);
  const projectQuery = query(collectionRef, where('projectId', '==', projectId));
  return onSnapshot(
    projectQuery,
    (snapshot) => {
      const transactions = snapshot.docs.map(
        (doc) => ({ ...(doc.data() as object), id: doc.id } as Transaction)
      );
      onChange(buildBudgetProgress(transactions));
    },
    (error) => {
      console.warn('[budgetProgressService] project subscription failed', error);
      onChange({ spentCents: 0, spentByCategory: {} });
    }
  );
}

export async function refreshProjectBudgetProgress(
  accountId: string,
  projectId: string,
  mode: 'online' | 'offline' = 'online'
): Promise<BudgetProgress> {
  if (!isFirebaseConfigured || !db) {
    return { spentCents: 0, spentByCategory: {} };
  }
  const collectionRef = collection(db, `accounts/${accountId}/transactions`);
  const projectQuery = query(collectionRef, where('projectId', '==', projectId));
  const snapshot = await getQuerySnapshotWithPreference(projectQuery, mode);
  const transactions = snapshot.docs.map(
    (doc: any) => ({ ...(doc.data() as object), id: doc.id } as Transaction)
  );
  return buildBudgetProgress(transactions);
}
