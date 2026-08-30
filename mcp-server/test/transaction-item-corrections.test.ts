/**
 * Focused legacy-emulator coverage for correct_transaction_and_its_items.
 * Normal MCP validation still uses a disposable real-Firestore smoke test.
 */

import { beforeAll, beforeEach, describe, expect, test } from "vitest";
import {
  TEST_ACCOUNT_ID,
  getDocData,
  getTestDb,
  listLineageEdges,
  makeCapturedServer,
  seedItem,
  seedProject,
  seedSpace,
  seedTransaction,
  wipeAccount,
  withContext,
} from "./helpers.js";
import { registerTransactionItemCorrectionTools } from "../src/tools/transaction-item-corrections.js";

const db = getTestDb();
const server = makeCapturedServer();

beforeAll(() => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  registerTransactionItemCorrectionTools(server as any, db);
});

beforeEach(async () => {
  await wipeAccount(db);
});

function callTool(args: Record<string, unknown>) {
  const handler = server.handlers.get("correct_transaction_and_its_items");
  if (!handler) throw new Error("Correction tool not registered");
  return withContext(() => handler(args));
}

function parseText(result: unknown): any {
  const response = result as { content?: Array<{ text?: string }> };
  return JSON.parse(response.content?.[0]?.text ?? "{}");
}

async function seedItemizedCategory(projectId: string, categoryId: string) {
  await db.doc(
    `accounts/${TEST_ACCOUNT_ID}/presets/default/budgetCategories/${categoryId}`
  ).set({
    name: categoryId,
    isArchived: false,
    isSystem: false,
    metadata: { categoryType: "itemized" },
  });
  await db.doc(
    `accounts/${TEST_ACCOUNT_ID}/projects/${projectId}/budgetCategories/${categoryId}`
  ).set({ budgetCents: 100_000 });
}

