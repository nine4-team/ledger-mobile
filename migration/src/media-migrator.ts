/**
 * Downloads media files from Supabase Storage and uploads them to Firebase Storage,
 * then patches the Firestore document URL fields from offline:// to the real Firebase URL.
 */
import { createWriteStream } from 'node:fs';
import { mkdir, unlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pipeline } from 'node:stream/promises';
import admin from 'firebase-admin';
import type { Bucket } from '@google-cloud/storage';
import type { MediaRef, FirestoreDoc } from './types.js';

const CONCURRENCY = 5;

interface MediaMigrationResult {
  uploaded: number;
  skipped: number;
  failed: number;
  errors: Array<{ mediaId: string; supabaseUrl: string; error: string }>;
}

async function downloadToTemp(url: string): Promise<string> {
  const tmpPath = join(tmpdir(), `ledger-media-${Date.now()}-${Math.random().toString(36).slice(2)}`);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} downloading ${url}`);
  if (!res.body) throw new Error(`No body for ${url}`);
  const writeStream = createWriteStream(tmpPath);
  await pipeline(res.body as unknown as NodeJS.ReadableStream, writeStream);
  return tmpPath;
}

async function uploadToFirebaseStorage(
  bucket: Bucket,
  localPath: string,
  destPath: string,
  contentType: string | null
): Promise<string> {
  const options = {
    destination: destPath,
    ...(contentType ? { metadata: { contentType } } : {}),
  };
  await bucket.upload(localPath, options);
  // Return gs:// URL — Firebase iOS SDK reads these natively via Storage.storage().reference(forURL:)
  return `gs://${bucket.name}/${destPath}`;
}

/**
 * Processes media in batches with bounded concurrency.
 */
async function runWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T) => Promise<R>
): Promise<PromiseSettledResult<R>[]> {
  const results: PromiseSettledResult<R>[] = [];
  for (let i = 0; i < items.length; i += concurrency) {
    const batch = items.slice(i, i + concurrency);
    // eslint-disable-next-line no-await-in-loop
    const settled = await Promise.allSettled(batch.map(fn));
    results.push(...settled);
  }
  return results;
}

/**
 * Migrate all media refs from Supabase Storage to Firebase Storage.
 * Updates documents in-place: replaces offline:// URLs with real Firebase Storage URLs.
 */
export async function migrateMedia(
  mediaRefs: MediaRef[],
  documents: FirestoreDoc[],
  storageBucket: Bucket,
  accountId: string,
  options: { dryRun?: boolean } = {}
): Promise<MediaMigrationResult> {
  if (options.dryRun) {
    console.log(`  [dry-run] Would migrate ${mediaRefs.length} media file(s).`);
    return { uploaded: mediaRefs.length, skipped: 0, failed: 0, errors: [] };
  }

  const tmpDir = join(tmpdir(), `ledger-migration-${accountId}`);
  await mkdir(tmpDir, { recursive: true });

  // Build a lookup from offline://mediaId → firebase URL (populated as we upload)
  const mediaIdToFirebaseUrl = new Map<string, string>();
  const uploadErrors: MediaMigrationResult['errors'] = [];

  let uploaded = 0;
  let skipped = 0;

  const results = await runWithConcurrency(mediaRefs, CONCURRENCY, async (ref) => {
    const destPath = `migrated/${accountId}/${ref.objectPath}`;

    // Check if already uploaded (idempotency)
    const [exists] = await storageBucket.file(destPath).exists();
    if (exists) {
      const gsUrl = `gs://${storageBucket.name}/${destPath}`;
      mediaIdToFirebaseUrl.set(ref.mediaId, gsUrl);
      return { mediaId: ref.mediaId, url: gsUrl, skipped: true };
    }

    const tmpPath = await downloadToTemp(ref.supabaseUrl);
    try {
      const firebaseUrl = await uploadToFirebaseStorage(
        storageBucket,
        tmpPath,
        destPath,
        ref.contentType
      );
      mediaIdToFirebaseUrl.set(ref.mediaId, firebaseUrl);
      return { mediaId: ref.mediaId, url: firebaseUrl, skipped: false };
    } finally {
      await unlink(tmpPath).catch(() => {});
    }
  });

  for (let i = 0; i < results.length; i++) {
    const result = results[i];
    const ref = mediaRefs[i];
    if (result.status === 'fulfilled') {
      if (result.value.skipped) skipped++;
      else uploaded++;
    } else {
      uploadErrors.push({
        mediaId: ref.mediaId,
        supabaseUrl: ref.supabaseUrl,
        error: result.reason instanceof Error ? result.reason.message : String(result.reason),
      });
    }
  }

  // Patch documents: replace offline://mediaId with real Firebase URLs
  patchDocumentUrls(documents, mediaIdToFirebaseUrl);

  return { uploaded, skipped, failed: uploadErrors.length, errors: uploadErrors };
}

/**
 * Walk all document data and replace offline://mediaId references with
 * the real Firebase Storage URLs.
 */
function patchDocumentUrls(
  documents: FirestoreDoc[],
  mediaIdToUrl: Map<string, string>
): void {
  function patchValue(value: unknown): unknown {
    if (typeof value === 'string' && value.startsWith('offline://')) {
      const mediaId = value.slice('offline://'.length);
      return mediaIdToUrl.get(mediaId) ?? value;
    }
    if (Array.isArray(value)) return value.map(patchValue);
    if (value !== null && typeof value === 'object') {
      const out: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
        out[k] = patchValue(v);
      }
      return out;
    }
    return value;
  }

  for (const doc of documents) {
    doc.data = patchValue(doc.data) as Record<string, unknown>;
  }
}
