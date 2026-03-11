#!/usr/bin/env tsx
/**
 * Ledger Migration CLI
 *
 * Migrates one account's data from Supabase (web) → Firestore (mobile).
 *
 * Usage:
 *   npx tsx migration/src/cli.ts --account <UUID> [options]
 *
 * Options:
 *   --account <UUID>      Supabase account ID to migrate (required)
 *   --target <emulator|production>  Where to write Firestore docs (default: emulator)
 *   --dry-run             Transform only — print report without writing anything
 *   --skip-media          Skip Supabase Storage → Firebase Storage migration
 *   --skip-backfill       Skip budgetSummary recalculation after writes
 *
 * Environment (from .env.local or env):
 *   VITE_SUPABASE_URL           Supabase project URL
 *   SUPABASE_SERVICE_ROLE_KEY   Supabase service role key
 *   FIREBASE_PROJECT_ID         Firebase project ID (default: ledger-nine4)
 *   FIREBASE_STORAGE_BUCKET     Firebase Storage bucket (default: <projectId>.appspot.com)
 *   FIRESTORE_EMULATOR_HOST     Required when --target emulator (default: localhost:8181)
 *   GOOGLE_APPLICATION_CREDENTIALS  Required when --target production
 */

import { readFileSync, existsSync } from 'node:fs';
import { writeFile, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';

// Load .env.local and .env before anything else (.env.local takes precedence)
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

import { createSupabaseClient, readAccount } from './supabase-reader.js';
import { transform } from './transform.js';
import { initFirestore, writeDocs, type WriteTarget } from './firestore-writer.js';
import { backfillBudgetSummaries } from './budget-backfill.js';
import { migrateMedia } from './media-migrator.js';
import { fetchSupabaseAuthUsers, importAuthUsersWithPasswords } from './auth-importer.js';
import type { Bucket } from '@google-cloud/storage';
import admin from 'firebase-admin';

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

function parseArgs(argv: string[]): {
  accountId: string;
  target: WriteTarget;
  dryRun: boolean;
  skipMedia: boolean;
  skipBackfill: boolean;
  skipAuth: boolean;
} {
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
    console.error('Usage: npx tsx migration/src/cli.ts --account <UUID> [--target emulator|production] [--dry-run] [--skip-media] [--skip-backfill]');
    process.exit(1);
  }

  const targetArg = flags.get('target');
  const target: WriteTarget = targetArg === 'production' ? 'production' : 'emulator';
  const dryRun = flags.has('dry-run');
  const skipMedia = flags.has('skip-media');
  const skipBackfill = flags.has('skip-backfill');
  const skipAuth = flags.has('skip-auth');

  return { accountId, target, dryRun, skipMedia, skipBackfill, skipAuth };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const { accountId, target, dryRun, skipMedia, skipBackfill, skipAuth } = parseArgs(process.argv);

  const supabaseUrl = process.env.VITE_SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !supabaseKey) {
    console.error('Error: VITE_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set.');
    process.exit(1);
  }

  const projectId = process.env.FIREBASE_PROJECT_ID ?? 'ledger-nine4';
  const storageBucketName =
    process.env.FIREBASE_STORAGE_BUCKET ?? `${projectId}.appspot.com`;

  if (target === 'emulator') {
    process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8181';
    process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= 'localhost:9199';
    process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';
  }

  console.log(`\n=== Ledger Migration ===`);
  console.log(`Account:  ${accountId}`);
  console.log(`Target:   ${target}${dryRun ? ' (dry-run)' : ''}`);
  console.log(`Auth:     ${skipAuth ? 'skipped' : 'enabled'}`);
  console.log(`Media:    ${skipMedia ? 'skipped' : 'enabled'}`);
  console.log(`Backfill: ${skipBackfill ? 'skipped' : 'enabled'}`);
  console.log('');

  // 1. Read from Supabase
  console.log('Step 1/6 — Reading from Supabase...');
  const supabase = createSupabaseClient(supabaseUrl, supabaseKey);
  const exportData = await readAccount(supabase, accountId);

  // 2. Transform
  console.log('\nStep 2/6 — Transforming data...');
  const result = transform(exportData);

  console.log(`  Documents: ${result.documents.length}`);
  console.log(`  Media refs: ${result.mediaRefs.length}`);
  if (result.warnings.length > 0) {
    console.log(`  Warnings: ${result.warnings.length}`);
  }
  if (result.errors.length > 0) {
    console.log(`  Errors: ${result.errors.length}`);
    for (const err of result.errors) {
      console.error(`  [error] ${err.code}: ${err.message}`, err.details ?? '');
    }
  }

  // Initialize Firebase before auth import or Firestore writes
  const db = initFirestore(target, projectId);

  // 3. Import auth users
  let authResult = { imported: 0, skipped: 0, failed: 0, errors: [] as { uid: string; email: string | null; error: string }[] };
  if (!skipAuth) {
    console.log('\nStep 3/6 — Importing auth users...');
    const userIds = exportData.users.map((u) => u.id).filter(Boolean);
    const authUsers = await fetchSupabaseAuthUsers(supabase, userIds);
    console.log(`  Found ${authUsers.length} auth user(s) in Supabase Auth.`);
    authResult = await importAuthUsersWithPasswords(authUsers, { dryRun });
    console.log(`  Imported: ${authResult.imported}, Skipped: ${authResult.skipped}, Failed: ${authResult.failed}`);
  } else {
    console.log('\nStep 3/6 — Auth import skipped.');
  }

  // 4. Write to Firestore
  console.log('\nStep 4/6 — Writing to Firestore...');
  const writeResult = await writeDocs(db, result.documents, {
    dryRun,
    opsPerSecond: target === 'production' ? 50 : undefined,
  });
  console.log(`  Written: ${writeResult.written}, Failed: ${writeResult.failed}`);

  // 5. Media migration
  let mediaResult = { uploaded: 0, skipped: 0, failed: 0, errors: [] as { mediaId: string; supabaseUrl: string; error: string }[] };
  if (!skipMedia && result.mediaRefs.length > 0) {
    console.log('\nStep 5/6 — Migrating media...');
    const storage = admin.storage();
    const bucket = storage.bucket(storageBucketName) as unknown as Bucket;
    mediaResult = await migrateMedia(
      result.mediaRefs,
      result.documents,
      bucket,
      accountId,
      { dryRun }
    );
    console.log(`  Uploaded: ${mediaResult.uploaded}, Skipped: ${mediaResult.skipped}, Failed: ${mediaResult.failed}`);

    // Write patched documents (URL fields updated) back to Firestore
    if (!dryRun && (mediaResult.uploaded + mediaResult.skipped) > 0) {
      const patchResult = await writeDocs(db, result.documents, { dryRun });
      console.log(`  Re-wrote ${patchResult.written} docs with patched URLs.`);
    }
  } else {
    console.log('\nStep 5/6 — Media migration skipped.');
  }

  // 6. Budget backfill
  let backfillResult = { backfilled: 0, failed: 0 };
  if (!skipBackfill) {
    console.log('\nStep 6/6 — Backfilling budget summaries...');
    const projectIds = exportData.projects.map((p) => p.id).filter(Boolean);
    backfillResult = await backfillBudgetSummaries(db, accountId, projectIds, { dryRun });
    console.log(`  Backfilled: ${backfillResult.backfilled}, Failed: ${backfillResult.failed}`);
  } else {
    console.log('\nStep 6/6 — Budget backfill skipped.');
  }

  // Report
  const report = {
    meta: {
      accountId,
      target,
      dryRun,
      migratedAt: new Date().toISOString(),
    },
    totals: {
      documents: result.documents.length,
      written: writeResult.written,
      writeFailed: writeResult.failed,
      authImported: authResult.imported,
      authSkipped: authResult.skipped,
      authFailed: authResult.failed,
      mediaRefs: result.mediaRefs.length,
      mediaUploaded: mediaResult.uploaded,
      mediaSkipped: mediaResult.skipped,
      mediaFailed: mediaResult.failed,
      backfilled: backfillResult.backfilled,
      backfillFailed: backfillResult.failed,
      warnings: result.warnings.length,
      errors: result.errors.length,
    },
    counts: result.counts,
    warnings: result.warnings.slice(0, 500),
    errors: result.errors,
    authErrors: authResult.errors,
    mediaErrors: mediaResult.errors,
  };

  const outDir = resolve(process.cwd(), 'migration', 'out', accountId);
  await mkdir(outDir, { recursive: true });
  const reportPath = join(outDir, 'migration-report.json');
  await writeFile(reportPath, JSON.stringify(report, null, 2), 'utf8');

  console.log(`\nReport written to: ${reportPath}`);
  console.log('\n=== Done ===\n');

  if (writeResult.failed > 0 || backfillResult.failed > 0 || authResult.failed > 0) {
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
