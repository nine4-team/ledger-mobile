import {
  FieldPath,
  collection,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  where,
} from '@react-native-firebase/firestore';
import { auth, db, isFirebaseConfigured } from '../firebase/firebase';
import { refreshBudgetCategories } from './budgetCategoriesService';
import { refreshProjectBudgetCategories } from './projectBudgetCategoriesService';

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
  const ref = doc(db, `accounts/${accountId}/users/${userId}/projectPreferences/${projectId}`);
  return onSnapshot(
    ref,
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
  projectId: string
): Promise<void> {
  if (!isFirebaseConfigured || !db) return;

  const uid = auth?.currentUser?.uid;
  if (!uid) return;

  const ref = doc(db, `accounts/${accountId}/users/${uid}/projectPreferences/${projectId}`);
  const snapshot = await getDoc(ref);

  // Only create if doesn't exist
  if (snapshot.exists()) return;

  // Find Furnishings category
  const budgetCategories = await refreshBudgetCategories(accountId, 'online');
  const furnishings = budgetCategories.find(c => c.name === 'Furnishings' && !c.isArchived);

  // Check if Furnishings is enabled in this project
  const projectBudgets = await refreshProjectBudgetCategories(accountId, projectId, 'online');
  const isFurnishingsEnabled = furnishings && projectBudgets.some(pb => pb.id === furnishings.id);

  const pinnedBudgetCategoryIds = isFurnishingsEnabled ? [furnishings.id] : [];

  await setDoc(ref, {
    id: projectId,
    accountId,
    userId: uid,
    projectId,
    pinnedBudgetCategoryIds,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
}

export async function updateProjectPreferences(
  accountId: string,
  userId: string,
  projectId: string,
  data: Partial<Omit<ProjectPreferences, 'id' | 'accountId' | 'userId' | 'projectId' | 'createdAt' | 'updatedAt'>>
): Promise<void> {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  const ref = doc(db, `accounts/${accountId}/users/${userId}/projectPreferences/${projectId}`);
  await setDoc(
    ref,
    {
      ...data,
      updatedAt: serverTimestamp(),
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
    const snapshot = await getDocs(
      query(
        collection(db, `accounts/${accountId}/users/${userId}/projectPreferences`),
        where(FieldPath.documentId(), 'in', chunk)
      )
    );
    snapshot.docs.forEach((doc) => {
      output[doc.id] = { ...(doc.data() as object), id: doc.id } as ProjectPreferences;
    });
  }
  return output;
}
