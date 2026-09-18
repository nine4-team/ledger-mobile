#!/usr/bin/env node

/**
 * Consolidate Witzenman's inventory-movement transactions into up to three
 * active transactions:
 *
 *   - one Purchase for business inventory -> project
 *   - one Return for inventory-origin items -> business inventory
 *   - one Sale for project-origin items -> business inventory
 *
 * By default, the old transactions are retained as canceled records for
 * auditability. With --commit --delete-originals --backup <path>, the old
 * transaction documents are physically deleted only after a verified local
 * backup is written and all references are reassigned. Their item membership
 * is consolidated into the replacement transaction. No new movement edges
 * are intentionally created; historical lineage edges are reassigned so
 * returned/sold history remains visible.
 *
 * Dry-run:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json \
 *     node scripts/consolidate-witzenman-inventory-transactions.mjs
 *
 * Commit (review the dry-run output first):
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json \
 *     node scripts/consolidate-witzenman-inventory-transactions.mjs \
 *     --commit --delete-originals \
 *     --backup /absolute/path/witzenman-consolidation-backup.json
 *
 * The script is intentionally conservative. It stops when a consolidation
 * group has multiple budget categories or inventory labels, when item links
 * do not match the source transactions, or when required documents are
 * missing. Sale and Return groups remain separate because they have different
 * accounting meanings.
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import admin from 'firebase-admin';

const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const DEFAULT_ACCOUNT_ID = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const DEFAULT_PROJECT_ID = '5abd46c9-9886-4b3e-b2b1-19f6cf995a44';
const DEFAULT_PROJECT_NAME = "Witzenman's 2nd Home";
const CONSOLIDATION_VERSION = 'witzenman-inventory-consolidation-v1';
const MAX_TRANSACTION_WRITES = 500;
const AUDIT_LINEAGE_KINDS = new Set(['returned', 'sold', 'soldToInventory']);

function fail(message) {
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function parseArgs(argv) {
  const result = {
    accountId: DEFAULT_ACCOUNT_ID,
    projectId: DEFAULT_PROJECT_ID,
    projectName: null,
    commit: false,
    backupOnly: false,
    deleteOriginals: false,
    backupPath: null,
    sourceLabel: null,
    transactionDate: null,
    help: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--account') result.accountId = argv[++index];
    else if (arg === '--project-id') result.projectId = argv[++index];
    else if (arg === '--project-name') {
      result.projectName = argv[++index];
      result.projectId = null;
    } else if (arg === '--source-label') result.sourceLabel = argv[++index];
    else if (arg === '--date') result.transactionDate = argv[++index];
    else if (arg === '--commit') result.commit = true;
    else if (arg === '--backup-only') result.backupOnly = true;
    else if (arg === '--delete-originals') result.deleteOriginals = true;
    else if (arg === '--backup') result.backupPath = argv[++index];
    else if (arg === '--help' || arg === '-h') result.help = true;
    else fail(`Unknown argument: ${arg}`);
  }

  if (result.transactionDate && !/^\d{4}-\d{2}-\d{2}$/.test(result.transactionDate)) {
    fail('--date must be YYYY-MM-DD');
  }
  if (result.commit && !result.backupPath) {
    fail('--commit requires --backup <path>');
  }
  if (result.backupOnly && result.commit) {
    fail('--backup-only cannot be combined with --commit');
  }
  if (result.backupOnly && !result.backupPath) {
    fail('--backup-only requires --backup <path>');
  }
  if (result.projectName && result.projectId) {
    fail('--project-id and --project-name are mutually exclusive');
  }
  return result;
}

function printHelp() {
  console.log(`
Consolidate Witzenman's inventory movement transactions.

Defaults:
  account:     ${DEFAULT_ACCOUNT_ID}
  project:     ${DEFAULT_PROJECT_NAME} (${DEFAULT_PROJECT_ID})

Options:
  --account <id>              Account ID override.
  --project-id <id>           Project ID override.
  --project-name <name>       Resolve an exact project name instead of using the default ID.
  --source-label <label>      Replacement transaction source; required when old labels differ.
  --date <YYYY-MM-DD>         Replacement transaction date; defaults to the latest source date.
  --commit                    Apply the reviewed plan. Omit for dry-run.
  --backup-only               Create and verify the backup without changing Firebase; requires --backup <path>.
  --delete-originals          Preview deletion in a dry-run; with --commit, delete originals only after backup and reference rewrites.
  --backup <path>             Required with --commit or --backup-only; backup is created with exclusive write.
  --help, -h                  Show this help.

The script never uses the Firebase emulator. Default commit mode retains old
transactions as canceled records. Delete mode requires --commit and --backup,
and backs up original transactions, changed items, and every affected lineage
edge before deleting anything.
`);
}

function log(message) {
  console.log(`\x1b[36m[witzenman-consolidation]\x1b[0m ${message}`);
}

function normalizeText(value) {
  return String(value ?? '').trim();
}

function normalizeName(value) {
  return normalizeText(value).toLocaleLowerCase();
}

function transactionType(data) {
  return normalizeText(data?.type ?? data?.transactionType).toLowerCase();
}

function isCanceled(data) {
  return normalizeText(data?.status).toLowerCase() === 'canceled';
}

function isDeleted(data) {
  return data?.deletedAt != null;
}

function isActive(data) {
  return !isCanceled(data) && !isDeleted(data);
}

function isInventorySource(value) {
  return normalizeText(value).toLowerCase().endsWith(' inventory');
}

function canonicalDirection(data) {
  if (data?.isCanonicalInventorySale !== true) return null;
  const direction = normalizeText(data.inventorySaleDirection).toLowerCase();
  if (direction === 'business_to_project' || direction === 'project_to_business') {
    return direction;
  }
  return null;
}

/**
 * Return the accounting direction for a transaction, or null when the record
 * is not an inventory movement that this script should touch.
 */
export function classifyTransaction(data) {
  const legacyDirection = canonicalDirection(data);
  if (legacyDirection === 'business_to_project') {
    return { direction: 'inbound', outboundType: null, reason: 'legacy canonical sale' };
  }
  if (legacyDirection === 'project_to_business') {
    return { direction: 'outbound', outboundType: 'sale', reason: 'legacy canonical sale' };
  }

  if (!isInventorySource(data?.source)) return null;

  const type = transactionType(data);
  if (type === 'purchase') {
    return { direction: 'inbound', outboundType: null, reason: 'inventory Purchase' };
  }
  if (type === 'sale') {
    return { direction: 'outbound', outboundType: 'sale', reason: 'inventory Sale' };
  }
  if (type === 'return') {
    return { direction: 'outbound', outboundType: 'return', reason: 'inventory Return' };
  }
  return null;
}

