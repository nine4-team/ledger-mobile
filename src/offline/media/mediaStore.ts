import AsyncStorage from '@react-native-async-storage/async-storage';
let FileSystem: typeof import('expo-file-system') | null = null;
try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  FileSystem = require('expo-file-system');
} catch {
  FileSystem = null;
}
import { create } from 'zustand';

import { useSyncStatusStore } from '../../sync/syncStatusStore';
import type { AttachmentRef, MediaRecord, MediaStatus, UploadJob } from './types';

const STORAGE_KEY = 'offline/media-cache';
const MEDIA_CACHE_DIR = FileSystem?.cacheDirectory
  ? `${FileSystem.cacheDirectory}media-cache/`
  : null;

type UploadHandler = (record: MediaRecord, job: UploadJob) => Promise<{ remoteUrl: string }>;

type MediaStoreState = {
  isHydrated: boolean;
  records: Record<string, MediaRecord>;
  jobs: Record<string, UploadJob>;
  setHydrated: (value: boolean) => void;
  setState: (records: Record<string, MediaRecord>, jobs: Record<string, UploadJob>) => void;
  upsertRecord: (record: MediaRecord) => void;
  updateRecord: (id: string, updates: Partial<MediaRecord>) => void;
  removeRecord: (id: string) => void;
  upsertJob: (job: UploadJob) => void;
  updateJob: (id: string, updates: Partial<UploadJob>) => void;
  removeJob: (id: string) => void;
};

const useMediaStore = create<MediaStoreState>((set) => ({
  isHydrated: false,
  records: {},
  jobs: {},
  setHydrated: (value) => set({ isHydrated: value }),
  setState: (records, jobs) => set({ records, jobs }),
  upsertRecord: (record) =>
    set((state) => ({
      records: {
        ...state.records,
        [record.id]: record,
      },
    })),
  updateRecord: (id, updates) =>
    set((state) => ({
      records: {
        ...state.records,
        [id]: {
          ...state.records[id],
          ...updates,
          updatedAt: Date.now(),
        },
      },
    })),
  removeRecord: (id) =>
    set((state) => {
      const next = { ...state.records };
      delete next[id];
      return { records: next };
    }),
  upsertJob: (job) =>
    set((state) => ({
      jobs: {
        ...state.jobs,
        [job.id]: job,
      },
    })),
  updateJob: (id, updates) =>
    set((state) => ({
      jobs: {
        ...state.jobs,
        [id]: {
          ...state.jobs[id],
          ...updates,
          updatedAt: Date.now(),
        },
      },
    })),
  removeJob: (id) =>
    set((state) => {
      const next = { ...state.jobs };
      delete next[id];
      return { jobs: next };
    }),
}));

let uploadHandler: UploadHandler | null = null;

function updateSyncCounts() {
  const { jobs } = useMediaStore.getState();
  let pending = 0;
  let failed = 0;
  Object.values(jobs).forEach((job) => {
    if (job.status === 'failed') {
      failed += 1;
      return;
    }
    if (job.status === 'queued' || job.status === 'uploading') {
      pending += 1;
    }
  });
  useSyncStatusStore.getState().setUploadCounts(pending, failed);
}

async function persistState() {
  const { records, jobs } = useMediaStore.getState();
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify({ records, jobs }));
  updateSyncCounts();
}

async function ensureMediaCacheDir() {
  if (!MEDIA_CACHE_DIR) {
    return;
  }
  if (!FileSystem) {
    return;
  }
  const info = await FileSystem.getInfoAsync(MEDIA_CACHE_DIR);
  if (!info.exists) {
    await FileSystem.makeDirectoryAsync(MEDIA_CACHE_DIR, { intermediates: true });
  }
}

export async function hydrateMediaStore(): Promise<void> {
  const stored = await AsyncStorage.getItem(STORAGE_KEY);
  if (!stored) {
    useMediaStore.getState().setHydrated(true);
    return;
  }
  let parsed: { records?: Record<string, MediaRecord>; jobs?: Record<string, UploadJob> };
  try {
    parsed = JSON.parse(stored) as {
      records?: Record<string, MediaRecord>;
      jobs?: Record<string, UploadJob>;
    };
  } catch {
    await AsyncStorage.removeItem(STORAGE_KEY);
    useMediaStore.getState().setHydrated(true);
    return;
  }
  useMediaStore
    .getState()
    .setState(parsed.records ?? {}, parsed.jobs ?? {});
  useMediaStore.getState().setHydrated(true);
  updateSyncCounts();
}

function createMediaId() {
  return `media_${Date.now()}_${Math.random().toString(36).slice(2)}`;
}

export async function saveLocalMedia(params: {
  localUri: string;
  size?: number;
  mimeType?: string;
  ownerScope?: string;
  persistCopy?: boolean;
}): Promise<{ mediaId: string; attachmentRef: AttachmentRef }> {
  const mediaId = createMediaId();
  let storedUri = params.localUri;
  if (params.persistCopy !== false && MEDIA_CACHE_DIR && FileSystem) {
    await ensureMediaCacheDir();
    const extension = params.localUri.split('.').pop();
    const fileName = extension ? `${mediaId}.${extension}` : mediaId;
    const targetUri = `${MEDIA_CACHE_DIR}${fileName}`;
    try {
      await FileSystem.copyAsync({ from: params.localUri, to: targetUri });
      storedUri = targetUri;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to cache media.';
      useSyncStatusStore.getState().setLastError(message);
    }
  }

  const now = Date.now();
  const record: MediaRecord = {
    id: mediaId,
    localUri: storedUri,
    createdAt: now,
    updatedAt: now,
    size: params.size,
    mimeType: params.mimeType,
    ownerScope: params.ownerScope,
    status: 'local_only',
  };
  useMediaStore.getState().upsertRecord(record);
  await persistState();

  return {
    mediaId,
    attachmentRef: {
      url: `offline://${mediaId}`,
      kind: params.mimeType?.includes('pdf')
        ? 'pdf'
        : params.mimeType?.startsWith('image')
          ? 'image'
          : 'file',
      contentType: params.mimeType,
    },
  };
}

