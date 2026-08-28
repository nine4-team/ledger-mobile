import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, type WriteBatch, FieldValue } from "firebase-admin/firestore";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { Invoice, InvoiceLine, Item, LineageEdge, Transaction } from "../types.js";
import { accountCollection, accountPath, subcollection, getDoc, queryDocs } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { notFound, validation } from "../util/errors.js";
import { tagNotesAsAi } from "../util/notes.js";
import { asToolResponse } from "../util/projections.js";
import { withTelemetry } from "../util/telemetry.js";
import { getUid } from "../context.js";
import { DEFAULT_INVENTORY_LABEL, resolveInventoryLabel } from "../util/inventory.js";
import { isReturnTransactionType } from "../util/enums.js";
import {
  validateDestinationSpaceAssignments,
  type DestinationSpaceAssignment,
} from "../util/space-assignments.js";
import { effectiveProjectPriceCents } from "../util/item-pricing.js";

// ─────────────────────────────────────────────────────────────────────────────
// MCP-side implementation of the per-batch inventory movement spec at
// docs/specs/sale-transactions.md. Mirrors
// LedgeriOS/Services/InventoryOperationsService.swift.
//
// Key invariants (also enforced by Firestore rules):
//   • Each inventory movement creates at least one new Purchase, Sale, or
//     Return transaction with an auto-ID. Structural fields (budgetCategoryId,
//     type, source, projectId) are frozen at creation, and clients cannot edit
//     totals directly. The trusted price trigger maintains an eligible unpaid
//     project-side Purchase when an attached sold item is repriced. itemIds
//     tracks current active membership.
//   • Inventory movement direction is derived from transaction shape:
//        - inventory → project: Purchase with `budgetCategoryId` set.
//        - project → inventory acquisition: Sale with source-category `budgetCategoryId`.
//   • Return is RESERVED for items going HOME to inventory — i.e., items
//     whose current Purchase or lineage proves they passed through inventory.
//     Items that originated in a project and are moving to inventory are a
//     Sale-to-Inventory, NOT a Return.
//   • Items in business inventory (projectId == null) have
//     budgetCategoryId == null.
//   • Batch cap: 100 items per operation.
// ─────────────────────────────────────────────────────────────────────────────

const MAX_BATCH_ITEMS = 100;
const INVENTORY_LABEL = DEFAULT_INVENTORY_LABEL;

const destinationSpaceAssignmentsSchema = z
  .array(z.object({
    itemId: z.string().describe("Item ID from this sale."),
    spaceId: z.string().describe("Space ID in the destination project."),
  }))
  .max(MAX_BATCH_ITEMS)
  .optional()
  .describe(
    "Optional per-item destination spaces. Each space must exist and belong to destinationProjectId. Items omitted here land unassigned."
  );

function projectPriceForMovement(item: Item): number {
  return effectiveProjectPriceCents(item);
}

/**
 * Resolve a project-price snapshot for an inventory→project charge or the
 * inventory-originated Return that reverses it.
 */
function computeProjectPriceTotals(items: (Item & { id: string })[]): {
  subtotalCents: number;
  amountCents: number;
  missingTax: string[];
} {
  let subtotalCents = 0;
  let amountCents = 0;
  const missingTax: string[] = [];
  for (const item of items) {
    const price = projectPriceForMovement(item);
    const rate = item.taxRatePct ?? 0;
    subtotalCents += price;
    amountCents += rate > 0 ? Math.round(price * (1 + rate / 100)) : price;
    if (item.taxRatePct == null) missingTax.push(item.id);
  }
  return { subtotalCents, amountCents, missingTax };
}

/**
 * Reverse an inventory→project sale at the value the project originally paid.
 *
 * This is only for inventory-originated items going home. Project-originated
 * items entering inventory are business acquisitions and use
 * computeProjectOriginAcquisitionTotals instead.
 */
export function computeProjectToInventoryTotals(items: (Item & { id: string })[]): {
  subtotalCents: number;
  amountCents: number;
  missingTax: string[];
} {
  return computeProjectPriceTotals(items);
}

/** Business acquisition value for project-originated items entering inventory. */
export function computeProjectOriginAcquisitionTotals(items: (Item & { id: string })[]): {
  subtotalCents: number;
  amountCents: number;
  missingTax: string[];
} {
  const subtotalCents = items.reduce((sum, item) => sum + (item.purchasePriceCents ?? 0), 0);
  return { subtotalCents, amountCents: subtotalCents, missingTax: [] };
}

function inventoryCreditPreviews(items: (Item & { id: string })[]) {
  return items.map((item) => {
    const totals = computeProjectToInventoryTotals([item]);
    return {
      itemId: item.id,
      name: item.name ?? null,
      priceBasis: "projectPriceCents" as const,
      projectPriceCents: projectPriceForMovement(item),
      creditSubtotalCents: totals.subtotalCents,
      creditAmountCents: totals.amountCents,
    };
  });
}

function acquisitionCreditPreviews(items: (Item & { id: string })[]) {
  return items.map((item) => {
    const creditCents = item.purchasePriceCents ?? 0;
    return {
      itemId: item.id,
      name: item.name ?? null,
      priceBasis: "purchasePriceCents" as const,
      purchasePriceCents: creditCents,
      creditSubtotalCents: creditCents,
      creditAmountCents: creditCents,
    };
  });
}

type ReturnedPaidItemCreditContext = {
  itemId: string;
  itemName: string;
  projectId: string;
  amountCents: number;
  budgetCategoryId: string;
  paidInvoiceId: string;
  paidInvoiceLineId: string;
  lineId: string;
};

