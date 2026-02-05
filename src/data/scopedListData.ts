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
import type { AttachmentRef } from '../offline/media';
import { ScopeConfig } from './scopeConfig';

export type ScopedItem = {
  id: string;
  name?: string | null;
  description?: string | null;
  notes?: string | null;
  sku?: string | null;
  projectId?: string | null;
  spaceId?: string | null;
  status?: string | null;
  source?: string | null;
  transactionId?: string | null;
  purchasePriceCents?: number | null;
  projectPriceCents?: number | null;
  marketValueCents?: number | null;
  purchasedBy?: string | null;
  bookmark?: boolean | null;
  images?: AttachmentRef[] | null;
  inheritedBudgetCategoryId?: string | null;
  createdAt?: unknown;
};

export type ScopedTransaction = {
  id: string;
  transactionDate?: string | null;
  amountCents?: number | null;
  source?: string | null;
  projectId?: string | null;
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
};

export type ProjectSummary = {
  id: string;
  name?: string | null;
  isArchived?: boolean | null;
};

type Unsubscribe = () => void;

function toSafeArray<T>(items: T[] | null | undefined): T[] {
  if (!items) return [];
  return Array.isArray(items) ? items : [];
}

function getScopeProjectId(scopeConfig: ScopeConfig): string | null {
  if (scopeConfig.scope !== 'project') {
    return null;
  }
  return scopeConfig.projectId ?? null;
}

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

function getScopedItemsQuery(accountId: string, scopeConfig: ScopeConfig) {
  const projectId = getScopeProjectId(scopeConfig);
  const collectionRef = collection(db, `accounts/${accountId}/items`);
  return scopeConfig.scope === 'inventory'
    ? query(collectionRef, where('projectId', '==', null))
    : query(collectionRef, where('projectId', '==', projectId));
}

function getScopedTransactionsQuery(accountId: string, scopeConfig: ScopeConfig) {
  const projectId = getScopeProjectId(scopeConfig);
  const collectionRef = collection(db, `accounts/${accountId}/transactions`);
  return scopeConfig.scope === 'inventory'
    ? query(collectionRef, where('projectId', '==', null))
    : query(collectionRef, where('projectId', '==', projectId));
}

export function subscribeToScopedItems(
  accountId: string,
  scopeConfig: ScopeConfig,
  onChange: (items: ScopedItem[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }

  const projectId = getScopeProjectId(scopeConfig);
  if (scopeConfig.scope === 'project' && !projectId) {
    onChange([]);
    return () => {};
  }

  const query = getScopedItemsQuery(accountId, scopeConfig);

  return onSnapshot(
    query,
    (snapshot) => {
      const next = snapshot.docs.map((doc) => ({ ...(doc.data() as object), id: doc.id } as ScopedItem));
      onChange(toSafeArray(next));
    },
    (error) => {
      console.warn('[scopedListData] items subscription failed', error);
      onChange([]);
    }
  );
}

export function subscribeToScopedTransactions(
  accountId: string,
  scopeConfig: ScopeConfig,
  onChange: (items: ScopedTransaction[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }

  const projectId = getScopeProjectId(scopeConfig);
  if (scopeConfig.scope === 'project' && !projectId) {
    onChange([]);
    return () => {};
  }

  const query = getScopedTransactionsQuery(accountId, scopeConfig);

  return onSnapshot(
    query,
    (snapshot) => {
      const next = snapshot.docs.map((doc) => ({ ...(doc.data() as object), id: doc.id } as ScopedTransaction));
      onChange(toSafeArray(next));
    },
    (error) => {
      console.warn('[scopedListData] transactions subscription failed', error);
      onChange([]);
    }
  );
}

export async function refreshScopedItems(
  accountId: string,
  scopeConfig: ScopeConfig,
  mode: 'online' | 'offline' = 'online'
): Promise<ScopedItem[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const projectId = getScopeProjectId(scopeConfig);
  if (scopeConfig.scope === 'project' && !projectId) {
    return [];
  }
  const query = getScopedItemsQuery(accountId, scopeConfig);
  const snapshot = await getQuerySnapshotWithPreference(query, mode);
  return snapshot.docs.map((doc: any) => ({ ...(doc.data() as object), id: doc.id } as ScopedItem));
}

export async function refreshScopedTransactions(
  accountId: string,
  scopeConfig: ScopeConfig,
  mode: 'online' | 'offline' = 'online'
): Promise<ScopedTransaction[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const projectId = getScopeProjectId(scopeConfig);
  if (scopeConfig.scope === 'project' && !projectId) {
    return [];
  }
  const query = getScopedTransactionsQuery(accountId, scopeConfig);
  const snapshot = await getQuerySnapshotWithPreference(query, mode);
  return snapshot.docs.map((doc: any) => ({ ...(doc.data() as object), id: doc.id } as ScopedTransaction));
}

export function subscribeToProjects(
  accountId: string,
  onChange: (items: ProjectSummary[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }

  const collectionRef = collection(db, `accounts/${accountId}/projects`);
  return onSnapshot(
    collectionRef,
    (snapshot) => {
      const next = snapshot.docs.map((doc) => ({ ...(doc.data() as object), id: doc.id } as ProjectSummary));
      onChange(toSafeArray(next));
    },
    (error) => {
      console.warn('[scopedListData] projects subscription failed', error);
      onChange([]);
    }
  );
}
