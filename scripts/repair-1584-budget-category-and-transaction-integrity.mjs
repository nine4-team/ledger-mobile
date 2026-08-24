#!/usr/bin/env node

/**
 * Repair the reviewed 1584 Design budget-category and transaction cohorts.
 *
 * Dry-run by default:
 *   node scripts/repair-1584-budget-category-and-transaction-integrity.mjs
 *
 * Apply after all preconditions pass:
 *   node scripts/repair-1584-budget-category-and-transaction-integrity.mjs --apply
 */

import crypto from 'node:crypto';
import admin from 'firebase-admin';

const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const ACCOUNT_ID = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const FURNISHINGS_ID = 'da556858-1df8-40be-b10c-b15710d7cc9a';
const APPLY = process.argv.includes('--apply');

const EXPECTED_CANONICAL_BLANK_COUNT = 699;
const EXPECTED_CANONICAL_BLANK_HASH = '2c4565736c70734e188c8817b92cd22dba50604285145120b2b2445f4d45cc7d';
const EXPECTED_INVENTORY_CATEGORY_COUNT = 222;
const EXPECTED_INVENTORY_CATEGORY_HASH = '14286b8a56cbcb06ebb8e6075b69ef3e2535b80092612d93cb818b21d644e2bd';

const TRANSACTION_CATEGORY_TARGETS = [
  '0F2B932B-6D73-4A86-9C6E-77A7E4A2924F',
  '280B2DB3-35A7-465C-9BD8-BCE83CC5E011',
  '2B55CDD8-3B27-4031-9FCB-18F83FB38C75',
  '4C8E9577-8B6C-402F-B639-71E68B57DED6',
  '4D83F5B0-13A4-4CD2-AF78-1B1E6FEEB8F7',
  '52857D52-70AC-4C97-9103-73E909BC1FFF',
  '645FCE00-92AB-4E6A-886C-C1FA719FA1E5',
  'AE2AB6D1-D918-4B2B-ADAB-7F6DC53F4183',
  'AFD21A64-F0C1-4592-A823-19A63A6537F2',
  'CC10307C-2EE0-47A4-9615-7139E582E366',
  'FBCB4BCE-0F60-4E4B-806A-2C0F890927E1',
  'SALE_c093c11b-6c1e-4c54-9df2-e7ee3c74a5f0_business_to_project_uncategorized',
];

const SENTINEL_ITEM_IDS = [
  '8uz0UJncy4jwJn8hoWgG',
  'ATN3wC4PRb9WtmmFxLba',
  'cNdL5v1m0ELMUH4cYRed',
  'eFQSGG0nn9Z3Bm72GXED',
  'hvtkV6uRkM0BDAbGF9Oz',
  'PxjFTP0k5auSTSitITJ3',
  'QRQ3Tt9Iw95GY09lPtJR',
  'qzgrjwsDlmBWNj4vhE9V',
  'TYYRdQbYeagRKeXhtSPA',
  'WbH3Hp1uRwxPyg0uAor0',
];

const CATEGORY_MISMATCH_ITEM_IDS = [
  'I-1767140664062-0b2v',
  'I-1767140664062-6v4b',
  'I-1767140664062-fcth',
  'I-1767140664062-ilhl',
  'I-1767140664062-l67j',
  'I-1767140664062-lits',
];

const EXISTING_TRANSACTION_LINKS = {
  '53ef2f6b-5018-4f95-aee8-fd05a7c9602e': ['I-1767120704519-o3du'],
  '7638e8ad-c8ce-427c-8914-55542e927107': ['I-1768420030214-9p60'],
  'c3df4180-7e7b-4e1f-a937-238acc1f6b89': [
    'I-1767813246734-lkba',
    'I-1767813326972-d04h',
    'I-1767813435724-lflu',
    'I-1767813501948-tbco',
    'I-1767813513172-r0v3',
    'I-1767813528867-q3br',
    'I-1767813544341-ivvg',
    'I-1767813550348-1l9c',
    'I-1767813603282-e94f',
    'I-1767813997456-stb0',
  ],
  '54e74bfe-28c3-4f0b-8494-e8e582cf5f88': [
    'UnDTVfY1ZYqUItkVXU6m',
    'V63IqFQSK26CGCaptgi1',
  ],
  'eee852d3-3896-477e-820f-af4853a0b08d': [
    'g8CjWCWqDQVduBkocCyu',
    'nIuICQSnIY8ZQQxwRgQZ',
  ],
};

