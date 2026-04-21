#!/usr/bin/env node
/**
 * migrate-transactions-to-fee-expense.mjs — Phase 3 Script 1
 *
 * Rewrites legacy `purchase` transactions whose linked budget category is
 * semantically a Fee or Expense category. See docs/plans/transaction-type-migration.md.
 *
 * For each transaction with `type == "purchase"`, load the linked category and
 * apply the taxonomy resolver:
 *   - category supportedTypes == [fee]     → new type = "fee"
 *   - category supportedTypes == [expense] → new type = "expense"
 *   - anything else                        → unchanged
 *
 * Usage:
 *   # Dry-run for a specific account (default — lists candidates, no writes):
 *   node scripts/migrate-transactions-to-fee-expense.mjs --account <id>
 *
 *   # Dry-run all accounts:
 *   node scripts/migrate-transactions-to-fee-expense.mjs --all
 *
 *   # Commit the real run for one account:
 *   node scripts/migrate-transactions-to-fee-expense.mjs --account <id> --commit
 *
 *   # Commit the real run for all accounts:
 *   node scripts/migrate-transactions-to-fee-expense.mjs --all --commit
 *
 * Credentials: uses GOOGLE_APPLICATION_CREDENTIALS env var (path to service
 * account JSON), falling back to ADC. To target the emulator set FIRESTORE_EMULATOR_HOST.
 *
 * Idempotent: re-running against a migrated account reports zero updates.
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
Migrate legacy \`purchase\` transactions to \`fee\` / \`expense\` based on their linked category.

Options:
  --account <id>    Run against one account. Required unless --all.
  --all             Run across every account.
  --commit          Apply writes. Omit for dry-run.
  --help, -h        Show this help.

Dry-run first. Commit after reviewing the candidate distribution.
`);
}

// ─── Logging ──────────────────────────────────────────────────────────────────

function log(msg) { console.log(`\x1b[36m[migrate-tx]\x1b[0m ${msg}`); }
function warn(msg) { console.warn(`\x1b[33m[migrate-tx]\x1b[0m ${msg}`); }
function fail(msg) { console.error(`\x1b[31m[migrate-tx]\x1b[0m ${msg}`); }

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

// ─── Taxonomy resolver (mirrors Swift TransactionTaxonomy.resolve) ───────────

/**
 * Derive supportedTypes from a category document, preferring the explicit
 * `supportedTypes` field and falling back to `metadata.categoryType` for
 * legacy docs. Mirrors Swift `BudgetCategory.resolvedSupportedTypes`.
 */
function resolvedSupportedTypes(categoryData) {
  const explicit = categoryData?.supportedTypes;
  if (Array.isArray(explicit) && explicit.length > 0) return explicit.map(String);
  const t = categoryData?.metadata?.categoryType;
  switch (t) {
    case 'fee': return ['fee'];
    case 'expense': return ['expense'];
    case 'itemized': return ['purchase', 'return'];
    case 'general': return ['expense'];
    default: return ['purchase', 'return'];
  }
}

