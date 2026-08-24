#!/usr/bin/env node

/**
 * Backfill the 47 Hal Roe project items whose linked transactions already
 * identify Furnishings as their budget category.
 *
 * Dry-run by default:
 *   node scripts/repair-hal-roe-missing-budget-categories.mjs
 *
 * Apply once all preconditions pass:
 *   node scripts/repair-hal-roe-missing-budget-categories.mjs --apply
 */

import admin from 'firebase-admin';

const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const ACCOUNT_ID = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const PROJECT_ID = 'pgwdhOFcslItEjDxeWgL';
const CATEGORY_ID = 'da556858-1df8-40be-b10c-b15710d7cc9a';
const APPLY = process.argv.includes('--apply');

const TARGETS_BY_TRANSACTION = {
  '0tha40ZlO2viSnxGPVO6': [
    'FMNtveOXfQGUDSUjpyom',
    'q4clAsIKfqG7j3sDEVU9',
    '5XnQHu3L7vrgKAb8LbcH',
    'H5FD89XHA7rrDmgymrPK',
    'CeG5JSYMvcIdhCyiRWwT',
    'SwKOJtcKbWSEZBjnLCBF',
    'LfUjZqjXuNRSR2sGKcpO',
    'cQpzHcMnsZaSExIRmuLF',
    'gHgFewmdTaYcwLoPcvy6',
    'iCgUKH914FOdxvqUYiKh',
    'mCJgWkk1Q5EMZqWH7AZk',
    'zEW3tXS6lriNZ5QkOMhc',
    '8XvyUy535A0t2t7IFOfC',
    'IRgU3iJVNJ0a91o6A394',
    'JQNx9SOG42Mksbeu9FCM',
    '1NfL08yX8s6Jvd9MfwbP',
    '2yyayVPvlQfihQxonJb4',
    'NiqOlBXxfqwb1qwyxL6v',
    '9hoifBxOyZ937MSghvDr',
    'B6GaLr2VQxohQMNU2zmJ',
    'nlsNdWJfspQp0o0TQgOr',
    'P0SG4s1KWCHHy2CtdiWc',
    'GSomdKJvZm9x28h39Br3',
    'NtpJzvfYjuA0LodO994m',
    'PYzFQc2Aoio2TaSFG5Zj',
    'p4O6Gf35Hkg54jvQuTVA',
  ],
  iR7EUfNYkbCxKvlP7nz2: [
    'ZB3WI0sAvlGcxe0LjgFX',
    'q0Geh9jwyIMKUnDvjUdE',
  ],
  KoP50hmljYbRGYcEs9r0: [
    'Cg5AntNBEE8NETBowgon',
    'qBxdHWPUOYDEMQ2BuyxA',
    'Ig8B8YNaxUjaomDRXVxr',
  ],
  wEx1Z6FgXFzr69ssWIt9: [
    'KMVFgfh8FcPnnnJjyviG',
    'w3q8aOu47DRYb7Ob1HCy',
    'Cum5bv5CoziDEoCI4cPJ',
    '4X2ycvveXminH3gsspLQ',
    'TeGdUTZ27FPknRnHIIev',
    'dVbje8Ph1Y3Q5NjhsjeB',
    'QyByR9E3bQvUH8DK4UfE',
    'uzgJREYu26UmHjz0X4Ff',
    'DBBhlgX87feV3hAtQUR0',
  ],
  yM4tihvNQZTUdvtU2Cdn: [
    '2KNSxgpCwIutJwFSmuY6',
    '6YZNkc2Fnu87brr1iVBj',
    'SmOdoj7Zpkdqi6QqAwiV',
    'amRMWyXUNEzrLW7X4adD',
    'i8fAfBLGtZedRIlJLwU1',
    'rvSdbSfwCp0E3aVjdjRQ',
    'AE7XHwUD6wpLVauuf63B',
  ],
};

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function isUiUncategorized(value) {
  return value == null || (typeof value === 'string' && value.trim() === '');
}

function initFirestore() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: FIREBASE_PROJECT_ID,
  });
  return admin.firestore();
}

