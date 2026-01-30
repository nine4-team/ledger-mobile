import { addDoc, collection, doc, onSnapshot, serverTimestamp } from 'firebase/firestore';
import { auth, db, isFirebaseConfigured } from '../firebase/firebase';

export type RequestStatus = 'pending' | 'applied' | 'failed';

export type RequestScope =
  | { accountId: string; projectId: string }
  | { accountId: string; scope: 'inventory' };

export type RequestDoc<TPayload extends Record<string, unknown> = Record<string, unknown>> = {
  type: string;
  status: RequestStatus;
  createdAt?: unknown;
  createdBy?: string;
  appliedAt?: unknown;
  errorCode?: string;
  errorMessage?: string;
  payload?: TPayload;
};

export function getRequestCollectionPath(scope: RequestScope): string {
  if ('projectId' in scope) {
    return `accounts/${scope.accountId}/projects/${scope.projectId}/requests`;
  }
  return `accounts/${scope.accountId}/inventory/requests`;
}

export function getRequestDocPath(scope: RequestScope, requestId: string): string {
  return `${getRequestCollectionPath(scope)}/${requestId}`;
}

export async function createRequestDoc<TPayload extends Record<string, unknown>>(
  type: string,
  payload: TPayload,
  scope: RequestScope
): Promise<string> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured. Configure EXPO_PUBLIC_FIREBASE_* first.');
  }
  const uid = auth?.currentUser?.uid;
  if (!uid) {
    throw new Error('Must be signed in to create a request.');
  }

  const requestDoc: RequestDoc<TPayload> = {
    type,
    status: 'pending',
    createdAt: serverTimestamp(),
    createdBy: uid,
    payload
  };

  const docRef = await addDoc(collection(db, getRequestCollectionPath(scope)), requestDoc);
  return docRef.id;
}

export function subscribeToRequest<TPayload extends Record<string, unknown>>(
  scope: RequestScope,
  requestId: string,
  onChange: (doc: (RequestDoc<TPayload> & { id: string }) | null) => void
): () => void {
  return subscribeToRequestPath(getRequestDocPath(scope, requestId), onChange);
}

export function subscribeToRequestPath<TPayload extends Record<string, unknown>>(
  requestDocPath: string,
  onChange: (doc: (RequestDoc<TPayload> & { id: string }) | null) => void
): () => void {
  if (!isFirebaseConfigured || !db) {
    onChange(null);
    return () => {};
  }

  const ref = doc(db, requestDocPath);
  return onSnapshot(ref, (snapshot) => {
    if (!snapshot.exists()) {
      onChange(null);
      return;
    }
    onChange({ ...(snapshot.data() as RequestDoc<TPayload>), id: snapshot.id });
  });
}
