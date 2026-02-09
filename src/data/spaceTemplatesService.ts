import {
  collection,
  doc,
  getDocs,
  getDocsFromCache,
  getDocsFromServer,
  onSnapshot,
  serverTimestamp,
  setDoc,
} from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';
import type { Checklist } from './spacesService';

export type SpaceTemplate = {
  id: string;
  accountId: string;
  name: string;
  isArchived?: boolean | null;
  order?: number | null;
  notes?: string | null;
  checklists?: Checklist[] | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

type Unsubscribe = () => void;

export function subscribeToSpaceTemplates(
  accountId: string,
  onChange: (templates: SpaceTemplate[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }
  const collectionRef = collection(db, `accounts/${accountId}/presets/default/spaceTemplates`);
  return onSnapshot(
    collectionRef,
      (snapshot) => {
        const next = snapshot.docs.map(
          (doc) => ({ ...(doc.data() as object), id: doc.id } as SpaceTemplate)
        );
        onChange(next);
      },
      (error) => {
        console.warn('[spaceTemplatesService] subscription failed', error);
        onChange([]);
      }
    );
}

export async function refreshSpaceTemplates(
  accountId: string,
  mode: 'online' | 'offline' = 'online'
): Promise<SpaceTemplate[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const ref = collection(db, `accounts/${accountId}/presets/default/spaceTemplates`);
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      const snapshot =
        source === 'cache' ? await getDocsFromCache(ref) : await getDocsFromServer(ref);
      return snapshot.docs.map(
        (doc: any) => ({ ...(doc.data() as object), id: doc.id } as SpaceTemplate)
      );
    } catch {
      // try next
    }
  }
  const snapshot = await getDocs(ref);
  return snapshot.docs.map(
    (doc: any) => ({ ...(doc.data() as object), id: doc.id } as SpaceTemplate)
  );
}

function normalizeChecklists(checklists: Checklist[] | null | undefined): Checklist[] | null {
  if (!checklists?.length) return null;
  return checklists.map((checklist) => ({
    ...checklist,
    items: checklist.items.map((item) => ({ ...item, isChecked: false })),
  }));
}

export function createSpaceTemplate(
  accountId: string,
  data: Omit<SpaceTemplate, 'id' | 'accountId' | 'isArchived' | 'createdAt' | 'updatedAt'>
): string {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const now = serverTimestamp();
  const docRef = doc(collection(db, `accounts/${accountId}/presets/default/spaceTemplates`));
  setDoc(docRef, {
    ...data,
    accountId,
    isArchived: false,
    order: data.order ?? Date.now(),
    checklists: normalizeChecklists(data.checklists ?? null),
    createdAt: now,
    updatedAt: now,
  }).catch(err => console.error('[spaceTemplates] create failed:', err));
  trackPendingWrite();
  return docRef.id;
}

export function updateSpaceTemplate(
  accountId: string,
  templateId: string,
  data: Partial<SpaceTemplate>
): void {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const now = serverTimestamp();
  setDoc(
    doc(db, `accounts/${accountId}/presets/default/spaceTemplates/${templateId}`),
    {
      ...data,
      checklists: normalizeChecklists(data.checklists ?? null),
      updatedAt: now,
    },
    { merge: true }
  ).catch(err => console.error('[spaceTemplates] updateSpaceTemplate failed:', err));
  trackPendingWrite();
}

export function setSpaceTemplateArchived(
  accountId: string,
  templateId: string,
  isArchived: boolean
): void {
  updateSpaceTemplate(accountId, templateId, { isArchived });
}

export function setSpaceTemplateOrder(
  accountId: string,
  orderedIds: string[]
): void {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const now = serverTimestamp();
  Promise.all(
    orderedIds.map((id, index) =>
      setDoc(
        doc(db, `accounts/${accountId}/presets/default/spaceTemplates/${id}`),
        {
          order: index,
          updatedAt: now,
        },
        { merge: true }
      )
    )
  ).catch(err => console.error('[spaceTemplates] setSpaceTemplateOrder failed:', err));
  trackPendingWrite();
}