async function main() {
  const db = initFirestore();
  const targets = Object.entries(TARGETS_BY_TRANSACTION).flatMap(([transactionId, itemIds]) =>
    itemIds.map((itemId) => ({ itemId, transactionId }))
  );
  const targetIds = new Set(targets.map(({ itemId }) => itemId));

  assert(targets.length === 47, `Expected 47 target rows, found ${targets.length}`);
  assert(targetIds.size === 47, `Expected 47 unique item IDs, found ${targetIds.size}`);

  const accountPath = `accounts/${ACCOUNT_ID}`;
  const itemRefs = targets.map(({ itemId }) => db.doc(`${accountPath}/items/${itemId}`));
  const transactionIds = Object.keys(TARGETS_BY_TRANSACTION);
  const transactionRefs = transactionIds.map((id) => db.doc(`${accountPath}/transactions/${id}`));
  const [projectSnap, accountCategorySnap, projectCategorySnap, itemSnaps, transactionSnaps, projectItemsSnap] =
    await Promise.all([
      db.doc(`${accountPath}/projects/${PROJECT_ID}`).get(),
      db.doc(`${accountPath}/presets/default/budgetCategories/${CATEGORY_ID}`).get(),
      db.doc(`${accountPath}/projects/${PROJECT_ID}/budgetCategories/${CATEGORY_ID}`).get(),
      db.getAll(...itemRefs),
      db.getAll(...transactionRefs),
      db.collection(`${accountPath}/items`).where('projectId', '==', PROJECT_ID).get(),
    ]);

  assert(projectSnap.exists, `Project ${PROJECT_ID} does not exist`);
  assert(projectSnap.data()?.name === 'Hal Roe — Trinidad Vacation Rental', 'Project name changed');
  assert(accountCategorySnap.exists, `Account category ${CATEGORY_ID} does not exist`);
  assert(accountCategorySnap.data()?.name === 'Furnishings', 'Expected category name Furnishings');
  assert(projectCategorySnap.exists, `Furnishings is not enabled for project ${PROJECT_ID}`);

  const transactions = new Map(transactionSnaps.map((snap) => [snap.id, snap]));
  for (const transactionId of transactionIds) {
    const snap = transactions.get(transactionId);
    assert(snap?.exists, `Transaction ${transactionId} does not exist`);
    const transaction = snap.data();
    assert(transaction?.projectId === PROJECT_ID, `Transaction ${transactionId} changed project`);
    assert(transaction?.budgetCategoryId === CATEGORY_ID, `Transaction ${transactionId} is not Furnishings`);
  }

  const before = [];
  for (let index = 0; index < targets.length; index += 1) {
    const target = targets[index];
    const snap = itemSnaps[index];
    assert(snap.exists, `Item ${target.itemId} does not exist`);
    const item = snap.data();
    assert(item.projectId === PROJECT_ID, `Item ${target.itemId} changed project`);
    assert(item.transactionId === target.transactionId, `Item ${target.itemId} changed transaction`);
    assert(isUiUncategorized(item.budgetCategoryId), `Item ${target.itemId} is no longer UI-uncategorized`);

    const transactionItemIds = transactions.get(target.transactionId).data()?.itemIds;
    assert(Array.isArray(transactionItemIds), `Transaction ${target.transactionId} has no itemIds array`);
    assert(transactionItemIds.includes(target.itemId), `Transaction ${target.transactionId} does not own item ${target.itemId}`);

    before.push({
      itemId: target.itemId,
      name: item.name ?? item.description ?? '',
      transactionId: target.transactionId,
      budgetCategoryId: item.budgetCategoryId ?? null,
    });
  }

  const uiUncategorizedIds = projectItemsSnap.docs
    .filter((doc) => isUiUncategorized(doc.data()?.budgetCategoryId))
    .map((doc) => doc.id)
    .sort();
  assert(uiUncategorizedIds.length === 47, `UI predicate now returns ${uiUncategorizedIds.length}, expected 47`);
  assert(
    uiUncategorizedIds.every((id) => targetIds.has(id)),
    'UI predicate returned an item outside the reviewed 47-item allowlist'
  );

  if (!APPLY) {
    console.log(JSON.stringify({
      mode: 'dry-run',
      firestoreProjectId: FIREBASE_PROJECT_ID,
      accountId: ACCOUNT_ID,
      projectId: PROJECT_ID,
      categoryId: CATEGORY_ID,
      categoryName: 'Furnishings',
      verifiedTargetCount: before.length,
      uiUncategorizedCountBefore: uiUncategorizedIds.length,
      transactionIds,
      targets: before,
    }, null, 2));
    return;
  }

  const batch = db.batch();
  for (const ref of itemRefs) {
    batch.update(ref, {
      budgetCategoryId: CATEGORY_ID,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  const [afterItemSnaps, afterProjectItemsSnap] = await Promise.all([
    db.getAll(...itemRefs),
    db.collection(`${accountPath}/items`).where('projectId', '==', PROJECT_ID).get(),
  ]);
  const failedIds = afterItemSnaps
    .filter((snap) => snap.data()?.budgetCategoryId !== CATEGORY_ID)
    .map((snap) => snap.id);
  const uiUncategorizedAfter = afterProjectItemsSnap.docs
    .filter((doc) => isUiUncategorized(doc.data()?.budgetCategoryId))
    .map((doc) => doc.id);

  assert(failedIds.length === 0, `Repair verification failed for: ${failedIds.join(', ')}`);
  assert(uiUncategorizedAfter.length === 0, `UI predicate still returns ${uiUncategorizedAfter.length} item(s)`);

  console.log(JSON.stringify({
    mode: 'apply',
    firestoreProjectId: FIREBASE_PROJECT_ID,
    accountId: ACCOUNT_ID,
    projectId: PROJECT_ID,
    categoryId: CATEGORY_ID,
    categoryName: 'Furnishings',
    updatedCount: afterItemSnaps.length,
    uiUncategorizedCountBefore: uiUncategorizedIds.length,
    uiUncategorizedCountAfter: uiUncategorizedAfter.length,
    verifiedItemIds: afterItemSnaps.map((snap) => snap.id).sort(),
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
