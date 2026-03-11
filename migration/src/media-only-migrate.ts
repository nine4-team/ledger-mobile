#!/usr/bin/env tsx
/**
 * Targeted media-only migration: uploads media to Firebase Storage and patches
 * ONLY the URL fields in existing Firestore documents.
 *
 * Unlike the full CLI, this does NOT overwrite entire documents — it uses
 * Firestore update() on specific fields, preserving all other data.
 *
 * Usage:
 *   npx tsx migration/src/media-only-migrate.ts --account <UUID> --target production [--dry-run]
 */

import { readFileSync, existsSync } from 'node:fs';
import { writeFile, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';

// Load .env.local and .env
for (const envFile of ['.env.local', '.env']) {
  const envFilePath = resolve(process.cwd(), envFile);
  if (!existsSync(envFilePath)) continue;
  const lines = readFileSync(envFilePath, 'utf8').split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim().replace(/^["']|["']$/g, '');
    if (!(key in process.env)) process.env[key] = value;
  }
}

import admin from 'firebase-admin';
import type { Bucket } from '@google-cloud/storage';
import { createSupabaseClient, readAccount } from './supabase-reader.js';
import { transform } from './transform.js';
import { initFirestore, type WriteTarget } from './firestore-writer.js';
import { migrateMedia } from './media-migrator.js';
import type { MediaRef } from './types.js';

function parseArgs(argv: string[]) {
  const args = argv.slice(2);
  const flags = new Map<string, string | true>();
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = args[i + 1];
    if (!next || next.startsWith('--')) {
      flags.set(key, true);
    } else {
      flags.set(key, next);
      i++;
    }
  }

  const accountId = flags.get('account');
  if (typeof accountId !== 'string' || accountId.length === 0) {
    console.error('Error: --account <UUID> is required.');
    process.exit(1);
  }

  const targetArg = flags.get('target');
  const target: WriteTarget = targetArg === 'production' ? 'production' : 'emulator';
  const dryRun = flags.has('dry-run');
  const limit = flags.get('limit');
  const limitNum = typeof limit === 'string' ? parseInt(limit, 10) : 0;

  return { accountId, target, dryRun, limit: limitNum };
}

/**
 * Scan ALL documents in known collections for offline:// URLs and patch them.
 * Uses update() instead of set() to avoid overwriting entire documents.
 *
 * This approach scans Firestore directly rather than relying on mediaRef owner paths,
 * because multiple items can share the same image (same offline:// mediaId) but the
 * transform only records one owner per mediaRef.
 */
async function patchAllOfflineUrls(
  db: admin.firestore.Firestore,
  accountId: string,
  mediaIdToUrl: Map<string, string>,
  options: { dryRun?: boolean } = {}
): Promise<{ patched: number; skipped: number; failed: number }> {
  let patched = 0;
  let skipped = 0;
  let failed = 0;

  // Collections and their URL-bearing fields
  const collectionsToScan: Array<{ path: string; urlFields: string[] }> = [
    { path: `accounts/${accountId}/items`, urlFields: ['images'] },
    { path: `accounts/${accountId}/transactions`, urlFields: ['receiptImages', 'otherImages', 'transactionImages'] },
    { path: `accounts/${accountId}/spaces`, urlFields: ['images'] },
    { path: `accounts/${accountId}/projects`, urlFields: ['mainImage', 'logo'] },
  ];

  for (const { path: collectionPath, urlFields } of collectionsToScan) {
    const snap = await db.collection(collectionPath).get();

    for (const doc of snap.docs) {
      const data = doc.data();
      const updates: Record<string, unknown> = {};

      for (const field of urlFields) {
        const fieldValue = data[field];
        if (fieldValue === undefined || fieldValue === null) continue;

        if (Array.isArray(fieldValue)) {
          let changed = false;
          const patchedArray = fieldValue.map((item: Record<string, unknown>) => {
            if (typeof item?.url === 'string' && item.url.startsWith('offline://')) {
              const mediaId = item.url.slice('offline://'.length);
              const newUrl = mediaIdToUrl.get(mediaId);
              if (newUrl) {
                changed = true;
                return { ...item, url: newUrl };
              }
            }
            return item;
          });
          if (changed) {
            updates[field] = patchedArray;
          }
        } else if (
          typeof fieldValue === 'object' &&
          typeof (fieldValue as Record<string, unknown>).url === 'string'
        ) {
          const obj = fieldValue as Record<string, unknown>;
          if ((obj.url as string).startsWith('offline://')) {
            const mediaId = (obj.url as string).slice('offline://'.length);
            const newUrl = mediaIdToUrl.get(mediaId);
            if (newUrl) {
              updates[field] = { ...obj, url: newUrl };
            }
          }
        } else if (typeof fieldValue === 'string' && fieldValue.startsWith('offline://')) {
          const mediaId = fieldValue.slice('offline://'.length);
          const newUrl = mediaIdToUrl.get(mediaId);
          if (newUrl) {
            updates[field] = newUrl;
          }
        }
      }

      if (Object.keys(updates).length > 0) {
        if (options.dryRun) {
          console.log(`  [dry-run] Would patch ${doc.ref.path} (${Object.keys(updates).length} fields)`);
          patched++;
        } else {
          try {
            await doc.ref.update(updates);
            patched++;
          } catch (err) {
            console.error(`  [error] Failed to patch ${doc.ref.path}:`, err instanceof Error ? err.message : err);
            failed++;
          }
        }
      } else {
        skipped++;
      }
    }
  }

  // Also check profile doc
  try {
    const profileRef = db.doc(`accounts/${accountId}/profile/${accountId}`);
    const profileSnap = await profileRef.get();
    if (profileSnap.exists) {
      const data = profileSnap.data()!;
      const updates: Record<string, unknown> = {};
      for (const field of ['businessLogo']) {
        const val = data[field] as Record<string, unknown> | undefined;
        if (val?.url && typeof val.url === 'string' && val.url.startsWith('offline://')) {
          const mediaId = val.url.slice('offline://'.length);
          const newUrl = mediaIdToUrl.get(mediaId);
          if (newUrl) updates[field] = { ...val, url: newUrl };
        }
      }
      if (Object.keys(updates).length > 0) {
        if (!options.dryRun) await profileRef.update(updates);
        patched++;
      }
    }
  } catch {}

  return { patched, skipped, failed };
}

async function main() {
  const { accountId, target, dryRun, limit } = parseArgs(process.argv);

  const supabaseUrl = process.env.VITE_SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !supabaseKey) {
    console.error('Error: VITE_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set.');
    process.exit(1);
  }

  const projectId = process.env.FIREBASE_PROJECT_ID ?? 'ledger-nine4';
  const storageBucketName =
    process.env.FIREBASE_STORAGE_BUCKET ?? `${projectId}.firebasestorage.app`;

  if (target === 'emulator') {
    process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8181';
    process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= 'localhost:9199';
  }

  console.log(`\n=== Media-Only Migration ===`);
  console.log(`Account:  ${accountId}`);
  console.log(`Target:   ${target}${dryRun ? ' (dry-run)' : ''}`);
  console.log('');

  // 1. Read from Supabase + Transform (to get mediaRefs)
  console.log('Step 1/3 — Reading from Supabase & transforming...');
  const supabase = createSupabaseClient(supabaseUrl, supabaseKey);
  const exportData = await readAccount(supabase, accountId);
  const result = transform(exportData);
  let mediaRefs = result.mediaRefs;
  if (limit > 0) {
    mediaRefs = mediaRefs.slice(0, limit);
    console.log(`  Media refs: ${result.mediaRefs.length} (limited to ${limit})`);
  } else {
    console.log(`  Media refs: ${result.mediaRefs.length}`);
  }

  if (mediaRefs.length === 0) {
    console.log('\nNo media refs found. Nothing to do.');
    return;
  }

  // 2. Upload media to Firebase Storage
  console.log('\nStep 2/3 — Uploading media to Firebase Storage...');
  const db = initFirestore(target, projectId);
  const storage = admin.storage();
  const bucket = storage.bucket(storageBucketName) as unknown as Bucket;

  const mediaResult = await migrateMedia(
    mediaRefs,
    result.documents, // passed for in-memory patching (we won't use the patched docs)
    bucket,
    accountId,
    { dryRun }
  );
  console.log(`  Uploaded: ${mediaResult.uploaded}, Skipped: ${mediaResult.skipped}, Failed: ${mediaResult.failed}`);

  // 3. Patch only URL fields in existing Firestore documents
  // Build the mediaId → gs:// URL map by checking what's in Storage
  console.log('\nStep 3/3 — Patching URL fields in Firestore...');
  const mediaIdToUrl = new Map<string, string>();

  for (const ref of mediaRefs) {
    const destPath = `migrated/${accountId}/${ref.objectPath}`;
    const gsUrl = `gs://${bucket.name}/${destPath}`;

    if (dryRun) {
      mediaIdToUrl.set(ref.mediaId, gsUrl);
      continue;
    }

    // Verify file exists in Storage before patching
    try {
      const [exists] = await bucket.file(destPath).exists();
      if (exists) {
        mediaIdToUrl.set(ref.mediaId, gsUrl);
      } else {
        console.warn(`  [warn] File not in Storage: ${destPath}`);
      }
    } catch (err) {
      console.warn(`  [warn] Could not check ${destPath}:`, err instanceof Error ? err.message : err);
    }
  }

  console.log(`  Resolved ${mediaIdToUrl.size} / ${mediaRefs.length} media URLs`);

  const patchResult = await patchAllOfflineUrls(db, accountId, mediaIdToUrl, { dryRun });
  console.log(`  Patched: ${patchResult.patched}, Skipped: ${patchResult.skipped}, Failed: ${patchResult.failed}`);

  // Report
  const report = {
    meta: { accountId, target, dryRun, migratedAt: new Date().toISOString(), type: 'media-only' },
    media: { uploaded: mediaResult.uploaded, skipped: mediaResult.skipped, failed: mediaResult.failed },
    patch: patchResult,
    mediaErrors: mediaResult.errors,
  };

  const outDir = resolve(process.cwd(), 'migration', 'out', accountId);
  await mkdir(outDir, { recursive: true });
  const reportPath = join(outDir, 'media-migration-report.json');
  await writeFile(reportPath, JSON.stringify(report, null, 2), 'utf8');
  console.log(`\nReport written to: ${reportPath}`);
  console.log('\n=== Done ===\n');
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
