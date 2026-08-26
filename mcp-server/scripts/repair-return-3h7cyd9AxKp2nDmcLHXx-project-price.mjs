import assert from "node:assert/strict";
import admin from "firebase-admin";

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "ledger-nine4";
const ACCOUNT_ID = "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94";
const RETURN_ID = "3h7cyd9AxKp2nDmcLHXx";
const EXPECTED_PROJECT_ID = "5abd46c9-9886-4b3e-b2b1-19f6cf995a44";
const EXPECTED_INVENTORY_LABEL = "1584 Design Inventory";
const EXPECTED_ITEM_COUNT = 27;
const EXPECTED_LINEAGE_EDGE_COUNT = 81;
const INCORRECT_PURCHASE_CREDIT_CENTS = 61_074;
const CORRECT_PROJECT_CREDIT_CENTS = 110_102;
const APPLY = process.argv.includes("--apply");
const AUDIT_NOTE_PREFIX = "[AI 8/26/2026] Repaired Return 3h7cyd9AxKp2nDmcLHXx credit basis";

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
}

const db = admin.firestore();
const returnRef = db.doc(`accounts/${ACCOUNT_ID}/transactions/${RETURN_ID}`);
const edgesQuery = db
  .collection(`accounts/${ACCOUNT_ID}/lineageEdges`)
  .where("toTransactionId", "==", RETURN_ID);

function effectiveProjectPriceCents(item) {
  return Math.max(item.projectPriceCents ?? 0, item.purchasePriceCents ?? 0);
}

function normalized(value) {
  if (value == null || typeof value !== "object") return value;
  if (typeof value.toDate === "function") return value.toDate().toISOString();
  if (typeof value.path === "string" && value.constructor?.name === "DocumentReference") {
    return { documentReference: value.path };
  }
  if (Array.isArray(value)) return value.map(normalized);
  return Object.fromEntries(
    Object.entries(value)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, child]) => [key, normalized(child)])
  );
}

function fingerprint(value) {
  return JSON.stringify(normalized(value));
}

function withoutRepairableReturnFields(data) {
  const copy = { ...data };
  delete copy.amountCents;
  delete copy.subtotalCents;
  delete copy.notes;
  delete copy.updatedAt;
  return copy;
}

function revisedNotes(notes) {
  const lines = String(notes ?? "")
    .split("\n")
    .filter((line) => !line.startsWith(AUDIT_NOTE_PREFIX));
  while (lines.at(-1) === "") lines.pop();
  const auditNote =
    `${AUDIT_NOTE_PREFIX}: changed amountCents/subtotalCents from ` +
    `${INCORRECT_PURCHASE_CREDIT_CENTS} to ${CORRECT_PROJECT_CREDIT_CENTS}. ` +
    "No item, membership, scope, transaction link, or lineage movement was changed.";
  return [...lines, ...(lines.length ? [""] : []), auditNote].join("\n");
}

