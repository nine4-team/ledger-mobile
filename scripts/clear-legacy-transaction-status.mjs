#!/usr/bin/env node
/**
 * clear-legacy-transaction-status.mjs — Billing v2 Phase 5.5
 *
 * Deletes `status` from any transaction where the value is a legacy
 * `"pending"` or `"completed"` (or casing variants). Phase 3 stopped writing
 * both values; no reader branches on them any more. Legacy values become
 * "effectively nil" once the field is gone.
 *
 * `canceled` / `cancelled` values are preserved — that's the only active case.
 *
 * Rollback anchor: gs://ledger-nine4-backups/pre-billing-v2-20260421-105733
 *
 * Usage:
 *   node scripts/clear-legacy-transaction-status.mjs --account <id>          # dry-run
 *   node scripts/clear-legacy-transaction-status.mjs --all                   # dry-run
 *   node scripts/clear-legacy-transaction-status.mjs --account <id> --commit
 *   node scripts/clear-legacy-transaction-status.mjs --all --commit
 */

import admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';
import { mkdirSync, writeFileSync, appendFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const BATCH_SIZE = 500;
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const LOG_DIR = join(dirname(fileURLToPath(import.meta.url)), 'migration-logs');
const LEGACY_VALUES = new Set(['pending', 'completed']);

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
Delete legacy \`pending\`/\`completed\` transaction status (billing-v2 Phase 5.5).

Options:
  --account <id>    Run against one account. Required unless --all.
  --all             Run across every account.
  --commit          Apply writes. Omit for dry-run.
  --help, -h        Show this help.
`);
}

function log(msg) { console.log(`\x1b[36m[clear-tx-status]\x1b[0m ${msg}`); }
function fail(msg) { console.error(`\x1b[31m[clear-tx-status]\x1b[0m ${msg}`); }

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

async function processAccount(db, accountId, commit) {
  log(`Processing account ${accountId} (${commit ? 'COMMIT' : 'dry-run'})`);

  const snap = await db.collection(`accounts/${accountId}/transactions`).get();
  const dist = { pending: 0, completed: 0, canceled: 0, other: 0, nil: 0 };
  const candidates = [];

  for (const doc of snap.docs) {
    const data = doc.data();
    const raw = data.status;
    if (raw === undefined || raw === null) { dist.nil++; continue; }
    const norm = typeof raw === 'string' ? raw.toLowerCase() : '';
    if (LEGACY_VALUES.has(norm)) {
      dist[norm]++;
      candidates.push({ ref: doc.ref, oldValue: raw });
    } else if (norm === 'canceled' || norm === 'cancelled') {
      dist.canceled++;
    } else {
      dist.other++;
    }
  }

  log(`  ${snap.size} transactions. Distribution: ${JSON.stringify(dist)}`);
  log(`  Candidates (legacy status to clear): ${candidates.length}`);

  if (candidates.length === 0) return 0;

  mkdirSync(LOG_DIR, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const logPath = join(
    LOG_DIR,
    `clear-tx-status-${accountId}-${commit ? 'commit' : 'dryrun'}-${ts}.jsonl`,
  );
  writeFileSync(logPath, '');
  for (const c of candidates) {
    appendFileSync(logPath, JSON.stringify({ path: c.ref.path, oldValue: c.oldValue }) + '\n');
  }
  log(`  Changelog: ${logPath}`);

  if (!commit) {
    log('  DRY-RUN — no writes. Re-run with --commit to apply.');
    return 0;
  }

  let updated = 0;
  for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
    const slice = candidates.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const c of slice) {
      batch.update(c.ref, {
        status: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    updated += slice.length;
    log(`    Committed: ${updated}/${candidates.length}`);
  }
  return updated;
}

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

  let total = 0;
  for (const id of accountIds) {
    try {
      total += await processAccount(db, id, args.commit);
    } catch (err) {
      fail(`Account ${id} failed: ${err.stack || err}`);
      process.exitCode = 1;
    }
  }

  log(`FINISHED — ${args.commit ? 'cleared' : 'would clear'} legacy status on ${total} transaction(s) across ${accountIds.length} account(s).`);
}

main().catch((err) => {
  fail(err.stack || String(err));
  process.exit(1);
});
