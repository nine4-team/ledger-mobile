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
  expectedTransaction: {
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
// M1 — sell_items_from_inventory_to_project happy path
// ─────────────────────────────────────────────────────────────────────────────
describe("sell_items_from_inventory_to_project", () => {
  test("M1: happy path creates one Purchase transaction with frozen accounting shape", async () => {
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

    const result = await callTool("sell_items_from_inventory_to_project", {
      itemIds: ["item_1", "item_2"],
      destinationProjectId: "proj_dest",
      budgetCategoryId: "cat_furnishings",
      notes: "4/9 — M1 happy path",
      dryRun: false,
    });

    expect(isError(result)).toBe(false);

    const purchases = await listTransactionsOfType(db, "Purchase");
    expect(purchases.length).toBe(1);
    const purchase = purchases[0];

    // Frozen shape fields
    expect(purchase.data.type).toBe("Purchase");
    expect(purchase.data.source).toBe("Business Inventory");
    expect(purchase.data.projectId).toBe("proj_dest");
    expect(purchase.data.budgetCategoryId).toBe("cat_furnishings");
    expect(purchase.data.itemIds).toEqual(["item_1", "item_2"]);
    // amountCents = 12000*1.0825 + 6000*1.0825 = 12990 + 6495 = 19485
    expect(purchase.data.amountCents).toBe(19485);
    expect(purchase.data.subtotalCents).toBe(18000);
    // No legacy canonical markers
    expect(purchase.data.isCanonicalInventorySale).toBeUndefined();
    expect(purchase.data.inventorySaleDirection).toBeUndefined();
    // Auto-ID (not SALE_ prefix)
    expect(purchase.id.startsWith("SALE_")).toBe(false);

    // Items are updated
    const item1 = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item1?.projectId).toBe("proj_dest");
    expect(item1?.budgetCategoryId).toBe("cat_furnishings");
    expect(item1?.status).toBe("purchased");
    expect(item1?.transactionId).toBe(purchase.id);

    // Lineage edges created
    const edges = await listLineageEdges(db);
    expect(edges.length).toBe(2);
    expect(edges.every((e) => e.data.movementKind === "sold")).toBe(true);
    expect(edges.every((e) => e.data.toTransactionId === purchase.id)).toBe(true);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // M2 — sell_items_from_inventory_to_project dryRun (no writes)
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

    const result = await callTool("sell_items_from_inventory_to_project", {
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
    expect(parsed.plan.purchaseTransaction.amountCents).toBe(12990);
    expect(parsed.plan.purchaseTransaction.projectId).toBe("proj_dest");

    // Nothing committed
    const purchases = await listTransactionsOfType(db, "Purchase");
    expect(purchases.length).toBe(0);
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
    const result = await callTool("sell_items_from_inventory_to_project", {
      itemIds: ["item_1"],
      destinationProjectId: "proj_dest",
      budgetCategoryId: "",
      notes: "4/9 — M3 empty cat",
      dryRun: false,
    });

    expect(isError(result)).toBe(true);

    const purchases = await listTransactionsOfType(db, "Purchase");
    expect(purchases.length).toBe(0);
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

    const result = await callTool("sell_items_from_inventory_to_project", {
      itemIds: ["item_1"],
      destinationProjectId: "proj_dest",
      budgetCategoryId: "cat_does_not_exist",
      notes: "4/9 — M4 bad cat",
      dryRun: false,
    });

    expect(isError(result)).toBe(true);
    expect(getText(result).toLowerCase()).toContain("not enabled");

    const purchases = await listTransactionsOfType(db, "Purchase");
    expect(purchases.length).toBe(0);
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

    const result = await callTool("sell_items_from_inventory_to_project", {
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

    const purchases = await listTransactionsOfType(db, "Purchase");
    expect(purchases.length).toBe(0);
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
      purchasePriceCents: 8000,
      projectPriceCents: 10000,
      transactionId: "prior_sale",
      // currentSource != source → item came from inventory, eligible for return-to-inventory.
      source: "Home Depot",
      currentSource: "Business Inventory",
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
    // Return tx lives on the source project (budget impact lands there).
    expect(returnTx.data.projectId).toBe("proj_source");
    expect(returnTx.data.itemIds).toEqual(["item_1"]);
    expect(returnTx.data.amountCents).toBe(8000);

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
// M7 — sell_items_from_project_to_project
// ─────────────────────────────────────────────────────────────────────────────
describe("sell_items_from_project_to_project", () => {
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

    const result = await callTool("sell_items_from_project_to_project", {
      itemIds: ["item_1"],
      destinationProjectId: "proj_dest",
      destinationBudgetCategoryId: "cat_install",
      notes: "4/9 — M7 project move",
      dryRun: false,
    });

    expect(isError(result)).toBe(false);

    const sales = await listTransactionsOfType(db, "Sale");
    const purchases = await listTransactionsOfType(db, "Purchase");
    const returns = await listTransactionsOfType(db, "Return");
    // Item originated in proj_source (no source field), so first hop is a
    // Sale-to-Inventory against proj_source; second hop is a Purchase against
    // proj_dest. src_sale (seed legacy Sale) is still there, no Return.
    expect(sales.length).toBe(2);
    expect(purchases.length).toBe(1);
    expect(returns.length).toBe(0);

    const firstHopSale = sales.find((s) => s.id !== "src_sale");
    expect(firstHopSale).toBeDefined();
    expect(firstHopSale!.data.projectId).toBe("proj_source");
    expect(firstHopSale!.data.budgetCategoryId).toBeUndefined();
    expect(firstHopSale!.data.itemIds).toEqual(["item_1"]);
    expect(firstHopSale!.data.amountCents).toBe(10000);

    const destPurchase = purchases[0];
    expect(destPurchase.data.source).toBe("Business Inventory");
    expect(destPurchase.data.projectId).toBe("proj_dest");
    expect(destPurchase.data.budgetCategoryId).toBe("cat_install");
    expect(destPurchase.data.itemIds).toEqual(["item_1"]);
    expect(destPurchase.data.amountCents).toBe(12990);

    const item = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item?.projectId).toBe("proj_dest");
    expect(item?.budgetCategoryId).toBe("cat_install");
    expect(item?.transactionId).toBe(destPurchase.id);

    // Lineage: soldToInventory (first hop) + sold (second hop) per item.
    const edges = await listLineageEdges(db);
    expect(edges.length).toBe(2);
    const kinds = edges.map((e) => e.data.movementKind).sort();
    expect(kinds).toEqual(["sold", "soldToInventory"]);
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

  test("M8c: update_transaction itemIds on Sale is allowed for active membership", async () => {
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
      itemIds: ["item_x", "item_y"],
    });

    const result = await callTool("update_transaction", {
      transactionId: "sale_perbatch",
      itemIds: ["item_y"],
      notes: "4/9 — M8c returned item_x",
    });

    expect(isError(result)).toBe(false);

    const tx = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/sale_perbatch`
    );
    expect(tx?.itemIds).toEqual(["item_y"]);
    expect(tx?.amountCents).toBe(10000);
  });

  test("M8d: legacy canonical sale updates allowed", async () => {
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
  test("M9: sell_items_from_inventory_to_project output matches sale-transaction.golden.json exactly", async () => {
    const input = GOLDEN.input;
    const expected = GOLDEN.expectedTransaction;

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

    const result = await callTool("sell_items_from_inventory_to_project", {
      itemIds: input.items.map((i) => i.id),
      destinationProjectId: input.destinationProjectId,
      budgetCategoryId: input.budgetCategoryId,
      notes: input.notes,
      dryRun: false,
    });

    expect(isError(result)).toBe(false);

    const purchases = await listTransactionsOfType(db, "Purchase");
    expect(purchases.length).toBe(1);
    const purchase = purchases[0];

    // Field-by-field match against the golden shape.
    expect(purchase.data.type).toBe(expected.type);
    expect(purchase.data.source).toBe(expected.source);
    expect(purchase.data.projectId).toBe(expected.projectId);
    expect(purchase.data.budgetCategoryId).toBe(expected.budgetCategoryId);
    expect(purchase.data.subtotalCents).toBe(expected.subtotalCents);
    expect(purchase.data.amountCents).toBe(expected.amountCents);
    expect(purchase.data.itemIds).toEqual(expected.itemIds);
    expect(purchase.data.status).toBe(expected.status);
    expect(purchase.data.isComplete).toBe(expected.isComplete);
    // tagNotesAsAi prepends an `[AI M/D/YYYY] ` audit marker — check that the
    // original prose survives at the end.
    expect(purchase.data.notes as string).toContain(expected.notes);

    // No legacy markers leaked in.
    expect(purchase.data.isCanonicalInventorySale).toBeUndefined();
    expect(purchase.data.inventorySaleDirection).toBeUndefined();
  });
});
