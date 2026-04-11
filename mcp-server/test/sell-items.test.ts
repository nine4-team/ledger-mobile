/**
 * Per-batch sale redesign — MCP test matrix (M1-M9).
 *
 * Requires Firestore emulator running on 127.0.0.1:8181:
 *   firebase emulators:start --only firestore --project demo-mcp-test
 */

import { describe, test, expect, beforeAll, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import {
  TEST_ACCOUNT_ID,
  getTestDb,
  makeCapturedServer,
  wipeAccount,
  seedProject,
  seedItem,
  seedTransaction,
  withContext,
  getDocData,
  listTransactionsOfType,
  listLineageEdges,
} from "./helpers.js";
import { registerInventoryOperationTools } from "../src/tools/inventory-operations.js";
import { registerTransactionTools } from "../src/tools/transactions.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const GOLDEN_PATH = resolve(__dirname, "fixtures/sale-transaction.golden.json");
const GOLDEN = JSON.parse(readFileSync(GOLDEN_PATH, "utf8")) as {
  input: {
    items: Array<{
      id: string;
      name: string;
      purchasePriceCents: number;
      projectPriceCents: number;
      taxRatePct: number;
    }>;
    destinationProjectId: string;
    budgetCategoryId: string;
    notes: string;
  };
  expectedSaleTransaction: {
    type: string;
    source: string;
    projectId: string;
    budgetCategoryId: string;
    subtotalCents: number;
    amountCents: number;
    itemIds: string[];
    status: string;
    isComplete: boolean;
    notes: string;
  };
  frozenFields: string[];
};

const db = getTestDb();
const server = makeCapturedServer();

beforeAll(() => {
  // Register all the tools we need to exercise.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  registerInventoryOperationTools(server as any, db);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  registerTransactionTools(server as any, db);
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
  return !!(result as { isError?: boolean })?.isError;
}

function getText(result: unknown): string {
  const r = result as { content?: Array<{ text?: string }> };
  return r?.content?.[0]?.text ?? "";
}

// ─────────────────────────────────────────────────────────────────────────────
// M1 — sell_items happy path
// ─────────────────────────────────────────────────────────────────────────────
describe("sell_items", () => {
  test("M1: happy path creates one Sale transaction with frozen shape", async () => {
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_furnishings", budgetCents: 100000 }],
    });
    await seedItem(db, {
      id: "item_1",
      purchasePriceCents: 10000,
      projectPriceCents: 12000,
      taxRatePct: 8.25,
      projectId: null,
      budgetCategoryId: null,
    });
    await seedItem(db, {
      id: "item_2",
      purchasePriceCents: 5000,
      projectPriceCents: 6000,
      taxRatePct: 8.25,
      projectId: null,
      budgetCategoryId: null,
    });

    const result = await callTool("sell_items", {
      itemIds: ["item_1", "item_2"],
      destinationProjectId: "proj_dest",
      budgetCategoryId: "cat_furnishings",
      notes: "4/9 — M1 happy path",
      dryRun: false,
    });

    expect(isError(result)).toBe(false);

    const sales = await listTransactionsOfType(db, "Sale");
    expect(sales.length).toBe(1);
    const sale = sales[0];

    // Frozen shape fields
    expect(sale.data.type).toBe("Sale");
    expect(sale.data.source).toBe("Business Inventory");
    expect(sale.data.projectId).toBe("proj_dest");
    expect(sale.data.budgetCategoryId).toBe("cat_furnishings");
    expect(sale.data.itemIds).toEqual(["item_1", "item_2"]);
    // amountCents = 12000*1.0825 + 6000*1.0825 = 12990 + 6495 = 19485
    expect(sale.data.amountCents).toBe(19485);
    expect(sale.data.subtotalCents).toBe(18000);
    // No legacy canonical markers
    expect(sale.data.isCanonicalInventorySale).toBeUndefined();
    expect(sale.data.inventorySaleDirection).toBeUndefined();
    // Auto-ID (not SALE_ prefix)
    expect(sale.id.startsWith("SALE_")).toBe(false);

    // Items are updated
    const item1 = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item1?.projectId).toBe("proj_dest");
    expect(item1?.budgetCategoryId).toBe("cat_furnishings");
    expect(item1?.status).toBe("purchased");
    expect(item1?.transactionId).toBe(sale.id);

    // Lineage edges created
    const edges = await listLineageEdges(db);
    expect(edges.length).toBe(2);
    expect(edges.every((e) => e.data.movementKind === "sold")).toBe(true);
    expect(edges.every((e) => e.data.toTransactionId === sale.id)).toBe(true);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // M2 — sell_items dryRun (no writes)
  // ─────────────────────────────────────────────────────────────────────────
  test("M2: dryRun returns plan and commits nothing", async () => {
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedItem(db, {
      id: "item_1",
      purchasePriceCents: 10000,
      projectPriceCents: 12000,
      taxRatePct: 8.25,
      projectId: null,
      budgetCategoryId: null,
    });

    const result = await callTool("sell_items", {
      itemIds: ["item_1"],
      destinationProjectId: "proj_dest",
      budgetCategoryId: "cat_furnishings",
      notes: "4/9 — M2 dryRun",
      dryRun: true,
    });

    expect(isError(result)).toBe(false);
    const text = getText(result);
    const parsed = JSON.parse(text);
    expect(parsed.dryRun).toBe(true);
    expect(parsed.plan.saleTransaction.amountCents).toBe(12990);
    expect(parsed.plan.saleTransaction.projectId).toBe("proj_dest");

    // Nothing committed
    const sales = await listTransactionsOfType(db, "Sale");
    expect(sales.length).toBe(0);
    const item1 = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item1?.projectId).toBeNull();
    expect(item1?.budgetCategoryId).toBeNull();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // M3 — missing budgetCategoryId rejected (via Zod schema)
  // ─────────────────────────────────────────────────────────────────────────
  test("M3: missing budgetCategoryId rejected", async () => {
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: null,
      budgetCategoryId: null,
    });

    // Call without budgetCategoryId. The zod schema requires it, so the
    // MCP SDK would reject at the transport layer. Our captured handlers
    // bypass that — so we test the server-side validateCategoryInProject
    // defense by passing a nonexistent category instead (covered by M4).
    // Here we pass an empty string, which must still hit the validation.
    const result = await callTool("sell_items", {
      itemIds: ["item_1"],
      destinationProjectId: "proj_dest",
      budgetCategoryId: "",
      notes: "4/9 — M3 empty cat",
      dryRun: false,
    });

    expect(isError(result)).toBe(true);

    const sales = await listTransactionsOfType(db, "Sale");
    expect(sales.length).toBe(0);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // M4 — category not enabled in destination project
  // ─────────────────────────────────────────────────────────────────────────
  test("M4: category not enabled in destination rejected", async () => {
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: null,
      budgetCategoryId: null,
    });

    const result = await callTool("sell_items", {
      itemIds: ["item_1"],
      destinationProjectId: "proj_dest",
      budgetCategoryId: "cat_does_not_exist",
      notes: "4/9 — M4 bad cat",
      dryRun: false,
    });

    expect(isError(result)).toBe(true);
    expect(getText(result).toLowerCase()).toContain("not enabled");

    const sales = await listTransactionsOfType(db, "Sale");
    expect(sales.length).toBe(0);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // M5 — 101 items rejected
  // ─────────────────────────────────────────────────────────────────────────
  test("M5: 101 items rejected with batch-size error", async () => {
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    const itemIds = Array.from({ length: 101 }, (_, i) => `item_${i}`);

    const result = await callTool("sell_items", {
      itemIds,
      destinationProjectId: "proj_dest",
      budgetCategoryId: "cat_furnishings",
      notes: "4/9 — M5 101 items",
      dryRun: false,
    });

    // The zod schema `z.array(...).max(100)` rejects at parse time. In our
    // test setup we pass args directly into the handler; zod parsing still
    // runs inside the handler since it's registered with z schemas.
    // Regardless of which layer rejects, it must be an error.
    expect(isError(result)).toBe(true);

    const sales = await listTransactionsOfType(db, "Sale");
    expect(sales.length).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// M6 — return_items with returnTo: "inventory"
// ─────────────────────────────────────────────────────────────────────────────
describe("return_items", () => {
  test("M6: returnTo 'inventory' creates Return tx, wipes item category, sets projectId null", async () => {
    await seedProject(db, {
      id: "proj_source",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    // Item currently in a project, linked to a prior sale transaction.
    await seedTransaction(db, {
      id: "prior_sale",
      type: "Sale",
      source: "Business Inventory",
      projectId: "proj_source",
      budgetCategoryId: "cat_furnishings",
      amountCents: 10825,
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "proj_source",
      budgetCategoryId: "cat_furnishings",
      purchasePriceCents: 10000,
      transactionId: "prior_sale",
    });

    const result = await callTool("return_items", {
      itemIds: ["item_1"],
      returnTo: "inventory",
      notes: "4/9 — M6 return to inventory",
      dryRun: false,
    });

    expect(isError(result)).toBe(false);

    const returns = await listTransactionsOfType(db, "Return");
    expect(returns.length).toBe(1);
    const returnTx = returns[0];
    expect(returnTx.data.source).toBe("Business Inventory");
    expect(returnTx.data.projectId).toBeNull();
    expect(returnTx.data.itemIds).toEqual(["item_1"]);
    expect(returnTx.data.amountCents).toBe(10000);

    const item = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item?.projectId).toBeNull();
    expect(item?.budgetCategoryId).toBeNull();
    expect(item?.status).toBe("returned");
    expect(item?.transactionId).toBe(returnTx.id);

    // Lineage edge (returned)
    const edges = await listLineageEdges(db);
    expect(edges.length).toBe(1);
    expect(edges[0].data.movementKind).toBe("returned");
    expect(edges[0].data.toTransactionId).toBe(returnTx.id);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// M7 — move_items_between_projects
// ─────────────────────────────────────────────────────────────────────────────
describe("move_items_between_projects", () => {
  test("M7: produces one Return + one Sale in a single batch", async () => {
    await seedProject(db, {
      id: "proj_source",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_install" }],
    });
    await seedTransaction(db, {
      id: "src_sale",
      type: "Sale",
      source: "Business Inventory",
      projectId: "proj_source",
      budgetCategoryId: "cat_furnishings",
      amountCents: 10825,
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "proj_source",
      budgetCategoryId: "cat_furnishings",
      purchasePriceCents: 10000,
      projectPriceCents: 12000,
      taxRatePct: 8.25,
      transactionId: "src_sale",
    });

    const result = await callTool("move_items_between_projects", {
      itemIds: ["item_1"],
      destinationProjectId: "proj_dest",
      destinationBudgetCategoryId: "cat_install",
      notes: "4/9 — M7 project move",
      dryRun: false,
    });

    expect(isError(result)).toBe(false);

    const sales = await listTransactionsOfType(db, "Sale");
    const returns = await listTransactionsOfType(db, "Return");
    // src_sale is still there (legacy Sale), plus the new destination Sale.
    expect(sales.length).toBe(2);
    expect(returns.length).toBe(1);

    const newSale = sales.find((s) => s.id !== "src_sale");
    expect(newSale).toBeDefined();
    expect(newSale!.data.projectId).toBe("proj_dest");
    expect(newSale!.data.budgetCategoryId).toBe("cat_install");
    expect(newSale!.data.itemIds).toEqual(["item_1"]);

    const newReturn = returns[0];
    expect(newReturn.data.source).toBe("Business Inventory");
    expect(newReturn.data.projectId).toBeNull();
    expect(newReturn.data.itemIds).toEqual(["item_1"]);

    const item = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item?.projectId).toBe("proj_dest");
    expect(item?.budgetCategoryId).toBe("cat_install");
    expect(item?.transactionId).toBe(newSale!.id);

    // Lineage: one returned edge + one sold edge per item (= 2)
    const edges = await listLineageEdges(db);
    expect(edges.length).toBe(2);
    const kinds = edges.map((e) => e.data.movementKind).sort();
    expect(kinds).toEqual(["returned", "sold"]);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// M8 — update_transaction on a Sale's amountCents rejected (server-side defense)
// ─────────────────────────────────────────────────────────────────────────────
describe("update_transaction", () => {
  test("M8: update_transaction on Sale amountCents rejected", async () => {
    // Create a per-batch Sale (no isCanonicalInventorySale marker).
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedTransaction(db, {
      id: "sale_perbatch",
      type: "Sale",
      source: "Business Inventory",
      projectId: "proj_dest",
      budgetCategoryId: "cat_furnishings",
      amountCents: 10000,
      itemIds: ["item_x"],
    });

    const result = await callTool("update_transaction", {
      transactionId: "sale_perbatch",
      amountCents: 99999,
      notes: "4/9 — M8 mutate attempt",
    });

    expect(isError(result)).toBe(true);
    expect(getText(result).toLowerCase()).toMatch(/frozen|immutable|sale/);

    const tx = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/sale_perbatch`
    );
    expect(tx?.amountCents).toBe(10000); // unchanged
  });

  test("M8b: update_transaction notes on Sale is allowed", async () => {
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedTransaction(db, {
      id: "sale_perbatch_notes",
      type: "Sale",
      source: "Business Inventory",
      projectId: "proj_dest",
      budgetCategoryId: "cat_furnishings",
      amountCents: 10000,
      itemIds: ["item_x"],
    });

    const result = await callTool("update_transaction", {
      transactionId: "sale_perbatch_notes",
      notes: "4/9 — M8b note update",
    });

    expect(isError(result)).toBe(false);
  });

  test("M8c: legacy canonical sale updates allowed", async () => {
    await seedTransaction(db, {
      id: "SALE_legacy_canonical",
      type: "Sale",
      source: "Purchase from Inventory",
      projectId: "proj_legacy",
      budgetCategoryId: "cat_legacy",
      amountCents: 5000,
      itemIds: ["item_legacy"],
      isCanonicalInventorySale: true,
      inventorySaleDirection: "business_to_project",
    });

    // Updating amountCents on a legacy canonical sale is exempt from the
    // per-batch immutability rule (carve-out for backwards compat).
    const result = await callTool("update_transaction", {
      transactionId: "SALE_legacy_canonical",
      amountCents: 6000,
      notes: "4/9 — M8c legacy fix",
    });

    expect(isError(result)).toBe(false);

    const tx = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/SALE_legacy_canonical`
    );
    expect(tx?.amountCents).toBe(6000);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// M9 — Shape parity with golden fixture
// ─────────────────────────────────────────────────────────────────────────────
describe("shape parity", () => {
  test("M9: sell_items output matches sale-transaction.golden.json exactly", async () => {
    const input = GOLDEN.input;
    const expected = GOLDEN.expectedSaleTransaction;

    await seedProject(db, {
      id: input.destinationProjectId,
      budgetCategories: [{ id: input.budgetCategoryId }],
    });
    for (const it of input.items) {
      await seedItem(db, {
        id: it.id,
        name: it.name,
        purchasePriceCents: it.purchasePriceCents,
        projectPriceCents: it.projectPriceCents,
        taxRatePct: it.taxRatePct,
        projectId: null,
        budgetCategoryId: null,
      });
    }

    const result = await callTool("sell_items", {
      itemIds: input.items.map((i) => i.id),
      destinationProjectId: input.destinationProjectId,
      budgetCategoryId: input.budgetCategoryId,
      notes: input.notes,
      dryRun: false,
    });

    expect(isError(result)).toBe(false);

    const sales = await listTransactionsOfType(db, "Sale");
    expect(sales.length).toBe(1);
    const sale = sales[0];

    // Field-by-field match against the golden shape.
    expect(sale.data.type).toBe(expected.type);
    expect(sale.data.source).toBe(expected.source);
    expect(sale.data.projectId).toBe(expected.projectId);
    expect(sale.data.budgetCategoryId).toBe(expected.budgetCategoryId);
    expect(sale.data.subtotalCents).toBe(expected.subtotalCents);
    expect(sale.data.amountCents).toBe(expected.amountCents);
    expect(sale.data.itemIds).toEqual(expected.itemIds);
    expect(sale.data.status).toBe(expected.status);
    expect(sale.data.isComplete).toBe(expected.isComplete);
    expect(sale.data.notes).toBe(expected.notes);

    // No legacy markers leaked in.
    expect(sale.data.isCanonicalInventorySale).toBeUndefined();
    expect(sale.data.inventorySaleDirection).toBeUndefined();
  });
});
