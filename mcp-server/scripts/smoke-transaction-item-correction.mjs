#!/usr/bin/env node
import { randomUUID } from "node:crypto";
import { initFirebase } from "../build/firebase.js";
import { requestContext } from "../build/context.js";
import { registerTransactionItemCorrectionTools } from "../build/tools/transaction-item-corrections.js";

const credentialsPath = process.argv[2] ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
const accountId = process.env.LEDGER_ACCOUNT_ID;
if (!credentialsPath || !accountId) {
  throw new Error(
    "Usage: LEDGER_ACCOUNT_ID=... node scripts/smoke-transaction-item-correction.mjs /path/to/service-account.json"
  );
}
if (process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("This smoke test must verify real Firestore; FIRESTORE_EMULATOR_HOST must be unset.");
}

const db = initFirebase(credentialsPath);
const runId = randomUUID();
const requestId = `mcp-correction-smoke-${runId}`;
const projectId = `mcp-correction-smoke-project-${runId}`;
const categoryId = `mcp-correction-smoke-category-${runId}`;
const spaceId = `mcp-correction-smoke-space-${runId}`;
const transactionId = `mcp-correction-smoke-transaction-${runId}`;
const itemIds = [
  `mcp-correction-smoke-item-a-${runId}`,
  `mcp-correction-smoke-item-b-${runId}`,
];

function capture(register) {
  const handlers = new Map();
  register({
    tool(...args) { handlers.set(args[0], args.at(-1)); },
    resource() {},
  }, db);
  return handlers;
}

function parse(result) {
  const payload = JSON.parse(result.content[0].text);
  if (result.isError) throw new Error(JSON.stringify(payload));
  return payload;
}

async function exactCleanup() {
  const fixedRefs = [
    ...itemIds.map((id) => db.doc(`accounts/${accountId}/items/${id}`)),
    db.doc(`accounts/${accountId}/transactions/${transactionId}`),
    db.doc(`accounts/${accountId}/spaces/${spaceId}`),
    db.doc(`accounts/${accountId}/projects/${projectId}/budgetCategories/${categoryId}`),
    db.doc(`accounts/${accountId}/projects/${projectId}`),
    db.doc(`accounts/${accountId}/presets/default/budgetCategories/${categoryId}`),
  ];
  // Budget-summary triggers may finish after the transaction is removed and
  // briefly recreate the disposable project. Re-delete only these exact smoke
  // IDs after bounded waits so cleanup also covers delayed trigger writes.
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const lineage = await db.collection(`accounts/${accountId}/lineageEdges`)
      .where("requestId", "==", requestId)
      .get()
      .catch(() => null);
    for (const ref of [...(lineage?.docs.map((doc) => doc.ref) ?? []), ...fixedRefs]) {
      await ref.delete().catch(() => {});
    }
    if (attempt < 3) await new Promise((resolve) => setTimeout(resolve, 2_000));
  }

  const remainingDocuments = await db.getAll(...fixedRefs);
  const remainingLineage = await db.collection(`accounts/${accountId}/lineageEdges`)
    .where("requestId", "==", requestId)
    .get();
  if (remainingDocuments.some((snapshot) => snapshot.exists) || !remainingLineage.empty) {
    throw new Error("Disposable correction smoke fixtures were not fully removed.");
  }
}

await requestContext.run({ accountId, uid: "mcp-correction-smoke" }, async () => {
  try {
    await db.doc(`accounts/${accountId}/projects/${projectId}`).set({
      name: "Disposable MCP transaction correction smoke",
      clientName: "Disposable smoke",
      isArchived: false,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await db.doc(`accounts/${accountId}/presets/default/budgetCategories/${categoryId}`).set({
      name: "Disposable MCP correction category",
      isArchived: false,
      isSystem: false,
      metadata: { categoryType: "itemized" },
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await db.doc(`accounts/${accountId}/projects/${projectId}/budgetCategories/${categoryId}`).set({
      budgetCents: 100,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await db.doc(`accounts/${accountId}/spaces/${spaceId}`).set({
      name: "Disposable MCP correction space",
      projectId,
      isArchived: false,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await db.doc(`accounts/${accountId}/transactions/${transactionId}`).set({
      type: "Purchase",
      source: "Disposable MCP correction vendor",
      projectId,
      budgetCategoryId: categoryId,
      itemIds,
      amountCents: 200,
      subtotalCents: 200,
      status: "completed",
      purchaseHandling: "project_reimbursement",
      reimbursementType: "owed-to-company",
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    for (const itemId of itemIds) {
      await db.doc(`accounts/${accountId}/items/${itemId}`).set({
        name: "Disposable MCP correction item",
        status: "purchased",
        projectId,
        budgetCategoryId: categoryId,
        transactionId,
        spaceId,
        purchasePriceCents: 100,
        projectPriceCents: 100,
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    }

    const tools = capture(registerTransactionItemCorrectionTools);
    const correct = tools.get("correct_transaction_and_its_items");
    if (!correct) throw new Error("Correction tool was not registered.");

    const dryRun = parse(await correct({
      transactionId,
      destinationProjectId: null,
      requestId,
      dryRun: true,
    }));
    if (!dryRun.plan.eligible || dryRun.plan.activeItemCount !== 2 || dryRun.plan.writeCount !== 5) {
      throw new Error(`Unexpected dry-run plan: ${JSON.stringify(dryRun)}`);
    }
    const before = await db.doc(`accounts/${accountId}/transactions/${transactionId}`).get();
    if (before.data()?.projectId !== projectId) throw new Error("Dry-run mutated the transaction.");

    const executed = parse(await correct({
      transactionId,
      destinationProjectId: null,
      requestId,
      dryRun: false,
    }));
    if (!executed.corrected) throw new Error("Execution reported no correction.");

    const transaction = await db.doc(`accounts/${accountId}/transactions/${transactionId}`).get();
    if (
      transaction.data()?.projectId !== null ||
      transaction.data()?.budgetCategoryId !== null ||
      transaction.data()?.purchaseHandling !== "inventory_resale" ||
      JSON.stringify(transaction.data()?.itemIds) !== JSON.stringify(itemIds)
    ) {
      throw new Error("Corrected transaction did not preserve membership and inventory invariants.");
    }
    const itemSnapshots = await db.getAll(...itemIds.map((id) =>
      db.doc(`accounts/${accountId}/items/${id}`)
    ));
    for (const snapshot of itemSnapshots) {
      const item = snapshot.data();
      if (
        item?.projectId !== null ||
        item?.budgetCategoryId !== null ||
        item?.transactionId !== transactionId ||
        item?.spaceId !== null
      ) {
        throw new Error(`Corrected item ${snapshot.id} violated aggregate invariants.`);
      }
    }
    const lineage = await db.collection(`accounts/${accountId}/lineageEdges`)
      .where("requestId", "==", requestId)
      .get();
    if (lineage.size !== 2) throw new Error("Correction lineage count was not two.");

    console.log(JSON.stringify({
      ok: true,
      runId,
      verified: [
        "dry-run isolation",
        "two-sided membership preservation",
        "atomic project-to-inventory correction",
        "category clearing",
        "space detachment",
        "Purchase handling cleanup",
        "per-item correction lineage",
      ],
    }, null, 2));
  } finally {
    await exactCleanup();
  }
});
