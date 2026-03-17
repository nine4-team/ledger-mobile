#!/usr/bin/env tsx
/**
 * Generate missing thumbnails from originals already in Firebase Storage,
 * then patch Firestore docs to replace offline:// thumbnail URLs with gs://.
 *
 * Does NOT need Supabase — works entirely from Firebase.
 *
 * Usage:
 *   npx tsx migration/src/fix-thumbnails.ts --account <UUID> --target production [--dry-run]
 */

import { readFileSync, existsSync } from 'node:fs';
import { unlink } from 'node:fs/promises';
import { resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { join, extname } from 'node:path';

for (const envFile of ['.env.local', '.env']) {
  const p = resolve(process.cwd(), envFile);
  if (!existsSync(p)) continue;
  for (const line of readFileSync(p, 'utf8').split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq === -1) continue;
    const k = t.slice(0, eq).trim();
    const v = t.slice(eq + 1).trim().replace(/^["']|["']$/g, '');
    if (!(k in process.env)) process.env[k] = v;
  }
}

import admin from 'firebase-admin';
import sharp from 'sharp';
import type { Bucket } from '@google-cloud/storage';
import { initFirestore, type WriteTarget } from './firestore-writer.js';

const THUMBNAIL_SIZES = [
  { suffix: '_sm', maxDimension: 300, quality: 100 },
  { suffix: '_md', maxDimension: 800, quality: 100 },
] as const;

const CONCURRENCY = 5;

function parseArgs(argv: string[]) {
  const args = argv.slice(2);
  const flags = new Map<string, string | true>();
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = args[i + 1];
    if (!next || next.startsWith('--')) { flags.set(key, true); }
    else { flags.set(key, next); i++; }
  }

  const accountId = flags.get('account');
  if (typeof accountId !== 'string') {
    console.error('Error: --account <UUID> is required.');
    process.exit(1);
  }

  const targetArg = flags.get('target');
  const target: WriteTarget = targetArg === 'production' ? 'production' : 'emulator';
  const dryRun = flags.has('dry-run');
  return { accountId, target, dryRun };
}

/**
 * Scan all docs in a collection for offline:// thumbnail URLs.
 * Returns a map of offline://mediaId → { docRef, field, index, originalGsUrl }.
 */
async function findOfflineThumbnails(
  db: admin.firestore.Firestore,
  collectionPath: string,
  imageFields: string[]
): Promise<Array<{
  docRef: admin.firestore.DocumentReference;
  field: string;
  index: number;
  thumbField: string;
  offlineUrl: string;
  originalGsUrl: string;
}>> {
  const results: Array<{
    docRef: admin.firestore.DocumentReference;
    field: string;
    index: number;
    thumbField: string;
    offlineUrl: string;
    originalGsUrl: string;
  }> = [];

  const snap = await db.collection(collectionPath).get();
  for (const doc of snap.docs) {
    const data = doc.data();
    for (const field of imageFields) {
      const value = data[field];
      if (!Array.isArray(value)) continue;

      for (let i = 0; i < value.length; i++) {
        const img = value[i];
        if (!img || typeof img !== 'object') continue;
        const originalUrl = img.url;
        if (typeof originalUrl !== 'string' || !originalUrl.startsWith('gs://')) continue;

        for (const thumbField of ['thumbnailUrlSm', 'thumbnailUrlMd']) {
          const thumbUrl = img[thumbField];
          if (typeof thumbUrl === 'string' && thumbUrl.startsWith('offline://')) {
            results.push({
              docRef: doc.ref,
              field,
              index: i,
              thumbField,
              offlineUrl: thumbUrl,
              originalGsUrl: originalUrl,
            });
          }
        }
      }
    }
  }

  return results;
}

async function main() {
  const { accountId, target, dryRun } = parseArgs(process.argv);
  const projectId = process.env.FIREBASE_PROJECT_ID ?? 'ledger-nine4';
  const storageBucketName = process.env.FIREBASE_STORAGE_BUCKET ?? `${projectId}.firebasestorage.app`;

  if (target === 'emulator') {
    process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8181';
    process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= 'localhost:9199';
  }

  const db = initFirestore(target, projectId);
  const storage = admin.storage();
  const bucket = storage.bucket(storageBucketName) as unknown as Bucket;

  console.log(`\n=== Fix Thumbnails ===`);
  console.log(`Account: ${accountId}`);
  console.log(`Target: ${target}${dryRun ? ' (dry-run)' : ''}\n`);

  // 1. Find all offline:// thumbnail URLs
  console.log('1. Scanning Firestore for offline:// thumbnail URLs...');
  const collections = [
    { path: `accounts/${accountId}/items`, fields: ['images'] },
    { path: `accounts/${accountId}/transactions`, fields: ['receiptImages', 'otherImages', 'transactionImages'] },
    { path: `accounts/${accountId}/spaces`, fields: ['images'] },
  ];

  const allMissing: Awaited<ReturnType<typeof findOfflineThumbnails>> = [];
  for (const { path, fields } of collections) {
    const missing = await findOfflineThumbnails(db, path, fields);
    if (missing.length > 0) {
      console.log(`   ${path}: ${missing.length} offline thumbnail URLs`);
    }
    allMissing.push(...missing);
  }
  console.log(`   Total: ${allMissing.length} offline thumbnail URLs`);

  if (allMissing.length === 0) {
    console.log('\nAll thumbnails already resolved. Nothing to do.');
    return;
  }

  // 2. Group by original gs:// URL to avoid downloading the same file twice
  const byOriginal = new Map<string, typeof allMissing>();
  for (const entry of allMissing) {
    const key = entry.originalGsUrl;
    if (!byOriginal.has(key)) byOriginal.set(key, []);
    byOriginal.get(key)!.push(entry);
  }
  console.log(`   Unique originals to process: ${byOriginal.size}`);

  // 3. Generate thumbnails and build URL map
  console.log('\n2. Generating thumbnails from Firebase Storage originals...');
  const thumbUrlMap = new Map<string, string>(); // offline://url → gs://url
  let generated = 0;
  let failed = 0;

  const entries = Array.from(byOriginal.entries());
  for (let batch = 0; batch < entries.length; batch += CONCURRENCY) {
    const chunk = entries.slice(batch, batch + CONCURRENCY);
    await Promise.allSettled(chunk.map(async ([gsUrl, refs]) => {
      // Extract Storage path from gs://bucket/path
      const prefix = `gs://${bucket.name}/`;
      if (!gsUrl.startsWith(prefix)) return;
      const storagePath = gsUrl.slice(prefix.length);

      const ext = extname(storagePath);
      const base = storagePath.slice(0, -ext.length);

      // Download original from Firebase Storage
      const tmpPath = join(tmpdir(), `ledger-thumb-${Date.now()}-${Math.random().toString(36).slice(2)}`);
      try {
        await bucket.file(storagePath).download({ destination: tmpPath });
      } catch (err) {
        console.warn(`   [warn] Failed to download ${storagePath}: ${err instanceof Error ? err.message : err}`);
        failed += refs.length;
        return;
      }

      try {
        for (const size of THUMBNAIL_SIZES) {
          const thumbStoragePath = `${base}${size.suffix}.jpg`;
          const thumbGsUrl = `gs://${bucket.name}/${thumbStoragePath}`;

          // Check if already exists
          const [thumbExists] = await bucket.file(thumbStoragePath).exists();
          if (thumbExists) {
            // Map all offline:// refs that point to this thumbnail
            for (const ref of refs) {
              if (ref.thumbField === 'thumbnailUrlSm' && size.suffix === '_sm') {
                thumbUrlMap.set(ref.offlineUrl, thumbGsUrl);
              } else if (ref.thumbField === 'thumbnailUrlMd' && size.suffix === '_md') {
                thumbUrlMap.set(ref.offlineUrl, thumbGsUrl);
              }
            }
            continue;
          }

          if (dryRun) {
            for (const ref of refs) {
              if (ref.thumbField === 'thumbnailUrlSm' && size.suffix === '_sm') {
                thumbUrlMap.set(ref.offlineUrl, thumbGsUrl);
              } else if (ref.thumbField === 'thumbnailUrlMd' && size.suffix === '_md') {
                thumbUrlMap.set(ref.offlineUrl, thumbGsUrl);
              }
            }
            continue;
          }

          // Generate thumbnail
          const thumbLocalPath = `${tmpPath}${size.suffix}.jpg`;
          await sharp(tmpPath)
            .resize(size.maxDimension, size.maxDimension, { fit: 'inside', withoutEnlargement: true })
            .jpeg({ quality: size.quality })
            .toFile(thumbLocalPath);

          await bucket.upload(thumbLocalPath, {
            destination: thumbStoragePath,
            metadata: { contentType: 'image/jpeg' },
          });
          await unlink(thumbLocalPath).catch(() => {});

          // Map all offline:// refs that point to this thumbnail
          for (const ref of refs) {
            if (ref.thumbField === 'thumbnailUrlSm' && size.suffix === '_sm') {
              thumbUrlMap.set(ref.offlineUrl, thumbGsUrl);
            } else if (ref.thumbField === 'thumbnailUrlMd' && size.suffix === '_md') {
              thumbUrlMap.set(ref.offlineUrl, thumbGsUrl);
            }
          }
          generated++;
        }
      } finally {
        await unlink(tmpPath).catch(() => {});
      }
    }));

    if ((batch + CONCURRENCY) % 50 === 0 || batch + CONCURRENCY >= entries.length) {
      console.log(`   Processed ${Math.min(batch + CONCURRENCY, entries.length)} / ${entries.length} originals`);
    }
  }

  console.log(`   Generated: ${generated}, Failed: ${failed}`);
  console.log(`   Resolved ${thumbUrlMap.size} / ${allMissing.length} offline URLs`);

  // 4. Patch Firestore docs
  console.log('\n3. Patching Firestore docs...');
  // Group patches by doc
  const patchesByDoc = new Map<string, { docRef: admin.firestore.DocumentReference; updates: Array<{ field: string; index: number; thumbField: string; newUrl: string }> }>();

  for (const entry of allMissing) {
    const newUrl = thumbUrlMap.get(entry.offlineUrl);
    if (!newUrl) continue;

    const key = entry.docRef.path;
    if (!patchesByDoc.has(key)) {
      patchesByDoc.set(key, { docRef: entry.docRef, updates: [] });
    }
    patchesByDoc.get(key)!.updates.push({
      field: entry.field,
      index: entry.index,
      thumbField: entry.thumbField,
      newUrl,
    });
  }

  let patched = 0;
  for (const [, { docRef, updates }] of patchesByDoc) {
    // Read current doc, apply patches, write back
    const snap = await docRef.get();
    if (!snap.exists) continue;
    const data = snap.data()!;

    for (const { field, index, thumbField, newUrl } of updates) {
      const arr = data[field];
      if (Array.isArray(arr) && arr[index]) {
        arr[index][thumbField] = newUrl;
      }
    }

    if (dryRun) {
      console.log(`   [dry-run] Would patch ${docRef.path} (${updates.length} thumb URLs)`);
    } else {
      const fieldUpdates: Record<string, unknown> = {};
      for (const { field } of updates) {
        fieldUpdates[field] = data[field];
      }
      await docRef.update(fieldUpdates);
    }
    patched++;
  }

  console.log(`   Patched ${patched} docs`);
  console.log(`\n=== Done ===\n`);
}

main().catch((err) => {
  console.error('Fix failed:', err);
  process.exit(1);
});