function cents(value, field, transactionId) {
  assert(Number.isInteger(value), `${transactionId} has invalid ${field}: ${value}`);
  assert(value >= 0 || field === 'amountCents', `${transactionId} has invalid ${field}: ${value}`);
  return Math.abs(value);
}

function itemIdsFor(data, transactionId) {
  assert(Array.isArray(data.itemIds), `${transactionId} is missing itemIds; refusing to consolidate it`);
  const ids = [...new Set(data.itemIds.map(normalizeText).filter(Boolean))];
  assert(ids.length > 0, `${transactionId} has no itemIds; refusing to consolidate it`);
  return ids;
}

function dateFromValue(value) {
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  if (value instanceof admin.firestore.Timestamp) return value.toDate().toISOString().slice(0, 10);
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return null;
}

function effectiveDate(data) {
  return dateFromValue(data?.transactionDate) || dateFromValue(data?.createdAt);
}

function todayUtc() {
  return new Date().toISOString().slice(0, 10);
}

function appendNote(existing, note) {
  return [normalizeText(existing), note].filter(Boolean).join('\n\n');
}

function stableJson(value) {
  return JSON.stringify(value, (_key, current) => {
    if (current instanceof admin.firestore.Timestamp) {
      return { __type: 'timestamp', seconds: current.seconds, nanoseconds: current.nanoseconds };
    }
    if (current instanceof Date) return current.toISOString();
    return current;
  });
}

function snapshotRecord(snapshot) {
  return {
    path: snapshot.ref.path,
    id: snapshot.id,
    createTime: snapshot.createTime?.toDate().toISOString() ?? null,
    updateTime: snapshot.updateTime?.toDate().toISOString() ?? null,
    data: snapshot.data(),
  };
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function consolidationKey(projectId) {
  return `${CONSOLIDATION_VERSION}:${projectId}`;
}

function replacementId(projectId, direction, outboundType = null) {
  const suffix = direction === 'outbound' ? `outbound_${outboundType}` : 'inbound';
  return `CONSOLIDATED_${projectId}_${suffix}`;
}

function projectSpendCents(transactionDocs) {
  return transactionDocs.reduce((total, snapshot) => {
    const data = snapshot.data();
    if (!isActive(data) || !data.budgetCategoryId) return total;

    const amount = Number(data.amountCents);
    if (!Number.isFinite(amount)) return total;

    const legacyDirection = canonicalDirection(data);
    if (legacyDirection === 'project_to_business') return total - Math.abs(amount);
    if (legacyDirection === 'business_to_project') return total + Math.abs(amount);

    const type = transactionType(data);
    return total + (type === 'sale' || type === 'return' ? -Math.abs(amount) : Math.abs(amount));
  }, 0);
}

function chunk(values, size) {
  const chunks = [];
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }
  return chunks;
}

async function loadLineageSnapshots(db, accountId, transactionIds) {
  if (transactionIds.length === 0) return [];

  const collection = db.collection(`accounts/${accountId}/lineageEdges`);
  const queries = chunk(transactionIds, 30).flatMap((ids) => [
    collection.where('fromTransactionId', 'in', ids).get(),
    collection.where('toTransactionId', 'in', ids).get(),
  ]);
  const snapshots = await Promise.all(queries);
  const unique = new Map();
  for (const query of snapshots) {
    for (const snapshot of query.docs) unique.set(snapshot.id, snapshot);
  }
  return [...unique.values()];
}

function resolveProjectSnapshot(db, accountId, projectId, projectName) {
  if (projectId) {
    return db.doc(`accounts/${accountId}/projects/${projectId}`).get();
  }

  return db.collection(`accounts/${accountId}/projects`).get().then((snapshot) => {
    const matches = snapshot.docs.filter((doc) => normalizeName(doc.data()?.name) === normalizeName(projectName));
    assert(matches.length === 1,
      `Expected exactly one project named ${JSON.stringify(projectName)}, found ${matches.length}`);
    return matches[0];
  });
}

function chooseUnique(values, label, override = null) {
  if (override) return override;
  const normalized = values.map(normalizeText);
  assert(normalized.every(Boolean), `${label} is missing on one or more source transactions`);
  const unique = [...new Set(normalized)].sort();
  assert(unique.length === 1, `${label} is ambiguous: ${unique.join(', ') || '(missing)'}`);
  return unique[0];
}

function describeDirection(direction) {
  return direction === 'inbound' ? 'inventory -> project' : 'project -> inventory';
}

function validateItemLinks(direction, itemSnapshots, sourceTransactionIds, projectId) {
  const expectedProjectId = direction === 'inbound' ? projectId : null;
  const problems = [];

  for (const snapshot of itemSnapshots) {
    const data = snapshot.data() || {};
    const actualProjectId = data.projectId ?? null;
    const transactionId = normalizeText(data.transactionId);
    if (actualProjectId !== expectedProjectId) {
      problems.push(`${snapshot.id}: projectId=${JSON.stringify(actualProjectId)}, expected ${JSON.stringify(expectedProjectId)}`);
    }
    if (!sourceTransactionIds.has(transactionId)) {
      problems.push(`${snapshot.id}: transactionId=${JSON.stringify(transactionId)}, not one of [${[...sourceTransactionIds].join(', ')}]`);
    }
  }

  assert(problems.length === 0,
    `${describeDirection(direction)} has item links that do not match its source transactions:\n  ${problems.join('\n  ')}`);
}

function chooseLineageSnapshots(sourceSnapshots, lineageSnapshots) {
  const sourceIds = new Set(sourceSnapshots.map((snapshot) => snapshot.id));
  const chosen = new Map();

  for (const snapshot of lineageSnapshots) {
    const data = snapshot.data() || {};
    if (!sourceIds.has(data.fromTransactionId)) continue;
    if (!AUDIT_LINEAGE_KINDS.has(normalizeText(data.movementKind))) continue;
    if (data.deletedAt != null || !normalizeText(data.itemId)) continue;

    // Duplicate app/server edges can exist for one historical movement. Keep
    // one edge per source transaction, item, and audit movement kind; the new
    // transaction only needs one edge for the audit resolver to find it.
    const key = `${data.fromTransactionId}|${data.itemId}|${data.movementKind}`;
    const existing = chosen.get(key);
    const currentDate = data.createdAt?.toMillis?.() ?? 0;
    const existingDate = existing?.data()?.createdAt?.toMillis?.() ?? 0;
    if (!existing || currentDate >= existingDate) chosen.set(key, snapshot);
  }

  return [...chosen.values()];
}

