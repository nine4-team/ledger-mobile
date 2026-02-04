import { globalListenerManager } from '../data/listenerManager';
import { refreshTrackedRequestDocs } from './requestDocTracker';
import { retryPendingUploads } from '../offline/media/mediaStore';
import { useSyncStatusStore } from './syncStatusStore';

export async function triggerManualSync(): Promise<void> {
  const store = useSyncStatusStore.getState();
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
