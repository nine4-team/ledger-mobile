import {
  collection,
  doc,
  getDocsFromCache,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  where,
} from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ItemLineageMovementKind = 'sold' | 'returned' | 'correction' | 'association';
export type ItemLineageSource = 'app' | 'server' | 'migration';

export type ItemLineageEdge = {
  id: string;
  accountId: string;
  itemId: string;
  fromTransactionId: string | null;
  toTransactionId: string | null;
  movementKind: ItemLineageMovementKind;
  source: ItemLineageSource;
  createdAt: unknown;
  createdBy?: string | null;
  note?: string | null;
  fromProjectId?: string | null;
  toProjectId?: string | null;
};

// ---------------------------------------------------------------------------
// Normalizer
// ---------------------------------------------------------------------------

export function normalizeEdgeFromFirestore(raw: unknown, id: string): ItemLineageEdge {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return {
    ...(data as object),
    id,
    fromTransactionId: (data.fromTransactionId as string) ?? null,
    toTransactionId: (data.toTransactionId as string) ?? null,
    movementKind: (data.movementKind as ItemLineageMovementKind) ?? 'association',
    source: (data.source as ItemLineageSource) ?? 'server',
  } as ItemLineageEdge;
}

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

export function subscribeToEdgesFromTransaction(
  accountId: string,
  transactionId: string,
  onChange: (edges: ItemLineageEdge[]) => void,
): () => void {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }

  const q = query(
    collection(db, `accounts/${accountId}/lineageEdges`),
    where('fromTransactionId', '==', transactionId),
  );

  // Cache-first prelude: React Native Firebase's onSnapshot does NOT read
  // from cache on the first callback — it waits for a server round-trip.
  // getDocsFromCache gives us instant results while the listener spins up.
  getDocsFromCache(q)
    .then(snapshot => {
      const edges = snapshot.docs.map(d => normalizeEdgeFromFirestore(d.data(), d.id));
      onChange(edges);
    })
    .catch(() => {
      onChange([]);
    });

  // Real-time listener for ongoing updates
  return onSnapshot(
    q,
    (snapshot) => {
      const edges = snapshot.docs.map(d => normalizeEdgeFromFirestore(d.data(), d.id));
      onChange(edges);
    },
    (error) => {
      console.warn('[lineageEdgesService] subscription failed', error);
      onChange([]);
    },
  );
}

// ---------------------------------------------------------------------------
// Writes
// ---------------------------------------------------------------------------

export function createLineageEdge(
  accountId: string,
  edge: Omit<ItemLineageEdge, 'id' | 'createdAt'>,
): string {
  if (!isFirebaseConfigured || !db) {
    throw new Error(
      'Firebase is not configured. Add google-services.json / GoogleService-Info.plist and rebuild the dev client.',
    );
  }

  const edgeId = `app_${Date.now()}_${edge.itemId}_${edge.movementKind}`;
  const docRef = doc(collection(db, `accounts/${accountId}/lineageEdges`), edgeId);

  setDoc(docRef, {
    ...edge,
    createdAt: serverTimestamp(),
  }).catch(err => console.error('[lineageEdgesService] createLineageEdge failed:', err));

  trackPendingWrite();

  return edgeId;
}
