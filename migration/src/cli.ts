#!/usr/bin/env tsx
/**
 * Ledger Migration CLI
 *
 * Migrates account data from Supabase (web) → Firestore (mobile).
 *
 * Usage:
 *   npx tsx migration/src/cli.ts --account <UUID> [options]
 *   npx tsx migration/src/cli.ts --all [options]
 *
 * Options:
 *   --account <UUID>      Supabase account ID to migrate
 *   --all                 Discover and migrate all accounts from Supabase
 *   --target <emulator|production>  Where to write Firestore docs (default: emulator)
 *   --dry-run             Transform only — print report without writing anything
 *   --skip-media          Skip Supabase Storage → Firebase Storage migration
 *   --skip-backfill       Skip budgetSummary recalculation after writes
 *   --skip-auth           Skip auth user import
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

import { createSupabaseClient, readAccount, listAccounts } from './supabase-reader.js';
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
  accountId: string | null;
  all: boolean;
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
  const all = flags.has('all');

  if (all && typeof accountId === 'string') {
    console.error('Error: --all and --account are mutually exclusive.');
    process.exit(1);
  }
  if (!all && (typeof accountId !== 'string' || accountId.length === 0)) {
    console.error('Error: --account <UUID> or --all is required.');
    console.error('Usage: npx tsx migration/src/cli.ts --account <UUID> [options]');
    console.error('       npx tsx migration/src/cli.ts --all [options]');
    process.exit(1);
  }

  const targetArg = flags.get('target');
  const target: WriteTarget = targetArg === 'production' ? 'production' : 'emulator';
  const dryRun = flags.has('dry-run');
  const skipMedia = flags.has('skip-media');
  const skipBackfill = flags.has('skip-backfill');
  const skipAuth = flags.has('skip-auth');

  return { accountId: typeof accountId === 'string' ? accountId : null, all, target, dryRun, skipMedia, skipBackfill, skipAuth };
}

// ---------------------------------------------------------------------------
// Migrate a single account (steps 1–6 + report)
// ---------------------------------------------------------------------------

import type { SupabaseClient } from '@supabase/supabase-js';

async function migrateOneAccount(
  supabase: SupabaseClient,
  db: admin.firestore.Firestore,
  accountId: string,
  opts: {
    target: WriteTarget;
    dryRun: boolean;
    skipMedia: boolean;
    skipBackfill: boolean;
    skipAuth: boolean;
    storageBucketName: string;
  }
): Promise<boolean> {
  // 1. Read from Supabase
  console.log('Step 1/6 — Reading from Supabase...');
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

  // 3. Import auth users
  let authResult = { imported: 0, skipped: 0, failed: 0, errors: [] as { uid: string; email: string | null; error: string }[] };
  if (!opts.skipAuth) {
    console.log('\nStep 3/6 — Importing auth users...');
    const userIds = exportData.users.map((u) => u.id).filter(Boolean);
    const authUsers = await fetchSupabaseAuthUsers(supabase, userIds);
    console.log(`  Found ${authUsers.length} auth user(s) in Supabase Auth.`);
    authResult = await importAuthUsersWithPasswords(authUsers, { dryRun: opts.dryRun });
    console.log(`  Imported: ${authResult.imported}, Skipped: ${authResult.skipped}, Failed: ${authResult.failed}`);
  } else {
    console.log('\nStep 3/6 — Auth import skipped.');
  }

  // 4. Write to Firestore
  console.log('\nStep 4/6 — Writing to Firestore...');
  const writeResult = await writeDocs(db, result.documents, {
    dryRun: opts.dryRun,
    opsPerSecond: opts.target === 'production' ? 50 : undefined,
  });
  console.log(`  Written: ${writeResult.written}, Failed: ${writeResult.failed}`);

  // 5. Media migration
  let mediaResult = { uploaded: 0, skipped: 0, failed: 0, errors: [] as { mediaId: string; supabaseUrl: string; error: string }[] };
  if (!opts.skipMedia && result.mediaRefs.length > 0) {
    console.log('\nStep 5/6 — Migrating media...');
    const storage = admin.storage();
    const bucket = storage.bucket(opts.storageBucketName) as unknown as Bucket;
    mediaResult = await migrateMedia(
      result.mediaRefs,
      result.documents,
      bucket,
      accountId,
      { dryRun: opts.dryRun }
    );
    console.log(`  Uploaded: ${mediaResult.uploaded}, Skipped: ${mediaResult.skipped}, Failed: ${mediaResult.failed}`);

    // Write patched documents (URL fields updated) back to Firestore
    if (!opts.dryRun && (mediaResult.uploaded + mediaResult.skipped) > 0) {
      const patchResult = await writeDocs(db, result.documents, { dryRun: opts.dryRun });
      console.log(`  Re-wrote ${patchResult.written} docs with patched URLs.`);
    }
  } else {
    console.log('\nStep 5/6 — Media migration skipped.');
  }

  // 6. Budget backfill
  let backfillResult = { backfilled: 0, failed: 0 };
  if (!opts.skipBackfill) {
    console.log('\nStep 6/6 — Backfilling budget summaries...');
    const projectIds = exportData.projects.map((p) => p.id).filter(Boolean);
    backfillResult = await backfillBudgetSummaries(db, accountId, projectIds, { dryRun: opts.dryRun });
    console.log(`  Backfilled: ${backfillResult.backfilled}, Failed: ${backfillResult.failed}`);
  } else {
    console.log('\nStep 6/6 — Budget backfill skipped.');
  }

  // Report
  const report = {
    meta: {
      accountId,
      target: opts.target,
      dryRun: opts.dryRun,
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

  const hasFails = writeResult.failed > 0 || backfillResult.failed > 0 || authResult.failed > 0;
  return !hasFails;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const { accountId, all, target, dryRun, skipMedia, skipBackfill, skipAuth } = parseArgs(process.argv);

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
    process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';
  }

  const supabase = createSupabaseClient(supabaseUrl, supabaseKey);
  const db = initFirestore(target, projectId);

  // Determine which accounts to migrate
  let accounts: Array<{ id: string; name: string }>;
  if (all) {
    console.log('\nDiscovering accounts from Supabase...');
    accounts = await listAccounts(supabase);
    console.log(`Found ${accounts.length} account(s):`);
    for (const a of accounts) {
      console.log(`  - ${a.name} (${a.id})`);
    }
  } else {
    accounts = [{ id: accountId!, name: accountId! }];
  }

  const opts = { target, dryRun, skipMedia, skipBackfill, skipAuth, storageBucketName };
  const results: Array<{ id: string; name: string; success: boolean }> = [];

  for (const account of accounts) {
    console.log(`\n${'='.repeat(60)}`);
    console.log(`=== Migrating: ${account.name} (${account.id}) ===`);
    console.log(`${'='.repeat(60)}`);
    console.log(`Target:   ${target}${dryRun ? ' (dry-run)' : ''}`);
    console.log(`Auth:     ${skipAuth ? 'skipped' : 'enabled'}`);
    console.log(`Media:    ${skipMedia ? 'skipped' : 'enabled'}`);
    console.log(`Backfill: ${skipBackfill ? 'skipped' : 'enabled'}`);
    console.log('');

    try {
      const success = await migrateOneAccount(supabase, db, account.id, opts);
      results.push({ id: account.id, name: account.name, success });
    } catch (err) {
      console.error(`\nAccount ${account.name} (${account.id}) failed:`, err);
      results.push({ id: account.id, name: account.name, success: false });
    }
  }

  // Summary
  if (accounts.length > 1) {
    console.log(`\n${'='.repeat(60)}`);
    console.log('=== Migration Summary ===');
    console.log(`${'='.repeat(60)}`);
    for (const r of results) {
      const icon = r.success ? 'OK' : 'FAILED';
      console.log(`  [${icon}] ${r.name} (${r.id})`);
    }
    const failed = results.filter(r => !r.success).length;
    const passed = results.filter(r => r.success).length;
    console.log(`\n  ${passed}/${results.length} succeeded, ${failed} failed.`);
  }

  console.log('\n=== Done ===\n');

  if (results.some(r => !r.success)) {
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
