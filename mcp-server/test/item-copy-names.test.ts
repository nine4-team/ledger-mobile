/**
 * Focused emulator regressions for the physical-item copy-name invariant.
 *
 * Requires Firestore emulator running on 127.0.0.1:8181.
 */

import { beforeAll, beforeEach, describe, expect, test } from "vitest";
import { registerCompositeTools } from "../src/tools/composite.js";
import { registerInventoryOperationTools } from "../src/tools/inventory-operations.js";
import { registerItemTools } from "../src/tools/items.js";
import {
  TEST_ACCOUNT_ID,
  getDocData,
  getTestDb,
  makeCapturedServer,
  seedItem,
  seedProject,
  wipeAccount,
  withContext,
} from "./helpers.js";

const db = getTestDb();
const server = makeCapturedServer();

beforeAll(() => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  registerItemTools(server as any, db);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  registerInventoryOperationTools(server as any, db);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  registerCompositeTools(server as any, db);
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

async function allItems(): Promise<Array<Record<string, unknown> & { id: string }>> {
  const snapshot = await db.collection(`accounts/${TEST_ACCOUNT_ID}/items`).get();
  return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

describe("physical item copy names", () => {
  test("expanding a receipt quantity 4 creates four physical documents with byte-identical names", async () => {
    const quantity = 4;
    const sourceName = "  Brass Sconce — Café  ";
    await db
      .doc(`accounts/${TEST_ACCOUNT_ID}/presets/default/budgetCategories/category_items`)
      .set({ name: "Furnishings", metadata: { categoryType: "itemized" } });

    const result = await callTool("create_transaction_with_items", {
      transaction: {
        budgetCategoryId: "category_items",
        amountCents: quantity * 12_500,
        subtotalCents: quantity * 12_500,
        type: "Purchase",
        source: "Receipt Vendor",
      },
      items: Array.from({ length: quantity }, () => ({
        name: sourceName,
        status: "purchased",
        purchasePriceCents: 12_500,
      })),
    });

    expect(isError(result), JSON.stringify(result)).toBe(false);
    const created = await allItems();
    expect(created).toHaveLength(quantity);
    expect(created.map((item) => item.name)).toEqual(Array(quantity).fill(sourceName));
  });

  test("bulk creation accepts repeated identical names", async () => {
    const sourceName = "Oak Dining Chair";
    const result = await callTool("bulk_create_items", {
      items: [
        { name: sourceName, status: "purchased" },
        { name: sourceName, status: "purchased" },
        { name: sourceName, status: "purchased" },
      ],
    });

    expect(isError(result)).toBe(false);
    const created = await allItems();
    expect(created).toHaveLength(3);
    expect(created.every((item) => item.name === sourceName)).toBe(true);
    expect(new Set(created.map((item) => item.id)).size).toBe(3);
  });

  test("inventory-to-project movement preserves identical names", async () => {
    const sourceName = "Linen Counter Stool";
    const createResult = await callTool("bulk_create_items", {
      items: Array.from({ length: 4 }, () => ({
        name: sourceName,
        status: "purchased",
        purchasePriceCents: 20_000,
      })),
    });
    expect(isError(createResult)).toBe(false);

    await seedProject(db, {
      id: "project_destination",
      budgetCategories: [{ id: "category_furnishings" }],
    });
    const created = await allItems();
    const itemIds = created.map((item) => item.id);

    const movementResult = await callTool("sell_items_from_inventory_to_project", {
      itemIds,
      destinationProjectId: "project_destination",
      budgetCategoryId: "category_furnishings",
      dryRun: false,
    });

    expect(isError(movementResult)).toBe(false);
    const moved = await allItems();
    expect(moved.map((item) => item.name)).toEqual(Array(4).fill(sourceName));
    expect(moved.every((item) => item.projectId === "project_destination")).toBe(true);
  });

  test("explicit user-supplied distinct names remain unchanged", async () => {
    const explicitNames = [
      "Chair — Left",
      "Chair — Right",
      "Chair (2)",
      "Chair duplicate — artist's title",
    ];

    const result = await callTool("bulk_create_items", {
      items: explicitNames.map((name) => ({ name, status: "purchased" })),
    });

    expect(isError(result)).toBe(false);
    const createdNames = (await allItems())
      .map((item) => item.name as string)
      .sort();
    expect(createdNames).toEqual([...explicitNames].sort());
  });

  test("this release does not rename existing records automatically", async () => {
    const existingName = "Legacy Lamp — unit 2 of 4";
    await seedItem(db, {
      id: "existing_item",
      name: existingName,
      projectId: null,
      budgetCategoryId: null,
      purchasePriceCents: 1_000,
    });

    const result = await callTool("create_item", {
      name: "New Lamp",
      status: "purchased",
      purchasePriceCents: 1_000,
    });
    expect(isError(result)).toBe(false);

    const existing = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/items/existing_item`
    );
    expect(existing?.name).toBe(existingName);
  });
});
