#!/usr/bin/env node
/**
 * Audit and optionally migrate budget categories to canonical categoryType.
 *
 * Defaults to dry-run and writes review artifacts under:
 *   docs/plans/category-type-migration-runs/YYYY-MM-DD/
 *
 * Usage:
 *   node scripts/audit-category-type-migration.mjs --account <id>
 *   node scripts/audit-category-type-migration.mjs --all
 *   node scripts/audit-category-type-migration.mjs --account <id> --commit
 *   node scripts/audit-category-type-migration.mjs --account <id> --commit --remove-legacy-fields
 *
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS or ADC. Use FIRESTORE_EMULATOR_HOST
 * to target the emulator.
 */

import admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const VALID_CATEGORY_TYPES = new Set(['general', 'itemized', 'fee']);
const LEGACY_STANDARD = 'standard';
const BATCH_SIZE = 450;

const REVIEWED_NAME_TARGETS = new Map([
  ['furnishings', { categoryType: 'itemized', reason: 'reviewed target: item rows expected' }],
  ['additional requests', { categoryType: 'itemized', reason: 'reviewed target: usually furnishings/add-ons' }],
  ['kitchen', { categoryType: 'general', reason: 'reviewed target: non-itemized project cost' }],
  ['install services', { categoryType: 'general', reason: 'reviewed target: labor/service cost' }],
  ['install', { categoryType: 'general', reason: 'reviewed target: install labor/service cost' }],
  ['install supplies', { categoryType: 'general', reason: 'reviewed target: supplies stay general' }],
  ['fuel', { categoryType: 'general', reason: 'reviewed target: non-itemized project cost' }],
  ['storage & receiving', { categoryType: 'general', reason: 'reviewed target: non-itemized project cost' }],
  ['storage and receiving', { categoryType: 'general', reason: 'reviewed target: non-itemized project cost' }],
  ['games and entertainment', { categoryType: 'itemized', reason: 'reviewed target: itemized category' }],
  ['design fee', { categoryType: 'fee', reason: 'reviewed target: business revenue/payment category' }],
]);

function parseArgs(argv) {
  const args = {
    account: null,
    all: false,
    commit: false,
    removeLegacyFields: false,
    outputDir: null,
    help: false,
  };

  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--account') args.account = argv[++i];
    else if (arg === '--all') args.all = true;
    else if (arg === '--commit') args.commit = true;
    else if (arg === '--remove-legacy-fields') args.removeLegacyFields = true;
    else if (arg === '--output-dir') args.outputDir = argv[++i];
    else if (arg === '--help' || arg === '-h') args.help = true;
    else {
      console.error(`Unknown arg: ${arg}`);
      process.exit(2);
    }
  }

  return args;
}

function printHelp() {
  console.log(`
Audit and optionally migrate budget categories to canonical metadata.categoryType.

Options:
  --account <id>             Run one account. Required unless --all.
  --all                      Run across every account.
  --commit                   Apply category writes. Omit for dry-run.
  --remove-legacy-fields     With --commit, delete supportedTypes and metadata.itemizationEnabled.
  --output-dir <path>        Override artifact directory.
  --help, -h                 Show this help.

Dry-run first. Review category-audit.json and affected-transactions.json before commit.
`);
}

function log(message) {
  console.log(`\x1b[36m[cat-type]\x1b[0m ${message}`);
}

function fail(message) {
  console.error(`\x1b[31m[cat-type]\x1b[0m ${message}`);
}

function todayString() {
  return new Date().toISOString().slice(0, 10);
}

