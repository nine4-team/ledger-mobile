#!/usr/bin/env node
/**
 * revert-transactions-to-fee-expense.mjs — Emergency rollback for Phase 3 Script 1.
 *
 * Restores `type` from `_migrationPreviousType` on every transaction that
 * carries the latter field, then clears the marker. Only touches docs the
 * forward script wrote — everything else is left alone.
 *
 * Usage:
 *   node scripts/revert-transactions-to-fee-expense.mjs --account <id>
 *   node scripts/revert-transactions-to-fee-expense.mjs --all
 *   node scripts/revert-transactions-to-fee-expense.mjs --account <id> --commit
 *
 * Idempotent. Dry-run by default.
 */

import admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';

const BATCH_SIZE = 500;
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';

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

function log(msg) { console.log(`\x1b[36m[revert-tx]\x1b[0m ${msg}`); }
function fail(msg) { console.error(`\x1b[31m[revert-tx]\x1b[0m ${msg}`); }

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

async function revertAccount(db, accountId, commit) {
  log(`Processing account ${accountId} (${commit ? 'COMMIT' : 'dry-run'})`);

  // Firestore can't efficiently query "has field X" — fetch all transactions
  // for the account, filter client-side. Account transaction counts are
  // bounded; this is fine.
  const snap = await db.collection(`accounts/${accountId}/transactions`).get();
  const candidates = snap.docs.filter((d) => {
    const data = d.data();
    return typeof data._migrationPreviousType === 'string';
  });
  log(`  Found ${candidates.length} transactions carrying _migrationPreviousType`);

  if (candidates.length === 0) return { reverted: 0 };

  if (!commit) {
    for (const d of candidates.slice(0, 10)) {
      const data = d.data();
      log(`    would revert ${d.ref.path}: ${data.type} → ${data._migrationPreviousType}`);
    }
    if (candidates.length > 10) log(`    ...and ${candidates.length - 10} more`);
    return { reverted: 0 };
  }

  let reverted = 0;
  for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
    const slice = candidates.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const d of slice) {
      const data = d.data();
      batch.update(d.ref, {
        type: data._migrationPreviousType,
        _migrationPreviousType: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    reverted += slice.length;
    log(`  Committed batch: ${reverted}/${candidates.length}`);
  }

  log(`  Done. Reverted ${reverted} transactions.`);
  return { reverted };
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log('Reverts Phase 3 Script 1. Dry-run by default. --commit to apply.');
    return;
  }
  if (!args.account && !args.all) {
    fail('Must specify --account <id> or --all.');
    process.exit(2);
  }
  if (args.account && args.all) {
    fail('--account and --all are mutually exclusive.');
    process.exit(2);
  }

  const db = initFirestore();
  const accountIds = args.account
    ? [args.account]
    : (await db.collection('accounts').get()).docs.map((d) => d.id);

  let total = 0;
  for (const id of accountIds) {
    try {
      const { reverted } = await revertAccount(db, id, args.commit);
      total += reverted;
    } catch (err) {
      fail(`Account ${id} failed: ${err.stack || err}`);
      process.exitCode = 1;
    }
  }
  log(`FINISHED — ${args.commit ? 'reverted' : 'would revert'} ${total} transactions.`);
}

main().catch((err) => {
  fail(err.stack || String(err));
  process.exit(1);
});
