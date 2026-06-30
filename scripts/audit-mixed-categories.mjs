#!/usr/bin/env node
/**
 * Audit Firestore for unsupported mixed budget categories.
 *
 * Mixed means supportedTypes contains exactly:
 *   ["purchase", "return", "expense"]
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/audit-mixed-categories.mjs
 *
 * Optional:
 *   FIREBASE_PROJECT_ID=ledger-nine4
 */

import admin from 'firebase-admin';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';

function sameSet(values, target) {
  if (!Array.isArray(values)) return false;
  const actual = [...new Set(values.map(String).map((s) => s.toLowerCase()))].sort();
  const expected = [...target].sort();
  return actual.length === expected.length && actual.every((value, index) => value === expected[index]);
}

function accountIdFromPath(path) {
  return path.split('/')[1] ?? null;
}

function projectIdFromCategoryPath(path) {
  const parts = path.split('/');
  const index = parts.indexOf('projects');
  return index >= 0 ? parts[index + 1] : null;
}

function normalizeType(value) {
  return String(value ?? '').toLowerCase();
}

function initFirestore() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  return admin.firestore();
}

async function main() {
  const db = initFirestore();
  const accountsSnap = await db.collection('accounts').get();
  const accounts = accountsSnap.docs.map((doc) => ({
    id: doc.id,
    name: doc.data()?.name ?? doc.data()?.businessName ?? null,
  }));

  const categoriesSnap = await db.collectionGroup('budgetCategories').get();
  const mixedCategories = [];
  for (const doc of categoriesSnap.docs) {
    const data = doc.data() ?? {};
    if (!sameSet(data.supportedTypes, ['purchase', 'return', 'expense'])) continue;
    mixedCategories.push({
      path: doc.ref.path,
      accountId: accountIdFromPath(doc.ref.path),
      projectId: projectIdFromCategoryPath(doc.ref.path),
      id: doc.id,
      name: data.name ?? null,
      supportedTypes: data.supportedTypes,
      metadataCategoryType: data.metadata?.categoryType ?? null,
      isArchived: data.isArchived ?? false,
    });
  }

  const mixedIdsByAccount = new Map();
  for (const category of mixedCategories) {
    if (!category.accountId) continue;
    const ids = mixedIdsByAccount.get(category.accountId) ?? [];
    ids.push(category.id);
    mixedIdsByAccount.set(category.accountId, ids);
  }

  const txCountsByCategory = new Map();
  const txTypeCountsByCategory = new Map();
  const txExamplesByCategory = new Map();
  const mixedTransactions = [];
  for (const account of accounts) {
    const mixedIds = mixedIdsByAccount.get(account.id) ?? [];
    if (mixedIds.length === 0) continue;
    const transactionsSnap = await db.collection(`accounts/${account.id}/transactions`).get();
    for (const doc of transactionsSnap.docs) {
      const transaction = doc.data() ?? {};
      const categoryId = transaction.budgetCategoryId ?? null;
      if (!mixedIds.includes(categoryId)) continue;

      const key = `${account.id}:${categoryId}`;
      const type = normalizeType(transaction.type ?? transaction.transactionType);
      const itemIdsCount = Array.isArray(transaction.itemIds) ? transaction.itemIds.length : null;

      txCountsByCategory.set(key, (txCountsByCategory.get(key) ?? 0) + 1);

      const typeCounts = txTypeCountsByCategory.get(key) ?? {};
      typeCounts[type || '(missing)'] = (typeCounts[type || '(missing)'] ?? 0) + 1;
      txTypeCountsByCategory.set(key, typeCounts);

      const examples = txExamplesByCategory.get(key) ?? [];
      if (examples.length < 8) {
        examples.push({
          path: doc.ref.path,
          type: transaction.type ?? transaction.transactionType ?? null,
          projectId: transaction.projectId ?? null,
          source: transaction.source ?? null,
          amountCents: transaction.amountCents ?? null,
          itemIdsCount,
          subtotalCents: transaction.subtotalCents ?? null,
          taxCents: transaction.taxCents ?? null,
          transactionDate: transaction.transactionDate?.toDate?.()?.toISOString?.().slice(0, 10)
            ?? transaction.transactionDate
            ?? null,
        });
      }
      txExamplesByCategory.set(key, examples);

      mixedTransactions.push({
        accountId: account.id,
        categoryId,
        path: doc.ref.path,
        type,
        hasItems: itemIdsCount != null && itemIdsCount > 0,
      });
    }
  }

  const categories = mixedCategories.map((category) => {
    const key = `${category.accountId}:${category.id}`;
    return {
      ...category,
      transactionCount: txCountsByCategory.get(key) ?? 0,
      transactionTypeCounts: txTypeCountsByCategory.get(key) ?? {},
      examples: txExamplesByCategory.get(key) ?? [],
    };
  });

  const report = {
    projectId: PROJECT_ID,
    accountCount: accounts.length,
    categoryDocCount: categoriesSnap.size,
    mixedCategoryCount: mixedCategories.length,
    mixedTransactionCount: mixedTransactions.length,
    mixedTransactionsWithItems: mixedTransactions.filter((tx) => tx.hasItems).length,
    mixedTransactionsWithoutItems: mixedTransactions.filter((tx) => !tx.hasItems).length,
    categories,
  };

  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
