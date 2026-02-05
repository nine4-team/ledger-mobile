import {
  addDoc,
  collection,
  doc,
  onSnapshot,
  serverTimestamp,
} from '@react-native-firebase/firestore';
import { auth, db, isFirebaseConfigured } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';
import { trackRequestDocPath } from '../sync/requestDocTracker';

export type RequestStatus = 'pending' | 'applied' | 'failed' | 'denied';

export type RequestScope =
  | { accountId: string; scope: 'account' }
  | { accountId: string; scope: 'inventory' }
  | { accountId: string; projectId: string };

export type RequestDoc<TPayload extends Record<string, unknown> = Record<string, unknown>> = {
  type: string;
  status: RequestStatus;
  opId: string;
  createdAt?: unknown;
  createdBy?: string;
  appliedAt?: unknown;
  errorCode?: string;
  errorMessage?: string;
  payload: TPayload;
};

export function generateRequestOpId(): string {
  const cryptoApi = globalThis.crypto as { randomUUID?: () => string } | undefined;
  if (cryptoApi?.randomUUID) {
    return cryptoApi.randomUUID();
  }
  return 'op_' + Math.random().toString(36).slice(2) + Date.now().toString(36);
}

export function getRequestCollectionPath(scope: RequestScope): string {
  if ('projectId' in scope) {
    return `accounts/${scope.accountId}/projects/${scope.projectId}/requests`;
  }
  if (scope.scope === 'account') {
    return `accounts/${scope.accountId}/requests`;
  }
  return `accounts/${scope.accountId}/inventory/requests`;
}

export function getRequestDocPath(scope: RequestScope, requestId: string): string {
  return `${getRequestCollectionPath(scope)}/${requestId}`;
}

export function parseRequestDocPath(path: string): RequestScope | null {
  const trimmed = path.trim();
  const projectMatch = trimmed.match(/^accounts\/([^/]+)\/projects\/([^/]+)\/requests\/[^/]+$/);
  if (projectMatch) {
    return { accountId: projectMatch[1], projectId: projectMatch[2] };
  }
  const accountMatch = trimmed.match(/^accounts\/([^/]+)\/requests\/[^/]+$/);
  if (accountMatch) {
    return { accountId: accountMatch[1], scope: 'account' };
  }
  const inventoryMatch = trimmed.match(/^accounts\/([^/]+)\/inventory\/requests\/[^/]+$/);
  if (inventoryMatch) {
    return { accountId: inventoryMatch[1], scope: 'inventory' };
  }
  return null;
}

export async function createRequestDoc<TPayload extends Record<string, unknown>>(
  type: string,
  payload: TPayload,
  scope: RequestScope,
  opId: string
): Promise<string> {
  if (!isFirebaseConfigured || !db) {
    throw new Error(
      'Firebase is not configured. Add google-services.json / GoogleService-Info.plist and rebuild the dev client.'
    );
  }
  const uid = auth?.currentUser?.uid;
  if (!uid) {
    throw new Error('Must be signed in to create a request.');
  }
  if (!opId) {
    throw new Error('Request opId is required to create a request.');
  }

  const requestDoc: RequestDoc<TPayload> = {
    type,
    status: 'pending',
    opId,
    createdAt: serverTimestamp(),
    createdBy: uid,
    payload
  };

  const docRef = await addDoc(collection(db, getRequestCollectionPath(scope)), requestDoc);
  trackPendingWrite();
  trackRequestDocPath(docRef.path);
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
    if (!snapshot.exists) {
      onChange(null);
      return;
    }
    onChange({ ...(snapshot.data() as RequestDoc<TPayload>), id: snapshot.id });
  });
}
