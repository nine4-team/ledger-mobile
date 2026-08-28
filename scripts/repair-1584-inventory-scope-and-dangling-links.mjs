#!/usr/bin/env node

/**
 * Repair the reviewed 1584 Design inventory-scope cohort and three dangling
 * item→transaction references.
 *
 * Dry-run:
 *   FIREBASE_ACCESS_TOKEN=... node scripts/repair-1584-inventory-scope-and-dangling-links.mjs
 *
 * Apply exactly the reviewed plan:
 *   FIREBASE_ACCESS_TOKEN=... node scripts/repair-1584-inventory-scope-and-dangling-links.mjs \
 *     --apply --expected-plan-hash=<hash printed by dry-run>
 */

import crypto from 'node:crypto';
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import admin from 'firebase-admin';

const PROJECT_ID = 'ledger-nine4';
const ACCOUNT_ID = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const FURNISHINGS_ID = 'da556858-1df8-40be-b10c-b15710d7cc9a';
const INVENTORY_LABEL = '1584 Design Inventory';
const APPLY = process.argv.includes('--apply');
const expectedHashArg = process.argv.find((arg) => arg.startsWith('--expected-plan-hash='));
const EXPECTED_PLAN_HASH = expectedHashArg?.split('=', 2)[1] ?? null;

const EXPECTED_MISSING_PROJECT_NO_CATEGORY_IDS = [
  '4o2WAyUQKXwNBWL6whNU',
  'Jh5TKLc89IoEGFFJ92cD',
  'NCFbLAWwpNcTPYtm5iMh',
  'Rg8JFT2kDTrCjSc3yXLP',
  'XZJ6POEDxP2iJB1npcyL',
  'c9SnOm4Vi6wGq3Q7vvto',
  'k2YkrPN6Mc0GGjN1iYWp',
  'li70JVyVtJUgjq4WJWTn',
];

const EXPECTED_MISSING_PROJECT_WITH_CATEGORY_IDS = [
  'DviGIFmBWKnuBQ0L4Xg3',
  'GqwnnQBHXr6lf9LVVLNR',
  'J49wKCdcsDlphua6Nepb',
  'R8GY3qh3I6S8duIBr0ue',
  'W8Fs2w9d0k4TCEacf8lo',
  'WsvPkx1icYqgHb1RlVOs',
  'boNgYUmq3kgOWt1i3LnT',
  'fhmbqdIMwUSzrIB3wsDE',
  'hrSBopIXNXKBOjCch5TI',
  'hrjMH82zVSLejOKricfF',
  'rFo1VX7H4Gxf2gJwUSIa',
];

const LAMP_ITEM_IDS = ['Sg6QLlQVL59kS0EIJASY', 'lldP1lVmLAn80HstTMw7'];
const DELETED_LAMP_TRANSACTION_ID = 'RoygLqovaS57FhLU0qxg';
const LAMP_REPLACEMENT_TRANSACTION_ID = 'qoei5Sw9L7HaER90bAeo';
const BENCH_ITEM_ID = '0JdSt0xQ8kGL4BqlFcFm';
const BENCH_TRANSACTION_ID = 'IAws2hFz6C3Eb1N8hCu5';
const BENCH_PROJECT_ID = '405GIhLoU2pLY4zqb71R';
const LAMP_PROJECT_ID = '1LLWjydzaK6uD44TjM4u';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function hasOwn(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
}

function sorted(values) {
  return [...values].sort();
}

function sameIds(actual, expected) {
  return JSON.stringify(sorted(actual)) === JSON.stringify(sorted(expected));
}

function timestampKey(snapshot) {
  return `${snapshot.updateTime.seconds}:${snapshot.updateTime.nanoseconds}`;
}

function jsonSafe(value) {
  if (value instanceof admin.firestore.Timestamp) {
    return { __type: 'timestamp', seconds: value.seconds, nanoseconds: value.nanoseconds };
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return { __type: 'geopoint', latitude: value.latitude, longitude: value.longitude };
  }
  if (value instanceof admin.firestore.DocumentReference) {
    return { __type: 'reference', path: value.path };
  }
  if (Array.isArray(value)) return value.map(jsonSafe);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, jsonSafe(child)]));
  }
  return value;
}

