/**
 * Legacy emulator coverage: per-batch sale redesign — MCP test matrix (M1-M9).
 *
 * Do not use this harness as the default MCP validation path. Normal MCP
 * smoke tests should run against real Firestore with a Firebase Admin
 * service-account key, matching local/deployed MCP behavior.
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
  seedSpace,
  seedItem,
  seedTransaction,
  withContext,
  getDocData,
  listTransactionsOfType,
  listLineageEdges,
} from "./helpers.js";
import { registerInventoryOperationTools } from "../src/tools/inventory-operations.js";
import { registerTransactionTools } from "../src/tools/transactions.js";
import { registerItemTools } from "../src/tools/items.js";

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
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  registerItemTools(server as any, db);
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
    await seedSpace(db, { id: "space_living", projectId: "proj_dest" });
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
      destinationSpaceAssignments: [{ itemId: "item_1", spaceId: "space_living" }],
      notes: "4/9 — M2 dryRun",
      dryRun: true,
    });

    expect(isError(result)).toBe(false);
    const text = getText(result);
    const parsed = JSON.parse(text);
    expect(parsed.dryRun).toBe(true);
    expect(parsed.plan.purchaseTransaction.amountCents).toBe(12990);
    expect(parsed.plan.purchaseTransaction.projectId).toBe("proj_dest");
    expect(parsed.plan.itemUpdates[0].set.spaceId).toBe("space_living");

    // Nothing committed
    const purchases = await listTransactionsOfType(db, "Purchase");
    expect(purchases.length).toBe(0);
    const item1 = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item1?.projectId).toBeNull();
    expect(item1?.budgetCategoryId).toBeNull();
  });

  test("applies validated destination spaces and reports exact final assignments", async () => {
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedSpace(db, { id: "space_living", projectId: "proj_dest" });
    await seedItem(db, {
      id: "item_assigned",
      projectId: null,
      budgetCategoryId: null,
      purchasePriceCents: 1000,
    });
    await seedItem(db, {
      id: "item_unassigned",
      projectId: null,
      budgetCategoryId: null,
      purchasePriceCents: 2000,
      spaceId: "legacy_inventory_space",
    });

    const result = await callTool("sell_items_from_inventory_to_project", {
      itemIds: ["item_assigned", "item_unassigned"],
      destinationProjectId: "proj_dest",
      budgetCategoryId: "cat_furnishings",
      destinationSpaceAssignments: [
        { itemId: "item_assigned", spaceId: "space_living" },
      ],
      dryRun: false,
    });

    expect(isError(result)).toBe(false);
    const assigned = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_assigned`);
    const unassigned = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_unassigned`);
    expect(assigned?.spaceId).toBe("space_living");
    expect(unassigned?.spaceId).toBeNull();

    const response = JSON.parse(getText(result));
    expect(response.spaceAssignmentsApplied).toBe(1);
    expect(response.unassignedItemIds).toEqual(["item_unassigned"]);
    expect(response.finalItems).toContainEqual(expect.objectContaining({
      itemId: "item_assigned",
      spaceId: "space_living",
    }));
  });

  test("rejects a destination space from another project without writing", async () => {
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedProject(db, { id: "proj_other" });
    await seedSpace(db, { id: "space_other", projectId: "proj_other" });
    await seedItem(db, {
      id: "item_1",
      projectId: null,
      budgetCategoryId: null,
      purchasePriceCents: 1000,
    });

    const result = await callTool("sell_items_from_inventory_to_project", {
      itemIds: ["item_1"],
      destinationProjectId: "proj_dest",
      budgetCategoryId: "cat_furnishings",
      destinationSpaceAssignments: [
        { itemId: "item_1", spaceId: "space_other" },
      ],
      dryRun: false,
    });

    expect(isError(result)).toBe(true);
    expect(getText(result)).toContain("does not belong to project proj_dest");
    expect(await listTransactionsOfType(db, "Purchase")).toHaveLength(0);
    const item = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item?.projectId).toBeNull();
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
describe("sell_items_from_project_to_inventory", () => {
  test("project-origin acquisition uses purchase cost even when project price and metadata are higher", async () => {
    await seedProject(db, {
      id: "proj_source",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedTransaction(db, {
      id: "vendor_purchase",
      type: "Purchase",
      source: "Home Depot",
      projectId: "proj_source",
      budgetCategoryId: "cat_furnishings",
      amountCents: 1000,
      itemIds: ["project_item"],
    });
    await seedItem(db, {
      id: "project_item",
      projectId: "proj_source",
      budgetCategoryId: "cat_furnishings",
      purchasePriceCents: 1000,
      projectPriceCents: 1500,
      taxRatePct: 10,
      transactionId: "vendor_purchase",
      source: "Home Depot",
      // Deliberately misleading metadata: the current Purchase is authoritative.
      currentSource: "Business Inventory",
    });

    const args = {
      itemIds: ["project_item"],
      sourceProjectId: "proj_source",
      notes: "Acquire project-origin item",
    };
    const preview = await callTool("sell_items_from_project_to_inventory", {
      ...args,
      dryRun: true,
    });
    expect(isError(preview)).toBe(false);
    const previewPlan = JSON.parse(getText(preview));
    expect(previewPlan.plan.saleTransactions).toEqual([
      {
        type: "Sale",
        source: "Business Inventory",
        projectId: "proj_source",
        budgetCategoryId: "cat_furnishings",
        amountCents: 1000,
        subtotalCents: 1000,
        itemIds: ["project_item"],
      },
    ]);
    expect(previewPlan.plan.credits).toEqual([
      {
        itemId: "project_item",
        name: "project_item",
        priceBasis: "purchasePriceCents",
        purchasePriceCents: 1000,
        creditSubtotalCents: 1000,
        creditAmountCents: 1000,
        origin: "project",
        originEvidence: {
          kind: "currentTransaction",
          transactionId: "vendor_purchase",
          detail: "Current Purchase source 'Home Depot' is not an inventory label.",
        },
      },
    ]);
    expect(previewPlan.totals).toEqual({ amountCents: 1000, subtotalCents: 1000 });

    const result = await callTool("sell_items_from_project_to_inventory", {
      ...args,
      dryRun: false,
    });
    expect(isError(result)).toBe(false);
    const sales = await listTransactionsOfType(db, "Sale");
    expect(sales).toHaveLength(1);
    expect(sales[0].data.amountCents).toBe(1000);
    expect(sales[0].data.subtotalCents).toBe(1000);
  });
});

describe("return_items", () => {
  test("inventory return blocks when origin cannot be resolved safely", async () => {
    await seedProject(db, {
      id: "proj_source",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedItem(db, {
      id: "unresolved_item",
      projectId: "proj_source",
      budgetCategoryId: "cat_furnishings",
      purchasePriceCents: 699,
      projectPriceCents: 965,
    });

    const result = await callTool("return_items", {
      itemIds: ["unresolved_item"],
      returnTo: "inventory",
      dryRun: true,
    });

    expect(isError(result)).toBe(true);
    expect(getText(result)).toContain("could not be resolved safely");
    expect(await listTransactionsOfType(db, "Return")).toHaveLength(0);
  });

  test("vendor return accepts lowercase type and preserves the recorded refund", async () => {
    await seedProject(db, {
      id: "proj_hal",
      budgetCategories: [{ id: "cat_arcade" }],
    });
    await seedTransaction(db, {
      id: "purchase_wayfair",
      type: "Purchase",
      source: "Wayfair",
      projectId: "proj_hal",
      budgetCategoryId: "cat_arcade",
      amountCents: 157236,
      itemIds: ["atari", "nba_jam", "pac_man"],
    });
    await seedTransaction(db, {
      id: "return_wayfair",
      type: "return",
      source: "Wayfair",
      projectId: "proj_hal",
      budgetCategoryId: "cat_arcade",
      amountCents: 149268,
      itemIds: [],
    });
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/transactions/return_wayfair`).update({
      subtotalCents: 145000,
      taxRatePct: 3.25,
      paymentMethod: "Original card",
    });

    const itemFixtures = [
      { id: "atari", name: "Atari Star Wars", purchasePriceCents: 50000 },
      { id: "nba_jam", name: "NBA Jam", purchasePriceCents: 52000 },
      { id: "pac_man", name: "Pac-Man Legacy", purchasePriceCents: 55236 },
    ];
    for (const item of itemFixtures) {
      await seedItem(db, {
        ...item,
        projectId: "proj_hal",
        budgetCategoryId: "cat_arcade",
        transactionId: "purchase_wayfair",
        source: "Wayfair",
      });
    }

    const args = {
      itemIds: itemFixtures.map((item) => item.id),
      returnTo: "vendor",
      returnTransactionId: "return_wayfair",
    };

    const preview = await callTool("return_items", { ...args, dryRun: true });
    expect(isError(preview)).toBe(false);
    expect(
      await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/return_wayfair`)
    ).toMatchObject({ amountCents: 149268, itemIds: [] });

    const result = await callTool("return_items", { ...args, dryRun: false });
    expect(isError(result)).toBe(false);

    const returnTx = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/return_wayfair`
    );
    expect(returnTx).toMatchObject({
      type: "return",
      source: "Wayfair",
      projectId: "proj_hal",
      budgetCategoryId: "cat_arcade",
      amountCents: 149268,
      subtotalCents: 145000,
      taxRatePct: 3.25,
      paymentMethod: "Original card",
    });
    expect(returnTx?.itemIds).toEqual(["atari", "nba_jam", "pac_man"]);

    const purchaseTx = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/purchase_wayfair`
    );
    expect(purchaseTx).toMatchObject({ amountCents: 157236, itemIds: [] });

    for (const item of itemFixtures) {
      const stored = await getDocData(
        db,
        `accounts/${TEST_ACCOUNT_ID}/items/${item.id}`
      );
      expect(stored).toMatchObject({
        status: "returned",
        transactionId: "return_wayfair",
        projectId: "proj_hal",
        budgetCategoryId: "cat_arcade",
        purchasePriceCents: item.purchasePriceCents,
      });
    }

    const edges = await listLineageEdges(db);
    expect(edges).toHaveLength(3);
    expect(edges.every((edge) =>
      edge.data.fromTransactionId === "purchase_wayfair" &&
      edge.data.toTransactionId === "return_wayfair" &&
      edge.data.movementKind === "returned"
    )).toBe(true);
  });

  test("M6: returnTo 'inventory' creates Return tx, wipes item category, sets projectId null", async () => {
    await seedProject(db, {
      id: "proj_source",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    // Item currently in a project, linked to the Purchase that charged the project.
    await seedTransaction(db, {
      id: "prior_sale",
      type: "Purchase",
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
      // Deliberately stale metadata: the current Purchase transaction is authoritative.
      source: "Home Depot",
      currentSource: "Home Depot",
    });

    const args = {
      itemIds: ["item_1"],
      returnTo: "inventory",
      notes: "4/9 — M6 return to inventory",
    };

    const preview = await callTool("return_items", { ...args, dryRun: true });
    expect(isError(preview)).toBe(false);
    const previewPlan = JSON.parse(getText(preview));
    expect(previewPlan.plan.returnTransactions).toEqual([
      {
        type: "Return",
        source: "Business Inventory",
        projectId: "proj_source",
        budgetCategoryId: "cat_furnishings",
        amountCents: 10000,
        subtotalCents: 10000,
        itemIds: ["item_1"],
      },
    ]);
    expect(previewPlan.plan.credits).toEqual([
      {
        itemId: "item_1",
        name: "item_1",
        priceBasis: "projectPriceCents",
        projectPriceCents: 10000,
        creditSubtotalCents: 10000,
        creditAmountCents: 10000,
        origin: "inventory",
        originEvidence: {
          kind: "currentTransaction",
          transactionId: "prior_sale",
          detail: "Current Purchase source 'Business Inventory' is an inventory label.",
        },
      },
    ]);
    expect(previewPlan.totals).toEqual({ amountCents: 10000, subtotalCents: 10000 });
    expect(await listTransactionsOfType(db, "Return")).toHaveLength(0);

    const result = await callTool("return_items", { ...args, dryRun: false });

    expect(isError(result)).toBe(false);

    const returns = await listTransactionsOfType(db, "Return");
    expect(returns.length).toBe(1);
    const returnTx = returns[0];
    expect(returnTx.data.source).toBe("Business Inventory");
    // Return tx lives on the source project (budget impact lands there).
    expect(returnTx.data.projectId).toBe("proj_source");
    expect(returnTx.data.budgetCategoryId).toBe("cat_furnishings");
    expect(returnTx.data.itemIds).toEqual(["item_1"]);
    // Inventory-originated returns reverse the prior project sale value, not
    // the supplier acquisition cost.
    expect(returnTx.data.amountCents).toBe(10000);
    expect(returnTx.data.subtotalCents).toBe(10000);

    const item = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item?.projectId).toBeNull();
    expect(item?.budgetCategoryId).toBeNull();
    expect(item?.status).toBe("purchased");
    expect(item?.transactionId).toBe(returnTx.id);

    // Lineage edge (returned)
    const edges = await listLineageEdges(db);
    expect(edges.length).toBe(1);
    expect(edges[0].data.movementKind).toBe("returned");
    expect(edges[0].data.toTransactionId).toBe(returnTx.id);
  });

  test("inventory return rejects an existing Return transaction", async () => {
    const result = await callTool("return_items", {
      itemIds: ["item_1"],
      returnTo: "inventory",
      returnTransactionId: "existing_return",
      dryRun: false,
    });

    expect(isError(result)).toBe(true);
    expect(getText(result)).toContain("cannot be used when returnTo is 'inventory'");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// M7 — sell_items_from_project_to_project
// ─────────────────────────────────────────────────────────────────────────────
describe("sell_items_from_project_to_project", () => {
  test("M7: project-origin item creates a purchase-cost Sale plus destination Purchase", async () => {
    await seedProject(db, {
      id: "proj_source",
      budgetCategories: [{ id: "cat_furnishings" }],
    });
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_install" }],
    });
    await seedTransaction(db, {
      id: "src_purchase",
      type: "Purchase",
      source: "Wayfair",
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
      transactionId: "src_purchase",
      source: "Wayfair",
      currentSource: "Wayfair",
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
    // The current vendor Purchase proves project origin, so the first hop is a
    // Sale-to-Inventory against proj_source; the second hop is a Purchase
    // against proj_dest. The source vendor Purchase remains and no Return is made.
    expect(sales.length).toBe(1);
    expect(purchases.length).toBe(2);
    expect(returns.length).toBe(0);

    const firstHopSale = sales[0];
    expect(firstHopSale).toBeDefined();
    expect(firstHopSale!.data.projectId).toBe("proj_source");
    expect(firstHopSale!.data.budgetCategoryId).toBe("cat_furnishings");
    expect(firstHopSale!.data.itemIds).toEqual(["item_1"]);
    expect(firstHopSale!.data.amountCents).toBe(10000);
    expect(firstHopSale!.data.subtotalCents).toBe(10000);

    const destPurchase = purchases.find((purchase) => purchase.id !== "src_purchase")!;
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

  test("applies a destination-project space on the atomic two-hop sale", async () => {
    await seedProject(db, {
      id: "proj_source",
      budgetCategories: [{ id: "cat_source" }],
    });
    await seedProject(db, {
      id: "proj_dest",
      budgetCategories: [{ id: "cat_dest" }],
    });
    await seedSpace(db, { id: "space_dest", projectId: "proj_dest" });
    await seedTransaction(db, {
      id: "tx_source",
      type: "Purchase",
      source: "Vendor",
      projectId: "proj_source",
      budgetCategoryId: "cat_source",
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "proj_source",
      budgetCategoryId: "cat_source",
      transactionId: "tx_source",
      purchasePriceCents: 1000,
    });

    const result = await callTool("sell_items_from_project_to_project", {
      itemIds: ["item_1"],
      destinationProjectId: "proj_dest",
      destinationBudgetCategoryId: "cat_dest",
      destinationSpaceAssignments: [
        { itemId: "item_1", spaceId: "space_dest" },
      ],
      dryRun: false,
    });

    expect(isError(result)).toBe(false);
    const item = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item?.projectId).toBe("proj_dest");
    expect(item?.spaceId).toBe("space_dest");
    expect(JSON.parse(getText(result)).finalItems).toContainEqual(expect.objectContaining({
      itemId: "item_1",
      spaceId: "space_dest",
    }));
  });
});

describe("item correction space handling", () => {
  test("requires explicit detachment and returns the prior assignment receipt", async () => {
    await seedProject(db, { id: "proj_source" });
    await seedSpace(db, { id: "space_source", projectId: "proj_source" });
    await seedTransaction(db, {
      id: "tx_source",
      type: "Purchase",
      source: "Vendor",
      projectId: "proj_source",
      budgetCategoryId: "cat_source",
      itemIds: ["item_1"],
    });
    await seedItem(db, {
      id: "item_1",
      projectId: "proj_source",
      budgetCategoryId: "cat_source",
      transactionId: "tx_source",
      spaceId: "space_source",
    });

    const ambiguous = await callTool("bulk_update_items_by_id", {
      updates: [{ id: "item_1", projectId: null }],
    });
    expect(isError(ambiguous)).toBe(true);
    expect(getText(ambiguous)).toContain("spaceId space_source");

    const corrected = await callTool("bulk_update_items_by_id", {
      updates: [{ id: "item_1", projectId: null, spaceId: null }],
    });
    expect(isError(corrected)).toBe(false);
    const response = JSON.parse(getText(corrected));
    expect(response.detachedSpaceAssignments).toEqual([{
      itemId: "item_1",
      spaceId: "space_source",
      spaceProjectId: "proj_source",
      spaceFound: true,
    }]);

    const item = await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/items/item_1`);
    expect(item?.projectId).toBeNull();
    expect(item?.budgetCategoryId).toBeNull();
    expect(item?.spaceId).toBeNull();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// M8 — update_transaction on a Sale's amountCents rejected (server-side defense)
// ─────────────────────────────────────────────────────────────────────────────
describe("update_transaction", () => {
  test("schema accepts explicit null transaction scope", () => {
    const schema = server.schemas.get("update_transaction");
    const projectId = schema?.projectId as { safeParse(value: unknown): { success: boolean } };
    const budgetCategoryId = schema?.budgetCategoryId as { safeParse(value: unknown): { success: boolean } };

    expect(projectId.safeParse(null).success).toBe(true);
    expect(budgetCategoryId.safeParse(null).success).toBe(true);
  });

  test("M7: ordinary Purchase can be corrected to inventory without a movement", async () => {
    await seedItem(db, {
      id: "item_1",
      projectId: "proj_hal",
      budgetCategoryId: "cat_furnishings",
      transactionId: "purchase_misfiled",
      purchasePriceCents: 10000,
    });
    await seedTransaction(db, {
      id: "purchase_misfiled",
      type: "Purchase",
      source: "Vendor",
      projectId: "proj_hal",
      budgetCategoryId: "cat_furnishings",
      amountCents: 10000,
      itemIds: ["item_1"],
      purchaseHandling: "project_reimbursement",
      reimbursementType: "owed-to-company",
    });

    const result = await callTool("update_transaction", {
      transactionId: "purchase_misfiled",
      projectId: null,
    });

    expect(isError(result)).toBe(false);
    const tx = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/purchase_misfiled`
    );
    expect(tx?.projectId).toBeNull();
    expect(tx?.budgetCategoryId).toBeNull();
    expect(tx?.purchaseHandling).toBe("project_reimbursement");
    expect(tx?.reimbursementType).toBe("owed-to-company");
    expect(tx?.itemIds).toEqual([]);

    const item = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/items/item_1`
    );
    expect(item?.projectId).toBe("proj_hal");
    expect(item?.budgetCategoryId).toBe("cat_furnishings");
    expect(item?.transactionId).toBeNull();

    const movementTransactions = [
      ...(await listTransactionsOfType(db, "Sale")),
      ...(await listTransactionsOfType(db, "Return")),
    ];
    expect(movementTransactions).toHaveLength(0);
    const allTransactions = await db
      .collection(`accounts/${TEST_ACCOUNT_ID}/transactions`)
      .get();
    expect(allTransactions.size).toBe(1);
    const correctionEdges = await listLineageEdges(db);
    expect(correctionEdges).toHaveLength(1);
    expect(correctionEdges[0].data).toMatchObject({
      itemId: "item_1",
      fromTransactionId: "purchase_misfiled",
      movementKind: "correction",
    });
  });

  test("M7b: generated inventory Purchase cannot be corrected in place", async () => {
    await seedTransaction(db, {
      id: "inventory_purchase",
      type: "Purchase",
      source: "Business Inventory",
      projectId: "proj_hal",
      budgetCategoryId: "cat_furnishings",
      amountCents: 10000,
      itemIds: ["item_1"],
    });

    const result = await callTool("update_transaction", {
      transactionId: "inventory_purchase",
      projectId: null,
    });

    expect(isError(result)).toBe(true);
    expect(getText(result).toLowerCase()).toMatch(/frozen|immutable/);
  });

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
