#!/usr/bin/env node
/**
 * Dry-run/commit migration for transaction taxonomy cleanup.
 *
 * Defaults to dry-run and writes JSONL decisions to stdout.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/migrate-transaction-taxonomy.mjs > dry-run.jsonl
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/migrate-transaction-taxonomy.mjs --account <accountId> > dry-run.jsonl
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/migrate-transaction-taxonomy.mjs --commit --backup <backup.json> > commit-log.jsonl
 *
 * Optional:
 *   FIREBASE_PROJECT_ID=ledger-nine4
 */

import admin from 'firebase-admin';
import fs from 'node:fs';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const COMMIT = process.argv.includes('--commit');
const BACKUP_PATH = (() => {
  const index = process.argv.indexOf('--backup');
  return index === -1 ? null : process.argv[index + 1] ?? null;
})();
const ACCOUNT_FILTER = (() => {
  const index = process.argv.indexOf('--account');
  return index === -1 ? null : process.argv[index + 1] ?? null;
})();

if (COMMIT && (!BACKUP_PATH || !fs.existsSync(BACKUP_PATH))) {
  throw new Error('--commit requires --backup <existing-backup.json>');
}

const PURCHASED_BY_NORMALIZATION = new Map([
  ['Client', 'client-card'],
  ['Design Business', 'design-business'],
  ['', null],
]);

const REIMBURSEMENT_NORMALIZATION = new Map([
  ['Client Owes Design Business', 'owed-to-company'],
  ['Design Business Owes Client', 'owed-to-client'],
  ['', null],
]);

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

function normalize(value) {
  return String(value ?? '').trim().toLowerCase();
}

function sameSet(values, target) {
  if (!Array.isArray(values)) return false;
  const actual = [...new Set(values.map(normalize))].sort();
  const expected = [...target].sort();
  return actual.length === expected.length && actual.every((value, index) => value === expected[index]);
}

function targetCategoryNameForTransaction(tx, projectCategoryNames = new Set()) {
  const source = normalize(tx.source);
  const notes = normalize(tx.notes);
  const combined = `${source} ${notes}`;

  if (combined.includes('blvd home')) return 'Furnishings';
  if (combined.includes('art explore') || combined.includes('custom artwork')) return 'Furnishings';
  if (combined.includes('cinema works')) return 'Install Services';
  if (combined.includes("deni's kitchen") || combined.includes('deni’s kitchen') || combined.includes('denis kitchen')) return 'Kitchen';
  if (combined.includes('home depot')) return 'Install Supplies';
  if (combined.includes("lowe's") || combined.includes('lowe’s') || combined.includes('lowes')) return 'Install Supplies';
  if (combined.includes('ace hardware')) return 'Install Supplies';
  if (combined.includes('dean berryessa')) return 'Install Services';
  if (combined.includes('install expenses')) return 'Install Services';
  if (combined.includes('speedway gas')) return 'Fuel';
  if (combined.includes('fedex')) {
    return projectCategoryNames.has('storage & receiving') ? 'Storage & Receiving' : 'Install Services';
  }
  return null;
}

function compactUpdate(update) {
  return Object.fromEntries(Object.entries(update).map(([key, value]) => [
    key,
    value && typeof value === 'object' && value.constructor?.name === 'DeleteTransform'
      ? '(delete)'
      : value,
  ]));
}

