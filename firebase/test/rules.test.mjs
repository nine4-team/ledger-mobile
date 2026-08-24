// Emulator-backed Firestore rules tests for the per-batch sale redesign.
//
// Covers the R1-R5 matrix from docs/plans per-batch sale redesign:
//   R1  Update amountCents on a Sale transaction                  → rejected
//   R2  Update itemIds on a Sale transaction                      → allowed
//   R3  Update budgetCategoryId on a Sale transaction             → rejected
//   R4  Update notes on a Sale transaction                        → allowed
//   R5  Legacy isCanonicalInventorySale: true sale                → allowed (mutable)
//
// Plus regression checks:
//   R6  Non-Sale transaction update (Purchase)                    → allowed
//   R7  Update `type` on a Sale transaction                       → rejected
//   R8  Update `source` on a Sale transaction                     → rejected
//   R9  Update `projectId` on a Sale transaction                  → rejected
//
// Run:
//   1) cd firebase/test && npm install
//   2) In another terminal: firebase emulators:start --only firestore --project demo-rules-test
//   3) npm test
//
// Exits non-zero on any failure.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RULES_PATH = resolve(__dirname, '../firestore.rules');

const ACCOUNT_ID = 'acc_rules_test';
const USER_ID = 'user_rules_test';
const EMPLOYEE_ID = 'employee_rules_test';
const TARGET_MEMBER_ID = 'target_member_rules_test';
const SALE_ID = 'sale_new_perbatch';
const LEGACY_SALE_ID = 'SALE_legacy_business_to_project_cat1';
const PURCHASE_ID = 'tx_purchase';

const results = [];
let failures = 0;

async function run(name, fn) {
  try {
    await fn();
    results.push({ name, status: 'PASS' });
    console.log(`  ✓ ${name}`);
  } catch (err) {
    failures += 1;
    results.push({ name, status: 'FAIL', error: err?.message ?? String(err) });
    console.log(`  ✗ ${name}`);
    console.log(`      ${err?.message ?? err}`);
  }
}

const testEnv = await initializeTestEnvironment({
  projectId: 'demo-rules-test',
  firestore: {
    rules: readFileSync(RULES_PATH, 'utf8'),
    host: '127.0.0.1',
    port: 8181,
  },
});

// Seed: membership + test transactions, bypassing rules.
await testEnv.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();

  // Membership doc so isAccountMember() returns true.
  await setDoc(doc(db, `accounts/${ACCOUNT_ID}/users/${USER_ID}`), {
    uid: USER_ID,
    role: 'owner',
  });
  await setDoc(doc(db, `accounts/${ACCOUNT_ID}/users/${EMPLOYEE_ID}`), {
    uid: EMPLOYEE_ID,
    role: 'user',
  });
  await setDoc(doc(db, `accounts/${ACCOUNT_ID}/users/${TARGET_MEMBER_ID}`), {
    uid: TARGET_MEMBER_ID,
    role: 'user',
    email: 'target@example.com',
  });

  // New per-batch Sale transaction (the shape the rule guards).
  await setDoc(doc(db, `accounts/${ACCOUNT_ID}/transactions/${SALE_ID}`), {
    type: 'Sale',
    source: 'Business Inventory',
    projectId: 'proj1',
    budgetCategoryId: 'cat1',
    amountCents: 10000,
    itemIds: ['item1', 'item2', 'item3'],
    notes: 'initial note',
    status: 'complete',
    createdBy: USER_ID,
  });

  // Legacy canonical sale (must remain mutable for cancel_transaction etc.).
  await setDoc(doc(db, `accounts/${ACCOUNT_ID}/transactions/${LEGACY_SALE_ID}`), {
    type: 'Sale',
    isCanonicalInventorySale: true,
    inventorySaleDirection: 'business_to_project',
    source: 'Purchase from Inventory',
    projectId: 'proj1',
    budgetCategoryId: 'cat1',
    amountCents: 5000,
    itemIds: ['itemA'],
  });

  // Non-Sale transaction (regression baseline: update should still work).
  await setDoc(doc(db, `accounts/${ACCOUNT_ID}/transactions/${PURCHASE_ID}`), {
    type: 'Purchase',
    source: 'Amazon',
    projectId: 'proj1',
    amountCents: 3000,
    itemIds: ['itemX'],
  });
});

