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
import { DEFAULT_INVENTORY_LABEL, resolveInventoryLabel } from "../util/inventory.js";

// ─────────────────────────────────────────────────────────────────────────────
// MCP-side implementation of the per-batch inventory movement spec at
// docs/specs/sale-transactions.md. Mirrors
// LedgeriOS/Services/InventoryOperationsService.swift.
//
// Key invariants (also enforced by Firestore rules):
//   • Each inventory movement creates at least one new immutable Purchase,
//     Sale, or Return transaction with an auto-ID. Shape fields (amountCents,
//     itemIds, budgetCategoryId, type, source, projectId) are frozen at creation.
//   • Inventory movement direction is derived from transaction shape:
//        - inventory → project: Purchase with `budgetCategoryId` set.
//        - project → inventory acquisition: Sale with `budgetCategoryId` absent.
//   • Return is RESERVED for items going HOME to inventory — i.e., items
//     that previously passed through inventory (currentSource != source).
//     Items that originated in a project and are moving to inventory are a
//     Sale-to-Inventory, NOT a Return.
//   • Items in business inventory (projectId == null) have
//     budgetCategoryId == null.
//   • Batch cap: 100 items per operation.
// ─────────────────────────────────────────────────────────────────────────────

const MAX_BATCH_ITEMS = 100;
const INVENTORY_LABEL = DEFAULT_INVENTORY_LABEL;

/**
 * Resolve a frozen amount snapshot for a batch of items. Uses
 * `projectPriceCents` (the client-charged price) exclusively — never falls
 * back to `purchasePriceCents` (the business's cost). Callers must invoke
 * `missingProjectPrice` first and bail with a validation error if any item
 * lacks a non-null, non-zero `projectPriceCents`; this function assumes that
 * check has already passed and treats a missing/zero price as `0`.
 */
function computeBatchTotals(items: (Item & { id: string })[]): {
  subtotalCents: number;
  amountCents: number;
  missingTax: string[];
} {
  let subtotalCents = 0;
  let amountCents = 0;
  const missingTax: string[] = [];
  for (const item of items) {
    const price = item.projectPriceCents ?? 0;
    const rate = item.taxRatePct ?? 0;
    subtotalCents += price;
    amountCents += rate > 0 ? Math.round(price * (1 + rate / 100)) : price;
    if (item.taxRatePct == null) missingTax.push(item.id);
  }
  return { subtotalCents, amountCents, missingTax };
}

/**
 * Return the ids of items that lack a usable `projectPriceCents`. Inventory
 * movements that create a Sale, a Purchase-from-Inventory, or a Return-to-
 * Inventory must charge at the client-facing project price; silently falling
 * back to `purchasePriceCents` (cost) would mis-state the project's budget.
 */
function missingProjectPrice(items: (Item & { id: string })[]): string[] {
  return items
    .filter((i) => i.projectPriceCents == null || i.projectPriceCents === 0)
    .map((i) => i.id);
}