export async function enqueueUpload(params: {
  mediaId: string;
  destinationPath?: string;
  idempotencyKey?: string;
}): Promise<UploadJob> {
  const now = Date.now();
  const job: UploadJob = {
    id: `upload_${params.mediaId}_${now}`,
    mediaId: params.mediaId,
    idempotencyKey: params.idempotencyKey ?? `upload_${params.mediaId}`,
    status: 'queued',
    createdAt: now,
    updatedAt: now,
    attemptCount: 0,
    destinationPath: params.destinationPath,
  };
  useMediaStore.getState().upsertJob(job);
  useMediaStore.getState().updateRecord(params.mediaId, { status: 'local_only' });
  await persistState();
  return job;
}

export function registerUploadHandler(handler: UploadHandler): void {
  uploadHandler = handler;
}

export async function processUploadQueue(): Promise<void> {
  if (!uploadHandler) {
    return;
  }
  const { jobs, records } = useMediaStore.getState();
  const queue = Object.values(jobs).filter(
    (job) => job.status === 'queued' || job.status === 'failed'
  );

  for (const job of queue) {
    const record = records[job.mediaId];
    if (!record) {
      useMediaStore.getState().updateJob(job.id, {
        status: 'failed',
        lastError: 'Missing media record.',
        attemptCount: job.attemptCount + 1,
      });
      continue;
    }

    useMediaStore.getState().updateJob(job.id, { status: 'uploading' });
    useMediaStore.getState().updateRecord(record.id, { status: 'uploading' });
    try {
      const result = await uploadHandler(record, job);
      useMediaStore.getState().updateJob(job.id, { status: 'completed' });
      useMediaStore.getState().updateRecord(record.id, {
        status: 'uploaded',
        remoteUrl: result.remoteUrl,
        lastError: undefined,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Upload failed.';
      useMediaStore.getState().updateJob(job.id, {
        status: 'failed',
        lastError: message,
        attemptCount: job.attemptCount + 1,
      });
      useMediaStore.getState().updateRecord(record.id, {
        status: 'failed',
        lastError: message,
      });
      useSyncStatusStore.getState().pushBackgroundError(message, false);
    }
    await persistState();
  }
}

export async function retryPendingUploads(): Promise<void> {
  await processUploadQueue();
}

export function resolveAttachmentUri(ref: AttachmentRef): string | null {
  if (!ref.url.startsWith('offline://')) {
    return ref.url;
  }
  const mediaId = ref.url.replace('offline://', '');
  const record = useMediaStore.getState().records[mediaId];
  if (!record) return null;
  return record.localUri ?? null;
}

export function resolveAttachmentState(ref: AttachmentRef): {
  status: MediaStatus;
  record?: MediaRecord;
} {
  if (!ref.url.startsWith('offline://')) {
    return { status: 'uploaded' };
  }
  const mediaId = ref.url.replace('offline://', '');
  const record = useMediaStore.getState().records[mediaId];
  if (!record) {
    return { status: 'failed' };
  }
  return { status: record.status, record };
}

export async function deleteLocalMediaByUrl(url: string): Promise<void> {
  if (!url.startsWith('offline://')) {
    return;
  }
  const mediaId = url.replace('offline://', '');
  const record = useMediaStore.getState().records[mediaId];
  if (!record) {
    return;
  }
  if (FileSystem && MEDIA_CACHE_DIR && record.localUri?.startsWith(MEDIA_CACHE_DIR)) {
    try {
      await FileSystem.deleteAsync(record.localUri, { idempotent: true });
    } catch {
      // ignore cleanup errors
    }
  }
  useMediaStore.getState().removeRecord(mediaId);
  Object.values(useMediaStore.getState().jobs).forEach((job) => {
    if (job.mediaId === mediaId) {
      useMediaStore.getState().removeJob(job.id);
    }
  });
  await persistState();
}

export async function cleanupOrphanedMedia(referencedMediaIds: string[]): Promise<void> {
  const { records, jobs } = useMediaStore.getState();
  const referenced = new Set(referencedMediaIds);
  const removedRecords: string[] = [];
  Object.values(records).forEach((record) => {
    if (!referenced.has(record.id)) {
      removedRecords.push(record.id);
    }
  });

  for (const recordId of removedRecords) {
    const record = records[recordId];
    if (FileSystem && MEDIA_CACHE_DIR && record?.localUri?.startsWith(MEDIA_CACHE_DIR)) {
      try {
        await FileSystem.deleteAsync(record.localUri, { idempotent: true });
      } catch {
        // ignore cleanup errors
      }
    }
    useMediaStore.getState().removeRecord(recordId);
  }

  Object.values(jobs).forEach((job) => {
    if (removedRecords.includes(job.mediaId)) {
      useMediaStore.getState().removeJob(job.id);
    }
  });
  await persistState();
}

export { useMediaStore };