const authed = testEnv.authenticatedContext(USER_ID).firestore();
const employeeAuthed = testEnv.authenticatedContext(EMPLOYEE_ID).firestore();
const saleRef = doc(authed, `accounts/${ACCOUNT_ID}/transactions/${SALE_ID}`);
const legacyRef = doc(authed, `accounts/${ACCOUNT_ID}/transactions/${LEGACY_SALE_ID}`);
const purchaseRef = doc(authed, `accounts/${ACCOUNT_ID}/transactions/${PURCHASE_ID}`);
const targetMemberRef = doc(authed, `accounts/${ACCOUNT_ID}/users/${TARGET_MEMBER_ID}`);
const employeeTargetMemberRef = doc(employeeAuthed, `accounts/${ACCOUNT_ID}/users/${TARGET_MEMBER_ID}`);
const validItemRef = doc(authed, `accounts/${ACCOUNT_ID}/items/item_price_valid`);
const invalidItemRef = doc(authed, `accounts/${ACCOUNT_ID}/items/item_price_invalid`);

console.log('\nRunning Firestore rules tests for Sale immutability:\n');

await run('R1: update amountCents on per-batch Sale → rejected', async () => {
  await assertFails(updateDoc(saleRef, { amountCents: 99999 }));
});

await run('R2: update itemIds on per-batch Sale → allowed', async () => {
  await assertSucceeds(updateDoc(saleRef, { itemIds: ['item1'] }));
});

await run('R3: update budgetCategoryId on per-batch Sale → rejected', async () => {
  await assertFails(updateDoc(saleRef, { budgetCategoryId: 'cat2' }));
});

await run('R4: update notes on per-batch Sale → allowed', async () => {
  await assertSucceeds(updateDoc(saleRef, { notes: 'updated note' }));
});

await run('R5: update amountCents on legacy canonical sale → allowed', async () => {
  await assertSucceeds(updateDoc(legacyRef, { amountCents: 7777 }));
});

await run('R6: update amountCents on Purchase transaction → allowed (regression)', async () => {
  await assertSucceeds(updateDoc(purchaseRef, { amountCents: 77 }));
});

await run('R7: update type on per-batch Sale → rejected', async () => {
  await assertFails(updateDoc(saleRef, { type: 'Purchase' }));
});

await run('R8: update source on per-batch Sale → rejected', async () => {
  await assertFails(updateDoc(saleRef, { source: 'Something Else' }));
});

await run('R9: update projectId on per-batch Sale → rejected', async () => {
  await assertFails(updateDoc(saleRef, { projectId: 'projOther' }));
});

await run('R10: update status on per-batch Sale → allowed', async () => {
  await assertSucceeds(updateDoc(saleRef, { status: 'canceled' }));
});

await run('R11: owner updates member financial access → allowed', async () => {
  await assertSucceeds(updateDoc(targetMemberRef, {
    role: 'user',
    companyFinancialAccess: 'limited',
    allowedFeeCategoryIds: ['kitchen'],
    updatedAt: new Date(),
  }));
});

await run('R12: employee updates member financial access → rejected', async () => {
  await assertFails(updateDoc(employeeTargetMemberRef, {
    companyFinancialAccess: 'full',
    allowedFeeCategoryIds: [],
    updatedAt: new Date(),
  }));
});

await run('R13: owner updates unrelated membership field → rejected', async () => {
  await assertFails(updateDoc(targetMemberRef, {
    email: 'changed@example.com',
    updatedAt: new Date(),
  }));
});

await run('R14: item project price at purchase-cost floor → allowed', async () => {
  await assertSucceeds(setDoc(validItemRef, {
    name: 'Chair',
    purchasePriceCents: 10000,
    projectPriceCents: 10000,
  }));
});

await run('R15: item project price below purchase cost → rejected', async () => {
  await assertFails(setDoc(invalidItemRef, {
    name: 'Chair',
    purchasePriceCents: 10000,
    projectPriceCents: 0,
  }));
});

await run('R16: partial update cannot raise purchase above project price → rejected', async () => {
  await assertFails(updateDoc(validItemRef, { purchasePriceCents: 12000 }));
});

await testEnv.cleanup();

console.log(`\nResult: ${results.length - failures}/${results.length} passed`);
if (failures > 0) {
  console.log('\nFailures:');
  for (const r of results.filter((r) => r.status === 'FAIL')) {
    console.log(`  - ${r.name}`);
    console.log(`      ${r.error}`);
  }
  process.exit(1);
}
process.exit(0);
