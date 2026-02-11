import {
  addDoc,
  collection,
  getDocs,
  getDocsFromCache,
  getDocsFromServer,
  onSnapshot,
  query,
  serverTimestamp,
  where,
} from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';

export type Invite = {
  id: string;
  accountId: string;
  email: string;
  role: 'admin' | 'user';
  token: string;
  createdAt?: unknown;
  createdByUid?: string | null;
  acceptedAt?: unknown;
  revokedAt?: unknown;
};

type Unsubscribe = () => void;

function normalizeInviteFromFirestore(raw: unknown, id: string, accountId: string): Invite {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return { ...(data as object), id, accountId } as Invite;
}

function generateToken(): string {
  return Math.random().toString(36).slice(2, 10) + Math.random().toString(36).slice(2, 10);
}

export function subscribeToInvites(accountId: string, onChange: (invites: Invite[]) => void): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }
  const collectionRef = collection(db, `accounts/${accountId}/invites`);
  const queryRef = query(collectionRef, where('revokedAt', '==', null));
  return onSnapshot(
    queryRef,
      (snapshot) => {
        const invites = snapshot.docs.map(
          (doc) => normalizeInviteFromFirestore(doc.data(), doc.id, accountId)
        );
        onChange(invites);
      },
      (error) => {
        console.warn('[invitesService] subscription failed', error);
        onChange([]);
      }
    );
}

export async function createInvite(params: {
  accountId: string;
  email: string;
  role: 'admin' | 'user';
  createdByUid?: string | null;
}): Promise<Invite> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const { accountId, email, role, createdByUid } = params;
  const trimmed = email.trim().toLowerCase();
  if (!trimmed) {
    throw new Error('Email is required.');
  }
  const token = generateToken();
  const now = serverTimestamp();
  const ref = await addDoc(collection(db, `accounts/${accountId}/invites`), {
    accountId,
    email: trimmed,
    role,
    token,
    createdByUid: createdByUid ?? null,
    createdAt: now,
    revokedAt: null,
    acceptedAt: null,
  });
  return { id: ref.id, accountId, email: trimmed, role, token };
}

export async function fetchPendingInvites(
  accountId: string,
  mode: 'online' | 'offline' = 'online'
): Promise<Invite[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const ref = query(
    collection(db, `accounts/${accountId}/invites`),
    where('revokedAt', '==', null)
  );
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      const snapshot =
        source === 'cache' ? await getDocsFromCache(ref) : await getDocsFromServer(ref);
      return snapshot.docs.map(
        (doc: any) => normalizeInviteFromFirestore(doc.data(), doc.id, accountId)
      );
    } catch {
      // try next
    }
  }
  const snapshot = await getDocs(ref);
  return snapshot.docs.map(
    (doc: any) => normalizeInviteFromFirestore(doc.data(), doc.id, accountId)
  );
}
