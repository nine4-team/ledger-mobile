#!/usr/bin/env node
/**
 * Repair Kapcsos Martinique Rental inventory sales that were written at $0.
 *
 * Read-only by default. Pass --commit to write.
 */

import admin from 'firebase-admin';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const ACCOUNT_ID = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const PROJECT_ID_KAPCSOS = '405GIhLoU2pLY4zqb71R';
const CATEGORY_ID = 'da556858-1df8-40be-b10c-b15710d7cc9a';
const INVENTORY_LABEL = '1584 Design Inventory';
const COMMIT = process.argv.includes('--commit');

const ITEMS = [
  {
    id: 'xWT51cNVX58eIomO3PHg',
    name: 'Bronze curtain rings',
    transactionId: '7wegKK0ssG1I8rfrF8pJ',
    purchasePriceCents: 1500,
    projectPriceCents: 2000,
  },
  {
    id: '2BiQqajdVa22lXXR3crn',
    name: 'Woven hanger',
    transactionId: 'FFQ2ZMEsFYNTcZyQHk8s',
    purchasePriceCents: 824,
    projectPriceCents: 1099,
  },
  {
    id: 'S7dCMqwf7FWof0BlWhze',
    name: 'Woven hanger',
    transactionId: 'FFQ2ZMEsFYNTcZyQHk8s',
    purchasePriceCents: 824,
    projectPriceCents: 1099,
  },
];

const TRANSACTIONS = [
  {
    id: '7wegKK0ssG1I8rfrF8pJ',
    itemIds: ['xWT51cNVX58eIomO3PHg'],
    subtotalCents: 2000,
    amountCents: 2000,
  },
  {
    id: 'FFQ2ZMEsFYNTcZyQHk8s',
    itemIds: ['2BiQqajdVa22lXXR3crn', 'S7dCMqwf7FWof0BlWhze'],
    subtotalCents: 2198,
    amountCents: 2198,
  },
];

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

function itemPath(id) {
  return `accounts/${ACCOUNT_ID}/items/${id}`;
}

function transactionPath(id) {
  return `accounts/${ACCOUNT_ID}/transactions/${id}`;
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sameMembers(actual, expected) {
  return Array.isArray(actual)
    && actual.length === expected.length
    && [...actual].sort().join('|') === [...expected].sort().join('|');
}

function normalize(value) {
  return String(value ?? '').trim().toLowerCase();
}

async function loadSnapshot(reader = db) {
  const refs = [
    ...ITEMS.map((item) => db.doc(itemPath(item.id))),
    ...TRANSACTIONS.map((tx) => db.doc(transactionPath(tx.id))),
  ];
  const docs = reader === db ? await db.getAll(...refs) : await reader.getAll(...refs);
  return new Map(docs.map((doc) => [doc.ref.path, doc]));
}

function validateSnapshot(byPath) {
  for (const expected of ITEMS) {
    const snap = byPath.get(itemPath(expected.id));
    assert(snap?.exists, `Missing item ${expected.id}`);
    const item = snap.data() ?? {};
    assert(item.name === expected.name, `${expected.id}.name changed`);
    assert(item.projectId === PROJECT_ID_KAPCSOS, `${expected.id}.projectId changed`);
    assert(item.budgetCategoryId === CATEGORY_ID, `${expected.id}.budgetCategoryId changed`);
    assert(item.transactionId === expected.transactionId, `${expected.id}.transactionId changed`);
    assert(item.currentSource === INVENTORY_LABEL, `${expected.id}.currentSource changed`);
    assert((item.projectPriceCents ?? 0) <= 0, `${expected.id}.projectPriceCents is no longer zero/missing`);
  }

  for (const expected of TRANSACTIONS) {
    const snap = byPath.get(transactionPath(expected.id));
    assert(snap?.exists, `Missing transaction ${expected.id}`);
    const tx = snap.data() ?? {};
    assert(normalize(tx.type) === 'purchase', `${expected.id}.type changed`);
    assert(tx.source === INVENTORY_LABEL, `${expected.id}.source changed`);
    assert(tx.projectId === PROJECT_ID_KAPCSOS, `${expected.id}.projectId changed`);
    assert(tx.budgetCategoryId === CATEGORY_ID, `${expected.id}.budgetCategoryId changed`);
    assert(sameMembers(tx.itemIds, expected.itemIds), `${expected.id}.itemIds changed`);
    assert((tx.amountCents ?? 0) <= 0, `${expected.id}.amountCents is no longer zero/missing`);
  }
}

function buildPlan() {
  return {
    mode: COMMIT ? 'COMMIT' : 'DRY_RUN',
    firestoreProjectId: PROJECT_ID,
    accountId: ACCOUNT_ID,
    items: ITEMS.map((item) => ({
      id: item.id,
      name: item.name,
      purchasePriceCents: item.purchasePriceCents,
      projectPriceCents: item.projectPriceCents,
    })),
    transactions: TRANSACTIONS.map((tx) => ({
      id: tx.id,
      subtotalCents: tx.subtotalCents,
      amountCents: tx.amountCents,
      itemIds: tx.itemIds,
    })),
  };
}

async function commitRepair() {
  await db.runTransaction(async (tx) => {
    const byPath = await loadSnapshot(tx);
    validateSnapshot(byPath);
    const now = FieldValue.serverTimestamp();

    for (const item of ITEMS) {
      tx.update(db.doc(itemPath(item.id)), {
        purchasePriceCents: item.purchasePriceCents,
        projectPriceCents: item.projectPriceCents,
        updatedAt: now,
      });
    }

    for (const transaction of TRANSACTIONS) {
      tx.update(db.doc(transactionPath(transaction.id)), {
        subtotalCents: transaction.subtotalCents,
        amountCents: transaction.amountCents,
        updatedAt: now,
        repairNote: 'Admin repair 2026-08-21: set Kapcsos inventory sale total from item project prices after zero-dollar sale write.',
      });
    }
  });
}

async function verify() {
  const byPath = await loadSnapshot();
  return {
    items: ITEMS.map((expected) => {
      const item = byPath.get(itemPath(expected.id)).data() ?? {};
      return {
        id: expected.id,
        name: item.name ?? null,
        purchasePriceCents: item.purchasePriceCents ?? null,
        projectPriceCents: item.projectPriceCents ?? null,
        transactionId: item.transactionId ?? null,
      };
    }),
    transactions: TRANSACTIONS.map((expected) => {
      const tx = byPath.get(transactionPath(expected.id)).data() ?? {};
      return {
        id: expected.id,
        subtotalCents: tx.subtotalCents ?? null,
        amountCents: tx.amountCents ?? null,
        itemIds: tx.itemIds ?? null,
        repairNote: tx.repairNote ?? null,
      };
    }),
  };
}

try {
  const byPath = await loadSnapshot();
  validateSnapshot(byPath);
  console.log(JSON.stringify(buildPlan(), null, 2));
  if (!COMMIT) {
    console.log('\nDry-run only. Re-run with --commit to write.');
    process.exit(0);
  }
  await commitRepair();
  console.log('\nCommitted repair.');
  console.log(JSON.stringify(await verify(), null, 2));
} catch (error) {
  console.error(error);
  process.exit(1);
}