function snapshotBackup(snapshot) {
  return {
    path: snapshot.ref.path,
    exists: snapshot.exists,
    createTime: snapshot.createTime ? jsonSafe(snapshot.createTime) : null,
    updateTime: snapshot.updateTime ? jsonSafe(snapshot.updateTime) : null,
    data: snapshot.exists ? jsonSafe(snapshot.data()) : null,
  };
}

const refreshToken = process.env.FIREBASE_REFRESH_TOKEN;
let temporaryCredentialDirectory = null;
if (refreshToken) {
  assert(process.env.FIREBASE_CLIENT_ID && process.env.FIREBASE_CLIENT_SECRET,
    'Firebase CLI refresh-token auth also requires FIREBASE_CLIENT_ID and FIREBASE_CLIENT_SECRET.');
  temporaryCredentialDirectory = mkdtempSync(join(tmpdir(), 'ledger-repair-auth-'));
  const credentialPath = join(temporaryCredentialDirectory, 'application-default-credentials.json');
  writeFileSync(credentialPath, JSON.stringify({
    client_id: process.env.FIREBASE_CLIENT_ID,
    client_secret: process.env.FIREBASE_CLIENT_SECRET,
    refresh_token: refreshToken,
    type: 'authorized_user',
  }), { mode: 0o600 });
  process.env.GOOGLE_APPLICATION_CREDENTIALS = credentialPath;
}
const credential = admin.credential.applicationDefault();
if (temporaryCredentialDirectory) {
  process.on('exit', () => rmSync(temporaryCredentialDirectory, { recursive: true, force: true }));
}

admin.initializeApp({ credential, projectId: PROJECT_ID });
const db = admin.firestore();
const base = `accounts/${ACCOUNT_ID}`;

async function loadState() {
  const [itemsSnap, transactionsSnap, edgesSnap] = await Promise.all([
    db.collection(`${base}/items`).get(),
    db.collection(`${base}/transactions`).get(),
    db.collection(`${base}/lineageEdges`).get(),
  ]);
  return {
    items: new Map(itemsSnap.docs.map((snap) => [snap.id, { snap, data: snap.data() }])),
    transactions: new Map(transactionsSnap.docs.map((snap) => [snap.id, { snap, data: snap.data() }])),
    edges: new Map(edgesSnap.docs.map((snap) => [snap.id, { snap, data: snap.data() }])),
  };
}