function returnedPaidItemCreditLineId(paidInvoiceId: string, paidInvoiceLineId: string, itemId: string) {
  return `returnCredit:${paidInvoiceId}:${paidInvoiceLineId}:${itemId}`;
}

function invoiceDateMillis(invoice: Invoice) {
  const value = invoice.datePaid ?? invoice.dateSent ?? invoice.dateIssued ?? invoice.createdAt;
  if (!value) return 0;
  if (value instanceof Date) return value.getTime();
  if (typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
    return value.toDate().getTime();
  }
  return 0;
}

async function returnedPaidItemCreditContexts(
  db: Firestore,
  items: (Item & { id: string })[]
): Promise<ReturnedPaidItemCreditContext[]> {
  const selected = new Map(items.map((item) => [item.id, item]));
  if (!selected.size) return [];

  const projectIds = [...new Set(items.map((item) => item.projectId).filter((id): id is string => Boolean(id)))];
  const allInvoices: (Invoice & { id: string })[] = [];
  for (const projectId of projectIds) {
    const invoices = await queryDocs<Invoice>(accountCollection(db, "invoices").where("projectId", "==", projectId));
    allInvoices.push(...invoices);
  }

  const existingCreditLineIds = new Set<string>();
  for (const invoice of allInvoices) {
    if (invoice.status === "canceled") continue;
    for (const line of invoice.lines ?? []) {
      if (line.id?.startsWith("returnCredit:")) existingCreditLineIds.add(line.id);
    }
  }

  const candidatesByItemId = new Map<string, { invoice: Invoice & { id: string }; line: InvoiceLine; item: Item & { id: string }; lineId: string }[]>();
  for (const invoice of allInvoices) {
    if (invoice.status !== "paid") continue;
    for (const line of invoice.lines ?? []) {
      if (line.sourceType !== "item") continue;
      if (line.sign !== 1) continue;
      if (!line.sourceId || !line.id) continue;
      if (!line.budgetCategoryId) continue;
      const item = selected.get(line.sourceId);
      if (!item) continue;
      const lineId = returnedPaidItemCreditLineId(invoice.id, line.id, item.id);
      if (existingCreditLineIds.has(lineId)) continue;
      const existing = candidatesByItemId.get(item.id) ?? [];
      existing.push({ invoice, line, item, lineId });
      candidatesByItemId.set(item.id, existing);
    }
  }

  return [...candidatesByItemId.entries()].sort(([a], [b]) => a.localeCompare(b)).flatMap(([, candidates]) => {
    const candidate = candidates.sort((a, b) => {
      const dateDelta = invoiceDateMillis(b.invoice) - invoiceDateMillis(a.invoice);
      if (dateDelta !== 0) return dateDelta;
      return b.invoice.id.localeCompare(a.invoice.id);
    })[0];
    if (!candidate.line.budgetCategoryId) return [];
    const projectId = candidate.item.projectId ?? candidate.invoice.projectId;
    if (!projectId) return [];
    return [{
      itemId: candidate.item.id,
      itemName: candidate.item.name ?? candidate.item.description ?? "item",
      projectId,
      amountCents: candidate.line.amountCents,
      budgetCategoryId: candidate.line.budgetCategoryId,
      paidInvoiceId: candidate.invoice.id,
      paidInvoiceLineId: candidate.line.id ?? "",
      lineId: candidate.lineId,
    }];
  });
}

function appendReturnedPaidItemCreditDrafts(
  batch: WriteBatch,
  db: Firestore,
  credits: ReturnedPaidItemCreditContext[],
  uid: string
) {
  if (!credits.length) return [];
  const byProject = new Map<string, ReturnedPaidItemCreditContext[]>();
  for (const credit of credits) {
    const existing = byProject.get(credit.projectId) ?? [];
    existing.push(credit);
    byProject.set(credit.projectId, existing);
  }

  const invoiceIds: string[] = [];
  const now = FieldValue.serverTimestamp();
  for (const [projectId, projectCredits] of byProject.entries()) {
    const invoiceRef = accountCollection(db, "invoices").doc(randomUUID());
    invoiceIds.push(invoiceRef.id);
    const lines = projectCredits
      .sort((a, b) => a.lineId.localeCompare(b.lineId))
      .map((credit) => ({
        id: credit.lineId,
        sourceType: "manual",
        amountCents: credit.amountCents,
        sign: -1,
        budgetCategoryId: credit.budgetCategoryId,
        snapshotName: `Credit: returned ${credit.itemName}`,
      }));
    batch.set(invoiceRef, {
      accountId: accountPath().split("/")[1],
      projectId,
      status: "created",
      itemIds: [],
      transactionIds: [],
      lines,
      notes: "Credit for paid item(s) returned to inventory.",
      dateIssued: now,
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
      updatedBy: uid,
    });
  }
  return invoiceIds;
}

/**
 * Return the ids of items that have neither a usable project price nor a
 * purchase price that can initialize it.
 */
function missingProjectPrice(items: (Item & { id: string })[]): string[] {
  return items
    .filter((i) => projectPriceForMovement(i) <= 0)
    .map((i) => i.id);
}

