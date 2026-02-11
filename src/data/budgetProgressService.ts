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
import type { BudgetCategory } from './budgetCategoriesService';
import { refreshBudgetCategories, mapBudgetCategories } from './budgetCategoriesService';

export type BudgetProgress = {
  spentCents: number;
  spentByCategory: Record<string, number>;
};

type Unsubscribe = () => void;

function normalizeTransactionFromFirestore(raw: unknown, id: string): Transaction {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return { ...(data as object), id } as Transaction;
}

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
  // Exclude canceled transactions
  if (tx.isCanceled === true) return 0;

  if (typeof tx.amountCents !== 'number') return 0;
  const amount = tx.amountCents;
  const txType = tx.transactionType?.trim().toLowerCase();

  // Handle returns (negative amount)
  if (txType === 'return') {
    return -Math.abs(amount);
  }

  // Handle canonical inventory sales with direction-based multiplier
  if (tx.isCanonicalInventorySale && tx.inventorySaleDirection) {
    // project_to_business: subtract from spent (money back)
    // business_to_project: add to spent (money out)
    return tx.inventorySaleDirection === 'project_to_business'
      ? -Math.abs(amount)
      : Math.abs(amount);
  }

  // Default: purchases add to spent
  return amount;
}

function buildBudgetProgress(
  transactions: Transaction[],
  budgetCategories: Record<string, BudgetCategory>
): BudgetProgress {
  const spentByCategory: Record<string, number> = {};
  let overallSpentCents = 0;

  transactions.forEach((tx) => {
    const categoryId = tx.budgetCategoryId?.trim();
    if (!categoryId) return;

    const amount = normalizeSpendAmount(tx);
    if (amount === 0) return; // Skip canceled

    // Track per-category spending (always include)
    spentByCategory[categoryId] = (spentByCategory[categoryId] ?? 0) + amount;

    // Track overall spending (exclude if category has excludeFromOverallBudget)
    const category = budgetCategories[categoryId];
    const shouldExclude = category?.metadata?.excludeFromOverallBudget === true;
    if (!shouldExclude) {
      overallSpentCents += amount;
    }
  });

  return { spentCents: overallSpentCents, spentByCategory };
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

  // Fetch budget categories once for the subscription
  let budgetCategoriesMap: Record<string, BudgetCategory> = {};
  refreshBudgetCategories(accountId, 'offline').then((categories) => {
    budgetCategoriesMap = mapBudgetCategories(categories);
  });

  const collectionRef = collection(db, `accounts/${accountId}/transactions`);
  const projectQuery = query(collectionRef, where('projectId', '==', projectId));
  return onSnapshot(
    projectQuery,
    (snapshot) => {
      const transactions = snapshot.docs.map(
        (doc) => normalizeTransactionFromFirestore(doc.data(), doc.id)
      );
      onChange(buildBudgetProgress(transactions, budgetCategoriesMap));
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

  // Fetch budget categories
  const budgetCategories = await refreshBudgetCategories(accountId, mode);
  const budgetCategoriesMap = mapBudgetCategories(budgetCategories);

  const collectionRef = collection(db, `accounts/${accountId}/transactions`);
  const projectQuery = query(collectionRef, where('projectId', '==', projectId));
  const snapshot = await getQuerySnapshotWithPreference(projectQuery, mode);
  const transactions = snapshot.docs.map(
    (doc: any) => normalizeTransactionFromFirestore(doc.data(), doc.id)
  );
  return buildBudgetProgress(transactions, budgetCategoriesMap);
}
