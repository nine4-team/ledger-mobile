import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import type { Project, BudgetCategory, Item } from "../types.js";
import { accountCollection, subcollection, queryDocs, getDoc } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { normalizeSpendAmount, resolveSupportedTypes, categoryPillLabel } from "../util/budget.js";
import type { Transaction, ProjectBudgetCategory } from "../types.js";

export function registerResources(server: McpServer, db: Firestore) {
  // ── ledger://projects ──────────────────────────────────────────────────────
  server.resource(
    "all-projects",
    "ledger://projects",
    { description: "All active projects with budget summaries", mimeType: "application/json" },
    async (uri) => {
      const projects = await queryDocs<Project>(
        accountCollection(db, "projects").where("isArchived", "==", false)
      );

      const rows = projects.map((p) => ({
        id: p.id,
        name: p.name,
        clientName: p.clientName,
        budget: formatCents(p.budgetSummary?.totalBudgetCents),
        spent: formatCents(p.budgetSummary?.spentCents),
      }));

      return { contents: [{ uri: uri.href, mimeType: "application/json", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── ledger://projects/{projectId} ──────────────────────────────────────────
  server.resource(
    "project-detail",
    new ResourceTemplate("ledger://projects/{projectId}", { list: undefined }),
    { description: "Single project with full details", mimeType: "application/json" },
    async (uri, params) => {
      const projectId = params.projectId as string;
      const project = await getDoc<Project>(db, "projects", projectId);
      return {
        contents: [{
          uri: uri.href,
          mimeType: "application/json",
          text: JSON.stringify(project, null, 2),
        }],
      };
    }
  );

  // ── ledger://projects/{projectId}/budget ───────────────────────────────────
  server.resource(
    "project-budget",
    new ResourceTemplate("ledger://projects/{projectId}/budget", { list: undefined }),
    { description: "Computed budget report for a project", mimeType: "text/plain" },
    async (uri, params) => {
      const projectId = params.projectId as string;

      const categories = await queryDocs<BudgetCategory>(
        accountCollection(db, "presets/default/budgetCategories")
      );
      const catMap = new Map(categories.map((c) => [c.id, c]));

      const allocations = await queryDocs<ProjectBudgetCategory>(
        subcollection(db, "projects", projectId, "budgetCategories")
      );

      const transactions = await queryDocs<Transaction>(
        accountCollection(db, "transactions").where("projectId", "==", projectId)
      );

      const spentByCategory = new Map<string, number>();
      for (const tx of transactions) {
        const catId = tx.budgetCategoryId?.trim();
        if (!catId) continue;
        spentByCategory.set(catId, (spentByCategory.get(catId) ?? 0) + normalizeSpendAmount(tx));
      }

      const lines: string[] = [`Budget Report for Project ${projectId}`, "=".repeat(50)];

      let overallBudget = 0;
      let overallSpent = 0;

      for (const alloc of allocations) {
        const cat = catMap.get(alloc.id);
        const budget = alloc.budgetCents ?? 0;
        const spent = spentByCategory.get(alloc.id) ?? 0;
        const exclude = cat?.metadata?.excludeFromOverallBudget ?? false;

        lines.push(`\n${cat?.name ?? alloc.id} (${cat ? categoryPillLabel(cat) : "General"})`);
        lines.push(`  Budget: ${formatCents(budget)}  |  Spent: ${formatCents(spent)}  |  Remaining: ${formatCents(budget - spent)}`);
        if (exclude) lines.push("  (excluded from overall budget)");

        if (!exclude) {
          overallBudget += budget;
          overallSpent += spent;
        }
      }

      lines.push("\n" + "=".repeat(50));
      lines.push(`Overall: ${formatCents(overallSpent)} / ${formatCents(overallBudget)} (${overallBudget > 0 ? Math.round((overallSpent / overallBudget) * 100) : 0}%)`);

      return { contents: [{ uri: uri.href, mimeType: "text/plain", text: lines.join("\n") }] };
    }
  );

  // ── ledger://inventory ─────────────────────────────────────────────────────
  server.resource(
    "inventory-summary",
    "ledger://inventory",
    { description: "Business inventory summary", mimeType: "application/json" },
    async (uri) => {
      const items = await queryDocs<Item>(
        accountCollection(db, "items").where("projectId", "==", null)
      );

      const statusCounts: Record<string, number> = {};
      let totalValue = 0;
      for (const item of items) {
        const s = item.status ?? "unknown";
        statusCounts[s] = (statusCounts[s] ?? 0) + 1;
        totalValue += item.purchasePriceCents ?? 0;
      }

      const summary = {
        totalItems: items.length,
        totalValue: formatCents(totalValue),
        byStatus: statusCounts,
      };

      return { contents: [{ uri: uri.href, mimeType: "application/json", text: JSON.stringify(summary, null, 2) }] };
    }
  );

  // ── ledger://budget-categories ─────────────────────────────────────────────
  server.resource(
    "budget-categories",
    "ledger://budget-categories",
    { description: "All account-level budget categories", mimeType: "application/json" },
    async (uri) => {
      const categories = await queryDocs<BudgetCategory>(
        accountCollection(db, "presets/default/budgetCategories")
      );

      const rows = categories.map((c) => ({
        id: c.id,
        name: c.name,
        categoryType: c.metadata?.categoryType ?? "general",
        supportedTypes: resolveSupportedTypes(c),
        excludeFromOverallBudget: c.metadata?.excludeFromOverallBudget ?? false,
        isArchived: c.isArchived,
      }));

      return { contents: [{ uri: uri.href, mimeType: "application/json", text: JSON.stringify(rows, null, 2) }] };
    }
  );
}