async function main() {
  const db = initFirestore();
  const FieldValue = admin.firestore.FieldValue;
  const categoryByAccountName = new Map();
  const categoryNameByAccountId = new Map();
  const categoryNamesByAccountProject = new Map();
  const mixedCategoryIdsByAccount = new Map();

  const categorySnap = await db.collectionGroup('budgetCategories').get();
  for (const doc of categorySnap.docs) {
    const data = doc.data() ?? {};
    const accountId = accountIdFromPath(doc.ref.path);
    if (!accountId) continue;
    const byName = categoryByAccountName.get(accountId) ?? new Map();
    byName.set(normalize(data.name), { id: doc.id, path: doc.ref.path, data });
    categoryByAccountName.set(accountId, byName);

    const parts = doc.ref.path.split('/');
    const presetIndex = parts.indexOf('presets');
    if (presetIndex !== -1 && parts[presetIndex + 1] === 'default' && data.name) {
      const namesById = categoryNameByAccountId.get(accountId) ?? new Map();
      namesById.set(doc.id, normalize(data.name));
      categoryNameByAccountId.set(accountId, namesById);
    }
  }

  for (const doc of categorySnap.docs) {
    const accountId = accountIdFromPath(doc.ref.path);
    if (!accountId) continue;
    const data = doc.data() ?? {};
    const parts = doc.ref.path.split('/');
    const projectIndex = parts.indexOf('projects');
    if (projectIndex !== -1 && parts[projectIndex + 1]) {
      const projectKey = `${accountId}:${parts[projectIndex + 1]}`;
      const names = categoryNamesByAccountProject.get(projectKey) ?? new Set();
      const presetName = categoryNameByAccountId.get(accountId)?.get(doc.id);
      names.add(presetName ?? normalize(data.name));
      categoryNamesByAccountProject.set(projectKey, names);
    }

    if (sameSet(data.supportedTypes, ['purchase', 'return', 'expense'])) {
      const ids = mixedCategoryIdsByAccount.get(accountId) ?? new Set();
      ids.add(doc.id);
      mixedCategoryIdsByAccount.set(accountId, ids);
    }
  }

  const accountSnap = await db.collection('accounts').get();
  for (const accountDoc of accountSnap.docs) {
    const accountId = accountDoc.id;
    if (ACCOUNT_FILTER && accountId !== ACCOUNT_FILTER) continue;
    const accountName = accountDoc.data()?.name ?? accountDoc.data()?.businessName ?? accountId;
    const categoriesByName = categoryByAccountName.get(accountId) ?? new Map();
    const mixedCategoryIds = mixedCategoryIdsByAccount.get(accountId) ?? new Set();
    const txSnap = await db.collection(`accounts/${accountId}/transactions`).get();

    for (const doc of txSnap.docs) {
      const tx = doc.data() ?? {};
      const update = {};
      const reasons = [];
      const type = normalize(tx.type);

      if (type === 'expense') {
        update.type = 'purchase';
        reasons.push('expense->purchase');
      }
      if (type === 'fee') {
        update.type = 'paymentToBusiness';
        reasons.push('fee->paymentToBusiness');
      }
      if (type === 'to inventory') {
        update.type = 'return';
        reasons.push('to inventory->return');
      }

      if (PURCHASED_BY_NORMALIZATION.has(tx.purchasedBy)) {
        const value = PURCHASED_BY_NORMALIZATION.get(tx.purchasedBy);
        update.purchasedBy = value === null ? FieldValue.delete() : value;
        reasons.push(`normalize purchasedBy ${JSON.stringify(tx.purchasedBy)}`);
      }
      if (REIMBURSEMENT_NORMALIZATION.has(tx.reimbursementType)) {
        const value = REIMBURSEMENT_NORMALIZATION.get(tx.reimbursementType);
        update.reimbursementType = value === null ? FieldValue.delete() : value;
        reasons.push(`normalize reimbursementType ${JSON.stringify(tx.reimbursementType)}`);
      }

      if (type === 'fee' && tx.source === '1584 Design Inventory') {
        update.source = FieldValue.delete();
        reasons.push('remove design-fee inventory source');
      }

      if (mixedCategoryIds.has(tx.budgetCategoryId)) {
        const projectCategoryNames = categoryNamesByAccountProject.get(`${accountId}:${tx.projectId}`) ?? new Set();
        const targetName = targetCategoryNameForTransaction(tx, projectCategoryNames);
        const target = targetName ? categoriesByName.get(normalize(targetName)) : null;
        if (target && target.id !== tx.budgetCategoryId) {
          update.budgetCategoryId = target.id;
          reasons.push(`mixed category recategorize -> ${targetName}`);
        } else if (target && target.id === tx.budgetCategoryId) {
          reasons.push(`mixed category target already current -> ${targetName}`);
        } else if (targetName === 'Storage & Receiving') {
          const fallback = categoriesByName.get(normalize('Install Services'));
          if (fallback) {
            update.budgetCategoryId = fallback.id;
            reasons.push('mixed category recategorize -> Install Services fallback');
          }
        } else {
          reasons.push('mixed category needs manual target');
        }
      }

      if (Object.keys(update).length === 0) continue;

      const event = {
        mode: COMMIT ? 'commit' : 'dry-run',
        accountId,
        accountName,
        path: doc.ref.path,
        id: doc.id,
        current: {
          type: tx.type ?? null,
          source: tx.source ?? null,
          budgetCategoryId: tx.budgetCategoryId ?? null,
          purchasedBy: tx.purchasedBy ?? null,
          reimbursementType: tx.reimbursementType ?? null,
        },
        update: compactUpdate(update),
        reasons,
      };
      console.log(JSON.stringify(event));
      if (COMMIT) {
        await doc.ref.update({ ...update, updatedAt: FieldValue.serverTimestamp() });
      }
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
