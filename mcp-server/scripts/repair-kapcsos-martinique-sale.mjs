import admin from "firebase-admin";

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "ledger-nine4";
const ACCOUNT_ID = "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94";
const SOURCE_PROJECT_ID = "405GIhLoU2pLY4zqb71R";
const SANDRA_PROJECT_ID = "0159ca8a-0e60-4861-8b10-1660e7fae38a";
const MASON_PROJECT_ID = "1LLWjydzaK6uD44TjM4u";
const CATEGORY_ID = "da556858-1df8-40be-b10c-b15710d7cc9a";
const INVENTORY_LABEL = "1584 Design Inventory";
const CREATED_BY = "4ef35958-597c-4aea-b99e-1ef62352a72d";
const COMMIT = process.argv.includes("--commit");
const VERIFY_ONLY = process.argv.includes("--verify");

const ITEMS = [
  { id: "BHRAcfCh0V0XMqXi1Jcy", name: '65.4" 2-Light Hand Woven Rattan Floor Lamp', sourceTx: "KH7PZPWtNR5NKeLf62qE", destination: "sandra", price: 13899 },
  { id: "ie5cY7l3a3dAcLJHQQ7h", name: "Minimalism Winter Pine Forest - Canvas Wall Art Set", sourceTx: "dT91f6jiZXVRmkX8RN7t", destination: "mason", price: 13799 },
  { id: "CK1JL53HPwYhP1ExCscp", name: "Meagan Table Lamp", sourceTx: "dT91f6jiZXVRmkX8RN7t", destination: "mason", price: 9799 },
  { id: "xmHQSrVxr5vBYpv3Ve32", name: "Meagan Table Lamp", sourceTx: "dT91f6jiZXVRmkX8RN7t", destination: "mason", price: 9799 },
];

const BOTCHED_TX_IDS = [
  "IsJMdv2UQkEJWH5xqTLg", "LzTWKvy27xMgXjOy3tRj", "3960ryP5d4FlYcHaUvik", "7EHHOHBgN2epoxrIOhxm",
  "RvVP7kLnmNoHx0ryVBVZ", "qfHv9YH4b6bt5TYywmMs", "iPnl6O2uzKEltoqFouN9", "9FP6utOHRQTsovV32qzp",
];

const FINAL = {
  sandra: {
    projectId: SANDRA_PROJECT_ID,
    saleId: "REPAIR_SALE_TO_INVENTORY_20260714_SANDRA",
    purchaseId: "REPAIR_PURCHASE_FROM_INVENTORY_20260714_SANDRA",
    itemIds: ["BHRAcfCh0V0XMqXi1Jcy"], subtotal: 13899, amount: 14837,
  },
  mason: {
    projectId: MASON_PROJECT_ID,
    saleId: "REPAIR_SALE_TO_INVENTORY_20260714_MASON",
    purchaseId: "REPAIR_PURCHASE_FROM_INVENTORY_20260714_MASON",
    itemIds: ["ie5cY7l3a3dAcLJHQQ7h", "CK1JL53HPwYhP1ExCscp", "xmHQSrVxr5vBYpv3Ve32"], subtotal: 33397, amount: 35650,
  },
};

