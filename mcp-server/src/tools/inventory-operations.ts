import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { Item, Transaction } from "../types.js";
import { accountCollection, subcollection, getDoc } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { notFound, requireAuditNote, validation } from "../util/errors.js";
import { asToolResponse } from "../util/projections.js";
import { withTelemetry } from "../util/telemetry.js";

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Deterministic canonical sale transaction ID — must match Swift InventoryOperationsService. */
function canonicalSaleId(projectId: string, direction: string, categoryId: string): string {
  return `SALE_${projectId}_${direction}_${categoryId}`;
}

/** Resolve budget category for an item, with fallback chain. */
function resolveCategory(item: Item, override?: string): string {
  return item.budgetCategoryId ?? override ?? "uncategorized";
}

/** Group items by (projectId, resolvedCategoryId) for canonical sale batching. */
function groupForSale(
  items: (Item & { id: string })[],
  override?: string
): Map<string, (Item & { id: string })[]> {
  const groups = new Map<string, (Item & { id: string })[]>();
  for (const item of items) {
    if (!item.projectId) continue; // Can't create project_to_business for inventory items
    const categoryId = resolveCategory(item, override);
    const key = `${item.projectId}::${categoryId}`;
    const group = groups.get(key) ?? [];
    group.push(item);
    groups.set(key, group);
  }
  return groups;
}

/** Compute sale amounts for a group of items: subtotal (pre-tax) and tax-inclusive amount. */
function saleDelta(items: (Item & { id: string })[]): { subtotalCents: number; amountCents: number } {
  let subtotalCents = 0;
  let amountCents = 0;
  for (const item of items) {
    const price = item.purchasePriceCents ?? 0;
    const rate = item.taxRatePct ?? 0;
    subtotalCents += price;
    amountCents += rate > 0 ? Math.round(price * (1 + rate / 100)) : price;
  }
  return { subtotalCents, amountCents };
}

/** Count items missing taxRatePct and build a warning string if any. */
function missingTaxWarning(items: (Item & { id: string })[]): string {
  const missing = items.filter((i) => i.taxRatePct == null);
  if (missing.length === 0) return "";
  return `\n⚠ ${missing.length} of ${items.length} item(s) have no taxRatePct — amountCents may undercount actual cost. Use update_item to set taxRatePct on: ${missing.map((i) => i.id).join(", ")}`;
}

// ── Tool Registration ────────────────────────────────────────────────────────

