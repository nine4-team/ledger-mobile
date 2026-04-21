#!/usr/bin/env node
/**
 * backfill-invoice-lines.mjs — Billing v2 Phase 5.1
 *
 * Synthesizes the new signed `lines` array onto v1 invoices that pre-date the
 * billing-v2 rework. Legacy v1 invoices had no credits by construction, so
 * every synthesized line gets `sign: 1` (charge).
 *
 * For each invoice under `accounts/{id}/invoices/`:
 *   - Skip if `lines` is already present (idempotent).
 *   - Build one InvoiceLine per entry in `itemIds` and `transactionIds`.
 *   - Pull `amountCents` from the current item/tx doc.
 *     - Items: prefer `projectPriceCents` (what the client was charged), fall
 *       back to `purchasePriceCents`. Matches `InvoiceLineCalculations.amountCents(for:)`.
 *     - Transactions: `amountCents` field directly.
 *   - Leave `snapshotName` null. Filling it from the *current* name would
 *     misrepresent what the invoice said when it was issued.
 *   - Do NOT touch stored `totalCents`. Trust the historical value; if items/tx
 *     amounts have drifted the original net is still the source of truth.
 *
 * Usage:
 *   node scripts/backfill-invoice-lines.mjs --account <id>          # dry-run one account
 *   node scripts/backfill-invoice-lines.mjs --all                   # dry-run everything
 *   node scripts/backfill-invoice-lines.mjs --account <id> --commit # apply
 *   node scripts/backfill-invoice-lines.mjs --all --commit          # apply everything
 *
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS (service account JSON) or ADC.
 * Target the emulator with FIRESTORE_EMULATOR_HOST.
 *
 * Idempotent: re-running on a backfilled account reports zero updates.
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
Backfill signed \`lines\` onto v1 invoices (billing-v2 Phase 5.1).

Options:
  --account <id>    Run against one account. Required unless --all.
  --all             Run across every account.
  --commit          Apply writes. Omit for dry-run.
  --help, -h        Show this help.

Dry-run first. Commit after reviewing the candidate distribution.
`);
}

// ─── Logging ──────────────────────────────────────────────────────────────────

function log(msg) { console.log(`\x1b[36m[backfill-inv]\x1b[0m ${msg}`); }
function warn(msg) { console.warn(`\x1b[33m[backfill-inv]\x1b[0m ${msg}`); }
function fail(msg) { console.error(`\x1b[31m[backfill-inv]\x1b[0m ${msg}`); }

// ─── Firebase init ────────────────────────────────────────────────────────────

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

// ─── Line construction ────────────────────────────────────────────────────────

function itemAmountCents(itemData) {
  const projectPrice = itemData?.projectPriceCents;
  if (typeof projectPrice === 'number' && projectPrice > 0) return projectPrice;
  const purchase = itemData?.purchasePriceCents;
  return typeof purchase === 'number' ? purchase : 0;
}

function txAmountCents(txData) {
  const a = txData?.amountCents;
  return typeof a === 'number' ? a : 0;
}

function buildLines({ itemIds, transactionIds, itemById, txById }) {
  const lines = [];
  const missing = { items: [], transactions: [] };

  for (const id of itemIds ?? []) {
    const data = itemById.get(id);
    if (!data) {
      missing.items.push(id);
      // Still emit a zero-amount line so membership is preserved — the invoice
      // still claims this id. Better than silently dropping it.
      lines.push({
        sourceType: 'item',
        sourceId: id,
        amountCents: 0,
        sign: 1,
        snapshotName: null,
      });
      continue;
    }
    lines.push({
      sourceType: 'item',
      sourceId: id,
      amountCents: itemAmountCents(data),
      sign: 1,
      snapshotName: null,
    });
  }

  for (const id of transactionIds ?? []) {
    const data = txById.get(id);
    if (!data) {
      missing.transactions.push(id);
      lines.push({
        sourceType: 'transaction',
        sourceId: id,
        amountCents: 0,
        sign: 1,
        snapshotName: null,
      });
      continue;
    }
    lines.push({
      sourceType: 'transaction',
      sourceId: id,
      amountCents: txAmountCents(data),
      sign: 1,
      snapshotName: null,
    });
  }

  return { lines, missing };
}

// ─── Per-account pass ─────────────────────────────────────────────────────────

async function processAccount(db, accountId, commit) {
  log(`Processing account ${accountId} (${commit ? 'COMMIT' : 'dry-run'})`);

  const invoicesSnap = await db.collection(`accounts/${accountId}/invoices`).get();
  log(`  Invoices: ${invoicesSnap.size}`);
  if (invoicesSnap.empty) return { updated: 0 };

  // Collect every item/tx id referenced by any invoice lacking `lines`, then
  // batch-fetch. Cheaper than loading the whole account.
  const candidateDocs = [];
  const neededItemIds = new Set();
  const neededTxIds = new Set();

  const distribution = {
    'already-backfilled': 0,
    'candidate': 0,
    'empty-membership': 0,
    'skipped-draft': 0,
  };

  for (const doc of invoicesSnap.docs) {
    const inv = doc.data();
    if (Array.isArray(inv.lines)) {
      distribution['already-backfilled']++;
      continue;
    }
    // Drafts are in-progress; freezing them into a stored `lines` array is
    // the wrong behavior. They pick up lines naturally when the user next
    // saves the draft through the picker. Only sent / paid / voided get
    // backfilled — those are historical records that should be immutable.
    const status = typeof inv.status === 'string' ? inv.status.toLowerCase() : 'draft';
    if (status === 'draft') {
      distribution['skipped-draft']++;
      continue;
    }
    const itemIds = Array.isArray(inv.itemIds) ? inv.itemIds : [];
    const txIds = Array.isArray(inv.transactionIds) ? inv.transactionIds : [];
    if (itemIds.length === 0 && txIds.length === 0) {
      // Empty invoice — write an empty lines array so the v2 reader path
      // doesn't have to keep handling nil.
      distribution['empty-membership']++;
      candidateDocs.push({ ref: doc.ref, inv, itemIds, txIds });
      continue;
    }
    distribution['candidate']++;
    candidateDocs.push({ ref: doc.ref, inv, itemIds, txIds });
    for (const id of itemIds) neededItemIds.add(id);
    for (const id of txIds) neededTxIds.add(id);
  }

  log('  Distribution:');
  for (const [k, v] of Object.entries(distribution)) log(`    ${k}: ${v}`);

  if (candidateDocs.length === 0) {
    log('  Nothing to do.');
    return { updated: 0 };
  }

  // Batch-fetch referenced items and transactions. Firestore getAll takes refs
  // in chunks; keep it simple and chunk by 300.
  const itemById = await fetchByIds(
    db.collection(`accounts/${accountId}/items`),
    [...neededItemIds],
  );
  const txById = await fetchByIds(
    db.collection(`accounts/${accountId}/transactions`),
    [...neededTxIds],
  );
  log(`  Loaded ${itemById.size}/${neededItemIds.size} items, ${txById.size}/${neededTxIds.size} transactions`);

  // Prepare writes and collect missing-reference stats.
  const writes = []; // { ref, lines, storedTotal, syntheticTotal, missing }
  let totalMissingItems = 0;
  let totalMissingTx = 0;
  let totalMismatches = 0;

  for (const c of candidateDocs) {
    const { lines, missing } = buildLines({
      itemIds: c.itemIds,
      transactionIds: c.txIds,
      itemById,
      txById,
    });
    totalMissingItems += missing.items.length;
    totalMissingTx += missing.transactions.length;

    const syntheticTotal = lines.reduce((s, l) => s + l.amountCents * l.sign, 0);
    const storedTotal = typeof c.inv.totalCents === 'number' ? c.inv.totalCents : null;
    const mismatch = storedTotal !== null && storedTotal !== syntheticTotal;
    if (mismatch) totalMismatches++;

    writes.push({
      ref: c.ref,
      path: c.ref.path,
      lines,
      storedTotal,
      syntheticTotal,
      mismatch,
      missing,
    });
  }

  log(`  Missing item refs: ${totalMissingItems}  Missing tx refs: ${totalMissingTx}`);
  log(`  Stored-total vs synthesized-total mismatches: ${totalMismatches} (stored total is preserved either way)`);

  // Write changelog.
  mkdirSync(LOG_DIR, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const logPath = join(
    LOG_DIR,
    `inv-lines-${accountId}-${commit ? 'commit' : 'dryrun'}-${ts}.jsonl`,
  );
  writeFileSync(logPath, '');
  for (const w of writes) {
    appendFileSync(logPath, JSON.stringify({
      path: w.path,
      lineCount: w.lines.length,
      storedTotal: w.storedTotal,
      syntheticTotal: w.syntheticTotal,
      mismatch: w.mismatch,
      missingItemIds: w.missing.items,
      missingTransactionIds: w.missing.transactions,
    }) + '\n');
  }
  log(`  Changelog: ${logPath}`);

  if (!commit) {
    log('  DRY-RUN — no writes performed. Re-run with --commit to apply.');
    for (const w of writes.slice(0, 5)) {
      log(`    would write ${w.lines.length} line(s) to ${w.path}` +
          (w.mismatch ? ` (stored=${w.storedTotal} vs synth=${w.syntheticTotal})` : ''));
    }
    if (writes.length > 5) log(`    ...and ${writes.length - 5} more`);
    return { updated: 0 };
  }

  // Commit in batches of 500. Only write `lines` and `updatedAt` — never
  // touch stored `totalCents`, itemIds, or transactionIds.
  let updated = 0;
  for (let i = 0; i < writes.length; i += BATCH_SIZE) {
    const slice = writes.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const w of slice) {
      batch.update(w.ref, {
        lines: w.lines,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    updated += slice.length;
    log(`  Committed batch: ${updated}/${writes.length}`);
  }

  log(`  Done. Backfilled ${updated} invoices. Changelog at ${logPath}`);
  return { updated };
}

async function fetchByIds(collectionRef, ids) {
  const out = new Map();
  if (ids.length === 0) return out;
  const CHUNK = 300;
  for (let i = 0; i < ids.length; i += CHUNK) {
    const slice = ids.slice(i, i + CHUNK);
    const refs = slice.map((id) => collectionRef.doc(id));
    const snaps = await collectionRef.firestore.getAll(...refs);
    for (const snap of snaps) {
      if (snap.exists) out.set(snap.id, snap.data());
    }
  }
  return out;
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

  let totalUpdated = 0;
  for (const id of accountIds) {
    try {
      const { updated } = await processAccount(db, id, args.commit);
      totalUpdated += updated;
    } catch (err) {
      fail(`Account ${id} failed: ${err.stack || err}`);
      process.exitCode = 1;
    }
  }

  log(`FINISHED — ${args.commit ? 'backfilled' : 'would backfill'} ${totalUpdated} invoice(s) across ${accountIds.length} account(s).`);
}

main().catch((err) => {
  fail(err.stack || String(err));
  process.exit(1);
});
