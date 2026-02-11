import {
  FieldPath,
  collection,
  doc,
  getDoc,
  getDocFromCache,
  getDocFromServer,
  getDocs,
  getDocsFromCache,
  getDocsFromServer,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  where,
} from '@react-native-firebase/firestore';
import { auth, db, isFirebaseConfigured } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';
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

function normalizeProjectPreferencesFromFirestore(raw: unknown, id: string): ProjectPreferences {
  const data = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const pinnedIds = Array.isArray(data.pinnedBudgetCategoryIds)
    ? data.pinnedBudgetCategoryIds
    : [];
  return { ...(data as object), id, pinnedBudgetCategoryIds: pinnedIds } as ProjectPreferences;
}

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
        onChange(normalizeProjectPreferencesFromFirestore(snapshot.data(), snapshot.id));
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
): Promise<ProjectPreferences | null> {
  if (!isFirebaseConfigured || !db) return null;

  const uid = auth?.currentUser?.uid;
  if (!uid) return null;

  const ref = doc(db, `accounts/${accountId}/users/${uid}/projectPreferences/${projectId}`);

  // Try cache first, then server, then fallback to bare getDoc
  let snapshot;
  try {
    snapshot = await getDocFromCache(ref);
  } catch {
    try {
      snapshot = await getDocFromServer(ref);
    } catch {
      snapshot = await getDoc(ref);
    }
  }

  // Only create if doesn't exist
  if (snapshot.exists) return null;

  // Find Furnishings category
  const budgetCategories = await refreshBudgetCategories(accountId, 'offline');
  const furnishings = budgetCategories.find(c => c.name === 'Furnishings' && !c.isArchived);

  // Check if Furnishings is enabled in this project
  const projectBudgets = await refreshProjectBudgetCategories(accountId, projectId, 'offline');
  const isFurnishingsEnabled = furnishings && projectBudgets.some(pb => pb.id === furnishings.id);

  const pinnedBudgetCategoryIds = isFurnishingsEnabled ? [furnishings.id] : [];

  const prefs: ProjectPreferences = {
    id: projectId,
    accountId,
    userId: uid,
    projectId,
    pinnedBudgetCategoryIds,
  };

  setDoc(ref, {
    ...prefs,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }).catch(err => console.error('[projectPreferencesService] ensureProjectPreferences write failed:', err));
  trackPendingWrite();

  return prefs;
}

export function updateProjectPreferences(
  accountId: string,
  userId: string,
  projectId: string,
  data: Partial<Omit<ProjectPreferences, 'id' | 'accountId' | 'userId' | 'projectId' | 'createdAt' | 'updatedAt'>>
): void {
  if (!isFirebaseConfigured || !db) {
    return;
  }
  const ref = doc(db, `accounts/${accountId}/users/${userId}/projectPreferences/${projectId}`);
  setDoc(
    ref,
    {
      ...data,
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  ).catch(err => console.error('[projectPreferences] updateProjectPreferences failed:', err));
  trackPendingWrite();
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
    const q = query(
      collection(db, `accounts/${accountId}/users/${userId}/projectPreferences`),
      where(FieldPath.documentId(), 'in', chunk)
    );

    // Try cache first, then server, then fallback to bare getDocs
    let snapshot;
    try {
      snapshot = await getDocsFromCache(q);
    } catch {
      try {
        snapshot = await getDocsFromServer(q);
      } catch {
        snapshot = await getDocs(q);
      }
    }

    snapshot.docs.forEach((doc) => {
      output[doc.id] = normalizeProjectPreferencesFromFirestore(doc.data(), doc.id);
    });
  }
  return output;
}
