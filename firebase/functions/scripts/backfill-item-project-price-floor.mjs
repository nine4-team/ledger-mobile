#!/usr/bin/env node
/**
 * Repair legacy Item documents whose project price is below purchase cost.
 * Dry-run is the default; pass --commit to write. Optionally scope with
 * --account <accountId>; otherwise every account is scanned.
 */

import admin from 'firebase-admin';

const projectId = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const commit = process.argv.includes('--commit');
const accountFlag = process.argv.indexOf('--account');
const accountId = accountFlag >= 0 ? process.argv[accountFlag + 1] : null;

if (accountFlag >= 0 && !accountId) {
  throw new Error('--account requires an account id');
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId,
  });
}

const db = admin.firestore();

function finitePrice(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

async function accountIds() {
  if (accountId) return [accountId];
  const snapshot = await db.collection('accounts').select().get();
  return snapshot.docs.map((doc) => doc.id);
}

async function repairAccount(id) {
  const snapshot = await db.collection(`accounts/${id}/items`).get();
  const candidates = snapshot.docs.flatMap((doc) => {
    const data = doc.data();
    const purchasePrice = finitePrice(data.purchasePriceCents);
    const projectPrice = finitePrice(data.projectPriceCents);
    if (purchasePrice == null || purchasePrice <= (projectPrice ?? 0)) return [];
    return [{ ref: doc.ref, from: projectPrice, to: purchasePrice }];
  });

  if (commit && candidates.length > 0) {
    const writer = db.bulkWriter();
    writer.onWriteError((error) => error.failedAttempts < 3);
    for (const candidate of candidates) {
      writer.update(candidate.ref, {
        projectPriceCents: candidate.to,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await writer.close();
  }

  console.log(`${id}: scanned=${snapshot.size} repair=${candidates.length}`);
  for (const candidate of candidates.slice(0, 20)) {
    console.log(`  ${candidate.ref.id}: ${candidate.from ?? 'missing'} -> ${candidate.to}`);
  }
  if (candidates.length > 20) console.log(`  ... ${candidates.length - 20} more`);
  return { scanned: snapshot.size, repaired: candidates.length };
}

let scanned = 0;
let repaired = 0;
console.log(`[${commit ? 'COMMIT' : 'DRY RUN'}] project=${projectId}`);
for (const id of await accountIds()) {
  const result = await repairAccount(id);
  scanned += result.scanned;
  repaired += result.repaired;
}
console.log(`Done: scanned=${scanned} ${commit ? 'repaired' : 'wouldRepair'}=${repaired}`);
if (!commit) console.log('No writes performed. Re-run with --commit to apply.');
