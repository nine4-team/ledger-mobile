import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { Item, Transaction } from "../types.js";
import { accountCollection, subcollection, getDoc } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { notFound, requireAuditNote, validation } from "../util/errors.js";
import { asToolResponse } from "../util/projections.js";
import { withTelemetry } from "../util/telemetry.js";
import { getUid } from "../context.js";

// ─────────────────────────────────────────────────────────────────────────────
// Per-batch sale redesign — this file is the MCP-side implementation of the
// sale-transactions spec at docs/specs/sale-transactions.md.
//
// Key invariants (enforced here + by Firestore rules + mirrored on iOS):
//   • Each sell action creates exactly ONE new Sale transaction (auto-ID).
//   • A Sale transaction's shape fields (amountCents, itemIds, budgetCategoryId,
//     type, source, projectId) are frozen at creation and never mutated.
//   • Sales only go business → project. Returning items to inventory is a
//     Return transaction with source: "Business Inventory", NOT a sale.
//   • Items in business inventory (projectId == null) have
//     budgetCategoryId == null. Enforced by items.ts + bulk-getters.ts.
//   • Batch cap: 100 items per operation (Firestore limit is 500 docs per
//     batch; 100 items keeps us well under with item updates + txn writes +
//     lineage edges + source-transaction arrayRemoves).
// ─────────────────────────────────────────────────────────────────────────────

const MAX_BATCH_ITEMS = 100;

/** Resolve a frozen amount snapshot for a batch of items. */
function computeBatchTotals(items: (Item & { id: string })[]): {
  subtotalCents: number;
  amountCents: number;
  missingTax: string[];
} {
  let subtotalCents = 0;
  let amountCents = 0;
  const missingTax: string[] = [];
  for (const item of items) {
    const price = item.projectPriceCents ?? item.purchasePriceCents ?? 0;
    const rate = item.taxRatePct ?? 0;
    subtotalCents += price;
    amountCents += rate > 0 ? Math.round(price * (1 + rate / 100)) : price;
    if (item.taxRatePct == null) missingTax.push(item.id);
  }
  return { subtotalCents, amountCents, missingTax };
}

/** Build a warning string if any items lack a tax rate. */
function missingTaxWarning(missingTax: string[], total: number): string {
  if (missingTax.length === 0) return "";
  return (
    `\n⚠ ${missingTax.length} of ${total} item(s) have no taxRatePct — ` +
    `amountCents may undercount actual cost. Use update_item to set taxRatePct on: ` +
    missingTax.join(", ")
  );
}

/**
 * Validate that a budget category exists and is enabled in a project.
 * Returns null if valid, or an error tool-response if not.
 */
async function validateCategoryInProject(
  db: Firestore,
  projectId: string,
  budgetCategoryId: string
) {
  if (!budgetCategoryId) {
    return validation(
      "budgetCategoryId is required and cannot be empty.",
      "Ask the user to pick from get_project_budget_categories."
    );
  }
  const catRef = subcollection(db, "projects", projectId, "budgetCategories").doc(
    budgetCategoryId
  );
  const snap = await catRef.get();
  if (!snap.exists) {
    return validation(
      `Budget category ${budgetCategoryId} is not enabled in project ${projectId}.`,
      `Call enable_category_for_project first, or pick a category from get_project_budget_categories.`
    );
  }
  return null;
}

// ── Tool Registration ────────────────────────────────────────────────────────