function buildDirectionPlan(
  direction,
  outboundType,
  sourceSnapshots,
  itemSnapshots,
  lineageSnapshots,
  projectId,
  options,
) {
  if (sourceSnapshots.length === 0) return null;

  const sourceIds = sourceSnapshots.map((snapshot) => snapshot.id);
  const data = sourceSnapshots.map((snapshot) => snapshot.data());
  const categoryId = chooseUnique(data.map((value) => value.budgetCategoryId),
    `${describeDirection(direction)} budgetCategoryId`);
  const sourceLabel = chooseUnique(data.map((value) => value.source),
    `${describeDirection(direction)} source`, options.sourceLabel);

  if (direction === 'outbound') {
    assert(outboundType === 'sale' || outboundType === 'return',
      `Missing outbound type for ${describeDirection(direction)}`);
    assert(data.every((value) => classifyTransaction(value)?.outboundType === outboundType),
      `${describeDirection(direction)} contains a transaction with the wrong outbound type`);
  }

  const rawItemIds = [...new Set(data.flatMap((value) => (
    Array.isArray(value.itemIds) ? value.itemIds.map(normalizeText).filter(Boolean) : []
  )))].sort();
  assert(itemSnapshots.length === rawItemIds.length,
    `${describeDirection(direction)} expected ${rawItemIds.length} item documents, loaded ${itemSnapshots.length}`);

  const lineageToRewire = chooseLineageSnapshots(sourceSnapshots, lineageSnapshots);
  const historicalItemIds = new Set(lineageToRewire.map((snapshot) => normalizeText(snapshot.data()?.itemId)).filter(Boolean));
  const sourceIdSet = new Set(sourceIds);
  const expectedProjectId = direction === 'inbound' ? projectId : null;
  const itemSnapshotsById = new Map(itemSnapshots.map((snapshot) => [snapshot.id, snapshot]));
  const activeItemIds = [];
  const staleItemIds = [];
  for (const itemId of rawItemIds) {
    const itemData = itemSnapshotsById.get(itemId)?.data() || {};
    if ((itemData.projectId ?? null) === expectedProjectId && sourceIdSet.has(normalizeText(itemData.transactionId))) {
      activeItemIds.push(itemId);
    } else {
      staleItemIds.push(itemId);
    }
  }
  assert(staleItemIds.every((itemId) => historicalItemIds.has(itemId)),
    `${describeDirection(direction)} has stale itemIds without matching historical lineage: ${staleItemIds.filter((itemId) => !historicalItemIds.has(itemId)).join(', ')}`);
  validateItemLinks(
    direction,
    activeItemIds.map((itemId) => itemSnapshotsById.get(itemId)),
    sourceIdSet,
    projectId,
  );

  const amountCents = data.reduce((total, value, index) => total + cents(value.amountCents, 'amountCents', sourceIds[index]), 0);
  const subtotalCents = data.reduce((total, value, index) => {
    const subtotal = value.subtotalCents == null ? value.amountCents : value.subtotalCents;
    return total + cents(subtotal, 'subtotalCents', sourceIds[index]);
  }, 0);
  const dates = data.map(effectiveDate).filter(Boolean).sort();
  const transactionDate = options.transactionDate || dates.at(-1) || todayUtc();
  const replacementTransactionId = replacementId(projectId, direction, outboundType);

  return {
    direction,
    sourceTransactionIds: sourceIds,
    sourceSnapshots,
    itemSnapshots,
    itemIds: activeItemIds,
    categoryId,
    sourceLabel,
    outboundType,
    amountCents,
    subtotalCents,
    transactionDate,
    replacementTransactionId,
    signCents: direction === 'inbound' ? amountCents : -amountCents,
    lineageSnapshots: lineageToRewire,
  };
}

