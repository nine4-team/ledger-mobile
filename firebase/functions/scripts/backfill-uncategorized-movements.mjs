#!/usr/bin/env node
/**
 * Backfill `budgetCategoryId` on legacy uncategorized inventory-movement
 * transactions so they are reflected in project budget progress.
 *
 * Context
 * -------
 * A handful of legacy / manually-created inventory movements (Sale to
 * inventory, Return to inventory) were written without a budget category —
 * either the field is missing/empty or it holds the literal string
 * "uncategorized". The budget-progress builder skips any transaction whose
 * `budgetCategoryId` doesn't resolve to a real category, so these amounts
 * silently drop out of the project's category spend and overall total.
 *
 * These transactions are frozen by Firestore rules and by the MCP
 * `update_transaction` guard (accounting shape fields are immutable on
 * inventory movements). This script uses the Admin SDK directly — the
 * sanctioned escape hatch for one-off data repair — to set the correct
 * category. It also repairs any in-project items still attached to those
 * transactions that carry the same bad category (the project-item invariant
 * requires a real category).
 *
 * Safety
 * ------
 *  - Dry run by default. Pass `--apply` to commit.
 *  - Targets are DISCOVERED from the data (non-canceled transactions in the
 *    configured projects whose category is missing/empty/"uncategorized"),
 *    not from a hand-maintained ID list.
 *  - Only INVENTORY MOVEMENTS (Sale, or Return/Purchase from "* Inventory")
 *    are auto-assigned. A plain uncategorized Purchase is reported but never
 *    guessed at — its correct category isn't necessarily the project default.
 *  - Idempotent: a transaction that already has a real category is skipped.
 *
 * Usage
 * -----
 *   Dry run:
 *     GOOGLE_APPLICATION_CREDENTIALS=/path/AuthKey.json \
 *       node firebase/functions/scripts/backfill-uncategorized-movements.mjs
 *   Apply:
 *     GOOGLE_APPLICATION_CREDENTIALS=/path/AuthKey.json \
 *       node firebase/functions/scripts/backfill-uncategorized-movements.mjs --apply
 */

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';

const APPLY = process.argv.includes('--apply');
const projectId = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const ACCOUNT_ID = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94'; // 1584 Design
const TODAY = '2026-07-06';

/**
 * Per-project remediation config. `categoryId` is the category every legacy
 * uncategorized inventory movement in that project belongs to.
 * Start with Sandra – BAHAMA only; add more projects after it verifies.
 */
const TARGETS = [
  {
    label: 'Sandra – BAHAMA Unit',
    projectId: 'fc4e8569-75f6-46b4-97ae-c4bc57f615d0',
    categoryId: 'da556858-1df8-40be-b10c-b15710d7cc9a', // Furnishings
    categoryName: 'Furnishings',
  },
];

// ── init ────────────────────────────────────────────────────────────────────
if (!admin.apps.length) {
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    admin.initializeApp({ projectId });
    console.error(`[backfill] EMULATOR ${process.env.FIRESTORE_EMULATOR_HOST}`);
  } else if (credPath) {
    const serviceAccount = JSON.parse(readFileSync(credPath, 'utf8'));
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount), projectId });
    console.error(`[backfill] PRODUCTION as ${serviceAccount.client_email}`);
  } else {
    admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId });
    console.error('[backfill] PRODUCTION via application-default credentials');
  }
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// ── helpers ──────────────────────────────────────────────────────────────────
const money = (c) => `$${((c ?? 0) / 100).toFixed(2)}`;

function isBadCategory(v) {
  if (v == null) return true;
  if (typeof v !== 'string') return true;
  const t = v.trim().toLowerCase();
  return t === '' || t === 'uncategorized';
}

function isInventoryMovement(tx) {
  const type = typeof tx.type === 'string' ? tx.type.trim().toLowerCase() : '';
  const source = typeof tx.source === 'string' ? tx.source.trim() : '';
  if (type === 'sale') return true;
  if ((type === 'return' || type === 'purchase') && / Inventory$/.test(source)) return true;
  return false;
}

function txCol() {
  return db.collection(`accounts/${ACCOUNT_ID}/transactions`);
}
function itemDoc(id) {
  return db.doc(`accounts/${ACCOUNT_ID}/items/${id}`);
}