function missingProjectPriceError(ids: string[]) {
  return validation(
    `${ids.length} item(s) have no projectPriceCents (the client-charged price): ${ids.join(", ")}.`,
    "Inventory movement amounts must use projectPriceCents, not purchasePriceCents (cost). " +
      "Set projectPriceCents on each listed item via update_item before retrying."
  );
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
 * Pre-fetch each distinct source transaction's type. Inventory movement
 * transactions are frozen; their itemIds cannot be mutated via arrayRemove.
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
    const isInventoryPurchase =
      tx?.type === "Purchase" && typeof tx.source === "string" && tx.source.endsWith(" Inventory");
    if (tx && (tx.type === "Sale" || tx.type === "Return" || isInventoryPurchase)) frozen.add(txId);
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
  // ── sell_items_from_inventory_to_project ───────────────────────────────────
  server.tool(
    "sell_items_from_inventory_to_project",
    "[event] Sell items from business inventory into a project. Creates ONE new immutable Purchase " +
      "transaction (source: Business Inventory) against destinationProjectId, increasing that " +
      "project's budget under budgetCategoryId. Every item must currently be in business inventory " +
      "(projectId == null).\n\n" +
      "REAL EVENT vs CORRECTION: This records a real business event (money changes hands, budgets " +
      "move). Do NOT use it to satisfy a schema rule when an item was logged incorrectly. If you " +
      "encounter project items with no transaction (legacy orphans), the fix is `bulk_update_items` " +
      "with `projectId: null` to relocate them to inventory as a CORRECTION — then sell from " +
      "inventory normally. Inventing fake transactions to justify bad data pollutes the books.\n\n" +
      "Ask the user to pick the category from get_project_budget_categories BEFORE calling — one " +
      "category per batch. Shape fields (amountCents, itemIds, budgetCategoryId, projectId, type, " +
      "source) are frozen at creation. Cap: 100 items per call.\n\n" +
      "PRICING: amountCents/subtotalCents are derived from each item's projectPriceCents (the " +
      "client-charged price) — NOT purchasePriceCents (cost). Every item must have a non-null, " +
      "non-zero projectPriceCents; the call fails with the offending IDs otherwise.",
    {
      itemIds: z
        .array(z.string())
        .min(1)
        .max(MAX_BATCH_ITEMS)
        .describe(`Item document IDs to sell from inventory (max ${MAX_BATCH_ITEMS} per call). Every item must currently be in business inventory (projectId == null).`),
      destinationProjectId: z.string().describe("Destination project ID — where items will land."),
      budgetCategoryId: z
        .string()
        .describe(
          "Budget category in destinationProjectId — required, applies to the whole batch. Ask the user to pick from get_project_budget_categories."
        ),
      notes: z
        .string()
        .optional()
        .describe(
          "Optional prose describing the sale (e.g. 'Sold 5 fixtures into Witzenman — client approved selections'). Free-form. The Purchase transaction's createdAt/createdBy + lineage edges are the audit trail."
        ),
      dryRun: z
        .boolean()
        .default(false)
        .describe("If true, compute and return the sale plan without writing anything."),
    },
    withTelemetry(
      "sell_items_from_inventory_to_project",
      async ({ itemIds, destinationProjectId, budgetCategoryId, notes, dryRun }) => {
        const inventoryLabel = await resolveInventoryLabel(db);

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

        const notInInventory = items.filter((i) => i.projectId);
        if (notInInventory.length > 0) {
          return validation(
            `${notInInventory.length} item(s) are not in business inventory: ${notInInventory.map((i) => i.id).join(", ")}`,
            "For items currently in a project, use sell_items_from_project_to_project or sell_items_from_project_to_inventory."
          );
        }

        const catError = await validateCategoryInProject(
          db,
          destinationProjectId,
          budgetCategoryId
        );
        if (catError) return catError;

        const missingPrice = missingProjectPrice(items);
        if (missingPrice.length > 0) return missingProjectPriceError(missingPrice);

        const { subtotalCents, amountCents, missingTax } = computeBatchTotals(items);
        if (dryRun) {
          return asToolResponse({
            dryRun: true,
            direction: "inventoryToProject",
            plan: {
              purchaseTransaction: {
                type: "Purchase" as const,
                source: inventoryLabel,
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
                  currentSource: inventoryLabel,
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
        return await commitSellToProject(db, items, destinationProjectId, budgetCategoryId, {
          subtotalCents,
          amountCents,
          missingTax,
          notes,
          inventoryLabel,
        });
      }
    )
  );

  // ── sell_items_from_project_to_inventory ───────────────────────────────────
  server.tool(
    "sell_items_from_project_to_inventory",
    "[event] Sell project items into business inventory (the business is acquiring items that " +
      "originated in the project). Creates ONE new immutable Sale transaction against " +
      "sourceProjectId, decreasing that project's budget. Items land in inventory with projectId " +
      "and budgetCategoryId cleared.\n\n" +
      "ORIGIN REQUIREMENT: every item must have originated in the source project (currentSource == " +
      "source). Items that previously passed through inventory are going HOME — use return_items " +
      "(returnTo: 'inventory') for those, not this tool.\n\n" +
      "REAL EVENT vs CORRECTION: This records a real business event. For data-entry mistakes (item " +
      "logged against the wrong project), use `bulk_update_items` with `projectId: null` to relocate " +
      "without creating a transaction.\n\n" +
      "Shape fields (amountCents, itemIds, projectId, type, source) are frozen at creation. " +
      "Cap: 100 items per call. PRICING: same projectPriceCents rule as sell_items_from_inventory_to_project.",
    {
      itemIds: z
        .array(z.string())
        .min(1)
        .max(MAX_BATCH_ITEMS)
        .describe(`Item document IDs to sell into inventory (max ${MAX_BATCH_ITEMS} per call). Every item must currently be in sourceProjectId AND have originated there.`),
      sourceProjectId: z
        .string()
        .describe("Source project ID — where items are coming from. Must match every item's current projectId."),
      notes: z
        .string()
        .optional()
        .describe(
          "Optional prose describing the sale (e.g. 'Acquiring leftover sconces from Witzenman into inventory'). Free-form. createdAt/createdBy + lineage edges are the audit trail."
        ),
      dryRun: z
        .boolean()
        .default(false)
        .describe("If true, compute and return the sale plan without writing anything."),
    },
    withTelemetry(
      "sell_items_from_project_to_inventory",
      async ({ itemIds, sourceProjectId, notes, dryRun }) => {
        const inventoryLabel = await resolveInventoryLabel(db);

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

        const wrongProject = items.filter((i) => i.projectId !== sourceProjectId);
        if (wrongProject.length > 0) {
          return validation(
            `${wrongProject.length} item(s) are not in project ${sourceProjectId}: ${wrongProject.map((i) => i.id).join(", ")}`,
            "Every item must currently be in sourceProjectId."
          );
        }
        const fromInventory = items.filter((i) => cameFromInventory(i));
        if (fromInventory.length > 0) {
          return validation(
            `${fromInventory.length} item(s) previously passed through inventory (currentSource != source): ${fromInventory.map((i) => i.id).join(", ")}. These must go via return_items (Return), not sell_items_from_project_to_inventory.`,
            "Use return_items with returnTo: 'inventory' for from-inventory items. sell_items_from_project_to_inventory is reserved for items that originated in the project."
          );
        }

        const missingPrice = missingProjectPrice(items);
        if (missingPrice.length > 0) return missingProjectPriceError(missingPrice);

        const { subtotalCents, amountCents, missingTax } = computeBatchTotals(items);
        if (dryRun) {
          return asToolResponse({
            dryRun: true,
            direction: "projectToInventory",
            plan: {
              saleTransaction: {
                type: "Sale" as const,
                source: inventoryLabel,
                projectId: sourceProjectId,
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
                  currentSource: inventoryLabel,
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
        return await commitSellToInventory(db, items, sourceProjectId, {
          subtotalCents,
          amountCents,
          missingTax,
          notes,
          inventoryLabel,
        });
      }
    )
  );

  // ── return_items ────────────────────────────────────────────────────────────
  server.tool(
    "return_items",
    "[event] Return items. A Return is for items going HOME — either back to the vendor they came " +
      "from, or back to business inventory (if they previously came from inventory).\n\n" +
      "• returnTo: 'vendor' — attaches items to an existing vendor Return transaction. Create the " +
      "Return transaction first via create_transaction (type: 'Return'), then pass its ID as " +
      "returnTransactionId.\n\n" +
      "• returnTo: 'inventory' — moves items from their current project back to business inventory. " +
      "ORIGIN REQUIREMENT: every item must have previously passed through inventory " +
      "(currentSource != source). Items that originated in the project and have never been in " +
      "inventory before are NOT a return. For those, decide: was it a real business event " +
      "(business is genuinely acquiring the items for the first time)? → " +
      "sell_items_from_project_to_inventory. Or was it a data-entry mistake (the item should never " +
      "have been logged against the project)? → bulk_update_items with projectId: null " +
      "(corrections doctrine). Creates a new Return transaction with source: 'Business Inventory' " +
      "(or appends to one if returnTransactionId is provided). Items have budgetCategoryId and " +
      "projectId cleared.\n\n" +
      "REAL EVENT vs CORRECTION: This records a real business event. For data-entry mistakes " +
      "(wrong project, wrong vendor on the original record), use `bulk_update_items` to relocate " +
      "items without creating a Return transaction.\n\n" +
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
        const inventoryLabel = await resolveInventoryLabel(db);

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
        // project go via sell_items_from_project_to_inventory.
        if (returnTo === "inventory") {
          const originated = items.filter((i) => !cameFromInventory(i));
          if (originated.length > 0) {
            return validation(
              `${originated.length} item(s) originated in their current project (currentSource == source) — these are NOT a return: ${originated.map((i) => i.id).join(", ")}.`,
              "Decide first: REAL EVENT (business genuinely acquiring these for the first time) → " +
                "sell_items_from_project_to_inventory. CORRECTION (the item should never have been " +
                "logged against the project) → bulk_update_items with projectId: null. return_items " +
                "(returnTo: 'inventory') is reserved for items going HOME to inventory."
            );
          }
          const missingPrice = missingProjectPrice(items);
          if (missingPrice.length > 0) return missingProjectPriceError(missingPrice);
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
                        currentSource: inventoryLabel,
                      }
                    : { status: "returned" },
                from: { transactionId: i.transactionId ?? null },
              })),
              lineageEdges: items.length,
            },
          });
        }

        if (returnTo === "inventory") {
          return await commitReturnToInventory(db, items, existingReturnTx, notes, inventoryLabel);
        }
        return await commitReturnToVendor(db, items, existingReturnTx!, notes);
      }
    )
  );

  // ── sell_items_from_project_to_project ─────────────────────────────────────
  server.tool(
    "sell_items_from_project_to_project",
    "[event] Sell items from one project directly to another (items physically moved between project " +
      "sites; budgets shift accordingly). Implemented as an origin-aware two-hop atomic batch:\n\n" +
      "  FIRST HOP (per-item, origin-aware):\n" +
      "   • Items that previously passed through inventory (currentSource != source) → a Return " +
      "transaction against the source project.\n" +
      "   • Items that originated in the source project (currentSource == source) → a Sale-to-Inventory " +
      "transaction (type: 'Sale', no budgetCategoryId) against the source project.\n" +
      "   • Mixed batches produce BOTH first-hop transactions in the same Firestore batch.\n\n" +
      "  SECOND HOP: one Purchase-from-Inventory transaction (type: 'Purchase', with budgetCategoryId) " +
      "against the destination project, covering every item in the batch.\n\n" +
      "REAL EVENT vs CORRECTION: This records real financial movement — NOT a silent bookkeeping " +
      "repoint. For data-entry mistakes (item logged on the wrong project from the start), use " +
      "`bulk_update_items` to relocate without creating Sale/Return transactions.\n\n" +
      "All items must be in the same source project. Cap: 100 items per call. One destination category " +
      "applies to the whole batch — ask the user to pick from get_project_budget_categories before " +
      "calling. Source and destination must differ.\n\n" +
      "DO NOT use this as a shortcut for 'the item was entered on the wrong transaction but still belongs " +
      "to the same project' — that's a reassignment, use update_item to move the item to the correct " +
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
      "sell_items_from_project_to_project",
      async ({
        itemIds,
        destinationProjectId,
        destinationBudgetCategoryId,
        notes,
        dryRun,
      }) => {
        const inventoryLabel = await resolveInventoryLabel(db);

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
            "Use sell_items_from_inventory_to_project for items currently in business inventory."
          );
        }

        const sourceProjects = new Set(items.map((i) => i.projectId!));
        if (sourceProjects.size > 1) {
          return validation(
            `Items span multiple source projects (${[...sourceProjects].join(", ")}). sell_items_from_project_to_project handles one source project per call.`,
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

        const missingPrice = missingProjectPrice(items);
        if (missingPrice.length > 0) return missingProjectPriceError(missingPrice);

        const split = splitByOrigin(items);
        const { subtotalCents, amountCents, missingTax } = computeBatchTotals(items);

        if (dryRun) {
          const returnLeg =
            split.returnItems.length > 0
              ? {
                  type: "Return" as const,
                  source: inventoryLabel,
                  projectId: sourceProjectId,
                  amountCents: split.returnItems.reduce(
                    (sum, i) => sum + (i.projectPriceCents ?? 0),
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
                    source: inventoryLabel,
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
                purchaseFromInventory: {
                  type: "Purchase" as const,
                  source: inventoryLabel,
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
                  currentSource: inventoryLabel,
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
          { subtotalCents, amountCents, missingTax, notes, inventoryLabel }
        );
      }
    )
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// commit: sell_items_from_inventory_to_project
// ─────────────────────────────────────────────────────────────────────────────

async function commitSellToProject(
  db: Firestore,
  items: (Item & { id: string })[],
  destinationProjectId: string,
  budgetCategoryId: string,
  totals: { subtotalCents: number; amountCents: number; missingTax: string[]; notes?: string; inventoryLabel: string }
) {
  const frozen = await frozenSourceTxIds(db, items);

  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  // 1. New Purchase transaction (frozen shape).
  const purchaseRef = txCol.doc();
  batch.set(purchaseRef, {
    type: "Purchase",
    source: totals.inventoryLabel,
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
      transactionId: purchaseRef.id,
      spaceId: null,
      currentSource: totals.inventoryLabel,
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
      toTransactionId: purchaseRef.id,
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
          `Purchased ${items.length} item(s) from inventory into project ${destinationProjectId}.\n` +
          `New Purchase transaction: ${purchaseRef.id}\n` +
          `amountCents: ${totals.amountCents} (${formatCents(totals.amountCents)})\n` +
          `budgetCategoryId: ${budgetCategoryId}` +
          missingTaxWarning(totals.missingTax, items.length),
      },
    ],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// commit: sell_items_from_project_to_inventory (Sale-to-Inventory)
// ─────────────────────────────────────────────────────────────────────────────

async function commitSellToInventory(
  db: Firestore,
  items: (Item & { id: string })[],
  sourceProjectId: string,
  totals: { subtotalCents: number; amountCents: number; missingTax: string[]; notes?: string; inventoryLabel: string }
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
    source: totals.inventoryLabel,
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
      currentSource: totals.inventoryLabel,
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
  notes: string | undefined,
  inventoryLabel: string
) {
  const frozen = await frozenSourceTxIds(db, items);

  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  // Return amount uses projectPriceCents (the client-charged price that hit
  // the project's budget on the way in). Caller validated every item has a
  // non-null, non-zero projectPriceCents before reaching this commit.
  const returnAmount = items.reduce((sum, i) => sum + (i.projectPriceCents ?? 0), 0);
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
      source: inventoryLabel,
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
      currentSource: inventoryLabel,
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
// commit: sell_items_from_project_to_project, origin-aware two-hop
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
  totals: { subtotalCents: number; amountCents: number; missingTax: string[]; notes?: string; inventoryLabel: string }
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
      (sum, i) => sum + (i.projectPriceCents ?? 0),
      0
    );
    batch.set(returnRef, {
      type: "Return",
      source: totals.inventoryLabel,
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
      source: totals.inventoryLabel,
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

  // 2. Second hop — Purchase-from-Inventory (destination) covers every item.
  const destPurchaseRef = txCol.doc();
  batch.set(destPurchaseRef, {
    type: "Purchase",
    source: totals.inventoryLabel,
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
      transactionId: destPurchaseRef.id,
      spaceId: null,
      currentSource: totals.inventoryLabel,
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
      toTransactionId: destPurchaseRef.id,
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
  legs.push(`Purchase-from-Inventory (destination): ${destPurchaseRef.id}`);

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
