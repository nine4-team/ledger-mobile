import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { Item, Transaction } from "../types.js";
import { accountCollection, queryDocs, getDoc } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { itemMatches } from "../util/search.js";

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
      limit: z.number().default(50).describe("Max results (ignored when fetchAll is true)"),
      offset: z.number().default(0).describe("Number of results to skip (for pagination). Use with limit to page through results."),
      fetchAll: z.boolean().default(false).describe("Return all matching items, ignoring limit/offset. Use when you need the full collection without pagination."),
    },
    async ({ projectId, spaceId, budgetCategoryId, status, bookmarked, hasTransaction, limit, offset, fetchAll }) => {
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

      return { content: [{ type: "text", text: JSON.stringify(items.map(formatItem), null, 2) }] };
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
      limit: z.number().default(25).describe("Max results"),
      offset: z.number().default(0).describe("Number of results to skip (for pagination)"),
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
    "Create a new item.",
    {
      name: z.string().describe("Item name"),
      projectId: z.string().optional().describe("Project ID (omit for business inventory). To match an item to a project, check the project's notes field — it may contain payment method details (card last 4), billing address, or other identifiers that help determine which project a purchase belongs to."),
      purchasePriceCents: z.coerce.number().optional().describe("Purchase price in cents"),
      projectPriceCents: z.coerce.number().optional().describe("Project price in cents"),
      status: z.string().default("purchased").describe("Status: to purchase, purchased, to return, returned"),
      source: z.string().optional().describe("Vendor/source"),
      sku: z.string().optional().describe("SKU"),
      notes: z.string().optional().describe("Notes"),
      spaceId: z.string().optional().describe("Space ID"),
      budgetCategoryId: z.string().optional().describe("Budget category ID"),
      transactionId: z.string().optional().describe("Transaction ID to link this item to"),
      taxRatePct: z.coerce.number().optional().describe("Tax rate as a percentage (e.g. 8.375). Auto-inherited from the linked transaction if not provided."),
    },
    async ({ name, projectId, purchasePriceCents, projectPriceCents, status, source, sku, notes, spaceId, budgetCategoryId, transactionId, taxRatePct }) => {
      // Auto-inherit taxRatePct from transaction if not explicitly provided
      let resolvedTaxRate = taxRatePct;
      if (resolvedTaxRate === undefined && transactionId) {
        const tx = await getDoc<Transaction>(db, "transactions", transactionId);
        if (tx?.taxRatePct != null) resolvedTaxRate = tx.taxRatePct;
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
      if (budgetCategoryId) data.budgetCategoryId = budgetCategoryId;
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
        if (item.budgetCategoryId) data.budgetCategoryId = item.budgetCategoryId;
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
    "Update item fields.",
    {
      itemId: z.string().describe("Item document ID"),
      name: z.string().optional().describe("Item name"),
      status: z.string().optional().describe("Item status: to purchase, purchased, to return, returned"),
      purchasePriceCents: z.coerce.number().optional().describe("Purchase price in cents"),
      projectPriceCents: z.coerce.number().optional().describe("Project price in cents"),
      marketValueCents: z.coerce.number().optional().describe("Market value in cents"),
      source: z.string().optional().describe("Vendor/source"),
      sku: z.string().optional().describe("SKU"),
      notes: z.string().optional().describe("Notes"),
      projectId: z.string().optional().describe("Project ID — set to reassign item to a different project"),
      spaceId: z.string().optional().describe("Space ID"),
      transactionId: z.string().optional().describe("Transaction ID to link this item to"),
      bookmark: z.boolean().optional().describe("Bookmark flag"),
      quantity: z.coerce.number().optional().describe("Quantity (defaults to 1)"),
      taxRatePct: z.coerce.number().optional().describe("Tax rate as a percentage (e.g. 8.375)"),
    },
    async ({ itemId, ...fields }) => {
      const updates: Record<string, unknown> = { updatedAt: new Date() };
      for (const [key, value] of Object.entries(fields)) {
        if (value !== undefined) updates[key] = value;
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
    "Update a field across multiple items matching a filter. Uses Firestore batched writes (max 500 per batch). Does not support transactionId changes — use update_item individually for that.",
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
        projectId: z.string().optional(),
        spaceId: z.string().optional(),
        budgetCategoryId: z.string().optional(),
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
    "Update multiple items by ID with per-item field values in a single batched write. Does not support transactionId changes — use update_item individually for that.",
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
        projectId: z.string().optional(),
        spaceId: z.string().optional(),
        budgetCategoryId: z.string().optional(),
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
      let processed = 0;
      let batch = db.batch();
      let batchCount = 0;

      for (const { id, ...fields } of updates) {
        const itemUpdates: Record<string, unknown> = { updatedAt: new Date() };
        for (const [key, value] of Object.entries(fields)) {
          if (value !== undefined) itemUpdates[key] = value;
        }
        batch.update(itemsCol.doc(id), itemUpdates);
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
      return { content: [{ type: "text", text: `Deleted item ${itemId}` }] };
    }
  );
}
