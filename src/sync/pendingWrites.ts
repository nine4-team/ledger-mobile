import { waitForPendingWrites } from '@react-native-firebase/firestore';

import { useSyncStatusStore } from './syncStatusStore';
import { db, isFirebaseConfigured } from '../firebase/firebase';

let pendingTokens: string[] = [];

export function trackPendingWrite(): void {
  if (!isFirebaseConfigured) {
    return;
  }
  if (!db) {
    return;
  }
  const token = `${Date.now()}_${Math.random().toString(36).slice(2)}`;
  pendingTokens.push(token);
  const store = useSyncStatusStore.getState();
  store.setPendingWritesCount(pendingTokens.length);
  store.setSyncing(true);

  waitForPendingWrites(db)
    .then(() => {
      pendingTokens = [];
      store.setPendingWritesCount(0);
    })
    .catch((error) => {
      const message = error instanceof Error ? error.message : 'Pending writes failed.';
      store.setLastError(message);
    })
    .finally(() => {
      store.setSyncing(false);
    });
}
