import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import type { Project, Transaction, BudgetCategory, ProjectBudgetCategory } from "../types.js";
import { accountCollection, subcollection, queryDocs, getDoc } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { normalizeSpendAmount } from "../util/budget.js";
import {
  ProjectionMode,
  projectSummary,
  capResponse,
  asToolResponse,
  pickFields,
} from "../util/projections.js";
import { requireAuditNote, notFound } from "../util/errors.js";

export function registerProjectTools(server: McpServer, db: Firestore) {
  // ── list_projects ──────────────────────────────────────────────────────────
  server.tool(
    "list_projects",
    "List all projects. Returns name, client, notes, archive status, and denormalized budget summary. The notes field may contain client-specific context useful for matching receipts to projects — payment method details (e.g. card last 4 digits), billing address variations, or other identifiers.",
    {
      filter: z.enum(["active", "archived", "all"]).default("active").describe("Filter by archive status"),
      mode: ProjectionMode.describe("'summary' (default) or 'full'."),
      fields: z.array(z.string()).optional().describe("Explicit field list. Overrides mode."),
    },
    async ({ filter, mode, fields }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "projects");
      if (filter === "active") query = query.where("isArchived", "==", false);
      else if (filter === "archived") query = query.where("isArchived", "==", true);

      const projects = await queryDocs<Project>(query);
      const projected = projects.map((p) => {
        if (fields && fields.length) return pickFields(p as unknown as Record<string, unknown>, fields);
        return mode === "full" ? (p as unknown as Record<string, unknown>) : (projectSummary(p) as unknown as Record<string, unknown>);
      });
      return asToolResponse(capResponse(projected));
    }
  );

  // ── get_project ────────────────────────────────────────────────────────────
  server.tool(
    "get_project",
    "Get a single project with full details including budget summary. The notes field may contain client-specific context useful for matching receipts to projects — payment method details (e.g. card last 4 digits), billing address variations, or other identifiers.",
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
    "[mutating] Create a new project. Requires a dated audit note in `notes` — written to the project's notes subcollection.",
    {
      name: z.string().describe("Project name"),
      clientName: z.string().default("").describe("Client name"),
      description: z.string().optional().describe("Project description"),
      notes: z.string().describe("REQUIRED dated audit note, e.g. '4/6 — New Witzenman 2nd home project, signed contract'. May also contain receipt-matching hints."),
    },
    async ({ name, clientName, description, notes }) => {
      const noteError = requireAuditNote(notes, "create_project");
      if (noteError) return noteError;
      const data: Record<string, unknown> = {
        name,
        clientName,
        isArchived: false,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      if (description) data.description = description;

      const ref = await accountCollection(db, "projects").add(data);

      if (notes) {
        await subcollection(db, "projects", ref.id, "notes").add({
          text: notes,
          source: "mcp",
          createdBy: "mcp-agent",
          createdByName: "AI Assistant",
          createdAt: new Date(),
        });
      }

      return { content: [{ type: "text", text: `Created project ${ref.id}` }] };
    }
  );

  // ── update_project ─────────────────────────────────────────────────────────
  server.tool(
    "update_project",
    "[mutating] Update project fields. Requires a dated audit note in `notes` — written to the project's notes subcollection (not the legacy string field).",
    {
      projectId: z.string().describe("Project document ID"),
      name: z.string().optional().describe("New project name"),
      clientName: z.string().optional().describe("New client name"),
      description: z.string().optional().describe("New description"),
      notes: z.string().describe("REQUIRED dated audit note for this update"),
    },
    async ({ projectId, name, clientName, description, notes }) => {
      const noteError = requireAuditNote(notes, "update_project");
      if (noteError) return noteError;
      const existing = await getDoc<Project>(db, "projects", projectId);
      if (!existing) return notFound("Project", projectId);

      const updates: Record<string, unknown> = { updatedAt: new Date() };
      if (name !== undefined) updates.name = name;
      if (clientName !== undefined) updates.clientName = clientName;
      if (description !== undefined) updates.description = description;

      await accountCollection(db, "projects").doc(projectId).update(updates);

      await subcollection(db, "projects", projectId, "notes").add({
        text: notes,
        source: "mcp",
        createdBy: "mcp-agent",
        createdByName: "AI Assistant",
        createdAt: new Date(),
      });

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
