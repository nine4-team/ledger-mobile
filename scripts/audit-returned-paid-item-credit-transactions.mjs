#!/usr/bin/env node
/**
 * Audit synthetic returned-paid-item credit transactions.
 *
 * These rows were created by the old returned-after-paid-item workaround and
 * should be reviewed before migration into ordinary draft invoice credit lines.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/audit-returned-paid-item-credit-transactions.mjs
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

function accountIdFromPath(path) {
  return path.split('/')[1] ?? null;
}

function compactDate(value) {
  return value?.toDate?.()?.toISOString?.().slice(0, 10) ?? value ?? null;
}

function nameFromCreditSource(source) {
  return String(source ?? '').replace(/^Credit:\s*returned\s*/i, '').trim();
}

async function findPossibleItems(db, accountId, projectId, name) {
  if (!accountId || !projectId || !name) return [];
  const snap = await db.collection(`accounts/${accountId}/items`)
    .where('projectId', '==', projectId)
    .limit(200)
    .get();
  const needle = normalize(name);
  return snap.docs
    .map((doc) => ({ id: doc.id, path: doc.ref.path, ...doc.data() }))
    .filter((item) => {
      const itemName = normalize(item.name ?? item.description);
      return itemName && (itemName.includes(needle) || needle.includes(itemName));
    })
    .slice(0, 10)
    .map((item) => ({
      path: item.path,
      id: item.id,
      name: item.name ?? item.description ?? null,
      projectId: item.projectId ?? null,
      budgetCategoryId: item.budgetCategoryId ?? null,
      purchasePriceCents: item.purchasePriceCents ?? null,
      projectPriceCents: item.projectPriceCents ?? null,
      status: item.status ?? null,
    }));
}

async function findPossiblePaidInvoiceLines(db, accountId, projectId, possibleItems) {
  if (!accountId || !projectId || !possibleItems.length) return [];
  const itemIds = new Set(possibleItems.map((item) => item.id));
  const snap = await db.collection(`accounts/${accountId}/invoices`)
    .where('projectId', '==', projectId)
    .where('status', '==', 'paid')
    .get();

  const matches = [];
  for (const doc of snap.docs) {
    const invoice = doc.data() ?? {};
    for (const line of invoice.lines ?? []) {
      if (line.sourceType !== 'item') continue;
      if (!itemIds.has(line.sourceId)) continue;
      if (line.sign !== 1) continue;
      matches.push({
        invoicePath: doc.ref.path,
        invoiceId: doc.id,
        invoiceNumber: invoice.invoiceNumber ?? null,
        lineId: line.id ?? null,
        sourceId: line.sourceId ?? null,
        amountCents: line.amountCents ?? null,
        budgetCategoryId: line.budgetCategoryId ?? null,
        snapshotName: line.snapshotName ?? null,
      });
    }
  }
  return matches;
}

async function main() {
  const db = initFirestore();
  const report = {
    projectId: PROJECT_ID,
    transactionsScanned: 0,
    candidateCount: 0,
    candidates: [],
  };

  const txSnap = await db.collectionGroup('transactions').get();
  for (const doc of txSnap.docs) {
    report.transactionsScanned += 1;
    const data = doc.data() ?? {};
    const type = normalize(data.type ?? data.transactionType);
    const source = String(data.source ?? '');
    const isCandidate = source.startsWith('Credit: returned ')
      && data.reimbursementType === 'owed-to-client'
      && (type === 'purchase' || type === 'expense');
    if (!isCandidate) continue;

    const accountId = accountIdFromPath(doc.ref.path);
    const returnedName = nameFromCreditSource(source);
    const possibleItems = await findPossibleItems(db, accountId, data.projectId, returnedName);
    const possiblePaidInvoiceLines = await findPossiblePaidInvoiceLines(db, accountId, data.projectId, possibleItems);

    report.candidateCount += 1;
    report.candidates.push({
      transactionPath: doc.ref.path,
      transactionId: doc.id,
      accountId,
      projectId: data.projectId ?? null,
      type: data.type ?? null,
      source,
      returnedName,
      amountCents: data.amountCents ?? null,
      budgetCategoryId: data.budgetCategoryId ?? null,
      reimbursementType: data.reimbursementType ?? null,
      transactionDate: compactDate(data.transactionDate),
      possibleItems,
      possiblePaidInvoiceLines,
    });
  }

  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