function buildPlan(state) {
  const missingProjectItems = [...state.items.values()].filter(({ data }) => !hasOwn(data, 'projectId'));
  const missingProjectNoCategory = [...state.transactions.values()].filter(({ data }) =>
    !hasOwn(data, 'projectId') && !data.budgetCategoryId
  );
  const missingProjectWithCategory = [...state.transactions.values()].filter(({ data }) =>
    !hasOwn(data, 'projectId') && typeof data.budgetCategoryId === 'string' && data.budgetCategoryId.trim()
  );
  const legacyExplicitNullWithCategory = [...state.transactions.values()].filter(({ data }) =>
    hasOwn(data, 'projectId') && data.projectId === null && typeof data.budgetCategoryId === 'string'
  );
  const danglingItems = [...state.items.values()].filter(({ data }) =>
    data.transactionId && !state.transactions.has(data.transactionId)
  );

  assert(missingProjectItems.length === 105, `Expected 105 missing-project items, found ${missingProjectItems.length}`);
  assert(missingProjectItems.every(({ data }) =>
    (!hasOwn(data, 'budgetCategoryId') || data.budgetCategoryId === null) && !data.spaceId
  ), 'A missing-project item gained a category or project space; aborting.');
  assert(sameIds(missingProjectNoCategory.map(({ snap }) => snap.id), EXPECTED_MISSING_PROJECT_NO_CATEGORY_IDS),
    'Missing-project/no-category transaction cohort changed; aborting.');
  assert(sameIds(missingProjectWithCategory.map(({ snap }) => snap.id), EXPECTED_MISSING_PROJECT_WITH_CATEGORY_IDS),
    'Missing-project/categorized transaction cohort changed; aborting.');
  assert(legacyExplicitNullWithCategory.length === 76,
    `Expected 76 grandfathered legacy transactions, found ${legacyExplicitNullWithCategory.length}`);
  assert(sameIds(danglingItems.map(({ snap }) => snap.id), [BENCH_ITEM_ID, ...LAMP_ITEM_IDS]),
    'Dangling item cohort changed; aborting.');

  const replacement = state.transactions.get(LAMP_REPLACEMENT_TRANSACTION_ID);
  assert(replacement, 'Lamp replacement transaction is missing.');
  assert(replacement.data.projectId === LAMP_PROJECT_ID, 'Lamp replacement project changed.');
  assert(replacement.data.budgetCategoryId === FURNISHINGS_ID, 'Lamp replacement category changed.');
  assert(replacement.data.amountCents === 28175 && replacement.data.subtotalCents === 25998,
    'Lamp replacement totals changed.');
  assert((replacement.data.source ?? '').toLowerCase() === 'homegoods', 'Lamp replacement vendor changed.');
  assert(replacement.data.transactionDate === '2026-08-18', 'Lamp replacement date changed.');
  assert((replacement.data.itemIds ?? []).length === 0, 'Lamp replacement already has unexpected items.');

  const lampItems = LAMP_ITEM_IDS.map((id) => state.items.get(id));
  assert(lampItems.every(Boolean), 'A lamp item is missing.');
  for (const { data } of lampItems) {
    assert(data.transactionId === DELETED_LAMP_TRANSACTION_ID, 'A lamp transaction link changed.');
    assert(data.projectId === LAMP_PROJECT_ID && data.budgetCategoryId === FURNISHINGS_ID,
      'A lamp project/category changed.');
    assert(data.purchasePriceCents === 12999 && data.projectPriceCents === 12999,
      'A lamp price changed.');
  }

  const bench = state.items.get(BENCH_ITEM_ID);
  assert(bench, 'Bench item is missing.');
  assert(bench.data.transactionId === BENCH_TRANSACTION_ID, 'Bench transaction link changed.');
  assert(bench.data.projectId === BENCH_PROJECT_ID && bench.data.budgetCategoryId === FURNISHINGS_ID,
    'Bench project/category changed.');
  assert(bench.data.projectPriceCents === 12999, 'Bench project price changed.');
  assert(bench.data.currentSource === INVENTORY_LABEL, 'Bench current source changed.');
  assert(!state.transactions.has(BENCH_TRANSACTION_ID), 'Bench transaction unexpectedly exists.');
  assert(!state.transactions.has(DELETED_LAMP_TRANSACTION_ID), 'Deleted lamp transaction unexpectedly exists.');
  const benchEdges = [...state.edges.values()].filter(({ data }) =>
    data.itemId === BENCH_ITEM_ID &&
    data.toTransactionId === BENCH_TRANSACTION_ID &&
    data.movementKind === 'sold'
  );
  assert(benchEdges.length === 1, `Expected one bench sale lineage edge, found ${benchEdges.length}`);

  const mutations = [
    ...missingProjectItems.map(({ snap }) => ({ path: snap.ref.path, op: 'normalize-inventory-item', stamp: timestampKey(snap) })),
    ...missingProjectNoCategory.map(({ snap }) => ({ path: snap.ref.path, op: 'normalize-inventory-transaction', stamp: timestampKey(snap) })),
    ...missingProjectWithCategory.map(({ snap, data }) => ({
      path: snap.ref.path,
      op: 'normalize-inventory-acquisition',
      category: data.budgetCategoryId,
      stamp: timestampKey(snap),
    })),
    { path: replacement.snap.ref.path, op: 'attach-lamp-items', stamp: timestampKey(replacement.snap) },
    ...lampItems.map(({ snap }) => ({ path: snap.ref.path, op: 'relink-lamp-item', stamp: timestampKey(snap) })),
    { path: `${base}/transactions/${BENCH_TRANSACTION_ID}`, op: 'restore-bench-transaction', stamp: 'absent' },
  ];
  const planHash = crypto.createHash('sha256')
    .update(JSON.stringify(mutations.sort((a, b) => a.path.localeCompare(b.path))))
    .digest('hex');

  return {
    missingProjectItems,
    missingProjectNoCategory,
    missingProjectWithCategory,
    legacyExplicitNullWithCategory,
    danglingItems,
    replacement,
    lampItems,
    bench,
    benchEdge: benchEdges[0],
    mutations,
    planHash,
  };
}

