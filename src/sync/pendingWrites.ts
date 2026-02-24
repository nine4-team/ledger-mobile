import { waitForPendingWrites } from '@react-native-firebase/firestore';

import { useSyncStatusStore } from './syncStatusStore';
import { db, isFirebaseConfigured } from '../firebase/firebase';

let pendingCount = 0;
let flushScheduled = false;

export function trackPendingWrite(): void {
  if (!isFirebaseConfigured || !db) {
    return;
  }

  pendingCount += 1;
  const store = useSyncStatusStore.getState();
  store.setPendingWritesCount(pendingCount);
  store.setSyncing(true);

  // Only start one waitForPendingWrites at a time. If one is already in flight,
  // it will observe the new write too — no need to start another.
  if (flushScheduled) {
    return;
  }

  flushScheduled = true;
  waitForPendingWrites(db)
    .then(() => {
      pendingCount = 0;
      flushScheduled = false;
      useSyncStatusStore.getState().setPendingWritesCount(0);
    })
    .catch((error) => {
      flushScheduled = false;
      const message = error instanceof Error ? error.message : 'Pending writes failed.';
      useSyncStatusStore.getState().setLastError(message);
    })
    .finally(() => {
      useSyncStatusStore.getState().setSyncing(false);
    });
}
