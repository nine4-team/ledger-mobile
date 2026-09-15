#!/usr/bin/env node
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { initFirebase } from "../build/firebase.js";
import { requestContext } from "../build/context.js";
import { registerInventoryOperationTools } from "../build/tools/inventory-operations.js";

// Real-Firestore regression in a new, isolated disposable account. Never accepts
// an existing account ID and never touches a client's inventory.
if (process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Real Firestore required.");
const db = initFirebase(process.argv[2] ?? process.env.GOOGLE_APPLICATION_CREDENTIALS);
const accountId = `mcp-resale-smoke-${randomUUID()}`;
const root = db.doc(`accounts/${accountId}`);
const doc = (path) => root.collection(path.split("/")[0]).doc(path.split("/").slice(1).join("/"));
const handlers = new Map();
registerInventoryOperationTools({ tool(...args) { handlers.set(args[0], args.at(-1)); } }, db);
const call = async (name, args) => {
  const result = await handlers.get(name)(args);
  assert.ok(!result.isError, result.content[0].text);
  return JSON.parse(result.content[0].text);
};
const get = async (path) => (await doc(path).get()).data();
const item = (transactionId, extra = {}) => ({
  name: "Disposable resale regression", projectId: null, budgetCategoryId: null,
  transactionId, purchasePriceCents: 100, projectPriceCents: 200,
  taxRatePct: 0, status: "purchased", ...extra,
});
await requestContext.run({ accountId, uid: "mcp-resale-smoke" }, async () => {
  await root.create({ name: "Disposable resale smoke" });
  try {
    for (const id of ["kristen", "other", "mason"]) {
      await doc(`projects/${id}`).set({ name: id, isArchived: false });
      await doc(`projects/${id}/budgetCategories/category`).set({ budgetCents: 1000 });
    }
    for (const [id, projectId, itemIds] of [
      ["sale-k", "kristen", ["single", "mixed", "return"]],
      ["sale-o", "other", ["other", "legacy"]],
    ]) {
      await doc(`transactions/${id}`).set({
        type: "Sale", source: "Business Inventory", status: "completed",
        projectId, budgetCategoryId: "category", itemIds,
        subtotalCents: itemIds.length * 100, amountCents: itemIds.length * 100,
      });
      for (const itemId of itemIds) {
        await doc(`items/${itemId}`).set(item(id, itemId === "legacy" ? {} : {
          inventoryEntryTransactionId: id, inventoryEntryProjectId: projectId,
          inventoryEntryBudgetCategoryId: "category",
          inventoryEntryPriceCents: 100, inventoryEntryAmountCents: 100,
        }));
      }
    }
    await doc("items/ordinary").set(item(null));
    await doc("transactions/home").set({ type: "Return", source: "Business Inventory",
      projectId: "other", budgetCategoryId: "category", itemIds: ["home"],
      amountCents: 100, subtotalCents: 100, status: "completed" });
    await doc("items/home").set(item("home"));
    const sell = (itemIds, dryRun) => call("sell_items_from_inventory_to_project", {
      itemIds, destinationProjectId: "mason", budgetCategoryId: "category", dryRun,
    });
    // Both entry points remain available with different prices/destinations.
    const locked = await call("return_items_from_inventory_to_project", {
      itemIds: ["single"], dryRun: true,
    });
    assert.equal(locked.lockedDestination.projectId, "kristen");
    assert.equal(locked.totals.amountCents, 100);
    const preview = await sell(["single"], true);
    assert.equal(preview.plan.purchaseTransaction.projectId, "mason");
    assert.equal(preview.plan.purchaseTransaction.amountCents, 200);
    assert.equal((await get("items/single")).projectId, null);
    const single = await sell(["single"], false);
    assert.equal((await get("items/single")).transactionId, single.purchaseTransactionId);
    // Mixed source projects/origins and ambiguous return evidence remain sellable.
    const ids = ["mixed", "other", "legacy", "ordinary", "home"];
    assert.equal((await sell(ids, true)).plan.purchaseTransaction.amountCents, 1000);
    const bulk = await sell(ids, false);
    for (const id of ["single", ...ids]) {
      const data = await get(`items/${id}`);
      assert.equal(data.projectId, "mason");
      assert.equal(data.budgetCategoryId, "category");
      assert.equal(data.projectPriceCents, 200);
      assert.equal(data.name, "Disposable resale regression");
    }
    assert.equal((await get(`transactions/${bulk.purchaseTransactionId}`)).amountCents, 1000);
    assert.equal((await get("transactions/sale-k")).amountCents, 300);
    assert.deepEqual((await get("transactions/sale-k")).itemIds, ["return"]);
    assert.equal((await get("transactions/sale-o")).amountCents, 200);
    assert.deepEqual((await get("transactions/sale-o")).itemIds, []);
    assert.equal((await get("items/single")).inventoryEntryProjectId, "kristen");
    const returned = await call("return_items_from_inventory_to_project", {
      itemIds: ["return"], dryRun: false,
    });
    assert.equal(returned.projectId, "kristen");
    assert.equal(returned.totals.amountCents, 100);
    assert.equal((await get("items/return")).projectPriceCents, 100);
    const invalid = await handlers.get("sell_items_from_inventory_to_project")({
      itemIds: ["single"], destinationProjectId: "mason", budgetCategoryId: "category", dryRun: true,
    });
    assert.equal(invalid.isError, true);
    // Production item triggers may add their own audit edges as well.
    assert.equal((await root.collection("lineageEdges").where("source", "==", "mcp").get()).size, 7);
    console.log(JSON.stringify({ ok: true, verified: ["single resale", "mixed bulk resale",
      "ambiguous return evidence does not block sale", "dry-run isolation", "locked return",
      "frozen acquisition totals and provenance", "lineage", "project-item rejection"] }));
  } finally {
    // Only the unique account created above; repeat for asynchronous budget triggers.
    for (let attempt = 0; attempt < 4; attempt++) {
      await db.recursiveDelete(root);
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
    assert.equal((await root.get()).exists, false);
    for (const collection of await root.listCollections()) {
      assert.equal((await collection.limit(1).get()).empty, true);
    }
    console.log("Disposable resale smoke account and fixtures removed.");
  }
});