const NOTE = (categoryName) =>
  `${TODAY} — Data repair: assigned ${categoryName} budget category to a legacy ` +
  `uncategorized inventory movement so it is reflected in project budget progress.`;

// ── main ──────────────────────────────────────────────────────────────────────
async function processTarget(target) {
  console.log(`\n=== ${target.label} (${target.projectId}) ===`);
  console.log(`Assigning category: ${target.categoryName} (${target.categoryId})`);

  const snap = await txCol().where('projectId', '==', target.projectId).get();

  const fixTx = [];   // inventory movements → auto-assign
  const skipTx = [];  // uncategorized but NOT a movement → report only

  for (const doc of snap.docs) {
    const tx = doc.data() ?? {};
    if (tx.status === 'canceled') continue;
    if (!isBadCategory(tx.budgetCategoryId)) continue;
    (isInventoryMovement(tx) ? fixTx : skipTx).push({ id: doc.id, tx });
  }

  // Discover in-project items on the fixable transactions that share the bad category.
  const itemsToFix = [];
  for (const { tx } of fixTx) {
    for (const itemId of tx.itemIds ?? []) {
      const isnap = await itemDoc(itemId).get();
      if (!isnap.exists) continue;
      const item = isnap.data() ?? {};
      if (item.projectId === target.projectId && isBadCategory(item.budgetCategoryId)) {
        itemsToFix.push({ id: itemId, item });
      }
    }
  }

  // Report
  console.log(`\nTransactions to fix (inventory movements): ${fixTx.length}`);
  for (const { id, tx } of fixTx) {
    const cur = tx.budgetCategoryId == null ? '<missing>' : JSON.stringify(tx.budgetCategoryId);
    console.log(`  ${id}  ${String(tx.type).padEnd(8)} ${money(tx.amountCents).padStart(10)}  ${cur} → ${target.categoryId}`);
  }
  console.log(`\nIn-project items to fix: ${itemsToFix.length}`);
  for (const { id, item } of itemsToFix) {
    const cur = item.budgetCategoryId == null ? '<missing>' : JSON.stringify(item.budgetCategoryId);
    console.log(`  ${id}  ${String(item.name ?? '').slice(0, 40).padEnd(40)}  ${cur} → ${target.categoryId}`);
  }
  if (skipTx.length) {
    console.log(`\n⚠️  Uncategorized NON-movement transactions (NOT auto-fixed — verify manually):`);
    for (const { id, tx } of skipTx) {
      console.log(`  ${id}  ${String(tx.type).padEnd(8)} ${money(tx.amountCents).padStart(10)}  source=${tx.source ?? ''}`);
    }
  }

  if (!APPLY) return { fixed: fixTx.length, items: itemsToFix.length, skipped: skipTx.length };

  // Apply
  const batch = db.batch();
  for (const { id, tx } of fixTx) {
    const notes = typeof tx.notes === 'string' && tx.notes.length
      ? `${tx.notes}\n${NOTE(target.categoryName)}`
      : NOTE(target.categoryName);
    batch.update(txCol().doc(id), {
      budgetCategoryId: target.categoryId,
      notes,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  for (const { id } of itemsToFix) {
    batch.update(itemDoc(id), {
      budgetCategoryId: target.categoryId,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  console.log(`\n✅ Applied: ${fixTx.length} transactions, ${itemsToFix.length} items.`);
  return { fixed: fixTx.length, items: itemsToFix.length, skipped: skipTx.length };
}

async function main() {
  console.log(APPLY ? '*** APPLY MODE — writing to Firestore ***' : '*** DRY RUN — no writes (pass --apply to commit) ***');
  let totals = { fixed: 0, items: 0, skipped: 0 };
  for (const target of TARGETS) {
    const r = await processTarget(target);
    totals.fixed += r.fixed;
    totals.items += r.items;
    totals.skipped += r.skipped;
  }
  console.log(`\n──────────────────────────────────────`);
  console.log(`${APPLY ? 'Applied' : 'Would fix'}: ${totals.fixed} transactions, ${totals.items} items` +
    (totals.skipped ? `; ${totals.skipped} non-movement uncategorized left for manual review.` : '.'));
}

main().catch((err) => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
