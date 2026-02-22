import { collection, doc, serverTimestamp, setDoc } from '@react-native-firebase/firestore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import { trackPendingWrite } from '../sync/pendingWrites';
import { createRepository } from './repository';

export type BudgetSummaryCategory = {
  budgetCents: number;
  spentCents: number;
  name: string;
  categoryType: string | null;
  excludeFromOverallBudget: boolean;
  isArchived: boolean;
};

export type ProjectBudgetSummary = {
  spentCents: number;
  totalBudgetCents: number;
  categories: Record<string, BudgetSummaryCategory>;
  updatedAt?: unknown;
};

export type Project = {
  id: string;
  accountId: string;
  name: string;
  clientName: string;
  description?: string | null;
  mainImageUrl?: string | null;
  isArchived?: boolean | null;
  budgetSummary?: ProjectBudgetSummary | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

type CreateProjectPayload = {
  accountId: string;
  name: string;
  clientName: string;
  description?: string | null;
};

type CreateProjectResponse = {
  projectId: string;
};

export function createProject(payload: CreateProjectPayload): CreateProjectResponse {
  if (!isFirebaseConfigured || !db) {
    throw new Error('Firebase is not configured.');
  }
  const projectRef = doc(collection(db, `accounts/${payload.accountId}/projects`));
  const projectId = projectRef.id;

  // Write project doc (fire-and-forget)
  setDoc(projectRef, {
    accountId: payload.accountId,
    name: payload.name,
    clientName: payload.clientName,
    description: payload.description ?? null,
    isArchived: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }).catch(err => console.error('[projects] create failed:', err));
  trackPendingWrite();

  return { projectId };
}

export function subscribeToProject(
  accountId: string,
  projectId: string,
  onChange: (project: Project | null) => void
): () => void {
  const repo = createRepository<Project>(`accounts/${accountId}/projects`, 'offline');
  return repo.subscribe(projectId, onChange);
}

export function updateProject(
  accountId: string,
  projectId: string,
  data: Partial<Project>
): void {
  const repo = createRepository<Project>(`accounts/${accountId}/projects`, 'online');
  repo.upsert(projectId, {
    ...data,
    updatedAt: serverTimestamp(),
  });
}

export function deleteProject(accountId: string, projectId: string): void {
  const repo = createRepository<Project>(`accounts/${accountId}/projects`, 'online');
  repo.delete(projectId);
}
