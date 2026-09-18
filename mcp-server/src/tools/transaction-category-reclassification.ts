import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { randomUUID } from "node:crypto";
import type {
  DocumentReference,
  Firestore,
  Transaction as FirestoreTransaction,
} from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { BudgetCategory, Item, Transaction } from "../types.js";
import { getAccountId, getUid } from "../context.js";
import { resolveCategoryType } from "../util/budget.js";
import { toolError } from "../util/errors.js";
import { accountCollection, accountPath } from "../util/query.js";
import { asToolResponse } from "../util/projections.js";
import { withTelemetry } from "../util/telemetry.js";

const MAX_ATOMIC_WRITES = 500;

type CorrectionInput = {
  transactionId: string;
  targetBudgetCategoryId: string;
  expectedCurrentBudgetCategoryId: string;
  requestId: string;
};

type CorrectionPlan = {
  eligible: boolean;
  noOp: boolean;
  blockers: Array<{ code: string; message: string }>;
  transactionId: string;
  currentBudgetCategoryId: string | null;
  targetBudgetCategoryId: string;
  projectId: string | null;
  amountCents: number | null;
  itemIds: string[];
  writeCount: number;
};

function normalizedType(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function categoryId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.toLowerCase() !== "uncategorized" ? trimmed : null;
}

function isEligiblePurchase(transaction: Transaction): boolean {
  return transaction.isCanonicalInventorySale !== true
    && normalizedType(transaction.type) === "purchase"
    && normalizedType(transaction.status) !== "canceled"
    && normalizedType(transaction.status) !== "cancelled"
    && typeof transaction.projectId === "string"
    && transaction.projectId.trim().length > 0
    && typeof transaction.source === "string"
    && transaction.source.trim().toLowerCase().endsWith(" inventory");
}

function sameIds(left: string[], right: string[]): boolean {
  return left.length === right.length && new Set(left).size === left.length
    && left.every((id) => right.includes(id));
}

function publicError(plan: CorrectionPlan) {
  return toolError({
    code: plan.blockers.some((blocker) => blocker.code === "NOT_FOUND") ? "NOT_FOUND" : "CONFLICT",
    message: "The Purchase category correction was blocked.",
    hint: "Resolve the reported blocker and retry with the current category ID.",
    retryable: true,
    details: { plan },
  });
}

