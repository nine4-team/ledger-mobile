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
  budgetCategoryId?: string | null;
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

function normalizeScopedItemFromFirestore(raw: unknown, id: string): ScopedItem {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  // Legacy: older docs used `description` as the primary label.
  const legacyDescription = typeof data.description === 'string' ? data.description : null;
  const rawName = typeof data.name === 'string' ? data.name : null;
  const name = rawName && rawName.trim().length > 0 ? rawName : legacyDescription;

  const rest: Record<string, unknown> = { ...data };
  delete (rest as any).description;
  return { ...(rest as object), id, name: name ?? null } as ScopedItem;
}

function normalizeScopedTransactionFromFirestore(raw: unknown, id: string): ScopedTransaction {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return { ...(data as object), id } as ScopedTransaction;
}

function normalizeProjectSummaryFromFirestore(raw: unknown, id: string): ProjectSummary {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return { ...(data as object), id } as ProjectSummary;
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
      const next = snapshot.docs.map((doc) => normalizeScopedItemFromFirestore(doc.data(), doc.id));
      onChange(toSafeArray(next));
    },
    (error) => {
      console.warn('[scopedListData] items subscription failed', error);
      onChange([]);
    }
  );
}

export function subscribeToTransactionItems(
  accountId: string,
  transactionId: string,
  onChange: (items: ScopedItem[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }

  const q = query(collection(db, `accounts/${accountId}/items`), where('transactionId', '==', transactionId));

  return onSnapshot(
    q,
    (snapshot) => {
      const next = snapshot.docs.map((doc) => normalizeScopedItemFromFirestore(doc.data(), doc.id));
      onChange(toSafeArray(next));
    },
    (error) => {
      console.warn('[scopedListData] transaction items subscription failed', error);
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
      const next = snapshot.docs.map((doc) => normalizeScopedTransactionFromFirestore(doc.data(), doc.id));
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
  return snapshot.docs.map((doc: any) => normalizeScopedItemFromFirestore(doc.data(), doc.id));
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
  return snapshot.docs.map((doc: any) => normalizeScopedTransactionFromFirestore(doc.data(), doc.id));
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
      const next = snapshot.docs.map((doc) => normalizeProjectSummaryFromFirestore(doc.data(), doc.id));
      onChange(toSafeArray(next));
    },
    (error) => {
      console.warn('[scopedListData] projects subscription failed', error);
      onChange([]);
    }
  );
}
