import { beforeAll, beforeEach, describe, expect, test } from "vitest";
import {
  TEST_ACCOUNT_ID,
  getDocData,
  getTestDb,
  listLineageEdges,
  listTransactionsOfType,
  makeCapturedServer,
  seedItem,
  seedProject,
  seedTransaction,
  wipeAccount,
  withContext,
} from "./helpers.js";
import {
  registerInventoryOperationTools,
  resolveReturnToProjectProvenance,
} from "../src/tools/inventory-operations.js";
import type { Item, Transaction } from "../src/types.js";

const db = getTestDb();
const server = makeCapturedServer();

beforeAll(() => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  registerInventoryOperationTools(server as any, db);
});

beforeEach(async () => {
  await wipeAccount(db);
});

function callTool(name: string, args: Record<string, unknown>) {
  const handler = server.handlers.get(name);
  if (!handler) throw new Error(`Tool ${name} not registered`);
  return withContext(() => handler(args));
}

function isError(result: unknown): boolean {
  return Boolean((result as { isError?: boolean })?.isError);
}

function responseJson(result: unknown): Record<string, any> {
  const text = (result as { content?: Array<{ text?: string }> }).content?.[0]?.text ?? "{}";
  return JSON.parse(text) as Record<string, any>;
}

function item(overrides: Partial<Item> & { id: string }): Item & { id: string } {
  return { name: overrides.id, ...overrides } as Item & { id: string };
}

function transaction(overrides: Partial<Transaction> & { id: string }): Transaction & { id: string } {
  return { ...overrides } as Transaction & { id: string };
}

describe("resolveReturnToProjectProvenance", () => {
  test("uses the frozen snapshot rather than mutable price and tax fields", () => {
    const source = transaction({
      id: "return_1",
      type: "Return",
      status: "completed",
      source: "Business Inventory",
      projectId: "project_home",
      budgetCategoryId: "cat_original",
      subtotalCents: 10_000,
      amountCents: 10_825,
      itemIds: ["item_1"],
    });
    const selected = item({
      id: "item_1",
      projectId: undefined,
      transactionId: source.id,
      purchasePriceCents: 4_000,
      projectPriceCents: 99_999,
      taxRatePct: 20,
      inventoryEntryTransactionId: source.id,
      inventoryEntryProjectId: "project_home",
      inventoryEntryBudgetCategoryId: "cat_original",
      inventoryEntryPriceCents: 10_000,
      inventoryEntryAmountCents: 10_825,
    });

    const result = resolveReturnToProjectProvenance([selected], new Map([[source.id, source]]));
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.lines[0].priceCents).toBe(10_000);
    expect(result.lines[0].amountCents).toBe(10_825);
    expect(result.lines[0].budgetCategoryId).toBe("cat_original");
    expect(result.lines[0].evidence).toBe("snapshot");
  });

  test("rejects an inconsistent partial snapshot instead of falling back", () => {
    const source = transaction({
      id: "return_1",
      type: "Return",
      source: "Business Inventory",
      projectId: "project_home",
      budgetCategoryId: "cat_original",
      itemIds: ["item_1"],
    });
    const selected = item({
      id: "item_1",
      transactionId: source.id,
      inventoryEntryProjectId: "wrong_project",
    });

    const result = resolveReturnToProjectProvenance([selected], new Map([[source.id, source]]));
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.message).toContain("incomplete or inconsistent");
  });

  test("accepts only an exact single-item legacy transaction", () => {
    const exact = transaction({
      id: "sale_1",
      type: "Sale",
      source: "Business Inventory",
      projectId: "project_home",
      budgetCategoryId: "cat_original",
      subtotalCents: 8_000,
      amountCents: 8_000,
      itemIds: ["item_1"],
    });
    const selected = item({ id: "item_1", transactionId: exact.id, purchasePriceCents: 8_000 });
    const exactResult = resolveReturnToProjectProvenance([selected], new Map([[exact.id, exact]]));
    expect(exactResult.ok).toBe(true);
    if (exactResult.ok) expect(exactResult.lines[0].evidence).toBe("legacySingleItemTransaction");

    const ambiguous = transaction({ ...exact, itemIds: ["item_1", "item_2"] });
    const ambiguousResult = resolveReturnToProjectProvenance(
      [selected],
      new Map([[ambiguous.id, ambiguous]])
    );
    expect(ambiguousResult.ok).toBe(false);
    if (!ambiguousResult.ok) expect(ambiguousResult.message).toContain("exact provable");
  });
});

