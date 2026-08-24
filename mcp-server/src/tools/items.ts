import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { Item, Transaction, AttachmentRef } from "../types.js";
import { accountCollection, accountPath, queryDocs, getDoc } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { itemMatches } from "../util/search.js";
import { uploadToStorage, deleteFromStorage } from "../storage.js";
import { generateThumbnails, thumbnailPath } from "../util/thumbnail.js";
import {
  ProjectionMode,
  ResponseLimitArg,
  itemSummary,
  capResponse,
  asToolResponse,
  pickFields,
} from "../util/projections.js";
import { notFound, validation } from "../util/errors.js";
import { appendOrReviseAiAuditLine, tagNotesAsAi } from "../util/notes.js";
import {
  applyItemPriceFloorToCreate,
  applyItemPriceFloorToUpdate,
  normalizedProjectPriceCents,
} from "../util/item-pricing.js";
import {
  detachedSpaceAssignment,
  validateItemSpaceTransition,
  type DetachedSpaceAssignment,
  type SpaceCache,
} from "../util/space-assignments.js";

// ─────────────────────────────────────────────────────────────────────────────
// Inventory invariant helpers (per-batch inventory movement redesign).
//
// Rule 1: (item.projectId == null) ↔ (item.budgetCategoryId == null)
// Items in business inventory have no budget category. Categories are
// resolved at sell-into-project time.
//
// Rule 2: (item.projectId != null) → (item.transactionId != null)
// Project items must be attached to a transaction. Inventory items may or
// may not have one. Legacy orphans (project items with no transactionId)
// are left as-is; the Bulk Reassign UI repairs them manually.
//
// See docs/specs/sale-transactions.md and docs/specs/inventory-as-store.md.
// ─────────────────────────────────────────────────────────────────────────────

/** Reject create payloads that violate the inventory invariant. */
function checkCreateInvariant(
  projectId: string | undefined | null,
  budgetCategoryId: string | undefined | null
): string | null {
  const inInventory = projectId == null || projectId === "";
  if (inInventory && budgetCategoryId != null && budgetCategoryId !== "") {
    return (
      "Cannot create an inventory item (no projectId) with a budgetCategoryId. " +
      "Items in business inventory have no budget category — omit budgetCategoryId, " +
      "or set projectId to put the item in a project first."
    );
  }
  return null;
}

/**
 * Reject update payloads that violate the inventory invariant.
 * `updates` is the incoming delta (only keys that were explicitly provided).
 */
function checkUpdateInvariant(
  existing: { projectId?: string | null; budgetCategoryId?: string | null },
  updates: Record<string, unknown>
): string | null {
  const hasProjectIdUpdate = "projectId" in updates;
  const hasCategoryUpdate = "budgetCategoryId" in updates;

  const nextProjectId = hasProjectIdUpdate
    ? (updates.projectId as string | null | undefined)
    : (existing.projectId ?? null);
  const nextCategory = hasCategoryUpdate
    ? (updates.budgetCategoryId as string | null | undefined)
    : (existing.budgetCategoryId ?? null);

  const nextInInventory = nextProjectId == null || nextProjectId === "";
  const nextHasCategory = nextCategory != null && nextCategory !== "";

  if (nextInInventory && nextHasCategory) {
    return (
      "Cannot set budgetCategoryId on an item that is in business inventory (projectId: null). " +
      "Items in inventory have no category. Either set projectId in the same update, or " +
      "clear budgetCategoryId by passing null."
    );
  }

  // Moving an item from inventory INTO a project requires a category.
  const wasInInventory = existing.projectId == null || existing.projectId === "";
  const isMovingIntoProject =
    wasInInventory && hasProjectIdUpdate && !nextInInventory;
  if (isMovingIntoProject && !nextHasCategory) {
    return (
      "Moving an item from business inventory into a project requires a budgetCategoryId. " +
      "Pass both projectId and budgetCategoryId in the same update, or use sell_items_from_inventory_to_project instead."
    );
  }

  return null;
}

/** Reject create payloads where a project item has no transactionId. */
export function checkTransactionLinkageOnCreate(
  projectId: string | undefined | null,
  transactionId: string | undefined | null
): string | null {
  const hasProject = projectId != null && projectId !== "";
  const hasTransaction = transactionId != null && transactionId !== "";
  if (hasProject && !hasTransaction) {
    return (
      "Cannot create an item in a project (projectId set) without a transactionId. " +
      "Project items must be attached to a transaction. Either pass transactionId, " +
      "or omit projectId to create in business inventory."
    );
  }
  return null;
}

export type LinkageStatus =
  | { kind: "ok" }
  | { kind: "reject"; message: string }
  | { kind: "warn"; message: string };

/**
 * Evaluate the transaction-linkage invariant against an update payload.
 *
 * Hard-reject only when the update would CREATE a new orphan (existing item
 * was fine, post-update would be a project item with no transactionId).
 *
 * If the existing item was ALREADY an orphan and the update doesn't fix the
 * orphan state, allow the write and return a warning so the caller can
 * surface it. Routine edits (e.g. fixing a typo on a legacy orphan) should
 * not be blocked by a problem the update didn't introduce.
 */
export function checkTransactionLinkageOnUpdate(
  existing: { projectId?: string | null; transactionId?: string | null },
  updates: Record<string, unknown>
): LinkageStatus {
  const hasProjectIdUpdate = "projectId" in updates;
  const hasTransactionIdUpdate = "transactionId" in updates;

  const prevProjectId = existing.projectId ?? null;
  const prevTransactionId = existing.transactionId ?? null;
  const prevHasProject = prevProjectId != null && prevProjectId !== "";
  const prevHasTransaction = prevTransactionId != null && prevTransactionId !== "";
  const wasOrphan = prevHasProject && !prevHasTransaction;

  const nextProjectId = hasProjectIdUpdate
    ? (updates.projectId as string | null | undefined)
    : prevProjectId;
  const nextTransactionId = hasTransactionIdUpdate
    ? (updates.transactionId as string | null | undefined)
    : prevTransactionId;
  const nextHasProject = nextProjectId != null && nextProjectId !== "";
  const nextHasTransaction = nextTransactionId != null && nextTransactionId !== "";
  const willBeOrphan = nextHasProject && !nextHasTransaction;

  if (!willBeOrphan) return { kind: "ok" };
  if (wasOrphan) {
    return {
      kind: "warn",
      message:
        "Item is a legacy orphan (project item with no transactionId). Update applied. " +
        "To clean up: bulk_update_items with projectId: null moves it to inventory, " +
        "then sell_items_from_inventory_to_project records the real purchase.",
    };
  }
  return {
    kind: "reject",
    message:
      "Cannot leave an item in a project (projectId set) without a transactionId. " +
      "Either pass transactionId in the same update, or move the item to business inventory (projectId: null).",
  };
}