function normalizeName(value) {
  return String(value ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
}

function normalizeCategoryType(value) {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (normalized === LEGACY_STANDARD || normalized === 'expense') return 'general';
  if (VALID_CATEGORY_TYPES.has(normalized)) return normalized;
  return null;
}

function rawCategoryType(data) {
  const value = data?.metadata?.categoryType;
  return typeof value === 'string' ? value : null;
}

function normalizeSupportedTypes(values) {
  if (!Array.isArray(values)) return [];
  return [...new Set(values.map((value) => String(value).trim().toLowerCase()).filter(Boolean))].sort();
}

function categoryTypeFromSupportedTypes(values) {
  const supported = normalizeSupportedTypes(values);
  if (supported.length === 1 && supported[0] === 'fee') return 'fee';
  if (supported.length === 1 && supported[0] === 'expense') return 'general';
  if (supported.length === 2 && supported.includes('purchase') && supported.includes('return')) return 'itemized';
  if (supported.length === 0) return null;
  return null;
}

function sameArray(a, b) {
  if (a.length !== b.length) return false;
  return a.every((value, index) => value === b[index]);
}

function isMixedSupportedTypes(values) {
  return sameArray(normalizeSupportedTypes(values), ['expense', 'purchase', 'return']);
}

function reviewedTargetForName(name) {
  return REVIEWED_NAME_TARGETS.get(normalizeName(name)) ?? null;
}

function proposedCategoryTypeForCategory(data) {
  const reviewed = reviewedTargetForName(data?.name);
  if (reviewed) return reviewed;

  const metadataType = normalizeCategoryType(rawCategoryType(data));
  if (metadataType) {
    return { categoryType: metadataType, reason: 'existing valid metadata.categoryType' };
  }

  const supportedType = categoryTypeFromSupportedTypes(data?.supportedTypes);
  if (supportedType) {
    return { categoryType: supportedType, reason: 'temporary derivation from legacy supportedTypes' };
  }

  return { categoryType: 'general', reason: 'default for missing category behavior; needs review if category should be itemized' };
}

function serializeFirestoreValue(value) {
  if (value?.toDate && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(serializeFirestoreValue);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, serializeFirestoreValue(child)]));
  }
  return value ?? null;
}