export function registerInventoryOperationTools(server: McpServer, db: Firestore) {
  // ── sell_items ──────────────────────────────────────────────────────────────
  server.tool(
    "sell_items",
    "[destructive] Move items between scopes (project ↔ business inventory) via canonical sale transactions. " +
      "Creates deterministic sale transaction IDs, lineage edges, and updates item fields atomically. " +
      "Use direction 'to_business' to move project items to inventory, 'to_project' to move items into a project. " +
      "Project-to-project moves are handled by 'to_project' with a two-hop model (source → inventory → destination). " +
      "Set dryRun: true to preview the plan without writing. " +
      "IMPORTANT: When selling items to a project (direction 'to_project'), you MUST ask the user which budget " +
      "category this sale should be filed under BEFORE calling this tool. Use get_project_budget_categories on the " +
      "destination project to list the available categories, present them to the user, and pass their choice as " +
      "overrideCategoryId. Do not skip this step or assume a default — the app always requires the user to pick a category.",
    {
      itemIds: z.array(z.string()).min(1).describe("Item document IDs to sell"),
      direction: z.enum(["to_business", "to_project"]).describe(
        "Sale direction: 'to_business' moves items FROM a project TO business inventory, " +
          "'to_project' moves items INTO a project (from inventory or another project)"
      ),
      destinationProjectId: z.string().optional().describe(
        "Destination project ID — required when direction is 'to_project'"
      ),
      overrideCategoryId: z.string().optional().describe(
        "Budget category for the sale. When direction is 'to_project', this is required — " +
          "always ask the user to choose from the destination project's budget categories before calling this tool"
      ),
      notes: z.string().describe(
        "REQUIRED dated audit note explaining the move — e.g. '4/6 — Moved 3 fixtures from Witzenman to inventory, client returned them'."
      ),
      dryRun: z.boolean().default(false).describe(
        "If true, compute and return the sale plan (transactions, item updates, lineage edges) without writing. Use to preview before committing."
      ),
    },
    withTelemetry("sell_items", async ({ itemIds, direction, destinationProjectId, overrideCategoryId, notes, dryRun }) => {
      const noteError = requireAuditNote(notes, "sell_items");
      if (noteError) return noteError;

      // Validate direction-specific requirements
      if (direction === "to_project" && !destinationProjectId) {
        return validation(
          "destinationProjectId is required when direction is 'to_project'",
          "Pass the target project's ID as destinationProjectId."
        );
      }

      // Fetch all items
      const items: (Item & { id: string })[] = [];
      const missing: string[] = [];
      for (const itemId of itemIds) {
        const item = await getDoc<Item>(db, "items", itemId);
        if (!item) {
          missing.push(itemId);
        } else {
          items.push(item);
        }
      }
      if (missing.length > 0) {
        return notFound("Items", missing.join(", "), "get_items");
      }

      if (dryRun) {
        return asToolResponse({
          dryRun: true,
          direction,
          destinationProjectId: destinationProjectId ?? null,
          overrideCategoryId: overrideCategoryId ?? null,
          plan: planSale(items, direction, destinationProjectId, overrideCategoryId),
          warning:
            items.filter((i) => i.taxRatePct == null).length > 0
              ? `${items.filter((i) => i.taxRatePct == null).length} item(s) missing taxRatePct — amountCents will undercount.`
              : null,
        });
      }

      if (direction === "to_business") {
        return await sellToBusiness(db, items, overrideCategoryId, notes);
      } else {
        return await sellToProject(db, items, destinationProjectId!, overrideCategoryId, notes);
      }
    })
  );

  // ── return_items ────────────────────────────────────────────────────────────
  server.tool(
    "return_items",
    "[destructive] Process item returns atomically: updates item status to 'returned', moves items from source " +
      "transaction to the return transaction, and creates lineage edges. The return transaction must " +
      "already exist with type 'Return'. Set dryRun: true to preview the plan without writing.",
    {
      itemIds: z.array(z.string()).min(1).describe("Item document IDs to return"),
      returnTransactionId: z.string().describe("Existing return transaction ID to move items to"),
      notes: z.string().describe(
        "REQUIRED dated audit note — e.g. '4/6 — Returned 2 fixtures (wrong finish)'."
      ),
      dryRun: z.boolean().default(false).describe(
        "If true, return the plan without writing."
      ),
    },
    withTelemetry("return_items", async ({ itemIds, returnTransactionId, notes, dryRun }) => {
      const noteError = requireAuditNote(notes, "return_items");
      if (noteError) return noteError;

      // Validate return transaction exists and is type Return
      const returnTx = await getDoc<Transaction>(db, "transactions", returnTransactionId);
      if (!returnTx) return notFound("Return transaction", returnTransactionId);
      if (returnTx.type !== "Return") {
        return validation(
          `Transaction ${returnTransactionId} is type '${returnTx.type}', not 'Return'.`,
          "Create a transaction with type 'Return' first, then call return_items with its ID."
        );
      }

      // Fetch all items
      const items: (Item & { id: string })[] = [];
      const missing: string[] = [];
      for (const itemId of itemIds) {
        const item = await getDoc<Item>(db, "items", itemId);
        if (!item) {
          missing.push(itemId);
        } else {
          items.push(item);
        }
      }
      if (missing.length > 0) {
        return notFound("Items", missing.join(", "), "get_items");
      }

      if (dryRun) {
        return asToolResponse({
          dryRun: true,
          returnTransactionId,
          plan: {
            itemUpdates: items.map((i) => ({
              itemId: i.id,
              name: i.name ?? null,
              from: { transactionId: i.transactionId ?? null, status: i.status ?? null },
              to: { transactionId: returnTransactionId, status: "returned" },
            })),
            lineageEdges: items.length,
          },
        });
      }

      return await returnItems(db, items, returnTransactionId);
    })
  );
}