function formatItem(item: Item & { id: string }) {
  return {
    id: item.id,
    name: item.name ?? item.description ?? "",
    status: item.status ?? "",
    source: item.source ?? "",
    sku: item.sku ?? "",
    projectId: item.projectId ?? null,
    spaceId: item.spaceId ?? null,
    budgetCategoryId: item.budgetCategoryId ?? null,
    purchasePrice: formatCents(item.purchasePriceCents),
    projectPrice: formatCents(normalizedProjectPriceCents(
      item.purchasePriceCents,
      item.projectPriceCents
    )),
    marketValue: formatCents(item.marketValueCents),
    transactionId: item.transactionId ?? null,
    bookmark: item.bookmark ?? false,
    quantity: item.quantity ?? 1,
    taxRatePct: item.taxRatePct ?? null,
    notes: item.notes ?? "",
    imageCount: item.images?.length ?? 0,
    images: (item.images ?? []).map((ref: AttachmentRef) => ({
      url: ref.url,
      kind: ref.kind ?? "image",
      fileName: ref.fileName ?? null,
      contentType: ref.contentType ?? null,
    })),
  };
}

export function registerItemTools(server: McpServer, db: Firestore) {
  // ── list_items ─────────────────────────────────────────────────────────────
  server.tool(
    "list_items",
    "List items by EXACT-match structured filters (projectId, status, budgetCategoryId, etc.). Use projectId='inventory' for business inventory (no project). Supports pagination via offset + limit.\n\nPicking between this and search_items:\n- Exact vendor string → list_items (here).\n- Partial vendor name, or any keyword that might appear in source or notes → search_items.\nDon't enumerate name variants by calling this tool in a loop.",
    {
      projectId: z.string().optional().describe("Filter by project ID. Use 'inventory' for items with no project."),
      spaceId: z.string().optional().describe("Filter by space ID"),
      budgetCategoryId: z.string().optional().describe("Filter by budget category"),
      status: z.string().optional().describe("Filter by status (to purchase, purchased, to return, returned)"),
      bookmarked: z.boolean().optional().describe("Filter by bookmark status"),
      hasTransaction: z.boolean().optional().describe("Filter by transaction linkage: true = only items with a transactionId, false = only items with NO transactionId"),
      hasImages: z.boolean().optional().describe("Filter by image presence: true = only items with at least one image, false = only items with NO images. Use false to find items still needing photos."),
      limit: z.coerce.number().default(50).describe("Max results (ignored when fetchAll is true)"),
      offset: z.coerce.number().default(0).describe("Number of results to skip (for pagination). Use with limit to page through results."),
      fetchAll: z.boolean().default(false).describe("Return all matching items, ignoring limit/offset — subject to the per-response byte budget. If the result exceeds the budget, the response leads with a `_truncationNotice` and a `nextOffset` to resume; it does NOT silently drop items. For large projects, prefer narrowing the filter (e.g. hasImages: false) over fetchAll."),
      mode: ProjectionMode.describe("'summary' (default) or 'full'."),
      fields: z.array(z.string()).optional().describe("Explicit field list. Overrides mode."),
      responseLimit: ResponseLimitArg,
    },
    async ({ projectId, spaceId, budgetCategoryId, status, bookmarked, hasTransaction, hasImages, limit, offset, fetchAll, mode, fields, responseLimit }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "items");

      if (projectId === "inventory") {
        query = query.where("projectId", "==", null);
      } else if (projectId) {
        query = query.where("projectId", "==", projectId);
      }

      if (spaceId) query = query.where("spaceId", "==", spaceId);
      if (budgetCategoryId) query = query.where("budgetCategoryId", "==", budgetCategoryId);
      if (status) query = query.where("status", "==", status);
      if (bookmarked !== undefined) query = query.where("bookmark", "==", bookmarked);

      // Firestore can't query "field absent" or array length, so we filter client-side
      const clientFilters: ((item: Item & { id: string }) => boolean)[] = [];
      if (hasTransaction === true) clientFilters.push((item) => !!item.transactionId);
      else if (hasTransaction === false) clientFilters.push((item) => !item.transactionId);
      if (hasImages === true) clientFilters.push((item) => (item.images?.length ?? 0) > 0);
      else if (hasImages === false) clientFilters.push((item) => (item.images?.length ?? 0) === 0);
      const hasClientFilter = clientFilters.length > 0;

      if (!fetchAll && !hasClientFilter) {
        query = query.offset(offset).limit(limit);
      }
      let items = await queryDocs<Item>(query);
      if (hasClientFilter) items = items.filter((item) => clientFilters.every((f) => f(item)));
      if (!fetchAll) items = items.slice(offset, offset + limit);

      const projected = items.map((i) => {
        if (fields && fields.length) return pickFields(i as unknown as Record<string, unknown>, fields);
        return mode === "full" ? (i as unknown as Record<string, unknown>) : (itemSummary(i) as unknown as Record<string, unknown>);
      });
      return asToolResponse(capResponse(projected, { limitBytes: responseLimit, offset, fetchAll }));
    }
  );

  // ── get_item ───────────────────────────────────────────────────────────────
  server.tool(
    "get_item",
    "Get a single item with all details. Includes images[] array — each entry's url is a public HTTPS download URL (Firebase Storage token URL), fetch directly with curl/WebFetch, no auth required.",
    { itemId: z.string().describe("Item document ID") },
    async ({ itemId }) => {
      const item = await getDoc<Item>(db, "items", itemId);
      if (!item) {
        return { content: [{ type: "text", text: `Item ${itemId} not found.` }], isError: true };
      }
      return { content: [{ type: "text", text: JSON.stringify(formatItem(item), null, 2) }] };
    }
  );

  // ── search_items ───────────────────────────────────────────────────────────
  server.tool(
    "search_items",
    "Substring filter across `name`, `description`, `sku`, `source`, `notes`, and `amount`. Case-insensitive.\n\nPicking between this and list_items:\n- Partial vendor name, or any keyword that might appear in source or notes → search_items (here).\n- Exact vendor string, or other structured filters (status, projectId, budgetCategoryId) → list_items.\nA single substring call beats looping list_items over a list of name variants.",
    {
      query: z.string().describe("Search term"),
      projectId: z.string().optional().describe("Scope search to a project, or 'inventory' for business inventory"),
      limit: z.coerce.number().default(25).describe("Max results"),
      offset: z.coerce.number().default(0).describe("Number of results to skip (for pagination)"),
    },
    async ({ query: searchTerm, projectId, limit, offset }) => {
      let q: FirebaseFirestore.Query = accountCollection(db, "items");
      if (projectId === "inventory") {
        q = q.where("projectId", "==", null);
      } else if (projectId) {
        q = q.where("projectId", "==", projectId);
      }

      const all = await queryDocs<Item>(q);
      const matched = all
        .filter((item) => itemMatches(item, searchTerm))
        .slice(offset, offset + limit);

      return { content: [{ type: "text", text: JSON.stringify(matched.map(formatItem), null, 2) }] };
    }
  );

  // ── create_item ────────────────────────────────────────────────────────────
  server.tool(
    "create_item",
    "[mutating] Create a new item.\n\nNOTES CONVENTION: `notes` is the optional user-facing description of the item (what it is — finish, size, room, etc.). Plain prose, no required format.\n\nInvariants: items in business inventory (no projectId) must have no budgetCategoryId. Items in a project (projectId set) must have a transactionId — pass both together, or omit projectId to create in inventory.",
    {
      name: z.string().describe("Item name"),
      projectId: z.string().optional().describe("Project ID (omit for business inventory). To match an item to a project, check the project's notes field — it may contain payment method details (card last 4), billing address, or other identifiers that help determine which project a purchase belongs to."),
      purchasePriceCents: z.coerce.number().optional().describe("Purchase price in cents"),
      projectPriceCents: z.coerce.number().optional().describe("Project price in cents"),
      status: z.string().default("purchased").describe("Status: to purchase, purchased, to return, returned"),
      source: z.string().optional().describe("Vendor/source"),
      sku: z.string().optional().describe("SKU"),
      notes: z.string().optional().describe("Optional prose describing the item (finish, size, room, etc.). Free-form, no required format."),
      spaceId: z.string().optional().describe("Space ID"),
      budgetCategoryId: z.string().optional().describe("Budget category ID. Auto-inherited from the linked transaction if not provided."),
      transactionId: z.string().optional().describe("Transaction ID to link this item to"),
      taxRatePct: z.coerce.number().optional().describe("Tax rate as a percentage (e.g. 8.375). Auto-inherited from the linked transaction if not provided."),
    },
    async ({ name, projectId, purchasePriceCents, projectPriceCents, status, source, sku, notes, spaceId, budgetCategoryId, transactionId, taxRatePct }) => {
      // Auto-inherit taxRatePct and budgetCategoryId from transaction if not explicitly provided
      let resolvedTaxRate = taxRatePct;
      let resolvedBudgetCategoryId = budgetCategoryId;
      if ((resolvedTaxRate === undefined || resolvedBudgetCategoryId === undefined) && transactionId) {
        const tx = await getDoc<Transaction>(db, "transactions", transactionId);
        if (resolvedTaxRate === undefined && tx?.taxRatePct != null) resolvedTaxRate = tx.taxRatePct;
        if (resolvedBudgetCategoryId === undefined && tx?.budgetCategoryId) resolvedBudgetCategoryId = tx.budgetCategoryId;
      }

      // If the item is going into business inventory (no projectId), strip any
      // inherited or provided category — inventory items have no category.
      if (!projectId) {
        resolvedBudgetCategoryId = undefined;
      }

      // Enforce the invariant on the final resolved values.
      const invariantError = checkCreateInvariant(projectId, resolvedBudgetCategoryId);
      if (invariantError) {
        return validation(
          invariantError,
          "Pass a projectId together with budgetCategoryId, or omit budgetCategoryId for inventory items."
        );
      }

      const linkageError = checkTransactionLinkageOnCreate(projectId, transactionId);
      if (linkageError) {
        return validation(
          linkageError,
          "Pass transactionId alongside projectId, or omit projectId to create in business inventory."
        );
      }

      const data: Record<string, unknown> = {
        name,
        status,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      if (projectId) data.projectId = projectId;
      if (purchasePriceCents !== undefined) data.purchasePriceCents = purchasePriceCents;
      applyItemPriceFloorToCreate(data, { purchasePriceCents, projectPriceCents });
      if (source) data.source = source;
      if (sku) data.sku = sku;
      if (notes) data.notes = tagNotesAsAi(notes);
      if (spaceId) data.spaceId = spaceId;
      if (resolvedBudgetCategoryId) data.budgetCategoryId = resolvedBudgetCategoryId;
      if (transactionId) data.transactionId = transactionId;
      if (resolvedTaxRate !== undefined) data.taxRatePct = resolvedTaxRate;

      const ref = await accountCollection(db, "items").add(data);

      // Maintain bidirectional link: append item to transaction's itemIds
      if (transactionId) {
        await accountCollection(db, "transactions").doc(transactionId).update({
          itemIds: FieldValue.arrayUnion(ref.id),
          updatedAt: new Date(),
        });
      }

      return { content: [{ type: "text", text: `Created item ${ref.id}` }] };
    }
  );

  // ── bulk_create_items ─────────────────────────────────────────────────────
  server.tool(
    "bulk_create_items",
    "Create multiple items in one batch. Top-level transactionId and projectId are defaults applied to all items unless overridden per-item.",
    {
      transactionId: z.string().optional().describe("Transaction ID — applied to all items unless overridden per-item"),
      projectId: z.string().optional().describe("Project ID — applied to all items unless overridden per-item"),
      items: z.array(z.object({
        name: z.string().describe("Item name"),
        projectId: z.string().optional().describe("Project ID (overrides top-level)"),
        purchasePriceCents: z.coerce.number().optional().describe("Purchase price in cents"),
        projectPriceCents: z.coerce.number().optional().describe("Project price in cents"),
        status: z.string().default("purchased").describe("Status: to purchase, purchased, to return, returned"),
        source: z.string().optional().describe("Vendor/source"),
        sku: z.string().optional().describe("SKU"),
        notes: z.string().optional().describe("Notes"),
        spaceId: z.string().optional().describe("Space ID"),
        budgetCategoryId: z.string().optional().describe("Budget category ID"),
        transactionId: z.string().optional().describe("Transaction ID (overrides top-level)"),
        taxRatePct: z.coerce.number().optional().describe("Tax rate % (auto-inherited from transaction if omitted)"),
      })).describe("Array of items to create"),
    },
    async ({ transactionId: defaultTransactionId, projectId: defaultProjectId, items }) => {
      if (items.length === 0) {
        return { content: [{ type: "text", text: "No items provided." }], isError: true };
      }

      const itemsCol = accountCollection(db, "items");
      const txCol = accountCollection(db, "transactions");
      const createdIds: string[] = [];
      const txItemMap = new Map<string, string[]>();

      // Pre-fetch transactions for taxRatePct inheritance (deduplicated)
      const txIds = new Set<string>();
      for (const item of items) {
        const txId = item.transactionId ?? defaultTransactionId;
        if (txId && item.taxRatePct === undefined) txIds.add(txId);
      }
      const txCache = new Map<string, Transaction>();
      for (const txId of txIds) {
        const tx = await getDoc<Transaction>(db, "transactions", txId);
        if (tx) txCache.set(txId, tx);
      }

      type BatchOp = { type: "set"; ref: FirebaseFirestore.DocumentReference; data: Record<string, unknown> }
        | { type: "update"; ref: FirebaseFirestore.DocumentReference; data: Record<string, unknown> };
      const ops: BatchOp[] = [];

      for (const item of items) {
        const resolvedProjectId = item.projectId ?? defaultProjectId;
        const resolvedTransactionId = item.transactionId ?? defaultTransactionId;

        // Resolve tax rate: explicit > inherited from transaction
        let resolvedTaxRate = item.taxRatePct;
        if (resolvedTaxRate === undefined && resolvedTransactionId) {
          const tx = txCache.get(resolvedTransactionId);
          if (tx?.taxRatePct != null) resolvedTaxRate = tx.taxRatePct;
        }

        // Inventory invariant: strip category when item is going to inventory.
        const categoryIn = resolvedProjectId ? item.budgetCategoryId : undefined;
        const invariantError = checkCreateInvariant(resolvedProjectId, categoryIn);
        if (invariantError) {
          return validation(
            `Item ${items.indexOf(item)} (${item.name}): ${invariantError}`,
            "Pass a projectId together with budgetCategoryId, or omit budgetCategoryId for inventory items."
          );
        }

        const linkageError = checkTransactionLinkageOnCreate(resolvedProjectId, resolvedTransactionId);
        if (linkageError) {
          return validation(
            `Item ${items.indexOf(item)} (${item.name}): ${linkageError}`,
            "Pass transactionId alongside projectId, or omit projectId for inventory items."
          );
        }

        const data: Record<string, unknown> = {
          name: item.name,
          status: item.status,
          createdAt: new Date(),
          updatedAt: new Date(),
        };
        if (resolvedProjectId) data.projectId = resolvedProjectId;
        if (item.purchasePriceCents !== undefined) data.purchasePriceCents = item.purchasePriceCents;
        applyItemPriceFloorToCreate(data, item);
        if (item.source) data.source = item.source;
        if (item.sku) data.sku = item.sku;
        if (item.notes) data.notes = tagNotesAsAi(item.notes);
        if (item.spaceId) data.spaceId = item.spaceId;
        if (categoryIn) data.budgetCategoryId = categoryIn;
        if (resolvedTransactionId) data.transactionId = resolvedTransactionId;
        if (resolvedTaxRate !== undefined) data.taxRatePct = resolvedTaxRate;

        const ref = itemsCol.doc();
        createdIds.push(ref.id);
        ops.push({ type: "set", ref, data });

        if (resolvedTransactionId) {
          const existing = txItemMap.get(resolvedTransactionId) ?? [];
          existing.push(ref.id);
          txItemMap.set(resolvedTransactionId, existing);
        }
      }

      // One arrayUnion op per unique transaction
      for (const [txId, itemIds] of txItemMap) {
        ops.push({
          type: "update",
          ref: txCol.doc(txId),
          data: { itemIds: FieldValue.arrayUnion(...itemIds), updatedAt: new Date() },
        });
      }

      // Commit in chunks of 500
      for (let i = 0; i < ops.length; i += 500) {
        const batch = db.batch();
        for (const op of ops.slice(i, i + 500)) {
          if (op.type === "set") {
            batch.set(op.ref, op.data);
          } else {
            batch.update(op.ref, op.data);
          }
        }
        await batch.commit();
      }

      return {
        content: [{ type: "text", text: `Created ${createdIds.length} items: ${createdIds.join(", ")}` }],
      };
    }
  );

  // ── update_item ────────────────────────────────────────────────────────────
  server.tool(
    "update_item",
    "[mutating] Update item fields.\n\n" +
      "NOTES CONVENTION: The `notes` field is a single string shared between user-authored " +
      "prose (at the top) and AI-authored audit lines (at the bottom, blank-line separated). " +
      "Two ways to edit it:\n" +
      "  • `notes` — REPLACES the entire field. Use only when the user asks you to rewrite it " +
      "or when consolidating your own prior stale AI lines. Preserve user prose verbatim.\n" +
      "  • `aiAuditAppend` — appends a tagged '[AI M/D/YYYY] …' line to the bottom. If the " +
      "last line is already an AI line from today, it's REPLACED (no stacking).\n" +
      "Most field edits don't need either — updatedAt already records the audit trail.\n\n" +
      "Inventory invariant: items in business inventory (projectId: null) must have " +
      "budgetCategoryId: null. Pass null explicitly to either field to clear it. Moving " +
      "an item from inventory into a project requires passing both projectId AND " +
      "budgetCategoryId in the same update. When projectId changes and the item already " +
      "has a space, spaceId must be explicit: pass null to detach it or a space in the " +
      "resulting scope. Detached assignments are returned for a later sale.\n\n" +
      "Transaction-linkage invariant: items in a project (projectId set) should have a " +
      "transactionId. Updates that would CREATE a new project-orphan (e.g. setting projectId " +
      "without transactionId on a non-orphan item) are rejected. Updates that touch an item " +
      "that's ALREADY an orphan (legacy data) are allowed and return a warning so you can " +
      "decide whether to clean it up. Do not invent a fake transactionId to dodge the warning. " +
      "Correct path: bulk_update_items projectId: null moves the orphan to inventory, then " +
      "sell_items_from_inventory_to_project records the real Purchase.",
    {
      itemId: z.string().describe("Item document ID"),
      name: z.string().optional().describe("Item name"),
      status: z.string().optional().describe("Item status: to purchase, purchased, to return, returned"),
      purchasePriceCents: z.coerce.number().optional().describe("Purchase price in cents"),
      projectPriceCents: z.coerce.number().optional().describe("Project price in cents"),
      marketValueCents: z.coerce.number().optional().describe("Market value in cents"),
      source: z.string().optional().describe("Vendor/source"),
      sku: z.string().optional().describe("SKU"),
      notes: z.string().optional().describe("If provided, REPLACES the entire notes field. Pass the full new content. Use `aiAuditAppend` instead to add a one-line audit entry without touching user prose."),
      aiAuditAppend: z.string().optional().describe("A short one-line AI audit entry. Server appends with '[AI M/D/YYYY]' prefix; revises (not stacks) same-day entries. Mutually compatible with `notes` — if both passed, `notes` applied first, then `aiAuditAppend`."),
      projectId: z.string().nullable().optional().describe("Project ID — set to reassign item. Pass null to move into business inventory (budgetCategoryId is wiped automatically if needed)."),
      spaceId: z.string().nullable().optional().describe("Space ID in the resulting item scope. Pass null to detach; detached assignments are returned in the result."),
      budgetCategoryId: z.string().nullable().optional().describe("Budget category ID. Pass null to clear (required when projectId is null)."),
      transactionId: z.string().optional().describe("Transaction ID to link this item to"),
      bookmark: z.boolean().optional().describe("Bookmark flag"),
      quantity: z.coerce.number().optional().describe("Quantity (defaults to 1)"),
      taxRatePct: z.coerce.number().optional().describe("Tax rate as a percentage (e.g. 8.375)"),
    },
    async ({ itemId, ...fields }) => {
      const existing = await getDoc<Item>(db, "items", itemId);
      if (!existing) return notFound("Item", itemId);
      const callerProvidedSpaceId = Object.prototype.hasOwnProperty.call(fields, "spaceId");

      // Merge notes: `notes` replaces outright; `aiAuditAppend` appends/revises
      // a tagged AI line below whatever notes ends up being after replacement.
      let mergedNotes = existing.notes;
      if (fields.notes !== undefined) mergedNotes = fields.notes;
      if (fields.aiAuditAppend !== undefined) {
        mergedNotes = appendOrReviseAiAuditLine(mergedNotes, fields.aiAuditAppend);
      }

      const updates: Record<string, unknown> = { updatedAt: new Date() };
      if (fields.notes !== undefined || fields.aiAuditAppend !== undefined) {
        updates.notes = mergedNotes;
      }
      for (const [key, value] of Object.entries(fields)) {
        if (key === "notes" || key === "aiAuditAppend") continue;
        if (value !== undefined) updates[key] = value;
      }

      // Inventory scope has no project category. Space handling is explicit
      // whenever an existing assignment crosses scopes.
      if ("projectId" in updates && updates.projectId == null) {
        if (!("budgetCategoryId" in updates)) updates.budgetCategoryId = null;
      }
      applyItemPriceFloorToUpdate(existing, updates);

      // Enforce the inventory invariant before writing.
      const invariantError = checkUpdateInvariant(existing, updates);
      if (invariantError) {
        return validation(
          invariantError,
          "Items in business inventory have no budget category. Pass null, or set projectId."
        );
      }

      const spaceCache: SpaceCache = new Map();
      const spaceIssue = await validateItemSpaceTransition(
        db,
        itemId,
        existing,
        updates,
        callerProvidedSpaceId,
        spaceCache
      );
      if (spaceIssue) return validation(spaceIssue.message, spaceIssue.guidance);
      const detachedSpaceAssignments = [
        await detachedSpaceAssignment(db, itemId, existing, updates, spaceCache),
      ].filter((assignment): assignment is DetachedSpaceAssignment => assignment !== null);

      const linkage = checkTransactionLinkageOnUpdate(existing, updates);
      if (linkage.kind === "reject") {
        return validation(
          linkage.message,
          "Do not invent a fake transactionId to satisfy this rule. If you're trying to fix a legacy orphan, " +
            "use bulk_update_items with projectId: null to move it to inventory, then sell_items_from_inventory_to_project."
        );
      }

      // If transactionId is changing, sync itemIds on both old and new transactions
      if (fields.transactionId !== undefined) {
        const itemDoc = await accountCollection(db, "items").doc(itemId).get();
        const oldTransactionId = itemDoc.exists ? (itemDoc.data() as Record<string, unknown>)?.transactionId as string | undefined : undefined;
        const newTransactionId = fields.transactionId;

        await accountCollection(db, "items").doc(itemId).update(updates);

        if (oldTransactionId && oldTransactionId !== newTransactionId) {
          await accountCollection(db, "transactions").doc(oldTransactionId).update({
            itemIds: FieldValue.arrayRemove(itemId),
            updatedAt: new Date(),
          });
        }
        if (newTransactionId && newTransactionId !== oldTransactionId) {
          await accountCollection(db, "transactions").doc(newTransactionId).update({
            itemIds: FieldValue.arrayUnion(itemId),
            updatedAt: new Date(),
          });
        }
      } else {
        await accountCollection(db, "items").doc(itemId).update(updates);
      }

      return asToolResponse({
        message: `Updated item ${itemId}.`,
        itemId,
        detachedSpaceAssignments,
        warning: linkage.kind === "warn" ? linkage.message : null,
      });
    }
  );

  // ── bulk_update_items ───────────────────────────────────────────────────────
  server.tool(
    "bulk_update_items",
    "DOCTRINE — CORRECTIONS PRIMITIVE: This is the tool for fixing data-entry mistakes (wrong project, " +
      "wrong category, wrong vendor on the original record) WITHOUT recording a financial event. " +
      "Use it to relocate misfiled items — most commonly, pass `projectId: null` to move legacy orphans " +
      "(items in a project with no transactionId) back to inventory as a correction; then re-record the " +
      "real business event via sell_items_from_inventory_to_project.\n\n" +
      "For real business events (items actually changing hands, budgets actually shifting), use " +
      "sell_items_from_* / return_items instead.\n\n" +
      "Update a field across multiple items matching a filter. Uses Firestore batched writes (max 500 per batch). Does not support transactionId changes — use update_item individually for that. Scope changes with existing spaces require explicit spaceId handling; pass null to detach and receive a reusable assignment receipt.\n\nInventory invariant: the update is rejected upfront if applying it to any matched item would violate (projectId null ↔ budgetCategoryId null).",
    {
      filter: z.object({
        projectId: z.string().optional().describe("Filter by project ID. Use 'inventory' for items with no project."),
        spaceId: z.string().optional().describe("Filter by space ID"),
        budgetCategoryId: z.string().optional().describe("Filter by budget category"),
        status: z.string().optional().describe("Filter by status"),
        source: z.string().optional().describe("Filter by source/vendor"),
        transactionId: z.string().optional().describe("Filter by transaction ID"),
        bookmarked: z.boolean().optional().describe("Filter by bookmark status"),
      }).describe("Filter criteria — at least one field required"),
      update: z.object({
        name: z.string().optional(),
        status: z.string().optional(),
        purchasePriceCents: z.coerce.number().optional(),
        projectPriceCents: z.coerce.number().optional(),
        marketValueCents: z.coerce.number().optional(),
        source: z.string().optional(),
        sku: z.string().optional(),
        notes: z.string().optional(),
        projectId: z.string().nullable().optional().describe("Pass null to move matched items to inventory (budgetCategoryId is wiped automatically)."),
        spaceId: z.string().nullable().optional().describe("Space in the resulting scope, or null to detach and return the prior assignment."),
        budgetCategoryId: z.string().nullable().optional().describe("Pass null to clear."),
        bookmark: z.boolean().optional(),
        quantity: z.coerce.number().optional(),
        taxRatePct: z.coerce.number().optional(),
      }).describe("Fields to set on all matched items"),
    },
    async ({ filter, update }) => {
      const callerProvidedSpaceId = Object.prototype.hasOwnProperty.call(update, "spaceId");
      let query: FirebaseFirestore.Query = accountCollection(db, "items");

      if (filter.projectId === "inventory") {
        query = query.where("projectId", "==", null);
      } else if (filter.projectId) {
        query = query.where("projectId", "==", filter.projectId);
      }
      if (filter.spaceId) query = query.where("spaceId", "==", filter.spaceId);
      if (filter.budgetCategoryId) query = query.where("budgetCategoryId", "==", filter.budgetCategoryId);
      if (filter.status) query = query.where("status", "==", filter.status);
      if (filter.source) query = query.where("source", "==", filter.source);
      if (filter.transactionId) query = query.where("transactionId", "==", filter.transactionId);
      if (filter.bookmarked !== undefined) query = query.where("bookmark", "==", filter.bookmarked);

      const snapshot = await query.get();
      if (snapshot.empty) {
        return { content: [{ type: "text", text: "No items matched the filter. 0 updated." }] };
      }

      const updates: Record<string, unknown> = { updatedAt: new Date() };
      for (const [key, value] of Object.entries(update)) {
        if (value !== undefined) updates[key] = value;
      }

      // Inventory scope has no project category. Existing scoped spaces must
      // be handled explicitly when projectId changes.
      if ("projectId" in updates && updates.projectId == null) {
        if (!("budgetCategoryId" in updates)) updates.budgetCategoryId = null;
      }

      // Preflight: validate the invariant against every matched item.
      const violations: string[] = [];
      const newOrphans: string[] = [];
      const preExistingOrphans: string[] = [];
      const preparedUpdates = new Map<string, Record<string, unknown>>();
      const spaceViolations: Array<{ id: string; message: string; guidance: string }> = [];
      const detachedSpaceAssignments: DetachedSpaceAssignment[] = [];
      const spaceCache: SpaceCache = new Map();
      for (const doc of snapshot.docs) {
        const existing = doc.data() as Item & {
          projectId?: string | null;
          budgetCategoryId?: string | null;
          transactionId?: string | null;
        };
        const itemUpdates = applyItemPriceFloorToUpdate(existing, { ...updates });
        preparedUpdates.set(doc.id, itemUpdates);
        if (checkUpdateInvariant(existing, itemUpdates)) violations.push(doc.id);
        const spaceIssue = await validateItemSpaceTransition(
          db,
          doc.id,
          existing,
          itemUpdates,
          callerProvidedSpaceId,
          spaceCache
        );
        if (spaceIssue) {
          spaceViolations.push({ id: doc.id, ...spaceIssue });
        } else {
          const detached = await detachedSpaceAssignment(
            db,
            doc.id,
            existing,
            itemUpdates,
            spaceCache
          );
          if (detached) detachedSpaceAssignments.push(detached);
        }
        const linkage = checkTransactionLinkageOnUpdate(existing, itemUpdates);
        if (linkage.kind === "reject") newOrphans.push(doc.id);
        else if (linkage.kind === "warn") preExistingOrphans.push(doc.id);
      }
      if (violations.length > 0) {
        return validation(
          `Bulk update would violate the inventory invariant on ${violations.length} item(s): ${violations.slice(0, 5).join(", ")}${violations.length > 5 ? "…" : ""}`,
          "Narrow the filter, or split the update so inventory items and project items are handled separately."
        );
      }
      if (spaceViolations.length > 0) {
        const first = spaceViolations[0];
        return validation(
          `Bulk update has ${spaceViolations.length} invalid or ambiguous space assignment(s). First: ${first.message}`,
          first.guidance
        );
      }
      if (newOrphans.length > 0) {
        return validation(
          `Bulk update would CREATE ${newOrphans.length} new project-orphan item(s) (project set, no transactionId): ${newOrphans.slice(0, 5).join(", ")}${newOrphans.length > 5 ? "…" : ""}`,
          "Do not fabricate transactionIds to silence this rule. If you're trying to clean up legacy orphans, " +
            "use bulk_update_items with projectId: null to move them to inventory, then sell_items_from_inventory_to_project."
        );
      }

      let processed = 0;
      let batch = db.batch();
      let batchCount = 0;

      for (const doc of snapshot.docs) {
        batch.update(doc.ref, preparedUpdates.get(doc.id)!);
        batchCount++;
        if (batchCount === 500) {
          await batch.commit();
          processed += batchCount;
          batch = db.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) {
        await batch.commit();
        processed += batchCount;
      }

      const warning =
        preExistingOrphans.length > 0
          ? `${preExistingOrphans.length} updated item(s) are legacy project-orphans (no transactionId): ${preExistingOrphans.slice(0, 5).join(", ")}${preExistingOrphans.length > 5 ? "…" : ""}. Consider relocating via bulk_update_items projectId: null + sell_items_from_inventory_to_project.`
          : null;
      return asToolResponse({
        message: `Updated ${processed} items matching filter.`,
        updatedCount: processed,
        detachedSpaceAssignments,
        warning,
      });
    }
  );

  // ── bulk_update_items_by_id ────────────────────────────────────────────────
  server.tool(
    "bulk_update_items_by_id",
    "DOCTRINE — CORRECTIONS PRIMITIVE (per-item variant): Like bulk_update_items, this is for fixing " +
      "data-entry mistakes WITHOUT recording a financial event. Use it when each item needs different " +
      "field values (filter-based bulk_update_items can't express that). Most common correction: pass " +
      "`projectId: null` on legacy orphan items to relocate them to inventory, then re-record the real " +
      "business event with sell_items_from_inventory_to_project. For real business events (items actually " +
      "changing hands, budgets actually shifting), use sell_items_from_* / return_items.\n\n" +
      "Update multiple items by ID with per-item field values in a single batched write. Does not support transactionId changes — use update_item individually for that. Scope changes with existing spaces require explicit per-item spaceId handling; pass null to detach and receive a reusable assignment receipt.\n\nInventory invariant: each update is validated against its target item's current state. The whole call is rejected if ANY item would violate (projectId null ↔ budgetCategoryId null).",
    {
      updates: z.array(z.object({
        id: z.string().describe("Item document ID"),
        name: z.string().optional(),
        status: z.string().optional(),
        purchasePriceCents: z.coerce.number().optional(),
        projectPriceCents: z.coerce.number().optional(),
        marketValueCents: z.coerce.number().optional(),
        source: z.string().optional(),
        sku: z.string().optional(),
        notes: z.string().optional(),
        projectId: z.string().nullable().optional().describe("Pass null to move to inventory."),
        spaceId: z.string().nullable().optional().describe("Space in the resulting scope, or null to detach and return the prior assignment."),
        budgetCategoryId: z.string().nullable().optional().describe("Pass null to clear."),
        bookmark: z.boolean().optional(),
        quantity: z.coerce.number().optional(),
        taxRatePct: z.coerce.number().optional(),
      })).describe("Array of items to update, each with its own field values"),
    },
    async ({ updates }) => {
      if (updates.length === 0) {
        return { content: [{ type: "text", text: "No updates provided." }], isError: true };
      }

      const itemsCol = accountCollection(db, "items");

      // Preflight: fetch current state of each item, validate invariant,
      // and build the final updates payload. Reject the entire call if any
      // item would violate the invariant.
      type PreparedUpdate = { id: string; data: Record<string, unknown> };
      const prepared: PreparedUpdate[] = [];
      const notFoundIds: string[] = [];
      const violations: Array<{ id: string; error: string }> = [];
      const preExistingOrphans: string[] = [];
      const detachedSpaceAssignments: DetachedSpaceAssignment[] = [];
      const spaceCache: SpaceCache = new Map();

      for (const { id, ...fields } of updates) {
        const callerProvidedSpaceId = Object.prototype.hasOwnProperty.call(fields, "spaceId");
        const existing = await getDoc<Item>(db, "items", id);
        if (!existing) {
          notFoundIds.push(id);
          continue;
        }

        const itemUpdates: Record<string, unknown> = { updatedAt: new Date() };
        for (const [key, value] of Object.entries(fields)) {
          if (value !== undefined) itemUpdates[key] = value;
        }

        // Inventory scope has no project category. Existing scoped spaces must
        // be handled explicitly when projectId changes.
        if ("projectId" in itemUpdates && itemUpdates.projectId == null) {
          if (!("budgetCategoryId" in itemUpdates)) itemUpdates.budgetCategoryId = null;
        }
        applyItemPriceFloorToUpdate(existing, itemUpdates);

        const err = checkUpdateInvariant(existing, itemUpdates);
        if (err) {
          violations.push({ id, error: err });
          continue;
        }

        const spaceIssue = await validateItemSpaceTransition(
          db,
          id,
          existing,
          itemUpdates,
          callerProvidedSpaceId,
          spaceCache
        );
        if (spaceIssue) {
          violations.push({ id, error: `${spaceIssue.message} ${spaceIssue.guidance}` });
          continue;
        }
        const detached = await detachedSpaceAssignment(
          db,
          id,
          existing,
          itemUpdates,
          spaceCache
        );
        if (detached) detachedSpaceAssignments.push(detached);

        const linkage = checkTransactionLinkageOnUpdate(existing, itemUpdates);
        if (linkage.kind === "reject") {
          violations.push({ id, error: linkage.message });
          continue;
        }
        if (linkage.kind === "warn") preExistingOrphans.push(id);

        prepared.push({ id, data: itemUpdates });
      }

      if (notFoundIds.length > 0) {
        return notFound("Items", notFoundIds.join(", "), "get_items");
      }
      if (violations.length > 0) {
        const first = violations[0];
        return validation(
          `${violations.length} update(s) would violate an invariant. First (${first.id}): ${first.error}`,
          "Items in business inventory have no budget category. Project items must have a transactionId — do not fabricate one; relocate orphans to inventory instead."
        );
      }

      let processed = 0;
      let batch = db.batch();
      let batchCount = 0;

      for (const { id, data } of prepared) {
        batch.update(itemsCol.doc(id), data);
        batchCount++;
        if (batchCount === 500) {
          await batch.commit();
          processed += batchCount;
          batch = db.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) {
        await batch.commit();
        processed += batchCount;
      }

      const warning =
        preExistingOrphans.length > 0
          ? `${preExistingOrphans.length} updated item(s) are legacy project-orphans (no transactionId): ${preExistingOrphans.slice(0, 5).join(", ")}${preExistingOrphans.length > 5 ? "…" : ""}. Consider relocating via bulk_update_items projectId: null + sell_items_from_inventory_to_project.`
          : null;
      return asToolResponse({
        message: `Updated ${processed} items.`,
        updatedCount: processed,
        detachedSpaceAssignments,
        warning,
      });
    }
  );

  // ── delete_item ────────────────────────────────────────────────────────────
  server.tool(
    "delete_item",
    "Delete an item and atomically remove it from the parent transaction's itemIds array.",
    { itemId: z.string().describe("Item document ID") },
    async ({ itemId }) => {
      // Fetch item to discover its transactionId before deleting.
      // Note: narrow TOCTOU window if item is moved between read and commit —
      // acceptable because arrayRemove is a no-op if the value isn't present.
      const item = await getDoc<Item>(db, "items", itemId);
      if (!item) {
        return { content: [{ type: "text", text: `Item ${itemId} not found.` }], isError: true };
      }

      const batch = db.batch();
      batch.delete(accountCollection(db, "items").doc(itemId));

      if (item.transactionId) {
        batch.update(accountCollection(db, "transactions").doc(item.transactionId), {
          itemIds: FieldValue.arrayRemove(itemId),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // Best-effort cleanup of Storage files for any images on the item
      if (item.images?.length) {
        for (const img of item.images) {
          try { await deleteFromStorage(img.url); } catch { /* ignore */ }
          if (img.thumbnailUrlSm) {
            try { await deleteFromStorage(img.thumbnailUrlSm); } catch { /* ignore */ }
          }
          if (img.thumbnailUrlMd) {
            try { await deleteFromStorage(img.thumbnailUrlMd); } catch { /* ignore */ }
          }
        }
      }

      return { content: [{ type: "text", text: `Deleted item ${itemId}` }] };
    }
  );

  // ── attach_item_image ───────────────────────────────────────────────────────
  server.tool(
    "attach_item_image",
    "Attach an image or file to an item. Uploads to Firebase Storage and appends an AttachmentRef to the item's images array. For images, generates sm (300px) and md (800px) thumbnails. Returned URLs are public HTTPS download URLs (Firebase Storage token URLs) — fetch directly with curl/WebFetch later, no auth required.",
    {
      itemId: z.string().describe("Item document ID"),
      fileData: z.string().optional().describe("Base64-encoded file content (provide this OR fileUrl, not both)"),
      fileUrl: z.string().optional().describe("URL to fetch the file from (provide this OR fileData, not both)"),
      fileName: z.string().describe("File name (e.g. 'photo.jpg', 'spec-sheet.pdf')"),
      contentType: z.string().optional().describe("MIME type (e.g. 'image/jpeg', 'image/png', 'application/pdf'). Inferred from response headers when using fileUrl."),
    },
    async ({ itemId, fileData, fileUrl, fileName, contentType }) => {
      // 1. Validate item exists before uploading anything
      const item = await getDoc<Item>(db, "items", itemId);
      if (!item) {
        return { content: [{ type: "text", text: `Item ${itemId} not found.` }], isError: true };
      }

      // 2. Resolve file data from fileData (base64) or fileUrl
      if (!fileData && !fileUrl) {
        return { content: [{ type: "text", text: "Provide either fileData (base64) or fileUrl, not neither." }], isError: true };
      }
      if (fileData && fileUrl) {
        return { content: [{ type: "text", text: "Provide either fileData (base64) or fileUrl, not both." }], isError: true };
      }

      let data: Buffer;
      let resolvedContentType = contentType;

      if (fileUrl) {
        const res = await fetch(fileUrl);
        if (!res.ok) {
          return { content: [{ type: "text", text: `Failed to fetch file from URL: ${res.status} ${res.statusText}` }], isError: true };
        }
        data = Buffer.from(await res.arrayBuffer());
        if (!resolvedContentType) {
          resolvedContentType = res.headers.get("content-type")?.split(";")[0] ?? "application/octet-stream";
        }
      } else {
        data = Buffer.from(fileData!, "base64");
      }

      if (!resolvedContentType) {
        resolvedContentType = "application/octet-stream";
      }

      const sizeMB = data.length / (1024 * 1024);
      if (sizeMB > 10) {
        return { content: [{ type: "text", text: `File too large (${sizeMB.toFixed(1)}MB). Maximum is 10MB.` }], isError: true };
      }

      // 3. Determine attachment kind
      const kind = resolvedContentType.startsWith("image/")
        ? "image"
        : resolvedContentType === "application/pdf"
          ? "pdf"
          : "file";

      // 4. Upload primary file
      const storagePath = `${accountPath()}/items/${itemId}/${fileName}`;
      const url = await uploadToStorage(storagePath, data, resolvedContentType);

      // 5. Generate and upload thumbnails for images
      let thumbnailUrlSm: string | undefined;
      let thumbnailUrlMd: string | undefined;

      const thumbs = await generateThumbnails(data, resolvedContentType);
      if (thumbs.sm) {
        thumbnailUrlSm = await uploadToStorage(
          thumbnailPath(storagePath, "sm"), thumbs.sm, "image/jpeg"
        );
      }
      if (thumbs.md) {
        thumbnailUrlMd = await uploadToStorage(
          thumbnailPath(storagePath, "md"), thumbs.md, "image/jpeg"
        );
      }

      // 6. Build AttachmentRef entry
      const isPrimary = !item.images?.length;

      const entry: Record<string, unknown> = {
        url,
        kind,
        isPrimary,
      };
      if (fileName) entry.fileName = fileName;
      if (resolvedContentType) entry.contentType = resolvedContentType;
      if (thumbnailUrlSm) entry.thumbnailUrlSm = thumbnailUrlSm;
      if (thumbnailUrlMd) entry.thumbnailUrlMd = thumbnailUrlMd;

      // 7. Append to Firestore array
      try {
        const updates = applyItemPriceFloorToUpdate(item, {
          images: FieldValue.arrayUnion(entry),
          updatedAt: new Date(),
        });
        await accountCollection(db, "items").doc(itemId).update(updates);
      } catch (err) {
        // Clean up uploaded files on Firestore failure
        await deleteFromStorage(url).catch(() => {});
        if (thumbnailUrlSm) await deleteFromStorage(thumbnailUrlSm).catch(() => {});
        if (thumbnailUrlMd) await deleteFromStorage(thumbnailUrlMd).catch(() => {});
        throw err;
      }

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            message: `Attached ${fileName} to item ${itemId}`,
            url,
            kind,
            thumbnailUrlSm: thumbnailUrlSm ?? null,
            thumbnailUrlMd: thumbnailUrlMd ?? null,
          }, null, 2),
        }],
      };
    }
  );

  // ── detach_item_image ───────────────────────────────────────────────────────
  server.tool(
    "detach_item_image",
    "Remove an attachment from an item. Deletes the file and its thumbnails from Firebase Storage and removes the AttachmentRef from the item's images array. If the removed image was primary, promotes the next image.",
    {
      itemId: z.string().describe("Item document ID"),
      url: z.string().describe("The attachment URL to remove (matches the 'url' field in the AttachmentRef)"),
    },
    async ({ itemId, url }) => {
      const item = await getDoc<Item>(db, "items", itemId);
      if (!item) {
        return { content: [{ type: "text", text: `Item ${itemId} not found.` }], isError: true };
      }

      const attachments = item.images;
      const entry = attachments?.find((a) => a.url === url);
      if (!entry) {
        return { content: [{ type: "text", text: "No attachment with that URL found in images." }], isError: true };
      }

      // Remove the entry and promote next image to primary if needed
      let remaining = attachments!.filter((a) => a.url !== url);
      if (entry.isPrimary && remaining.length > 0) {
        remaining = remaining.map((a, i) => i === 0 ? { ...a, isPrimary: true } : a);
      }

      const updates = applyItemPriceFloorToUpdate(item, {
        images: remaining,
        updatedAt: new Date(),
      });
      await accountCollection(db, "items").doc(itemId).update(updates);

      // Delete files from Storage (best-effort)
      const deleted: string[] = [];
      try { await deleteFromStorage(url); deleted.push("primary"); } catch { /* ignore */ }
      if (entry.thumbnailUrlSm) {
        try { await deleteFromStorage(entry.thumbnailUrlSm); deleted.push("thumbnail-sm"); } catch { /* ignore */ }
      }
      if (entry.thumbnailUrlMd) {
        try { await deleteFromStorage(entry.thumbnailUrlMd); deleted.push("thumbnail-md"); } catch { /* ignore */ }
      }

      return {
        content: [{
          type: "text",
          text: `Removed attachment from item ${itemId}. Deleted from storage: ${deleted.join(", ") || "none (files may have already been removed)"}`,
        }],
      };
    }
  );
}
