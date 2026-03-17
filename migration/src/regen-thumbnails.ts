#!/usr/bin/env tsx
/**
 * Regenerate ALL thumbnails from originals in Firebase Storage.
 * Overwrites existing thumbnails with new quality settings.
 * Skips thumbnail generation for images smaller than the target size.
 *
 * Does NOT need Supabase — works entirely from Firebase.
 *
 * Usage:
 *   npx tsx migration/src/regen-thumbnails.ts --account <UUID> --target production [--dry-run]
 */

import { readFileSync, existsSync } from 'node:fs';
import { unlink } from 'node:fs/promises';
import { resolve, join, extname } from 'node:path';
import { tmpdir } from 'node:os';

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

interface ThumbEntry {
  docRef: admin.firestore.DocumentReference;
  field: string;
  index: number;
  originalGsUrl: string;
}

/** Collect all gs:// image URLs that have (or should have) thumbnails. */
async function collectImageUrls(
  db: admin.firestore.Firestore,
  collectionPath: string,
  imageFields: string[]
): Promise<ThumbEntry[]> {
  const results: ThumbEntry[] = [];
  const snap = await db.collection(collectionPath).get();

  for (const doc of snap.docs) {
    const data = doc.data();
    for (const field of imageFields) {
      const value = data[field];
      if (!Array.isArray(value)) continue;
      for (let i = 0; i < value.length; i++) {
        const img = value[i];
        if (!img || typeof img !== 'object') continue;
        const url = img.url;
        if (typeof url === 'string' && url.startsWith('gs://')) {
          results.push({ docRef: doc.ref, field, index: i, originalGsUrl: url });
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

  console.log(`\n=== Regenerate Thumbnails ===`);
  console.log(`Account: ${accountId}`);
  console.log(`Target: ${target}${dryRun ? ' (dry-run)' : ''}\n`);

  // 1. Collect all image URLs from Firestore
  console.log('1. Scanning Firestore for image URLs...');
  const collections = [
    { path: `accounts/${accountId}/items`, fields: ['images'] },
    { path: `accounts/${accountId}/transactions`, fields: ['receiptImages', 'otherImages', 'transactionImages'] },
    { path: `accounts/${accountId}/spaces`, fields: ['images'] },
  ];

  const allEntries: ThumbEntry[] = [];
  for (const { path, fields } of collections) {
    const entries = await collectImageUrls(db, path, fields);
    if (entries.length > 0) console.log(`   ${path}: ${entries.length} images`);
    allEntries.push(...entries);
  }

  // Dedupe by original URL
  const byOriginal = new Map<string, ThumbEntry[]>();
  for (const entry of allEntries) {
    if (!byOriginal.has(entry.originalGsUrl)) byOriginal.set(entry.originalGsUrl, []);
    byOriginal.get(entry.originalGsUrl)!.push(entry);
  }
  console.log(`   Total images: ${allEntries.length}, Unique originals: ${byOriginal.size}`);

  // 2. Download each original, generate thumbnails, upload
  console.log('\n2. Regenerating thumbnails...');
  // Maps originalGsUrl → { sm: gsUrl, md: gsUrl } (null if skipped for small images)
  const thumbResults = new Map<string, { sm: string | null; md: string | null }>();
  let generated = 0;
  let skippedSmall = 0;
  let failed = 0;

  const entries = Array.from(byOriginal.keys());
  for (let batch = 0; batch < entries.length; batch += CONCURRENCY) {
    const chunk = entries.slice(batch, batch + CONCURRENCY);
    await Promise.allSettled(chunk.map(async (gsUrl) => {
      const prefix = `gs://${bucket.name}/`;
      if (!gsUrl.startsWith(prefix)) return;
      const storagePath = gsUrl.slice(prefix.length);
      const ext = extname(storagePath);
      const base = storagePath.slice(0, -ext.length);

      const tmpPath = join(tmpdir(), `ledger-regen-${Date.now()}-${Math.random().toString(36).slice(2)}`);
      try {
        await bucket.file(storagePath).download({ destination: tmpPath });
      } catch (err) {
        console.warn(`   [warn] Download failed: ${storagePath}: ${err instanceof Error ? err.message : err}`);
        failed++;
        return;
      }

      const result: { sm: string | null; md: string | null } = { sm: null, md: null };

      try {
        const metadata = await sharp(tmpPath).metadata();
        const longestSide = Math.max(metadata.width ?? 0, metadata.height ?? 0);

        for (const size of THUMBNAIL_SIZES) {
          const key = size.suffix === '_sm' ? 'sm' : 'md';

          // Skip if source is already smaller than target
          if (longestSide <= size.maxDimension) {
            skippedSmall++;
            continue;
          }

          const thumbStoragePath = `${base}${size.suffix}.jpg`;
          const thumbGsUrl = `gs://${bucket.name}/${thumbStoragePath}`;

          if (dryRun) {
            result[key] = thumbGsUrl;
            generated++;
            continue;
          }

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

          result[key] = thumbGsUrl;
          generated++;
        }
      } finally {
        await unlink(tmpPath).catch(() => {});
      }

      thumbResults.set(gsUrl, result);
    }));

    if ((batch + CONCURRENCY) % 50 === 0 || batch + CONCURRENCY >= entries.length) {
      console.log(`   Processed ${Math.min(batch + CONCURRENCY, entries.length)} / ${entries.length}`);
    }
  }

  console.log(`   Generated: ${generated}, Skipped (small): ${skippedSmall}, Failed: ${failed}`);

  // 3. Patch Firestore docs
  console.log('\n3. Patching Firestore docs...');
  const patchesByDoc = new Map<string, {
    docRef: admin.firestore.DocumentReference;
    updates: Array<{ field: string; index: number; sm: string | null; md: string | null }>;
  }>();

  for (const entry of allEntries) {
    const result = thumbResults.get(entry.originalGsUrl);
    if (!result) continue;

    const key = entry.docRef.path;
    if (!patchesByDoc.has(key)) {
      patchesByDoc.set(key, { docRef: entry.docRef, updates: [] });
    }
    patchesByDoc.get(key)!.updates.push({
      field: entry.field,
      index: entry.index,
      sm: result.sm,
      md: result.md,
    });
  }

  let patched = 0;
  for (const [, { docRef, updates }] of patchesByDoc) {
    const snap = await docRef.get();
    if (!snap.exists) continue;
    const data = snap.data()!;

    for (const { field, index, sm, md } of updates) {
      const arr = data[field];
      if (!Array.isArray(arr) || !arr[index]) continue;
      // Set to gs:// URL or null if image was too small for that size
      arr[index].thumbnailUrlSm = sm ?? null;
      arr[index].thumbnailUrlMd = md ?? null;
    }

    if (dryRun) {
      console.log(`   [dry-run] Would patch ${docRef.path} (${updates.length} images)`);
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
  console.error('Regen failed:', err);
  process.exit(1);
});
