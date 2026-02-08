import { create } from 'zustand';

export type SyncStatusVariant = 'error' | 'syncing' | 'waiting' | 'queue' | 'idle';

type BackgroundError = {
  message: string;
  isOffline: boolean;
  timestamp: number;
};

export interface SyncStatusState {
  pendingWritesCount: number;
  pendingRequestDocs: number;
  failedRequestDocs: number;
  pendingUploads: number;
  failedUploads: number;
  isSyncing: boolean;
  lastError?: string;
  lastErrorAt?: number;
  backgroundError?: BackgroundError;
  setPendingWritesCount: (count: number) => void;
  setRequestDocCounts: (pending: number, failed: number) => void;
  setUploadCounts: (pending: number, failed: number) => void;
  setSyncing: (isSyncing: boolean) => void;
  setLastError: (message?: string) => void;
  pushBackgroundError: (message: string, isOffline: boolean) => void;
  clearBackgroundError: () => void;
  dismissSyncErrors: () => void;
}

const BACKGROUND_ERROR_DEDUP_MS = 5000;

export const useSyncStatusStore = create<SyncStatusState>((set, get) => ({
  pendingWritesCount: 0,
  pendingRequestDocs: 0,
  failedRequestDocs: 0,
  pendingUploads: 0,
  failedUploads: 0,
  isSyncing: false,
  lastError: undefined,
  lastErrorAt: undefined,
  backgroundError: undefined,
  setPendingWritesCount: (count) =>
    set({
      pendingWritesCount: Math.max(0, count),
    }),
  setRequestDocCounts: (pending, failed) =>
    set({
      pendingRequestDocs: Math.max(0, pending),
      failedRequestDocs: Math.max(0, failed),
    }),
  setUploadCounts: (pending, failed) =>
    set({
      pendingUploads: Math.max(0, pending),
      failedUploads: Math.max(0, failed),
    }),
  setSyncing: (isSyncing) => set({ isSyncing }),
  setLastError: (message) =>
    set({
      lastError: message,
      lastErrorAt: message ? Date.now() : undefined,
    }),
  pushBackgroundError: (message, isOffline) => {
    const now = Date.now();
    const last = get().backgroundError;
    if (last && last.message === message && now - last.timestamp < BACKGROUND_ERROR_DEDUP_MS) {
      return;
    }
    set({
      backgroundError: {
        message,
        isOffline,
        timestamp: now,
      },
    });
  },
  clearBackgroundError: () => set({ backgroundError: undefined }),
  dismissSyncErrors: () =>
    set({
      lastError: undefined,
      lastErrorAt: undefined,
      backgroundError: undefined,
    }),
}));
