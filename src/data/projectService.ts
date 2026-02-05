import { serverTimestamp } from '@react-native-firebase/firestore';
import { functions, isFirebaseConfigured } from '../firebase/firebase';
import { createRepository } from './repository';

export type Project = {
  id: string;
  accountId: string;
  name: string;
  clientName: string;
  description?: string | null;
  mainImageUrl?: string | null;
  isArchived?: boolean | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

type CreateProjectPayload = {
  accountId: string;
  name: string;
  clientName: string;
};

type CreateProjectResponse = {
  projectId: string;
};

export async function createProject(payload: CreateProjectPayload): Promise<CreateProjectResponse> {
  if (!isFirebaseConfigured || !functions) {
    throw new Error(
      'Firebase is not configured. Add google-services.json / GoogleService-Info.plist and rebuild the dev client.'
    );
  }
  const callable = functions.httpsCallable<CreateProjectPayload, CreateProjectResponse>('createProject');
  const response = await callable(payload);
  return response.data;
}

export function subscribeToProject(
  accountId: string,
  projectId: string,
  onChange: (project: Project | null) => void
): () => void {
  const repo = createRepository<Project>(`accounts/${accountId}/projects`, 'offline');
  return repo.subscribe(projectId, onChange);
}

export async function updateProject(
  accountId: string,
  projectId: string,
  data: Partial<Project>
): Promise<void> {
  const repo = createRepository<Project>(`accounts/${accountId}/projects`, 'online');
  await repo.upsert(projectId, {
    ...data,
    updatedAt: serverTimestamp(),
  });
}

export async function deleteProject(accountId: string, projectId: string): Promise<void> {
  const repo = createRepository<Project>(`accounts/${accountId}/projects`, 'online');
  await repo.delete(projectId);
}
