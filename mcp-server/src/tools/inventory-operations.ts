import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { Item, Transaction } from "../types.js";
import { accountCollection, subcollection, getDoc } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { notFound, validation } from "../util/errors.js";
import { tagNotesAsAi } from "../util/notes.js";
import { asToolResponse } from "../util/projections.js";
import { withTelemetry } from "../util/telemetry.js";
import { getUid } from "../context.js";

// ─────────────────────────────────────────────────────────────────────────────
// MCP-side implementation of the per-batch sale spec at
// docs/specs/sale-transactions.md. Mirrors
// LedgeriOS/Services/InventoryOperationsService.swift.
//
// Key invariants (also enforced by Firestore rules):
//   • Each inventory movement creates at least one new immutable Sale or
//     Return transaction with an auto-ID. Shape fields (amountCents, itemIds,
//     budgetCategoryId, type, source, projectId) are frozen at creation.
//   • Sales are BIDIRECTIONAL:
//        - inventory → project: Sale with `budgetCategoryId` set.
//        - project → inventory: Sale with `budgetCategoryId` absent.
//     Direction is derivable from the transaction shape alone.
//   • Return is RESERVED for items going HOME to inventory — i.e., items
//     that previously passed through inventory (currentSource != source).
//     Items that originated in a project and are moving to inventory are a
//     Sale-to-Inventory, NOT a Return.
//   • Items in business inventory (projectId == null) have
//     budgetCategoryId == null.
//   • Batch cap: 100 items per operation.
// ─────────────────────────────────────────────────────────────────────────────

const MAX_BATCH_ITEMS = 100;
const INVENTORY_LABEL = "Business Inventory";

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
 * True if the item's most recent scope move passed through inventory (i.e.
 * `currentSource != source`). A project→inventory move for such an item is
 * a Return (going home). For items that originated in their project
 * (`currentSource == source`, or currentSource missing), a project→inventory
 * move is a Sale-to-Inventory (business is acquiring the item).
 *
 * Mirrors InventoryOperationsService.cameFromInventory.
 */
function cameFromInventory(item: Item): boolean {
  const current = (item.currentSource ?? item.source ?? "").trim();
  const original = (item.source ?? "").trim();
  if (!current) return false;
  return current !== original;
}

/** Partition items by origin into Return leg and Sale-to-Inventory leg. */
function splitByOrigin(items: (Item & { id: string })[]): {
  returnItems: (Item & { id: string })[];
  saleItems: (Item & { id: string })[];
} {
  const returnItems: (Item & { id: string })[] = [];
  const saleItems: (Item & { id: string })[] = [];
  for (const item of items) {
    if (cameFromInventory(item)) returnItems.push(item);
    else saleItems.push(item);
  }
  return { returnItems, saleItems };
}

/**
 * Pre-fetch each distinct source transaction's type. Sale and Return are
 * frozen by Firestore rules; their itemIds cannot be mutated via arrayRemove.
 * The commit helpers skip arrayRemove for these sources.
 */
async function frozenSourceTxIds(
  db: Firestore,
  items: (Item & { id: string })[]
): Promise<Set<string>> {
  const unique = new Set(items.map((i) => i.transactionId).filter(Boolean) as string[]);
  const frozen = new Set<string>();
  for (const txId of unique) {
    const tx = await getDoc<Transaction>(db, "transactions", txId);
    if (tx && (tx.type === "Sale" || tx.type === "Return")) frozen.add(txId);
  }
  return frozen;
}

