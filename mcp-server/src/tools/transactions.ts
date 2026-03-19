import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { Transaction, Item } from "../types.js";
import { accountCollection, queryDocs, getDoc } from "../util/query.js";
import { formatCents, formatDate } from "../util/format.js";

function txTypeName(tx: Transaction): string {
  return tx.type ?? tx.transactionType ?? "";
}

function formatTransaction(tx: Transaction & { id: string }) {
  return {
    id: tx.id,
    type: txTypeName(tx),
    source: tx.source ?? "",
    amount: formatCents(tx.amountCents),
    date: tx.transactionDate ?? "",
    projectId: tx.projectId ?? null,
    budgetCategoryId: tx.budgetCategoryId ?? null,
    itemCount: tx.itemIds?.length ?? 0,
    notes: tx.notes ?? "",
    isCanceled: tx.isCanceled ?? false,
    needsReview: tx.needsReview ?? false,
    status: tx.status ?? "",
  };
}

export function registerTransactionTools(server: McpServer, db: Firestore) {
  // ── list_transactions ──────────────────────────────────────────────────────
  server.tool(
    "list_transactions",
    "List transactions with optional filters. Returns formatted amounts.",
    {
      projectId: z.string().optional().describe("Filter by project ID. Use 'inventory' for business inventory (projectId is null)."),
      budgetCategoryId: z.string().optional().describe("Filter by budget category ID"),
      type: z.string().optional().describe("Filter by transaction type (Purchase, Return, Sale, To Inventory)"),
      limit: z.number().default(50).describe("Max results"),
    },
    async ({ projectId, budgetCategoryId, type, limit }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "transactions");

      if (projectId === "inventory") {
        query = query.where("projectId", "==", null);
      } else if (projectId) {
        query = query.where("projectId", "==", projectId);
      }

      if (budgetCategoryId) {
        query = query.where("budgetCategoryId", "==", budgetCategoryId);
      }

      if (type) {
        query = query.where("type", "==", type);
      }

      query = query.limit(limit);
      const transactions = await queryDocs<Transaction>(query);
      const rows = transactions.map(formatTransaction);

      return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── get_transaction ────────────────────────────────────────────────────────
  server.tool(
    "get_transaction",
    "Get a single transaction with its linked items resolved via itemIds.",
    { transactionId: z.string().describe("Transaction document ID") },
    async ({ transactionId }) => {
      const tx = await getDoc<Transaction>(db, "transactions", transactionId);
      if (!tx) {
        return { content: [{ type: "text", text: `Transaction ${transactionId} not found.` }], isError: true };
      }

      // Resolve linked items
      let items: (Item & { id: string })[] = [];
      if (tx.itemIds?.length) {
        const itemPromises = tx.itemIds.map((itemId) =>
          getDoc<Item>(db, "items", itemId)
        );
        const results = await Promise.all(itemPromises);
        items = results.filter((i): i is Item & { id: string } => i !== null);
      }

      const result = {
        ...formatTransaction(tx),
        subtotalCents: tx.subtotalCents,
        taxRatePct: tx.taxRatePct,
        purchasedBy: tx.purchasedBy ?? "",
        reimbursementType: tx.reimbursementType ?? "",
        paymentMethod: tx.paymentMethod ?? "",
        receiptImageCount: tx.receiptImages?.length ?? 0,
        items: items.map((i) => ({
          id: i.id,
          name: i.name ?? i.description ?? "",
          status: i.status ?? "",
          purchasePrice: formatCents(i.purchasePriceCents),
        })),
      };

      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    }
  );

  // ── search_transactions ────────────────────────────────────────────────────
  server.tool(
    "search_transactions",
    "Search transactions by source (vendor) name or notes. Case-insensitive client-side filter.",
    {
      query: z.string().describe("Search term"),
      projectId: z.string().optional().describe("Scope search to a project"),
      limit: z.number().default(25).describe("Max results"),
    },
    async ({ query: searchTerm, projectId, limit }) => {
      let q: FirebaseFirestore.Query = accountCollection(db, "transactions");
      if (projectId) q = q.where("projectId", "==", projectId);

      const all = await queryDocs<Transaction>(q);
      const term = searchTerm.toLowerCase();
      const matched = all
        .filter((tx) => {
          const source = (tx.source ?? "").toLowerCase();
          const notes = (tx.notes ?? "").toLowerCase();
          return source.includes(term) || notes.includes(term);
        })
        .slice(0, limit);

      return { content: [{ type: "text", text: JSON.stringify(matched.map(formatTransaction), null, 2) }] };
    }
  );

  // ── create_transaction ─────────────────────────────────────────────────────
  server.tool(
    "create_transaction",
    "Create a new transaction.",
    {
      projectId: z.string().optional().describe("Project ID (omit for business inventory)"),
      budgetCategoryId: z.string().describe("Budget category ID"),
      amountCents: z.number().describe("Amount in cents (positive)"),
      type: z.string().default("Purchase").describe("Transaction type: Purchase, Return, Sale, To Inventory"),
      source: z.string().optional().describe("Vendor/source name"),
      transactionDate: z.string().optional().describe("Date string (e.g. '2024-03-15')"),
      notes: z.string().optional().describe("Notes"),
      itemIds: z.array(z.string()).optional().describe("Item IDs to link to this transaction"),
    },
    async ({ projectId, budgetCategoryId, amountCents, type: txType, source, transactionDate, notes, itemIds }) => {
      const data: Record<string, unknown> = {
        budgetCategoryId,
        amountCents,
        type: txType,
        isCanceled: false,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      if (projectId) data.projectId = projectId;
      if (source) data.source = source;
      if (transactionDate) data.transactionDate = transactionDate;
      if (notes) data.notes = notes;
      if (itemIds?.length) data.itemIds = itemIds;

      const ref = await accountCollection(db, "transactions").add(data);

      // Maintain bidirectional link: set transactionId on each linked item
      if (itemIds?.length) {
        const batch = db.batch();
        for (const itemId of itemIds) {
          batch.update(accountCollection(db, "items").doc(itemId), {
            transactionId: ref.id,
            updatedAt: new Date(),
          });
        }
        await batch.commit();
      }

      return { content: [{ type: "text", text: `Created transaction ${ref.id}` }] };
    }
  );

  // ── update_transaction ─────────────────────────────────────────────────────
  server.tool(
    "update_transaction",
    "Update transaction fields.",
    {
      transactionId: z.string().describe("Transaction document ID"),
      amountCents: z.number().optional().describe("New amount in cents"),
      source: z.string().optional().describe("New vendor/source"),
      notes: z.string().optional().describe("New notes"),
      budgetCategoryId: z.string().optional().describe("New budget category"),
      transactionDate: z.string().optional().describe("New date string"),
    },
    async ({ transactionId, amountCents, source, notes, budgetCategoryId, transactionDate }) => {
      const updates: Record<string, unknown> = { updatedAt: new Date() };
      if (amountCents !== undefined) updates.amountCents = amountCents;
      if (source !== undefined) updates.source = source;
      if (notes !== undefined) updates.notes = notes;
      if (budgetCategoryId !== undefined) updates.budgetCategoryId = budgetCategoryId;
      if (transactionDate !== undefined) updates.transactionDate = transactionDate;

      await accountCollection(db, "transactions").doc(transactionId).update(updates);
      return { content: [{ type: "text", text: `Updated transaction ${transactionId}` }] };
    }
  );

  // ── cancel_transaction ─────────────────────────────────────────────────────
  server.tool(
    "cancel_transaction",
    "Mark a transaction as canceled. Canceled transactions contribute $0 to budget calculations.",
    { transactionId: z.string().describe("Transaction document ID") },
    async ({ transactionId }) => {
      await accountCollection(db, "transactions").doc(transactionId).update({
        isCanceled: true,
        updatedAt: new Date(),
      });
      return { content: [{ type: "text", text: `Canceled transaction ${transactionId}` }] };
    }
  );
}
