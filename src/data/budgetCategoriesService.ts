import { db, isFirebaseConfigured } from '../firebase/firebase';

export type BudgetCategory = {
  id: string;
  name: string;
  slug?: string | null;
  isArchived?: boolean | null;
  metadata?: {
    categoryType?: 'standard' | 'itemized' | 'fee';
    excludeFromOverallBudget?: boolean;
    legacy?: Record<string, unknown> | null;
  } | null;
};

type Unsubscribe = () => void;

export function subscribeToBudgetCategories(
  accountId: string,
  onChange: (categories: BudgetCategory[]) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange([]);
    return () => {};
  }
  return db
    .collection(`accounts/${accountId}/presets/default/budgetCategories`)
    .onSnapshot(
      (snapshot) => {
        const next = snapshot.docs.map(
          (doc) => ({ ...(doc.data() as object), id: doc.id } as BudgetCategory)
        );
        onChange(next);
      },
      (error) => {
        console.warn('[budgetCategoriesService] subscription failed', error);
        onChange([]);
      }
    );
}

export async function refreshBudgetCategories(
  accountId: string,
  mode: 'online' | 'offline' = 'online'
): Promise<BudgetCategory[]> {
  if (!isFirebaseConfigured || !db) {
    return [];
  }
  const ref = db.collection(`accounts/${accountId}/presets/default/budgetCategories`);
  const preference = mode === 'offline' ? (['cache', 'server'] as const) : (['server', 'cache'] as const);
  for (const source of preference) {
    try {
      const snapshot = await (ref as any).get({ source });
      return snapshot.docs.map(
        (doc: any) => ({ ...(doc.data() as object), id: doc.id } as BudgetCategory)
      );
    } catch {
      // try next
    }
  }
  const snapshot = await ref.get();
  return snapshot.docs.map(
    (doc: any) => ({ ...(doc.data() as object), id: doc.id } as BudgetCategory)
  );
}

export function mapBudgetCategories(categories: BudgetCategory[]): Record<string, BudgetCategory> {
  return categories.reduce((acc, category) => {
    acc[category.id] = category;
    return acc;
  }, {} as Record<string, BudgetCategory>);
}
