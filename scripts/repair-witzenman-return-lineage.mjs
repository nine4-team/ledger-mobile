#!/usr/bin/env node

/**
 * Repair invalid sale-intent endpoints that currently name an inventory Return.
 *
 * This command is deliberately read-only by default. It does not delete
 * transactions, rewrite association history, redirect sale destinations, or
 * change accounting amounts. An apply requires all of:
 *   --apply --confirm-apply --manifest <reviewed-manifest.json>
 *   --backup <new-prewrite-backup.json>
 * and the manifest must contain `reviewed: true`.
 *
 * The repair preserves each actual destination sale. It only removes the
 * Return transaction/project from the source side of a `sold` or
 * `soldToInventory` intent edge. The edge document, item, destination, kind,
 * timestamp, and association history remain intact.
 *
 * Required environment for live reads:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json
 * Optional:
 *   FIREBASE_PROJECT_ID=ledger-nine4
 *
 * Examples:
 *   node scripts/repair-witzenman-return-lineage.mjs --plan --out /tmp/witzenman-return-repair.json
 *   node scripts/repair-witzenman-return-lineage.mjs --verify
 *   node scripts/repair-witzenman-return-lineage.mjs --apply --confirm-apply \
 *     --manifest /tmp/reviewed.json --backup /tmp/pre-repair-backup.json
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import admin from 'firebase-admin';

const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const DEFAULT_ACCOUNT_ID = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const DEFAULT_PROJECT_ID = '5abd46c9-9886-4b3e-b2b1-19f6cf995a44';
const DEFAULT_BACKUP = 'docs/plans/witzenman-inventory-consolidation-backup-2026-09-18.json';
const SALE_KINDS = new Set(['sold', 'soldToInventory']);
const MAX_BATCH_WRITES = 400;

function fail(message) {
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function normalizeType(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : null;
}

function valueOrNull(value) {
  return value === undefined ? null : value;
}

function sha256File(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function parseArgs(argv) {
  const options = {
    accountId: DEFAULT_ACCOUNT_ID,
    projectId: DEFAULT_PROJECT_ID,
    backupInput: DEFAULT_BACKUP,
    backupOutput: null,
    manifest: null,
    out: null,
    plan: false,
    verify: false,
    apply: false,
    confirmApply: false,
    approvePlan: false,
    backupOnly: false,
    help: false,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--account') options.accountId = argv[++i];
    else if (arg === '--project-id') options.projectId = argv[++i];
    else if (arg === '--backup-input') options.backupInput = argv[++i];
    else if (arg === '--backup') options.backupOutput = argv[++i];
    else if (arg === '--manifest') options.manifest = argv[++i];
    else if (arg === '--out') options.out = argv[++i];
    else if (arg === '--plan') options.plan = true;
    else if (arg === '--verify') options.verify = true;
    else if (arg === '--apply') options.apply = true;
    else if (arg === '--confirm-apply') options.confirmApply = true;
    else if (arg === '--approve-plan') options.approvePlan = true;
    else if (arg === '--backup-only') options.backupOnly = true;
    else if (arg === '--help' || arg === '-h') options.help = true;
    else fail(`Unknown argument: ${arg}`);
  }

  if (options.apply && (!options.manifest || !options.backupOutput)) {
    fail('--apply requires --manifest <reviewed-manifest.json> and --backup <new-prewrite-backup.json>');
  }
  if (options.apply && !options.confirmApply) {
    fail('--apply also requires --confirm-apply; this is an intentional production-write guard');
  }
  if (options.backupOnly && options.apply) fail('--backup-only cannot be combined with --apply');
  if (options.backupOnly && !options.backupOutput) fail('--backup-only requires --backup <new-backup.json>');
  return options;
}

function printHelp() {
  console.log(`
Repair invalid Witzenman Return sale lineage.

Default: read-only live analysis using the original consolidation backup.

Options:
  --account <id>             Account override.
  --project-id <id>          Project override.
  --backup-input <path>      Original backup input (default: ${DEFAULT_BACKUP}).
  --plan                     Write/read a repair manifest; never writes Firebase.
  --approve-plan             Mark the generated manifest reviewed for a later apply.
  --out <path>               Save the dry-run manifest/report at this path.
  --verify                   Read-only post-repair invariant check.
  --backup-only --backup <path>
                             Save current repair-target documents; no Firebase writes.
  --apply --confirm-apply --manifest <path> --backup <path>
                             Apply only the exact reviewed manifest after backup.
`);
}

function initFirestore() {
  if (admin.apps.length === 0) admin.initializeApp({ projectId: FIREBASE_PROJECT_ID });
  return admin.firestore();
}

function docIdFromPath(documentPath) {
  return documentPath.split('/').at(-1);
}

function serialize(value) {
  if (value === undefined) return null;
  if (value === null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') return value;
  if (value instanceof Date) return { __type: 'timestamp', value: value.toISOString() };
  if (value && typeof value.toDate === 'function') return { __type: 'timestamp', value: value.toDate().toISOString() };
  if (Array.isArray(value)) return value.map(serialize);
  if (typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, serialize(entry)]));
  return String(value);
}

function readJson(filePath) {
  const absolute = path.resolve(filePath);
  assert(fs.existsSync(absolute), `File not found: ${absolute}`);
  return JSON.parse(fs.readFileSync(absolute, 'utf8'));
}

function writeJsonExclusive(filePath, value) {
  const absolute = path.resolve(filePath);
  assert(!fs.existsSync(absolute), `Refusing to overwrite existing file: ${absolute}`);
  fs.mkdirSync(path.dirname(absolute), { recursive: true });
  fs.writeFileSync(absolute, `${JSON.stringify(value, null, 2)}\n`, { flag: 'wx' });
  return absolute;
}

async function loadLive(db, accountId) {
  const transactionsSnapshot = await db.collection(`accounts/${accountId}/transactions`).get();
  const edgesSnapshot = await db.collection(`accounts/${accountId}/lineageEdges`).get();
  const itemsSnapshot = await db.collection(`accounts/${accountId}/items`).get();
  return {
    transactions: transactionsSnapshot.docs.map((doc) => ({
      id: doc.id,
      path: doc.ref.path,
      data: doc.data() ?? {},
    })),
    lineageEdges: edgesSnapshot.docs.map((doc) => ({
      id: doc.id,
      path: doc.ref.path,
      data: doc.data() ?? {},
    })),
    items: itemsSnapshot.docs.map((doc) => ({
      id: doc.id,
      path: doc.ref.path,
      data: doc.data() ?? {},
    })),
  };
}

function backupTransactionData(backup) {
  return (backup.transactions ?? []).map((entry) => ({
    id: entry.id ?? docIdFromPath(entry.path),
    path: entry.path,
    data: entry.data ?? {},
  }));
}

function backupEdgeData(backup) {
  return (backup.lineageEdges ?? []).map((entry) => ({
    id: entry.id ?? docIdFromPath(entry.path),
    path: entry.path,
    data: entry.data ?? {},
  }));
}

function originalReturnIds(backup) {
  return new Set(
    backupTransactionData(backup)
      .filter((tx) => normalizeType(tx.data.type ?? tx.data.transactionType) === 'return')
      .map((tx) => tx.id)
  );
}

function originalSaleCandidates(backup) {
  const returnIds = originalReturnIds(backup);
  return backupEdgeData(backup).filter((edge) =>
    returnIds.has(edge.data.fromTransactionId) && SALE_KINDS.has(edge.data.movementKind)
  );
}

function currentReturnTransactions(live, projectId) {
  return live.transactions.filter((tx) =>
    normalizeType(tx.data.type ?? tx.data.transactionType) === 'return' && tx.data.projectId === projectId
  );
}

function selectConsolidatedReturn(live, projectId) {
  const exactId = `CONSOLIDATED_${projectId}_outbound_return`;
  return live.transactions.find((tx) => tx.id === exactId)
    ?? currentReturnTransactions(live, projectId).find((tx) => tx.data.consolidationDirection === 'outbound')
    ?? null;
}

function edgeKey(edge) {
  const data = edge.data;
  return [data.itemId ?? '', data.toTransactionId ?? '', data.movementKind ?? ''].join('|');
}

function analyze({ backup, live, accountId, projectId }) {
  const originalCandidates = originalSaleCandidates(backup);
  const originalIds = new Set(originalCandidates.map((edge) => edge.id));
  const liveById = new Map(live.lineageEdges.map((edge) => [edge.id, edge]));
  const liveByKey = new Map(live.lineageEdges.map((edge) => [edgeKey(edge), edge]));
  const returnTransactions = currentReturnTransactions(live, projectId);
  const returnIds = new Set(returnTransactions.map((tx) => tx.id));
  const consolidatedReturn = selectConsolidatedReturn(live, projectId);

  const historical = originalCandidates.map((original) => {
    const current = liveById.get(original.id) ?? liveByKey.get(edgeKey(original));
    return {
      evidence: 'original-backup',
      originalEdgeId: original.id,
      currentEdgeId: current?.id ?? null,
      currentPath: current?.path ?? null,
      itemId: original.data.itemId ?? null,
      destinationTransactionId: original.data.toTransactionId ?? null,
      destinationProjectId: original.data.toProjectId ?? null,
      movementKind: original.data.movementKind ?? null,
      current: current ? {
        fromTransactionId: valueOrNull(current.data.fromTransactionId),
        fromProjectId: valueOrNull(current.data.fromProjectId),
        toTransactionId: valueOrNull(current.data.toTransactionId),
        toProjectId: valueOrNull(current.data.toProjectId),
      } : null,
    };
  });

  const currentInvalid = live.lineageEdges.filter((edge) => {
    const kindIsSale = SALE_KINDS.has(edge.data.movementKind);
    const sourceIsReturn = returnIds.has(edge.data.fromTransactionId);
    const destinationIsReturn = returnIds.has(edge.data.toTransactionId);
    return kindIsSale && (sourceIsReturn || destinationIsReturn);
  });

  const operations = [];
  const blockers = [];
  for (const edge of currentInvalid) {
    const sourceIsReturn = returnIds.has(edge.data.fromTransactionId);
    const destinationIsReturn = returnIds.has(edge.data.toTransactionId);
    if (destinationIsReturn) {
      blockers.push({
        edgeId: edge.id,
        reason: 'A sale intent edge has a Return destination; its actual destination cannot be inferred safely.',
        path: edge.path,
      });
      continue;
    }
    if (!sourceIsReturn) continue;
    operations.push({
      kind: 'clear-return-sale-source',
      edgeId: edge.id,
      path: edge.path,
      evidence: originalIds.has(edge.id) ? 'original-backup' : 'live-post-consolidation',
      itemId: edge.data.itemId ?? null,
      before: {
        fromTransactionId: valueOrNull(edge.data.fromTransactionId),
        fromProjectId: valueOrNull(edge.data.fromProjectId),
        toTransactionId: valueOrNull(edge.data.toTransactionId),
        toProjectId: valueOrNull(edge.data.toProjectId),
        movementKind: valueOrNull(edge.data.movementKind),
      },
      after: {
        fromTransactionId: null,
        fromProjectId: null,
        toTransactionId: valueOrNull(edge.data.toTransactionId),
        toProjectId: valueOrNull(edge.data.toProjectId),
        movementKind: valueOrNull(edge.data.movementKind),
      },
    });
  }

  const backupReturnIds = originalReturnIds(backup);
  const historicalReturnedItemIds = new Set();
  for (const tx of backupTransactionData(backup)) {
    if (!backupReturnIds.has(tx.id)) continue;
    for (const itemId of Array.isArray(tx.data.itemIds) ? tx.data.itemIds : []) historicalReturnedItemIds.add(itemId);
  }
  for (const edge of backupEdgeData(backup)) {
    if (backupReturnIds.has(edge.data.toTransactionId) && edge.data.movementKind === 'returned' && edge.data.itemId) {
      historicalReturnedItemIds.add(edge.data.itemId);
    }
  }

  const returnMembership = consolidatedReturn ? {
    transactionId: consolidatedReturn.id,
    before: Array.isArray(consolidatedReturn.data.returnedItemIds)
      ? [...consolidatedReturn.data.returnedItemIds].sort()
      : null,
    after: [...new Set([
      ...(Array.isArray(consolidatedReturn.data.returnedItemIds) ? consolidatedReturn.data.returnedItemIds : []),
      ...historicalReturnedItemIds,
    ])].sort(),
    snapshotAvailable: Boolean(consolidatedReturn.data.returnSnapshot),
  } : null;

  const itemById = new Map((live.items ?? []).map((item) => [item.id, item]));
  const affectedItemIds = [...new Set(operations.map((operation) => operation.itemId).filter(Boolean))];
  const missingAffectedItems = affectedItemIds.filter((itemId) => !itemById.has(itemId));
  const affectedProjectPriceCents = affectedItemIds.reduce((sum, itemId) => {
    return sum + Number(itemById.get(itemId)?.data.projectPriceCents ?? 0);
  }, 0);
  const currentAudit = consolidatedReturn?.data.audit && typeof consolidatedReturn.data.audit === 'object'
    ? consolidatedReturn.data.audit
    : null;
  const returnAudit = consolidatedReturn && currentAudit ? {
    transactionId: consolidatedReturn.id,
    before: currentAudit,
    after: (() => {
      const linkedItemsSumCents = Number(currentAudit.linkedItemsSumCents ?? 0);
      const existingReturnedSumCents = Number(currentAudit.returnedItemsSumCents ?? 0);
      const existingReturnedCount = Number(currentAudit.returnedItemsCount ?? 0);
      const discountCents = Number(currentAudit.discountCents ?? 0);
      const resolvedSubtotalCents = Number(currentAudit.resolvedSubtotalCents ?? consolidatedReturn.data.subtotalCents ?? 0);
      const returnedItemsSumCents = existingReturnedSumCents + affectedProjectPriceCents;
      const returnedItemsCount = existingReturnedCount + affectedItemIds.length;
      const itemsSumCents = linkedItemsSumCents + returnedItemsSumCents;
      const varianceCents = itemsSumCents - discountCents - resolvedSubtotalCents;
      const variancePercent = resolvedSubtotalCents > 0
        ? Math.round((varianceCents / resolvedSubtotalCents) * 10000) / 100
        : 0;
      return {
        ...currentAudit,
        itemsSumCents,
        varianceCents,
        variancePercent,
        returnedItemsSumCents,
        returnedItemsCount,
        soldItemsSumCents: 0,
        soldItemsCount: 0,
        returnSnapshotMissingCount: affectedItemIds.length,
      };
    })(),
    affectedItemIds,
    affectedProjectPriceCents,
    missingAffectedItems,
  } : null;

  if (!consolidatedReturn) {
    blockers.push({ reason: 'Could not identify the current consolidated Witzenman Return.' });
  }
  if (returnAudit?.missingAffectedItems.length) {
    blockers.push({
      reason: 'One or more affected items are missing, so the stale Return audit cannot be reconciled safely.',
      itemIds: returnAudit.missingAffectedItems,
    });
  }

  return {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    accountId,
    projectId,
    originalReturnIds: [...backupReturnIds].sort(),
    originalSaleCandidateCount: originalCandidates.length,
    historicalCandidates: historical,
    currentInvalidSaleEdgeCount: currentInvalid.length,
    operations,
    returnMembership,
    returnAudit,
    blockers,
    notes: [
      'This manifest never deletes transactions or rewrites association edges.',
      'No legacy per-item Return snapshot is synthesized because the original backup contains aggregate Return totals only.',
      'Post-consolidation candidates are listed separately by evidence and require explicit review before apply.',
    ],
    reviewed: false,
  };
}

function repairBackupDocuments(live, manifest) {
  const edgeIds = new Set(manifest.operations.map((operation) => operation.edgeId));
  const transactionId = manifest.returnMembership?.transactionId;
  const tx = live.transactions.find((entry) => entry.id === transactionId);
  const edges = live.lineageEdges.filter((entry) => edgeIds.has(entry.id));
  return {
    schemaVersion: 1,
    createdAt: new Date().toISOString(),
    kind: 'witzenman-return-lineage-repair-prewrite',
    accountId: manifest.accountId,
    projectId: manifest.projectId,
    manifestSha256: crypto.createHash('sha256').update(JSON.stringify(manifest)).digest('hex'),
    transactions: tx ? [{ path: tx.path, id: tx.id, data: serialize(tx.data) }] : [],
    lineageEdges: edges.map((edge) => ({ path: edge.path, id: edge.id, data: serialize(edge.data) })),
  };
}

async function applyManifest(db, manifest, live, backupPath) {
  assert(manifest.reviewed === true, 'Manifest must be edited/reviewed and set reviewed: true before apply.');
  assert(manifest.accountId && manifest.projectId, 'Manifest is missing account/project scope.');
  assert(manifest.blockers.length === 0, 'Manifest contains blockers; resolve them before apply.');
  assert(manifest.operations.length > 0 || manifest.returnMembership, 'Manifest contains no repair scope.');

  const liveByPath = new Map([
    ...live.lineageEdges.map((entry) => [entry.path, entry]),
    ...live.transactions.map((entry) => [entry.path, entry]),
  ]);
  const prewrite = repairBackupDocuments(live, manifest);
  if (fs.existsSync(path.resolve(backupPath))) {
    const existing = readJson(backupPath);
    assert(existing.manifestSha256 === prewrite.manifestSha256,
      'Existing pre-write backup belongs to a different repair manifest.');
    assert(JSON.stringify(existing.transactions) === JSON.stringify(prewrite.transactions)
      && JSON.stringify(existing.lineageEdges) === JSON.stringify(prewrite.lineageEdges),
      'Existing pre-write backup does not match the current live repair targets.');
  } else {
    writeJsonExclusive(backupPath, prewrite);
  }

  assert(manifest.operations.length < MAX_BATCH_WRITES,
    `Repair manifest has too many operations for one atomic batch: ${manifest.operations.length}`);
  const batch = db.batch();
  for (const operation of manifest.operations) {
    const current = liveByPath.get(operation.path);
    assert(current, `Repair target is missing: ${operation.path}`);
    assert(valueOrNull(current.data.fromTransactionId) === operation.before.fromTransactionId,
      `Precondition failed for ${operation.path}: fromTransactionId changed.`);
    assert(valueOrNull(current.data.fromProjectId) === operation.before.fromProjectId,
      `Precondition failed for ${operation.path}: fromProjectId changed.`);
    batch.update(db.doc(operation.path), {
      fromTransactionId: null,
      fromProjectId: null,
      repairKind: 'witzenman-return-lineage-v1',
      repairedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  const membership = manifest.returnMembership;
  const auditPlan = manifest.returnAudit;
  if (membership) {
    const current = liveByPath.get(`accounts/${manifest.accountId}/transactions/${membership.transactionId}`);
    assert(current, `Return target is missing: ${membership.transactionId}`);
    assert(auditPlan, 'Manifest is missing the Return audit repair plan.');
    const actual = Array.isArray(current.data.returnedItemIds) ? [...current.data.returnedItemIds].sort() : null;
    assert(JSON.stringify(actual) === JSON.stringify(membership.before),
      `Precondition failed for Return ${membership.transactionId}: returnedItemIds changed.`);
    assert(JSON.stringify(current.data.audit ?? null) === JSON.stringify(auditPlan.before),
      `Precondition failed for Return ${membership.transactionId}: audit changed.`);
    batch.update(db.doc(current.path), {
      returnedItemIds: membership.after,
      audit: auditPlan.after,
      repairKind: 'witzenman-return-lineage-v1',
      repairedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  console.log(`Applied ${manifest.operations.length} edge repair(s) and Return membership repair.`);
}

function verifyManifest(live, manifest) {
  const returnIds = new Set(
    live.transactions
      .filter((tx) => tx.data.projectId === manifest.projectId && normalizeType(tx.data.type ?? tx.data.transactionType) === 'return')
      .map((tx) => tx.id)
  );
  const invalid = live.lineageEdges.filter((edge) =>
    SALE_KINDS.has(edge.data.movementKind)
      && (returnIds.has(edge.data.fromTransactionId) || returnIds.has(edge.data.toTransactionId))
  );
  const consolidatedReturn = live.transactions.find((tx) =>
    tx.id === manifest.returnMembership?.transactionId
  ) ?? selectConsolidatedReturn(live, manifest.projectId);
  const result = {
    verifiedAt: new Date().toISOString(),
    accountId: manifest.accountId,
    projectId: manifest.projectId,
    invalidSaleEndpoints: invalid.map((edge) => ({
      edgeId: edge.id,
      itemId: edge.data.itemId ?? null,
      fromTransactionId: valueOrNull(edge.data.fromTransactionId),
      toTransactionId: valueOrNull(edge.data.toTransactionId),
      movementKind: edge.data.movementKind ?? null,
    })),
    returnAudit: manifest.returnAudit ? {
      soldItemsCount: consolidatedReturn?.data.audit?.soldItemsCount ?? null,
      soldItemsSumCents: consolidatedReturn?.data.audit?.soldItemsSumCents ?? null,
      returnedItemsCount: consolidatedReturn?.data.audit?.returnedItemsCount ?? null,
      returnedItemsSumCents: consolidatedReturn?.data.audit?.returnedItemsSumCents ?? null,
    } : null,
    passed: invalid.length === 0
      && (!manifest.returnAudit || (
        (consolidatedReturn?.data.audit?.soldItemsCount ?? null) === 0
        && (consolidatedReturn?.data.audit?.soldItemsSumCents ?? null) === 0
      )),
  };
  console.log(JSON.stringify(result, null, 2));
  return result;
}

async function main() {
  const options = parseArgs(process.argv);
  if (options.help) return printHelp();
  assert(!options.apply || fs.existsSync(path.resolve(options.manifest)), `Manifest not found: ${options.manifest}`);
  const backup = readJson(options.backupInput);
  const db = initFirestore();
  const live = await loadLive(db, options.accountId);

  if (options.verify) {
    const manifest = options.manifest ? readJson(options.manifest) : { accountId: options.accountId, projectId: options.projectId };
    const result = verifyManifest(live, manifest);
    if (!result.passed) process.exitCode = 2;
    return;
  }

  const manifest = analyze({ backup, live, accountId: options.accountId, projectId: options.projectId });
  if (options.backupOnly) {
    assert(options.backupOutput, '--backup-only requires --backup <path>');
    const current = options.manifest
      ? repairBackupDocuments(live, readJson(options.manifest))
      : {
          schemaVersion: 1,
          createdAt: new Date().toISOString(),
          kind: 'witzenman-return-lineage-repair-readonly-backup',
          accountId: options.accountId,
          projectId: options.projectId,
          originalBackup: path.resolve(options.backupInput),
          originalBackupSha256: sha256File(options.backupInput),
          transactions: live.transactions.map((entry) => ({ path: entry.path, id: entry.id, data: serialize(entry.data) })),
          lineageEdges: live.lineageEdges.map((entry) => ({ path: entry.path, id: entry.id, data: serialize(entry.data) })),
        };
    console.log(`Wrote read-only backup: ${writeJsonExclusive(options.backupOutput, current)}`);
    return;
  }

  if (options.apply) {
    const reviewedManifest = readJson(options.manifest);
    assert(reviewedManifest.accountId === options.accountId, 'Manifest account does not match --account.');
    assert(reviewedManifest.projectId === options.projectId, 'Manifest project does not match --project-id.');
    await applyManifest(db, reviewedManifest, live, options.backupOutput);
    const after = await loadLive(db, options.accountId);
    verifyManifest(after, reviewedManifest);
    return;
  }

  if (options.approvePlan) {
    manifest.reviewed = true;
    manifest.reviewedAt = new Date().toISOString();
  }
  const output = options.out ? writeJsonExclusive(options.out, manifest) : null;
  console.log(JSON.stringify({
    mode: 'dry-run',
    output,
    originalSaleCandidateCount: manifest.originalSaleCandidateCount,
    currentInvalidSaleEdgeCount: manifest.currentInvalidSaleEdgeCount,
    plannedEdgeRepairs: manifest.operations.length,
    blockers: manifest.blockers,
    returnMembership: manifest.returnMembership,
    message: 'No Firebase writes performed. Review the manifest and set reviewed: true before any separately authorized apply.',
  }, null, 2));
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`ERROR: ${error.message}`);
    process.exitCode = 1;
  });
}

export { analyze, originalReturnIds, originalSaleCandidates };