function writeBackup(plan) {
  const logDir = join(dirname(fileURLToPath(import.meta.url)), 'migration-logs');
  mkdirSync(logDir, { recursive: true });
  const timestamp = new Date().toISOString().replaceAll(':', '-');
  const path = join(logDir, `repair-1584-inventory-scope-${timestamp}.before.json`);
  const uniqueSnapshots = new Map();
  for (const row of [
    ...plan.missingProjectItems,
    ...plan.missingProjectNoCategory,
    ...plan.missingProjectWithCategory,
    ...plan.danglingItems,
    plan.replacement,
    plan.benchEdge,
  ]) {
    uniqueSnapshots.set(row.snap.ref.path, row.snap);
  }
  const payload = {
    projectId: PROJECT_ID,
    accountId: ACCOUNT_ID,
    createdAt: new Date().toISOString(),
    planHash: plan.planHash,
    documents: [...uniqueSnapshots.values()].map(snapshotBackup),
    absentDocuments: [
      `${base}/transactions/${BENCH_TRANSACTION_ID}`,
      `${base}/transactions/${DELETED_LAMP_TRANSACTION_ID}`,
    ],
  };
  writeFileSync(path, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
  chmodSync(path, 0o600);
  return path;
}

async function applyPlan(plan) {
  assert(EXPECTED_PLAN_HASH, 'Apply requires --expected-plan-hash=<dry-run hash>.');
  assert(EXPECTED_PLAN_HASH === plan.planHash,
    `Plan hash changed: expected ${EXPECTED_PLAN_HASH}, actual ${plan.planHash}`);

  const backupPath = writeBackup(plan);
  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const { snap } of plan.missingProjectItems) {
    batch.update(snap.ref, {
      projectId: null,
      budgetCategoryId: null,
      updatedAt: now,
    }, { lastUpdateTime: snap.updateTime });
  }
  for (const { snap } of plan.missingProjectNoCategory) {
    batch.update(snap.ref, { projectId: null, updatedAt: now }, { lastUpdateTime: snap.updateTime });
  }
  for (const { snap, data } of plan.missingProjectWithCategory) {
    batch.update(snap.ref, {
      projectId: null,
      budgetCategoryId: null,
      intendedBudgetCategoryId: data.budgetCategoryId,
      purchaseHandling: 'inventory_resale',
      updatedAt: now,
    }, { lastUpdateTime: snap.updateTime });
  }

  batch.update(plan.replacement.snap.ref, {
    itemIds: LAMP_ITEM_IDS,
    updatedAt: now,
  }, { lastUpdateTime: plan.replacement.snap.updateTime });
  for (const { snap } of plan.lampItems) {
    batch.update(snap.ref, {
      transactionId: LAMP_REPLACEMENT_TRANSACTION_ID,
      updatedAt: now,
    }, { lastUpdateTime: snap.updateTime });
  }

  batch.create(db.doc(`${base}/transactions/${BENCH_TRANSACTION_ID}`), {
    type: 'Purchase',
    source: INVENTORY_LABEL,
    projectId: BENCH_PROJECT_ID,
    budgetCategoryId: FURNISHINGS_ID,
    amountCents: 12999,
    subtotalCents: 12999,
    itemIds: [BENCH_ITEM_ID],
    isComplete: true,
    transactionDate: '2026-06-30',
    createdAt: plan.benchEdge.data.createdAt,
    updatedAt: now,
    notes: 'Data repair 2026-08-28: reconstructed the deleted inventory-to-Kapcsos purchase from the surviving item and sold lineage edge.',
  });

  await batch.commit();
  return backupPath;
}