function initFirestore() {
  if (admin.apps.length) return admin.firestore();

  if (process.env.FIRESTORE_EMULATOR_HOST) {
    log(`Connecting to Firestore emulator at ${process.env.FIRESTORE_EMULATOR_HOST}`);
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

async function listAccountIds(db, args) {
  if (args.account) return [args.account];
  const snap = await db.collection('accounts').get();
  return snap.docs.map((doc) => doc.id);
}

async function fetchCategoryTransactionStats(db, accountId, categoryId, oldType, newType) {
  const snap = await db
    .collection(`accounts/${accountId}/transactions`)
    .where('budgetCategoryId', '==', categoryId)
    .get();

  const transactions = [];
  let incompleteLinkedTransactionCount = 0;
  let completenessWouldChangeCount = 0;
  let itemizedLinkedTransactionCount = 0;

  for (const doc of snap.docs) {
    const tx = doc.data() ?? {};
    const itemIds = Array.isArray(tx.itemIds) ? tx.itemIds : [];
    if (itemIds.length > 0) itemizedLinkedTransactionCount++;
    if (tx.isComplete === false) incompleteLinkedTransactionCount++;

    const type = String(tx.type ?? tx.transactionType ?? '').trim().toLowerCase();
    const oldRequiresItemAudit = (type === 'purchase' || type === 'return') && oldType === 'itemized';
    const newRequiresItemAudit = (type === 'purchase' || type === 'return') && newType === 'itemized';
    const oldWouldBeComplete = oldRequiresItemAudit ? tx.isComplete !== false : true;
    const newWouldBeComplete = newRequiresItemAudit ? tx.isComplete !== false : true;

    if (oldWouldBeComplete !== newWouldBeComplete || oldRequiresItemAudit !== newRequiresItemAudit) {
      completenessWouldChangeCount++;
      transactions.push({
        transactionId: doc.id,
        path: doc.ref.path,
        projectId: tx.projectId ?? null,
        source: tx.source ?? null,
        categoryId,
        type: tx.type ?? tx.transactionType ?? null,
        oldResolvedCategoryType: oldType,
        newCategoryType: newType,
        oldIsComplete: tx.isComplete ?? null,
        proposedIsComplete: newRequiresItemAudit ? tx.isComplete ?? null : true,
        itemIdsCount: itemIds.length,
        amountCents: tx.amountCents ?? null,
        subtotalCents: tx.subtotalCents ?? null,
        taxRatePct: tx.taxRatePct ?? null,
        reason: newRequiresItemAudit
          ? 'itemized category requires item/audit completeness'
          : 'general/fee category does not require item rows',
      });
    }
  }

  return {
    linkedTransactionCount: snap.size,
    incompleteLinkedTransactionCount,
    itemizedLinkedTransactionCount,
    completenessWouldChangeCount,
    transactions,
  };
}

async function auditAccount(db, accountId) {
  log(`Auditing account ${accountId}`);
  const categoriesSnap = await db
    .collection(`accounts/${accountId}/presets/default/budgetCategories`)
    .get();

  const categoryAudit = [];
  const accountTargetsById = new Map();
  const affectedTransactions = [];
  const backups = [];
  const counters = {
    categoryCount: categoriesSnap.size,
    categoriesNeedingWrite: 0,
    categoriesWithSupportedTypes: 0,
    categoriesWithMixedSupportedTypes: 0,
    categoriesMissingCategoryType: 0,
    categoriesWithLegacyStandard: 0,
    categoriesWithItemizationEnabled: 0,
    affectedTransactionCount: 0,
  };

  for (const doc of categoriesSnap.docs) {
    const data = doc.data() ?? {};
    const currentRawType = rawCategoryType(data);
    const currentNormalizedType = normalizeCategoryType(currentRawType);
    const supportedTypes = normalizeSupportedTypes(data.supportedTypes);
    const legacySupportedType = categoryTypeFromSupportedTypes(data.supportedTypes);
    const oldResolvedType = currentNormalizedType ?? legacySupportedType ?? 'general';
    const proposed = proposedCategoryTypeForCategory(data);
    const hasSupportedTypes = Array.isArray(data.supportedTypes);
    const hasItemizationEnabled = data.metadata?.itemizationEnabled !== undefined;
    const isLegacyStandard = String(currentRawType ?? '').trim().toLowerCase() === LEGACY_STANDARD;
    const categoryNeedsCanonicalWrite = currentNormalizedType !== proposed.categoryType || isLegacyStandard;
    const categoryHasLegacyFields = hasSupportedTypes || hasItemizationEnabled;
    const needsWrite = categoryNeedsCanonicalWrite || categoryHasLegacyFields;
    accountTargetsById.set(doc.id, {
      name: data.name ?? null,
      proposedCategoryType: proposed.categoryType,
    });

    if (needsWrite) counters.categoriesNeedingWrite++;
    if (hasSupportedTypes) counters.categoriesWithSupportedTypes++;
    if (isMixedSupportedTypes(data.supportedTypes)) counters.categoriesWithMixedSupportedTypes++;
    if (!currentRawType) counters.categoriesMissingCategoryType++;
    if (isLegacyStandard) counters.categoriesWithLegacyStandard++;
    if (hasItemizationEnabled) counters.categoriesWithItemizationEnabled++;

    const txStats = await fetchCategoryTransactionStats(
      db,
      accountId,
      doc.id,
      oldResolvedType,
      proposed.categoryType
    );
    affectedTransactions.push(...txStats.transactions);

    categoryAudit.push({
      accountId,
      categoryId: doc.id,
      path: doc.ref.path,
      name: data.name ?? null,
      currentMetadataCategoryType: currentRawType,
      currentResolvedCategoryType: oldResolvedType,
      currentSupportedTypes: supportedTypes,
      hasItemizationEnabled,
      proposedCategoryType: proposed.categoryType,
      proposedRemoveSupportedTypes: hasSupportedTypes,
      proposedRemoveItemizationEnabled: hasItemizationEnabled,
      linkedTransactionCount: txStats.linkedTransactionCount,
      incompleteLinkedTransactionCount: txStats.incompleteLinkedTransactionCount,
      itemizedLinkedTransactionCount: txStats.itemizedLinkedTransactionCount,
      completenessWouldChangeCount: txStats.completenessWouldChangeCount,
      needsWrite,
      reason: proposed.reason,
      risk: riskForCategory({
        currentType: oldResolvedType,
        proposedType: proposed.categoryType,
        supportedTypes,
        linkedTransactionCount: txStats.linkedTransactionCount,
        completenessWouldChangeCount: txStats.completenessWouldChangeCount,
      }),
    });

    if (needsWrite) {
      backups.push({
        accountId,
        categoryId: doc.id,
        path: doc.ref.path,
        data: serializeFirestoreValue(data),
      });
    }
  }

  const projectCategoryAudit = await auditProjectCategoryCopies(db, accountId, accountTargetsById);

  counters.affectedTransactionCount = affectedTransactions.length;
  counters.projectCategoryCopiesWithBehaviorFields = projectCategoryAudit.length;
  return { categoryAudit, projectCategoryAudit, affectedTransactions, backups, counters };
}

async function auditProjectCategoryCopies(db, accountId, accountTargetsById) {
  const rows = [];
  const projectsSnap = await db.collection(`accounts/${accountId}/projects`).get();

  for (const projectDoc of projectsSnap.docs) {
    const copiesSnap = await projectDoc.ref.collection('budgetCategories').get();
    for (const copyDoc of copiesSnap.docs) {
      const data = copyDoc.data() ?? {};
      const currentMetadataCategoryType = rawCategoryType(data);
      const currentDirectCategoryType = typeof data.categoryType === 'string' ? data.categoryType : null;
      const currentSupportedTypes = normalizeSupportedTypes(data.supportedTypes);
      const hasBehaviorFields =
        currentMetadataCategoryType !== null ||
        currentDirectCategoryType !== null ||
        currentSupportedTypes.length > 0 ||
        data.metadata?.itemizationEnabled !== undefined;

      if (!hasBehaviorFields) continue;

      const accountTarget = accountTargetsById.get(copyDoc.id) ?? null;
      rows.push({
        accountId,
        projectId: projectDoc.id,
        categoryId: copyDoc.id,
        path: copyDoc.ref.path,
        name: data.name ?? accountTarget?.name ?? null,
        currentMetadataCategoryType,
        currentDirectCategoryType,
        currentSupportedTypes,
        hasItemizationEnabled: data.metadata?.itemizationEnabled !== undefined,
        accountLevelProposedCategoryType: accountTarget?.proposedCategoryType ?? null,
        recommendation: accountTarget
          ? 'remove project-level behavior fields and resolve through account-level category'
          : 'review orphan project category behavior fields',
      });
    }
  }

  return rows;
}

function riskForCategory({ currentType, proposedType, supportedTypes, linkedTransactionCount, completenessWouldChangeCount }) {
  if (supportedTypes.includes('expense') && supportedTypes.includes('purchase') && supportedTypes.includes('return')) return 'review';
  if (currentType !== proposedType && linkedTransactionCount > 0) return 'review';
  if (completenessWouldChangeCount > 0) return 'review';
  return 'low';
}

function buildSummary({ mode, args, accountIds, countersByAccount, categoryAudit, projectCategoryAudit, affectedTransactions }) {
  const totals = Object.values(countersByAccount).reduce((acc, value) => {
    for (const [key, count] of Object.entries(value)) {
      acc[key] = (acc[key] ?? 0) + count;
    }
    return acc;
  }, {});

  const byProposedType = {};
  for (const row of categoryAudit) {
    byProposedType[row.proposedCategoryType] = (byProposedType[row.proposedCategoryType] ?? 0) + 1;
  }

  const reviewRows = categoryAudit.filter((row) => row.risk !== 'low' || row.needsWrite);
  const lines = [
    '# Category Type Migration Run',
    '',
    `Mode: ${mode}`,
    `Project: ${PROJECT_ID}`,
    `Accounts: ${accountIds.length}`,
    `Remove legacy fields on commit: ${args.removeLegacyFields ? 'yes' : 'no'}`,
    '',
    '## Totals',
    '',
    `- Categories scanned: ${totals.categoryCount ?? 0}`,
    `- Categories needing write: ${totals.categoriesNeedingWrite ?? 0}`,
    `- Categories with supportedTypes: ${totals.categoriesWithSupportedTypes ?? 0}`,
    `- Categories with mixed supportedTypes: ${totals.categoriesWithMixedSupportedTypes ?? 0}`,
    `- Categories missing metadata.categoryType: ${totals.categoriesMissingCategoryType ?? 0}`,
    `- Categories with legacy standard: ${totals.categoriesWithLegacyStandard ?? 0}`,
    `- Categories with itemizationEnabled: ${totals.categoriesWithItemizationEnabled ?? 0}`,
    `- Project category copies with behavior fields: ${totals.projectCategoryCopiesWithBehaviorFields ?? 0}`,
    `- Affected transactions: ${affectedTransactions.length}`,
    '',
    '## Proposed Category Types',
    '',
    ...Object.entries(byProposedType).sort().map(([type, count]) => `- ${type}: ${count}`),
    '',
    '## Review Rows',
    '',
    ...reviewRows.slice(0, 50).map((row) => (
      `- ${row.name ?? row.categoryId} (${row.accountId}): ${row.currentResolvedCategoryType} -> ${row.proposedCategoryType}; ` +
      `tx=${row.linkedTransactionCount}; completeness changes=${row.completenessWouldChangeCount}; risk=${row.risk}; ${row.reason}`
    )),
  ];

  if (reviewRows.length > 50) lines.push(`- ...and ${reviewRows.length - 50} more review rows`);
  lines.push('');
  return lines.join('\n');
}

async function applyCategoryWrites(db, categoryAudit, { removeLegacyFields }) {
  const candidates = categoryAudit.filter((row) => row.needsWrite);
  let written = 0;

  for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const slice = candidates.slice(i, i + BATCH_SIZE);
    for (const row of slice) {
      const update = {
        'metadata.categoryType': row.proposedCategoryType,
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (removeLegacyFields) {
        update.supportedTypes = FieldValue.delete();
        update['metadata.itemizationEnabled'] = FieldValue.delete();
      }
      batch.update(db.doc(row.path), update);
    }
    await batch.commit();
    written += slice.length;
    log(`Committed category batch ${written}/${candidates.length}`);
  }

  return written;
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printHelp();
    return;
  }
  if (!args.account && !args.all) {
    fail('Must specify --account <id> or --all.');
    printHelp();
    process.exit(2);
  }
  if (args.account && args.all) {
    fail('--account and --all are mutually exclusive.');
    process.exit(2);
  }
  if (args.removeLegacyFields && !args.commit) {
    fail('--remove-legacy-fields only makes sense with --commit.');
    process.exit(2);
  }

  const outputDir = args.outputDir ?? join('docs', 'plans', 'category-type-migration-runs', todayString());
  mkdirSync(outputDir, { recursive: true });

  const db = initFirestore();
  const accountIds = await listAccountIds(db, args);
  const categoryAudit = [];
  const projectCategoryAudit = [];
  const affectedTransactions = [];
  const backups = [];
  const countersByAccount = {};

  for (const accountId of accountIds) {
    const result = await auditAccount(db, accountId);
    categoryAudit.push(...result.categoryAudit);
    projectCategoryAudit.push(...result.projectCategoryAudit);
    affectedTransactions.push(...result.affectedTransactions);
    backups.push(...result.backups);
    countersByAccount[accountId] = result.counters;
  }

  const mode = args.commit ? 'commit' : 'dry-run';
  let writeResults = null;
  if (args.commit) {
    writeResults = {
      writtenCategoryCount: await applyCategoryWrites(db, categoryAudit, {
        removeLegacyFields: args.removeLegacyFields,
      }),
      removedLegacyFields: args.removeLegacyFields,
    };
  }

  const summary = buildSummary({
    mode,
    args,
    accountIds,
    countersByAccount,
    categoryAudit,
    projectCategoryAudit,
    affectedTransactions,
  });

  writeFileSync(join(outputDir, 'category-audit.json'), `${JSON.stringify(categoryAudit, null, 2)}\n`);
  writeFileSync(join(outputDir, 'project-category-audit.json'), `${JSON.stringify(projectCategoryAudit, null, 2)}\n`);
  writeFileSync(join(outputDir, 'affected-transactions.json'), `${JSON.stringify(affectedTransactions, null, 2)}\n`);
  writeFileSync(join(outputDir, 'backups-manifest.json'), `${JSON.stringify(backups, null, 2)}\n`);
  writeFileSync(join(outputDir, 'summary.md'), summary);
  if (writeResults) {
    writeFileSync(join(outputDir, 'write-results.json'), `${JSON.stringify(writeResults, null, 2)}\n`);
  }

  log(`Saved artifacts to ${outputDir}`);
  log(`${mode === 'commit' ? 'Wrote' : 'Would write'} ${categoryAudit.filter((row) => row.needsWrite).length} categories.`);
  log(`Affected transaction rows for review: ${affectedTransactions.length}`);
}

main().catch((error) => {
  fail(error.stack || String(error));
  process.exit(1);
});
