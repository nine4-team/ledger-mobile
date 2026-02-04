import firestore from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import type { Checklist } from './spacesService';

export type SpaceTemplate = {
  id: string;
  accountId: string;
  name: string;
  isArchived?: boolean | null;
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
  return db
    .collection(`accounts/${accountId}/presets/default/spaceTemplates`)
    .onSnapshot(
      (snapshot) => {
        const next = snapshot.docs.map(
          (doc) => ({ ...(doc.data() as object), id: doc.id } as SpaceTemplate)
        );
        onChange(next.filter((template) => !template.isArchived));
      },
      (error) => {
        console.warn('[spaceTemplatesService] subscription failed', error);
        onChange([]);
      }
    );
}

function normalizeChecklists(checklists: Checklist[] | null | undefined): Checklist[] | null {
  if (!checklists?.length) return null;
  return checklists.map((checklist) => ({
    ...checklist,
    items: checklist.items.map((item) => ({ ...item, isChecked: false })),
  }));
}

export async function createSpaceTemplate(
  accountId: string,
  data: Omit<SpaceTemplate, 'id' | 'accountId' | 'isArchived' | 'createdAt' | 'updatedAt'>
): Promise<string> {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const now = firestore.FieldValue.serverTimestamp();
  const docRef = await db
    .collection(`accounts/${accountId}/presets/default/spaceTemplates`)
    .add({
      ...data,
      accountId,
      isArchived: false,
      checklists: normalizeChecklists(data.checklists ?? null),
      createdAt: now,
      updatedAt: now,
    });
  return docRef.id;
}
