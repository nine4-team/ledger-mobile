#!/usr/bin/env node
/**
 * Audit invoice lines and invoiceable sources missing budgetCategoryId.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/audit-invoice-line-categories.mjs
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

function accountIdFromPath(path) {
  return path.split('/')[1] ?? null;
}

async function main() {
  const db = initFirestore();
  const report = {
    projectId: PROJECT_ID,
    invoicesScanned: 0,
    invoiceLinesScanned: 0,
    invoiceLinesMissingBudgetCategoryId: [],
    invoiceItemsMissingBudgetCategoryId: [],
    invoiceTransactionsMissingBudgetCategoryId: [],
  };

  const invoiceSnap = await db.collectionGroup('invoices').get();
  for (const invoiceDoc of invoiceSnap.docs) {
    report.invoicesScanned += 1;
    const invoice = invoiceDoc.data() ?? {};
    const accountId = accountIdFromPath(invoiceDoc.ref.path);
    if (!accountId) continue;

    for (const line of invoice.lines ?? []) {
      report.invoiceLinesScanned += 1;
      if (!line.budgetCategoryId) {
        report.invoiceLinesMissingBudgetCategoryId.push({
          invoicePath: invoiceDoc.ref.path,
          invoiceId: invoiceDoc.id,
          lineId: line.id ?? null,
          sourceType: line.sourceType ?? null,
          sourceId: line.sourceId ?? null,
          amountCents: line.amountCents ?? null,
          sign: line.sign ?? null,
          snapshotName: line.snapshotName ?? null,
        });
      }
    }

    for (const itemId of invoice.itemIds ?? []) {
      const itemSnap = await db.doc(`accounts/${accountId}/items/${itemId}`).get();
      const item = itemSnap.data();
      if (item && !item.budgetCategoryId) {
        report.invoiceItemsMissingBudgetCategoryId.push({
          invoicePath: invoiceDoc.ref.path,
          itemPath: itemSnap.ref.path,
          itemId,
          projectId: item.projectId ?? null,
          name: item.name ?? item.description ?? null,
        });
      }
    }

    for (const txId of invoice.transactionIds ?? []) {
      const txSnap = await db.doc(`accounts/${accountId}/transactions/${txId}`).get();
      const tx = txSnap.data();
      if (tx && !tx.budgetCategoryId) {
        report.invoiceTransactionsMissingBudgetCategoryId.push({
          invoicePath: invoiceDoc.ref.path,
          transactionPath: txSnap.ref.path,
          transactionId: txId,
          projectId: tx.projectId ?? null,
          type: tx.type ?? null,
          source: tx.source ?? null,
          amountCents: tx.amountCents ?? null,
        });
      }
    }
  }

  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
