import { create } from 'zustand';

export interface OfflineUXState {
  isLoading: boolean;
  loadingMessage?: string;
  isStale: boolean;
  staleMessage?: string;
  queuedWritesCount: number;
  setLoading: (isLoading: boolean, message?: string) => void;
  setStale: (isStale: boolean, message?: string) => void;
  setQueuedWritesCount: (count: number) => void;
  incrementQueuedWrites: (delta?: number) => void;
  reset: () => void;
}

export const useOfflineUXStore = create<OfflineUXState>((set) => ({
  isLoading: false,
  loadingMessage: undefined,
  isStale: false,
  staleMessage: undefined,
  queuedWritesCount: 0,
  setLoading: (isLoading, message) =>
    set({
      isLoading,
      loadingMessage: message,
    }),
  setStale: (isStale, message) =>
    set({
      isStale,
      staleMessage: message,
    }),
  setQueuedWritesCount: (count) =>
    set({
      queuedWritesCount: Math.max(0, count),
    }),
  incrementQueuedWrites: (delta = 1) =>
    set((state) => ({
      queuedWritesCount: Math.max(0, state.queuedWritesCount + delta),
    })),
  reset: () =>
    set({
      isLoading: false,
      loadingMessage: undefined,
      isStale: false,
      staleMessage: undefined,
      queuedWritesCount: 0,
    }),
}));
