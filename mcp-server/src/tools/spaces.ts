import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import type { Space, Item } from "../types.js";
import { accountCollection, queryDocs, getDoc } from "../util/query.js";

export function registerSpaceTools(server: McpServer, db: Firestore) {
  // ── list_spaces ────────────────────────────────────────────────────────────
  server.tool(
    "list_spaces",
    "List spaces with item counts. Use projectId='inventory' for business inventory spaces.",
    {
      projectId: z.string().optional().describe("Filter by project ID, or 'inventory' for business inventory"),
    },
    async ({ projectId }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "spaces");
      if (projectId === "inventory") {
        query = query.where("projectId", "==", null);
      } else if (projectId) {
        query = query.where("projectId", "==", projectId);
      }

      const spaces = await queryDocs<Space>(query);

      // Get item counts per space
      const items = await queryDocs<Item>(accountCollection(db, "items"));
      const itemCountBySpace = new Map<string, number>();
      for (const item of items) {
        if (item.spaceId) {
          itemCountBySpace.set(item.spaceId, (itemCountBySpace.get(item.spaceId) ?? 0) + 1);
        }
      }

      const rows = spaces.map((s) => ({
        id: s.id,
        name: s.name,
        projectId: s.projectId ?? null,
        notes: s.notes ?? "",
        isArchived: s.isArchived,
        itemCount: itemCountBySpace.get(s.id) ?? 0,
        checklistCount: s.checklists?.length ?? 0,
      }));

      return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── get_space ──────────────────────────────────────────────────────────────
  server.tool(
    "get_space",
    "Get a space with its items and checklist progress.",
    { spaceId: z.string().describe("Space document ID") },
    async ({ spaceId }) => {
      const space = await getDoc<Space>(db, "spaces", spaceId);
      if (!space) {
        return { content: [{ type: "text", text: `Space ${spaceId} not found.` }], isError: true };
      }

      // Items in this space
      const items = await queryDocs<Item>(
        accountCollection(db, "items").where("spaceId", "==", spaceId)
      );

      // Checklist progress
      const checklists = (space.checklists ?? []).map((cl) => {
        const total = cl.items.length;
        const checked = cl.items.filter((i) => i.isChecked).length;
        return {
          id: cl.id,
          name: cl.name,
          progress: `${checked}/${total}`,
        };
      });

      const result = {
        id: space.id,
        name: space.name,
        projectId: space.projectId ?? null,
        notes: space.notes ?? "",
        isArchived: space.isArchived,
        checklists,
        items: items.map((i) => ({
          id: i.id,
          name: i.name ?? i.description ?? "",
          status: i.status ?? "",
        })),
      };

      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    }
  );

  // ── create_space ───────────────────────────────────────────────────────────
  server.tool(
    "create_space",
    "Create a new space.",
    {
      name: z.string().describe("Space name"),
      projectId: z.string().optional().describe("Project ID (omit for business inventory)"),
      notes: z.string().optional().describe("Notes"),
    },
    async ({ name, projectId, notes }) => {
      const data: Record<string, unknown> = {
        name,
        isArchived: false,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      if (projectId) data.projectId = projectId;
      if (notes) data.notes = notes;

      const ref = await accountCollection(db, "spaces").add(data);
      return { content: [{ type: "text", text: `Created space ${ref.id}` }] };
    }
  );

  // ── update_space ───────────────────────────────────────────────────────────
  server.tool(
    "update_space",
    "Update space fields.",
    {
      spaceId: z.string().describe("Space document ID"),
      name: z.string().optional().describe("New name"),
      notes: z.string().optional().describe("New notes"),
    },
    async ({ spaceId, name, notes }) => {
      const updates: Record<string, unknown> = { updatedAt: new Date() };
      if (name !== undefined) updates.name = name;
      if (notes !== undefined) updates.notes = notes;

      await accountCollection(db, "spaces").doc(spaceId).update(updates);
      return { content: [{ type: "text", text: `Updated space ${spaceId}` }] };
    }
  );
}