async function buildPlan(db: Firestore, input: CorrectionInput): Promise<CorrectionPlan> {
  const transactionRef = accountCollection(db, "transactions").doc(input.transactionId);
  const transactionSnapshot = await transactionRef.get();
  if (!transactionSnapshot.exists) {
    return {
      eligible: false,
      noOp: false,
      blockers: [{ code: "NOT_FOUND", message: `Transaction ${input.transactionId} was not found.` }],
      transactionId: input.transactionId,
      currentBudgetCategoryId: null,
      targetBudgetCategoryId: input.targetBudgetCategoryId,
      projectId: null,
      amountCents: null,
      itemIds: [],
      writeCount: 0,
    };
  }

  const transaction = { ...(transactionSnapshot.data() as Transaction), id: transactionSnapshot.id };
  const blockers: CorrectionPlan["blockers"] = [];
  const currentCategoryId = categoryId(transaction.budgetCategoryId);
  const targetCategoryId = categoryId(input.targetBudgetCategoryId);
  const itemIds = [...new Set(transaction.itemIds ?? [])];

  if (!isEligiblePurchase(transaction)) {
    blockers.push({ code: "NOT_ELIGIBLE", message: "Only an active project Purchase from Inventory can be reclassified." });
  }
  if (!currentCategoryId || currentCategoryId !== input.expectedCurrentBudgetCategoryId.trim()) {
    blockers.push({ code: "STALE_CATEGORY", message: "The Purchase category changed before this request was applied." });
  }
  if (!targetCategoryId) {
    blockers.push({ code: "INVALID_TARGET", message: "A real target budget category is required." });
  }
  if (targetCategoryId && targetCategoryId === currentCategoryId) {
    return {
      eligible: blockers.length === 0,
      noOp: true,
      blockers,
      transactionId: transaction.id,
      currentBudgetCategoryId: currentCategoryId,
      targetBudgetCategoryId: targetCategoryId,
      projectId: transaction.projectId ?? null,
      amountCents: transaction.amountCents ?? null,
      itemIds,
      writeCount: 0,
    };
  }

  if (targetCategoryId && transaction.projectId) {
    const accountCategoryRef = accountCollection(db, "presets/default/budgetCategories").doc(targetCategoryId);
    const projectCategoryRef = db.doc(`${accountPath()}/projects/${transaction.projectId}/budgetCategories/${targetCategoryId}`);
    const [accountCategorySnapshot, projectCategorySnapshot] = await Promise.all([
      accountCategoryRef.get(),
      projectCategoryRef.get(),
    ]);
    const accountCategory = accountCategorySnapshot.exists
      ? accountCategorySnapshot.data() as BudgetCategory & { isSystem?: boolean }
      : null;
    if (!accountCategory || accountCategory.isArchived || accountCategory.isSystem === true || resolveCategoryType(accountCategory) !== "itemized") {
      blockers.push({ code: "INVALID_TARGET", message: "The target must be an active, non-system, itemized account category." });
    }
    if (!projectCategorySnapshot.exists) {
      blockers.push({ code: "CATEGORY_NOT_ENABLED", message: "The target category is not enabled for this project." });
    }
  }

  const itemRefs = itemIds.map((id) => accountCollection(db, "items").doc(id));
  const itemSnapshots = itemRefs.length > 0 ? await db.getAll(...itemRefs) : [];
  const missingItemIds = itemSnapshots.filter((snapshot) => !snapshot.exists).map((snapshot) => snapshot.id);
  if (missingItemIds.length > 0) {
    blockers.push({ code: "STALE_MEMBERSHIP", message: `Attached items are missing: ${missingItemIds.join(", ")}.` });
  }
  const invalidItems = itemSnapshots.filter((snapshot) => {
    if (!snapshot.exists) return false;
    const item = snapshot.data() as Item;
    return item.transactionId !== transaction.id || item.projectId !== transaction.projectId;
  });
  if (invalidItems.length > 0) {
    blockers.push({ code: "STALE_MEMBERSHIP", message: "The Purchase item links do not match the current item records." });
  }

  const reverseSnapshot = await accountCollection(db, "items").where("transactionId", "==", transaction.id).get();
  const reverseItemIds = reverseSnapshot.docs.map((snapshot) => snapshot.id);
  if (!sameIds(itemIds, reverseItemIds)) {
    blockers.push({ code: "STALE_MEMBERSHIP", message: "The Purchase itemIds list differs from its reverse item links." });
  }

  const writeCount = blockers.length === 0 ? 2 + itemIds.length : 0;
  if (writeCount > MAX_ATOMIC_WRITES) {
    blockers.push({ code: "WRITE_LIMIT", message: `This correction requires ${writeCount} writes.` });
  }

  return {
    eligible: blockers.length === 0,
    noOp: false,
    blockers,
    transactionId: transaction.id,
    currentBudgetCategoryId: currentCategoryId,
    targetBudgetCategoryId: targetCategoryId ?? input.targetBudgetCategoryId,
    projectId: transaction.projectId ?? null,
    amountCents: transaction.amountCents ?? null,
    itemIds,
    writeCount,
  };
}