const NEW_REPAIR_TRANSACTIONS = [
  {
    id: 'REPAIR_20260824_WITZENMAN_POTTERY_BARN',
    projectId: '5abd46c9-9886-4b3e-b2b1-19f6cf995a44',
    source: 'Pottery Barn',
    itemIds: [
      '1DrwdqdnBjU77JX67GgB',
      'CImTaK6cl9nqzRigAQvV',
      'cXU9vEJfdXPXKDGo6UU6',
      'tvKgCS8StRXsghcB76Qb',
      'ybq5piDJYgCauWdWn4DL',
    ],
    amountCents: 32668,
  },
  {
    id: 'REPAIR_20260824_WITZENMAN_HOMEGOODS',
    projectId: '5abd46c9-9886-4b3e-b2b1-19f6cf995a44',
    source: 'Homegoods',
    itemIds: ['eohYQB1fuzq9ghsnuBdf'],
    amountCents: 5999,
  },
  {
    id: 'REPAIR_20260824_HYER_THRIFT_2025_12_30',
    projectId: '0ee567e7-ae7b-4816-910f-2296368a6e60',
    source: 'Thrift store',
    itemIds: ['I-1767121773605-4aae', 'I-1767122593888-mooc'],
    amountCents: 998,
    transactionDate: '2025-12-30',
  },
  {
    id: 'REPAIR_20260824_HYER_HOMEGOODS_2026_01_12',
    projectId: '0ee567e7-ae7b-4816-910f-2296368a6e60',
    source: 'Homegoods',
    itemIds: ['I-1768252832664-xnq3'],
    amountCents: 3999,
    transactionDate: '2026-01-12',
  },
  {
    id: 'REPAIR_20260824_HYER_HOMEGOODS_2026_01_20',
    projectId: '0ee567e7-ae7b-4816-910f-2296368a6e60',
    source: 'Homegoods',
    itemIds: ['I-1768941168217-hspv'],
    amountCents: 4000,
    transactionDate: '2026-01-20',
  },
];

const DUPLICATE_ITEM_ID = 'i1veNDGZylm87SmuEQay';
const DUPLICATE_SURVIVOR_ID = 'I-1770258762006-q6yt';
const DUPLICATE_SURVIVOR_TRANSACTION_ID =
  'SALE_fc4e8569-75f6-46b4-97ae-c4bc57f615d0_business_to_project_da556858-1df8-40be-b10c-b15710d7cc9a';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function isBlank(value) {
  return value == null || (typeof value === 'string' && value.trim() === '');
}

function isSentinel(value) {
  return typeof value === 'string' && value.trim().toLowerCase() === 'uncategorized';
}

function hashRows(rows) {
  return crypto.createHash('sha256').update(rows.join('\n')).digest('hex');
}

function sameSet(actual, expected) {
  return actual.length === expected.length && actual.every((value) => expected.includes(value));
}

function itemTotalPurchaseCents(item) {
  const quantity = Number.isFinite(item.quantity) && item.quantity > 0 ? item.quantity : 1;
  return (item.purchasePriceCents ?? 0) * quantity;
}

function uniqueAttachments(...attachmentLists) {
  const seen = new Set();
  const result = [];
  for (const attachment of attachmentLists.flat()) {
    const key = attachment?.url ?? attachment?.fileName ?? JSON.stringify(attachment);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(attachment);
  }
  return result;
}

async function loadState(db) {
  const base = `accounts/${ACCOUNT_ID}`;
  const [itemsSnap, transactionsSnap, projectsSnap, categoriesSnap, invoicesSnap, lineageSnap, protoItemsSnap] =
    await Promise.all([
      db.collection(`${base}/items`).get(),
      db.collection(`${base}/transactions`).get(),
      db.collection(`${base}/projects`).get(),
      db.collection(`${base}/presets/default/budgetCategories`).get(),
      db.collection(`${base}/invoices`).get(),
      db.collection(`${base}/lineageEdges`).get(),
      db.collection(`${base}/protoItems`).get(),
    ]);

  return {
    base,
    items: new Map(itemsSnap.docs.map((doc) => [doc.id, { id: doc.id, ...doc.data() }])),
    transactions: new Map(transactionsSnap.docs.map((doc) => [doc.id, { id: doc.id, ...doc.data() }])),
    projects: new Map(projectsSnap.docs.map((doc) => [doc.id, { id: doc.id, ...doc.data() }])),
    categories: new Map(categoriesSnap.docs.map((doc) => [doc.id, { id: doc.id, ...doc.data() }])),
    invoices: invoicesSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    lineage: lineageSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    protoItems: protoItemsSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
  };
}

