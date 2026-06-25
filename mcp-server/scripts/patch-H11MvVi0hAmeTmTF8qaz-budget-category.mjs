import admin from "firebase-admin";

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "ledger-nine4";
const ACCOUNT_ID = "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94";
const REPAIR_TRANSACTION_ID = "REPAIR_SALE_TO_INVENTORY_20260624_001";
const BUDGET_CATEGORY_ID = "da556858-1df8-40be-b10c-b15710d7cc9a";
const COMMIT = process.argv.includes("--commit");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const repairRef = db.doc(
  `accounts/${ACCOUNT_ID}/transactions/${REPAIR_TRANSACTION_ID}`
);

function requiredEqual(label, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

const snap = await repairRef.get();
if (!snap.exists) {
  throw new Error(`Missing repair transaction: ${repairRef.path}`);
}

const tx = snap.data();

requiredEqual("type", tx.type, "Sale");
requiredEqual("source", tx.source, "1584 Design Inventory");
requiredEqual("projectId", tx.projectId, "405GIhLoU2pLY4zqb71R");
requiredEqual("amountCents", tx.amountCents, 98998);
requiredEqual("subtotalCents", tx.subtotalCents, 98998);

const itemIds = Array.isArray(tx.itemIds) ? [...tx.itemIds].sort() : [];
requiredEqual(
  "itemIds",
  JSON.stringify(itemIds),
  JSON.stringify(["Dcysdan3I84AOmFMfrMd", "H11MvVi0hAmeTmTF8qaz"].sort())
);

const patch = {
  budgetCategoryId: BUDGET_CATEGORY_ID,
  sourceBudgetCategoryId: FieldValue.delete(),
  updatedAt: FieldValue.serverTimestamp(),
};

console.log(JSON.stringify({
  mode: COMMIT ? "COMMIT" : "DRY_RUN",
  projectId: PROJECT_ID,
  transactionPath: repairRef.path,
  before: {
    budgetCategoryId: tx.budgetCategoryId ?? null,
    sourceBudgetCategoryId: tx.sourceBudgetCategoryId ?? null,
  },
  patch: {
    budgetCategoryId: BUDGET_CATEGORY_ID,
    sourceBudgetCategoryId: "DELETE_FIELD",
    updatedAt: "SERVER_TIMESTAMP",
  },
}, null, 2));

if (!COMMIT) {
  console.log("\nDry-run only. Re-run with --commit to write.");
  process.exit(0);
}

await repairRef.update(patch);

const afterSnap = await repairRef.get();
const after = afterSnap.data();

console.log("\nCommitted patch.");
console.log(JSON.stringify({
  transactionPath: repairRef.path,
  after: {
    budgetCategoryId: after.budgetCategoryId ?? null,
    hasSourceBudgetCategoryId: Object.prototype.hasOwnProperty.call(
      after,
      "sourceBudgetCategoryId"
    ),
    sourceBudgetCategoryId: after.sourceBudgetCategoryId ?? null,
  },
}, null, 2));
