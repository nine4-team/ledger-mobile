import admin from "firebase-admin";

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "ledger-nine4";
const ACCOUNT_ID = "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94";
const SOURCE_PROJECT_ID = "405GIhLoU2pLY4zqb71R";
const DEST_PROJECT_ID = "fc4e8569-75f6-46b4-97ae-c4bc57f615d0";
const SOURCE_TRANSACTION_ID = "dT91f6jiZXVRmkX8RN7t";
const DEST_TRANSACTION_ID = "E614DE46-40F0-4D95-99EC-CD9F2E59432C";
const SOURCE_BUDGET_CATEGORY_ID = "da556858-1df8-40be-b10c-b15710d7cc9a";
const REPAIR_TRANSACTION_ID = "REPAIR_SALE_TO_INVENTORY_20260624_001";
const CREATED_BY = "4ef35958-597c-4aea-b99e-1ef62352a72d";
const INVENTORY_LABEL = "1584 Design Inventory";
const ITEMS = [
  "Dcysdan3I84AOmFMfrMd",
  "H11MvVi0hAmeTmTF8qaz",
];

const COMMIT = process.argv.includes("--commit");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;

function assertEqual(label, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function assertArrayContains(label, array, expected) {
  if (!Array.isArray(array) || !array.includes(expected)) {
    throw new Error(`${label}: expected array to contain ${expected}`);
  }
}

function centsSum(items) {
  return items.reduce((sum, item) => sum + (item.purchasePriceCents ?? 0), 0);
}

async function fetchRequiredDoc(path) {
  const snap = await db.doc(path).get();
  if (!snap.exists) throw new Error(`Missing required document: ${path}`);
  return { ref: snap.ref, id: snap.id, data: snap.data() };
}

async function collectExistingRepairEdges() {
  const edges = [];
  for (const itemId of ITEMS) {
    const snap = await db
      .collection(`accounts/${ACCOUNT_ID}/lineageEdges`)
      .where("itemId", "==", itemId)
      .where("toTransactionId", "==", REPAIR_TRANSACTION_ID)
      .get();
    snap.docs.forEach((doc) => edges.push({ id: doc.id, ...doc.data() }));
  }
  return edges;
}

async function buildPlan() {
  const repairRef = db.doc(`accounts/${ACCOUNT_ID}/transactions/${REPAIR_TRANSACTION_ID}`);
  const repairSnap = await repairRef.get();
  if (repairSnap.exists) {
    throw new Error(`Repair transaction already exists: ${REPAIR_TRANSACTION_ID}`);
  }

  const itemDocs = [];
  for (const itemId of ITEMS) {
    const doc = await fetchRequiredDoc(`accounts/${ACCOUNT_ID}/items/${itemId}`);
    const item = doc.data;
    assertEqual(`${itemId}.name`, item.name, "Regan 3-Drawer Nightstand");
    assertEqual(`${itemId}.sku`, item.sku, "W004254185");
    assertEqual(`${itemId}.projectId`, item.projectId, DEST_PROJECT_ID);
    assertEqual(`${itemId}.budgetCategoryId`, item.budgetCategoryId, SOURCE_BUDGET_CATEGORY_ID);
    assertEqual(`${itemId}.transactionId`, item.transactionId, DEST_TRANSACTION_ID);
    assertEqual(`${itemId}.source`, item.source, "Wayfair");
    assertEqual(`${itemId}.currentSource`, item.currentSource, INVENTORY_LABEL);
    assertEqual(`${itemId}.purchasePriceCents`, item.purchasePriceCents, 49499);
    assertEqual(`${itemId}.projectPriceCents`, item.projectPriceCents, 49499);
    itemDocs.push({ id: itemId, ...item });
  }

  const sourceTx = await fetchRequiredDoc(
    `accounts/${ACCOUNT_ID}/transactions/${SOURCE_TRANSACTION_ID}`
  );
  assertEqual("sourceTx.type", sourceTx.data.type, "Purchase");
  assertEqual("sourceTx.source", sourceTx.data.source, "Wayfair");
  assertEqual("sourceTx.projectId", sourceTx.data.projectId, SOURCE_PROJECT_ID);
  assertEqual("sourceTx.budgetCategoryId", sourceTx.data.budgetCategoryId, SOURCE_BUDGET_CATEGORY_ID);

  const destTx = await fetchRequiredDoc(
    `accounts/${ACCOUNT_ID}/transactions/${DEST_TRANSACTION_ID}`
  );
  assertEqual("destTx.type", destTx.data.type, "Purchase");
  assertEqual("destTx.source", destTx.data.source, INVENTORY_LABEL);
  assertEqual("destTx.projectId", destTx.data.projectId, DEST_PROJECT_ID);
  assertEqual("destTx.budgetCategoryId", destTx.data.budgetCategoryId, SOURCE_BUDGET_CATEGORY_ID);
  ITEMS.forEach((itemId) => assertArrayContains("destTx.itemIds", destTx.data.itemIds, itemId));

  const existingRepairEdges = await collectExistingRepairEdges();
  if (existingRepairEdges.length > 0) {
    throw new Error(`Repair lineage already exists: ${existingRepairEdges.map((e) => e.id).join(", ")}`);
  }

  const amountCents = centsSum(itemDocs);
  assertEqual("amountCents", amountCents, 98998);

  return {
    repairRef,
    amountCents,
    transaction: {
      type: "Sale",
      source: INVENTORY_LABEL,
      projectId: SOURCE_PROJECT_ID,
      sourceBudgetCategoryId: SOURCE_BUDGET_CATEGORY_ID,
      amountCents,
      subtotalCents: amountCents,
      itemIds: ITEMS,
      status: "completed",
      isComplete: true,
      transactionDate: "6/23/2026",
      createdAt: Timestamp.fromDate(new Date("2026-06-24T00:10:10.732Z")),
      updatedAt: FieldValue.serverTimestamp(),
      createdBy: CREATED_BY,
      notes:
        '[AI 6/24/2026] Repair: backfilled missing source-side Sale-to-Inventory hop for project-to-project sale of two Regan 3-Drawer Nightstand items (SKU W004254185). Items originated in source project transaction dT91f6jiZXVRmkX8RN7t from Wayfair and were sold into destination project transaction E614DE46-40F0-4D95-99EC-CD9F2E59432C through 1584 Design Inventory.',
    },
    edges: ITEMS.map((itemId) => ({
      accountId: ACCOUNT_ID,
      itemId,
      fromProjectId: SOURCE_PROJECT_ID,
      toProjectId: null,
      fromTransactionId: SOURCE_TRANSACTION_ID,
      toTransactionId: REPAIR_TRANSACTION_ID,
      movementKind: "soldToInventory",
      source: "repair",
      createdAt: FieldValue.serverTimestamp(),
      createdBy: CREATED_BY,
      note:
        "Repair backfill: missing first-hop Sale-to-Inventory for project-to-project sale into E614DE46-40F0-4D95-99EC-CD9F2E59432C.",
    })),
  };
}

function printablePlan(plan) {
  return {
    mode: COMMIT ? "COMMIT" : "DRY_RUN",
    projectId: PROJECT_ID,
    accountId: ACCOUNT_ID,
    transactionPath: plan.repairRef.path,
    transaction: {
      ...plan.transaction,
      createdAt: plan.transaction.createdAt.toDate().toISOString(),
      updatedAt: "SERVER_TIMESTAMP",
    },
    lineageEdges: plan.edges.map((edge) => ({
      ...edge,
      createdAt: "SERVER_TIMESTAMP",
    })),
  };
}

async function commit(plan) {
  const batch = db.batch();
  batch.create(plan.repairRef, plan.transaction);
  const edgesCol = db.collection(`accounts/${ACCOUNT_ID}/lineageEdges`);
  for (const edge of plan.edges) {
    batch.create(edgesCol.doc(), edge);
  }
  await batch.commit();
}

async function verify() {
  const tx = await db.doc(`accounts/${ACCOUNT_ID}/transactions/${REPAIR_TRANSACTION_ID}`).get();
  const edges = await collectExistingRepairEdges();
  const itemSnaps = await Promise.all(
    ITEMS.map((itemId) => db.doc(`accounts/${ACCOUNT_ID}/items/${itemId}`).get())
  );
  return {
    repairTransactionExists: tx.exists,
    repairTransaction: tx.exists
      ? {
          id: tx.id,
          type: tx.data().type,
          source: tx.data().source,
          projectId: tx.data().projectId,
          sourceBudgetCategoryId: tx.data().sourceBudgetCategoryId,
          amountCents: tx.data().amountCents,
          itemIds: tx.data().itemIds,
        }
      : null,
    repairLineageEdges: edges.map((edge) => ({
      id: edge.id,
      itemId: edge.itemId,
      movementKind: edge.movementKind,
      fromTransactionId: edge.fromTransactionId,
      toTransactionId: edge.toTransactionId,
    })),
    itemsUnmoved: itemSnaps.map((snap) => ({
      id: snap.id,
      projectId: snap.data()?.projectId,
      budgetCategoryId: snap.data()?.budgetCategoryId,
      transactionId: snap.data()?.transactionId,
      currentSource: snap.data()?.currentSource,
    })),
  };
}

try {
  const plan = await buildPlan();
  console.log(JSON.stringify(printablePlan(plan), null, 2));
  if (!COMMIT) {
    console.log("\nDry-run only. Re-run with --commit to write.");
    process.exit(0);
  }
  await commit(plan);
  console.log("\nCommitted repair.");
  console.log(JSON.stringify(await verify(), null, 2));
} catch (err) {
  console.error(err);
  process.exit(1);
}