// ── dry-run planner (pure) ──────────────────────────────────────────────────

export function planSale(
  items: (Item & { id: string })[],
  direction: "to_business" | "to_project",
  destinationProjectId: string | undefined,
  overrideCategoryId: string | undefined
) {
  const canonical = (projectId: string, dir: string, catId: string) =>
    `SALE_${projectId}_${dir}_${catId}`;
  const resolveCat = (i: Item) => i.budgetCategoryId ?? overrideCategoryId ?? "uncategorized";

  const saleTransactions: Array<{
    id: string;
    projectId: string;
    direction: string;
    budgetCategoryId: string;
    itemIds: string[];
    subtotalCents: number;
    amountCents: number;
  }> = [];
  const itemUpdates: Array<Record<string, unknown>> = [];
  let edgeCount = 0;

  const upsert = (
    id: string,
    projectId: string,
    dir: string,
    catId: string,
    itemId: string,
    subtotal: number,
    amount: number
  ) => {
    let existing = saleTransactions.find((s) => s.id === id);
    if (!existing) {
      existing = {
        id,
        projectId,
        direction: dir,
        budgetCategoryId: catId,
        itemIds: [],
        subtotalCents: 0,
        amountCents: 0,
      };
      saleTransactions.push(existing);
    }
    existing.itemIds.push(itemId);
    existing.subtotalCents += subtotal;
    existing.amountCents += amount;
  };

  for (const item of items) {
    const catId = resolveCat(item);
    const subtotal = item.purchasePriceCents ?? 0;
    const rate = item.taxRatePct ?? 0;
    const amount = rate > 0 ? Math.round(subtotal * (1 + rate / 100)) : subtotal;

    if (direction === "to_business") {
      if (!item.projectId) continue;
      const id = canonical(item.projectId, "project_to_business", catId);
      upsert(id, item.projectId, "project_to_business", catId, item.id, subtotal, amount);
      itemUpdates.push({
        itemId: item.id,
        set: { status: "purchased", transactionId: id },
        clear: ["projectId", "spaceId"],
      });
      edgeCount++;
    } else {
      const dstCatId = catId;
      if (item.projectId) {
        const srcId = canonical(item.projectId, "project_to_business", catId);
        upsert(srcId, item.projectId, "project_to_business", catId, item.id, subtotal, amount);
      }
      const dstId = canonical(destinationProjectId!, "business_to_project", dstCatId);
      upsert(dstId, destinationProjectId!, "business_to_project", dstCatId, item.id, subtotal, amount);
      itemUpdates.push({
        itemId: item.id,
        set: { projectId: destinationProjectId, transactionId: dstId },
        clear: ["spaceId"],
      });
      edgeCount++;
    }
  }

  return { saleTransactions, itemUpdates, lineageEdges: edgeCount };
}

// ── sell_items: to_business ─────────────────────────────────────────────────

