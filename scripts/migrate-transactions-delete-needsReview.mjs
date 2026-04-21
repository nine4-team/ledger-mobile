#!/usr/bin/env node
/**
 * migrate-transactions-delete-needsReview.mjs
 *
 * Deletes the vestigial `needsReview` field from every transaction document.
 * The live "Needs Review" badge is driven by `isComplete != true`; nothing
 * branches on `needsReview`. This script removes the stored field so future
 * reads/writes don't carry dead data.
 *
 * Usage:
 *   node scripts/migrate-transactions-delete-needsReview.mjs --account <id>
 *   node scripts/migrate-transactions-delete-needsReview.mjs --all
 *   node scripts/migrate-transactions-delete-needsReview.mjs --all --commit
 *
 * Credentials: uses GOOGLE_APPLICATION_CREDENTIALS env var (path to service
 * account JSON), falling back to ADC. To target the emulator set
 * FIRESTORE_EMULATOR_HOST.
 *
 * Idempotent: documents without `needsReview` are skipped.
 */

import admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';

const BATCH_SIZE = 400;
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

function printHelp() {
  console.log(`
Delete \`needsReview\` from every transaction doc.

Options:
  --account <id>   Run against one account. Required unless --all.
  --all            Run across every account.
  --commit         Apply writes. Omit for dry-run.
  --help, -h       Show this help.
`);
}

function log(msg) { console.log(`\x1b[36m[delete-needsReview]\x1b[0m ${msg}`); }
function fail(msg) { console.error(`\x1b[31m[delete-needsReview]\x1b[0m ${msg}`); }

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

async function migrateAccount(db, accountId, commit) {
  log(`Processing account ${accountId} (${commit ? 'COMMIT' : 'dry-run'})`);

  const snap = await db.collection(`accounts/${accountId}/transactions`).get();
  log(`  Loaded ${snap.size} transactions`);

  const candidates = snap.docs.filter((d) => Object.prototype.hasOwnProperty.call(d.data() ?? {}, 'needsReview'));
  log(`  Candidates with needsReview field: ${candidates.length}`);

  if (candidates.length === 0) return { updated: 0 };

  if (!commit) {
    log('  DRY-RUN — no writes performed. Re-run with --commit to apply.');
    return { updated: 0 };
  }

  let updated = 0;
  for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
    const slice = candidates.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const doc of slice) {
      batch.update(doc.ref, { needsReview: FieldValue.delete() });
    }
    await batch.commit();
    updated += slice.length;
    log(`  Committed batch: ${updated}/${candidates.length}`);
  }

  log(`  Done. Updated ${updated} transactions.`);
  return { updated };
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

  let totalUpdated = 0;
  for (const id of accountIds) {
    try {
      const { updated } = await migrateAccount(db, id, args.commit);
      totalUpdated += updated;
    } catch (err) {
      fail(`Account ${id} failed: ${err.stack || err}`);
      process.exitCode = 1;
    }
  }

  log(`FINISHED — ${args.commit ? 'updated' : 'would update'} ${totalUpdated} transactions across ${accountIds.length} account(s).`);
}

main().catch((err) => {
  fail(err.stack || String(err));
  process.exit(1);
});
