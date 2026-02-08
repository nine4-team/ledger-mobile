import { globalListenerManager } from '../data/listenerManager';
import { dismissFailedRequestDocs, refreshTrackedRequestDocs } from './requestDocTracker';
import { dismissFailedUploads, retryPendingUploads } from '../offline/media/mediaStore';
import { useSyncStatusStore } from './syncStatusStore';

export async function triggerManualSync(): Promise<void> {
  const store = useSyncStatusStore.getState();
  store.setLastError(undefined);
  store.setSyncing(true);
  try {
    globalListenerManager.refreshAllScopes();
    await refreshTrackedRequestDocs();
    await retryPendingUploads();
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Manual sync failed.';
    store.setLastError(message);
  } finally {
    store.setSyncing(false);
  }
}

export async function dismissAllSyncErrors(): Promise<void> {
  useSyncStatusStore.getState().dismissSyncErrors();
  dismissFailedRequestDocs();
  await dismissFailedUploads();
}
