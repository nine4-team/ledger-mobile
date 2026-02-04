import firestore from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';
import type { AttachmentRef } from '../offline/media';

export type ChecklistItem = {
  id: string;
  text: string;
  isChecked: boolean;
};

export type Checklist = {
  id: string;
  name: string;
  items: ChecklistItem[];
};

export type Space = {
  id: string;
  projectId: string | null;
  name: string;
  notes?: string | null;
  images?: AttachmentRef[] | null;
  checklists?: Checklist[] | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

type Unsubscribe = () => void;

export function subscribeToSpaces(
  accountId: string,
  projectId: string | null,
  onChange: (spaces: Space[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }
  const collectionRef = db.collection(`accounts/${accountId}/spaces`);
  const query = collectionRef.where('projectId', '==', projectId);
  return query.onSnapshot(
    (snapshot) => {
      const next = snapshot.docs.map((doc) => ({ ...(doc.data() as object), id: doc.id } as Space));
      onChange(next);
    },
    (error) => {
      console.warn('[spacesService] subscription failed', error);
      onChange([]);
    }
  );
}

export async function refreshSpaces(
  accountId: string,
  projectId: string | null,
  mode: 'online' | 'offline' = 'online'
): Promise<Space[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const collectionRef = db.collection(`accounts/${accountId}/spaces`);
  const query = collectionRef.where('projectId', '==', projectId);
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      const snapshot = await (query as any).get({ source });
      return snapshot.docs.map((doc: any) => ({ ...(doc.data() as object), id: doc.id } as Space));
    } catch {
      // try next
    }
  }
  const snapshot = await (query as any).get();
  return snapshot.docs.map((doc: any) => ({ ...(doc.data() as object), id: doc.id } as Space));
}

export async function createSpace(
  accountId: string,
  data: Pick<Space, 'name' | 'notes' | 'projectId'> &
    Partial<Pick<Space, 'checklists' | 'images'>>
): Promise<string> {
  if (!isFirebaseConfigured || !db) {
    throw new Error(
      'Firebase is not configured. Add google-services.json / GoogleService-Info.plist and rebuild the dev client.'
    );
  }
  const now = firestore.FieldValue.serverTimestamp();
  const docRef = await db.collection(`accounts/${accountId}/spaces`).add({
    name: data.name,
    notes: data.notes ?? null,
    projectId: data.projectId ?? null,
    checklists: data.checklists ?? null,
    images: data.images ?? null,
    createdAt: now,
    updatedAt: now,
  });
  trackPendingWrite();
  return docRef.id;
}

export async function updateSpace(
  accountId: string,
  spaceId: string,
  data: Partial<Space>
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  await db
    .collection(`accounts/${accountId}/spaces`)
    .doc(spaceId)
    .set(
      {
        ...data,
        updatedAt: firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  trackPendingWrite();
}

export async function deleteSpace(accountId: string, spaceId: string): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  await db.collection(`accounts/${accountId}/spaces`).doc(spaceId).delete();
  trackPendingWrite();
}

export function subscribeToSpace(
  accountId: string,
  spaceId: string,
  onChange: (space: Space | null) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange(null);
    return () => {};
  }
  return db
    .collection(`accounts/${accountId}/spaces`)
    .doc(spaceId)
    .onSnapshot(
      (snapshot) => {
        if (!snapshot.exists) {
          onChange(null);
          return;
        }
        onChange({ ...(snapshot.data() as object), id: snapshot.id } as Space);
      },
      (error) => {
        console.warn('[spacesService] space subscription failed', error);
        onChange(null);
      }
    );
}