export function registerInventoryOperationTools(server: McpServer, db: Firestore) {
  // ── sell_items ──────────────────────────────────────────────────────────────
  server.tool(
    "sell_items",
    "[destructive] Sell items from business inventory into a project. Creates ONE new immutable Sale transaction " +
      "per call — no long-lived aggregators. The Sale transaction's shape (amountCents, itemIds, " +
      "budgetCategoryId, projectId, type, source) is frozen at creation; it can never be mutated afterwards. " +
      "Cap: 100 items per call.\n\n" +
      "IMPORTANT: You MUST ask the user which budget category this sale should be filed under BEFORE calling " +
      "this tool. Use get_project_budget_categories on the destination project to list available categories, " +
      "present them to the user, and pass their choice as budgetCategoryId. One category applies to the whole " +
      "batch — if the user wants mixed categories, call sell_items once per category.\n\n" +
      "For project→project moves (items currently in a source project), use move_items_between_projects instead. " +
      "For moving items BACK to inventory, use return_items with returnTo: 'inventory'.",
    {
      itemIds: z
        .array(z.string())
        .min(1)
        .max(MAX_BATCH_ITEMS)
        .describe(`Item document IDs to sell (max ${MAX_BATCH_ITEMS} per call)`),
      destinationProjectId: z.string().describe("Destination project ID"),
      budgetCategoryId: z
        .string()
        .describe(
          "Budget category for the sale — required. Always ask the user to pick from " +
            "get_project_budget_categories before calling this tool. Applies to the whole batch."
        ),
      notes: z
        .string()
        .describe(
          "REQUIRED dated audit note — e.g. '4/6 — sold 5 fixtures from inventory into Witzenman, client approved selections'"
        ),
      dryRun: z
        .boolean()
        .default(false)
        .describe(
          "If true, compute and return the sale plan without writing anything. Use to preview before committing."
        ),
    },
    withTelemetry(
      "sell_items",
      async ({ itemIds, destinationProjectId, budgetCategoryId, notes, dryRun }) => {
        const noteError = requireAuditNote(notes, "sell_items");
        if (noteError) return noteError;

        // Fetch all items
        const items: (Item & { id: string })[] = [];
        const missing: string[] = [];
        for (const itemId of itemIds) {
          const item = await getDoc<Item>(db, "items", itemId);
          if (!item) missing.push(itemId);
          else items.push(item);
        }
        if (missing.length > 0) {
          return notFound("Items", missing.join(", "), "get_items");
        }

        // Defense-in-depth: enforce category is enabled in destination project.
        const catError = await validateCategoryInProject(
          db,
          destinationProjectId,
          budgetCategoryId
        );
        if (catError) return catError;

        const { subtotalCents, amountCents, missingTax } = computeBatchTotals(items);

        if (dryRun) {
          return asToolResponse({
            dryRun: true,
            plan: {
              saleTransaction: {
                type: "Sale" as const,
                source: "Business Inventory" as const,
                projectId: destinationProjectId,
                budgetCategoryId,
                amountCents,
                subtotalCents,
                itemIds: items.map((i) => i.id),
              },
              itemUpdates: items.map((i) => ({
                itemId: i.id,
                set: {
                  projectId: destinationProjectId,
                  budgetCategoryId,
                  status: "purchased",
                },
                note: "transactionId will be set to the new Sale doc ID once committed.",
              })),
              sourceTransactionArrayRemoves: [
                ...new Set(items.map((i) => i.transactionId).filter(Boolean) as string[]),
              ],
              lineageEdges: items.length,
            },
            warning:
              missingTax.length > 0
                ? `${missingTax.length} item(s) missing taxRatePct — amountCents will undercount.`
                : null,
          });
        }

        return await commitSellItems(db, items, destinationProjectId, budgetCategoryId, {
          subtotalCents,
          amountCents,
          missingTax,
          notes,
        });
      }
    )
  );

  // ── return_items ────────────────────────────────────────────────────────────
  server.tool(
    "return_items",
    "[destructive] Return items, either to a vendor or back to business inventory.\n\n" +
      "• returnTo: 'vendor' — attaches items to an existing vendor Return transaction. You must create the " +
      "Return transaction first via create_transaction (type: 'Return'), then pass its ID as returnTransactionId.\n\n" +
      "• returnTo: 'inventory' — moves items from their current project back to business inventory. Creates a " +
      "new Return transaction with source: 'Business Inventory' (or reuses one if returnTransactionId is " +
      "provided). Items have their budgetCategoryId wiped (inventory items have no category) and projectId " +
      "set to null.\n\n" +
      "Cap: 100 items per call. Set dryRun: true to preview the plan.",
    {
      itemIds: z
        .array(z.string())
        .min(1)
        .max(MAX_BATCH_ITEMS)
        .describe(`Item document IDs to return (max ${MAX_BATCH_ITEMS} per call)`),
      returnTo: z
        .enum(["vendor", "inventory"])
        .describe("Where the items are going: 'vendor' (attach to an existing Return tx) or 'inventory' (new or reused Return tx with source: 'Business Inventory')"),
      returnTransactionId: z
        .string()
        .optional()
        .describe(
          "When returnTo is 'vendor': REQUIRED existing Return transaction ID. " +
            "When returnTo is 'inventory': OPTIONAL existing Return transaction ID to append to; if omitted, a new one is created."
        ),
      notes: z
        .string()
        .describe("REQUIRED dated audit note — e.g. '4/6 — returned 2 fixtures (wrong finish)'"),
      dryRun: z.boolean().default(false).describe("If true, return the plan without writing."),
    },
    withTelemetry(
      "return_items",
      async ({ itemIds, returnTo, returnTransactionId, notes, dryRun }) => {
        const noteError = requireAuditNote(notes, "return_items");
        if (noteError) return noteError;

        // Validate vendor path needs an explicit return transaction
        if (returnTo === "vendor" && !returnTransactionId) {
          return validation(
            "returnTransactionId is required when returnTo is 'vendor'.",
            "Create a vendor Return transaction first (type: 'Return'), then pass its ID as returnTransactionId."
          );
        }

        // If caller provided a returnTransactionId, validate it
        let existingReturnTx: (Transaction & { id: string }) | null = null;
        if (returnTransactionId) {
          existingReturnTx = await getDoc<Transaction>(db, "transactions", returnTransactionId);
          if (!existingReturnTx) return notFound("Return transaction", returnTransactionId);
          if (existingReturnTx.type !== "Return") {
            return validation(
              `Transaction ${returnTransactionId} is type '${existingReturnTx.type}', not 'Return'.`,
              "Pass an existing Return transaction, or omit returnTransactionId to create a new one (only valid for returnTo: 'inventory')."
            );
          }
        }

        // Fetch all items
        const items: (Item & { id: string })[] = [];
        const missing: string[] = [];
        for (const itemId of itemIds) {
          const item = await getDoc<Item>(db, "items", itemId);
          if (!item) missing.push(itemId);
          else items.push(item);
        }
        if (missing.length > 0) {
          return notFound("Items", missing.join(", "), "get_items");
        }

        if (dryRun) {
          return asToolResponse({
            dryRun: true,
            returnTo,
            existingReturnTransactionId: existingReturnTx?.id ?? null,
            willCreateNewReturnTx: returnTo === "inventory" && !existingReturnTx,
            plan: {
              itemUpdates: items.map((i) => ({
                itemId: i.id,
                name: i.name ?? null,
                set:
                  returnTo === "inventory"
                    ? {
                        status: "returned",
                        projectId: null,
                        budgetCategoryId: null,
                      }
                    : { status: "returned" },
                from: { transactionId: i.transactionId ?? null },
              })),
              lineageEdges: items.length,
            },
          });
        }

        if (returnTo === "inventory") {
          return await commitReturnToInventory(db, items, existingReturnTx, notes);
        }
        return await commitReturnToVendor(db, items, existingReturnTx!, notes);
      }
    )
  );

  // ── move_items_between_projects ────────────────────────────────────────────
  server.tool(
    "move_items_between_projects",
    "[destructive] Move items from one project directly to another in a single atomic batch. Under the hood " +
      "this is a return-to-inventory (wiping the source project's category) plus a sell-into-destination " +
      "(resolving the new category at the time of the move). Both writes commit together.\n\n" +
      "Cap: 100 items per call. One destination category applies to the whole batch.\n\n" +
      "IMPORTANT: Ask the user which budget category to use in the destination before calling this tool.",
    {
      itemIds: z
        .array(z.string())
        .min(1)
        .max(MAX_BATCH_ITEMS)
        .describe(`Item document IDs to move (max ${MAX_BATCH_ITEMS} per call). All items must currently be in the same source project.`),
      destinationProjectId: z.string().describe("Destination project ID"),
      destinationBudgetCategoryId: z
        .string()
        .describe(
          "Budget category in the destination project — required, applies to the whole batch. Ask the user."
        ),
      notes: z
        .string()
        .describe(
          "REQUIRED dated audit note — e.g. '4/6 — moved 3 sconces from Witzenman to Bradshaws, client change'"
        ),
      dryRun: z.boolean().default(false),
    },
    withTelemetry(
      "move_items_between_projects",
      async ({
        itemIds,
        destinationProjectId,
        destinationBudgetCategoryId,
        notes,
        dryRun,
      }) => {
        const noteError = requireAuditNote(notes, "move_items_between_projects");
        if (noteError) return noteError;

        const items: (Item & { id: string })[] = [];
        const missing: string[] = [];
        for (const itemId of itemIds) {
          const item = await getDoc<Item>(db, "items", itemId);
          if (!item) missing.push(itemId);
          else items.push(item);
        }
        if (missing.length > 0) {
          return notFound("Items", missing.join(", "), "get_items");
        }

        // All items must currently be in a project (not already in inventory).
        const stray = items.filter((i) => !i.projectId);
        if (stray.length > 0) {
          return validation(
            `${stray.length} item(s) are not in a project — cannot move-between-projects: ${stray.map((i) => i.id).join(", ")}`,
            "Use sell_items instead for items currently in business inventory."
          );
        }

        // All items must be in the SAME source project (otherwise the semantics of
        // one Return transaction per call don't make sense).
        const sourceProjects = new Set(items.map((i) => i.projectId!));
        if (sourceProjects.size > 1) {
          return validation(
            `Items span multiple source projects (${[...sourceProjects].join(", ")}). move_items_between_projects handles one source project per call.`,
            "Call once per source project, or move via inventory in two steps (return_items → sell_items)."
          );
        }
        const sourceProjectId = [...sourceProjects][0];

        if (sourceProjectId === destinationProjectId) {
          return validation(
            "Source and destination project are the same.",
            "Pick a different destination project, or update the items' budgetCategoryId directly via update_item."
          );
        }

        // Defense-in-depth: enforce destination category is enabled.
        const catError = await validateCategoryInProject(
          db,
          destinationProjectId,
          destinationBudgetCategoryId
        );
        if (catError) return catError;

        const { subtotalCents, amountCents, missingTax } = computeBatchTotals(items);

        if (dryRun) {
          return asToolResponse({
            dryRun: true,
            plan: {
              returnTransaction: {
                type: "Return" as const,
                source: "Business Inventory" as const,
                projectId: null,
                amountCents,
                itemIds: items.map((i) => i.id),
              },
              saleTransaction: {
                type: "Sale" as const,
                source: "Business Inventory" as const,
                projectId: destinationProjectId,
                budgetCategoryId: destinationBudgetCategoryId,
                amountCents,
                subtotalCents,
                itemIds: items.map((i) => i.id),
              },
              itemUpdates: items.map((i) => ({
                itemId: i.id,
                from: { projectId: i.projectId, budgetCategoryId: i.budgetCategoryId ?? null },
                to: {
                  projectId: destinationProjectId,
                  budgetCategoryId: destinationBudgetCategoryId,
                },
              })),
              sourceTransactionArrayRemoves: [
                ...new Set(items.map((i) => i.transactionId).filter(Boolean) as string[]),
              ],
              lineageEdges: items.length * 2, // one returned, one sold per item
            },
            warning:
              missingTax.length > 0
                ? `${missingTax.length} item(s) missing taxRatePct — amountCents will undercount.`
                : null,
          });
        }

        return await commitMoveBetweenProjects(
          db,
          items,
          sourceProjectId,
          destinationProjectId,
          destinationBudgetCategoryId,
          { subtotalCents, amountCents, missingTax, notes }
        );
      }
    )
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// commit: sell_items (inventory → project)
// ─────────────────────────────────────────────────────────────────────────────

async function commitSellItems(
  db: Firestore,
  items: (Item & { id: string })[],
  destinationProjectId: string,
  budgetCategoryId: string,
  totals: { subtotalCents: number; amountCents: number; missingTax: string[]; notes: string }
) {
  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  // 1. Create new Sale transaction (auto-ID, frozen shape).
  const saleRef = txCol.doc();
  const saleData: Record<string, unknown> = {
    type: "Sale",
    source: "Business Inventory",
    projectId: destinationProjectId,
    budgetCategoryId,
    amountCents: totals.amountCents,
    subtotalCents: totals.subtotalCents,
    itemIds: items.map((i) => i.id),
    status: "completed",
    isComplete: true,
    notes: totals.notes,
    createdAt: now,
    updatedAt: now,
    createdBy: uid,
  };
  batch.set(saleRef, saleData);

  // 2. Update each item: set project, category, status, transactionId (new sale).
  //    Remove from prior transaction's itemIds in step 3.
  for (const item of items) {
    batch.update(itemsCol.doc(item.id), {
      projectId: destinationProjectId,
      budgetCategoryId,
      status: "purchased",
      transactionId: saleRef.id,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // 3. Remove each item from its prior transaction's itemIds (if any).
  //    Dedup per source-transaction to collapse multiple item removals.
  const priorTxMap = new Map<string, string[]>();
  for (const item of items) {
    if (!item.transactionId) continue;
    const ids = priorTxMap.get(item.transactionId) ?? [];
    ids.push(item.id);
    priorTxMap.set(item.transactionId, ids);
  }
  for (const [priorTxId, ids] of priorTxMap) {
    batch.update(txCol.doc(priorTxId), {
      itemIds: FieldValue.arrayRemove(...ids),
      updatedAt: now,
    });
  }

  // 4. Lineage edges (sold).
  for (const item of items) {
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: item.transactionId ?? null,
      toTransactionId: saleRef.id,
      fromProjectId: null, // source is inventory (or prior tx) — inventory has no project
      toProjectId: destinationProjectId,
      movementKind: "sold",
      source: "mcp",
      createdAt: now,
    });
  }

  await batch.commit();

  const warning = missingTaxWarning(totals.missingTax, items.length);
  return {
    content: [
      {
        type: "text" as const,
        text:
          `Sold ${items.length} item(s) into project ${destinationProjectId}.\n` +
          `New Sale transaction: ${saleRef.id}\n` +
          `amountCents: ${totals.amountCents} (${formatCents(totals.amountCents)})\n` +
          `budgetCategoryId: ${budgetCategoryId}\n` +
          `Items: ${items.map((i) => `${i.id} (${i.name ?? "unnamed"}, ${formatCents(i.purchasePriceCents)})`).join(", ")}` +
          warning,
      },
    ],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// commit: return_items (project → inventory)
// ─────────────────────────────────────────────────────────────────────────────

async function commitReturnToInventory(
  db: Firestore,
  items: (Item & { id: string })[],
  existingReturnTx: (Transaction & { id: string }) | null,
  notes: string
) {
  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  // Compute the Return transaction's amount.
  // Returns use purchasePriceCents (what the business actually paid), not
  // projectPriceCents (client-facing markup).
  const returnAmount = items.reduce(
    (sum, i) => sum + (i.purchasePriceCents ?? 0),
    0
  );

  // Either reuse an existing Business-Inventory Return tx or create a new one.
  let returnTxRef: FirebaseFirestore.DocumentReference;
  let isNewReturnTx: boolean;
  if (existingReturnTx) {
    returnTxRef = txCol.doc(existingReturnTx.id);
    isNewReturnTx = false;
    // Append to itemIds; recompute amount as existing + new.
    const prevAmount = existingReturnTx.amountCents ?? 0;
    batch.update(returnTxRef, {
      itemIds: FieldValue.arrayUnion(...items.map((i) => i.id)),
      amountCents: prevAmount + returnAmount,
      updatedAt: now,
      notes: existingReturnTx.notes ? `${existingReturnTx.notes}\n${notes}` : notes,
    });
  } else {
    returnTxRef = txCol.doc();
    isNewReturnTx = true;
    batch.set(returnTxRef, {
      type: "Return",
      source: "Business Inventory",
      projectId: null,
      amountCents: returnAmount,
      itemIds: items.map((i) => i.id),
      status: "completed",
      notes,
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
    });
  }

  // Update each item: clear projectId + budgetCategoryId (invariant: items in
  // inventory have no category), set status to "returned", link to return tx.
  for (const item of items) {
    batch.update(itemsCol.doc(item.id), {
      projectId: null,
      budgetCategoryId: null,
      spaceId: FieldValue.delete(),
      status: "returned",
      transactionId: returnTxRef.id,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // Remove each item from its prior transaction (if different from return tx).
  const priorTxMap = new Map<string, string[]>();
  for (const item of items) {
    if (!item.transactionId) continue;
    if (item.transactionId === returnTxRef.id) continue;
    const ids = priorTxMap.get(item.transactionId) ?? [];
    ids.push(item.id);
    priorTxMap.set(item.transactionId, ids);
  }
  for (const [priorTxId, ids] of priorTxMap) {
    batch.update(txCol.doc(priorTxId), {
      itemIds: FieldValue.arrayRemove(...ids),
      updatedAt: now,
    });
  }

  // Lineage edges (returned).
  for (const item of items) {
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: item.transactionId ?? null,
      toTransactionId: returnTxRef.id,
      fromProjectId: item.projectId ?? null,
      toProjectId: null,
      movementKind: "returned",
      source: "mcp",
      createdAt: now,
    });
  }

  await batch.commit();

  return {
    content: [
      {
        type: "text" as const,
        text:
          `Returned ${items.length} item(s) to business inventory.\n` +
          `${isNewReturnTx ? "New Return transaction" : "Appended to existing Return transaction"}: ${returnTxRef.id}\n` +
          `source: Business Inventory\n` +
          `Items now have projectId: null and budgetCategoryId: null.`,
      },
    ],
  };
}

async function commitReturnToVendor(
  db: Firestore,
  items: (Item & { id: string })[],
  returnTx: Transaction & { id: string },
  notes: string
) {
  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  // Update items: status → returned, link to vendor return transaction.
  // projectId stays (vendor returns don't change scope).
  for (const item of items) {
    batch.update(itemsCol.doc(item.id), {
      status: "returned",
      transactionId: returnTx.id,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // Remove from prior transactions (if different from the vendor return tx).
  const priorTxMap = new Map<string, string[]>();
  for (const item of items) {
    if (!item.transactionId) continue;
    if (item.transactionId === returnTx.id) continue;
    const ids = priorTxMap.get(item.transactionId) ?? [];
    ids.push(item.id);
    priorTxMap.set(item.transactionId, ids);
  }
  for (const [priorTxId, ids] of priorTxMap) {
    batch.update(txCol.doc(priorTxId), {
      itemIds: FieldValue.arrayRemove(...ids),
      updatedAt: now,
    });
  }

  // Add items to vendor return transaction's itemIds.
  batch.update(txCol.doc(returnTx.id), {
    itemIds: FieldValue.arrayUnion(...items.map((i) => i.id)),
    updatedAt: now,
    notes: returnTx.notes ? `${returnTx.notes}\n${notes}` : notes,
  });

  // Lineage edges (returned).
  for (const item of items) {
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: item.transactionId ?? null,
      toTransactionId: returnTx.id,
      fromProjectId: item.projectId ?? null,
      toProjectId: item.projectId ?? null, // vendor returns stay in-project
      movementKind: "returned",
      source: "mcp",
      createdAt: now,
    });
  }

  await batch.commit();

  return {
    content: [
      {
        type: "text" as const,
        text:
          `Returned ${items.length} item(s) to vendor return transaction ${returnTx.id}.\n` +
          `Items: ${items.map((i) => `${i.id} (${i.name ?? "unnamed"})`).join(", ")}`,
      },
    ],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// commit: move_items_between_projects (source project → destination project)
// One batch: one Return-to-inventory + one Sale-to-destination.
// ─────────────────────────────────────────────────────────────────────────────

async function commitMoveBetweenProjects(
  db: Firestore,
  items: (Item & { id: string })[],
  sourceProjectId: string,
  destinationProjectId: string,
  destinationBudgetCategoryId: string,
  totals: { subtotalCents: number; amountCents: number; missingTax: string[]; notes: string }
) {
  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  const returnAmount = items.reduce((sum, i) => sum + (i.purchasePriceCents ?? 0), 0);

  // 1. New Return-to-inventory transaction.
  const returnTxRef = txCol.doc();
  batch.set(returnTxRef, {
    type: "Return",
    source: "Business Inventory",
    projectId: null,
    amountCents: returnAmount,
    itemIds: items.map((i) => i.id),
    status: "completed",
    notes: totals.notes,
    createdAt: now,
    updatedAt: now,
    createdBy: uid,
  });

  // 2. New Sale-to-destination transaction (frozen shape).
  const saleRef = txCol.doc();
  batch.set(saleRef, {
    type: "Sale",
    source: "Business Inventory",
    projectId: destinationProjectId,
    budgetCategoryId: destinationBudgetCategoryId,
    amountCents: totals.amountCents,
    subtotalCents: totals.subtotalCents,
    itemIds: items.map((i) => i.id),
    status: "completed",
    isComplete: true,
    notes: totals.notes,
    createdAt: now,
    updatedAt: now,
    createdBy: uid,
  });

  // 3. Update each item: move directly to destination. The Return + Sale are
  //    bookkeeping entries that reflect the movement in lineage; the item itself
  //    transitions straight to destination with the new category.
  for (const item of items) {
    batch.update(itemsCol.doc(item.id), {
      projectId: destinationProjectId,
      budgetCategoryId: destinationBudgetCategoryId,
      status: "purchased",
      transactionId: saleRef.id,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // 4. Remove items from their prior source transactions.
  const priorTxMap = new Map<string, string[]>();
  for (const item of items) {
    if (!item.transactionId) continue;
    const ids = priorTxMap.get(item.transactionId) ?? [];
    ids.push(item.id);
    priorTxMap.set(item.transactionId, ids);
  }
  for (const [priorTxId, ids] of priorTxMap) {
    batch.update(txCol.doc(priorTxId), {
      itemIds: FieldValue.arrayRemove(...ids),
      updatedAt: now,
    });
  }

  // 5. Lineage edges: one "returned" (source → return) and one "sold" (return → sale).
  for (const item of items) {
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: item.transactionId ?? null,
      toTransactionId: returnTxRef.id,
      fromProjectId: sourceProjectId,
      toProjectId: null,
      movementKind: "returned",
      source: "mcp",
      createdAt: now,
    });
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: returnTxRef.id,
      toTransactionId: saleRef.id,
      fromProjectId: null,
      toProjectId: destinationProjectId,
      movementKind: "sold",
      source: "mcp",
      createdAt: now,
    });
  }

  await batch.commit();

  const warning = missingTaxWarning(totals.missingTax, items.length);
  return {
    content: [
      {
        type: "text" as const,
        text:
          `Moved ${items.length} item(s) from ${sourceProjectId} to ${destinationProjectId}.\n` +
          `New Return transaction (source → inventory): ${returnTxRef.id}\n` +
          `New Sale transaction (inventory → destination): ${saleRef.id}\n` +
          `Destination category: ${destinationBudgetCategoryId}\n` +
          `amountCents: ${totals.amountCents} (${formatCents(totals.amountCents)})` +
          warning,
      },
    ],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Safe uid accessor — prefer request context, fall back to "mcp-server" so
// env-configured (no-auth) deployments don't crash on writes.
// ─────────────────────────────────────────────────────────────────────────────

function safeGetUserId(): string {
  try {
    return getUid();
  } catch {
    return "mcp-server";
  }
}