async function validatePreconditions(db, state) {
  const { base, items, transactions, projects, categories } = state;
  assert(categories.get(FURNISHINGS_ID)?.name === 'Furnishings', 'Furnishings category is missing or renamed');

  const enabledEntries = await Promise.all(
    [...projects.keys()].map(async (projectId) => {
      const snap = await db.collection(`${base}/projects/${projectId}/budgetCategories`).get();
      return [projectId, new Set(snap.docs.map((doc) => doc.id))];
    })
  );
  const enabledByProject = new Map(enabledEntries);

  const canonicalBlanks = [...items.values()]
    .filter((item) => {
      if (isBlank(item.projectId) || !isBlank(item.budgetCategoryId) || isBlank(item.transactionId)) return false;
      const transaction = transactions.get(item.transactionId);
      return transaction
        && transaction.projectId === item.projectId
        && !isBlank(transaction.budgetCategoryId)
        && !isSentinel(transaction.budgetCategoryId)
        && Array.isArray(transaction.itemIds)
        && transaction.itemIds.includes(item.id);
    })
    .map((item) => {
      const transaction = transactions.get(item.transactionId);
      assert(categories.has(transaction.budgetCategoryId), `Unknown category on transaction ${transaction.id}`);
      assert(
        enabledByProject.get(item.projectId)?.has(transaction.budgetCategoryId),
        `Category ${transaction.budgetCategoryId} is not enabled for project ${item.projectId}`
      );
      return {
        id: item.id,
        projectId: item.projectId,
        transactionId: item.transactionId,
        categoryId: transaction.budgetCategoryId,
      };
    })
    .sort((a, b) => a.id.localeCompare(b.id));
  const canonicalHash = hashRows(
    canonicalBlanks.map((row) => `${row.id}|${row.projectId}|${row.transactionId}|${row.categoryId}`)
  );
  assert(canonicalBlanks.length === EXPECTED_CANONICAL_BLANK_COUNT, `Expected 699 canonical blanks, found ${canonicalBlanks.length}`);
  assert(canonicalHash === EXPECTED_CANONICAL_BLANK_HASH, `Canonical blank cohort hash changed: ${canonicalHash}`);

  const inventoryWithCategory = [...items.values()]
    .filter((item) => isBlank(item.projectId) && !isBlank(item.budgetCategoryId))
    .sort((a, b) => a.id.localeCompare(b.id));
  const inventoryHash = hashRows(inventoryWithCategory.map((item) => `${item.id}|${item.budgetCategoryId}`));
  assert(inventoryWithCategory.length === EXPECTED_INVENTORY_CATEGORY_COUNT, `Expected 222 categorized inventory items, found ${inventoryWithCategory.length}`);
  assert(inventoryHash === EXPECTED_INVENTORY_CATEGORY_HASH, `Categorized inventory cohort hash changed: ${inventoryHash}`);

  const mismatchIds = [...items.values()]
    .filter((item) => {
      if (isBlank(item.projectId) || isBlank(item.budgetCategoryId) || isSentinel(item.budgetCategoryId) || isBlank(item.transactionId)) return false;
      const transaction = transactions.get(item.transactionId);
      return transaction
        && !isBlank(transaction.budgetCategoryId)
        && !isSentinel(transaction.budgetCategoryId)
        && transaction.budgetCategoryId !== item.budgetCategoryId;
    })
    .map((item) => item.id)
    .sort();
  assert(sameSet(mismatchIds, CATEGORY_MISMATCH_ITEM_IDS), `Category mismatch cohort changed: ${mismatchIds.join(', ')}`);
  for (const itemId of CATEGORY_MISMATCH_ITEM_IDS) {
    const item = items.get(itemId);
    const transaction = transactions.get(item.transactionId);
    assert(transaction?.itemIds?.includes(itemId), `Mismatch item ${itemId} is not canonically owned`);
    assert(enabledByProject.get(item.projectId)?.has(transaction.budgetCategoryId), `Mismatch destination category is not enabled for ${itemId}`);
  }

  const sentinelIds = [...items.values()]
    .filter((item) => !isBlank(item.projectId) && isSentinel(item.budgetCategoryId))
    .map((item) => item.id)
    .sort();
  assert(sameSet(sentinelIds, SENTINEL_ITEM_IDS), `Sentinel item cohort changed: ${sentinelIds.join(', ')}`);
  for (const itemId of SENTINEL_ITEM_IDS) {
    const item = items.get(itemId);
    const transaction = transactions.get(item.transactionId);
    assert(transaction?.id === 'CC10307C-2EE0-47A4-9615-7139E582E366', `Sentinel item ${itemId} changed transaction`);
    assert(transaction.itemIds?.includes(itemId), `Sentinel item ${itemId} is not canonically owned`);
  }

  const transactionCategoryIssueIds = [...transactions.values()]
    .filter((transaction) => !isBlank(transaction.projectId) && (isBlank(transaction.budgetCategoryId) || isSentinel(transaction.budgetCategoryId)))
    .map((transaction) => transaction.id)
    .sort();
  assert(
    sameSet(transactionCategoryIssueIds, TRANSACTION_CATEGORY_TARGETS),
    `Transaction category cohort changed: ${transactionCategoryIssueIds.join(', ')}`
  );
  for (const transactionId of TRANSACTION_CATEGORY_TARGETS) {
    const transaction = transactions.get(transactionId);
    assert(transaction, `Missing transaction category target ${transactionId}`);
    assert(enabledByProject.get(transaction.projectId)?.has(FURNISHINGS_ID), `Furnishings is not enabled for transaction ${transactionId}`);
  }

  const noTransactionBlankIds = [...items.values()]
    .filter((item) => !isBlank(item.projectId) && isBlank(item.budgetCategoryId) && isBlank(item.transactionId))
    .map((item) => item.id)
    .sort();
  const plannedBlankOrphanIds = [
    DUPLICATE_ITEM_ID,
    ...Object.values(EXISTING_TRANSACTION_LINKS).flat().filter((itemId) => isBlank(items.get(itemId)?.budgetCategoryId)),
    ...NEW_REPAIR_TRANSACTIONS.flatMap((transaction) => transaction.itemIds),
  ].sort();
  assert(sameSet(noTransactionBlankIds, plannedBlankOrphanIds), `Blank orphan cohort changed: ${noTransactionBlankIds.join(', ')}`);

  const noOrMissingTransactionCategorizedIds = [...items.values()]
    .filter((item) => !isBlank(item.projectId) && !isBlank(item.budgetCategoryId)
      && (isBlank(item.transactionId) || !transactions.has(item.transactionId)))
    .map((item) => item.id)
    .sort();
  const plannedCategorizedLinkIds = Object.values(EXISTING_TRANSACTION_LINKS)
    .flat()
    .filter((itemId) => !isBlank(items.get(itemId)?.budgetCategoryId))
    .sort();
  assert(
    sameSet(noOrMissingTransactionCategorizedIds, plannedCategorizedLinkIds),
    `Categorized transaction-link cohort changed: ${noOrMissingTransactionCategorizedIds.join(', ')}`
  );

  for (const [transactionId, itemIds] of Object.entries(EXISTING_TRANSACTION_LINKS)) {
    const transaction = transactions.get(transactionId);
    assert(transaction, `Missing existing destination transaction ${transactionId}`);
    assert(transaction.budgetCategoryId === FURNISHINGS_ID, `Existing destination ${transactionId} is not Furnishings`);
    for (const itemId of itemIds) {
      const item = items.get(itemId);
      assert(item, `Missing item ${itemId}`);
      assert(item.projectId === transaction.projectId, `Item ${itemId} does not match transaction project`);
      assert(!transaction.itemIds?.includes(itemId), `Item ${itemId} is already owned by ${transactionId}`);
    }
  }

  for (const repairTransaction of NEW_REPAIR_TRANSACTIONS) {
    assert(!transactions.has(repairTransaction.id), `Repair transaction ${repairTransaction.id} already exists`);
    assert(enabledByProject.get(repairTransaction.projectId)?.has(FURNISHINGS_ID), `Furnishings is not enabled for ${repairTransaction.id}`);
    const calculatedAmount = repairTransaction.itemIds.reduce((sum, itemId) => {
      const item = items.get(itemId);
      assert(item, `Missing repair-transaction item ${itemId}`);
      assert(item.projectId === repairTransaction.projectId, `Repair item ${itemId} changed project`);
      assert(isBlank(item.transactionId) && isBlank(item.budgetCategoryId), `Repair item ${itemId} is no longer an orphan`);
      return sum + itemTotalPurchaseCents(item);
    }, 0);
    assert(calculatedAmount === repairTransaction.amountCents, `Repair transaction ${repairTransaction.id} amount changed: ${calculatedAmount}`);
  }

  const duplicate = items.get(DUPLICATE_ITEM_ID);
  const survivor = items.get(DUPLICATE_SURVIVOR_ID);
  assert(duplicate && survivor, 'Duplicate pair is missing');
  assert(duplicate.sku === '400295724061', 'Duplicate SKU changed');
  assert(survivor.sku === '400-295-7240', 'Survivor SKU changed');
  assert(duplicate.purchasePriceCents === survivor.purchasePriceCents, 'Duplicate pair purchase prices differ');
  assert(survivor.transactionId === DUPLICATE_SURVIVOR_TRANSACTION_ID, 'Duplicate survivor changed transaction');
  assert(transactions.get(DUPLICATE_SURVIVOR_TRANSACTION_ID)?.itemIds?.includes(DUPLICATE_SURVIVOR_ID), 'Duplicate survivor is not canonically owned');
  assert(![...transactions.values()].some((transaction) => transaction.itemIds?.includes(DUPLICATE_ITEM_ID)), 'Duplicate item is transaction-owned');
  assert(!state.lineage.some((edge) => edge.itemId === DUPLICATE_ITEM_ID), 'Duplicate item has lineage');
  assert(!state.invoices.some((invoice) => JSON.stringify(invoice).includes(DUPLICATE_ITEM_ID)), 'Duplicate item appears on an invoice');
  assert(!state.protoItems.some((protoItem) => JSON.stringify(protoItem).includes(DUPLICATE_ITEM_ID)), 'Duplicate item appears on a proto item');

  return { canonicalBlanks, inventoryWithCategory, duplicate, survivor };
}

