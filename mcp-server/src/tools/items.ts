import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import type { Item } from "../types.js";
import { accountCollection, queryDocs, getDoc } from "../util/query.js";
import { formatCents } from "../util/format.js";

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
    bookmark: item.bookmark ?? false,
    quantity: item.quantity ?? 1,
    notes: item.notes ?? "",
    imageCount: item.images?.length ?? 0,
  };
}

export function registerItemTools(server: McpServer, db: Firestore) {
  // ── list_items ─────────────────────────────────────────────────────────────
  server.tool(
    "list_items",
    "List items with optional filters. Use projectId='inventory' for business inventory items (no project).",
    {
      projectId: z.string().optional().describe("Filter by project ID. Use 'inventory' for items with no project."),
      spaceId: z.string().optional().describe("Filter by space ID"),
      budgetCategoryId: z.string().optional().describe("Filter by budget category"),
      status: z.string().optional().describe("Filter by status (to purchase, purchased, to return, returned)"),
      bookmarked: z.boolean().optional().describe("Filter by bookmark status"),
      limit: z.number().default(50).describe("Max results"),
    },
    async ({ projectId, spaceId, budgetCategoryId, status, bookmarked, limit }) => {
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

      query = query.limit(limit);
      const items = await queryDocs<Item>(query);

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
    "Search items by name, description, SKU, or source. Case-insensitive client-side filter.",
    {
      query: z.string().describe("Search term"),
      projectId: z.string().optional().describe("Scope search to a project, or 'inventory' for business inventory"),
      limit: z.number().default(25).describe("Max results"),
    },
    async ({ query: searchTerm, projectId, limit }) => {
      let q: FirebaseFirestore.Query = accountCollection(db, "items");
      if (projectId === "inventory") {
        q = q.where("projectId", "==", null);
      } else if (projectId) {
        q = q.where("projectId", "==", projectId);
      }

      const all = await queryDocs<Item>(q);
      const term = searchTerm.toLowerCase();
      const matched = all
        .filter((item) => {
          const name = (item.name ?? "").toLowerCase();
          const desc = (item.description ?? "").toLowerCase();
          const sku = (item.sku ?? "").toLowerCase();
          const source = (item.source ?? "").toLowerCase();
          return name.includes(term) || desc.includes(term) || sku.includes(term) || source.includes(term);
        })
        .slice(0, limit);

      return { content: [{ type: "text", text: JSON.stringify(matched.map(formatItem), null, 2) }] };
    }
  );

  // ── create_item ────────────────────────────────────────────────────────────
  server.tool(
    "create_item",
    "Create a new item.",
    {
      name: z.string().describe("Item name"),
      projectId: z.string().optional().describe("Project ID (omit for business inventory)"),
      purchasePriceCents: z.number().optional().describe("Purchase price in cents"),
      projectPriceCents: z.number().optional().describe("Project price in cents"),
      status: z.string().default("purchased").describe("Status: to purchase, purchased, to return, returned"),
      source: z.string().optional().describe("Vendor/source"),
      sku: z.string().optional().describe("SKU"),
      notes: z.string().optional().describe("Notes"),
      spaceId: z.string().optional().describe("Space ID"),
      budgetCategoryId: z.string().optional().describe("Budget category ID"),
    },
    async ({ name, projectId, purchasePriceCents, projectPriceCents, status, source, sku, notes, spaceId, budgetCategoryId }) => {
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

      const ref = await accountCollection(db, "items").add(data);
      return { content: [{ type: "text", text: `Created item ${ref.id}` }] };
    }
  );

  // ── update_item ────────────────────────────────────────────────────────────
  server.tool(
    "update_item",
    "Update item fields.",
    {
      itemId: z.string().describe("Item document ID"),
      name: z.string().optional().describe("New name"),
      purchasePriceCents: z.number().optional().describe("New purchase price in cents"),
      projectPriceCents: z.number().optional().describe("New project price in cents"),
      marketValueCents: z.number().optional().describe("New market value in cents"),
      status: z.string().optional().describe("New status"),
      source: z.string().optional().describe("New vendor/source"),
      sku: z.string().optional().describe("New SKU"),
      notes: z.string().optional().describe("New notes"),
      spaceId: z.string().optional().describe("New space ID"),
      bookmark: z.boolean().optional().describe("Bookmark flag"),
    },
    async ({ itemId, name, purchasePriceCents, projectPriceCents, marketValueCents, status, source, sku, notes, spaceId, bookmark }) => {
      const updates: Record<string, unknown> = { updatedAt: new Date() };
      if (name !== undefined) updates.name = name;
      if (purchasePriceCents !== undefined) updates.purchasePriceCents = purchasePriceCents;
      if (projectPriceCents !== undefined) updates.projectPriceCents = projectPriceCents;
      if (marketValueCents !== undefined) updates.marketValueCents = marketValueCents;
      if (status !== undefined) updates.status = status;
      if (source !== undefined) updates.source = source;
      if (sku !== undefined) updates.sku = sku;
      if (notes !== undefined) updates.notes = notes;
      if (spaceId !== undefined) updates.spaceId = spaceId;
      if (bookmark !== undefined) updates.bookmark = bookmark;

      await accountCollection(db, "items").doc(itemId).update(updates);
      return { content: [{ type: "text", text: `Updated item ${itemId}` }] };
    }
  );

  // ── delete_item ────────────────────────────────────────────────────────────
  server.tool(
    "delete_item",
    "Delete an item.",
    { itemId: z.string().describe("Item document ID") },
    async ({ itemId }) => {
      await accountCollection(db, "items").doc(itemId).delete();
      return { content: [{ type: "text", text: `Deleted item ${itemId}` }] };
    }
  );
}
