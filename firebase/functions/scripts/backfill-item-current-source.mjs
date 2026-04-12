#!/usr/bin/env node
/**
 * Backfill `currentSource` on every item across all accounts.
 *
 * Context: `item.currentSource` is a new denormalized field (added alongside the
 * existing `item.source`). `source` is the original vendor, preserved forever.
 * `currentSource` is the immediate/current source — denormalized from the
 * item's current transaction `source` so search cards can render the origin
 * without a per-row transaction lookup.
 *
 * Derivation rule (mirrors what `InventoryOperationsService` writes going
 * forward):
 *
 *   if item.currentSource != null → skip (idempotent, already backfilled)
 *   else if item.transactionId resolves to a transaction →
 *     if tx.type == "Sale" || tx.type == "Return":
 *       currentSource = tx.source || "Business Inventory"
 *     else (purchase or unknown):
 *       currentSource = tx.source || item.source
 *   else:
 *     currentSource = item.source
 *
 * The script skips the write entirely if the derived value is null/empty, so
 * items with no source information stay unchanged.
 *
 * ## Usage
 *
 * ### Production (default)
 * Requires a service-account JSON with Firestore write access:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
 *   node firebase/functions/scripts/backfill-item-current-source.mjs
 *
 * ### Emulator
 *   FIRESTORE_EMULATOR_HOST=localhost:8181 \
 *   FIREBASE_PROJECT_ID=ledger-nine4 \
 *     node firebase/functions/scripts/backfill-item-current-source.mjs
 *
 * ### Dry run
 *   DRY_RUN=1 node firebase/functions/scripts/backfill-item-current-source.mjs
 */

import admin from 'firebase-admin';

const projectId = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const dryRun = process.env.DRY_RUN === '1';

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();

const DEFAULT_INVENTORY_LABEL = 'Business Inventory';

function normalizeTxType(type) {
  return typeof type === 'string' ? type.trim().toLowerCase() : null;
}

function deriveCurrentSource({ item, tx }) {
  if (!tx) {
    return (item.source ?? null) || null;
  }
  const txType = normalizeTxType(tx.type);
  const txSource = typeof tx.source === 'string' && tx.source.length > 0 ? tx.source : null;
  if (txType === 'sale' || txType === 'return') {
    return txSource ?? DEFAULT_INVENTORY_LABEL;
  }
  return txSource ?? (item.source ?? null) ?? null;
}

async function backfillAccount(accountId) {
  const itemsRef = db.collection(`accounts/${accountId}/items`);
  const txCache = new Map();

  async function getTx(txId) {
    if (!txId) return null;
    if (txCache.has(txId)) return txCache.get(txId);
    const snap = await db.doc(`accounts/${accountId}/transactions/${txId}`).get();
    const data = snap.exists ? (snap.data() ?? null) : null;
    txCache.set(txId, data);
    return data;
  }

  const writer = db.bulkWriter();
  writer.onWriteError((err) => err.failedAttempts < 3);

  let scanned = 0;
  let updated = 0;
  let skipped = 0;
  let blank = 0;

  const snap = await itemsRef.get();
  for (const doc of snap.docs) {
    scanned++;
    const item = doc.data() ?? {};

    if (item.currentSource != null) {
      skipped++;
      continue;
    }

    const tx = await getTx(item.transactionId);
    const derived = deriveCurrentSource({ item, tx });

    if (!derived) {
      blank++;
      continue;
    }

    updated++;
    if (!dryRun) {
      writer.update(doc.ref, { currentSource: derived });
    }
  }

  if (!dryRun) {
    await writer.close();
  }

  return { scanned, updated, skipped, blank };
}

async function main() {
  console.log(
    `[${dryRun ? 'DRY RUN' : 'LIVE'}] Backfilling item.currentSource — project ${projectId}`
  );

  const accountsSnap = await db.collection('accounts').select().get();
  if (accountsSnap.empty) {
    console.log('No accounts found. Nothing to do.');
    return;
  }

  const totals = { scanned: 0, updated: 0, skipped: 0, blank: 0 };
  for (const acctDoc of accountsSnap.docs) {
    const accountId = acctDoc.id;
    const res = await backfillAccount(accountId);
    totals.scanned += res.scanned;
    totals.updated += res.updated;
    totals.skipped += res.skipped;
    totals.blank += res.blank;
    console.log(
      `  account ${accountId}: scanned=${res.scanned} updated=${res.updated} skipped=${res.skipped} blank=${res.blank}`
    );
  }

  console.log(
    `Done. Totals — scanned=${totals.scanned} updated=${totals.updated} skipped=${totals.skipped} blank=${totals.blank}`
  );
  if (dryRun) {
    console.log('(dry run — no writes performed)');
  }
}

main().catch((err) => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
