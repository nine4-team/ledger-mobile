import AsyncStorage from '@react-native-async-storage/async-storage';
import { doc, getDoc, onSnapshot } from '@react-native-firebase/firestore';

import { useSyncStatusStore } from './syncStatusStore';
import { db, isFirebaseConfigured } from '../firebase/firebase';
import type { RequestDoc } from '../data/requestDocs';

const STORAGE_KEY = 'sync/request-docs';

export type TrackedRequest = {
  path: string;
  status?: string;
  errorMessage?: string;
  doc?: RequestDoc<Record<string, unknown>>;
};

const subscriptions = new Map<string, () => void>();
const trackedRequests = new Map<string, TrackedRequest>();
const listeners = new Set<(requests: TrackedRequest[]) => void>();

function notifyListeners() {
  const payload = Array.from(trackedRequests.values());
  listeners.forEach((listener) => listener(payload));
}

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
  notifyListeners();
}

async function persistTrackedRequests() {
  const paths = Array.from(trackedRequests.keys());
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(paths));
}

function attachSubscription(path: string) {
  if (subscriptions.has(path)) {
    return;
  }
  if (!isFirebaseConfigured || !db) {
    return;
  }
  const ref = doc(db, path);
  const unsubscribe = onSnapshot(
    ref,
      (snapshot) => {
        if (!snapshot.exists) {
          trackedRequests.set(path, { path, status: 'failed', errorMessage: 'Request missing.' });
          updateCounts();
          persistTrackedRequests();
          return;
        }
        const data = snapshot.data() as RequestDoc<Record<string, unknown>> | undefined;
        const status = data?.status ?? 'pending';
        const errorMessage = data?.errorMessage;
        trackedRequests.set(path, { path, status, errorMessage, doc: data });
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
  if (!isFirebaseConfigured || !db) {
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
        const snapshot = await getDoc(doc(db, path));
        if (!snapshot.exists) {
          trackedRequests.set(path, { path, status: 'failed', errorMessage: 'Request missing.' });
          return;
        }
        const data = snapshot.data() as RequestDoc<Record<string, unknown>> | undefined;
        trackedRequests.set(path, {
          path,
          status: data?.status ?? 'pending',
          errorMessage: data?.errorMessage,
          doc: data,
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

export function subscribeToTrackedRequests(onChange: (requests: TrackedRequest[]) => void): () => void {
  listeners.add(onChange);
  onChange(Array.from(trackedRequests.values()));
  return () => {
    listeners.delete(onChange);
  };
}

export function getTrackedRequestsSnapshot(): TrackedRequest[] {
  return Array.from(trackedRequests.values());
}

export function dismissFailedRequestDocs(): void {
  const paths = Array.from(trackedRequests.keys());
  for (const path of paths) {
    const request = trackedRequests.get(path);
    if (request && (request.status === 'failed' || request.status === 'denied')) {
      untrackRequestDocPath(path);
    }
  }
}