function validateState(returnSnap, itemSnaps, edgeSnap) {
  assert(returnSnap.exists, `Missing Return ${RETURN_ID}`);
  const returnData = returnSnap.data();
  assert.equal(String(returnData.type).toLowerCase(), "return", "transaction type");
  assert.equal(returnData.source, EXPECTED_INVENTORY_LABEL, "transaction source");
  assert.equal(returnData.projectId, EXPECTED_PROJECT_ID, "transaction projectId");
  assert.equal(returnData.amountCents, INCORRECT_PURCHASE_CREDIT_CENTS, "current amountCents");
  assert.equal(returnData.subtotalCents, INCORRECT_PURCHASE_CREDIT_CENTS, "current subtotalCents");
  assert.equal(returnData.status, "completed", "transaction status");
  assert.equal(typeof returnData.budgetCategoryId, "string", "transaction budgetCategoryId type");
  assert(returnData.budgetCategoryId.length > 0, "transaction budgetCategoryId must be set");

  const itemIds = returnData.itemIds ?? [];
  assert.equal(itemIds.length, EXPECTED_ITEM_COUNT, "return item count");
  assert.equal(new Set(itemIds).size, EXPECTED_ITEM_COUNT, "return itemIds must be unique");
  assert.equal(itemSnaps.length, EXPECTED_ITEM_COUNT, "loaded item count");

  const items = itemSnaps.map((snap) => {
    assert(snap.exists, `Missing item ${snap.id}`);
    const item = snap.data();
    assert.equal(item.transactionId, RETURN_ID, `${snap.id}.transactionId`);
    assert.equal(item.projectId ?? null, null, `${snap.id}.projectId`);
    assert.equal(item.budgetCategoryId ?? null, null, `${snap.id}.budgetCategoryId`);
    assert.equal(item.status, "purchased", `${snap.id}.status`);
    assert.equal(item.currentSource, EXPECTED_INVENTORY_LABEL, `${snap.id}.currentSource`);
    return { id: snap.id, ...item };
  });

  const purchaseTotalCents = items.reduce(
    (sum, item) => sum + (item.purchasePriceCents ?? 0),
    0
  );
  const projectTotalCents = items.reduce(
    (sum, item) => sum + effectiveProjectPriceCents(item),
    0
  );
  assert.equal(purchaseTotalCents, INCORRECT_PURCHASE_CREDIT_CENTS, "purchase-price total");
  assert.equal(projectTotalCents, CORRECT_PROJECT_CREDIT_CENTS, "project-price total");

  assert.equal(edgeSnap.size, EXPECTED_LINEAGE_EDGE_COUNT, "lineage edge count");
  const edgesByItemId = new Map();
  for (const snap of edgeSnap.docs) {
    const edge = snap.data();
    assert.equal(edge.toTransactionId, RETURN_ID, `${snap.id}.toTransactionId`);
    assert(itemIds.includes(edge.itemId), `${snap.id}.itemId is not a Return member`);
    assert(
      edge.movementKind === "returned" || edge.movementKind === "association",
      `${snap.id}.movementKind`
    );
    assert.equal(edge.fromProjectId, EXPECTED_PROJECT_ID, `${snap.id}.fromProjectId`);
    assert.equal(edge.toProjectId ?? null, null, `${snap.id}.toProjectId`);
    assert.equal(typeof edge.fromTransactionId, "string", `${snap.id}.fromTransactionId type`);
    assert(edge.fromTransactionId.length > 0, `${snap.id}.fromTransactionId must be set`);
    const itemEdges = edgesByItemId.get(edge.itemId) ?? [];
    itemEdges.push({ id: snap.id, ...edge });
    edgesByItemId.set(edge.itemId, itemEdges);
  }
  assert.deepEqual(
    [...edgesByItemId.keys()].sort(),
    [...itemIds].sort(),
    "lineage item membership"
  );
  for (const itemId of itemIds) {
    const itemEdges = edgesByItemId.get(itemId) ?? [];
    assert.equal(itemEdges.length, 3, `${itemId} lineage edge count`);
    const returnedEdges = itemEdges.filter((edge) => edge.movementKind === "returned");
    const associationEdges = itemEdges.filter((edge) => edge.movementKind === "association");
    assert.equal(returnedEdges.length, 2, `${itemId} returned edge count`);
    assert.equal(associationEdges.length, 1, `${itemId} association edge count`);
    assert.deepEqual(
      [...new Set(returnedEdges.map((edge) => edge.source))].sort(),
      ["mcp", "server"],
      `${itemId} returned edge sources`
    );
    assert.equal(associationEdges[0].source, "server", `${itemId} association source`);
    assert.equal(
      new Set(itemEdges.map((edge) => edge.fromTransactionId)).size,
      1,
      `${itemId} lineage fromTransactionId consistency`
    );
  }

  return {
    returnData,
    items,
    itemIds,
    purchaseTotalCents,
    projectTotalCents,
    credits: items
      .map((item) => ({
        itemId: item.id,
        name: item.name ?? null,
        purchasePriceCents: item.purchasePriceCents ?? 0,
        projectPriceCents: effectiveProjectPriceCents(item),
        creditCents: effectiveProjectPriceCents(item),
      }))
      .sort((a, b) => a.itemId.localeCompare(b.itemId)),
  };
}

async function loadState() {
  const returnSnap = await returnRef.get();
  assert(returnSnap.exists, `Missing Return ${RETURN_ID}`);
  const itemIds = returnSnap.data().itemIds ?? [];
  const itemRefs = itemIds.map((itemId) =>
    db.doc(`accounts/${ACCOUNT_ID}/items/${itemId}`)
  );
  const [itemSnaps, edgeSnap] = await Promise.all([
    itemRefs.length ? db.getAll(...itemRefs) : [],
    edgesQuery.get(),
  ]);
  return { returnSnap, itemRefs, itemSnaps, edgeSnap };
}

