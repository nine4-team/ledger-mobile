#!/usr/bin/env node
/**
 * strip-billing-status.mjs — Billing v2 Phase 5.4
 *
 * Deletes the vestigial `billingStatus` field from every item and transaction.
 * By the time this runs, Phase 5.2 has already removed every Swift reader,
 * so the field is dead weight in Firestore.
 *
 * Rollback anchor: `gs://ledger-nine4-backups/pre-billing-v2-20260421-105733`
 * (Phase 5.3 export). Restore with:
 *   gcloud firestore import gs://ledger-nine4-backups/pre-billing-v2-20260421-105733 \
 *     --project=ledger-nine4
 *
 * Usage:
 *   node scripts/strip-billing-status.mjs --account <id>          # dry-run one account
 *   node scripts/strip-billing-status.mjs --all                   # dry-run everything
 *   node scripts/strip-billing-status.mjs --account <id> --commit # apply
 *   node scripts/strip-billing-status.mjs --all --commit          # apply everything
 *
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS or ADC. Target the emulator
 * with FIRESTORE_EMULATOR_HOST.
 *
 * Idempotent: re-running reports zero candidates.
 */

import admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';
import { mkdirSync, writeFileSync, appendFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const BATCH_SIZE = 500;
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const LOG_DIR = join(dirname(fileURLToPath(import.meta.url)), 'migration-logs');

// ─── CLI ──────────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const args = { commit: false, all: false, account: null, help: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--commit') args.commit = true;
    else if (a === '--all') args.all = true;
    else if (a === '--account') args.account = argv[++i];
    else if (a === '--help' || a === '-h') args.help = true;
    else {
      console.error(`Unknown arg: ${a}`);
      process.exit(2);
    }
  }
  return args;
}

function printHelp() {
  console.log(`
Strip \`billingStatus\` from items and transactions (billing-v2 Phase 5.4).

Options:
  --account <id>    Run against one account. Required unless --all.
  --all             Run across every account.
  --commit          Apply writes. Omit for dry-run.
  --help, -h        Show this help.

Dry-run first. Commit after reviewing the candidate counts.
`);
}

function log(msg) { console.log(`\x1b[36m[strip-bs]\x1b[0m ${msg}`); }
function fail(msg) { console.error(`\x1b[31m[strip-bs]\x1b[0m ${msg}`); }

function initFirestore() {
  if (admin.apps.length) return admin.firestore();
  const emulator = process.env.FIRESTORE_EMULATOR_HOST;
  if (emulator) {
    log(`Connecting to Firestore emulator at ${emulator}`);
    admin.initializeApp({ projectId: PROJECT_ID });
  } else {
    log(`Connecting to production Firestore (project=${PROJECT_ID})`);
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT_ID,
    });
  }
  return admin.firestore();
}

// ─── Per-collection pass ──────────────────────────────────────────────────────

async function stripFromCollection(db, collectionPath, commit, logStream) {
  const snap = await db.collection(collectionPath).get();
  const candidates = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    if (Object.prototype.hasOwnProperty.call(data, 'billingStatus')) {
      candidates.push({ ref: doc.ref, oldValue: data.billingStatus });
    }
  }
  log(`  ${collectionPath}: ${snap.size} docs, ${candidates.length} with billingStatus`);

  for (const c of candidates) {
    appendFileSync(logStream, JSON.stringify({
      path: c.ref.path,
      oldValue: c.oldValue ?? null,
    }) + '\n');
  }

  if (!commit || candidates.length === 0) return candidates.length;

  let updated = 0;
  for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
    const slice = candidates.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const c of slice) {
      batch.update(c.ref, {
        billingStatus: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    updated += slice.length;
    log(`    Committed: ${updated}/${candidates.length}`);
  }
  return updated;
}

async function processAccount(db, accountId, commit) {
  log(`Processing account ${accountId} (${commit ? 'COMMIT' : 'dry-run'})`);

  mkdirSync(LOG_DIR, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const logPath = join(
    LOG_DIR,
    `strip-bs-${accountId}-${commit ? 'commit' : 'dryrun'}-${ts}.jsonl`,
  );
  writeFileSync(logPath, '');

  const items = await stripFromCollection(db, `accounts/${accountId}/items`, commit, logPath);
  const txs = await stripFromCollection(db, `accounts/${accountId}/transactions`, commit, logPath);

  log(`  Changelog: ${logPath}`);
  if (!commit) log(`  DRY-RUN — would strip ${items + txs} field(s). Re-run with --commit to apply.`);

  return { items, txs };
}

// ─── Entry ────────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) { printHelp(); return; }

  if (!args.account && !args.all) {
    fail('Must specify --account <id> or --all.');
    printHelp();
    process.exit(2);
  }
  if (args.account && args.all) {
    fail('--account and --all are mutually exclusive.');
    process.exit(2);
  }

  const db = initFirestore();

  let accountIds;
  if (args.account) {
    accountIds = [args.account];
  } else {
    const accountsSnap = await db.collection('accounts').get();
    accountIds = accountsSnap.docs.map((d) => d.id);
    log(`Discovered ${accountIds.length} accounts`);
  }

  let totalItems = 0;
  let totalTxs = 0;
  for (const id of accountIds) {
    try {
      const { items, txs } = await processAccount(db, id, args.commit);
      totalItems += items;
      totalTxs += txs;
    } catch (err) {
      fail(`Account ${id} failed: ${err.stack || err}`);
      process.exitCode = 1;
    }
  }

  log(`FINISHED — ${args.commit ? 'stripped' : 'would strip'} billingStatus from ${totalItems} item(s) and ${totalTxs} transaction(s) across ${accountIds.length} account(s).`);
}

main().catch((err) => {
  fail(err.stack || String(err));
  process.exit(1);
});