/** Validate that a budget category exists and is enabled in a project. */
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
    "[destructive] Create a Sale transaction moving items between inventory and a project. " +
      "Sales are BIDIRECTIONAL — direction is derived from the arguments:\n\n" +
      "• INVENTORY → PROJECT (pass budgetCategoryId): items must currently be in business inventory " +
      "(projectId == null). Items land in destinationProjectId under the chosen category. The " +
      "project's budget for that category increases. Ask the user to pick the category from " +
      "get_project_budget_categories BEFORE calling — one category per batch.\n\n" +
      "• PROJECT → INVENTORY (omit budgetCategoryId): items must currently be in destinationProjectId " +
      "AND must have originated in that project (currentSource == source, i.e. the business is acquiring " +
      "them for inventory for the first time). Items land in inventory with projectId and " +
      "budgetCategoryId cleared. The source project's budget decreases. For items that came from " +
      "inventory originally, use return_items (returnTo: 'inventory') instead — that's a Return, not a Sale.\n\n" +
      "Each call creates ONE new immutable Sale transaction with an auto-ID. Shape fields (amountCents, " +
      "itemIds, budgetCategoryId, projectId, type, source) are frozen at creation. Cap: 100 items per call.\n\n" +
      "Related: for project→project reallocation, use move_items_between_projects — it runs the correct " +
      "origin-aware two-hop (Return or Sale-to-Inventory on the first hop, Sale-to-Project on the second).",
    {
      itemIds: z
        .array(z.string())
        .min(1)
        .max(MAX_BATCH_ITEMS)
        .describe(`Item document IDs to sell (max ${MAX_BATCH_ITEMS} per call)`),
      destinationProjectId: z
        .string()
        .describe(
          "The project side of the sale. For inventory→project, this is where items are going. " +
            "For project→inventory, this is where items are coming from (must match every item's current projectId)."
        ),
      budgetCategoryId: z
        .string()
        .optional()
        .describe(
          "Present → inventory→project direction (required: a category enabled in destinationProjectId; " +
            "ask the user to pick from get_project_budget_categories). " +
            "Absent → project→inventory direction (business is acquiring items that originated in the project)."
        ),
      notes: z
        .string()
        .optional()
        .describe(
          "Optional prose describing the sale (e.g. 'Sold 5 fixtures into Witzenman — client approved selections'). Free-form. The Sale transaction's createdAt/createdBy + lineage edges are the audit trail; notes is just human-readable context."
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

        // Fetch all items.
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

        const direction: "inventoryToProject" | "projectToInventory" =
          budgetCategoryId ? "inventoryToProject" : "projectToInventory";

        if (direction === "inventoryToProject") {
          // Every item must currently be in inventory.
          const notInInventory = items.filter((i) => i.projectId);
          if (notInInventory.length > 0) {
            return validation(
              `${notInInventory.length} item(s) are not in business inventory: ${notInInventory.map((i) => i.id).join(", ")}`,
              "For items currently in a project, use move_items_between_projects (project→project) or sell_items without budgetCategoryId (project→inventory)."
            );
          }

          const catError = await validateCategoryInProject(
            db,
            destinationProjectId,
            budgetCategoryId!
          );
          if (catError) return catError;

          const { subtotalCents, amountCents, missingTax } = computeBatchTotals(items);
          if (dryRun) {
            return asToolResponse({
              dryRun: true,
              direction,
              plan: {
                saleTransaction: {
                  type: "Sale" as const,
                  source: INVENTORY_LABEL,
                  projectId: destinationProjectId,
                  budgetCategoryId: budgetCategoryId!,
                  amountCents,
                  subtotalCents,
                  itemIds: items.map((i) => i.id),
                },
                itemUpdates: items.map((i) => ({
                  itemId: i.id,
                  set: {
                    projectId: destinationProjectId,
                    budgetCategoryId: budgetCategoryId!,
                    status: "purchased",
                    currentSource: INVENTORY_LABEL,
                  },
                })),
                lineageEdges: items.length,
              },
              warning:
                missingTax.length > 0
                  ? `${missingTax.length} item(s) missing taxRatePct — amountCents will undercount.`
                  : null,
            });
          }
          return await commitSellToProject(db, items, destinationProjectId, budgetCategoryId!, {
            subtotalCents,
            amountCents,
            missingTax,
            notes,
          });
        }

        // direction === "projectToInventory" — Sale to Inventory.
        // Every item must currently be in the source project AND must have
        // originated there (not routed through inventory previously).
        const wrongProject = items.filter((i) => i.projectId !== destinationProjectId);
        if (wrongProject.length > 0) {
          return validation(
            `${wrongProject.length} item(s) are not in project ${destinationProjectId}: ${wrongProject.map((i) => i.id).join(", ")}`,
            "For a project→inventory Sale, every item must currently be in destinationProjectId."
          );
        }
        const fromInventory = items.filter((i) => cameFromInventory(i));
        if (fromInventory.length > 0) {
          return validation(
            `${fromInventory.length} item(s) previously passed through inventory (currentSource != source): ${fromInventory.map((i) => i.id).join(", ")}. These must go via return_items (Return), not sell_items.`,
            "Use return_items with returnTo: 'inventory' for from-inventory items. sell_items (project→inventory) is reserved for items that originated in the project."
          );
        }

        const { subtotalCents, amountCents, missingTax } = computeBatchTotals(items);
        if (dryRun) {
          return asToolResponse({
            dryRun: true,
            direction,
            plan: {
              saleTransaction: {
                type: "Sale" as const,
                source: INVENTORY_LABEL,
                projectId: destinationProjectId,
                // budgetCategoryId absent → encodes project→inventory direction
                amountCents,
                subtotalCents,
                itemIds: items.map((i) => i.id),
              },
              itemUpdates: items.map((i) => ({
                itemId: i.id,
                set: {
                  projectId: null,
                  budgetCategoryId: null,
                  status: "purchased",
                  currentSource: INVENTORY_LABEL,
                },
              })),
              lineageEdges: items.length,
            },
            warning:
              missingTax.length > 0
                ? `${missingTax.length} item(s) missing taxRatePct — amountCents will undercount.`
                : null,
          });
        }
        return await commitSellToInventory(db, items, destinationProjectId, {
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
    "[destructive] Return items. A Return is for items going HOME — either back to the vendor they " +
      "came from, or back to business inventory (if they previously came from inventory).\n\n" +
      "• returnTo: 'vendor' — attaches items to an existing vendor Return transaction. Create the " +
      "Return transaction first via create_transaction (type: 'Return'), then pass its ID as " +
      "returnTransactionId.\n\n" +
      "• returnTo: 'inventory' — moves items from their current project back to business inventory. " +
      "ORIGIN REQUIREMENT: every item must have previously passed through inventory " +
      "(currentSource != source). Items that originated in the project and have never been in " +
      "inventory before are NOT a return — they are a Sale-to-Inventory (use sell_items without " +
      "budgetCategoryId instead). Creates a new Return transaction with source: 'Business Inventory' " +
      "(or appends to one if returnTransactionId is provided). Items have budgetCategoryId and " +
      "projectId cleared.\n\n" +
      "Cap: 100 items per call. Set dryRun: true to preview the plan.",
    {
      itemIds: z
        .array(z.string())
        .min(1)
        .max(MAX_BATCH_ITEMS)
        .describe(`Item document IDs to return (max ${MAX_BATCH_ITEMS} per call)`),
      returnTo: z
        .enum(["vendor", "inventory"])
        .describe(
          "Where the items are going: 'vendor' (attach to an existing Return tx) or 'inventory' " +
            "(new or reused Return tx with source: 'Business Inventory' — items must have come from inventory originally)"
        ),
      returnTransactionId: z
        .string()
        .optional()
        .describe(
          "When returnTo is 'vendor': REQUIRED existing Return transaction ID. " +
            "When returnTo is 'inventory': OPTIONAL existing Return transaction ID to append to; if omitted, a new one is created."
        ),
      notes: z
        .string()
        .optional()
        .describe("Optional prose describing the return (e.g. 'returned 2 fixtures — wrong finish'). Free-form. createdAt/createdBy + lineage edges are the audit trail."),
      dryRun: z.boolean().default(false).describe("If true, return the plan without writing."),
    },
    withTelemetry(
      "return_items",
      async ({ itemIds, returnTo, returnTransactionId, notes, dryRun }) => {

        if (returnTo === "vendor" && !returnTransactionId) {
          return validation(
            "returnTransactionId is required when returnTo is 'vendor'.",
            "Create a vendor Return transaction first (type: 'Return'), then pass its ID as returnTransactionId."
          );
        }

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

        // Origin guard (inventory path only): Return is ONLY for items that
        // previously passed through inventory. Items that originated in a
        // project go via sell_items (Sale-to-Inventory).
        if (returnTo === "inventory") {
          const originated = items.filter((i) => !cameFromInventory(i));
          if (originated.length > 0) {
            return validation(
              `${originated.length} item(s) originated in their current project (currentSource == source) — these are NOT a return: ${originated.map((i) => i.id).join(", ")}.`,
              "Use sell_items without budgetCategoryId to Sale-to-Inventory for originated-in-project items. return_items (returnTo: 'inventory') is reserved for items going HOME to inventory."
            );
          }
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
                        currentSource: INVENTORY_LABEL,
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
    "[destructive] Move items from one project to another. This is a real financial movement — NOT a " +
      "silent bookkeeping repoint. Implemented as an origin-aware two-hop atomic batch:\n\n" +
      "  FIRST HOP (per-item, origin-aware):\n" +
      "   • Items that previously passed through inventory (currentSource != source) → a Return " +
      "transaction against the source project.\n" +
      "   • Items that originated in the source project (currentSource == source) → a Sale-to-Inventory " +
      "transaction (type: 'Sale', no budgetCategoryId) against the source project.\n" +
      "   • Mixed batches produce BOTH first-hop transactions in the same Firestore batch.\n\n" +
      "  SECOND HOP: one Sale-to-Project transaction (type: 'Sale', with budgetCategoryId) against " +
      "the destination project, covering every item in the batch.\n\n" +
      "All items must be in the same source project. Cap: 100 items per call. One destination category " +
      "applies to the whole batch — ask the user to pick from get_project_budget_categories before calling. " +
      "Source and destination must differ.\n\n" +
      "DO NOT use this as a shortcut for 'the item was entered on the wrong transaction but still belongs to " +
      "the same project' — that's a reassignment, use update_item to move the item to the correct " +
      "transaction within the same project.",
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
        .optional()
        .describe(
          "Optional prose describing the move (e.g. 'Moved 3 sconces from Witzenman to Bradshaws — client change'). Free-form. createdAt/createdBy + lineage edges are the audit trail."
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

        const stray = items.filter((i) => !i.projectId);
        if (stray.length > 0) {
          return validation(
            `${stray.length} item(s) are not in a project — cannot move-between-projects: ${stray.map((i) => i.id).join(", ")}`,
            "Use sell_items (inventory→project) for items currently in business inventory."
          );
        }

        const sourceProjects = new Set(items.map((i) => i.projectId!));
        if (sourceProjects.size > 1) {
          return validation(
            `Items span multiple source projects (${[...sourceProjects].join(", ")}). move_items_between_projects handles one source project per call.`,
            "Call once per source project."
          );
        }
        const sourceProjectId = [...sourceProjects][0];

        if (sourceProjectId === destinationProjectId) {
          return validation(
            "Source and destination project are the same.",
            "Pick a different destination project. For within-project transaction reassignment, use update_item."
          );
        }

        const catError = await validateCategoryInProject(
          db,
          destinationProjectId,
          destinationBudgetCategoryId
        );
        if (catError) return catError;

        const split = splitByOrigin(items);
        const { subtotalCents, amountCents, missingTax } = computeBatchTotals(items);

        if (dryRun) {
          const returnLeg =
            split.returnItems.length > 0
              ? {
                  type: "Return" as const,
                  source: INVENTORY_LABEL,
                  projectId: sourceProjectId,
                  amountCents: split.returnItems.reduce(
                    (sum, i) => sum + (i.purchasePriceCents ?? 0),
                    0
                  ),
                  itemIds: split.returnItems.map((i) => i.id),
                }
              : null;
          const saleToInventoryLeg =
            split.saleItems.length > 0
              ? (() => {
                  const t = computeBatchTotals(split.saleItems);
                  return {
                    type: "Sale" as const,
                    source: INVENTORY_LABEL,
                    projectId: sourceProjectId,
                    // budgetCategoryId absent → project→inventory
                    amountCents: t.amountCents,
                    subtotalCents: t.subtotalCents,
                    itemIds: split.saleItems.map((i) => i.id),
                  };
                })()
              : null;
          return asToolResponse({
            dryRun: true,
            plan: {
              firstHop: {
                returnLeg,
                saleToInventoryLeg,
              },
              secondHop: {
                saleToProject: {
                  type: "Sale" as const,
                  source: INVENTORY_LABEL,
                  projectId: destinationProjectId,
                  budgetCategoryId: destinationBudgetCategoryId,
                  amountCents,
                  subtotalCents,
                  itemIds: items.map((i) => i.id),
                },
              },
              itemUpdates: items.map((i) => ({
                itemId: i.id,
                from: { projectId: i.projectId, budgetCategoryId: i.budgetCategoryId ?? null },
                to: {
                  projectId: destinationProjectId,
                  budgetCategoryId: destinationBudgetCategoryId,
                  currentSource: INVENTORY_LABEL,
                },
              })),
              lineageEdges: items.length * 2, // first-hop + second-hop per item
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
          split,
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
// commit: sell_items, inventory → project
// ─────────────────────────────────────────────────────────────────────────────

async function commitSellToProject(
  db: Firestore,
  items: (Item & { id: string })[],
  destinationProjectId: string,
  budgetCategoryId: string,
  totals: { subtotalCents: number; amountCents: number; missingTax: string[]; notes?: string }
) {
  const frozen = await frozenSourceTxIds(db, items);

  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  // 1. New Sale transaction (frozen shape).
  const saleRef = txCol.doc();
  batch.set(saleRef, {
    type: "Sale",
    source: INVENTORY_LABEL,
    projectId: destinationProjectId,
    budgetCategoryId,
    amountCents: totals.amountCents,
    subtotalCents: totals.subtotalCents,
    itemIds: items.map((i) => i.id),
    status: "completed",
    isComplete: true,
    ...(totals.notes ? { notes: tagNotesAsAi(totals.notes) } : {}),
    createdAt: now,
    updatedAt: now,
    createdBy: uid,
  });

  // 2. Each item: land in destination, currentSource ← inventory label.
  for (const item of items) {
    batch.update(itemsCol.doc(item.id), {
      projectId: destinationProjectId,
      budgetCategoryId,
      status: "purchased",
      transactionId: saleRef.id,
      spaceId: null,
      currentSource: INVENTORY_LABEL,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // 3. Remove from prior tx itemIds — skip frozen Sale/Return sources.
  applyArrayRemoves(batch, txCol, items, frozen, now);

  // 4. Lineage edges.
  for (const item of items) {
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: item.transactionId ?? null,
      toTransactionId: saleRef.id,
      fromProjectId: item.projectId ?? null,
      toProjectId: destinationProjectId,
      movementKind: "sold",
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
          `Sold ${items.length} item(s) from inventory into project ${destinationProjectId}.\n` +
          `New Sale transaction: ${saleRef.id}\n` +
          `amountCents: ${totals.amountCents} (${formatCents(totals.amountCents)})\n` +
          `budgetCategoryId: ${budgetCategoryId}` +
          missingTaxWarning(totals.missingTax, items.length),
      },
    ],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// commit: sell_items, project → inventory (Sale-to-Inventory)
// ─────────────────────────────────────────────────────────────────────────────

async function commitSellToInventory(
  db: Firestore,
  items: (Item & { id: string })[],
  sourceProjectId: string,
  totals: { subtotalCents: number; amountCents: number; missingTax: string[]; notes?: string }
) {
  const frozen = await frozenSourceTxIds(db, items);

  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  // 1. New Sale transaction. budgetCategoryId absent encodes project→inventory direction.
  const saleRef = txCol.doc();
  batch.set(saleRef, {
    type: "Sale",
    source: INVENTORY_LABEL,
    projectId: sourceProjectId,
    amountCents: totals.amountCents,
    subtotalCents: totals.subtotalCents,
    itemIds: items.map((i) => i.id),
    status: "completed",
    isComplete: true,
    ...(totals.notes ? { notes: tagNotesAsAi(totals.notes) } : {}),
    createdAt: now,
    updatedAt: now,
    createdBy: uid,
  });

  // 2. Each item: land in inventory.
  for (const item of items) {
    batch.update(itemsCol.doc(item.id), {
      projectId: null,
      budgetCategoryId: null,
      spaceId: null,
      status: "purchased",
      transactionId: saleRef.id,
      currentSource: INVENTORY_LABEL,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // 3. Remove from prior tx itemIds — skip frozen sources.
  applyArrayRemoves(batch, txCol, items, frozen, now);

  // 4. Lineage edges — "soldToInventory" signals project → inventory acquisition.
  for (const item of items) {
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: item.transactionId ?? null,
      toTransactionId: saleRef.id,
      fromProjectId: sourceProjectId,
      toProjectId: null,
      movementKind: "soldToInventory",
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
          `Sold ${items.length} item(s) from project ${sourceProjectId} to business inventory (business acquisition).\n` +
          `New Sale transaction: ${saleRef.id}\n` +
          `amountCents: ${totals.amountCents} (${formatCents(totals.amountCents)})\n` +
          `Items now have projectId: null and budgetCategoryId: null.` +
          missingTaxWarning(totals.missingTax, items.length),
      },
    ],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// commit: return_items, inventory path (items going HOME to inventory)
// ─────────────────────────────────────────────────────────────────────────────

async function commitReturnToInventory(
  db: Firestore,
  items: (Item & { id: string })[],
  existingReturnTx: (Transaction & { id: string }) | null,
  notes: string | undefined
) {
  const frozen = await frozenSourceTxIds(db, items);

  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  // Return amount uses purchasePriceCents (what the business actually paid).
  const returnAmount = items.reduce((sum, i) => sum + (i.purchasePriceCents ?? 0), 0);
  // projectId on the Return tx = source project (budget impact lands there).
  const sourceProjectId = items[0]?.projectId ?? null;
  const tagged = notes ? tagNotesAsAi(notes) : undefined;

  let returnTxRef: FirebaseFirestore.DocumentReference;
  let isNewReturnTx: boolean;
  if (existingReturnTx) {
    returnTxRef = txCol.doc(existingReturnTx.id);
    isNewReturnTx = false;
    const prevAmount = existingReturnTx.amountCents ?? 0;
    const mergedNotes = tagged
      ? existingReturnTx.notes
        ? `${existingReturnTx.notes}\n\n${tagged}`
        : tagged
      : existingReturnTx.notes;
    batch.update(returnTxRef, {
      itemIds: FieldValue.arrayUnion(...items.map((i) => i.id)),
      amountCents: prevAmount + returnAmount,
      updatedAt: now,
      ...(mergedNotes !== undefined ? { notes: mergedNotes } : {}),
    });
  } else {
    returnTxRef = txCol.doc();
    isNewReturnTx = true;
    batch.set(returnTxRef, {
      type: "Return",
      source: INVENTORY_LABEL,
      projectId: sourceProjectId,
      amountCents: returnAmount,
      itemIds: items.map((i) => i.id),
      status: "completed",
      ...(tagged ? { notes: tagged } : {}),
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
    });
  }

  for (const item of items) {
    batch.update(itemsCol.doc(item.id), {
      projectId: null,
      budgetCategoryId: null,
      spaceId: null,
      status: "returned",
      transactionId: returnTxRef.id,
      currentSource: INVENTORY_LABEL,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // Remove from prior tx itemIds — skip frozen + the return tx itself.
  const frozenPlusReturn = new Set(frozen);
  frozenPlusReturn.add(returnTxRef.id);
  applyArrayRemoves(batch, txCol, items, frozenPlusReturn, now);

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
          `Items now have projectId: null and budgetCategoryId: null.`,
      },
    ],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// commit: return_items, vendor path (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

async function commitReturnToVendor(
  db: Firestore,
  items: (Item & { id: string })[],
  returnTx: Transaction & { id: string },
  notes: string | undefined
) {
  const frozen = await frozenSourceTxIds(db, items);

  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();
  const tagged = notes ? tagNotesAsAi(notes) : undefined;

  for (const item of items) {
    batch.update(itemsCol.doc(item.id), {
      status: "returned",
      transactionId: returnTx.id,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // Vendor return tx is itself a Return, so its itemIds is frozen — use
  // update-with-arrayUnion (allowed by rules because itemIds arrayUnion is
  // permitted for mutable-append fields; matches prior behavior).
  const mergedNotes = tagged
    ? returnTx.notes
      ? `${returnTx.notes}\n\n${tagged}`
      : tagged
    : returnTx.notes;
  batch.update(txCol.doc(returnTx.id), {
    itemIds: FieldValue.arrayUnion(...items.map((i) => i.id)),
    updatedAt: now,
    ...(mergedNotes !== undefined ? { notes: mergedNotes } : {}),
  });

  // Remove from prior tx itemIds — skip frozen sources and the return tx itself.
  const frozenPlusReturn = new Set(frozen);
  frozenPlusReturn.add(returnTx.id);
  applyArrayRemoves(batch, txCol, items, frozenPlusReturn, now);

  for (const item of items) {
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: item.transactionId ?? null,
      toTransactionId: returnTx.id,
      fromProjectId: item.projectId ?? null,
      toProjectId: item.projectId ?? null,
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
// commit: move_items_between_projects, origin-aware two-hop
// ─────────────────────────────────────────────────────────────────────────────

async function commitMoveBetweenProjects(
  db: Firestore,
  items: (Item & { id: string })[],
  split: {
    returnItems: (Item & { id: string })[];
    saleItems: (Item & { id: string })[];
  },
  sourceProjectId: string,
  destinationProjectId: string,
  destinationBudgetCategoryId: string,
  totals: { subtotalCents: number; amountCents: number; missingTax: string[]; notes?: string }
) {
  const frozen = await frozenSourceTxIds(db, items);

  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  // 1a. First hop — Return leg (items that previously came from inventory).
  let returnTxId: string | null = null;
  if (split.returnItems.length > 0) {
    const returnRef = txCol.doc();
    returnTxId = returnRef.id;
    const returnAmount = split.returnItems.reduce(
      (sum, i) => sum + (i.purchasePriceCents ?? 0),
      0
    );
    batch.set(returnRef, {
      type: "Return",
      source: INVENTORY_LABEL,
      projectId: sourceProjectId,
      amountCents: returnAmount,
      itemIds: split.returnItems.map((i) => i.id),
      status: "completed",
      ...(totals.notes ? { notes: tagNotesAsAi(totals.notes) } : {}),
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
    });
  }

  // 1b. First hop — Sale-to-Inventory leg (items that originated in the source project).
  let firstSaleTxId: string | null = null;
  if (split.saleItems.length > 0) {
    const saleRef = txCol.doc();
    firstSaleTxId = saleRef.id;
    const saleTotals = computeBatchTotals(split.saleItems);
    batch.set(saleRef, {
      type: "Sale",
      source: INVENTORY_LABEL,
      projectId: sourceProjectId,
      // budgetCategoryId absent → project→inventory direction
      amountCents: saleTotals.amountCents,
      subtotalCents: saleTotals.subtotalCents,
      itemIds: split.saleItems.map((i) => i.id),
      status: "completed",
      isComplete: true,
      ...(totals.notes ? { notes: tagNotesAsAi(totals.notes) } : {}),
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
    });
  }

  // 2. Second hop — Sale-to-Project (destination) covers every item.
  const destSaleRef = txCol.doc();
  batch.set(destSaleRef, {
    type: "Sale",
    source: INVENTORY_LABEL,
    projectId: destinationProjectId,
    budgetCategoryId: destinationBudgetCategoryId,
    amountCents: totals.amountCents,
    subtotalCents: totals.subtotalCents,
    itemIds: items.map((i) => i.id),
    status: "completed",
    isComplete: true,
    ...(totals.notes ? { notes: tagNotesAsAi(totals.notes) } : {}),
    createdAt: now,
    updatedAt: now,
    createdBy: uid,
  });

  // 3. Item updates — land in destination.
  for (const item of items) {
    batch.update(itemsCol.doc(item.id), {
      projectId: destinationProjectId,
      budgetCategoryId: destinationBudgetCategoryId,
      status: "purchased",
      transactionId: destSaleRef.id,
      spaceId: null,
      currentSource: INVENTORY_LABEL,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // 4. Remove from prior tx itemIds — skip frozen.
  applyArrayRemoves(batch, txCol, items, frozen, now);

  // 5. Lineage edges — two per item.
  for (const item of items) {
    const cameFrom = cameFromInventory(item);
    const firstHopTxId = cameFrom ? returnTxId : firstSaleTxId;
    const firstHopKind = cameFrom ? "returned" : "soldToInventory";
    if (firstHopTxId) {
      batch.set(edgesCol.doc(), {
        itemId: item.id,
        fromTransactionId: item.transactionId ?? null,
        toTransactionId: firstHopTxId,
        fromProjectId: sourceProjectId,
        toProjectId: null,
        movementKind: firstHopKind,
        source: "mcp",
        createdAt: now,
      });
    }
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: firstHopTxId ?? item.transactionId ?? null,
      toTransactionId: destSaleRef.id,
      fromProjectId: null,
      toProjectId: destinationProjectId,
      movementKind: "sold",
      source: "mcp",
      createdAt: now,
    });
  }

  await batch.commit();

  const legs: string[] = [];
  if (returnTxId) legs.push(`Return (from-inventory leg): ${returnTxId}`);
  if (firstSaleTxId) legs.push(`Sale-to-Inventory (originated-in-project leg): ${firstSaleTxId}`);
  legs.push(`Sale-to-Project (destination): ${destSaleRef.id}`);

  return {
    content: [
      {
        type: "text" as const,
        text:
          `Moved ${items.length} item(s) from ${sourceProjectId} to ${destinationProjectId}.\n` +
          legs.join("\n") +
          `\nDestination category: ${destinationBudgetCategoryId}\n` +
          `amountCents (second-hop Sale): ${totals.amountCents} (${formatCents(totals.amountCents)})` +
          missingTaxWarning(totals.missingTax, items.length),
      },
    ],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Remove items from their prior source transaction's itemIds — one update per
 * distinct source tx. Sale and Return sources (listed in `frozen`) are skipped
 * because Firestore rules reject mutations to their itemIds array.
 */
function applyArrayRemoves(
  batch: FirebaseFirestore.WriteBatch,
  txCol: FirebaseFirestore.CollectionReference,
  items: (Item & { id: string })[],
  frozen: Set<string>,
  now: FirebaseFirestore.FieldValue
) {
  const priorTxMap = new Map<string, string[]>();
  for (const item of items) {
    if (!item.transactionId) continue;
    if (frozen.has(item.transactionId)) continue;
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
}

/**
 * Prefer the request's auth context; fall back to "mcp-server" so env-configured
 * (no-auth) deployments don't crash on writes.
 */
function safeGetUserId(): string {
  try {
    return getUid();
  } catch {
    return "mcp-server";
  }
}
