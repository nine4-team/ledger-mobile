import AsyncStorage from '@react-native-async-storage/async-storage';
import firestore from '@react-native-firebase/firestore';

import { useSyncStatusStore } from './syncStatusStore';
import { isFirebaseConfigured } from '../firebase/firebase';

const STORAGE_KEY = 'sync/request-docs';

type TrackedRequest = {
  path: string;
  status?: string;
  errorMessage?: string;
};

const subscriptions = new Map<string, () => void>();
const trackedRequests = new Map<string, TrackedRequest>();

function updateCounts() {
  let pending = 0;
  let failed = 0;
  trackedRequests.forEach((request) => {
    if (request.status === 'failed' || request.status === 'denied') {
      failed += 1;
      return;
    }
    if (request.status === 'pending' || !request.status) {
      pending += 1;
    }
  });
  useSyncStatusStore.getState().setRequestDocCounts(pending, failed);
}

async function persistTrackedRequests() {
  const paths = Array.from(trackedRequests.keys());
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(paths));
}

function attachSubscription(path: string) {
  if (subscriptions.has(path)) {
    return;
  }
  if (!isFirebaseConfigured) {
    return;
  }
  const unsubscribe = firestore()
    .doc(path)
    .onSnapshot(
      (snapshot) => {
        if (!snapshot.exists) {
          trackedRequests.set(path, { path, status: 'failed', errorMessage: 'Request missing.' });
          updateCounts();
          persistTrackedRequests();
          return;
        }
        const data = snapshot.data() as { status?: string; errorMessage?: string } | undefined;
        const status = data?.status ?? 'pending';
        const errorMessage = data?.errorMessage;
        trackedRequests.set(path, { path, status, errorMessage });
        updateCounts();
        if (status === 'applied') {
          untrackRequestDocPath(path);
        } else {
          persistTrackedRequests();
        }
        if (status === 'failed' || status === 'denied') {
          useSyncStatusStore
            .getState()
            .setLastError(errorMessage || 'Request failed.');
        }
      },
      (error) => {
        const message = error instanceof Error ? error.message : 'Request listener failed.';
        trackedRequests.set(path, { path, status: 'failed', errorMessage: message });
        useSyncStatusStore.getState().setLastError(message);
        updateCounts();
      }
    );
  subscriptions.set(path, unsubscribe);
}

export async function startRequestDocTracking(): Promise<void> {
  if (!isFirebaseConfigured) {
    return;
  }
  const stored = await AsyncStorage.getItem(STORAGE_KEY);
  if (!stored) {
    return;
  }
  let paths: string[] = [];
  try {
    paths = JSON.parse(stored);
  } catch {
    await AsyncStorage.removeItem(STORAGE_KEY);
    return;
  }
  paths.forEach((path) => {
    trackedRequests.set(path, { path, status: 'pending' });
    attachSubscription(path);
  });
  updateCounts();
}

export function trackRequestDocPath(path: string): void {
  if (!isFirebaseConfigured) {
    return;
  }
  trackedRequests.set(path, { path, status: 'pending' });
  attachSubscription(path);
  updateCounts();
  void persistTrackedRequests();
}

export function untrackRequestDocPath(path: string): void {
  const unsubscribe = subscriptions.get(path);
  if (unsubscribe) {
    unsubscribe();
  }
  subscriptions.delete(path);
  trackedRequests.delete(path);
  updateCounts();
  void persistTrackedRequests();
}

export async function refreshTrackedRequestDocs(): Promise<void> {
  if (!isFirebaseConfigured) {
    return;
  }
  const paths = Array.from(trackedRequests.keys());
  await Promise.all(
    paths.map(async (path) => {
      try {
        const snapshot = await firestore().doc(path).get();
        if (!snapshot.exists) {
          trackedRequests.set(path, { path, status: 'failed', errorMessage: 'Request missing.' });
          return;
        }
        const data = snapshot.data() as { status?: string; errorMessage?: string } | undefined;
        trackedRequests.set(path, {
          path,
          status: data?.status ?? 'pending',
          errorMessage: data?.errorMessage,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Request refresh failed.';
        trackedRequests.set(path, { path, status: 'failed', errorMessage: message });
        useSyncStatusStore.getState().setLastError(message);
      }
    })
  );
  updateCounts();
  await persistTrackedRequests();
}