async function verify() {
  const state = await loadState();
  const missingItems = [...state.items.values()].filter(({ data }) => !hasOwn(data, 'projectId'));
  const missingTransactions = [...state.transactions.values()].filter(({ data }) => !hasOwn(data, 'projectId'));
  const dangling = [...state.items.values()].filter(({ data }) =>
    data.transactionId && !state.transactions.has(data.transactionId)
  );
  const repairedAcquisitions = EXPECTED_MISSING_PROJECT_WITH_CATEGORY_IDS.map((id) => state.transactions.get(id));
  assert(missingItems.length === 0, `${missingItems.length} items still omit projectId.`);
  assert(missingTransactions.length === 0, `${missingTransactions.length} transactions still omit projectId.`);
  assert(dangling.length === 0, `${dangling.length} dangling item transaction links remain.`);
  assert(repairedAcquisitions.every(({ data }) =>
    data.projectId === null &&
    data.budgetCategoryId === null &&
    data.intendedBudgetCategoryId === FURNISHINGS_ID &&
    data.purchaseHandling === 'inventory_resale'
  ), 'An inventory acquisition did not receive the canonical repaired shape.');
  const replacement = state.transactions.get(LAMP_REPLACEMENT_TRANSACTION_ID);
  assert(sameIds(replacement.data.itemIds ?? [], LAMP_ITEM_IDS), 'Lamp replacement membership is wrong.');
  assert(LAMP_ITEM_IDS.every((id) => state.items.get(id).data.transactionId === LAMP_REPLACEMENT_TRANSACTION_ID),
    'A lamp was not relinked.');
  const benchTx = state.transactions.get(BENCH_TRANSACTION_ID);
  assert(benchTx?.data.projectId === BENCH_PROJECT_ID &&
    sameIds(benchTx.data.itemIds ?? [], [BENCH_ITEM_ID]) &&
    benchTx.data.amountCents === 12999,
  'Bench transaction reconstruction is incomplete.');
  const legacyCount = [...state.transactions.values()].filter(({ data }) =>
    hasOwn(data, 'projectId') && data.projectId === null && typeof data.budgetCategoryId === 'string'
  ).length;
  assert(legacyCount === 76, `Grandfathered legacy cohort changed: expected 76, found ${legacyCount}`);
  return {
    missingProjectItems: missingItems.length,
    missingProjectTransactions: missingTransactions.length,
    danglingItemLinks: dangling.length,
    repairedInventoryAcquisitions: repairedAcquisitions.length,
    grandfatheredLegacyTransactionsUntouched: legacyCount,
  };
}

const initialState = await loadState();
const plan = buildPlan(initialState);
console.log(JSON.stringify({
  mode: APPLY ? 'apply' : 'dry-run',
  accountId: ACCOUNT_ID,
  planHash: plan.planHash,
  writes: plan.mutations.length,
  missingProjectItems: plan.missingProjectItems.length,
  missingProjectTransactionsWithoutCategory: plan.missingProjectNoCategory.length,
  missingProjectInventoryAcquisitions: plan.missingProjectWithCategory.length,
  danglingItemsToRepair: plan.danglingItems.map(({ snap }) => snap.id),
  grandfatheredLegacyTransactionsUntouched: plan.legacyExplicitNullWithCategory.length,
}, null, 2));

if (APPLY) {
  const backupPath = await applyPlan(plan);
  const verification = await verify();
  console.log(JSON.stringify({ applied: true, backupPath, verification }, null, 2));
} else {
  console.log('Dry-run only. No documents changed.');
}