describe("correct_transaction_and_its_items", () => {
  test("moves a project Purchase and every attached item to general inventory", async () => {
    await seedProject(db, { id: "project_a" });
    await seedSpace(db, { id: "space_a", projectId: "project_a" });
    await seedTransaction(db, {
      id: "purchase_a",
      type: "Purchase",
      source: "Vendor",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      itemIds: ["item_1", "item_2"],
      purchaseHandling: "project_reimbursement",
      reimbursementType: "owed-to-company",
    });
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/transactions/purchase_a`).update({
      intendedProjectId: "project_a",
      intendedBudgetCategoryId: "category_a",
    });
    for (const itemId of ["item_1", "item_2"]) {
      await seedItem(db, {
        id: itemId,
        projectId: "project_a",
        budgetCategoryId: "category_a",
        transactionId: "purchase_a",
        spaceId: "space_a",
      });
    }

    const dryRun = parseText(await callTool({
      transactionId: "purchase_a",
      destinationProjectId: null,
      dryRun: true,
    }));
    expect(dryRun.plan.eligible).toBe(true);
    expect(dryRun.plan.detachedSpaceAssignments).toHaveLength(2);
    expect(dryRun.plan.transactionChanges).toMatchObject({
      projectId: null,
      budgetCategoryId: null,
      purchaseHandling: "inventory_resale",
      reimbursementType: null,
      intendedProjectId: null,
      intendedBudgetCategoryId: null,
    });

    const before = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/purchase_a`
    );
    expect(before?.projectId).toBe("project_a");
    expect(await listLineageEdges(db)).toHaveLength(0);

    const result = parseText(await callTool({
      transactionId: "purchase_a",
      destinationProjectId: null,
      requestId: "request-project-to-inventory",
      dryRun: false,
    }));
    expect(result.corrected).toBe(true);

    const transaction = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/purchase_a`
    );
    expect(transaction?.projectId).toBeNull();
    expect(transaction?.budgetCategoryId).toBeNull();
    expect(transaction?.itemIds).toEqual(["item_1", "item_2"]);
    expect(transaction?.purchaseHandling).toBe("inventory_resale");
    expect(transaction?.reimbursementType).toBeUndefined();
    expect(transaction?.intendedProjectId).toBeUndefined();
    expect(transaction?.intendedBudgetCategoryId).toBeUndefined();

    for (const itemId of ["item_1", "item_2"]) {
      const item = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/${itemId}`);
      expect(item?.projectId).toBeNull();
      expect(item?.budgetCategoryId).toBeNull();
      expect(item?.transactionId).toBe("purchase_a");
      expect(item?.spaceId).toBeNull();
    }

    const lineage = await listLineageEdges(db);
    expect(lineage).toHaveLength(2);
    expect(lineage.every(({ data }) =>
      data.movementKind === "correction" &&
      data.fromTransactionId === "purchase_a" &&
      data.toTransactionId === "purchase_a" &&
      data.fromProjectId === "project_a" &&
      data.toProjectId === null &&
      data.requestId === "request-project-to-inventory"
    )).toBe(true);
  });

  test("moves an inventory Purchase into a project with an explicit reimbursement choice", async () => {
    await seedProject(db, { id: "project_b" });
    await seedItemizedCategory("project_b", "category_b");
    await seedTransaction(db, {
      id: "inventory_purchase",
      type: "Purchase",
      source: "Vendor",
      projectId: null,
      budgetCategoryId: null,
      itemIds: ["item_1"],
      purchaseHandling: "inventory_resale",
    });
    await seedItem(db, {
      id: "item_1",
      projectId: null,
      budgetCategoryId: null,
      transactionId: "inventory_purchase",
      purchasePriceCents: 12_500,
      projectPriceCents: 0,
    });

    const result = parseText(await callTool({
      transactionId: "inventory_purchase",
      destinationProjectId: "project_b",
      destinationBudgetCategoryId: "category_b",
      destinationPurchaseHandling: "project_reimbursement",
      dryRun: false,
    }));
    expect(result.corrected).toBe(true);

    const transaction = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/inventory_purchase`
    );
    expect(transaction).toMatchObject({
      projectId: "project_b",
      budgetCategoryId: "category_b",
      itemIds: ["item_1"],
      purchaseHandling: "project_reimbursement",
      reimbursementType: "owed-to-company",
    });
    const item = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item).toMatchObject({
      projectId: "project_b",
      budgetCategoryId: "category_b",
      transactionId: "inventory_purchase",
      projectPriceCents: 12_500,
    });
  });

  test("moves an ordinary Return and all items between projects without Purchase metadata", async () => {
    await seedProject(db, { id: "project_a" });
    await seedProject(db, { id: "project_b" });
    await seedItemizedCategory("project_b", "category_b");
    await seedTransaction(db, {
      id: "vendor_return",
      type: "Return",
      source: "Vendor",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      transactionId: "vendor_return",
    });

    const result = parseText(await callTool({
      transactionId: "vendor_return",
      destinationProjectId: "project_b",
      destinationBudgetCategoryId: "category_b",
      dryRun: false,
    }));
    expect(result.corrected).toBe(true);
    expect(await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/vendor_return`
    )).toMatchObject({
      projectId: "project_b",
      budgetCategoryId: "category_b",
      itemIds: ["item_1"],
    });
    expect(await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/items/item_1`
    )).toMatchObject({
      projectId: "project_b",
      budgetCategoryId: "category_b",
      transactionId: "vendor_return",
    });
  });

  test("blocks an inventory Purchase to project when Purchase handling is omitted", async () => {
    await seedProject(db, { id: "project_b" });
    await seedItemizedCategory("project_b", "category_b");
    await seedTransaction(db, {
      id: "inventory_purchase",
      type: "Purchase",
      source: "Vendor",
      projectId: null,
      budgetCategoryId: null,
      itemIds: ["item_1"],
      purchaseHandling: "inventory_resale",
    });
    await seedItem(db, {
      id: "item_1",
      projectId: null,
      budgetCategoryId: null,
      transactionId: "inventory_purchase",
    });

    const dryRun = parseText(await callTool({
      transactionId: "inventory_purchase",
      destinationProjectId: "project_b",
      destinationBudgetCategoryId: "category_b",
      dryRun: true,
    }));
    expect(dryRun.plan.eligible).toBe(false);
    expect(dryRun.plan.blockers).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "PROJECT_PURCHASE_HANDLING_REQUIRED" }),
    ]));

    const executeResult = await callTool({
      transactionId: "inventory_purchase",
      destinationProjectId: "project_b",
      destinationBudgetCategoryId: "category_b",
      dryRun: false,
    });
    expect((executeResult as { isError?: boolean }).isError).toBe(true);
    expect(await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/inventory_purchase`
    )).toMatchObject({ projectId: null, budgetCategoryId: null });
    expect(await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/items/item_1`
    )).toMatchObject({ projectId: null, budgetCategoryId: null });
    expect(await listLineageEdges(db)).toHaveLength(0);
  });

  test("accepts explicit null handling for an ordinary inventory Purchase corrected into a project", async () => {
    await seedProject(db, { id: "project_b" });
    await seedItemizedCategory("project_b", "category_b");
    await seedTransaction(db, {
      id: "inventory_purchase",
      type: "Purchase",
      source: "Vendor",
      projectId: null,
      budgetCategoryId: null,
      itemIds: ["item_1"],
      purchaseHandling: "inventory_resale",
    });
    await seedItem(db, {
      id: "item_1",
      projectId: null,
      budgetCategoryId: null,
      transactionId: "inventory_purchase",
      purchasePriceCents: 12_500,
      projectPriceCents: 0,
    });

    const result = parseText(await callTool({
      transactionId: "inventory_purchase",
      destinationProjectId: "project_b",
      destinationBudgetCategoryId: "category_b",
      destinationPurchaseHandling: null,
      dryRun: false,
    }));
    expect(result.corrected).toBe(true);
    const transaction = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/inventory_purchase`
    );
    expect(transaction).toMatchObject({
      projectId: "project_b",
      budgetCategoryId: "category_b",
      itemIds: ["item_1"],
    });
    expect(transaction?.purchaseHandling).toBeUndefined();
    expect(transaction?.reimbursementType).toBeUndefined();
    expect(await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/items/item_1`
    )).toMatchObject({
      projectId: "project_b",
      budgetCategoryId: "category_b",
      transactionId: "inventory_purchase",
      projectPriceCents: 12_500,
    });
  });

  test("blocks asymmetric membership without partially updating the aggregate", async () => {
    await seedTransaction(db, {
      id: "purchase_a",
      type: "Purchase",
      source: "Vendor",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      transactionId: null,
    });

    const result = parseText(await callTool({
      transactionId: "purchase_a",
      destinationProjectId: null,
      dryRun: true,
    }));
    expect(result.plan.eligible).toBe(false);
    expect(result.plan.blockers).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "ASYMMETRIC_ACTIVE_MEMBERSHIP" }),
    ]));

    const executeResult = await callTool({
      transactionId: "purchase_a",
      destinationProjectId: null,
      dryRun: false,
    });
    expect((executeResult as { isError?: boolean }).isError).toBe(true);
    expect(await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/purchase_a`
    )).toMatchObject({ projectId: "project_a", itemIds: ["item_1"] });
    expect(await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/items/item_1`
    )).toMatchObject({ projectId: "project_a", transactionId: null });
  });

  test("blocks generated inventory movements", async () => {
    await seedTransaction(db, {
      id: "movement_purchase",
      type: "Purchase",
      source: "Business Inventory",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      transactionId: "movement_purchase",
    });

    const result = parseText(await callTool({
      transactionId: "movement_purchase",
      destinationProjectId: null,
      dryRun: true,
    }));
    expect(result.plan.eligible).toBe(false);
    expect(result.plan.blockers).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "IMMUTABLE_INVENTORY_MOVEMENT" }),
    ]));
  });

  test("blocks a missing or ineligible destination category", async () => {
    await seedProject(db, { id: "project_b" });
    await seedTransaction(db, {
      id: "vendor_return",
      type: "Return",
      source: "Vendor",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      transactionId: "vendor_return",
    });

    const result = parseText(await callTool({
      transactionId: "vendor_return",
      destinationProjectId: "project_b",
      destinationBudgetCategoryId: "missing_category",
      dryRun: true,
    }));
    expect(result.plan.eligible).toBe(false);
    expect(result.plan.blockers).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "DESTINATION_CATEGORY_NOT_FOUND" }),
      expect.objectContaining({ code: "DESTINATION_CATEGORY_NOT_ENABLED" }),
    ]));
  });

  test("blocks inventory-resale handling for an explicitly client-paid Purchase", async () => {
    await seedTransaction(db, {
      id: "client_purchase",
      type: "Purchase",
      source: "Vendor",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      itemIds: ["item_1"],
    });
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/transactions/client_purchase`).update({
      purchasedBy: "client-card",
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      transactionId: "client_purchase",
    });

    const result = parseText(await callTool({
      transactionId: "client_purchase",
      destinationProjectId: null,
      dryRun: true,
    }));
    expect(result.plan.eligible).toBe(false);
    expect(result.plan.blockers).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "PURCHASE_PAYER_CONFLICT" }),
    ]));
  });

  test("blocks invoice references to either the transaction or an active item", async () => {
    await seedTransaction(db, {
      id: "purchase_a",
      type: "Purchase",
      source: "Vendor",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      transactionId: "purchase_a",
    });
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/invoices/invoice_1`).set({
      projectId: "project_a",
      status: "created",
      itemIds: ["item_1"],
      lines: [{
        id: "line_1",
        sourceType: "item",
        sourceId: "item_1",
        amountCents: 1000,
        sign: 1,
      }],
    });

    const result = parseText(await callTool({
      transactionId: "purchase_a",
      destinationProjectId: null,
      dryRun: true,
    }));
    expect(result.plan.eligible).toBe(false);
    expect(result.plan.blockers).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "INVOICE_REFERENCES", referenceIds: ["invoice_1"] }),
    ]));
  });

  test("blocks downstream movement lineage and inventory-entry provenance", async () => {
    await seedTransaction(db, {
      id: "purchase_a",
      type: "Purchase",
      source: "Vendor",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      transactionId: "purchase_a",
    });
    await seedItem(db, {
      id: "historical_item",
      projectId: null,
      budgetCategoryId: null,
      inventoryEntryTransactionId: "purchase_a",
    });
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/lineageEdges/movement_1`).set({
      itemId: "item_1",
      fromTransactionId: "purchase_a",
      movementKind: "sold",
    });

    const result = parseText(await callTool({
      transactionId: "purchase_a",
      destinationProjectId: null,
      dryRun: true,
    }));
    expect(result.plan.eligible).toBe(false);
    expect(result.plan.blockers).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "INVENTORY_PROVENANCE" }),
      expect.objectContaining({ code: "DOWNSTREAM_MOVEMENT_LINEAGE" }),
    ]));
  });

  test("rejects an aggregate that exceeds Firestore's atomic write limit", async () => {
    const itemIds = Array.from({ length: 250 }, (_, index) => `item_${index}`);
    await seedTransaction(db, {
      id: "large_purchase",
      type: "Purchase",
      source: "Vendor",
      projectId: "project_a",
      budgetCategoryId: "category_a",
      itemIds,
    });
    const batch = db.batch();
    for (const itemId of itemIds) {
      batch.set(db.doc(`accounts/${TEST_ACCOUNT_ID}/items/${itemId}`), {
        name: itemId,
        status: "purchased",
        projectId: "project_a",
        budgetCategoryId: "category_a",
        transactionId: "large_purchase",
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    }
    await batch.commit();

    const result = parseText(await callTool({
      transactionId: "large_purchase",
      destinationProjectId: null,
      dryRun: true,
    }));
    expect(result.plan.eligible).toBe(false);
    expect(result.plan.writeCount).toBe(501);
    expect(result.plan.blockers).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "ATOMIC_WRITE_LIMIT_EXCEEDED" }),
    ]));
  });
});
