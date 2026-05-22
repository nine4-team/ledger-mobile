import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { Transaction, Item } from "../types.js";
import { accountCollection, queryDocs, getDoc, getDocs } from "../util/query.js";
import { formatCents } from "../util/format.js";
import {
  asToolResponse,
  transactionSummary,
  itemSummary,
  capResponse,
} from "../util/projections.js";
import { notFound, validation } from "../util/errors.js";
import { tagNotesAsAi } from "../util/notes.js";
import { withTelemetry } from "../util/telemetry.js";
import { isInventorySource, resolveInventoryLabel } from "../util/inventory.js";

/**
 * Task-shaped tools that sit on top of the primitives. Each one
 * collapses a common 5–15-call chain into a single intent verb.
 */

export function registerCompositeTools(server: McpServer, db: Firestore) {
  // ── reconcile_transaction ──────────────────────────────────────────────────
  server.tool(
    "reconcile_transaction",
    "[read-only] Fetch a transaction, resolve its linked items, and return a reconciliation report: audit variance, missing tax rates, items without prices, and concrete suggested fixes. Use this instead of chaining get_transaction + list item details manually.",
    { transactionId: z.string().describe("Transaction document ID") },
    withTelemetry("reconcile_transaction", async ({ transactionId }) => {
      const tx = await getDoc<Transaction>(db, "transactions", transactionId);
      if (!tx) return notFound("Transaction", transactionId);

      const itemIds = tx.itemIds ?? [];
      const { found: items } = itemIds.length
        ? await getDocs<Item>(db, "items", itemIds)
        : { found: [] as (Item & { id: string })[] };

      const itemsSumCents = items.reduce((sum, i) => sum + (i.purchasePriceCents ?? 0), 0);
      const subtotalCents = tx.subtotalCents ?? null;
      const varianceCents =
        subtotalCents !== null ? itemsSumCents - subtotalCents : null;
      const variancePercent =
        subtotalCents !== null && subtotalCents > 0
          ? Math.round((Math.abs(varianceCents!) / subtotalCents) * 10000) / 100
          : null;

      const itemsMissingPrice = items.filter((i) => i.purchasePriceCents == null);
      const itemsMissingTax = items.filter((i) => i.taxRatePct == null);
      const itemsMissingName = items.filter((i) => !i.name && !i.description);

      const suggestions: Array<{ action: string; detail: string; tool?: string }> = [];

      if (!tx.budgetCategoryId) {
        suggestions.push({
          action: "Set budgetCategoryId",
          detail: "Transaction has no budget category — choose one from get_project_budget_categories.",
          tool: "update_transaction",
        });
      }
      if (tx.taxRatePct == null && tx.subtotalCents == null) {
        suggestions.push({
          action: "Add tax info",
          detail: "Set either taxRatePct OR subtotalCents so completeness can resolve.",
          tool: "update_transaction",
        });
      }
      if (itemsMissingPrice.length > 0) {
        suggestions.push({
          action: `Set purchasePriceCents on ${itemsMissingPrice.length} item(s)`,
          detail: `Missing price on: ${itemsMissingPrice.map((i) => i.id).join(", ")}`,
          tool: "bulk_update_items_by_id",
        });
      }
      if (itemsMissingTax.length > 0) {
        suggestions.push({
          action: `Set taxRatePct on ${itemsMissingTax.length} item(s)`,
          detail: `Missing tax rate on: ${itemsMissingTax.map((i) => i.id).join(", ")}`,
          tool: "bulk_update_items_by_id",
        });
      }
      if (
        varianceCents !== null &&
        subtotalCents !== null &&
        variancePercent !== null &&
        variancePercent > 1
      ) {
        suggestions.push({
          action: "Resolve item-subtotal variance",
          detail: `Items sum to ${formatCents(itemsSumCents)} but subtotal is ${formatCents(subtotalCents)} (variance ${variancePercent}%). Either add/remove items or adjust subtotalCents.`,
        });
      }
      if (itemIds.length === 0 && tx.type === "Purchase") {
        suggestions.push({
          action: "Link items",
          detail: "Purchase has no items linked. Add items or call create_transaction_with_items.",
        });
      }
      if (itemsMissingName.length > 0) {
        suggestions.push({
          action: `Name ${itemsMissingName.length} unnamed item(s)`,
          detail: itemsMissingName.map((i) => i.id).join(", "),
          tool: "bulk_update_items_by_id",
        });
      }

      return asToolResponse({
        transaction: transactionSummary(tx),
        audit: {
          itemCount: items.length,
          itemsSumCents,
          itemsSum: formatCents(itemsSumCents),
          subtotalCents,
          subtotal: subtotalCents !== null ? formatCents(subtotalCents) : null,
          varianceCents,
          variance: varianceCents !== null ? formatCents(varianceCents) : null,
          variancePercent,
          isComplete: tx.isComplete ?? null,
        },
        items: items.map(itemSummary),
        issues: {
          missingPrice: itemsMissingPrice.map((i) => i.id),
          missingTax: itemsMissingTax.map((i) => i.id),
          missingName: itemsMissingName.map((i) => i.id),
        },
        suggestions,
        healthy: suggestions.length === 0,
      });
    })
  );

  // ── create_transaction_with_items ──────────────────────────────────────────
  server.tool(
    "create_transaction_with_items",
    "[mutating] Atomically create a transaction and its items in a single batched write. Replaces the create_transaction + bulk_create_items chain and rolls back if any step fails. Requires a dated audit note.",
    {
      transaction: z
        .object({
          projectId: z.string().optional().describe("Project ID (omit for business inventory). If this is a Purchase with source equal to the account inventory label, the tool creates the purchase/items in inventory first, then creates a Purchase-from-inventory movement into this project."),
          budgetCategoryId: z.string().describe("Budget category ID"),
          amountCents: z.coerce.number().describe("Total amount in cents"),
          type: z.string().default("Purchase").describe("Purchase or Return (never Sale — use sell_items). 'To Inventory' is legacy; to return items to business inventory, use return_items with returnTo: 'inventory'."),
          source: z.string().optional().describe("Vendor/source name. The account inventory label is a built-in source, not a vendor preset; using it on a project Purchase routes through inventory and sells into the project."),
          transactionDate: z.string().optional(),
          subtotalCents: z.coerce.number().optional(),
          taxRatePct: z.coerce.number().optional(),
          purchasedBy: z.string().optional(),
          paymentMethod: z.string().optional(),
        })
        .describe("Transaction fields"),
      items: z
        .array(
          z.object({
            name: z.string(),
            purchasePriceCents: z.coerce.number().optional(),
            projectPriceCents: z.coerce.number().optional(),
            status: z.string().default("purchased"),
            source: z.string().optional(),
            sku: z.string().optional(),
            spaceId: z.string().optional(),
            budgetCategoryId: z.string().optional(),
            taxRatePct: z.coerce.number().optional(),
          })
        )
        .min(1)
        .describe("Items to create and link to the new transaction"),
      notes: z
        .string()
        .optional()
        .describe("Optional prose describing the transaction (e.g. 'Home Depot receipt — 5 fixtures for Witzenman'). Free-form. createdAt/createdBy records the audit trail."),
    },
    withTelemetry("create_transaction_with_items", async ({ transaction, items, notes }) => {
      if (transaction.type === "Sale") {
        return validation(
          "Cannot create Sale-to-Inventory transactions here — use sell_items instead.",
          "Sale-to-Inventory transactions require lineage edges and item scope changes that only sell_items can produce."
        );
      }

      const txCol = accountCollection(db, "transactions");
      const itemsCol = accountCollection(db, "items");
      const edgesCol = accountCollection(db, "lineageEdges");
      const txRef = txCol.doc();
      const itemRefs = items.map(() => itemsCol.doc());
      const itemIds = itemRefs.map((r: FirebaseFirestore.DocumentReference) => r.id);
      const inventoryLabel = await resolveInventoryLabel(db);
      const routeInventorySource =
        transaction.type === "Purchase" &&
        !!transaction.projectId &&
        isInventorySource(transaction.source, inventoryLabel);
      const saleRef = routeInventorySource ? txCol.doc() : null;

      // Resolve per-item tax rate from the transaction if not set.
      const resolvedTaxRate = transaction.taxRatePct;

      const batch = db.batch();

      const taggedNotes = notes ? tagNotesAsAi(notes) : undefined;
      const txData: Record<string, unknown> = {
        amountCents: transaction.amountCents,
        type: transaction.type,
        status: "completed",
        isComplete: false,
        itemIds: routeInventorySource ? [] : itemIds,
        ...(taggedNotes ? { notes: taggedNotes } : {}),
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      if (!routeInventorySource) txData.budgetCategoryId = transaction.budgetCategoryId;
      if (transaction.projectId && !routeInventorySource) txData.projectId = transaction.projectId;
      if (transaction.source) txData.source = transaction.source;
      if (transaction.transactionDate) txData.transactionDate = transaction.transactionDate;
      if (transaction.subtotalCents !== undefined) txData.subtotalCents = transaction.subtotalCents;
      if (transaction.taxRatePct !== undefined) txData.taxRatePct = transaction.taxRatePct;
      if (transaction.purchasedBy) txData.purchasedBy = transaction.purchasedBy;
      if (transaction.paymentMethod) txData.paymentMethod = transaction.paymentMethod;

      batch.set(txRef, txData);

      if (routeInventorySource && saleRef) {
        batch.set(saleRef, {
          type: "Purchase",
          source: inventoryLabel,
          projectId: transaction.projectId,
          budgetCategoryId: transaction.budgetCategoryId,
          amountCents: transaction.amountCents,
          subtotalCents: transaction.subtotalCents ?? transaction.amountCents,
          itemIds,
          status: "completed",
          isComplete: true,
          ...(taggedNotes ? { notes: taggedNotes } : {}),
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        const itemData: Record<string, unknown> = {
          name: item.name,
          status: item.status,
          transactionId: saleRef?.id ?? txRef.id,
          ...(taggedNotes ? { notes: taggedNotes } : {}),
          createdAt: new Date(),
          updatedAt: new Date(),
        };
        if (transaction.projectId && !routeInventorySource) itemData.projectId = transaction.projectId;
        if (transaction.projectId && routeInventorySource) itemData.projectId = transaction.projectId;
        if (item.purchasePriceCents !== undefined) itemData.purchasePriceCents = item.purchasePriceCents;
        if (item.projectPriceCents !== undefined) itemData.projectPriceCents = item.projectPriceCents;
        const itemSource = item.source;
        if (itemSource) {
          itemData.source = itemSource;
        }
        if (routeInventorySource) itemData.currentSource = inventoryLabel;
        else if (itemSource) itemData.currentSource = itemSource;
        if (item.sku) itemData.sku = item.sku;
        if (item.spaceId) itemData.spaceId = item.spaceId;
        if (routeInventorySource) itemData.budgetCategoryId = transaction.budgetCategoryId;
        else if (item.budgetCategoryId) itemData.budgetCategoryId = item.budgetCategoryId;
        else itemData.budgetCategoryId = transaction.budgetCategoryId;
        if (item.taxRatePct !== undefined) itemData.taxRatePct = item.taxRatePct;
        else if (resolvedTaxRate !== undefined) itemData.taxRatePct = resolvedTaxRate;

        batch.set(itemRefs[i], itemData);

        if (routeInventorySource && saleRef) {
          batch.set(edgesCol.doc(), {
            itemId: itemRefs[i].id,
            fromTransactionId: txRef.id,
            toTransactionId: saleRef.id,
            fromProjectId: null,
            toProjectId: transaction.projectId,
          movementKind: "sold",
            source: "mcp",
            createdAt: FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();

      return asToolResponse({
        ok: true,
        transactionId: txRef.id,
        saleTransactionId: saleRef?.id,
        routedThroughInventory: routeInventorySource,
        itemIds,
        itemCount: items.length,
      });
    })
  );

  // ── triage_inbox ───────────────────────────────────────────────────────────
  server.tool(
    "triage_inbox",
    "[read-only] Return incomplete transactions most in need of attention, with suggested next actions. Summary mode. Use this as an entry point for cleanup workflows.",
    {
      limit: z.coerce.number().default(20).describe("Max transactions to return"),
      projectId: z
        .string()
        .optional()
        .describe("Optional project scope. Use 'inventory' for business-inventory transactions."),
    },
    withTelemetry("triage_inbox", async ({ limit, projectId }) => {
      let q: FirebaseFirestore.Query = accountCollection(db, "transactions").where(
        "isComplete",
        "==",
        false
      );
      if (projectId === "inventory") q = q.where("projectId", "==", null);
      else if (projectId) q = q.where("projectId", "==", projectId);

      const all = await queryDocs<Transaction>(q);
      // Rank: needs_review ingestion first, then missing category, then largest amounts.
      all.sort((a, b) => {
        const aNeeds = a.ingestionStatus === "needs_review" ? 1 : 0;
        const bNeeds = b.ingestionStatus === "needs_review" ? 1 : 0;
        if (aNeeds !== bNeeds) return bNeeds - aNeeds;
        const aMissing = a.budgetCategoryId ? 0 : 1;
        const bMissing = b.budgetCategoryId ? 0 : 1;
        if (aMissing !== bMissing) return bMissing - aMissing;
        return (b.amountCents ?? 0) - (a.amountCents ?? 0);
      });

      const top = all.slice(0, limit).map((tx) => {
        const reasons: string[] = [];
        if (tx.ingestionStatus === "needs_review") reasons.push("email ingestion needs review");
        if (!tx.budgetCategoryId) reasons.push("no budget category");
        if (!tx.projectId) reasons.push("no project assigned");
        if (!(tx.itemIds?.length ?? 0)) reasons.push("no items linked");
        if (tx.subtotalCents == null && tx.taxRatePct == null) reasons.push("no tax info");
        return {
          ...transactionSummary(tx),
          reasons,
          suggestedTool: "reconcile_transaction",
        };
      });

      const capped = capResponse(top, { totalCount: all.length });
      return asToolResponse({
        ...capped,
        hint:
          capped.totalCount > capped.returnedCount
            ? `${capped.totalCount - capped.returnedCount} more incomplete transactions — raise limit or narrow by projectId.`
            : undefined,
      });
    })
  );
}