function makeReplacementData(plan, projectId, note) {
  const data = {
    type: plan.direction === 'inbound' ? 'Purchase' : plan.outboundType === 'return' ? 'Return' : 'Sale',
    source: plan.sourceLabel,
    projectId,
    budgetCategoryId: plan.categoryId,
    amountCents: plan.amountCents,
    subtotalCents: plan.subtotalCents,
    itemIds: plan.itemIds,
    transactionDate: plan.transactionDate,
    isComplete: true,
    notes: note,
    consolidationVersion: CONSOLIDATION_VERSION,
    consolidationKey: consolidationKey(projectId),
    consolidationDirection: plan.direction,
    consolidatedFromTransactionIds: plan.sourceTransactionIds,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  return data;
}

function makePlan({ projectId, projectName, transactionSnapshots, itemSnapshotsById, lineageSnapshots, options }) {
  const candidates = [];
  const existingConsolidated = [];
  const key = consolidationKey(projectId);

  for (const snapshot of transactionSnapshots) {
    const data = snapshot.data() || {};
    if (data.consolidationKey === key) {
      existingConsolidated.push(snapshot.id);
      continue;
    }
    if (!isActive(data) || data.projectId !== projectId) continue;

    const classification = classifyTransaction(data);
    if (!classification) continue;
    candidates.push({ snapshot, classification });
  }

  const activeExisting = existingConsolidated.filter((id) =>
    transactionSnapshots.find((snapshot) => snapshot.id === id && isActive(snapshot.data())));
  assert(activeExisting.length === 0 || candidates.length === 0,
    `An active consolidation already exists (${activeExisting.join(', ')}), but additional source transactions are also present. Review before running again.`);

  if (candidates.length === 0) {
    return {
      projectId,
      projectName,
      key,
      candidates: [],
      directions: [],
      existingConsolidated,
      beforeSpendCents: projectSpendCents(transactionSnapshots),
      afterSpendCents: projectSpendCents(transactionSnapshots),
      writes: 0,
      lineageEdgesToRewire: [],
      deleteOriginals: options.deleteOriginals,
      backupOnly: options.backupOnly,
      sourceIds: [],
      replacementIds: [],
    };
  }

  const groups = [
    {
      direction: 'inbound',
      outboundType: null,
      sourceSnapshots: candidates
        .filter(({ classification }) => classification.direction === 'inbound')
        .map(({ snapshot }) => snapshot),
    },
    ...['return', 'sale'].map((outboundType) => ({
      direction: 'outbound',
      outboundType,
      sourceSnapshots: candidates
        .filter(({ classification }) => (
          classification.direction === 'outbound' && classification.outboundType === outboundType
        ))
        .map(({ snapshot }) => snapshot),
    })),
  ].filter((group) => group.sourceSnapshots.length > 0);

  const itemIdsByGroup = new Map();
  for (const group of groups) {
    const directionIds = [...new Set(group.sourceSnapshots.flatMap((snapshot) => (
      Array.isArray(snapshot.data()?.itemIds)
        ? snapshot.data().itemIds.map(normalizeText).filter(Boolean)
        : []
    )))].sort();
    itemIdsByGroup.set(`${group.direction}:${group.outboundType || 'inbound'}`, new Set(directionIds));
  }

  const itemOwners = new Map();
  for (const group of groups) {
    const key = `${group.direction}:${group.outboundType || 'inbound'}`;
    for (const itemId of itemIdsByGroup.get(key)) {
      const previous = itemOwners.get(itemId);
      assert(!previous || previous === key,
        `The same current item appears in multiple consolidation groups (${itemId}: ${previous}, ${key}); refusing to choose which transactionId should win.`);
      itemOwners.set(itemId, key);
    }
  }

  const directionPlans = [];
  for (const group of groups) {
    const groupKey = `${group.direction}:${group.outboundType || 'inbound'}`;
    const itemSnapshots = [...itemIdsByGroup.get(groupKey)].map((id) => itemSnapshotsById.get(id));
    assert(itemSnapshots.every(Boolean), `${describeDirection(group.direction)} references a missing item document`);
    directionPlans.push(buildDirectionPlan(
      group.direction,
      group.outboundType,
      group.sourceSnapshots,
      itemSnapshots,
      lineageSnapshots,
      projectId,
      options,
    ));
  }

  const sourceIds = candidates.map(({ snapshot }) => snapshot.id);
  const sourceSet = new Set(sourceIds);
  const plansBySource = directionPlans.flatMap((directionPlan) => directionPlan.sourceSnapshots);
  assert(plansBySource.length === sourceIds.length && plansBySource.every((snapshot) => sourceSet.has(snapshot.id)),
    'Internal planning error: not every candidate was assigned to a direction');

  const replacementIds = new Set(directionPlans.map((directionPlan) => directionPlan.replacementTransactionId));
  const sourceReplacementById = new Map();
  for (const directionPlan of directionPlans) {
    for (const sourceTransactionId of directionPlan.sourceTransactionIds) {
      assert(!sourceReplacementById.has(sourceTransactionId),
        `Internal planning error: source transaction assigned twice (${sourceTransactionId})`);
      sourceReplacementById.set(sourceTransactionId, directionPlan.replacementTransactionId);
    }
  }
  const lineageEdgesToRewire = lineageSnapshots.filter((snapshot) => {
    const data = snapshot.data() || {};
    return sourceReplacementById.has(normalizeText(data.fromTransactionId)) ||
      sourceReplacementById.has(normalizeText(data.toTransactionId));
  });
  const itemWriteCount = directionPlans.reduce((total, directionPlan) => total + directionPlan.itemIds.length, 0);
  const lineageWriteCount = options.deleteOriginals
    ? lineageEdgesToRewire.length
    : directionPlans.reduce((total, directionPlan) => total + directionPlan.lineageSnapshots.length, 0);
  // Delete mode is deliberately staged because all historical references do
  // not fit in one Firestore transaction. The count includes the staged
  // replacement creates and their final activation updates.
  const writes = sourceIds.length + itemWriteCount + lineageWriteCount + (options.deleteOriginals
    ? directionPlans.length * 2
    : directionPlans.length);
  if (!options.deleteOriginals) {
    assert(writes <= MAX_TRANSACTION_WRITES,
      `Consolidation requires ${writes} Firestore writes; the ${MAX_TRANSACTION_WRITES}-write atomic limit would be exceeded.`);
  }

  const beforeSpendCents = projectSpendCents(transactionSnapshots);
  const replacementSpendCents = directionPlans.reduce((total, directionPlan) => total + directionPlan.signCents, 0);
  const sourceSpendCents = candidates.reduce((total, { snapshot }) => total + projectSpendCents([snapshot]), 0);
  const afterSpendCents = beforeSpendCents - sourceSpendCents + replacementSpendCents;
  assert(afterSpendCents === beforeSpendCents,
    `Planned consolidation changes project spend from ${beforeSpendCents} to ${afterSpendCents} cents`);

  const note = [
    `Consolidated by ${CONSOLIDATION_VERSION}.`,
    `Project: ${projectName} (${projectId}).`,
    `Source transactions: ${sourceIds.join(', ')}.`,
    options.deleteOriginals
      ? 'Original transactions will be deleted only after the local backup is verified and all references are reassigned.'
      : 'Original transactions are retained as canceled audit records; no physical movement or new lineage event was created. Historical audit edges are reassigned to the replacement transaction.',
  ].join(' ');

  return {
    projectId,
    projectName,
    key,
    candidates,
    directions: directionPlans.map((directionPlan) => ({
      ...directionPlan,
      note,
      replacementData: makeReplacementData(directionPlan, projectId, note),
    })),
    existingConsolidated,
    beforeSpendCents,
    afterSpendCents,
    writes,
    deleteOriginals: options.deleteOriginals,
    backupOnly: options.backupOnly,
    sourceReplacementById,
    lineageEdgesToRewire,
    sourceIds,
    replacementIds: [...replacementIds],
  };
}

function printPlan(plan) {
  const summary = {
    project: { id: plan.projectId, name: plan.projectName },
    mode: plan.backupOnly
      ? 'backup-only-delete-originals'
      : plan.deleteOriginals ? 'dry-run-delete-originals' : 'dry-run-cancel-originals',
    sourceTransactionCount: plan.candidates.length,
    sourceTransactionIds: plan.sourceIds || [],
    directions: plan.directions.map((directionPlan) => ({
      direction: directionPlan.direction,
      replacementTransactionId: directionPlan.replacementTransactionId,
      type: directionPlan.replacementData.type,
      source: directionPlan.sourceLabel,
      budgetCategoryId: directionPlan.categoryId,
      itemCount: directionPlan.itemIds.length,
      historicalLineageEdgesToRewire: directionPlan.lineageSnapshots.length,
      amountCents: directionPlan.amountCents,
      subtotalCents: directionPlan.subtotalCents,
      transactionDate: directionPlan.transactionDate,
      sourceTransactionIds: directionPlan.sourceTransactionIds,
    })),
    allHistoricalLineageEdgesToRewire: plan.lineageEdgesToRewire?.length ?? 0,
    writesIfCommitted: plan.writes,
    projectSpendCents: { before: plan.beforeSpendCents, after: plan.afterSpendCents },
    existingConsolidated: plan.existingConsolidated,
  };
  console.log(JSON.stringify(summary, null, 2));
}

async function writeBackup(backupPath, plan, projectSnapshot, transactionSnapshots, itemSnapshots, lineageSnapshots) {
  const absolutePath = path.resolve(backupPath);
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
  const payload = {
    createdAt: new Date().toISOString(),
    script: CONSOLIDATION_VERSION,
    planHash: sha256(stableJson({
      project: plan.projectId,
      sourceIds: plan.sourceIds,
      replacementIds: plan.replacementIds,
      directions: plan.directions.map((directionPlan) => ({
        direction: directionPlan.direction,
        itemIds: directionPlan.itemIds,
        lineageEdgeIds: directionPlan.lineageSnapshots.map((snapshot) => snapshot.id),
        amountCents: directionPlan.amountCents,
        subtotalCents: directionPlan.subtotalCents,
      })),
      lineageEdgeIdsToRewire: plan.lineageEdgesToRewire?.map((snapshot) => snapshot.id) ?? [],
      deleteOriginals: plan.deleteOriginals,
    })),
    project: snapshotRecord(projectSnapshot),
    transactions: transactionSnapshots.map(snapshotRecord),
    items: itemSnapshots.map(snapshotRecord),
    lineageEdges: lineageSnapshots.map(snapshotRecord),
    plan: {
      beforeSpendCents: plan.beforeSpendCents,
      afterSpendCents: plan.afterSpendCents,
      directions: plan.directions.map((directionPlan) => ({
        direction: directionPlan.direction,
        replacementTransactionId: directionPlan.replacementTransactionId,
        replacementData: directionPlan.replacementData,
        lineageEdgeIds: directionPlan.lineageSnapshots.map((snapshot) => snapshot.id),
      })),
    },
  };
  const serialized = JSON.stringify(payload, null, 2);
  fs.writeFileSync(absolutePath, serialized, { flag: 'wx', mode: 0o600 });
  const written = fs.readFileSync(absolutePath, 'utf8');
  assert(sha256(written) === sha256(serialized), `Backup verification failed: ${absolutePath}`);
  assert(payload.transactions.length === plan.sourceIds.length,
    `Backup verification failed: expected ${plan.sourceIds.length} source transactions, backed up ${payload.transactions.length}`);
  if (plan.deleteOriginals) {
    assert(payload.lineageEdges.length === plan.lineageEdgesToRewire.length,
      `Backup verification failed: expected ${plan.lineageEdgesToRewire.length} lineage edges, backed up ${payload.lineageEdges.length}`);
  }
  return absolutePath;
}

function transactionRefs(db, accountId, ids) {
  return ids.map((id) => db.doc(`accounts/${accountId}/transactions/${id}`));
}

function stableSourceTransactionData(data) {
  const comparable = { ...(data || {}) };
  // Cloud Functions may recompute these fields after a lineage edge is
  // created. They are not user edits that should prevent deleting the backed
  // up source document.
  delete comparable.updatedAt;
  delete comparable.isComplete;
  delete comparable.audit;
  return comparable;
}

function assertSourceStillIntact(originalSnapshot, currentSnapshot) {
  assert(currentSnapshot.exists, `Source transaction disappeared: ${originalSnapshot.id}`);
  assert(stableJson(stableSourceTransactionData(currentSnapshot.data())) ===
    stableJson(stableSourceTransactionData(originalSnapshot.data())),
  `Source transaction changed during staged consolidation: ${originalSnapshot.id}; aborting before deletion`);
}

function lineageReplacementPatch(snapshot, sourceReplacementById) {
  const data = snapshot.data() || {};
  const fromTransactionId = normalizeText(data.fromTransactionId);
  const toTransactionId = normalizeText(data.toTransactionId);
  const replacementFrom = sourceReplacementById.get(fromTransactionId);
  const replacementTo = sourceReplacementById.get(toTransactionId);
  assert(replacementFrom || replacementTo,
    `Lineage edge ${snapshot.id} does not reference a source transaction slated for consolidation`);

  const patch = {
    consolidatedBy: CONSOLIDATION_VERSION,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (replacementFrom) {
    patch.fromTransactionId = replacementFrom;
    patch.consolidatedFromTransactionId = fromTransactionId;
  }
  if (replacementTo) {
    patch.toTransactionId = replacementTo;
    patch.consolidatedToTransactionId = toTransactionId;
  }
  return patch;
}

async function updateLineageEdges(db, snapshots, sourceReplacementById, label) {
  for (const batchSnapshots of chunk(snapshots, MAX_TRANSACTION_WRITES - 100)) {
    const batch = db.batch();
    for (const snapshot of batchSnapshots) {
      batch.update(
        snapshot.ref,
        lineageReplacementPatch(snapshot, sourceReplacementById),
        { lastUpdateTime: snapshot.updateTime },
      );
    }
    if (batchSnapshots.length > 0) {
      await batch.commit();
      log(`${label}: rewrote ${batchSnapshots.length} lineage edges`);
    }
  }
}

async function stageReplacementTransactions(db, accountId, plan) {
  const replacementRefs = plan.directions.map((directionPlan) =>
    db.doc(`accounts/${accountId}/transactions/${directionPlan.replacementTransactionId}`));
  const existing = await db.getAll(...replacementRefs);
  const batch = db.batch();
  let creates = 0;

  plan.directions.forEach((directionPlan, index) => {
    const current = existing[index];
    if (current.exists) {
      const data = current.data() || {};
      assert(data.consolidationKey === plan.key,
        `Replacement transaction already exists with a different consolidation key: ${current.id}`);
      assert(isCanceled(data) && data.consolidationState === 'staged',
        `Replacement transaction already exists but is not a staged delete candidate: ${current.id}`);
      return;
    }

    batch.create(current.ref, {
      ...directionPlan.replacementData,
      status: 'canceled',
      consolidationState: 'staged',
      stagedAt: admin.firestore.FieldValue.serverTimestamp(),
      notes: appendNote(directionPlan.replacementData.notes,
        'Staged before original transaction deletion; this record is not active until final verification.'),
    });
    creates += 1;
  });

  if (creates > 0) {
    await batch.commit();
    log(`Staged ${creates} replacement transaction${creates === 1 ? '' : 's'}.`);
  }
}

async function updateCurrentItemsForDelete(db, plan, itemSnapshots) {
  const itemToReplacement = new Map();
  for (const directionPlan of plan.directions) {
    for (const itemId of directionPlan.itemIds) {
      itemToReplacement.set(itemId, directionPlan.replacementTransactionId);
    }
  }

  for (const batchSnapshots of chunk(itemSnapshots, MAX_TRANSACTION_WRITES - 100)) {
    const batch = db.batch();
    for (const snapshot of batchSnapshots) {
      const replacementTransactionId = itemToReplacement.get(snapshot.id);
      assert(replacementTransactionId, `No replacement transaction for item ${snapshot.id}`);
      batch.update(snapshot.ref, {
        transactionId: replacementTransactionId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { lastUpdateTime: snapshot.updateTime });
    }
    if (batchSnapshots.length > 0) {
      await batch.commit();
      log(`Updated ${batchSnapshots.length} current item transaction links.`);
    }
  }
}

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function settleOldLineageReferences(db, accountId, plan) {
  const sourceIds = plan.sourceIds;
  let emptyChecks = 0;
  for (let attempt = 1; attempt <= 20; attempt += 1) {
    const residual = (await loadLineageSnapshots(db, accountId, sourceIds)).filter((snapshot) => {
      const data = snapshot.data() || {};
      return plan.sourceReplacementById.has(normalizeText(data.fromTransactionId)) ||
        plan.sourceReplacementById.has(normalizeText(data.toTransactionId));
    });

    if (residual.length > 0) {
      emptyChecks = 0;
      await updateLineageEdges(db, residual, plan.sourceReplacementById, 'Settling trigger-created references');
      continue;
    }

    emptyChecks += 1;
    if (emptyChecks >= 3) return;
    await wait(1000);
  }
  fail('Timed out waiting for all trigger-created references to settle; originals were not deleted.');
}

async function finalizeDeletePlan(db, accountId, plan, transactionSnapshots, itemSnapshots) {
  const sourceRefs = transactionRefs(db, accountId, transactionSnapshots.map((snapshot) => snapshot.id));
  const itemRefs = itemSnapshots.map((snapshot) => snapshot.ref);
  const replacementRefs = plan.directions.map((directionPlan) =>
    db.doc(`accounts/${accountId}/transactions/${directionPlan.replacementTransactionId}`));

  await db.runTransaction(async (transaction) => {
    const fresh = await transaction.getAll(...sourceRefs, ...itemRefs, ...replacementRefs);
    const freshSources = fresh.slice(0, sourceRefs.length);
    const freshItems = fresh.slice(sourceRefs.length, sourceRefs.length + itemRefs.length);
    const freshReplacements = fresh.slice(sourceRefs.length + itemRefs.length);

    transactionSnapshots.forEach((snapshot, index) => {
      assertSourceStillIntact(snapshot, freshSources[index]);
    });
    for (const snapshot of freshItems) {
      const directionPlan = plan.directions.find((candidate) => candidate.itemIds.includes(snapshot.id));
      assert(snapshot.exists && directionPlan,
        `Current item disappeared or lost its replacement assignment: ${snapshot.id}`);
      assert(snapshot.data()?.transactionId === directionPlan.replacementTransactionId,
        `Current item changed during staged consolidation: ${snapshot.id}; aborting before deletion`);
    }
    for (const snapshot of freshReplacements) {
      assert(snapshot.exists, `Staged replacement disappeared: ${snapshot.id}`);
      assert(isCanceled(snapshot.data()) && snapshot.data()?.consolidationState === 'staged',
        `Replacement is not still staged: ${snapshot.id}`);
    }

    for (const snapshot of freshReplacements) {
      transaction.update(snapshot.ref, {
        status: admin.firestore.FieldValue.delete(),
        consolidationState: admin.firestore.FieldValue.delete(),
        stagedAt: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    for (const snapshot of freshSources) transaction.delete(snapshot.ref);
  });
}

async function applyDeletePlan(db, accountId, plan, projectSnapshot, transactionSnapshots, itemSnapshots, lineageSnapshots, backupPath) {
  const backup = await writeBackup(
    backupPath,
    plan,
    projectSnapshot,
    transactionSnapshots,
    itemSnapshots,
    lineageSnapshots,
  );

  await stageReplacementTransactions(db, accountId, plan);
  await updateLineageEdges(db, lineageSnapshots, plan.sourceReplacementById, 'Initial reference rewrite');
  await updateCurrentItemsForDelete(db, plan, itemSnapshots);
  await settleOldLineageReferences(db, accountId, plan);
  await finalizeDeletePlan(db, accountId, plan, transactionSnapshots, itemSnapshots);
  // A slow Cloud Function can still finish after the first settle pass. This
  // final pass can repair a late edge before verification, without touching the
  // deleted transaction documents.
  await settleOldLineageReferences(db, accountId, plan);

  const sourceRefs = transactionRefs(db, accountId, transactionSnapshots.map((snapshot) => snapshot.id));
  const itemRefs = itemSnapshots.map((snapshot) => snapshot.ref);
  const replacementRefs = plan.directions.map((directionPlan) =>
    db.doc(`accounts/${accountId}/transactions/${directionPlan.replacementTransactionId}`));
  const verified = await db.getAll(...sourceRefs, ...itemRefs, ...replacementRefs);
  const verifiedSources = verified.slice(0, sourceRefs.length);
  const verifiedItems = verified.slice(sourceRefs.length, sourceRefs.length + itemRefs.length);
  const verifiedReplacements = verified.slice(sourceRefs.length + itemRefs.length);

  for (const snapshot of verifiedSources) {
    assert(!snapshot.exists, `Verification failed: original transaction still exists: ${snapshot.id}`);
  }
  for (const snapshot of verifiedItems) {
    const directionPlan = plan.directions.find((candidate) => candidate.itemIds.includes(snapshot.id));
    assert(directionPlan && snapshot.data()?.transactionId === directionPlan.replacementTransactionId,
      `Verification failed: item ${snapshot.id} does not point to its replacement`);
  }
  for (const snapshot of verifiedReplacements) {
    assert(snapshot.exists && isActive(snapshot.data()) && !snapshot.data()?.consolidationState,
      `Verification failed: replacement ${snapshot.id} is not active`);
  }
  assert((await loadLineageSnapshots(db, accountId, plan.sourceIds)).length === 0,
    'Verification failed: a lineage edge still references a deleted source transaction');

  const projectTransactionsAfter = await db.collection(`accounts/${accountId}/transactions`)
    .where('projectId', '==', plan.projectId).get();
  const afterSpendCents = projectSpendCents(projectTransactionsAfter.docs);
  assert(afterSpendCents === plan.beforeSpendCents,
    `Verification failed: project spend changed from ${plan.beforeSpendCents} to ${afterSpendCents} cents`);

  return { backup, afterSpendCents };
}

async function applyPlan(db, accountId, plan, projectSnapshot, transactionSnapshots, itemSnapshots, lineageSnapshots, backupPath) {
  const backup = await writeBackup(
    backupPath,
    plan,
    projectSnapshot,
    transactionSnapshots,
    itemSnapshots,
    lineageSnapshots,
  );
  const transactionIds = transactionSnapshots.map((snapshot) => snapshot.id);
  const itemIds = itemSnapshots.map((snapshot) => snapshot.id);
  const lineageIds = lineageSnapshots.map((snapshot) => snapshot.id);
  const replacementRefs = plan.directions.map((directionPlan) =>
    db.doc(`accounts/${accountId}/transactions/${directionPlan.replacementTransactionId}`));
  const sourceRefs = transactionRefs(db, accountId, transactionIds);
  const itemRefs = itemIds.map((id) => db.doc(`accounts/${accountId}/items/${id}`));
  const lineageRefs = lineageIds.map((id) => db.doc(`accounts/${accountId}/lineageEdges/${id}`));
  const allRefs = [...sourceRefs, ...itemRefs, ...lineageRefs, ...replacementRefs];

  await db.runTransaction(async (transaction) => {
    const fresh = await transaction.getAll(...allRefs);
    const freshSources = fresh.slice(0, sourceRefs.length);
    const freshItems = fresh.slice(sourceRefs.length, sourceRefs.length + itemRefs.length);
    const freshLineage = fresh.slice(
      sourceRefs.length + itemRefs.length,
      sourceRefs.length + itemRefs.length + lineageRefs.length,
    );
    const freshReplacements = fresh.slice(sourceRefs.length + itemRefs.length + lineageRefs.length);

    transactionSnapshots.forEach((snapshot, index) => {
      const current = freshSources[index];
      assert(current.exists, `Source transaction disappeared: ${snapshot.id}`);
      assert(current.updateTime?.isEqual(snapshot.updateTime), `Concurrent edit detected on ${snapshot.id}; aborting`);
    });
    itemSnapshots.forEach((snapshot, index) => {
      const current = freshItems[index];
      assert(current.exists, `Item disappeared: ${snapshot.id}`);
      assert(current.updateTime?.isEqual(snapshot.updateTime), `Concurrent edit detected on item ${snapshot.id}; aborting`);
    });
    lineageSnapshots.forEach((snapshot, index) => {
      const current = freshLineage[index];
      assert(current.exists, `Lineage edge disappeared: ${snapshot.id}`);
      assert(current.updateTime?.isEqual(snapshot.updateTime), `Concurrent edit detected on lineage edge ${snapshot.id}; aborting`);
    });
    freshReplacements.forEach((snapshot) => assert(!snapshot.exists,
      `Replacement transaction already exists: ${snapshot.id}`));

    const replacementByDirection = new Map(plan.directions.map((directionPlan) => [
      directionPlan.direction,
      directionPlan.replacementTransactionId,
    ]));
    const itemToReplacement = new Map();
    for (const directionPlan of plan.directions) {
      for (const itemId of directionPlan.itemIds) itemToReplacement.set(itemId, replacementByDirection.get(directionPlan.direction));
    }

    for (const snapshot of freshSources) {
      const note = `Replaced by consolidation transaction ${
        plan.directions.find((directionPlan) => directionPlan.sourceTransactionIds.includes(snapshot.id))?.replacementTransactionId
      }. Original record retained as canceled audit history.`;
      transaction.update(snapshot.ref, {
        itemIds: [],
        status: 'canceled',
        notes: appendNote(snapshot.data()?.notes, note),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    for (const snapshot of freshItems) {
      const replacementIdForItem = itemToReplacement.get(snapshot.id);
      assert(replacementIdForItem, `No replacement transaction for item ${snapshot.id}`);
      transaction.update(snapshot.ref, {
        transactionId: replacementIdForItem,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    for (const snapshot of freshLineage) {
      const sourceTransactionId = normalizeText(snapshot.data()?.fromTransactionId);
      const directionPlan = plan.directions.find((candidate) =>
        candidate.sourceTransactionIds.includes(sourceTransactionId));
      assert(directionPlan, `No replacement transaction for lineage edge ${snapshot.id}`);
      transaction.update(snapshot.ref, {
        fromTransactionId: directionPlan.replacementTransactionId,
        consolidatedFromTransactionId: sourceTransactionId,
        consolidatedBy: CONSOLIDATION_VERSION,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    for (const directionPlan of plan.directions) {
      transaction.create(
        db.doc(`accounts/${accountId}/transactions/${directionPlan.replacementTransactionId}`),
        directionPlan.replacementData,
      );
    }
  });

  const afterTransactionSnapshots = await db.getAll(...sourceRefs, ...itemRefs, ...lineageRefs, ...replacementRefs);
  const afterSources = afterTransactionSnapshots.slice(0, sourceRefs.length);
  const afterItems = afterTransactionSnapshots.slice(sourceRefs.length, sourceRefs.length + itemRefs.length);
  const afterLineage = afterTransactionSnapshots.slice(
    sourceRefs.length + itemRefs.length,
    sourceRefs.length + itemRefs.length + lineageRefs.length,
  );
  const afterReplacements = afterTransactionSnapshots.slice(sourceRefs.length + itemRefs.length + lineageRefs.length);
  for (const snapshot of afterSources) {
    assert(isCanceled(snapshot.data()), `Verification failed: ${snapshot.id} is not canceled`);
    assert((snapshot.data().itemIds || []).length === 0, `Verification failed: ${snapshot.id} still has itemIds`);
  }
  for (const snapshot of afterItems) {
    const expected = plan.directions.find((directionPlan) => directionPlan.itemIds.includes(snapshot.id));
    assert(snapshot.data().transactionId === expected.replacementTransactionId,
      `Verification failed: item ${snapshot.id} points to ${snapshot.data().transactionId}`);
  }
  for (const snapshot of afterLineage) {
    const sourceTransactionId = normalizeText(snapshot.data()?.consolidatedFromTransactionId);
    const directionPlan = plan.directions.find((candidate) =>
      candidate.sourceTransactionIds.includes(sourceTransactionId));
    assert(directionPlan && snapshot.data()?.fromTransactionId === directionPlan.replacementTransactionId,
      `Verification failed: lineage edge ${snapshot.id} was not rewired`);
  }
  for (const snapshot of afterReplacements) {
    assert(snapshot.exists, `Verification failed: replacement ${snapshot.id} was not created`);
  }

  const projectTransactionsAfter = await db.collection(`accounts/${accountId}/transactions`)
    .where('projectId', '==', plan.projectId).get();
  const afterSpendCents = projectSpendCents(projectTransactionsAfter.docs);
  assert(afterSpendCents === plan.beforeSpendCents,
    `Verification failed: project spend changed from ${plan.beforeSpendCents} to ${afterSpendCents} cents`);

  return { backup, afterSpendCents };
}

function initFirestore() {
  assert(!process.env.FIRESTORE_EMULATOR_HOST && !process.env.FIREBASE_AUTH_EMULATOR_HOST,
    'Refusing to run with Firebase emulator variables set; this is a production-data consolidation script.');
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: FIREBASE_PROJECT_ID,
    });
  }
  return admin.firestore();
}

async function main() {
  const options = parseArgs(process.argv);
  if (options.help) {
    printHelp();
    return;
  }

  const db = initFirestore();
  const projectSnapshot = await resolveProjectSnapshot(db, options.accountId, options.projectId, options.projectName);
  assert(projectSnapshot.exists, `Project does not exist: ${options.projectId}`);
  const projectId = projectSnapshot.id;
  const projectName = normalizeText(projectSnapshot.data()?.name) || options.projectName || projectId;
  log(`Processing ${projectName} (${projectId}) in account ${options.accountId}`);

  const accountSnapshot = await db.doc(`accounts/${options.accountId}`).get();
  const accountName = normalizeText(accountSnapshot.data()?.name);
  const defaultSourceLabel = accountName ? `${accountName} Inventory` : 'Business Inventory';
  const effectiveOptions = { ...options, sourceLabel: options.sourceLabel || null };

  const transactionCollection = db.collection(`accounts/${options.accountId}/transactions`);
  const transactionQuery = await transactionCollection.where('projectId', '==', projectId).get();
  const transactionSnapshots = transactionQuery.docs;
  const candidateTransactionIds = transactionSnapshots
    .filter((snapshot) => isActive(snapshot.data()) && classifyTransaction(snapshot.data()))
    .map((snapshot) => snapshot.id);
  const lineageSnapshots = await loadLineageSnapshots(db, options.accountId, candidateTransactionIds);
  const candidateItemIds = [...new Set(transactionSnapshots.flatMap((snapshot) => {
    const classification = classifyTransaction(snapshot.data());
    return classification && isActive(snapshot.data()) && Array.isArray(snapshot.data()?.itemIds)
      ? snapshot.data().itemIds.map(normalizeText).filter(Boolean)
      : [];
  }))];
  const itemSnapshots = candidateItemIds.length
    ? await db.getAll(...candidateItemIds.map((id) => db.doc(`accounts/${options.accountId}/items/${id}`)))
    : [];
  const itemSnapshotsById = new Map(itemSnapshots.filter((snapshot) => snapshot.exists).map((snapshot) => [snapshot.id, snapshot]));

  if (!effectiveOptions.sourceLabel) {
    const labels = transactionSnapshots
      .filter((snapshot) => isActive(snapshot.data()) && classifyTransaction(snapshot.data()))
      .map((snapshot) => snapshot.data()?.source)
      .filter(isInventorySource);
    if (new Set(labels.map(normalizeText).filter(Boolean)).size === 0) effectiveOptions.sourceLabel = defaultSourceLabel;
  }

  const plan = makePlan({
    projectId,
    projectName,
    transactionSnapshots,
    itemSnapshotsById,
    lineageSnapshots,
    options: effectiveOptions,
  });
  printPlan(plan);

  const allPlanItemIds = [...new Set(plan.directions.flatMap((directionPlan) => directionPlan.itemIds))];
  const planTransactionIds = plan.sourceIds;
  const backupTransactions = transactionSnapshots.filter((snapshot) => planTransactionIds.includes(snapshot.id));
  const backupItems = allPlanItemIds.map((id) => itemSnapshotsById.get(id));
  const backupLineage = options.deleteOriginals
    ? plan.lineageEdgesToRewire
    : plan.directions.flatMap((directionPlan) => directionPlan.lineageSnapshots);

  if (options.backupOnly && plan.candidates.length > 0) {
    assert(backupItems.every(Boolean), 'Cannot create complete backup because an item document is missing');
    const backup = await writeBackup(
      options.backupPath,
      plan,
      projectSnapshot,
      backupTransactions,
      backupItems,
      backupLineage,
    );
    log(`BACKUP-ONLY — no Firebase writes performed. Verified backup: ${backup}`);
    return;
  }

  if (!options.commit || plan.candidates.length === 0) {
    log(plan.candidates.length === 0
      ? 'No active inventory movement transactions require consolidation.'
      : options.deleteOriginals
        ? 'DRY-RUN — no writes performed. Delete mode is only executable with --commit --delete-originals --backup <path> after reviewing the plan.'
        : 'DRY-RUN — no writes performed. Re-run with --commit --backup <path> after reviewing the plan.');
    return;
  }

  assert(backupItems.every(Boolean), 'Cannot create complete backup because an item document is missing');
  const result = options.deleteOriginals
    ? await applyDeletePlan(
      db,
      options.accountId,
      plan,
      projectSnapshot,
      backupTransactions,
      backupItems,
      backupLineage,
      options.backupPath,
    )
    : await applyPlan(
      db,
      options.accountId,
      plan,
      projectSnapshot,
      backupTransactions,
      backupItems,
      backupLineage,
      options.backupPath,
    );
  log(`COMMITTED — replacement transactions: ${plan.replacementIds.join(', ')}`);
  log(`Backup: ${result.backup}`);
  log(`Verified project spend remains ${result.afterSpendCents} cents.`);
}

const isMain = process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) {
  main()
    .catch((error) => {
      console.error(`\x1b[31m[witzenman-consolidation]\x1b[0m ${error.stack || error}`);
      process.exitCode = 1;
    })
    .finally(async () => {
      if (admin.apps.length) await admin.app().delete();
    });
}