if (!admin.apps.length) admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: PROJECT_ID });
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const path = (collection, id) => `accounts/${ACCOUNT_ID}/${collection}/${id}`;
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const equal = (label, actual, expected) => assert(actual === expected, `${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
const sameIds = (actual, expected) => Array.isArray(actual) && JSON.stringify([...actual].sort()) === JSON.stringify([...expected].sort());

function assertItem(item, expected) {
  equal(`${expected.id}.name`, item.name, expected.name);
  equal(`${expected.id}.purchasePriceCents`, item.purchasePriceCents, expected.price);
  equal(`${expected.id}.projectPriceCents`, item.projectPriceCents, expected.price);
  equal(`${expected.id}.taxRatePct`, item.taxRatePct, 6.75);
  equal(`${expected.id}.budgetCategoryId`, item.budgetCategoryId, CATEGORY_ID);
  equal(`${expected.id}.status`, item.status, "purchased");
  equal(`${expected.id}.currentSource`, item.currentSource, INVENTORY_LABEL);
  const final = FINAL[expected.destination];
  equal(`${expected.id}.projectId`, item.projectId, final.projectId);
  const allowedCurrentTx = expected.destination === "sandra" ? "qfHv9YH4b6bt5TYywmMs" : "9FP6utOHRQTsovV32qzp";
  equal(`${expected.id}.transactionId`, item.transactionId, allowedCurrentTx);
}

function assertSourceTx(tx, id) {
  equal(`${id}.type`, tx.type, "Purchase");
  equal(`${id}.source`, tx.source, "Wayfair");
  equal(`${id}.projectId`, tx.projectId, SOURCE_PROJECT_ID);
  equal(`${id}.budgetCategoryId`, tx.budgetCategoryId, CATEGORY_ID);
  for (const item of ITEMS.filter((entry) => entry.sourceTx === id)) {
    assert(!tx.itemIds?.includes(item.id), `${id}.itemIds unexpectedly still contains ${item.id}`);
  }
}

function assertBotchedTx(tx, id) {
  const expected = {
    IsJMdv2UQkEJWH5xqTLg: ["Sale", SOURCE_PROJECT_ID, 13899], LzTWKvy27xMgXjOy3tRj: ["Purchase", SANDRA_PROJECT_ID, 13899],
    "3960ryP5d4FlYcHaUvik": ["Sale", SOURCE_PROJECT_ID, 33397], "7EHHOHBgN2epoxrIOhxm": ["Purchase", MASON_PROJECT_ID, 33397],
    RvVP7kLnmNoHx0ryVBVZ: ["Return", SOURCE_PROJECT_ID, 13899], qfHv9YH4b6bt5TYywmMs: ["Purchase", SANDRA_PROJECT_ID, 14837],
    iPnl6O2uzKEltoqFouN9: ["Return", SOURCE_PROJECT_ID, 33397], "9FP6utOHRQTsovV32qzp": ["Purchase", MASON_PROJECT_ID, 35650],
  }[id];
  equal(`${id}.type`, tx.type, expected[0]); equal(`${id}.projectId`, tx.projectId, expected[1]); equal(`${id}.amountCents`, tx.amountCents, expected[2]);
  equal(`${id}.source`, tx.source, INVENTORY_LABEL); equal(`${id}.budgetCategoryId`, tx.budgetCategoryId, CATEGORY_ID);
}

async function loadSnapshot(reader = db) {
  const itemRefs = ITEMS.map((item) => db.doc(path("items", item.id)));
  const sourceRefs = ["KH7PZPWtNR5NKeLf62qE", "dT91f6jiZXVRmkX8RN7t"].map((id) => db.doc(path("transactions", id)));
  const botchedRefs = BOTCHED_TX_IDS.map((id) => db.doc(path("transactions", id)));
  const finalRefs = Object.values(FINAL).flatMap((entry) => [db.doc(path("transactions", entry.saleId)), db.doc(path("transactions", entry.purchaseId))]);
  const docs = await reader.getAll(...itemRefs, ...sourceRefs, ...botchedRefs, ...finalRefs);
  const edgeSnaps = [];
  for (const item of ITEMS) {
    const query = db.collection(path("lineageEdges", "")).where("itemId", "==", item.id);
    edgeSnaps.push(reader === db ? await query.get() : await reader.get(query));
  }
  return { docs, edgeDocs: edgeSnaps.flatMap((snap) => snap.docs), refs: { itemRefs, sourceRefs, botchedRefs, finalRefs } };
}

function validateSnapshot(snapshot) {
  const { docs, edgeDocs, refs } = snapshot;
  const byPath = new Map(docs.map((doc) => [doc.ref.path, doc]));
  for (const item of ITEMS) { const snap = byPath.get(path("items", item.id)); assert(snap?.exists, `Missing item ${item.id}`); assertItem(snap.data(), item); }
  for (const id of ["KH7PZPWtNR5NKeLf62qE", "dT91f6jiZXVRmkX8RN7t"]) { const snap = byPath.get(path("transactions", id)); assert(snap?.exists, `Missing source transaction ${id}`); assertSourceTx(snap.data(), id); }
  for (const id of BOTCHED_TX_IDS) { const snap = byPath.get(path("transactions", id)); assert(snap?.exists, `Missing botched transaction ${id}`); assertBotchedTx(snap.data(), id); }
  for (const ref of refs.finalRefs) assert(!byPath.get(ref.path)?.exists, `Final repair transaction already exists: ${ref.id}`);
  const relevantEdges = edgeDocs.filter((doc) => {
    const edge = doc.data();
    return BOTCHED_TX_IDS.includes(edge.fromTransactionId) || BOTCHED_TX_IDS.includes(edge.toTransactionId) ||
      (edge.createdAt?.toMillis?.() >= Date.parse("2026-07-14T23:53:00Z") && ITEMS.some((item) => item.id === edge.itemId));
  });
  assert(
    relevantEdges.length === 28,
    `botched lineage edge count: expected 28, got ${relevantEdges.length}; edges=${JSON.stringify(relevantEdges.map((doc) => ({ id: doc.id, ...doc.data() })), null, 2)}`
  );
  return { byPath, relevantEdges };
}

function saleDoc(final, now) {
  return { type: "Sale", source: INVENTORY_LABEL, projectId: SOURCE_PROJECT_ID, budgetCategoryId: CATEGORY_ID,
    amountCents: final.subtotal, subtotalCents: final.subtotal, itemIds: final.itemIds, status: "completed", isComplete: true,
    transactionDate: "2026-07-14", createdAt: now, updatedAt: now, createdBy: CREATED_BY,
    notes: "[AI 7/14/2026] Admin rollback + clean replay: source-side Sale-to-Inventory for corrected Kapcsos Martinique project-to-project sale. Supersedes the canceled/ignored botched sale/return/reissue sequence." };
}

function purchaseDoc(final, now) {
  return { type: "Purchase", source: INVENTORY_LABEL, projectId: final.projectId, budgetCategoryId: CATEGORY_ID,
    amountCents: final.amount, subtotalCents: final.subtotal, itemIds: final.itemIds, status: "completed", isComplete: true,
    transactionDate: "2026-07-14", createdAt: now, updatedAt: now, createdBy: CREATED_BY,
    notes: "[AI 7/14/2026] Admin rollback + clean replay: taxed destination Purchase for corrected Kapcsos Martinique project-to-project sale. Item tax rate is 6.75%. Supersedes the canceled/ignored botched sale/return/reissue sequence." };
}

function planSummary(validated) {
  return { mode: COMMIT ? "COMMIT" : "DRY_RUN", projectId: PROJECT_ID, accountId: ACCOUNT_ID,
    cancelAndEmptyTransactions: BOTCHED_TX_IDS, deleteBotchedLineageEdges: validated.relevantEdges.map((doc) => doc.id).sort(),
    createTransactions: Object.values(FINAL).flatMap((entry) => [
      { id: entry.saleId, type: "Sale", projectId: SOURCE_PROJECT_ID, subtotalCents: entry.subtotal, amountCents: entry.subtotal, itemIds: entry.itemIds },
      { id: entry.purchaseId, type: "Purchase", projectId: entry.projectId, subtotalCents: entry.subtotal, amountCents: entry.amount, itemIds: entry.itemIds },
    ]), updateItems: ITEMS.map((item) => ({ id: item.id, projectId: FINAL[item.destination].projectId, transactionId: FINAL[item.destination].purchaseId,
      purchasePriceCents: item.price, projectPriceCents: item.price, taxRatePct: 6.75, budgetCategoryId: CATEGORY_ID })), createIntentEdges: ITEMS.length * 2 };
}

async function commitRepair() {
  await db.runTransaction(async (tx) => {
    const snapshot = await loadSnapshot(tx);
    const validated = validateSnapshot(snapshot);
    const now = FieldValue.serverTimestamp();
    for (const ref of snapshot.refs.botchedRefs) tx.update(ref, { status: "canceled", itemIds: [], isComplete: false, audit: null,
      repairDisposition: "ignored-by-admin-rollback-20260714", repairNote: "Superseded by atomic rollback + clean replay.", updatedAt: now });
    for (const edge of validated.relevantEdges) tx.delete(edge.ref);
    const edgeCol = db.collection(path("lineageEdges", ""));
    for (const final of Object.values(FINAL)) {
      tx.create(db.doc(path("transactions", final.saleId)), saleDoc(final, now));
      tx.create(db.doc(path("transactions", final.purchaseId)), purchaseDoc(final, now));
      for (const itemId of final.itemIds) {
        const item = ITEMS.find((entry) => entry.id === itemId);
        tx.create(edgeCol.doc(), { accountId: ACCOUNT_ID, itemId, fromProjectId: SOURCE_PROJECT_ID, toProjectId: null,
          fromTransactionId: item.sourceTx, toTransactionId: final.saleId, movementKind: "soldToInventory", source: "admin-repair", createdBy: CREATED_BY, createdAt: now });
        tx.create(edgeCol.doc(), { accountId: ACCOUNT_ID, itemId, fromProjectId: null, toProjectId: final.projectId,
          fromTransactionId: final.saleId, toTransactionId: final.purchaseId, movementKind: "sold", source: "admin-repair", createdBy: CREATED_BY, createdAt: now });
        tx.update(db.doc(path("items", itemId)), { projectId: final.projectId, transactionId: final.purchaseId, budgetCategoryId: CATEGORY_ID,
          purchasePriceCents: item.price, projectPriceCents: item.price, taxRatePct: 6.75, status: "purchased", spaceId: null,
          currentSource: INVENTORY_LABEL, updatedBy: CREATED_BY, updatedAt: now });
      }
    }
  });
}

async function verify() {
  const finalTxs = [];
  for (const final of Object.values(FINAL)) for (const id of [final.saleId, final.purchaseId]) { const snap = await db.doc(path("transactions", id)).get(); finalTxs.push({ id, exists: snap.exists, ...(snap.exists ? { type: snap.data().type, status: snap.data().status, projectId: snap.data().projectId, subtotalCents: snap.data().subtotalCents, amountCents: snap.data().amountCents, itemIds: snap.data().itemIds } : {}) }); }
  const items = [];
  for (const item of ITEMS) { const snap = await db.doc(path("items", item.id)).get(); items.push(snap.exists ? { id: item.id, exists: true, projectId: snap.data().projectId, transactionId: snap.data().transactionId, taxRatePct: snap.data().taxRatePct } : { id: item.id, exists: false }); }
  const botched = [];
  for (const id of BOTCHED_TX_IDS) { const snap = await db.doc(path("transactions", id)).get(); botched.push(snap.exists ? { id, exists: true, status: snap.data().status, itemIds: snap.data().itemIds, repairDisposition: snap.data().repairDisposition } : { id, exists: false }); }
  const edges = [];
  for (const item of ITEMS) { const snap = await db.collection(path("lineageEdges", "")).where("itemId", "==", item.id).get(); edges.push(...snap.docs.map((doc) => ({ id: doc.id, itemId: item.id, movementKind: doc.data().movementKind, fromTransactionId: doc.data().fromTransactionId, toTransactionId: doc.data().toTransactionId }))); }
  const activeReturnEdges = edges.filter((edge) => edge.movementKind === "returned");
  assert(activeReturnEdges.length === 0, `Active returned edges remain: ${activeReturnEdges.map((edge) => edge.id).join(", ")}`);
  assert(edges.filter((edge) => edge.movementKind === "soldToInventory").length === 4, "Expected exactly four soldToInventory edges");
  assert(edges.filter((edge) => edge.movementKind === "sold").length === 4, "Expected exactly four sold edges");
  const sourceTransactions = [];
  for (const id of ["KH7PZPWtNR5NKeLf62qE", "dT91f6jiZXVRmkX8RN7t"]) {
    const snap = await db.doc(path("transactions", id)).get();
    sourceTransactions.push(snap.exists ? { id, exists: true, isComplete: snap.data().isComplete, audit: snap.data().audit } : { id, exists: false });
  }
  const projects = [];
  for (const id of [SOURCE_PROJECT_ID, SANDRA_PROJECT_ID, MASON_PROJECT_ID]) {
    const snap = await db.doc(path("projects", id)).get();
    projects.push(snap.exists ? { id, exists: true, name: snap.data().name, furnishings: snap.data().budgetSummary?.categories?.[CATEGORY_ID], budgetUpdatedAt: snap.data().budgetSummary?.updatedAt } : { id, exists: false });
  }
  return { finalTransactions: finalTxs, items, botchedTransactions: botched, activeIntentEdges: edges, sourceTransactions, projects };
}

try {
  if (VERIFY_ONLY) {
    console.log(JSON.stringify(await verify(), null, 2));
    process.exit(0);
  }
  const snapshot = await loadSnapshot();
  const validated = validateSnapshot(snapshot);
  console.log(JSON.stringify(planSummary(validated), null, 2));
  if (!COMMIT) { console.log("\nDry-run only. Re-run with --commit to write."); process.exit(0); }
  await commitRepair();
  console.log("\nCommitted repair.");
  console.log(JSON.stringify(await verify(), null, 2));
} catch (error) { console.error(error); process.exit(1); }
