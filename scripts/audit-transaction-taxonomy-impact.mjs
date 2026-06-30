#!/usr/bin/env node
/**
 * Audit Firestore data affected by the proposed transaction taxonomy migration.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/audit-transaction-taxonomy-impact.mjs
 *
 * Optional:
 *   FIREBASE_PROJECT_ID=ledger-nine4
 */

import admin from 'firebase-admin';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';

function initFirestore() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  return admin.firestore();
}

function normalize(value) {
  return String(value ?? '').trim().toLowerCase();
}

function supportedShape(values) {
  if (!Array.isArray(values) || values.length === 0) return '(missing)';
  return [...new Set(values.map(normalize))].sort().join('+');
}

function bump(map, key, amount = 1) {
  map.set(key, (map.get(key) ?? 0) + amount);
}

function objectFromMap(map) {
  return Object.fromEntries([...map.entries()].sort(([a], [b]) => a.localeCompare(b)));
}

function compactTx(doc, data) {
  return {
    path: doc.ref.path,
    id: doc.id,
    type: data.type ?? null,
    source: data.source ?? null,
    projectId: data.projectId ?? null,
    budgetCategoryId: data.budgetCategoryId ?? null,
    amountCents: data.amountCents ?? null,
    transactionDate: data.transactionDate?.toDate?.()?.toISOString?.().slice(0, 10)
      ?? data.transactionDate
      ?? null,
    purchasedBy: data.purchasedBy ?? null,
    reimbursementType: data.reimbursementType ?? null,
    itemIdsCount: Array.isArray(data.itemIds) ? data.itemIds.length : null,
    settlementInvoiceId: data.settlementInvoiceId ?? null,
  };
}

async function main() {
  const db = initFirestore();
  const accountsSnap = await db.collection('accounts').get();
  const accounts = accountsSnap.docs.map((doc) => ({
    id: doc.id,
    name: doc.data()?.name ?? doc.data()?.businessName ?? null,
  }));

  const categoriesByAccount = new Map();
  const categoryShapeCounts = new Map();
  const categoryMetadataCounts = new Map();
  const mixedCategories = [];

  const categoriesSnap = await db.collectionGroup('budgetCategories').get();
  for (const doc of categoriesSnap.docs) {
    const data = doc.data() ?? {};
    const parts = doc.ref.path.split('/');
    const accountId = parts[0] === 'accounts' ? parts[1] : null;
    const shape = supportedShape(data.supportedTypes);
    const metadataType = data.metadata?.categoryType ?? '(missing)';
    bump(categoryShapeCounts, shape);
    bump(categoryMetadataCounts, metadataType);
    if (accountId) {
      const accountCategories = categoriesByAccount.get(accountId) ?? new Map();
      const existing = accountCategories.get(doc.id);
      const category = {
        path: doc.ref.path,
        id: doc.id,
        name: data.name ?? null,
        shape,
        metadataType,
      };
      // Project category copies may share an ID with the account preset while
      // omitting taxonomy fields. Keep the more explicit taxonomy shape.
      if (!existing || (existing.shape === '(missing)' && shape !== '(missing)')) {
        accountCategories.set(doc.id, category);
      }
      categoriesByAccount.set(accountId, accountCategories);
    }
    if (shape === 'expense+purchase+return') {
      mixedCategories.push({
        path: doc.ref.path,
        accountId,
        id: doc.id,
        name: data.name ?? null,
        metadataType,
      });
    }
  }

  const globalTypeCounts = new Map();
  const typeCountsByAccount = {};
  const purchasedByCounts = new Map();
  const reimbursementCounts = new Map();
  const settlementByTypeCounts = new Map();
  const itemCountsByType = new Map();
  const categoryShapeByTxType = new Map();
  const feeExpenseExamples = [];
  const settlementExamples = [];
  const mixedCategoryExamples = [];
  let transactionCount = 0;
  let settlementTransactionCount = 0;
  let transactionsWithItemsCount = 0;

  for (const account of accounts) {
    const txSnap = await db.collection(`accounts/${account.id}/transactions`).get();
    const accountTypeCounts = new Map();
    const accountCategories = categoriesByAccount.get(account.id) ?? new Map();
    for (const doc of txSnap.docs) {
      transactionCount += 1;
      const data = doc.data() ?? {};
      const type = normalize(data.type ?? data.transactionType) || '(missing)';
      const itemIdsCount = Array.isArray(data.itemIds) ? data.itemIds.length : 0;
      const category = accountCategories.get(data.budgetCategoryId);
      const categoryShape = category?.shape ?? '(category missing)';

      bump(globalTypeCounts, type);
      bump(accountTypeCounts, type);
      bump(purchasedByCounts, data.purchasedBy ?? '(missing)');
      bump(reimbursementCounts, data.reimbursementType ?? '(missing)');
      bump(itemCountsByType, `${type}:${itemIdsCount > 0 ? 'withItems' : 'withoutItems'}`);
      bump(categoryShapeByTxType, `${type} -> ${categoryShape}`);
      if (itemIdsCount > 0) transactionsWithItemsCount += 1;

      if (data.settlementInvoiceId) {
        settlementTransactionCount += 1;
        bump(settlementByTypeCounts, type);
        if (settlementExamples.length < 20) {
          settlementExamples.push(compactTx(doc, data));
        }
      }

      if ((type === 'fee' || type === 'expense') && feeExpenseExamples.length < 40) {
        feeExpenseExamples.push(compactTx(doc, data));
      }

      if (categoryShape === 'expense+purchase+return' && mixedCategoryExamples.length < 40) {
        mixedCategoryExamples.push({
          ...compactTx(doc, data),
          categoryName: category?.name ?? null,
        });
      }
    }
    typeCountsByAccount[account.id] = {
      accountName: account.name,
      counts: objectFromMap(accountTypeCounts),
      transactionCount: txSnap.size,
    };
  }

  const invoicesSnap = await db.collectionGroup('invoices').get();
  const invoiceStatusCounts = new Map();
  let invoiceCount = 0;
  for (const doc of invoicesSnap.docs) {
    invoiceCount += 1;
    bump(invoiceStatusCounts, doc.data()?.status ?? '(missing)');
  }

  const report = {
    projectId: PROJECT_ID,
    accountCount: accounts.length,
    transactionCount,
    transactionTypeCounts: objectFromMap(globalTypeCounts),
    typeCountsByAccount,
    transactionsWithItemsCount,
    itemCountsByType: objectFromMap(itemCountsByType),
    settlementTransactionCount,
    settlementByTypeCounts: objectFromMap(settlementByTypeCounts),
    categoryDocCount: categoriesSnap.size,
    categorySupportedTypeShapeCounts: objectFromMap(categoryShapeCounts),
    categoryMetadataTypeCounts: objectFromMap(categoryMetadataCounts),
    mixedCategoryCount: mixedCategories.length,
    mixedCategories,
    purchasedByCounts: objectFromMap(purchasedByCounts),
    reimbursementTypeCounts: objectFromMap(reimbursementCounts),
    txTypeToCategoryShapeCounts: objectFromMap(categoryShapeByTxType),
    invoiceCount,
    invoiceStatusCounts: objectFromMap(invoiceStatusCounts),
    examples: {
      feeExpense: feeExpenseExamples,
      settlements: settlementExamples,
      mixedCategories: mixedCategoryExamples,
    },
  };

  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