async function sellToBusiness(
  db: Firestore,
  items: (Item & { id: string })[],
  overrideCategoryId?: string,
  notes?: string
) {
  // Validate all items have a projectId
  const noProject = items.filter((i) => !i.projectId);
  if (noProject.length > 0) {
    return {
      content: [{
        type: "text" as const,
        text: `Cannot sell to business: ${noProject.length} item(s) have no projectId (already in inventory): ${noProject.map((i) => i.id).join(", ")}`,
      }],
      isError: true,
    };
  }

  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");

  // Group items by (projectId, resolvedCategoryId)
  const groups = groupForSale(items, overrideCategoryId);
  const saleIds: string[] = [];

  for (const [key, groupItems] of groups) {
    const [projectId, categoryId] = key.split("::");
    const saleId = canonicalSaleId(projectId, "project_to_business", categoryId);
    saleIds.push(saleId);
    const { subtotalCents, amountCents } = saleDelta(groupItems);

    // Create or update canonical sale transaction (no taxRatePct — rate lives on items)
    batch.set(
      txCol.doc(saleId),
      {
        projectId,
        type: "Sale",
        isCanonicalInventorySale: true,
        inventorySaleDirection: "project_to_business",
        budgetCategoryId: categoryId,
        itemIds: FieldValue.arrayUnion(...groupItems.map((i) => i.id)),
        subtotalCents: FieldValue.increment(subtotalCents),
        amountCents: FieldValue.increment(amountCents),
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        ...(notes ? { notes } : {}),
      },
      { merge: true }
    );
  }

  for (const item of items) {
    const categoryId = resolveCategory(item, overrideCategoryId);
    const saleId = canonicalSaleId(item.projectId!, "project_to_business", categoryId);

    // Update item: clear projectId/spaceId, set status and link to canonical sale
    batch.update(itemsCol.doc(item.id), {
      projectId: FieldValue.delete(),
      spaceId: FieldValue.delete(),
      status: "purchased",
      transactionId: saleId,
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Remove item from source transaction's itemIds
    if (item.transactionId) {
      batch.update(txCol.doc(item.transactionId), {
        itemIds: FieldValue.arrayRemove(item.id),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    // Lineage edge
    const edge: Record<string, unknown> = {
      itemId: item.id,
      fromProjectId: item.projectId,
      toTransactionId: saleId,
      movementKind: "sold",
      source: "mcp",
      createdAt: FieldValue.serverTimestamp(),
    };
    if (item.transactionId) edge.fromTransactionId = item.transactionId;
    batch.set(edgesCol.doc(), edge);
  }

  await batch.commit();

  const uniqueSales = [...new Set(saleIds)];
  return {
    content: [{
      type: "text" as const,
      text: `Sold ${items.length} item(s) to business inventory.\n` +
        `Canonical sale transaction(s): ${uniqueSales.join(", ")}\n` +
        `Items: ${items.map((i) => `${i.id} (${i.name ?? "unnamed"}, ${formatCents(i.purchasePriceCents)})`).join(", ")}` +
        missingTaxWarning(items),
    }],
  };
}

// ── sell_items: to_project ──────────────────────────────────────────────────

async function sellToProject(
  db: Firestore,
  items: (Item & { id: string })[],
  destinationProjectId: string,
  overrideCategoryId?: string,
  notes?: string
) {
  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");

  const saleIds: string[] = [];
  const destinationCategoryIds = new Set<string>();

  for (const item of items) {
    const srcCatId = resolveCategory(item, overrideCategoryId);
    const dstCatId = resolveCategory(item, overrideCategoryId);
    const subtotal = item.purchasePriceCents ?? 0;
    const itemTaxRate = item.taxRatePct ?? 0;
    const amount = itemTaxRate > 0
      ? Math.round(subtotal * (1 + itemTaxRate / 100))
      : subtotal;

    destinationCategoryIds.add(dstCatId);

    // Hop 1: source project → business inventory (only if item was in a project)
    if (item.projectId) {
      const srcSaleId = canonicalSaleId(item.projectId, "project_to_business", srcCatId);
      saleIds.push(srcSaleId);

      batch.set(
        txCol.doc(srcSaleId),
        {
          projectId: item.projectId,
          type: "Sale",
          isCanonicalInventorySale: true,
          inventorySaleDirection: "project_to_business",
          budgetCategoryId: srcCatId,
          itemIds: FieldValue.arrayUnion(item.id),
          subtotalCents: FieldValue.increment(subtotal),
          amountCents: FieldValue.increment(amount),
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          ...(notes ? { notes } : {}),
        },
        { merge: true }
      );
    }

    // Hop 2: business inventory → destination project
    const dstSaleId = canonicalSaleId(destinationProjectId, "business_to_project", dstCatId);
    saleIds.push(dstSaleId);

    batch.set(
      txCol.doc(dstSaleId),
      {
        projectId: destinationProjectId,
        type: "Sale",
        isCanonicalInventorySale: true,
        inventorySaleDirection: "business_to_project",
        budgetCategoryId: dstCatId,
        itemIds: FieldValue.arrayUnion(item.id),
        subtotalCents: FieldValue.increment(subtotal),
        amountCents: FieldValue.increment(amount),
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        ...(notes ? { notes } : {}),
      },
      { merge: true }
    );

    // Update item: move to destination, link to destination canonical sale
    const itemUpdate: Record<string, unknown> = {
      projectId: destinationProjectId,
      spaceId: FieldValue.delete(),
      transactionId: dstSaleId,
      updatedAt: FieldValue.serverTimestamp(),
    };
    // Backfill projectPriceCents for legacy items missing it
    if (item.projectPriceCents == null && item.purchasePriceCents != null) {
      itemUpdate.projectPriceCents = item.purchasePriceCents;
    }
    batch.update(itemsCol.doc(item.id), itemUpdate);

    // Remove item from source transaction's itemIds
    if (item.transactionId) {
      batch.update(txCol.doc(item.transactionId), {
        itemIds: FieldValue.arrayRemove(item.id),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    // Lineage edge
    const edge: Record<string, unknown> = {
      itemId: item.id,
      toProjectId: destinationProjectId,
      toTransactionId: dstSaleId,
      movementKind: "sold",
      source: "mcp",
      createdAt: FieldValue.serverTimestamp(),
    };
    if (item.projectId) edge.fromProjectId = item.projectId;
    if (item.transactionId) edge.fromTransactionId = item.transactionId;
    batch.set(edgesCol.doc(), edge);
  }

  // Auto-enable budget categories in destination project
  for (const catId of destinationCategoryIds) {
    if (catId === "uncategorized") continue;
    const catRef = db.doc(
      `${accountCollection(db, "projects").path}/${destinationProjectId}/budgetCategories/${catId}`
    );
    batch.set(catRef, { updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  }

  await batch.commit();

  const uniqueSales = [...new Set(saleIds)];
  return {
    content: [{
      type: "text" as const,
      text: `Sold ${items.length} item(s) to project ${destinationProjectId}.\n` +
        `Canonical sale transaction(s): ${uniqueSales.join(", ")}\n` +
        `Items: ${items.map((i) => `${i.id} (${i.name ?? "unnamed"}, ${formatCents(i.purchasePriceCents)})`).join(", ")}` +
        missingTaxWarning(items),
    }],
  };
}

// ── return_items ─────────────────────────────────────────────────────────────

async function returnItems(
  db: Firestore,
  items: (Item & { id: string })[],
  returnTransactionId: string
) {
  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");

  for (const item of items) {
    // Update item: status → returned, link to return transaction
    batch.update(itemsCol.doc(item.id), {
      status: "returned",
      transactionId: returnTransactionId,
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Remove item from source transaction's itemIds
    if (item.transactionId && item.transactionId !== returnTransactionId) {
      batch.update(txCol.doc(item.transactionId), {
        itemIds: FieldValue.arrayRemove(item.id),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    // Add item to return transaction's itemIds
    batch.update(txCol.doc(returnTransactionId), {
      itemIds: FieldValue.arrayUnion(item.id),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Lineage edge
    const edge: Record<string, unknown> = {
      itemId: item.id,
      toTransactionId: returnTransactionId,
      movementKind: "returned",
      source: "mcp",
      createdAt: FieldValue.serverTimestamp(),
    };
    if (item.transactionId) edge.fromTransactionId = item.transactionId;
    if (item.projectId) {
      edge.fromProjectId = item.projectId;
      edge.toProjectId = item.projectId; // Returns stay in same project
    }
    batch.set(edgesCol.doc(), edge);
  }

  await batch.commit();

  return {
    content: [{
      type: "text" as const,
      text: `Returned ${items.length} item(s) to transaction ${returnTransactionId}.\n` +
        `Items: ${items.map((i) => `${i.id} (${i.name ?? "unnamed"}, ${formatCents(i.purchasePriceCents)})`).join(", ")}`,
    }],
  };
}
