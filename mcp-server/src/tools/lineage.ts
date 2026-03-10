import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import type { LineageEdge, Project, Transaction } from "../types.js";
import { accountCollection, queryDocs, getDoc } from "../util/query.js";
import { formatDate } from "../util/format.js";

async function resolveEdge(
  db: Firestore,
  edge: LineageEdge & { id: string },
  projectCache: Map<string, string>,
  txCache: Map<string, string>
) {
  // Resolve project names
  const resolveProject = async (pid: string | undefined) => {
    if (!pid) return null;
    if (projectCache.has(pid)) return projectCache.get(pid)!;
    const p = await getDoc<Project>(db, "projects", pid);
    const name = p?.name ?? pid;
    projectCache.set(pid, name);
    return name;
  };

  // Resolve transaction source
  const resolveTx = async (txId: string | undefined) => {
    if (!txId) return null;
    if (txCache.has(txId)) return txCache.get(txId)!;
    const tx = await getDoc<Transaction>(db, "transactions", txId);
    const label = tx?.source ?? txId;
    txCache.set(txId, label);
    return label;
  };

  return {
    id: edge.id,
    movementKind: edge.movementKind ?? "",
    itemId: edge.itemId ?? "",
    fromProject: await resolveProject(edge.fromProjectId),
    toProject: await resolveProject(edge.toProjectId),
    fromTransaction: await resolveTx(edge.fromTransactionId),
    toTransaction: await resolveTx(edge.toTransactionId),
    note: edge.note ?? "",
    source: edge.source ?? "",
    date: formatDate(edge.createdAt),
  };
}

export function registerLineageTools(server: McpServer, db: Firestore) {
  // ── get_item_history ───────────────────────────────────────────────────────
  server.tool(
    "get_item_history",
    "Get chronological movement history for an item, with project and transaction names resolved.",
    { itemId: z.string().describe("Item document ID") },
    async ({ itemId }) => {
      const edges = await queryDocs<LineageEdge>(
        accountCollection(db, "lineageEdges")
          .where("itemId", "==", itemId)
          .orderBy("createdAt", "asc")
      );

      const projectCache = new Map<string, string>();
      const txCache = new Map<string, string>();
      const resolved = await Promise.all(
        edges.map((e) => resolveEdge(db, e, projectCache, txCache))
      );

      return { content: [{ type: "text", text: JSON.stringify(resolved, null, 2) }] };
    }
  );

  // ── get_project_movements ──────────────────────────────────────────────────
  server.tool(
    "get_project_movements",
    "Get all item movements into or out of a project.",
    {
      projectId: z.string().describe("Project document ID"),
      movementKind: z.string().optional().describe("Filter by movement kind: association, sold, returned, correction"),
    },
    async ({ projectId, movementKind }) => {
      // Edges where project is source or destination
      const [fromEdges, toEdges] = await Promise.all([
        queryDocs<LineageEdge>(
          accountCollection(db, "lineageEdges").where("fromProjectId", "==", projectId)
        ),
        queryDocs<LineageEdge>(
          accountCollection(db, "lineageEdges").where("toProjectId", "==", projectId)
        ),
      ]);

      // Deduplicate by edge ID
      const edgeMap = new Map<string, LineageEdge & { id: string }>();
      for (const e of [...fromEdges, ...toEdges]) {
        edgeMap.set(e.id, e);
      }

      let edges = Array.from(edgeMap.values());
      if (movementKind) {
        edges = edges.filter((e) => e.movementKind === movementKind);
      }

      const projectCache = new Map<string, string>();
      const txCache = new Map<string, string>();
      const resolved = await Promise.all(
        edges.map((e) => resolveEdge(db, e, projectCache, txCache))
      );

      return { content: [{ type: "text", text: JSON.stringify(resolved, null, 2) }] };
    }
  );
}
