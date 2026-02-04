import firestore from '@react-native-firebase/firestore';
import { auth, db, isFirebaseConfigured } from '../firebase/firebase';

export type ProjectPreferences = {
  id: string;
  accountId: string;
  userId: string;
  projectId: string;
  pinnedBudgetCategoryIds: string[];
  createdAt?: unknown;
  updatedAt?: unknown;
};

type Unsubscribe = () => void;

export function subscribeToProjectPreferences(
  accountId: string,
  userId: string,
  projectId: string,
  onChange: (prefs: ProjectPreferences | null) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange(null);
    return () => {};
  }
  return db
    .collection(`accounts/${accountId}/users/${userId}/projectPreferences`)
    .doc(projectId)
    .onSnapshot(
      (snapshot) => {
        if (!snapshot.exists) {
          onChange(null);
          return;
        }
        onChange({ ...(snapshot.data() as object), id: snapshot.id } as ProjectPreferences);
      },
      (error) => {
        console.warn('[projectPreferencesService] subscription failed', error);
        onChange(null);
      }
    );
}

export async function ensureProjectPreferences(
  accountId: string,
  projectId: string,
  pinnedBudgetCategoryIds: string[]
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  const uid = auth?.currentUser?.uid;
  if (!uid) return;
  const ref = db.doc(`accounts/${accountId}/users/${uid}/projectPreferences/${projectId}`);
  const snapshot = await ref.get();
  if (snapshot.exists) return;
  await ref.set(
    {
      id: projectId,
      accountId,
      userId: uid,
      projectId,
      pinnedBudgetCategoryIds,
      createdAt: firestore.FieldValue.serverTimestamp(),
      updatedAt: firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

export async function fetchProjectPreferencesMap(params: {
  accountId: string;
  userId: string;
  projectIds: string[];
}): Promise<Record<string, ProjectPreferences>> {
  if (!isFirebaseConfigured || !db) {
    return {};
  }
  const { accountId, userId, projectIds } = params;
  const output: Record<string, ProjectPreferences> = {};
  if (!projectIds.length) return output;
  const chunks: string[][] = [];
  for (let i = 0; i < projectIds.length; i += 10) {
    chunks.push(projectIds.slice(i, i + 10));
  }
  for (const chunk of chunks) {
    const snapshot = await db
      .collection(`accounts/${accountId}/users/${userId}/projectPreferences`)
      .where(firestore.FieldPath.documentId(), 'in', chunk)
      .get();
    snapshot.docs.forEach((doc) => {
      output[doc.id] = { ...(doc.data() as object), id: doc.id } as ProjectPreferences;
    });
  }
  return output;
}