const beforeRaw = await loadState();
const before = validateState(
  beforeRaw.returnSnap,
  beforeRaw.itemSnaps,
  beforeRaw.edgeSnap
);
const beforeItemFingerprint = fingerprint(
  beforeRaw.itemSnaps.map((snap) => ({ id: snap.id, data: snap.data() }))
);
const beforeEdgeFingerprint = fingerprint(
  beforeRaw.edgeSnap.docs.map((snap) => ({ id: snap.id, data: snap.data() }))
);
const beforeStableReturnFingerprint = fingerprint(
  withoutRepairableReturnFields(before.returnData)
);

console.log(JSON.stringify({
  mode: APPLY ? "APPLY" : "DRY_RUN",
  returnPath: returnRef.path,
  itemCount: before.itemIds.length,
  lineageEdgeCount: beforeRaw.edgeSnap.size,
  before: {
    amountCents: before.returnData.amountCents,
    subtotalCents: before.returnData.subtotalCents,
    purchasePriceTotalCents: before.purchaseTotalCents,
  },
  after: {
    amountCents: before.projectTotalCents,
    subtotalCents: before.projectTotalCents,
    priceBasis: "projectPriceCents",
  },
  deltaCents: before.projectTotalCents - before.purchaseTotalCents,
  credits: before.credits,
  preserved: [
    "all 27 item documents",
    "Return.itemIds",
    "item project/inventory locations",
    "item.transactionId links",
    "all return lineage edges",
    "all other Return fields",
  ],
}, null, 2));

if (!APPLY) {
  console.log("\nDry-run only. Re-run with --apply after reviewing every guard and credit.");
  process.exit(0);
}

await db.runTransaction(async (transaction) => {
  const returnSnap = await transaction.get(returnRef);
  assert(returnSnap.exists, `Missing Return ${RETURN_ID}`);
  const itemIds = returnSnap.data().itemIds ?? [];
  assert.deepEqual(itemIds, before.itemIds, "Return.itemIds changed after dry-run read");
  const itemRefs = itemIds.map((itemId) =>
    db.doc(`accounts/${ACCOUNT_ID}/items/${itemId}`)
  );
  const itemSnaps = await Promise.all(itemRefs.map((ref) => transaction.get(ref)));
  const edgeSnap = await transaction.get(edgesQuery);
  const guarded = validateState(returnSnap, itemSnaps, edgeSnap);

  assert.equal(
    fingerprint(itemSnaps.map((snap) => ({ id: snap.id, data: snap.data() }))),
    beforeItemFingerprint,
    "Item documents changed after dry-run read"
  );
  assert.equal(
    fingerprint(edgeSnap.docs.map((snap) => ({ id: snap.id, data: snap.data() }))),
    beforeEdgeFingerprint,
    "Lineage edges changed after dry-run read"
  );
  assert.equal(
    fingerprint(withoutRepairableReturnFields(guarded.returnData)),
    beforeStableReturnFingerprint,
    "A protected Return field changed after dry-run read"
  );

  transaction.update(returnRef, {
    amountCents: CORRECT_PROJECT_CREDIT_CENTS,
    subtotalCents: CORRECT_PROJECT_CREDIT_CENTS,
    notes: revisedNotes(guarded.returnData.notes),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

const afterRaw = await loadState();
const afterReturnData = afterRaw.returnSnap.data();
assert.equal(afterReturnData.amountCents, CORRECT_PROJECT_CREDIT_CENTS, "repaired amountCents");
assert.equal(afterReturnData.subtotalCents, CORRECT_PROJECT_CREDIT_CENTS, "repaired subtotalCents");
assert.equal(
  fingerprint(withoutRepairableReturnFields(afterReturnData)),
  beforeStableReturnFingerprint,
  "A protected Return field changed during repair"
);
assert.equal(
  fingerprint(afterRaw.itemSnaps.map((snap) => ({ id: snap.id, data: snap.data() }))),
  beforeItemFingerprint,
  "An item document changed during repair"
);
assert.equal(
  fingerprint(afterRaw.edgeSnap.docs.map((snap) => ({ id: snap.id, data: snap.data() }))),
  beforeEdgeFingerprint,
  "A lineage edge changed during repair"
);

console.log(JSON.stringify({
  applied: true,
  returnId: RETURN_ID,
  amountCents: afterReturnData.amountCents,
  subtotalCents: afterReturnData.subtotalCents,
  unchangedItemDocuments: afterRaw.itemSnaps.length,
  unchangedLineageEdges: afterRaw.edgeSnap.size,
}, null, 2));
