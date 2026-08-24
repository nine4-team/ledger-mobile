import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { BudgetCategory, Item, LineageEdge, Project, Transaction } from "../types.js";
import { getUid } from "../context.js";
import { effectiveProjectPriceCents } from "../util/item-pricing.js";
import { accountCollection, accountPath, getDoc, queryDocs } from "../util/query.js";
import { asToolResponse } from "../util/projections.js";
import { notFound, validation } from "../util/errors.js";
import { withTelemetry } from "../util/telemetry.js";

async function enabledCategory(
  db: Firestore,
  projectId: string,
  budgetCategoryId: string
) {
  const enabled = await db.doc(
    `${accountPath()}/projects/${projectId}/budgetCategories/${budgetCategoryId}`
  ).get();
  return enabled.exists;
}

async function categoryName(db: Firestore, budgetCategoryId?: string) {
  if (!budgetCategoryId) return null;
  const snap = await db.doc(
    `${accountPath()}/presets/default/budgetCategories/${budgetCategoryId}`
  ).get();
  return snap.exists ? ((snap.data() as BudgetCategory).name ?? budgetCategoryId) : null;
}

async function describeIntent(db: Firestore, tx: Transaction & { id: string }) {
  const project = tx.intendedProjectId
    ? await getDoc<Project>(db, "projects", tx.intendedProjectId)
    : null;
  const categoryIsEnabled = tx.intendedProjectId && tx.intendedBudgetCategoryId
    ? await enabledCategory(db, tx.intendedProjectId, tx.intendedBudgetCategoryId)
    : false;
  const items = await Promise.all((tx.itemIds ?? []).map((id) => getDoc<Item>(db, "items", id)));
  const activeItems = items.filter((item): item is Item & { id: string } => item != null);
  const soldEdges = await queryDocs<LineageEdge>(
    accountCollection(db, "lineageEdges").where("fromTransactionId", "==", tx.id)
  );
  const destinationTransactionIds = [...new Set(soldEdges
    .map((edge) => edge.toTransactionId)
    .filter((id: string | undefined): id is string => Boolean(id)))];
  const destinationTransactions = (await Promise.all(
    destinationTransactionIds.map((id) => getDoc<Transaction>(db, "transactions", id))
  )).filter((item): item is Transaction & { id: string } => item != null);
  const destinationProjectIds = [...new Set(destinationTransactions.map((item) => item.projectId).filter(Boolean))];
  const destinationCategoryIds = [...new Set(destinationTransactions.map((item) => item.budgetCategoryId).filter(Boolean))];
  const groupingViolation = destinationProjectIds.length > 1
    || destinationCategoryIds.length > 1
    || (tx.intendedProjectId != null && destinationProjectIds.some((id) => id !== tx.intendedProjectId))
    || (tx.intendedBudgetCategoryId != null && destinationCategoryIds.some((id) => id !== tx.intendedBudgetCategoryId));

  let actionState: string;
  if (tx.inventoryIntentResolvedAt) actionState = "resolved";
  else if (!project) actionState = "project_unavailable";
  else if (!tx.intendedBudgetCategoryId || !categoryIsEnabled) actionState = "missing_or_invalid_category";
  else if (activeItems.some((item) => effectiveProjectPriceCents(item) <= 0)) actionState = "missing_project_prices";
  else if (activeItems.length > 0 && soldEdges.length > 0) actionState = "partially_completed";
  else if (activeItems.length > 0) actionState = "ready_to_sell";
  else if (soldEdges.length > 0) actionState = "partially_completed";
  else actionState = "waiting_for_items";

  return {
    transactionId: tx.id,
    purchaseHandling: tx.purchaseHandling,
    intendedProjectId: tx.intendedProjectId ?? null,
    intendedProjectName: project?.name ?? null,
    intendedBudgetCategoryId: tx.intendedBudgetCategoryId ?? null,
    intendedBudgetCategoryName: await categoryName(db, tx.intendedBudgetCategoryId),
    actionState,
    activeItemCount: activeItems.length,
    soldLineageCount: soldEdges.length,
    destinationProjectIds,
    destinationCategoryIds,
    groupingViolation,
    inventoryIntentResolvedAt: tx.inventoryIntentResolvedAt ?? null,
  };
}