describe("return_items_from_inventory_to_project", () => {
  test("round-trips an MCP Return-to-Inventory at its newly frozen values", async () => {
    await seedProject(db, {
      id: "project_home",
      budgetCategories: [{ id: "cat_original" }],
    });
    await seedTransaction(db, {
      id: "project_purchase",
      type: "Purchase",
      source: "Business Inventory",
      projectId: "project_home",
      budgetCategoryId: "cat_original",
      subtotalCents: 10_000,
      amountCents: 10_825,
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "project_home",
      budgetCategoryId: "cat_original",
      transactionId: "project_purchase",
      purchasePriceCents: 4_000,
      projectPriceCents: 10_000,
      taxRatePct: 8.25,
      source: "Vendor",
      currentSource: "Business Inventory",
    });

    const toInventory = await callTool("return_items", {
      itemIds: ["item_1"],
      returnTo: "inventory",
      notes: "8/28 — Returned to inventory",
      dryRun: false,
    });
    expect(isError(toInventory)).toBe(false);
    const inventoryItem = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(inventoryItem).toMatchObject({
      projectId: null,
      budgetCategoryId: null,
      inventoryEntryProjectId: "project_home",
      inventoryEntryBudgetCategoryId: "cat_original",
      inventoryEntryPriceCents: 10_000,
      inventoryEntryAmountCents: 10_825,
    });
    expect(inventoryItem?.inventoryEntryTransactionId).toBe(inventoryItem?.transactionId);

    await db.doc(`accounts/${TEST_ACCOUNT_ID}/items/item_1`).update({
      projectPriceCents: 50_000,
      taxRatePct: 20,
    });
    const toProject = await callTool("return_items_from_inventory_to_project", {
      itemIds: ["item_1"],
      notes: "8/28 — Returned to original project",
      dryRun: false,
    });
    expect(isError(toProject)).toBe(false);

    const restored = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(restored).toMatchObject({
      projectId: "project_home",
      budgetCategoryId: "cat_original",
      projectPriceCents: 10_000,
    });
    const purchases = await listTransactionsOfType(db, "Purchase");
    const replacement = purchases.find((purchase) => purchase.id !== "project_purchase");
    expect(replacement?.data).toMatchObject({
      projectId: "project_home",
      budgetCategoryId: "cat_original",
      subtotalCents: 10_000,
      amountCents: 10_825,
      itemIds: ["item_1"],
    });
  });

  test("restores the locked project/category/amount and splits categories atomically", async () => {
    await seedProject(db, {
      id: "project_home",
      budgetCategories: [{ id: "cat_furniture" }, { id: "cat_lighting" }],
    });
    await seedTransaction(db, {
      id: "inventory_return",
      type: "Return",
      source: "Business Inventory",
      projectId: "project_home",
      budgetCategoryId: "cat_furniture",
      subtotalCents: 10_000,
      amountCents: 10_825,
      itemIds: ["item_1"],
    });
    await seedTransaction(db, {
      id: "inventory_sale",
      type: "Sale",
      source: "Business Inventory",
      projectId: "project_home",
      budgetCategoryId: "cat_lighting",
      subtotalCents: 8_000,
      amountCents: 8_000,
      itemIds: ["item_2"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: null,
      budgetCategoryId: null,
      transactionId: "inventory_return",
      purchasePriceCents: 4_000,
      projectPriceCents: 77_777,
      taxRatePct: 20,
      inventoryEntryTransactionId: "inventory_return",
      inventoryEntryProjectId: "project_home",
      inventoryEntryBudgetCategoryId: "cat_furniture",
      inventoryEntryPriceCents: 10_000,
      inventoryEntryAmountCents: 10_825,
    });
    await seedItem(db, {
      id: "item_2",
      projectId: null,
      budgetCategoryId: null,
      transactionId: "inventory_sale",
      purchasePriceCents: 8_000,
      projectPriceCents: 88_888,
      taxRatePct: 9.5,
      inventoryEntryTransactionId: "inventory_sale",
      inventoryEntryProjectId: "project_home",
      inventoryEntryBudgetCategoryId: "cat_lighting",
      inventoryEntryPriceCents: 8_000,
      inventoryEntryAmountCents: 8_000,
    });

    const result = await callTool("return_items_from_inventory_to_project", {
      itemIds: ["item_1", "item_2"],
      notes: "8/28 — Returned to original project",
      dryRun: false,
    });
    expect(isError(result)).toBe(false);

    const purchases = (await listTransactionsOfType(db, "Purchase"))
      .sort((a, b) => String(a.data.budgetCategoryId).localeCompare(String(b.data.budgetCategoryId)));
    expect(purchases).toHaveLength(2);
    expect(purchases.map((purchase) => ({
      category: purchase.data.budgetCategoryId,
      subtotal: purchase.data.subtotalCents,
      amount: purchase.data.amountCents,
    }))).toEqual([
      { category: "cat_furniture", subtotal: 10_000, amount: 10_825 },
      { category: "cat_lighting", subtotal: 8_000, amount: 8_000 },
    ]);

    const restored1 = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    const restored2 = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_2`);
    expect(restored1).toMatchObject({
      projectId: "project_home",
      budgetCategoryId: "cat_furniture",
      projectPriceCents: 10_000,
      status: "purchased",
    });
    expect(restored2).toMatchObject({
      projectId: "project_home",
      budgetCategoryId: "cat_lighting",
      projectPriceCents: 8_000,
      status: "purchased",
    });
    expect((await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/inventory_return`))?.itemIds).toEqual([]);
    expect((await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/inventory_sale`))?.itemIds).toEqual([]);
    expect((await listLineageEdges(db)).filter((edge) => edge.data.movementKind === "sold")).toHaveLength(2);

    const payload = responseJson(result);
    expect(payload.projectId).toBe("project_home");
    expect(payload.totals).toMatchObject({ subtotalCents: 18_000, amountCents: 18_825 });
  });

  test("generic Sell rejects a return candidate without writing", async () => {
    await seedProject(db, {
      id: "project_home",
      budgetCategories: [{ id: "cat_original" }, { id: "cat_other" }],
    });
    await seedTransaction(db, {
      id: "inventory_return",
      type: "Return",
      source: "Business Inventory",
      projectId: "project_home",
      budgetCategoryId: "cat_original",
      subtotalCents: 10_000,
      amountCents: 10_825,
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: null,
      budgetCategoryId: null,
      transactionId: "inventory_return",
      purchasePriceCents: 4_000,
      projectPriceCents: 10_000,
      inventoryEntryTransactionId: "inventory_return",
      inventoryEntryProjectId: "project_home",
      inventoryEntryBudgetCategoryId: "cat_original",
      inventoryEntryPriceCents: 10_000,
      inventoryEntryAmountCents: 10_825,
    });

    const result = await callTool("sell_items_from_inventory_to_project", {
      itemIds: ["item_1"],
      destinationProjectId: "project_home",
      budgetCategoryId: "cat_other",
      dryRun: false,
    });
    expect(isError(result)).toBe(true);
    expect(responseJson(result).error.message).toContain("must return to their original project");
    expect(await listTransactionsOfType(db, "Purchase")).toHaveLength(0);
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`)).toMatchObject({
      projectId: null,
      transactionId: "inventory_return",
    });
  });

  test("rejects ambiguous legacy provenance without partial writes", async () => {
    await seedProject(db, {
      id: "project_home",
      budgetCategories: [{ id: "cat_original" }],
    });
    await seedTransaction(db, {
      id: "legacy_return",
      type: "Return",
      source: "Business Inventory",
      projectId: "project_home",
      budgetCategoryId: "cat_original",
      subtotalCents: 20_000,
      amountCents: 21_650,
      itemIds: ["item_1", "item_2"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: null,
      budgetCategoryId: null,
      transactionId: "legacy_return",
      purchasePriceCents: 4_000,
      projectPriceCents: 10_000,
    });

    const result = await callTool("return_items_from_inventory_to_project", {
      itemIds: ["item_1"],
      dryRun: false,
    });
    expect(isError(result)).toBe(true);
    expect(responseJson(result).error.message).toContain("exact provable");
    expect(await listTransactionsOfType(db, "Purchase")).toHaveLength(0);
    expect((await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/legacy_return`))?.itemIds)
      .toEqual(["item_1", "item_2"]);
  });

  test("re-enables the locked original category when its project allocation was removed", async () => {
    await seedProject(db, { id: "project_home" });
    await db.doc(
      `accounts/${TEST_ACCOUNT_ID}/presets/default/budgetCategories/cat_original`
    ).set({ name: "Original", isArchived: false });
    await seedTransaction(db, {
      id: "inventory_return",
      type: "Return",
      source: "Business Inventory",
      projectId: "project_home",
      budgetCategoryId: "cat_original",
      subtotalCents: 10_000,
      amountCents: 10_825,
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: null,
      budgetCategoryId: null,
      transactionId: "inventory_return",
      purchasePriceCents: 4_000,
      inventoryEntryTransactionId: "inventory_return",
      inventoryEntryProjectId: "project_home",
      inventoryEntryBudgetCategoryId: "cat_original",
      inventoryEntryPriceCents: 10_000,
      inventoryEntryAmountCents: 10_825,
    });

    const result = await callTool("return_items_from_inventory_to_project", {
      itemIds: ["item_1"],
      dryRun: false,
    });
    expect(isError(result)).toBe(false);
    expect(await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/projects/project_home/budgetCategories/cat_original`
    )).toMatchObject({ updatedBy: "user_mcp_test" });
  });
});
