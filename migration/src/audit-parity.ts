#!/usr/bin/env tsx
/**
 * Audit Parity: Supabase vs Firebase
 *
 * Reads all items and transactions from both Supabase and Firebase for a given
 * account, then reports what exists in Supabase but is missing from Firebase.
 *
 * Usage:
 *   npx tsx migration/src/audit-parity.ts --account <UUID> --target production
 *   npx tsx migration/src/audit-parity.ts --target production   # defaults to 1584 Design
 */

import { readFileSync, existsSync } from 'node:fs';
import { writeFile, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import admin from 'firebase-admin';
import { createSupabaseClient, readAccount } from './supabase-reader.js';
import { initFirestore, type WriteTarget } from './firestore-writer.js';
import type { SupabaseItem, SupabaseTransaction } from './types.js';

// ---------------------------------------------------------------------------
// Env loading (same pattern as cli.ts)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Arg parsing
// ---------------------------------------------------------------------------

const DEFAULT_ACCOUNT = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94'; // 1584 Design

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

  return {
    accountId: (flags.get('account') as string) ?? DEFAULT_ACCOUNT,
    target: ((flags.get('target') as string) ?? 'production') as WriteTarget,
  };
}

// ---------------------------------------------------------------------------
// ID resolution (mirrors transform.ts logic)
// ---------------------------------------------------------------------------

function normalizeId(v: unknown): string | null {
  if (typeof v !== 'string' || !v.trim()) return null;
  return v.trim();
}

function resolveItemDocId(item: SupabaseItem): string | null {
  return normalizeId(item.item_id) ?? normalizeId(item.id);
}

