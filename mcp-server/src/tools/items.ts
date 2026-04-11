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
import { requireAuditNote, notFound, validation } from "../util/errors.js";

// ─────────────────────────────────────────────────────────────────────────────
// Inventory invariant helpers (per-batch sale redesign).
//
// Rule: (item.projectId == null) ↔ (item.budgetCategoryId == null)
// Items in business inventory have no budget category. Categories are
// resolved at sell-into-project time. See docs/specs/sale-transactions.md
// and docs/specs/inventory-as-store.md.
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
      "Pass both projectId and budgetCategoryId in the same update, or use sell_items instead."
    );
  }

  return null;
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
    projectPrice: formatCents(item.projectPriceCents),
    marketValue: formatCents(item.marketValueCents),
    transactionId: item.transactionId ?? null,
    bookmark: item.bookmark ?? false,
    quantity: item.quantity ?? 1,
    taxRatePct: item.taxRatePct ?? null,
    notes: item.notes ?? "",
    imageCount: item.images?.length ?? 0,
  };
}

export function registerItemTools(server: McpServer, db: Firestore) {
  // ── list_items ─────────────────────────────────────────────────────────────
  server.tool(
    "list_items",
    "List items with optional filters. Supports pagination via offset + limit. Use projectId='inventory' for business inventory items (no project).",
    {
      projectId: z.string().optional().describe("Filter by project ID. Use 'inventory' for items with no project."),
      spaceId: z.string().optional().describe("Filter by space ID"),
      budgetCategoryId: z.string().optional().describe("Filter by budget category"),
      status: z.string().optional().describe("Filter by status (to purchase, purchased, to return, returned)"),
      bookmarked: z.boolean().optional().describe("Filter by bookmark status"),
      hasTransaction: z.boolean().optional().describe("Filter by transaction linkage: true = only items with a transactionId, false = only items with NO transactionId"),
      limit: z.coerce.number().default(50).describe("Max results (ignored when fetchAll is true)"),
      offset: z.coerce.number().default(0).describe("Number of results to skip (for pagination). Use with limit to page through results."),
      fetchAll: z.boolean().default(false).describe("Return all matching items, ignoring limit/offset. Use when you need the full collection without pagination."),
      mode: ProjectionMode.describe("'summary' (default) or 'full'."),
      fields: z.array(z.string()).optional().describe("Explicit field list. Overrides mode."),
      responseLimit: ResponseLimitArg,
    },
    async ({ projectId, spaceId, budgetCategoryId, status, bookmarked, hasTransaction, limit, offset, fetchAll, mode, fields, responseLimit }) => {
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

      // Firestore can't query "field does not exist", so we filter client-side
      let clientFilter: ((item: Item & { id: string }) => boolean) | null = null;
      if (hasTransaction === true) {
        clientFilter = (item) => !!item.transactionId;
      } else if (hasTransaction === false) {
        clientFilter = (item) => !item.transactionId;
      }

      if (!fetchAll && !clientFilter) {
        query = query.offset(offset).limit(limit);
      }
      let items = await queryDocs<Item>(query);
      if (clientFilter) items = items.filter(clientFilter);
      if (!fetchAll) items = items.slice(offset, offset + limit);

      const projected = items.map((i) => {
        if (fields && fields.length) return pickFields(i as unknown as Record<string, unknown>, fields);
        return mode === "full" ? (i as unknown as Record<string, unknown>) : (itemSummary(i) as unknown as Record<string, unknown>);
      });
      return asToolResponse(capResponse(projected, { limitBytes: responseLimit }));
    }
  );

  // ── get_item ───────────────────────────────────────────────────────────────
  server.tool(
    "get_item",
    "Get a single item with all details.",
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
    "Search items by name, description, SKU, source, notes, or amount. Case-insensitive client-side filter. Supports pagination via offset + limit.",
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
    "[mutating] Create a new item. Requires a dated audit note in `notes`.",
    {
      name: z.string().describe("Item name"),
      projectId: z.string().optional().describe("Project ID (omit for business inventory). To match an item to a project, check the project's notes field — it may contain payment method details (card last 4), billing address, or other identifiers that help determine which project a purchase belongs to."),
      purchasePriceCents: z.coerce.number().optional().describe("Purchase price in cents"),
      projectPriceCents: z.coerce.number().optional().describe("Project price in cents"),
      status: z.string().default("purchased").describe("Status: to purchase, purchased, to return, returned"),
      source: z.string().optional().describe("Vendor/source"),
      sku: z.string().optional().describe("SKU"),
      notes: z.string().describe("REQUIRED dated audit note, e.g. '4/6 — added chair from Restoration Hardware receipt'"),
      spaceId: z.string().optional().describe("Space ID"),
      budgetCategoryId: z.string().optional().describe("Budget category ID. Auto-inherited from the linked transaction if not provided."),
      transactionId: z.string().optional().describe("Transaction ID to link this item to"),
      taxRatePct: z.coerce.number().optional().describe("Tax rate as a percentage (e.g. 8.375). Auto-inherited from the linked transaction if not provided."),
    },
    async ({ name, projectId, purchasePriceCents, projectPriceCents, status, source, sku, notes, spaceId, budgetCategoryId, transactionId, taxRatePct }) => {
      const noteError = requireAuditNote(notes, "create_item");
      if (noteError) return noteError;
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

      const data: Record<string, unknown> = {
        name,
        status,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      if (projectId) data.projectId = projectId;
      if (purchasePriceCents !== undefined) data.purchasePriceCents = purchasePriceCents;
      if (projectPriceCents !== undefined) data.projectPriceCents = projectPriceCents;
      if (source) data.source = source;
      if (sku) data.sku = sku;
      if (notes) data.notes = notes;
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

        const data: Record<string, unknown> = {
          name: item.name,
          status: item.status,
          createdAt: new Date(),
          updatedAt: new Date(),
        };
        if (resolvedProjectId) data.projectId = resolvedProjectId;
        if (item.purchasePriceCents !== undefined) data.purchasePriceCents = item.purchasePriceCents;
        if (item.projectPriceCents !== undefined) data.projectPriceCents = item.projectPriceCents;
        if (item.source) data.source = item.source;
        if (item.sku) data.sku = item.sku;
        if (item.notes) data.notes = item.notes;
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
    "[mutating] Update item fields. Requires a dated audit note in `notes`.\n\n" +
      "Inventory invariant: items in business inventory (projectId: null) must have " +
      "budgetCategoryId: null. Pass null explicitly to either field to clear it. Moving " +
      "an item from inventory into a project requires passing both projectId AND " +
      "budgetCategoryId in the same update.",
    {
      itemId: z.string().describe("Item document ID"),
      name: z.string().optional().describe("Item name"),
      status: z.string().optional().describe("Item status: to purchase, purchased, to return, returned"),
      purchasePriceCents: z.coerce.number().optional().describe("Purchase price in cents"),
      projectPriceCents: z.coerce.number().optional().describe("Project price in cents"),
      marketValueCents: z.coerce.number().optional().describe("Market value in cents"),
      source: z.string().optional().describe("Vendor/source"),
      sku: z.string().optional().describe("SKU"),
      notes: z.string().describe("REQUIRED dated audit note for this update, appended to existing notes"),
      projectId: z.string().nullable().optional().describe("Project ID — set to reassign item. Pass null to move into business inventory (budgetCategoryId is wiped automatically if needed)."),
      spaceId: z.string().nullable().optional().describe("Space ID. Pass null to clear."),
      budgetCategoryId: z.string().nullable().optional().describe("Budget category ID. Pass null to clear (required when projectId is null)."),
      transactionId: z.string().optional().describe("Transaction ID to link this item to"),
      bookmark: z.boolean().optional().describe("Bookmark flag"),
      quantity: z.coerce.number().optional().describe("Quantity (defaults to 1)"),
      taxRatePct: z.coerce.number().optional().describe("Tax rate as a percentage (e.g. 8.375)"),
    },
    async ({ itemId, ...fields }) => {
      const noteError = requireAuditNote(fields.notes, "update_item");
      if (noteError) return noteError;
      const existing = await getDoc<Item>(db, "items", itemId);
      if (!existing) return notFound("Item", itemId);
      const mergedNotes = existing.notes ? `${existing.notes}\n${fields.notes}` : fields.notes;

      const updates: Record<string, unknown> = { updatedAt: new Date(), notes: mergedNotes };
      for (const [key, value] of Object.entries(fields)) {
        if (key === "notes") continue;
        if (value !== undefined) updates[key] = value;
      }

      // If the caller is clearing projectId and didn't explicitly clear
      // budgetCategoryId, wipe it as well so the invariant holds.
      if ("projectId" in updates && updates.projectId == null && !("budgetCategoryId" in updates)) {
        updates.budgetCategoryId = null;
      }

      // Enforce the inventory invariant before writing.
      const invariantError = checkUpdateInvariant(existing, updates);
      if (invariantError) {
        return validation(
          invariantError,
          "Items in business inventory have no budget category. Pass null, or set projectId."
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

      return { content: [{ type: "text", text: `Updated item ${itemId}` }] };
    }
  );

  // ── bulk_update_items ───────────────────────────────────────────────────────
  server.tool(
    "bulk_update_items",
    "Update a field across multiple items matching a filter. Uses Firestore batched writes (max 500 per batch). Does not support transactionId changes — use update_item individually for that.\n\nInventory invariant: the update is rejected upfront if applying it to any matched item would violate (projectId null ↔ budgetCategoryId null).",
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
        spaceId: z.string().nullable().optional(),
        budgetCategoryId: z.string().nullable().optional().describe("Pass null to clear."),
        bookmark: z.boolean().optional(),
        quantity: z.coerce.number().optional(),
        taxRatePct: z.coerce.number().optional(),
      }).describe("Fields to set on all matched items"),
    },
    async ({ filter, update }) => {
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

      // If the update clears projectId and didn't touch budgetCategoryId, wipe it.
      if ("projectId" in updates && updates.projectId == null && !("budgetCategoryId" in updates)) {
        updates.budgetCategoryId = null;
      }

      // Preflight: validate the invariant against every matched item.
      const violations: string[] = [];
      for (const doc of snapshot.docs) {
        const existing = doc.data() as { projectId?: string | null; budgetCategoryId?: string | null };
        const err = checkUpdateInvariant(existing, updates);
        if (err) violations.push(doc.id);
      }
      if (violations.length > 0) {
        return validation(
          `Bulk update would violate the inventory invariant on ${violations.length} item(s): ${violations.slice(0, 5).join(", ")}${violations.length > 5 ? "…" : ""}`,
          "Narrow the filter, or split the update so inventory items and project items are handled separately."
        );
      }

      let processed = 0;
      let batch = db.batch();
      let batchCount = 0;

      for (const doc of snapshot.docs) {
        batch.update(doc.ref, updates);
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

      return {
        content: [{ type: "text", text: `Updated ${processed} items matching filter.` }],
      };
    }
  );

  // ── bulk_update_items_by_id ────────────────────────────────────────────────
  server.tool(
    "bulk_update_items_by_id",
    "Update multiple items by ID with per-item field values in a single batched write. Does not support transactionId changes — use update_item individually for that.\n\nInventory invariant: each update is validated against its target item's current state. The whole call is rejected if ANY item would violate (projectId null ↔ budgetCategoryId null).",
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
        spaceId: z.string().nullable().optional(),
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

      for (const { id, ...fields } of updates) {
        const existing = await getDoc<Item>(db, "items", id);
        if (!existing) {
          notFoundIds.push(id);
          continue;
        }

        const itemUpdates: Record<string, unknown> = { updatedAt: new Date() };
        for (const [key, value] of Object.entries(fields)) {
          if (value !== undefined) itemUpdates[key] = value;
        }

        // Wipe category when clearing projectId.
        if ("projectId" in itemUpdates && itemUpdates.projectId == null && !("budgetCategoryId" in itemUpdates)) {
          itemUpdates.budgetCategoryId = null;
        }

        const err = checkUpdateInvariant(existing, itemUpdates);
        if (err) {
          violations.push({ id, error: err });
          continue;
        }

        prepared.push({ id, data: itemUpdates });
      }

      if (notFoundIds.length > 0) {
        return notFound("Items", notFoundIds.join(", "), "get_items");
      }
      if (violations.length > 0) {
        return validation(
          `${violations.length} update(s) would violate the inventory invariant: ${violations.slice(0, 3).map((v) => v.id).join(", ")}${violations.length > 3 ? "…" : ""}`,
          "Items in business inventory have no budget category. Pass null for budgetCategoryId on inventory items."
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

      return { content: [{ type: "text", text: `Updated ${processed} items.` }] };
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
    "Attach an image or file to an item. Uploads to Firebase Storage and appends an AttachmentRef to the item's images array. For images, generates sm (300px) and md (800px) thumbnails.",
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
        await accountCollection(db, "items").doc(itemId).update({
          images: FieldValue.arrayUnion(entry),
          updatedAt: new Date(),
        });
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

      await accountCollection(db, "items").doc(itemId).update({
        images: remaining,
        updatedAt: new Date(),
      });

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