function missingProjectPriceError(ids: string[]) {
  return validation(
    `${ids.length} item(s) have neither a project price nor a purchase price: ${ids.join(", ")}.`,
    "Set projectPriceCents or purchasePriceCents on each listed item before retrying. " +
      "When only purchasePriceCents is present, Ledger initializes projectPriceCents to that value."
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

/** Resolved origin with the evidence that selected the financial path. */
type ItemOriginResolution = {
  itemId: string;
  origin: "inventory" | "project" | "unresolved";
  evidence: {
    kind: "currentTransaction" | "lineage" | "metadata" | "none";
    detail: string;
    transactionId?: string;
    lineageEdgeId?: string;
  };
};

function dateMillis(value: unknown): number {
  if (value instanceof Date) return value.getTime();
  if (value && typeof value === "object" && "toMillis" in value && typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (value && typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
    return value.toDate().getTime();
  }
  return 0;
}

function isInventoryLabel(source: string | undefined): boolean {
  return Boolean(source?.trim().endsWith(" Inventory"));
}

async function resolveItemOrigin(
  db: Firestore,
  item: Item & { id: string }
): Promise<ItemOriginResolution> {
  if (item.transactionId) {
    const transaction = await getDoc<Transaction>(db, "transactions", item.transactionId);
    const type = transaction?.type?.trim().toLowerCase();
    if (transaction && transaction.projectId === item.projectId && type === "purchase") {
      const inventoryOrigin = isInventoryLabel(transaction.source);
      return {
        itemId: item.id,
        origin: inventoryOrigin ? "inventory" : "project",
        evidence: {
          kind: "currentTransaction",
          transactionId: item.transactionId,
          detail: inventoryOrigin
            ? `Current Purchase source '${transaction.source}' is an inventory label.`
            : `Current Purchase source '${transaction.source ?? ""}' is not an inventory label.`,
        },
      };
    }
  }

  const edges = await queryDocs<LineageEdge>(
    accountCollection(db, "lineageEdges").where("itemId", "==", item.id)
  );
  const inventoryEntries = edges
    .filter((edge) => edge.movementKind === "sold" && edge.toProjectId === item.projectId)
    .sort((a, b) => dateMillis(b.createdAt) - dateMillis(a.createdAt));
  if (inventoryEntries[0]) {
    return {
      itemId: item.id,
      origin: "inventory",
      evidence: {
        kind: "lineage",
        lineageEdgeId: inventoryEntries[0].id,
        detail: `Sold lineage enters current project ${item.projectId}.`,
      },
    };
  }

  const current = (item.currentSource ?? "").trim();
  const original = (item.source ?? "").trim();
  if (current && original) {
    const inventoryOrigin = current !== original;
    return {
      itemId: item.id,
      origin: inventoryOrigin ? "inventory" : "project",
      evidence: {
        kind: "metadata",
        detail: inventoryOrigin
          ? `Fallback only: currentSource '${current}' differs from source '${original}'.`
          : `Fallback only: currentSource matches source '${original}'.`,
      },
    };
  }

  return {
    itemId: item.id,
    origin: "unresolved",
    evidence: {
      kind: "none",
      detail: "No authoritative Purchase, inventory-entry lineage, or complete source metadata.",
    },
  };
}

async function resolveItemOrigins(
  db: Firestore,
  items: (Item & { id: string })[]
): Promise<Map<string, ItemOriginResolution>> {
  const resolutions = await Promise.all(items.map((item) => resolveItemOrigin(db, item)));
  return new Map(resolutions.map((resolution) => [resolution.itemId, resolution]));
}

function unresolvedOriginError(resolutions: ItemOriginResolution[]) {
  return validation(
    `${resolutions.length} item origin(s) could not be resolved safely: ${resolutions.map((resolution) => resolution.itemId).join(", ")}.`,
    "Repair or backfill transaction/lineage provenance before retrying. Ledger will not guess whether these are Returns or business acquisitions."
  );
}

function splitByResolvedOrigin(
  items: (Item & { id: string })[],
  origins: Map<string, ItemOriginResolution>
): {
  returnItems: (Item & { id: string })[];
  saleItems: (Item & { id: string })[];
} {
  return {
    returnItems: items.filter((item) => origins.get(item.id)?.origin === "inventory"),
    saleItems: items.filter((item) => origins.get(item.id)?.origin === "project"),
  };
}

function sourceCategoryGroups(items: (Item & { id: string })[]): Array<{
  budgetCategoryId: string;
  items: (Item & { id: string })[];
}> {
  const order: string[] = [];
  const groups = new Map<string, (Item & { id: string })[]>();
  for (const item of items) {
    const categoryId = item.budgetCategoryId?.trim();
    if (!categoryId) {
      throw new Error(
        `Item ${item.id} is missing budgetCategoryId; source-project egress requires a source category.`
      );
    }
    if (!groups.has(categoryId)) {
      order.push(categoryId);
      groups.set(categoryId, []);
    }
    groups.get(categoryId)!.push(item);
  }
  return order.map((budgetCategoryId) => ({
    budgetCategoryId,
    items: groups.get(budgetCategoryId)!,
  }));
}

function missingSourceBudgetCategory(items: (Item & { id: string })[]): string[] {
  return items
    .filter((item) => !item.budgetCategoryId?.trim())
    .map((item) => item.id);
}

function missingSourceBudgetCategoryError(ids: string[]) {
  return validation(
    `${ids.length} source item(s) are missing budgetCategoryId: ${ids.join(", ")}.`,
    "Correct the item/category before selling or returning it out of the source project."
  );
}

/**
 * Source transaction itemIds now represent active membership for every
 * transaction type. Kept as a compatibility shim for older call sites that
 * still pass a "frozen" set into applyArrayRemoves.
 */
async function frozenSourceTxIds(
  db: Firestore,
  items: (Item & { id: string })[]
): Promise<Set<string>> {
  void db;
  void items;
  return new Set<string>();
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
    "[event] Sell items from business inventory into a project. Creates ONE new Purchase " +
      "transaction (source: Business Inventory) against destinationProjectId, increasing that " +
      "project's budget under budgetCategoryId. Every item must currently be in business inventory " +
      "(projectId == null).\n\n" +
      "REAL EVENT vs CORRECTION: This records a real business event (money changes hands, budgets " +
      "move). Do NOT use it merely because a categorized project item has no transaction; that is a " +
      "valid correction/work-queue state until the proper transaction exists. Inventing fake transactions " +
      "to justify bad data pollutes the books.\n\n" +
      "Ask the user to pick the category from get_project_budget_categories BEFORE calling — one " +
      "category per batch. Structural fields (budgetCategoryId, projectId, type, source) are frozen; " +
      "clients cannot edit totals directly. Eligible sold-item project-price changes update this " +
      "project Purchase automatically. itemIds tracks active membership. Cap: 100 items per call.\n\n" +
      "SPACE ASSIGNMENTS: destinationSpaceAssignments may restore selected per-item assignments " +
      "captured during correction. Every supplied space is validated against the destination project; " +
      "omitted items land unassigned.\n\n" +
      "NAME PRESERVATION: this movement updates the existing physical item documents in place and never " +
      "changes their names. Identical names across multiple items remain identical.\n\n" +
      "PRICING: amountCents/subtotalCents are derived from each item's normalized projectPriceCents " +
      "(the client-charged price). Ledger raises projectPriceCents to purchasePriceCents whenever it " +
      "is missing, zero, or lower, and persists that value atomically. The call fails " +
      "only when neither price is available.",
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
      destinationSpaceAssignments: destinationSpaceAssignmentsSchema,
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
      async ({ itemIds, destinationProjectId, budgetCategoryId, destinationSpaceAssignments, notes, dryRun }) => {
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

        const resolvedSpaces = await validateDestinationSpaceAssignments(
          db,
          itemIds,
          destinationProjectId,
          destinationSpaceAssignments as DestinationSpaceAssignment[] | undefined
        );
        if (!resolvedSpaces.ok) {
          return validation(resolvedSpaces.issue.message, resolvedSpaces.issue.guidance);
        }

        const missingPrice = missingProjectPrice(items);
        if (missingPrice.length > 0) return missingProjectPriceError(missingPrice);

        const { subtotalCents, amountCents, missingTax } = computeProjectPriceTotals(items);
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
                  spaceId: resolvedSpaces.byItemId.get(i.id) ?? null,
                  currentSource: inventoryLabel,
                  projectPriceCents: projectPriceForMovement(i),
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
        return await commitSellToProject(db, items, destinationProjectId, budgetCategoryId, resolvedSpaces.byItemId, {
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
      "originated in the project). Creates ONE new Sale transaction against " +
      "sourceProjectId, decreasing that project's budget. Items land in inventory with projectId " +
      "and budgetCategoryId cleared.\n\n" +
      "ORIGIN REQUIREMENT: every item must have project-origin provenance. The current project " +
      "Purchase is authoritative when available; lineage is checked next and source metadata is " +
      "only a fallback. Items that previously passed through inventory are going HOME — use return_items " +
      "(returnTo: 'inventory') for those, not this tool.\n\n" +
      "REAL EVENT vs CORRECTION: This records a real business event. For data-entry mistakes (item " +
      "logged against the wrong project), use `bulk_update_items` with `projectId: null` to relocate " +
      "without creating a transaction.\n\n" +
      "NAME PRESERVATION: this movement updates existing item documents in place and never changes " +
      "their names, including when several physical items share the same name.\n\n" +
      "Accounting fields (amountCents, budgetCategoryId, projectId, type, source) are frozen at creation. " +
      "Cap: 100 items per call. PRICING: this is a true business acquisition, so amountCents/subtotalCents use purchasePriceCents even if projectPriceCents is higher.",
    {
      itemIds: z
        .array(z.string())
        .min(1)
        .max(MAX_BATCH_ITEMS)
        .describe(`Item document IDs to sell into inventory (max ${MAX_BATCH_ITEMS} per call). Every item must currently be in sourceProjectId and have project-origin provenance.`),
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
        const origins = await resolveItemOrigins(db, items);
        const unresolved = [...origins.values()].filter((resolution) => resolution.origin === "unresolved");
        if (unresolved.length > 0) return unresolvedOriginError(unresolved);
        const fromInventory = items.filter((item) => origins.get(item.id)?.origin === "inventory");
        if (fromInventory.length > 0) {
          return validation(
            `${fromInventory.length} item(s) have inventory-entry provenance: ${fromInventory.map((i) => i.id).join(", ")}. These must go via return_items (Return), not sell_items_from_project_to_inventory.`,
            "Use return_items with returnTo: 'inventory' for from-inventory items. sell_items_from_project_to_inventory is reserved for items that originated in the project."
          );
        }
        const missingSourceCategory = missingSourceBudgetCategory(items);
        if (missingSourceCategory.length > 0) {
          return missingSourceBudgetCategoryError(missingSourceCategory);
        }

        const { subtotalCents, amountCents, missingTax } = computeProjectOriginAcquisitionTotals(items);
        if (dryRun) {
          const saleTransactions = sourceCategoryGroups(items).map((group) => {
            const totals = computeProjectOriginAcquisitionTotals(group.items);
            return {
              type: "Sale" as const,
              source: inventoryLabel,
              projectId: sourceProjectId,
              budgetCategoryId: group.budgetCategoryId,
              amountCents: totals.amountCents,
              subtotalCents: totals.subtotalCents,
              itemIds: group.items.map((i) => i.id),
            };
          });
          return asToolResponse({
            dryRun: true,
            direction: "projectToInventory",
            plan: {
              saleTransactions,
              credits: acquisitionCreditPreviews(items).map((credit) => ({
                ...credit,
                origin: origins.get(credit.itemId)?.origin,
                originEvidence: origins.get(credit.itemId)?.evidence,
              })),
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
            totals: { amountCents, subtotalCents },
            warning: null,
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
      "ORIGIN REQUIREMENT: every item must have transaction or lineage proof that it previously passed through inventory. " +
      "Items that originated in the project and have never been in " +
      "inventory before are NOT a return. For those, decide: was it a real business event " +
      "(business is genuinely acquiring the items for the first time)? → " +
      "sell_items_from_project_to_inventory. Or was it a data-entry mistake (the item should never " +
      "have been logged against the project)? → bulk_update_items with projectId: null " +
      "(corrections doctrine). Creates a new per-batch Return transaction with source: " +
      "'Business Inventory'. Items have budgetCategoryId and " +
      "projectId cleared.\n\n" +
      "REAL EVENT vs CORRECTION: This records a real business event. For data-entry mistakes " +
      "(wrong project, wrong vendor on the original record), use `bulk_update_items` to relocate " +
      "items without creating a Return transaction.\n\n" +
      "NAME PRESERVATION: return/movement updates never rename existing item documents. Duplicate " +
      "names remain valid and unchanged.\n\n" +
      "PRICING: returnTo: 'inventory' always reverses normalized projectPriceCents (including " +
      "recorded per-item tax), never purchasePriceCents. The dry-run lists each credit and its basis.\n\n" +
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
            "(new per-batch Return tx with the inventory source label — items must have come from inventory originally)"
        ),
      returnTransactionId: z
        .string()
        .optional()
        .describe(
          "When returnTo is 'vendor': REQUIRED existing Return transaction ID. " +
            "When returnTo is 'inventory': omit this field; inventory returns always create a new per-batch Return transaction."
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
        if (returnTo === "inventory" && returnTransactionId) {
          return validation(
            "returnTransactionId cannot be used when returnTo is 'inventory'.",
            "Omit returnTransactionId. Inventory returns always create a new per-batch Return transaction with frozen accounting fields."
          );
        }

        let existingReturnTx: (Transaction & { id: string }) | null = null;
        if (returnTransactionId) {
          existingReturnTx = await getDoc<Transaction>(db, "transactions", returnTransactionId);
          if (!existingReturnTx) return notFound("Return transaction", returnTransactionId);
          if (!isReturnTransactionType(existingReturnTx.type)) {
            return validation(
              `Transaction ${returnTransactionId} is type '${existingReturnTx.type}', not 'Return'.`,
              "Pass an existing vendor Return transaction. Inventory returns create their own per-batch Return transaction."
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
          const origins = await resolveItemOrigins(db, items);
          const unresolved = [...origins.values()].filter((resolution) => resolution.origin === "unresolved");
          if (unresolved.length > 0) return unresolvedOriginError(unresolved);
          const originated = items.filter((item) => origins.get(item.id)?.origin === "project");
          if (originated.length > 0) {
            return validation(
              `${originated.length} item(s) have project-origin provenance — these are NOT a return: ${originated.map((i) => i.id).join(", ")}.`,
              "Decide first: REAL EVENT (business genuinely acquiring these for the first time) → " +
                "sell_items_from_project_to_inventory. CORRECTION (the item should never have been " +
                "logged against the project) → bulk_update_items with projectId: null. return_items " +
                "(returnTo: 'inventory') is reserved for items going HOME to inventory."
            );
          }
          const missingSourceCategory = missingSourceBudgetCategory(items);
          if (missingSourceCategory.length > 0) {
            return missingSourceBudgetCategoryError(missingSourceCategory);
          }
        }

        if (dryRun) {
          const origins = returnTo === "inventory" ? await resolveItemOrigins(db, items) : new Map<string, ItemOriginResolution>();
          const returnTransactions =
            returnTo === "inventory"
              ? sourceCategoryGroups(items).map((group) => {
                  const totals = computeProjectToInventoryTotals(group.items);
                  return {
                    type: "Return" as const,
                    source: inventoryLabel,
                    projectId: group.items[0]?.projectId ?? null,
                    budgetCategoryId: group.budgetCategoryId,
                    amountCents: totals.amountCents,
                    subtotalCents: totals.subtotalCents,
                    itemIds: group.items.map((i) => i.id),
                  };
                })
              : [];
          const returnTotals =
            returnTo === "inventory" ? computeProjectToInventoryTotals(items) : null;
          return asToolResponse({
            dryRun: true,
            returnTo,
            existingReturnTransactionId: existingReturnTx?.id ?? null,
            willCreateNewReturnTx: returnTo === "inventory",
            plan: {
              returnTransactions,
              credits: returnTo === "inventory"
                ? inventoryCreditPreviews(items).map((credit) => ({
                    ...credit,
                    origin: origins.get(credit.itemId)?.origin,
                    originEvidence: origins.get(credit.itemId)?.evidence,
                  }))
                : [],
              itemUpdates: items.map((i) => ({
                itemId: i.id,
                name: i.name ?? null,
                set:
                  returnTo === "inventory"
                    ? {
                        status: "purchased",
                        projectId: null,
                        budgetCategoryId: null,
                        currentSource: inventoryLabel,
                      }
                    : { status: "returned" },
                from: { transactionId: i.transactionId ?? null },
              })),
              lineageEdges: items.length,
            },
            totals: returnTotals
              ? {
                  amountCents: returnTotals.amountCents,
                  subtotalCents: returnTotals.subtotalCents,
                }
              : null,
            warning: returnTotals
              ? missingTaxWarning(returnTotals.missingTax, items.length) || null
              : null,
          });
        }

        if (returnTo === "inventory") {
          return await commitReturnToInventory(db, items, notes, inventoryLabel);
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
      "   • Items with inventory-entry provenance → a Return " +
      "transaction against the source project.\n" +
      "   • Items with project-origin provenance → a Sale-to-Inventory " +
      "transaction (type: 'Sale', source-category budgetCategoryId) against the source project.\n" +
      "   • Mixed batches produce BOTH first-hop transactions in the same Firestore batch.\n\n" +
      "  SECOND HOP: one Purchase-from-Inventory transaction (type: 'Purchase', with budgetCategoryId) " +
      "against the destination project, covering every item in the batch.\n\n" +
      "PRICING: a Return first hop reverses normalized projectPriceCents; a Sale-to-Inventory first " +
      "hop uses purchasePriceCents; the destination Purchase uses normalized projectPriceCents.\n\n" +
      "REAL EVENT vs CORRECTION: This records real financial movement — NOT a silent bookkeeping " +
      "repoint. For data-entry mistakes (item logged on the wrong project from the start), use " +
      "`bulk_update_items` to relocate without creating Sale/Return transactions.\n\n" +
      "NAME PRESERVATION: both movement hops update the same item documents and never change their " +
      "names. Identically named physical records remain identically named.\n\n" +
      "All items must be in the same source project. Cap: 100 items per call. One destination category " +
      "applies to the whole batch — ask the user to pick from get_project_budget_categories before " +
      "calling. Source and destination must differ.\n\n" +
      "SPACE ASSIGNMENTS: destinationSpaceAssignments may preserve selected per-item assignments. " +
      "Every supplied space is validated against the destination project; omitted items land unassigned.\n\n" +
      "DO NOT use this as a shortcut for 'the item was entered on the wrong transaction but still belongs " +
      "to the same project' — that's a reassignment, use update_item to move the item to the correct " +
      "transaction within the same project.",
    {
      itemIds: z
        .array(z.string())
        .min(1)
        .max(MAX_BATCH_ITEMS)
        .describe(`Item document IDs to sell (max ${MAX_BATCH_ITEMS} per call). All items must currently be in the same source project.`),
      destinationProjectId: z.string().describe("Destination project ID"),
      destinationBudgetCategoryId: z
        .string()
        .describe(
          "Budget category in the destination project — required, applies to the whole batch. Ask the user."
        ),
      destinationSpaceAssignments: destinationSpaceAssignmentsSchema,
      notes: z
        .string()
        .optional()
        .describe(
          "Optional prose describing the sale (e.g. 'Sold 3 sconces from Witzenman to Bradshaws — client change'). Free-form. createdAt/createdBy + lineage edges are the audit trail."
        ),
      dryRun: z.boolean().default(false),
    },
    withTelemetry(
      "sell_items_from_project_to_project",
      async ({
        itemIds,
        destinationProjectId,
        destinationBudgetCategoryId,
        destinationSpaceAssignments,
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
            `${stray.length} item(s) are not in a project — cannot sell from project to project: ${stray.map((i) => i.id).join(", ")}`,
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

        const resolvedSpaces = await validateDestinationSpaceAssignments(
          db,
          itemIds,
          destinationProjectId,
          destinationSpaceAssignments as DestinationSpaceAssignment[] | undefined
        );
        if (!resolvedSpaces.ok) {
          return validation(resolvedSpaces.issue.message, resolvedSpaces.issue.guidance);
        }

        const missingPrice = missingProjectPrice(items);
        if (missingPrice.length > 0) return missingProjectPriceError(missingPrice);
        const missingSourceCategory = missingSourceBudgetCategory(items);
        if (missingSourceCategory.length > 0) {
          return missingSourceBudgetCategoryError(missingSourceCategory);
        }

        const origins = await resolveItemOrigins(db, items);
        const unresolved = [...origins.values()].filter((resolution) => resolution.origin === "unresolved");
        if (unresolved.length > 0) return unresolvedOriginError(unresolved);
        const split = splitByResolvedOrigin(items, origins);
        const { subtotalCents, amountCents, missingTax } = computeProjectPriceTotals(items);

        if (dryRun) {
          const returnLegs = sourceCategoryGroups(split.returnItems).map((group) => {
            const t = computeProjectToInventoryTotals(group.items);
            return {
                    type: "Return" as const,
                    source: inventoryLabel,
                    projectId: sourceProjectId,
              budgetCategoryId: group.budgetCategoryId,
                    amountCents: t.amountCents,
                    subtotalCents: t.subtotalCents,
              itemIds: group.items.map((i) => i.id),
            };
          });
          const saleToInventoryLegs = sourceCategoryGroups(split.saleItems).map((group) => {
            const t = computeProjectOriginAcquisitionTotals(group.items);
            return {
                    type: "Sale" as const,
                    source: inventoryLabel,
                    projectId: sourceProjectId,
              budgetCategoryId: group.budgetCategoryId,
                    amountCents: t.amountCents,
                    subtotalCents: t.subtotalCents,
              itemIds: group.items.map((i) => i.id),
            };
          });
          return asToolResponse({
            dryRun: true,
            plan: {
              firstHop: {
                returnLegs,
                saleToInventoryLegs,
                originResolutions: items.map((item) => origins.get(item.id)),
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
                  spaceId: resolvedSpaces.byItemId.get(i.id) ?? null,
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

        return await commitSellItemsFromProjectToProject(
          db,
          items,
          split,
          sourceProjectId,
          destinationProjectId,
          destinationBudgetCategoryId,
          resolvedSpaces.byItemId,
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
  destinationSpaceIdsByItem: Map<string, string>,
  totals: { subtotalCents: number; amountCents: number; missingTax: string[]; notes?: string; inventoryLabel: string }
) {
  const frozen = await frozenSourceTxIds(db, items);

  const batch = db.batch();
  const itemsCol = accountCollection(db, "items");
  const txCol = accountCollection(db, "transactions");
  const edgesCol = accountCollection(db, "lineageEdges");
  const now = FieldValue.serverTimestamp();
  const uid = safeGetUserId();

  // 1. New Purchase transaction (fixed structural shape, server-maintained open total).
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
      spaceId: destinationSpaceIdsByItem.get(item.id) ?? null,
      currentSource: totals.inventoryLabel,
      projectPriceCents: projectPriceForMovement(item),
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // 3. Remove from prior tx active membership.
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

  return asToolResponse({
    message: `Purchased ${items.length} item(s) from inventory into project ${destinationProjectId}.`,
    purchaseTransactionId: purchaseRef.id,
    amountCents: totals.amountCents,
    amount: formatCents(totals.amountCents),
    budgetCategoryId,
    finalItems: items.map((item) => ({
      itemId: item.id,
      projectId: destinationProjectId,
      budgetCategoryId,
      spaceId: destinationSpaceIdsByItem.get(item.id) ?? null,
    })),
    spaceAssignmentsApplied: destinationSpaceIdsByItem.size,
    unassignedItemIds: items
      .filter((item) => !destinationSpaceIdsByItem.has(item.id))
      .map((item) => item.id),
    warning: totals.missingTax.length > 0
      ? missingTaxWarning(totals.missingTax, items.length).trim()
      : null,
  });
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

  const saleTxByItemId = new Map<string, string>();
  for (const group of sourceCategoryGroups(items)) {
    const saleRef = txCol.doc();
    const groupTotals = computeProjectOriginAcquisitionTotals(group.items);
    batch.set(saleRef, {
      type: "Sale",
      source: totals.inventoryLabel,
      projectId: sourceProjectId,
      budgetCategoryId: group.budgetCategoryId,
      amountCents: groupTotals.amountCents,
      subtotalCents: groupTotals.subtotalCents,
      itemIds: group.items.map((i) => i.id),
      status: "completed",
      isComplete: true,
      ...(totals.notes ? { notes: tagNotesAsAi(totals.notes) } : {}),
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
    });
    for (const item of group.items) saleTxByItemId.set(item.id, saleRef.id);
  }

  // 2. Each item: land in inventory.
  for (const item of items) {
    const saleTxId = saleTxByItemId.get(item.id);
    if (!saleTxId) continue;
    batch.update(itemsCol.doc(item.id), {
      projectId: null,
      budgetCategoryId: null,
      spaceId: null,
      status: "purchased",
      transactionId: saleTxId,
      currentSource: totals.inventoryLabel,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // 3. Remove from prior tx active membership.
  applyArrayRemoves(batch, txCol, items, frozen, now);

  // 4. Lineage edges — "soldToInventory" signals project → inventory acquisition.
  for (const item of items) {
    const saleTxId = saleTxByItemId.get(item.id);
    if (!saleTxId) continue;
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: item.transactionId ?? null,
      toTransactionId: saleTxId,
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
          `New Sale transaction(s): ${[...new Set(saleTxByItemId.values())].join(", ")}\n` +
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
  const returnedPaidCredits = await returnedPaidItemCreditContexts(db, items);

  // An inventory return reverses the project-side Purchase at its project-sale
  // value. Project-originated Sale-to-Inventory is a distinct business
  // acquisition and uses purchase cost in commitSellToInventory.
  // projectId on the Return tx = source project (budget impact lands there).
  const sourceProjectId = items[0]?.projectId ?? null;
  const tagged = notes ? tagNotesAsAi(notes) : undefined;

  const returnTxByItemId = new Map<string, string>();
  for (const group of sourceCategoryGroups(items)) {
    const returnTxRef = txCol.doc();
    const groupTotals = computeProjectToInventoryTotals(group.items);
    batch.set(returnTxRef, {
      type: "Return",
      source: inventoryLabel,
      projectId: sourceProjectId,
      budgetCategoryId: group.budgetCategoryId,
      amountCents: groupTotals.amountCents,
      subtotalCents: groupTotals.subtotalCents,
      itemIds: group.items.map((i) => i.id),
      status: "completed",
      ...(tagged ? { notes: tagged } : {}),
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
    });
    for (const item of group.items) returnTxByItemId.set(item.id, returnTxRef.id);
  }

  for (const item of items) {
    const returnTxId = returnTxByItemId.get(item.id);
    if (!returnTxId) continue;
    batch.update(itemsCol.doc(item.id), {
      projectId: null,
      budgetCategoryId: null,
      spaceId: null,
      status: "purchased",
      transactionId: returnTxId,
      currentSource: inventoryLabel,
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // Remove from prior tx active membership; skip the return tx itself.
  const frozenPlusReturn = new Set(frozen);
  for (const txId of returnTxByItemId.values()) frozenPlusReturn.add(txId);
  applyArrayRemoves(batch, txCol, items, frozenPlusReturn, now);

  for (const item of items) {
    const returnTxId = returnTxByItemId.get(item.id);
    if (!returnTxId) continue;
    batch.set(edgesCol.doc(), {
      itemId: item.id,
      fromTransactionId: item.transactionId ?? null,
      toTransactionId: returnTxId,
      fromProjectId: item.projectId ?? null,
      toProjectId: null,
      movementKind: "returned",
      source: "mcp",
      createdAt: now,
    });
  }

  const creditInvoiceIds = appendReturnedPaidItemCreditDrafts(batch, db, returnedPaidCredits, uid);

  await batch.commit();

  return {
    content: [
      {
        type: "text" as const,
        text:
          `Returned ${items.length} item(s) to business inventory.\n` +
          `New Return transaction(s): ${[...new Set(returnTxByItemId.values())].join(", ")}\n` +
          `Items now have projectId: null and budgetCategoryId: null.` +
          `${creditInvoiceIds.length ? `\nDraft credit invoice(s): ${creditInvoiceIds.join(", ")}` : ""}`,
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

  // Append into the destination Return transaction's active membership.
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

  // Remove from prior tx active membership; skip the return tx itself.
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

async function commitSellItemsFromProjectToProject(
  db: Firestore,
  items: (Item & { id: string })[],
  split: {
    returnItems: (Item & { id: string })[];
    saleItems: (Item & { id: string })[];
  },
  sourceProjectId: string,
  destinationProjectId: string,
  destinationBudgetCategoryId: string,
  destinationSpaceIdsByItem: Map<string, string>,
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
  const returnTxByItemId = new Map<string, string>();
  for (const group of sourceCategoryGroups(split.returnItems)) {
    const returnRef = txCol.doc();
    const returnTotals = computeProjectToInventoryTotals(group.items);
    batch.set(returnRef, {
      type: "Return",
      source: totals.inventoryLabel,
      projectId: sourceProjectId,
      budgetCategoryId: group.budgetCategoryId,
      amountCents: returnTotals.amountCents,
      subtotalCents: returnTotals.subtotalCents,
      itemIds: group.items.map((i) => i.id),
      status: "completed",
      ...(totals.notes ? { notes: tagNotesAsAi(totals.notes) } : {}),
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
    });
    for (const item of group.items) returnTxByItemId.set(item.id, returnRef.id);
  }

  // 1b. First hop — Sale-to-Inventory leg (items that originated in the source project).
  const firstSaleTxByItemId = new Map<string, string>();
  for (const group of sourceCategoryGroups(split.saleItems)) {
    const saleRef = txCol.doc();
    const saleTotals = computeProjectOriginAcquisitionTotals(group.items);
    batch.set(saleRef, {
      type: "Sale",
      source: totals.inventoryLabel,
      projectId: sourceProjectId,
      budgetCategoryId: group.budgetCategoryId,
      amountCents: saleTotals.amountCents,
      subtotalCents: saleTotals.subtotalCents,
      itemIds: group.items.map((i) => i.id),
      status: "completed",
      isComplete: true,
      ...(totals.notes ? { notes: tagNotesAsAi(totals.notes) } : {}),
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
    });
    for (const item of group.items) firstSaleTxByItemId.set(item.id, saleRef.id);
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
      spaceId: destinationSpaceIdsByItem.get(item.id) ?? null,
      currentSource: totals.inventoryLabel,
      projectPriceCents: projectPriceForMovement(item),
      updatedAt: now,
      updatedBy: uid,
    });
  }

  // 4. Remove from prior tx active membership.
  applyArrayRemoves(batch, txCol, items, frozen, now);

  // 5. Lineage edges — two per item.
  for (const item of items) {
    const isReturn = returnTxByItemId.has(item.id);
    const firstHopTxId = isReturn
      ? returnTxByItemId.get(item.id) ?? null
      : firstSaleTxByItemId.get(item.id) ?? null;
    const firstHopKind = isReturn ? "returned" : "soldToInventory";
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
  const returnTxIds = [...new Set(returnTxByItemId.values())];
  const firstSaleTxIds = [...new Set(firstSaleTxByItemId.values())];
  if (returnTxIds.length > 0) legs.push(`Return (from-inventory leg): ${returnTxIds.join(", ")}`);
  if (firstSaleTxIds.length > 0) legs.push(`Sale-to-Inventory (originated-in-project leg): ${firstSaleTxIds.join(", ")}`);
  legs.push(`Purchase-from-Inventory (destination): ${destPurchaseRef.id}`);

  return asToolResponse({
    message: `Sold ${items.length} item(s) from ${sourceProjectId} to ${destinationProjectId}.`,
    movementTransactions: legs,
    purchaseTransactionId: destPurchaseRef.id,
    destinationBudgetCategoryId,
    amountCents: totals.amountCents,
    amount: formatCents(totals.amountCents),
    finalItems: items.map((item) => ({
      itemId: item.id,
      projectId: destinationProjectId,
      budgetCategoryId: destinationBudgetCategoryId,
      spaceId: destinationSpaceIdsByItem.get(item.id) ?? null,
    })),
    spaceAssignmentsApplied: destinationSpaceIdsByItem.size,
    unassignedItemIds: items
      .filter((item) => !destinationSpaceIdsByItem.has(item.id))
      .map((item) => item.id),
    warning: totals.missingTax.length > 0
      ? missingTaxWarning(totals.missingTax, items.length).trim()
      : null,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Remove items from their prior source transaction's active itemIds — one
 * update per distinct source tx.
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