async function commitOps(db, ops) {
  for (let index = 0; index < ops.length; index += 450) {
    const batch = db.batch();
    for (const op of ops.slice(index, index + 450)) {
      if (op.type === 'update') batch.update(op.ref, op.data);
      if (op.type === 'set') batch.set(op.ref, op.data);
      if (op.type === 'delete') batch.delete(op.ref);
    }
    await batch.commit();
  }
}

async function applyRepair(db, state, cohorts) {
  const { base, items, transactions } = state;
  const now = admin.firestore.FieldValue.serverTimestamp();
  const transactionOps = [];
  const itemOps = [];

  for (const transactionId of TRANSACTION_CATEGORY_TARGETS) {
    transactionOps.push({
      type: 'update',
      ref: db.doc(`${base}/transactions/${transactionId}`),
      data: { budgetCategoryId: FURNISHINGS_ID, updatedAt: now },
    });
  }

  for (const [transactionId, itemIds] of Object.entries(EXISTING_TRANSACTION_LINKS)) {
    transactionOps.push({
      type: 'update',
      ref: db.doc(`${base}/transactions/${transactionId}`),
      data: {
        itemIds: admin.firestore.FieldValue.arrayUnion(...itemIds),
        updatedAt: now,
      },
    });
  }

  for (const repairTransaction of NEW_REPAIR_TRANSACTIONS) {
    const data = {
      accountId: ACCOUNT_ID,
      projectId: repairTransaction.projectId,
      budgetCategoryId: FURNISHINGS_ID,
      source: repairTransaction.source,
      type: 'purchase',
      amountCents: repairTransaction.amountCents,
      subtotalCents: repairTransaction.amountCents,
      itemIds: repairTransaction.itemIds,
      isComplete: true,
      notes: `Data repair 2026-08-24: restored transaction ownership for legacy project item(s): ${repairTransaction.itemIds.join(', ')}. No historical receipt transaction was available.`,
      createdAt: now,
      updatedAt: now,
    };
    if (repairTransaction.transactionDate) data.transactionDate = repairTransaction.transactionDate;
    transactionOps.push({
      type: 'set',
      ref: db.doc(`${base}/transactions/${repairTransaction.id}`),
      data,
    });
  }

  await commitOps(db, transactionOps);

  for (const row of cohorts.canonicalBlanks) {
    itemOps.push({
      type: 'update',
      ref: db.doc(`${base}/items/${row.id}`),
      data: { budgetCategoryId: row.categoryId, updatedAt: now },
    });
  }

  for (const item of cohorts.inventoryWithCategory) {
    itemOps.push({
      type: 'update',
      ref: db.doc(`${base}/items/${item.id}`),
      data: { budgetCategoryId: null, updatedAt: now },
    });
  }

  for (const itemId of SENTINEL_ITEM_IDS) {
    itemOps.push({
      type: 'update',
      ref: db.doc(`${base}/items/${itemId}`),
      data: { budgetCategoryId: FURNISHINGS_ID, updatedAt: now },
    });
  }

  for (const itemId of CATEGORY_MISMATCH_ITEM_IDS) {
    const item = items.get(itemId);
    const categoryId = transactions.get(item.transactionId).budgetCategoryId;
    itemOps.push({
      type: 'update',
      ref: db.doc(`${base}/items/${itemId}`),
      data: { budgetCategoryId: categoryId, updatedAt: now },
    });
  }

  for (const [transactionId, itemIds] of Object.entries(EXISTING_TRANSACTION_LINKS)) {
    for (const itemId of itemIds) {
      itemOps.push({
        type: 'update',
        ref: db.doc(`${base}/items/${itemId}`),
        data: {
          transactionId,
          budgetCategoryId: transactions.get(transactionId).budgetCategoryId,
          updatedAt: now,
        },
      });
    }
  }

  for (const repairTransaction of NEW_REPAIR_TRANSACTIONS) {
    for (const itemId of repairTransaction.itemIds) {
      itemOps.push({
        type: 'update',
        ref: db.doc(`${base}/items/${itemId}`),
        data: {
          transactionId: repairTransaction.id,
          budgetCategoryId: FURNISHINGS_ID,
          updatedAt: now,
        },
      });
    }
  }

  const mergedImages = uniqueAttachments(cohorts.survivor.images ?? [], cohorts.duplicate.images ?? []);
  const survivorNotes = [
    cohorts.survivor.notes?.trim(),
    `[2026-08-24] Confirmed item ${DUPLICATE_ITEM_ID} was the same physical magnifying glass by SKU, price, and photos. Merged its photos and space assignment, then removed the duplicate record.`,
  ].filter(Boolean).join('\n\n');
  itemOps.push({
    type: 'update',
    ref: db.doc(`${base}/items/${DUPLICATE_SURVIVOR_ID}`),
    data: {
      images: mergedImages,
      spaceId: cohorts.duplicate.spaceId ?? cohorts.survivor.spaceId ?? null,
      notes: survivorNotes,
      updatedAt: now,
    },
  });
  itemOps.push({ type: 'delete', ref: db.doc(`${base}/items/${DUPLICATE_ITEM_ID}`) });

  await commitOps(db, itemOps);
  return { transactionWriteCount: transactionOps.length, itemWriteCount: itemOps.length };
}

