import { db, isFirebaseConfigured } from '../firebase/firebase';

export type ProjectBudgetCategory = {
  id: string;
  budgetCents: number | null;
};

type Unsubscribe = () => void;

export function subscribeToProjectBudgetCategories(
  accountId: string,
  projectId: string,
  onChange: (categories: ProjectBudgetCategory[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }
  return db
    .collection(`accounts/${accountId}/projects/${projectId}/budgetCategories`)
    .onSnapshot(
      (snapshot) => {
        const next = snapshot.docs.map(
          (doc) => ({ ...(doc.data() as object), id: doc.id } as ProjectBudgetCategory)
        );
        onChange(next);
      },
      (error) => {
        console.warn('[projectBudgetCategoriesService] subscription failed', error);
        onChange([]);
      }
    );
}

export async function refreshProjectBudgetCategories(
  accountId: string,
  projectId: string,
  mode: 'online' | 'offline' = 'online'
): Promise<ProjectBudgetCategory[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const ref = db.collection(`accounts/${accountId}/projects/${projectId}/budgetCategories`);
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      const snapshot = await (ref as any).get({ source });
      return snapshot.docs.map(
        (doc: any) => ({ ...(doc.data() as object), id: doc.id } as ProjectBudgetCategory)
      );
    } catch {
      // try next
    }
  }
  const snapshot = await ref.get();
  return snapshot.docs.map(
    (doc: any) => ({ ...(doc.data() as object), id: doc.id } as ProjectBudgetCategory)
  );
}