async function commitCorrection(db: Firestore, input: CorrectionInput, plan: CorrectionPlan) {
  const transactionRef = accountCollection(db, "transactions").doc(input.transactionId);
  const auditRef = accountCollection(db, "transactionCategoryEvents").doc(input.requestId);
  const actor = getUid();

  return db.runTransaction(async (firestoreTransaction: FirestoreTransaction) => {
    const existingAudit = await firestoreTransaction.get(auditRef);
    if (existingAudit.exists) {
      const data = existingAudit.data() ?? {};
      if (data.transactionId !== input.transactionId || data.budgetCategoryId !== input.targetBudgetCategoryId) {
        throw new Error("REQUEST_ID_REUSED");
      }
      return { ...plan, alreadyApplied: true, auditEventId: auditRef.id };
    }

    const transactionSnapshot = await firestoreTransaction.get(transactionRef);
    if (!transactionSnapshot.exists) throw new Error("TRANSACTION_NOT_FOUND");
    const transaction = { ...(transactionSnapshot.data() as Transaction), id: transactionSnapshot.id };
    if (!isEligiblePurchase(transaction) || categoryId(transaction.budgetCategoryId) !== input.expectedCurrentBudgetCategoryId.trim()) {
      throw new Error("STALE_CATEGORY");
    }

    const itemIds = [...new Set(transaction.itemIds ?? [])];
    const itemRefs = itemIds.map((id) => accountCollection(db, "items").doc(id));
    const itemSnapshots = itemRefs.length > 0 ? await firestoreTransaction.getAll(...itemRefs) : [];
    if (itemSnapshots.some((snapshot) => !snapshot.exists || (snapshot.data() as Item).transactionId !== transaction.id || (snapshot.data() as Item).projectId !== transaction.projectId)) {
      throw new Error("STALE_MEMBERSHIP");
    }

    const now = FieldValue.serverTimestamp();
    firestoreTransaction.update(transactionRef, {
      budgetCategoryId: input.targetBudgetCategoryId,
      updatedAt: now,
      updatedBy: actor,
    });
    for (const itemRef of itemRefs) {
      firestoreTransaction.update(itemRef, {
        budgetCategoryId: input.targetBudgetCategoryId,
        updatedAt: now,
        updatedBy: actor,
      });
    }
    firestoreTransaction.create(auditRef, {
      accountId: getAccountId(),
      transactionId: input.transactionId,
      requestId: input.requestId,
      previousBudgetCategoryId: input.expectedCurrentBudgetCategoryId,
      budgetCategoryId: input.targetBudgetCategoryId,
      projectId: transaction.projectId,
      itemIds,
      source: "mcp",
      createdBy: actor,
      createdAt: now,
    });
    return { ...plan, alreadyApplied: false, auditEventId: auditRef.id };
  });
}

export function registerTransactionCategoryReclassificationTools(server: McpServer, db: Firestore) {
  server.tool(
    "reclassify_inventory_purchase_category",
    "[correction, mutating] Change the category of an eligible project Purchase from Inventory and all currently attached items atomically. Invoice records are untouched. Use dryRun first.",
    {
      transactionId: z.string().min(1),
      targetBudgetCategoryId: z.string().min(1),
      expectedCurrentBudgetCategoryId: z.string().min(1),
      requestId: z.string().min(1).max(200).optional(),
      dryRun: z.boolean().default(true),
    },
    withTelemetry("reclassify_inventory_purchase_category", async (args) => {
      const requestId = args.requestId?.trim() || randomUUID();
      const input: CorrectionInput = {
        transactionId: args.transactionId.trim(),
        targetBudgetCategoryId: args.targetBudgetCategoryId.trim(),
        expectedCurrentBudgetCategoryId: args.expectedCurrentBudgetCategoryId.trim(),
        requestId,
      };
      const plan = await buildPlan(db, input);
      if (args.dryRun) return asToolResponse({ dryRun: true, plan: { ...plan, requestId } });
      if (!plan.eligible) return publicError(plan);
      if (plan.noOp) return asToolResponse({ dryRun: false, result: { ...plan, alreadyApplied: false } });
      try {
        return asToolResponse({ dryRun: false, result: await commitCorrection(db, input, plan) });
      } catch (error) {
        return toolError({
          code: "CONFLICT",
          message: error instanceof Error ? error.message : "The category correction could not be committed.",
          hint: "Retry with the same requestId after refreshing the transaction.",
          retryable: true,
        });
      }
    }),
  );
}
