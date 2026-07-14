import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import type { BudgetCategory, ProjectBudgetCategory, Transaction } from "../types.js";
import { accountCollection, subcollection, queryDocs } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { normalizeSpendAmount, resolveCategoryType } from "../util/budget.js";

export function registerBudgetTools(server: McpServer, db: Firestore) {
  // ── list_budget_categories ─────────────────────────────────────────────────
  server.tool(
    "list_budget_categories",
    "List all account-level budget categories (presets).",
    {
      includeArchived: z.boolean().default(false).describe("Include archived categories"),
    },
    async ({ includeArchived }) => {
      let query: FirebaseFirestore.Query = accountCollection(
        db,
        "presets/default/budgetCategories"
      );
      if (!includeArchived) {
        query = query.where("isArchived", "==", false);
      }

      const categories = await queryDocs<BudgetCategory>(query);
      const rows = categories.map((c) => ({
        id: c.id,
        name: c.name,
        categoryType: resolveCategoryType(c),
        excludeFromOverallBudget: c.metadata?.excludeFromOverallBudget ?? false,
        isArchived: c.isArchived,
        order: c.order ?? 0,
      }));

      return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── get_project_budget_categories ──────────────────────────────────────────
  server.tool(
    "get_project_budget_categories",
    "List enabled budget categories for a project with allocations and computed spend.",
    { projectId: z.string().describe("Project document ID") },
    async ({ projectId }) => {
      // Account categories
      const categories = await queryDocs<BudgetCategory>(
        accountCollection(db, "presets/default/budgetCategories")
      );
      const catMap = new Map(categories.map((c) => [c.id, c]));

      // Project allocations
      const allocations = await queryDocs<ProjectBudgetCategory>(
        subcollection(db, "projects", projectId, "budgetCategories")
      );

      // Project transactions for spend
      const transactions = await queryDocs<Transaction>(
        accountCollection(db, "transactions").where("projectId", "==", projectId)
      );
      const spentByCategory = new Map<string, number>();
      for (const tx of transactions) {
        const catId = tx.budgetCategoryId?.trim();
        if (!catId) continue;
        spentByCategory.set(catId, (spentByCategory.get(catId) ?? 0) + normalizeSpendAmount(tx));
      }

      const rows = allocations.map((alloc) => {
        const cat = catMap.get(alloc.id);
        const spent = spentByCategory.get(alloc.id) ?? 0;
        return {
          id: alloc.id,
          name: cat?.name ?? "",
          categoryType: cat ? resolveCategoryType(cat) : "general",
          budget: formatCents(alloc.budgetCents),
          budgetCents: alloc.budgetCents ?? 0,
          spent: formatCents(spent),
          spentCents: spent,
          excludeFromOverallBudget: cat?.metadata?.excludeFromOverallBudget ?? false,
        };
      });

      return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── update_project_budget_allocation ───────────────────────────────────────
  server.tool(
    "update_project_budget_allocation",
    "Set or update the budget amount for a category in a project.",
    {
      projectId: z.string().describe("Project document ID"),
      budgetCategoryId: z.string().describe("Budget category document ID"),
      budgetCents: z.coerce.number().describe("Budget amount in cents"),
    },
    async ({ projectId, budgetCategoryId, budgetCents }) => {
      const ref = subcollection(db, "projects", projectId, "budgetCategories").doc(budgetCategoryId);
      await ref.set(
        { budgetCents, updatedAt: new Date() },
        { merge: true }
      );
      return {
        content: [{ type: "text", text: `Set ${budgetCategoryId} budget to ${formatCents(budgetCents)} for project ${projectId}` }],
      };
    }
  );

  // ── enable_category_for_project ────────────────────────────────────────────
  server.tool(
    "enable_category_for_project",
    "Enable a budget category for a project. Creates the project budget category document.",
    {
      projectId: z.string().describe("Project document ID"),
      budgetCategoryId: z.string().describe("Budget category document ID"),
      budgetCents: z.coerce.number().optional().describe("Optional initial budget in cents"),
    },
    async ({ projectId, budgetCategoryId, budgetCents }) => {
      const ref = subcollection(db, "projects", projectId, "budgetCategories").doc(budgetCategoryId);
      const data: Record<string, unknown> = { createdAt: new Date(), updatedAt: new Date() };
      if (budgetCents !== undefined) data.budgetCents = budgetCents;

      await ref.set(data, { merge: true });
      return {
        content: [{ type: "text", text: `Enabled category ${budgetCategoryId} for project ${projectId}` }],
      };
    }
  );
}