export function registerPurchaseIntentTools(server: McpServer, db: Firestore) {
  server.tool(
    "list_inventory_purchase_intents",
    "[read-only] List inventory resale acquisitions planned for projects, enriched with current project/category names and a derived follow-up state. General inventory without intendedProjectId is excluded by default.",
    {
      includeResolved: z.boolean().default(false),
      includeGeneralInventory: z.boolean().default(false),
      limit: z.coerce.number().int().positive().max(500).default(100),
    },
    withTelemetry("list_inventory_purchase_intents", async ({ includeResolved, includeGeneralInventory, limit }) => {
      const transactions = await queryDocs<Transaction>(
        accountCollection(db, "transactions")
          .where("purchaseHandling", "==", "inventory_resale")
          .limit(limit)
      );
      const filtered = transactions.filter((tx) =>
        tx.projectId == null
        && (includeGeneralInventory || Boolean(tx.intendedProjectId))
        && (includeResolved || !tx.inventoryIntentResolvedAt)
      );
      return asToolResponse(await Promise.all(filtered.map((tx) => describeIntent(db, tx))));
    })
  );

  server.tool(
    "update_inventory_purchase_intent",
    "[correction] Set, change, clear, or explicitly resolve the intended project/category on one inventory resale acquisition. This changes planning metadata only; it does not create a sale.",
    {
      transactionId: z.string(),
      intendedProjectId: z.string().nullable().optional(),
      intendedBudgetCategoryId: z.string().nullable().optional(),
      markResolved: z.boolean().optional(),
      dryRun: z.boolean().default(true),
    },
    withTelemetry("update_inventory_purchase_intent", async ({ transactionId, intendedProjectId, intendedBudgetCategoryId, markResolved, dryRun }) => {
      const tx = await getDoc<Transaction>(db, "transactions", transactionId);
      if (!tx) return notFound("Transaction", transactionId, "list_transactions");
      if (tx.projectId || tx.purchaseHandling !== "inventory_resale") {
        return validation(
          "Purchase intent metadata can only be changed on inventory_resale transactions in business inventory.",
          "Use the project reimbursement correction tool if this purchase should not be inventory."
        );
      }

      const nextProjectId = intendedProjectId === undefined ? tx.intendedProjectId : intendedProjectId ?? undefined;
      const nextCategoryId = intendedBudgetCategoryId === undefined
        ? tx.intendedBudgetCategoryId
        : intendedBudgetCategoryId ?? undefined;
      if (!nextProjectId && nextCategoryId) {
        return validation("An intended category cannot exist without an intended project.", "Clear both fields or choose a project.");
      }
      if (nextProjectId) {
        const project = await getDoc<Project>(db, "projects", nextProjectId);
        if (!project) return notFound("Project", nextProjectId, "list_projects");
        if (nextCategoryId && !(await enabledCategory(db, nextProjectId, nextCategoryId))) {
          return validation(
            `Budget category ${nextCategoryId} is not enabled in project ${nextProjectId}.`,
            "Pick a category from get_project_budget_categories."
          );
        }
      }

      const plan = {
        transactionId,
        intendedProjectId: nextProjectId ?? null,
        intendedBudgetCategoryId: nextCategoryId ?? null,
        inventoryIntentResolvedAt: markResolved === true ? "server_timestamp" : markResolved === false ? null : "unchanged",
      };
      if (dryRun) return asToolResponse({ dryRun: true, plan });

      const updates: Record<string, unknown> = {
        intendedProjectId: nextProjectId ?? null,
        intendedBudgetCategoryId: nextCategoryId ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (markResolved === true) updates.inventoryIntentResolvedAt = FieldValue.serverTimestamp();
      if (markResolved === false) updates.inventoryIntentResolvedAt = FieldValue.delete();
      await accountCollection(db, "transactions").doc(transactionId).update(updates);
      return asToolResponse({ dryRun: false, updated: plan });
    })
  );

  server.tool(
    "correct_inventory_purchase_to_project_reimbursement",
    "[correction] Correct a vendor Purchase mistakenly routed to inventory into a direct project reimbursement. This does not invent an inventory sale. The transaction and its active items move atomically; project price defaults to purchase price. Defaults to dry-run.",
    {
      transactionId: z.string(),
      projectId: z.string(),
      budgetCategoryId: z.string(),
      dryRun: z.boolean().default(true),
    },
    withTelemetry("correct_inventory_purchase_to_project_reimbursement", async ({ transactionId, projectId, budgetCategoryId, dryRun }) => {
      const tx = await getDoc<Transaction>(db, "transactions", transactionId);
      if (!tx) return notFound("Transaction", transactionId, "list_transactions");
      if (tx.projectId || tx.type?.toLowerCase() !== "purchase") {
        return validation("Only an inventory-scoped vendor Purchase can use this correction.", "Select the original inventory acquisition transaction.");
      }
      const project = await getDoc<Project>(db, "projects", projectId);
      if (!project) return notFound("Project", projectId, "list_projects");
      if (!(await enabledCategory(db, projectId, budgetCategoryId))) {
        return validation(
          `Budget category ${budgetCategoryId} is not enabled in project ${projectId}.`,
          "Pick a category from get_project_budget_categories."
        );
      }
      const soldEdges = await queryDocs(
        accountCollection(db, "lineageEdges").where("fromTransactionId", "==", transactionId)
      );
      if (soldEdges.length > 0) {
        return validation(
          "This acquisition already has inventory movement lineage and cannot be rewritten as a simple correction.",
          "Review the existing sales/returns and correct them explicitly before moving the acquisition."
        );
      }
      const items = await Promise.all((tx.itemIds ?? []).map((id) => getDoc<Item>(db, "items", id)));
      const activeItems = items.filter((item): item is Item & { id: string } => item != null);
      const plan = {
        transactionId,
        projectId,
        budgetCategoryId,
        itemIds: activeItems.map((item) => item.id),
        purchaseHandling: "project_reimbursement",
        reimbursementType: "owed-to-company",
      };
      if (dryRun) return asToolResponse({ dryRun: true, plan });

      const batch = db.batch();
      const now = FieldValue.serverTimestamp();
      batch.update(accountCollection(db, "transactions").doc(transactionId), {
        projectId,
        budgetCategoryId,
        purchaseHandling: "project_reimbursement",
        reimbursementType: "owed-to-company",
        intendedProjectId: FieldValue.delete(),
        intendedBudgetCategoryId: FieldValue.delete(),
        inventoryIntentResolvedAt: FieldValue.delete(),
        updatedAt: now,
        updatedBy: getUid(),
      });
      for (const item of activeItems) {
        const updates: Record<string, unknown> = {
          projectId,
          budgetCategoryId,
          updatedAt: now,
          updatedBy: getUid(),
        };
        const normalizedProjectPrice = effectiveProjectPriceCents(item);
        if (normalizedProjectPrice > 0) {
          updates.projectPriceCents = normalizedProjectPrice;
        }
        batch.update(accountCollection(db, "items").doc(item.id), updates);
      }
      await batch.commit();
      return asToolResponse({ dryRun: false, corrected: plan });
    })
  );
}
