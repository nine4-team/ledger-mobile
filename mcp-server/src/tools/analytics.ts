import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import type { Item, Transaction, BudgetCategory, ProjectBudgetCategory } from "../types.js";
import { accountCollection, subcollection, queryDocs } from "../util/query.js";
import { formatCents } from "../util/format.js";
import { normalizeSpendAmount } from "../util/budget.js";

export function registerAnalyticsTools(server: McpServer, db: Firestore) {
  // ── project_health ─────────────────────────────────────────────────────────
  server.tool(
    "project_health",
    "Comprehensive project health snapshot: budget utilization, item counts by status, items needing attention.",
    { projectId: z.string().describe("Project document ID") },
    async ({ projectId }) => {
      const [items, transactions] = await Promise.all([
        queryDocs<Item>(accountCollection(db, "items").where("projectId", "==", projectId)),
        queryDocs<Transaction>(accountCollection(db, "transactions").where("projectId", "==", projectId)),
      ]);

      // Item stats
      const statusCounts: Record<string, number> = {};
      let missingPrice = 0;
      let missingSku = 0;
      let missingName = 0;
      let bookmarked = 0;

      for (const item of items) {
        const s = item.status ?? "unknown";
        statusCounts[s] = (statusCounts[s] ?? 0) + 1;
        if (!item.purchasePriceCents && !item.projectPriceCents) missingPrice++;
        if (!item.sku) missingSku++;
        if (!item.name && !item.description) missingName++;
        if (item.bookmark) bookmarked++;
      }

      // Budget from denormalized summary or compute
      const categories = await queryDocs<BudgetCategory>(
        accountCollection(db, "presets/default/budgetCategories")
      );
      const allocations = await queryDocs<ProjectBudgetCategory>(
        subcollection(db, "projects", projectId, "budgetCategories")
      );

      let totalBudget = 0;
      let totalSpent = 0;
      for (const alloc of allocations) {
        const cat = categories.find((c) => c.id === alloc.id);
        const exclude = cat?.metadata?.excludeFromOverallBudget ?? false;
        if (!exclude) {
          totalBudget += alloc.budgetCents ?? 0;
        }
      }
      for (const tx of transactions) {
        const cat = categories.find((c) => c.id === tx.budgetCategoryId);
        const exclude = cat?.metadata?.excludeFromOverallBudget ?? false;
        if (!exclude) {
          totalSpent += normalizeSpendAmount(tx);
        }
      }

      const incomplete = transactions.filter((t) => t.isComplete === false).length;

      const report = {
        projectId,
        budget: {
          total: formatCents(totalBudget),
          spent: formatCents(totalSpent),
          remaining: formatCents(totalBudget - totalSpent),
          utilizationPct: totalBudget > 0 ? `${Math.round((totalSpent / totalBudget) * 100)}%` : "N/A",
        },
        items: {
          total: items.length,
          byStatus: statusCounts,
          bookmarked,
        },
        transactions: {
          total: transactions.length,
          incomplete,
        },
        attention: {
          itemsMissingPrice: missingPrice,
          itemsMissingSku: missingSku,
          itemsMissingName: missingName,
          incompleteTransactions: incomplete,
        },
      };

      return { content: [{ type: "text", text: JSON.stringify(report, null, 2) }] };
    }
  );

  // ── inventory_summary ──────────────────────────────────────────────────────
  server.tool(
    "inventory_summary",
    "Business inventory overview: total items, value, breakdown by status and vendor.",
    {},
    async () => {
      const items = await queryDocs<Item>(
        accountCollection(db, "items").where("projectId", "==", null)
      );

      const statusCounts: Record<string, number> = {};
      const vendorCounts: Record<string, number> = {};
      let totalValue = 0;

      for (const item of items) {
        const s = item.status ?? "unknown";
        statusCounts[s] = (statusCounts[s] ?? 0) + 1;
        const vendor = item.source ?? "Unknown";
        vendorCounts[vendor] = (vendorCounts[vendor] ?? 0) + 1;
        totalValue += item.purchasePriceCents ?? 0;
      }

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            totalItems: items.length,
            totalValue: formatCents(totalValue),
            byStatus: statusCounts,
            byVendor: vendorCounts,
          }, null, 2),
        }],
      };
    }
  );

  // ── spending_by_vendor ─────────────────────────────────────────────────────
  server.tool(
    "spending_by_vendor",
    "Aggregate spending grouped by vendor/source, sorted by total.",
    { projectId: z.string().optional().describe("Scope to a project") },
    async ({ projectId }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "transactions");
      if (projectId) query = query.where("projectId", "==", projectId);

      const transactions = await queryDocs<Transaction>(query);
      const vendorTotals = new Map<string, { totalCents: number; count: number }>();

      for (const tx of transactions) {
        if (tx.isCanceled) continue;
        const vendor = tx.source ?? "Unknown";
        const existing = vendorTotals.get(vendor) ?? { totalCents: 0, count: 0 };
        existing.totalCents += tx.amountCents ?? 0;
        existing.count++;
        vendorTotals.set(vendor, existing);
      }

      const rows = Array.from(vendorTotals.entries())
        .map(([vendor, data]) => ({
          vendor,
          total: formatCents(data.totalCents),
          totalCents: data.totalCents,
          transactionCount: data.count,
        }))
        .sort((a, b) => b.totalCents - a.totalCents);

      return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── budget_variance_report ─────────────────────────────────────────────────
  server.tool(
    "budget_variance_report",
    "Per-category over/under budget status for a project.",
    { projectId: z.string().describe("Project document ID") },
    async ({ projectId }) => {
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

      const rows = allocations.map((alloc) => {
        const cat = catMap.get(alloc.id);
        const budgetCents = alloc.budgetCents ?? 0;
        const spentCents = spentByCategory.get(alloc.id) ?? 0;
        const variance = budgetCents - spentCents;
        let status = "on-track";
        if (budgetCents > 0 && spentCents > budgetCents) status = "over-budget";
        else if (budgetCents > 0 && spentCents < budgetCents * 0.5) status = "under-budget";

        return {
          id: alloc.id,
          name: cat?.name ?? "",
          budget: formatCents(budgetCents),
          spent: formatCents(spentCents),
          variance: formatCents(variance),
          percentUsed: budgetCents > 0 ? `${Math.round((spentCents / budgetCents) * 100)}%` : "N/A",
          status,
        };
      });

      return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── items_needing_attention ────────────────────────────────────────────────
  server.tool(
    "items_needing_attention",
    "Find items with data quality issues: missing prices, SKUs, names, or with incomplete status.",
    { projectId: z.string().optional().describe("Scope to a project, or 'inventory' for business inventory") },
    async ({ projectId }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "items");
      if (projectId === "inventory") {
        query = query.where("projectId", "==", null);
      } else if (projectId) {
        query = query.where("projectId", "==", projectId);
      }

      const items = await queryDocs<Item>(query);
      const issues: { id: string; name: string; problems: string[] }[] = [];

      for (const item of items) {
        const problems: string[] = [];
        if (!item.name && !item.description) problems.push("missing name");
        if (!item.purchasePriceCents && !item.projectPriceCents) problems.push("missing price");
        if (!item.sku) problems.push("missing SKU");
        if (item.status === "to return") problems.push("pending return");
        if (item.status === "to purchase") problems.push("not yet purchased");

        if (problems.length > 0) {
          issues.push({
            id: item.id,
            name: item.name ?? item.description ?? "(unnamed)",
            problems,
          });
        }
      }

      return { content: [{ type: "text", text: JSON.stringify(issues, null, 2) }] };
    }
  );
}