function resolveTransactionDocId(tx: SupabaseTransaction): string | null {
  return normalizeId(tx.transaction_id) ?? normalizeId(tx.id);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const { accountId, target } = parseArgs(process.argv);
  const projectId = process.env.FIREBASE_PROJECT_ID ?? 'ledger-nine4';

  console.log(`\n=== Parity Audit ===`);
  console.log(`  Account:  ${accountId}`);
  console.log(`  Target:   ${target}`);
  console.log(`  Firebase: ${projectId}\n`);

  // --- Supabase ---
  const supabaseUrl = process.env.VITE_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('Missing VITE_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  }

  console.log('Reading from Supabase...');
  const supabase = createSupabaseClient(supabaseUrl, serviceRoleKey);
  const sbData = await readAccount(supabase, accountId);

  const sbItems = new Map<string, SupabaseItem>();
  for (const item of sbData.items) {
    const docId = resolveItemDocId(item);
    if (docId) sbItems.set(docId, item);
  }

  const sbTransactions = new Map<string, SupabaseTransaction>();
  for (const tx of sbData.transactions) {
    const docId = resolveTransactionDocId(tx);
    if (docId) sbTransactions.set(docId, tx);
  }

  console.log(`  Supabase items:        ${sbItems.size}`);
  console.log(`  Supabase transactions: ${sbTransactions.size}`);

  // --- Firebase ---
  console.log('\nReading from Firebase...');
  const db = initFirestore(target, projectId);

  const fbItemSnap = await db.collection(`accounts/${accountId}/items`).get();
  const fbItemIds = new Set(fbItemSnap.docs.map((d) => d.id));

  const fbTxSnap = await db.collection(`accounts/${accountId}/transactions`).get();
  const fbTxIds = new Set(fbTxSnap.docs.map((d) => d.id));

  console.log(`  Firebase items:        ${fbItemIds.size}`);
  console.log(`  Firebase transactions: ${fbTxIds.size}`);

  // --- Compare ---
  console.log('\nComparing...\n');

  const missingItems: Array<{
    docId: string;
    supabaseUuid: string;
    name: string | null;
    projectId: string | null;
    disposition: string | null;
    purchasePrice: string | null;
    createdAt: string | null;
  }> = [];

  for (const [docId, item] of sbItems) {
    if (!fbItemIds.has(docId)) {
      missingItems.push({
        docId,
        supabaseUuid: item.id,
        name: item.name,
        projectId: item.project_id,
        disposition: item.disposition,
        purchasePrice: item.purchase_price,
        createdAt: item.created_at,
      });
    }
  }

  const missingTransactions: Array<{
    docId: string;
    supabaseUuid: string;
    source: string | null;
    amount: string | null;
    transactionDate: string | null;
    transactionType: string | null;
    projectId: string | null;
    status: string | null;
    createdAt: string | null;
  }> = [];

  for (const [docId, tx] of sbTransactions) {
    if (!fbTxIds.has(docId)) {
      missingTransactions.push({
        docId,
        supabaseUuid: tx.id,
        source: tx.source,
        amount: tx.amount,
        transactionDate: tx.transaction_date,
        transactionType: tx.transaction_type,
        projectId: tx.project_id,
        status: tx.status,
        createdAt: tx.created_at,
      });
    }
  }

  // Also check: items in Firebase but NOT in Supabase (created natively)
  const firebaseOnlyItems = [...fbItemIds].filter((id) => !sbItems.has(id));
  const firebaseOnlyTx = [...fbTxIds].filter((id) => !sbTransactions.has(id));

  // --- Report ---
  const report = {
    meta: {
      accountId,
      target,
      auditedAt: new Date().toISOString(),
    },
    summary: {
      supabaseItems: sbItems.size,
      supabaseTransactions: sbTransactions.size,
      firebaseItems: fbItemIds.size,
      firebaseTransactions: fbTxIds.size,
      missingFromFirebase: {
        items: missingItems.length,
        transactions: missingTransactions.length,
      },
      firebaseOnly: {
        items: firebaseOnlyItems.length,
        transactions: firebaseOnlyTx.length,
      },
    },
    missingItems,
    missingTransactions,
    firebaseOnlyItemIds: firebaseOnlyItems,
    firebaseOnlyTransactionIds: firebaseOnlyTx,
  };

  // Print summary
  console.log('=== Summary ===');
  console.log(`  Supabase items:         ${sbItems.size}`);
  console.log(`  Firebase items:         ${fbItemIds.size}`);
  console.log(`  Missing from Firebase:  ${missingItems.length} items, ${missingTransactions.length} transactions`);
  console.log(`  Firebase-only:          ${firebaseOnlyItems.length} items, ${firebaseOnlyTx.length} transactions`);

  if (missingItems.length > 0) {
    console.log(`\n--- Missing Items (in Supabase, not in Firebase) ---`);
    for (const item of missingItems) {
      console.log(`  ${item.docId}  ${item.name ?? '(unnamed)'}  ${item.disposition ?? '?'}  $${item.purchasePrice ?? '?'}  created: ${item.createdAt ?? '?'}`);
    }
  }

  if (missingTransactions.length > 0) {
    console.log(`\n--- Missing Transactions (in Supabase, not in Firebase) ---`);
    for (const tx of missingTransactions) {
      console.log(`  ${tx.docId}  ${tx.source ?? '(no source)'}  $${tx.amount ?? '?'}  ${tx.transactionType ?? '?'}  ${tx.transactionDate ?? '?'}  created: ${tx.createdAt ?? '?'}`);
    }
  }

  if (missingItems.length === 0 && missingTransactions.length === 0) {
    console.log('\n  All Supabase data exists in Firebase. No gaps found.');
  }

  // Write report
  const outDir = join('migration', 'out', accountId);
  await mkdir(outDir, { recursive: true });
  const reportPath = join(outDir, 'parity-audit.json');
  await writeFile(reportPath, JSON.stringify(report, null, 2));
  console.log(`\nReport written to ${reportPath}`);

  process.exit(0);
}

main().catch((err) => {
  console.error('Audit failed:', err);
  process.exit(1);
});
