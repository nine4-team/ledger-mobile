import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import type { Project, Transaction, BudgetCategory, ProjectBudgetCategory } from "../types.js";
import { accountCollection, subcollection, queryDocs, getDoc } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { normalizeSpendAmount } from "../util/budget.js";

export function registerProjectTools(server: McpServer, db: Firestore) {
  // ── list_projects ──────────────────────────────────────────────────────────
  server.tool(
    "list_projects",
    "List all projects. Returns name, client, archive status, and denormalized budget summary.",
    { filter: z.enum(["active", "archived", "all"]).default("active").describe("Filter by archive status") },
    async ({ filter }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "projects");
      if (filter === "active") query = query.where("isArchived", "!=", true);
      else if (filter === "archived") query = query.where("isArchived", "==", true);

      const projects = await queryDocs<Project>(query);

      const rows = projects.map((p) => {
        const bs = p.budgetSummary;
        return {
          id: p.id,
          name: p.name || "",
          clientName: p.clientName || "",
          isArchived: p.isArchived ?? false,
          budget: formatCents(bs?.totalBudgetCents),
          spent: formatCents(bs?.spentCents),
        };
      });

      return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── get_project ────────────────────────────────────────────────────────────
  server.tool(
    "get_project",
    "Get a single project with full details including budget summary.",
    { projectId: z.string().describe("Project document ID") },
    async ({ projectId }) => {
      const project = await getDoc<Project>(db, "projects", projectId);
      if (!project) {
        return { content: [{ type: "text", text: `Project ${projectId} not found.` }], isError: true };
      }
      return { content: [{ type: "text", text: JSON.stringify(project, null, 2) }] };
    }
  );

  // ── get_project_budget ─────────────────────────────────────────────────────
  server.tool(
    "get_project_budget",
    "Compute live budget breakdown for a project from transactions. Shows per-category budget vs. spent with variance.",
    { projectId: z.string().describe("Project document ID") },
    async ({ projectId }) => {
      // 1. Account-level budget categories
      const categories = await queryDocs<BudgetCategory>(
        accountCollection(db, "presets/default/budgetCategories")
      );
      const catMap = new Map(categories.map((c) => [c.id, c]));

      // 2. Project budget allocations
      const allocations = await queryDocs<ProjectBudgetCategory>(
        subcollection(db, "projects", projectId, "budgetCategories")
      );
      const allocMap = new Map(allocations.map((a) => [a.id, a]));

      // 3. Project transactions
      const transactions = await queryDocs<Transaction>(
        accountCollection(db, "transactions").where("projectId", "==", projectId)
      );

      // 4. Compute spend per category
      const spentByCategory = new Map<string, number>();
      for (const tx of transactions) {
        const catId = tx.budgetCategoryId?.trim();
        if (!catId) continue;
        const amount = normalizeSpendAmount(tx);
        spentByCategory.set(catId, (spentByCategory.get(catId) ?? 0) + amount);
      }

      // 5. Build report
      const allCatIds = new Set([
        ...catMap.keys(),
        ...allocMap.keys(),
        ...spentByCategory.keys(),
      ]);

      let overallBudget = 0;
      let overallSpent = 0;
      const categoryRows: Record<string, unknown>[] = [];

      for (const catId of allCatIds) {
        const cat = catMap.get(catId);
        const alloc = allocMap.get(catId);
        const budgetCents = alloc?.budgetCents ?? 0;
        const spentCents = spentByCategory.get(catId) ?? 0;
        if (budgetCents === 0 && spentCents === 0 && !alloc) continue;

        const exclude = cat?.metadata?.excludeFromOverallBudget ?? false;
        const variance = budgetCents - spentCents;

        categoryRows.push({
          id: catId,
          name: cat?.name ?? "",
          categoryType: cat?.metadata?.categoryType ?? "general",
          budget: formatCents(budgetCents),
          spent: formatCents(spentCents),
          variance: formatCents(variance),
          percentUsed: budgetCents > 0 ? `${Math.round((spentCents / budgetCents) * 100)}%` : "N/A",
          excludeFromOverall: exclude,
          enabled: !!alloc,
        });

        if (!exclude) {
          overallBudget += budgetCents;
          overallSpent += spentCents;
        }
      }

      const report = {
        projectId,
        overall: {
          budget: formatCents(overallBudget),
          spent: formatCents(overallSpent),
          variance: formatCents(overallBudget - overallSpent),
          percentUsed: overallBudget > 0 ? `${Math.round((overallSpent / overallBudget) * 100)}%` : "N/A",
        },
        categories: categoryRows,
        transactionCount: transactions.length,
      };

      return { content: [{ type: "text", text: JSON.stringify(report, null, 2) }] };
    }
  );

  // ── create_project ─────────────────────────────────────────────────────────
  server.tool(
    "create_project",
    "Create a new project.",
    {
      name: z.string().describe("Project name"),
      clientName: z.string().default("").describe("Client name"),
      description: z.string().optional().describe("Project description"),
    },
    async ({ name, clientName, description }) => {
      const data: Record<string, unknown> = {
        name,
        clientName,
        isArchived: false,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      if (description) data.description = description;

      const ref = await accountCollection(db, "projects").add(data);
      return { content: [{ type: "text", text: `Created project ${ref.id}` }] };
    }
  );

  // ── update_project ─────────────────────────────────────────────────────────
  server.tool(
    "update_project",
    "Update project fields.",
    {
      projectId: z.string().describe("Project document ID"),
      name: z.string().optional().describe("New project name"),
      clientName: z.string().optional().describe("New client name"),
      description: z.string().optional().describe("New description"),
    },
    async ({ projectId, name, clientName, description }) => {
      const updates: Record<string, unknown> = { updatedAt: new Date() };
      if (name !== undefined) updates.name = name;
      if (clientName !== undefined) updates.clientName = clientName;
      if (description !== undefined) updates.description = description;

      await accountCollection(db, "projects").doc(projectId).update(updates);
      return { content: [{ type: "text", text: `Updated project ${projectId}` }] };
    }
  );

  // ── archive_project ────────────────────────────────────────────────────────
  server.tool(
    "archive_project",
    "Archive or unarchive a project.",
    {
      projectId: z.string().describe("Project document ID"),
      archive: z.boolean().describe("true to archive, false to unarchive"),
    },
    async ({ projectId, archive }) => {
      await accountCollection(db, "projects").doc(projectId).update({
        isArchived: archive,
        updatedAt: new Date(),
      });
      return { content: [{ type: "text", text: `${archive ? "Archived" : "Unarchived"} project ${projectId}` }] };
    }
  );
}