function arrayEquals(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

/**
 * Given a stored transaction type and the linked category (may be undefined),
 * return the intended type. Only `purchase` is ever remapped; everything else
 * passes through unchanged.
 */
function resolveType(storedType, categoryData) {
  if (storedType !== 'purchase') return storedType;
  const supported = categoryData ? resolvedSupportedTypes(categoryData) : ['purchase', 'return'];
  if (arrayEquals(supported, ['fee'])) return 'fee';
  if (arrayEquals(supported, ['expense'])) return 'expense';
  return 'purchase';
}

// ─── Per-account migration ────────────────────────────────────────────────────

async function migrateAccount(db, accountId, commit) {
  log(`Processing account ${accountId} (${commit ? 'COMMIT' : 'dry-run'})`);

  // Preload every category for this account. Production data is small enough
  // that we fetch the whole set once and index by ID; avoids O(N) category
  // reads during the per-transaction pass.
  const categoriesSnap = await db
    .collection(`accounts/${accountId}/presets/default/budgetCategories`)
    .get();
  const categoryById = new Map();
  for (const doc of categoriesSnap.docs) categoryById.set(doc.id, doc.data());
  log(`  Loaded ${categoryById.size} categories`);

  // Production data has mixed casing on `type` ("Purchase" vs "purchase" etc.) —
  // Firestore `==` is case-sensitive, so we can't filter server-side. Fetch all
  // transactions and filter client-side by lower-cased type. Also catches and
  // normalizes the casing as a side-effect of the migration.
  const txSnap = await db.collection(`accounts/${accountId}/transactions`).get();
  log(`  Scanning ${txSnap.size} total transactions (all types, all casings)`);

  const distribution = {
    'purchase→purchase': 0,
    'purchase→fee': 0,
    'purchase→expense': 0,
    'case-normalize-only': 0,
    'no-category': 0,
    'missing-category': 0,
    'skipped (non-purchase)': 0,
  };

  const candidates = []; // { ref, oldRawType, oldType, newType, categoryId, caseChangeOnly }

  for (const doc of txSnap.docs) {
    const tx = doc.data();
    const rawType = typeof tx.type === 'string' ? tx.type : '';
    const lowered = rawType.trim().toLowerCase();

    if (lowered !== 'purchase') {
      // Every non-purchase tx still gets casing normalized if needed (Sale/Return).
      if (rawType && rawType !== lowered && ['sale', 'return'].includes(lowered)) {
        distribution['case-normalize-only']++;
        candidates.push({
          ref: doc.ref,
          oldRawType: rawType,
          oldType: rawType,
          newType: lowered,
          categoryId: typeof tx.budgetCategoryId === 'string' ? tx.budgetCategoryId.trim() : '',
          caseChangeOnly: true,
        });
      } else {
        distribution['skipped (non-purchase)']++;
      }
      continue;
    }

    const categoryId = typeof tx.budgetCategoryId === 'string' ? tx.budgetCategoryId.trim() : '';
    let categoryData;
    if (!categoryId) {
      distribution['no-category']++;
    } else {
      categoryData = categoryById.get(categoryId);
      if (!categoryData) distribution['missing-category']++;
    }

    const newType = resolveType('purchase', categoryData);
    distribution[`purchase→${newType}`]++;

    // Case-normalize to lowercase even when resolving to `purchase` (i.e.
    // `"Purchase"` → `"purchase"`). This aligns with Cloud Functions' lowercase
    // comparisons and Swift's case-insensitive decoder.
    const caseChangeOnly = newType === 'purchase' && rawType !== 'purchase';
    if (caseChangeOnly) distribution['case-normalize-only']++;

    if (newType !== 'purchase' || caseChangeOnly) {
      candidates.push({
        ref: doc.ref,
        oldRawType: rawType,
        oldType: rawType,
        newType,
        categoryId,
        caseChangeOnly,
      });
    }
  }

  log('  Distribution:');
  for (const [k, v] of Object.entries(distribution)) log(`    ${k}: ${v}`);
  log(`  Candidates to update: ${candidates.length}`);

  if (candidates.length === 0) {
    log('  Nothing to do.');
    return { updated: 0 };
  }

  // Open changelog file. Every candidate (dry-run or commit) is recorded as
  // JSONL so you can diff, review, or feed into a reverse script.
  mkdirSync(LOG_DIR, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const logPath = join(LOG_DIR, `tx-${accountId}-${commit ? 'commit' : 'dryrun'}-${ts}.jsonl`);
  writeFileSync(logPath, '');
  for (const c of candidates) {
    appendFileSync(logPath, JSON.stringify({
      path: c.ref.path,
      oldType: c.oldType,
      newType: c.newType,
      categoryId: c.categoryId,
    }) + '\n');
  }
  log(`  Changelog: ${logPath}`);

  if (!commit) {
    log('  DRY-RUN — no writes performed. Re-run with --commit to apply.');
    for (const c of candidates.slice(0, 10)) {
      log(`    would update ${c.ref.path}: ${c.oldType} → ${c.newType} (cat=${c.categoryId})`);
    }
    if (candidates.length > 10) log(`    ...and ${candidates.length - 10} more`);
    return { updated: 0 };
  }

  // Commit in batches of 500. Each update also stashes the previous type in
  // `_migrationPreviousType` so a reverse pass can restore without the export.
  let updated = 0;
  for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
    const slice = candidates.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const c of slice) {
      batch.update(c.ref, {
        type: c.newType,
        _migrationPreviousType: c.oldType,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    updated += slice.length;
    log(`  Committed batch: ${updated}/${candidates.length}`);
  }

  log(`  Done. Updated ${updated} transactions. Changelog at ${logPath}`);
  return { updated };
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
