#!/usr/bin/env node
/**
 * migrate-categories-add-supported-types.mjs — Phase 3 Script 2
 *
 * Populates the new `supportedTypes: string[]` field on every budget category
 * by deriving it from the legacy `metadata.categoryType`. Does NOT touch
 * `metadata.categoryType` — Cloud Functions still read it (see Phase 4).
 *
 * Mapping (matches docs/specs/transaction-type.md):
 *   fee      → ["fee"]
 *   expense  → ["expense"]
 *   general  → ["expense"]
 *   itemized → ["purchase", "return"]
 *   (missing/unknown) → ["purchase", "return"]  // same default as resolver
 *
 * Usage:
 *   node scripts/migrate-categories-add-supported-types.mjs --account <id>
 *   node scripts/migrate-categories-add-supported-types.mjs --all
 *   node scripts/migrate-categories-add-supported-types.mjs --account <id> --commit
 *   node scripts/migrate-categories-add-supported-types.mjs --all --commit
 *
 * Credentials: uses GOOGLE_APPLICATION_CREDENTIALS env var (path to service
 * account JSON), falling back to ADC. To target the emulator set FIRESTORE_EMULATOR_HOST.
 *
 * Idempotent: categories already carrying a non-empty `supportedTypes` are skipped.
 */

import admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';
import { readFileSync } from 'node:fs';

const BATCH_SIZE = 500;
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const VALID_TYPES = new Set(['fee', 'expense', 'purchase', 'return']);

function parseArgs(argv) {
  const args = { commit: false, all: false, account: null, overrides: null, help: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--commit') args.commit = true;
    else if (a === '--all') args.all = true;
    else if (a === '--account') args.account = argv[++i];
    else if (a === '--overrides') args.overrides = argv[++i];
    else if (a === '--help' || a === '-h') args.help = true;
    else {
      console.error(`Unknown arg: ${a}`);
      process.exit(2);
    }
  }
  return args;
}

function loadOverrides(path) {
  if (!path) return {};
  const raw = JSON.parse(readFileSync(path, 'utf8'));
  const cleaned = {};
  // Keys prefixed with `_` are comments (e.g. "_install"). Skip them.
  for (const [k, v] of Object.entries(raw)) {
    if (k.startsWith('_')) continue;
    if (!Array.isArray(v) || v.length === 0) throw new Error(`Overrides: ${k} must be a non-empty array`);
    for (const t of v) {
      if (!VALID_TYPES.has(t)) throw new Error(`Overrides: ${k} has unknown type '${t}'. Valid: fee | expense | purchase | return`);
    }
    cleaned[k] = v;
  }
  return cleaned;
}

function printHelp() {
  console.log(`
Add \`supportedTypes\` to every budget category. Additive-only — does not clear
\`metadata.categoryType\` (that happens in Phase 4 after Cloud Functions migrate).

Options:
  --account <id>          Run against one account. Required unless --all.
  --all                   Run across every account.
  --overrides <path>      JSON file mapping { categoryId: ["purchase","return","expense"] }.
                          Unknown IDs fall through to the legacy-derivation default.
                          See docs/plans/transaction-type-migration.md §Script 2.
  --commit                Apply writes. Omit for dry-run.
  --help, -h              Show this help.
`);
}

function log(msg) { console.log(`\x1b[36m[migrate-cat]\x1b[0m ${msg}`); }
function fail(msg) { console.error(`\x1b[31m[migrate-cat]\x1b[0m ${msg}`); }

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

/**
 * Derive supportedTypes for a legacy category. Same mapping as the Swift-side
 * `BudgetCategory.resolvedSupportedTypes` fallback AND the Cloud Functions
 * helper. Missing/unknown → Mixed (widest safe default).
 */
function deriveSupportedTypes(metadataCategoryType) {
  switch (metadataCategoryType) {
    case 'fee': return ['fee'];
    case 'expense': return ['expense'];
    case 'general': return ['expense'];
    case 'itemized': return ['purchase', 'return'];
    default: return ['purchase', 'return', 'expense'];
  }
}

async function migrateAccount(db, accountId, commit, overrides) {
  log(`Processing account ${accountId} (${commit ? 'COMMIT' : 'dry-run'})`);

  const catsSnap = await db
    .collection(`accounts/${accountId}/presets/default/budgetCategories`)
    .get();
  log(`  Loaded ${catsSnap.size} categories`);

  const distribution = {};
  const candidates = []; // { ref, supportedTypes, sourceLabel }
  let alreadyMigrated = 0;

  for (const doc of catsSnap.docs) {
    const data = doc.data() ?? {};
    const existing = data.supportedTypes;
    if (Array.isArray(existing) && existing.length > 0) {
      alreadyMigrated++;
      continue;
    }

    const legacy = data?.metadata?.categoryType ?? '(missing)';
    const override = overrides[doc.id];
    const supported = override ?? deriveSupportedTypes(data?.metadata?.categoryType);
    const source = override ? `override` : legacy;
    const key = `${source} → [${supported.join(', ')}]`;
    distribution[key] = (distribution[key] ?? 0) + 1;
    candidates.push({ ref: doc.ref, supportedTypes: supported, sourceLabel: source });
  }

  log(`  Already migrated (supportedTypes present): ${alreadyMigrated}`);
  log('  Distribution for candidates:');
  for (const [k, v] of Object.entries(distribution)) log(`    ${k}: ${v}`);
  log(`  Candidates to update: ${candidates.length}`);

  if (candidates.length === 0) {
    log('  Nothing to do.');
    return { updated: 0 };
  }

  if (!commit) {
    log('  DRY-RUN — no writes performed. Re-run with --commit to apply.');
    for (const c of candidates.slice(0, 10)) {
      log(`    would update ${c.ref.path}: supportedTypes=[${c.supportedTypes.join(',')}] (was ${c.sourceLabel})`);
    }
    if (candidates.length > 10) log(`    ...and ${candidates.length - 10} more`);
    return { updated: 0 };
  }

  let updated = 0;
  for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
    const slice = candidates.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const c of slice) {
      batch.update(c.ref, {
        supportedTypes: c.supportedTypes,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    updated += slice.length;
    log(`  Committed batch: ${updated}/${candidates.length}`);
  }

  log(`  Done. Updated ${updated} categories.`);
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

  const overrides = loadOverrides(args.overrides);
  if (args.overrides) log(`Loaded ${Object.keys(overrides).length} overrides from ${args.overrides}`);

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
      const { updated } = await migrateAccount(db, id, args.commit, overrides);
      totalUpdated += updated;
    } catch (err) {
      fail(`Account ${id} failed: ${err.stack || err}`);
      process.exitCode = 1;
    }
  }

  log(`FINISHED — ${args.commit ? 'updated' : 'would update'} ${totalUpdated} categories across ${accountIds.length} account(s).`);
}

main().catch((err) => {
  fail(err.stack || String(err));
  process.exit(1);
});