async function verify(db) {
  const state = await loadState(db);
  const { items, transactions, categories, projects } = state;
  const projectItems = [...items.values()].filter((item) => !isBlank(item.projectId));
  const inventoryItems = [...items.values()].filter((item) => isBlank(item.projectId));

  const uiUncategorized = projectItems.filter((item) => isBlank(item.budgetCategoryId));
  const sentinelItems = projectItems.filter((item) => isSentinel(item.budgetCategoryId));
  const unknownOrDisabledItems = [];
  const projectCategoryEntries = await Promise.all(
    [...projects.keys()].map(async (projectId) => {
      const snap = await db.collection(`${state.base}/projects/${projectId}/budgetCategories`).get();
      return [projectId, new Set(snap.docs.map((doc) => doc.id))];
    })
  );
  const enabledByProject = new Map(projectCategoryEntries);
  for (const item of projectItems) {
    if (!categories.has(item.budgetCategoryId) || !enabledByProject.get(item.projectId)?.has(item.budgetCategoryId)) {
      unknownOrDisabledItems.push(item.id);
    }
  }

  const noTransaction = projectItems.filter((item) => isBlank(item.transactionId));
  const missingTransaction = projectItems.filter((item) => !isBlank(item.transactionId) && !transactions.has(item.transactionId));
  const canonicalOwnershipFailures = projectItems.filter((item) => {
    const transaction = transactions.get(item.transactionId);
    return transaction && !transaction.itemIds?.includes(item.id);
  });
  const categoryMismatches = projectItems.filter((item) => {
    const transaction = transactions.get(item.transactionId);
    return transaction
      && !isBlank(transaction.budgetCategoryId)
      && !isSentinel(transaction.budgetCategoryId)
      && item.budgetCategoryId !== transaction.budgetCategoryId;
  });
  const inventoryWithCategory = inventoryItems.filter((item) => !isBlank(item.budgetCategoryId));
  const transactionCategoryIssues = [...transactions.values()].filter(
    (transaction) => !isBlank(transaction.projectId)
      && (isBlank(transaction.budgetCategoryId) || isSentinel(transaction.budgetCategoryId))
  );

  assert(uiUncategorized.length === 0, `${uiUncategorized.length} project items remain UI-uncategorized`);
  assert(sentinelItems.length === 0, `${sentinelItems.length} project items retain sentinel categories`);
  assert(unknownOrDisabledItems.length === 0, `${unknownOrDisabledItems.length} project items have unknown/disabled categories`);
  assert(noTransaction.length === 0, `${noTransaction.length} project items have no transaction`);
  assert(missingTransaction.length === 0, `${missingTransaction.length} project items reference missing transactions`);
  assert(canonicalOwnershipFailures.length === 0, `${canonicalOwnershipFailures.length} item back-references lack canonical ownership`);
  assert(categoryMismatches.length === 0, `${categoryMismatches.length} item/transaction category mismatches remain`);
  assert(inventoryWithCategory.length === 0, `${inventoryWithCategory.length} inventory items retain categories`);
  assert(transactionCategoryIssues.length === 0, `${transactionCategoryIssues.length} project transactions retain blank/sentinel categories`);
  assert(!items.has(DUPLICATE_ITEM_ID), 'Duplicate item still exists');

  return {
    allItems: items.size,
    projectItems: projectItems.length,
    inventoryItems: inventoryItems.length,
    uiUncategorizedProjectItems: uiUncategorized.length,
    projectItemsWithSentinelCategory: sentinelItems.length,
    projectItemsWithUnknownOrDisabledCategory: unknownOrDisabledItems.length,
    projectItemsWithoutTransaction: noTransaction.length,
    projectItemsWithMissingTransaction: missingTransaction.length,
    canonicalOwnershipFailures: canonicalOwnershipFailures.length,
    itemTransactionCategoryMismatches: categoryMismatches.length,
    inventoryItemsWithCategory: inventoryWithCategory.length,
    projectTransactionsWithBlankOrSentinelCategory: transactionCategoryIssues.length,
    createdRepairTransactions: NEW_REPAIR_TRANSACTIONS.map((transaction) => transaction.id),
    mergedDuplicate: { removed: DUPLICATE_ITEM_ID, survivor: DUPLICATE_SURVIVOR_ID },
  };
}

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: FIREBASE_PROJECT_ID,
  });
  const db = admin.firestore();
  const state = await loadState(db);
  const cohorts = await validatePreconditions(db, state);

  const summary = {
    mode: APPLY ? 'apply' : 'dry-run',
    firestoreProjectId: FIREBASE_PROJECT_ID,
    accountId: ACCOUNT_ID,
    canonicalBlankItemBackfills: cohorts.canonicalBlanks.length,
    blankOrphanItemsRepairedOrMerged: 13,
    sentinelItemCategoryRepairs: SENTINEL_ITEM_IDS.length,
    itemTransactionCategoryMismatchRepairs: CATEGORY_MISMATCH_ITEM_IDS.length,
    inventoryCategoryClears: cohorts.inventoryWithCategory.length,
    existingTransactionAssociationsRestored: Object.values(EXISTING_TRANSACTION_LINKS).flat().length,
    repairTransactionsCreated: NEW_REPAIR_TRANSACTIONS.length,
    transactionCategoryRepairs: TRANSACTION_CATEGORY_TARGETS.length,
    duplicateItemsMerged: 1,
  };

  if (!APPLY) {
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  const writeCounts = await applyRepair(db, state, cohorts);
  const verification = await verify(db);
  console.log(JSON.stringify({ ...summary, ...writeCounts, verification }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
