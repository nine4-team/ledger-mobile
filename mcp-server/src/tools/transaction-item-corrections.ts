import { randomUUID } from "node:crypto";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  FieldValue,
  type DocumentData,
  type DocumentReference,
  type DocumentSnapshot,
  type Firestore,
  type Query,
  type QuerySnapshot,
  type Transaction as FirestoreTransaction,
} from "firebase-admin/firestore";
import { z } from "zod";
import type { BudgetCategory, Invoice, Item, Transaction } from "../types.js";
import { getAccountId, getUid } from "../context.js";
import { resolveCategoryType } from "../util/budget.js";
import { toolError } from "../util/errors.js";
import { effectiveProjectPriceCents } from "../util/item-pricing.js";
import { accountCollection, accountPath } from "../util/query.js";
import { asToolResponse } from "../util/projections.js";
import { withTelemetry } from "../util/telemetry.js";

const MAX_ATOMIC_WRITES = 500;
const FIRESTORE_IN_LIMIT = 30;

type DestinationPurchaseHandling = "project_reimbursement" | null;

type CorrectionBlocker = {
  code: string;
  message: string;
  referenceIds?: string[];
};

type DetachedSpaceAssignment = {
  itemId: string;
  spaceId: string;
  spaceProjectId: string | null;
  spaceFound: boolean;
};

type ItemWrite = {
  itemId: string;
  updates: Record<string, unknown>;
  publicChanges: Record<string, unknown>;
};

type InternalCorrectionPlan = {
  publicPlan: Record<string, unknown> & {
    eligible: boolean;
    blockers: CorrectionBlocker[];
    noOp: boolean;
  };
  transactionRef: DocumentReference | null;
  transactionUpdates: Record<string, unknown>;
  itemWrites: ItemWrite[];
  lineageItemIds: string[];
  sourceProjectId: string | null;
  destinationProjectId: string | null;
};

type CorrectionInput = {
  transactionId: string;
  destinationProjectId: string | null;
  destinationBudgetCategoryId?: string | null;
  destinationPurchaseHandling?: DestinationPurchaseHandling;
  destinationPurchaseHandlingWasProvided: boolean;
  requestId: string;
};

class CorrectionBlockedError extends Error {
  constructor(readonly plan: InternalCorrectionPlan) {
    super("Transaction-and-items correction was blocked.");
  }
}

function scopeId(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function categoryId(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function normalizedType(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function isInventoryMovement(transaction: Transaction): boolean {
  if (transaction.isCanonicalInventorySale === true || transaction.isCanonicalInventory === true) {
    return true;
  }
  const type = normalizedType(transaction.type);
  const source = transaction.source?.trim().toLowerCase() ?? "";
  return type === "sale" ||
    ((type === "purchase" || type === "return") && source.endsWith(" inventory"));
}

function isMovementLineage(value: unknown): boolean {
  if (typeof value !== "string") return false;
  const normalized = value.toLowerCase().replace(/[^a-z]/g, "");
  return normalized === "sold" ||
    normalized === "returned" ||
    normalized === "soldtoinventory" ||
    normalized === "transferred";
}

function chunks<T>(values: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}

function sameIdSet(left: string[], right: string[]): boolean {
  if (left.length !== right.length) return false;
  const rightSet = new Set(right);
  return left.every((id) => rightSet.has(id));
}

function snapshotData<T>(snapshot: DocumentSnapshot): (T & { id: string }) | null {
  if (!snapshot.exists) return null;
  return { ...(snapshot.data() as T), id: snapshot.id };
}

async function readDocument(
  ref: DocumentReference,
  firestoreTransaction?: FirestoreTransaction
): Promise<DocumentSnapshot> {
  return firestoreTransaction ? firestoreTransaction.get(ref) : ref.get();
}

async function readDocuments(
  db: Firestore,
  refs: DocumentReference[],
  firestoreTransaction?: FirestoreTransaction
): Promise<DocumentSnapshot[]> {
  if (refs.length === 0) return [];
  return firestoreTransaction
    ? firestoreTransaction.getAll(...refs)
    : db.getAll(...refs);
}

async function readQuery(
  query: Query,
  firestoreTransaction?: FirestoreTransaction
): Promise<QuerySnapshot> {
  return firestoreTransaction ? firestoreTransaction.get(query) : query.get();
}

function invoiceReferencesAggregate(
  invoice: Invoice,
  transactionId: string,
  itemIds: Set<string>
): boolean {
  if ((invoice.transactionIds ?? []).includes(transactionId)) return true;
  if ((invoice.itemIds ?? []).some((id) => itemIds.has(id))) return true;
  return (invoice.lines ?? []).some((line) => {
    const raw = line as typeof line & { sourceTransactionId?: string };
    return (
      (raw.sourceType === "transaction" && raw.sourceId === transactionId) ||
      (raw.sourceType === "item" && typeof raw.sourceId === "string" && itemIds.has(raw.sourceId)) ||
      raw.sourceTransactionId === transactionId ||
      (raw.settlementTransactionIds ?? []).includes(transactionId)
    );
  });
}

function addChange(
  updates: Record<string, unknown>,
  publicChanges: Record<string, unknown>,
  key: string,
  current: unknown,
  next: unknown,
  deleteWhenNull = false
) {
  const normalizedCurrent = current === undefined ? null : current;
  const normalizedNext = next === undefined ? null : next;
  if (normalizedCurrent === normalizedNext) return;
  updates[key] = deleteWhenNull && normalizedNext === null ? FieldValue.delete() : normalizedNext;
  publicChanges[key] = normalizedNext;
}

function emptyPlan(
  transactionId: string,
  destinationProjectId: string | null,
  destinationBudgetCategoryId: string | null,
  blocker: CorrectionBlocker
): InternalCorrectionPlan {
  return {
    publicPlan: {
      transactionId,
      destination: {
        projectId: destinationProjectId,
        budgetCategoryId: destinationBudgetCategoryId,
      },
      eligible: false,
      blockers: [blocker],
      noOp: false,
      activeItemIds: [],
      activeItemCount: 0,
      detachedSpaceAssignments: [],
      writeCount: 0,
    },
    transactionRef: null,
    transactionUpdates: {},
    itemWrites: [],
    lineageItemIds: [],
    sourceProjectId: null,
    destinationProjectId,
  };
}

async function buildCorrectionPlan(
  db: Firestore,
  input: CorrectionInput,
  firestoreTransaction?: FirestoreTransaction
): Promise<InternalCorrectionPlan> {
  const txRef = accountCollection(db, "transactions").doc(input.transactionId);
  const txSnapshot = await readDocument(txRef, firestoreTransaction);
  const transaction = snapshotData<Transaction>(txSnapshot);
  const destinationCategoryId = categoryId(input.destinationBudgetCategoryId);

  if (!transaction) {
    return emptyPlan(
      input.transactionId,
      input.destinationProjectId,
      destinationCategoryId,
      {
        code: "TRANSACTION_NOT_FOUND",
        message: `Transaction ${input.transactionId} was not found.`,
      }
    );
  }

  const blockers: CorrectionBlocker[] = [];
  const type = normalizedType(transaction.type);
  const sourceProjectId = scopeId(transaction.projectId);
  const sourceCategoryId = categoryId(transaction.budgetCategoryId);
  const destinationProjectId = scopeId(input.destinationProjectId);

  if (transaction.status === "canceled") {
    blockers.push({ code: "TRANSACTION_CANCELED", message: "Canceled transactions cannot use this correction." });
  }
  if (type !== "purchase" && type !== "return") {
    blockers.push({
      code: "UNSUPPORTED_TRANSACTION_TYPE",
      message: `Transaction type ${transaction.type ?? "(missing)"} is not an ordinary itemized Purchase or Return.`,
    });
  }
  if (isInventoryMovement(transaction)) {
    blockers.push({
      code: "IMMUTABLE_INVENTORY_MOVEMENT",
      message: "Generated inventory-movement transactions cannot be structurally corrected in place.",
    });
  }
  if (transaction.settlementInvoiceId) {
    blockers.push({
      code: "SETTLEMENT_REFERENCE",
      message: "This transaction records collection for an invoice.",
      referenceIds: [transaction.settlementInvoiceId],
    });
  }

  if (destinationProjectId) {
    if (!destinationCategoryId) {
      blockers.push({
        code: "DESTINATION_CATEGORY_REQUIRED",
        message: "A project destination requires a budget category.",
      });
    } else {
      const projectRef = accountCollection(db, "projects").doc(destinationProjectId);
      const presetRef = db.doc(
        `${accountPath()}/presets/default/budgetCategories/${destinationCategoryId}`
      );
      const enabledRef = projectRef.collection("budgetCategories").doc(destinationCategoryId);
      const [projectSnapshot, presetSnapshot, enabledSnapshot] = await readDocuments(
        db,
        [projectRef, presetRef, enabledRef],
        firestoreTransaction
      );
      if (!projectSnapshot.exists) {
        blockers.push({
          code: "DESTINATION_PROJECT_NOT_FOUND",
          message: `Destination project ${destinationProjectId} was not found.`,
        });
      } else if (projectSnapshot.data()?.isArchived === true) {
        blockers.push({
          code: "DESTINATION_PROJECT_ARCHIVED",
          message: `Destination project ${destinationProjectId} is archived.`,
        });
      }
      if (!presetSnapshot.exists) {
        blockers.push({
          code: "DESTINATION_CATEGORY_NOT_FOUND",
          message: `Budget category ${destinationCategoryId} was not found.`,
        });
      } else {
        const category = {
          ...(presetSnapshot.data() as BudgetCategory),
          id: presetSnapshot.id,
        };
        const raw = presetSnapshot.data() ?? {};
        if (category.isArchived === true || raw.isSystem === true || resolveCategoryType(category) !== "itemized") {
          blockers.push({
            code: "DESTINATION_CATEGORY_INELIGIBLE",
            message: `Budget category ${destinationCategoryId} must be active, non-system, and itemized.`,
          });
        }
      }
      if (!enabledSnapshot.exists) {
        blockers.push({
          code: "DESTINATION_CATEGORY_NOT_ENABLED",
          message: `Budget category ${destinationCategoryId} is not enabled in project ${destinationProjectId}.`,
        });
      }
    }
  } else if (destinationCategoryId !== null) {
    blockers.push({
      code: "INVENTORY_CATEGORY_FORBIDDEN",
      message: "Business Inventory cannot carry a project budget category.",
    });
  }

  if (type !== "purchase" && input.destinationPurchaseHandlingWasProvided) {
    blockers.push({
      code: "PURCHASE_HANDLING_NOT_APPLICABLE",
      message: "destinationPurchaseHandling is valid only for a Purchase transaction.",
    });
  }
  if (!destinationProjectId && input.destinationPurchaseHandlingWasProvided) {
    blockers.push({
      code: "PURCHASE_HANDLING_NOT_APPLICABLE",
      message: "Business Inventory always uses inventory_resale handling for an eligible Purchase.",
    });
  }
  if (
    type === "purchase" &&
    sourceProjectId === null &&
    destinationProjectId !== null &&
    !input.destinationPurchaseHandlingWasProvided
  ) {
    blockers.push({
      code: "PROJECT_PURCHASE_HANDLING_REQUIRED",
      message: "Moving an inventory Purchase directly into a project requires an explicit destinationPurchaseHandling choice.",
    });
  }
  if (type === "purchase") {
    const purchasedBy = transaction.purchasedBy?.trim().toLowerCase() ?? "";
    const explicitlyNotBusinessPaid = purchasedBy.length > 0 &&
      purchasedBy !== "missing" &&
      purchasedBy !== "design-business";
    if (
      explicitlyNotBusinessPaid &&
      (destinationProjectId === null || input.destinationPurchaseHandling === "project_reimbursement")
    ) {
      blockers.push({
        code: "PURCHASE_PAYER_CONFLICT",
        message: "The requested inventory-resale/project-reimbursement handling conflicts with the transaction's explicit non-business payer.",
      });
    }
  }

  const rawItemIds = Array.isArray(transaction.itemIds) ? transaction.itemIds : [];
  const listedItemIds = rawItemIds.filter((id): id is string => typeof id === "string" && id.length > 0);
  const duplicateItemIds = listedItemIds.filter((id, index) => listedItemIds.indexOf(id) !== index);
  if (listedItemIds.length !== rawItemIds.length) {
    blockers.push({
      code: "INVALID_TRANSACTION_MEMBERSHIP",
      message: "transaction.itemIds contains a non-string or empty item ID.",
    });
  }
  if (duplicateItemIds.length > 0) {
    blockers.push({
      code: "DUPLICATE_TRANSACTION_MEMBERSHIP",
      message: "transaction.itemIds contains duplicate item IDs.",
      referenceIds: unique(duplicateItemIds),
    });
  }

  const listedItemRefs = listedItemIds.map((id) => accountCollection(db, "items").doc(id));
  const listedSnapshots = await readDocuments(db, listedItemRefs, firestoreTransaction);
  const listedItems = listedSnapshots
    .map((snapshot) => snapshotData<Item>(snapshot))
    .filter((item): item is Item & { id: string } => item !== null);
  const missingItemIds = listedSnapshots
    .map((snapshot, index) => snapshot.exists ? null : listedItemIds[index])
    .filter((id): id is string => id !== null);
  if (missingItemIds.length > 0) {
    blockers.push({
      code: "MISSING_ACTIVE_ITEMS",
      message: "One or more transaction itemIds do not resolve to an item.",
      referenceIds: missingItemIds,
    });
  }

  const reverseSnapshot = await readQuery(
    accountCollection(db, "items").where("transactionId", "==", input.transactionId),
    firestoreTransaction
  );
  const reverseItems = reverseSnapshot.docs.map((doc) => ({
    ...(doc.data() as Item),
    id: doc.id,
  }));
  const reverseItemIds = reverseItems.map((item) => item.id);
  if (!sameIdSet(listedItemIds, reverseItemIds)) {
    blockers.push({
      code: "ASYMMETRIC_ACTIVE_MEMBERSHIP",
      message: "transaction.itemIds and reverse item.transactionId membership do not match exactly.",
      referenceIds: unique([...listedItemIds, ...reverseItemIds]),
    });
  }

  const aggregateItemsById = new Map<string, Item & { id: string }>();
  for (const item of [...listedItems, ...reverseItems]) aggregateItemsById.set(item.id, item);
  const aggregateItems = [...aggregateItemsById.values()];
  const aggregateItemIds = new Set(aggregateItems.map((item) => item.id));

  const inconsistentItemIds = aggregateItems
    .filter((item) => {
      const itemProjectId = scopeId(item.projectId);
      const itemCategoryId = categoryId(item.budgetCategoryId);
      if (itemProjectId !== sourceProjectId) return true;
      return sourceProjectId === null
        ? itemCategoryId !== null
        : itemCategoryId !== sourceCategoryId;
    })
    .map((item) => item.id);
  if (inconsistentItemIds.length > 0) {
    blockers.push({
      code: "INCONSISTENT_AGGREGATE_SCOPE",
      message: "One or more active items do not match the transaction's current project/category.",
      referenceIds: inconsistentItemIds,
    });
  }
  if (sourceProjectId !== null && sourceCategoryId === null) {
    blockers.push({
      code: "SOURCE_CATEGORY_MISSING",
      message: "The project-scoped transaction has no real budget category.",
    });
  }
  if (sourceProjectId === null && sourceCategoryId !== null) {
    blockers.push({
      code: "SOURCE_INVENTORY_CATEGORY",
      message: "The inventory-scoped transaction incorrectly carries a project budget category.",
    });
  }

  const provenanceSnapshot = await readQuery(
    accountCollection(db, "items").where("inventoryEntryTransactionId", "==", input.transactionId),
    firestoreTransaction
  );
  if (!provenanceSnapshot.empty) {
    blockers.push({
      code: "INVENTORY_PROVENANCE",
      message: "Items use this transaction as inventory-entry provenance.",
      referenceIds: provenanceSnapshot.docs.map((doc) => doc.id),
    });
  }

  const lineageDocs = new Map<string, DocumentData>();
  const lineageFromSnapshot = await readQuery(
    accountCollection(db, "lineageEdges").where("fromTransactionId", "==", input.transactionId),
    firestoreTransaction
  );
  const lineageToSnapshot = await readQuery(
    accountCollection(db, "lineageEdges").where("toTransactionId", "==", input.transactionId),
    firestoreTransaction
  );
  for (const doc of [...lineageFromSnapshot.docs, ...lineageToSnapshot.docs]) {
    lineageDocs.set(doc.id, doc.data());
  }
  for (const itemIdChunk of chunks([...aggregateItemIds], FIRESTORE_IN_LIMIT)) {
    const snapshot = await readQuery(
      accountCollection(db, "lineageEdges").where("itemId", "in", itemIdChunk),
      firestoreTransaction
    );
    for (const doc of snapshot.docs) lineageDocs.set(doc.id, doc.data());
  }
  const movementLineageIds = [...lineageDocs.entries()]
    .filter(([, data]) => isMovementLineage(data.movementKind))
    .map(([id]) => id);
  if (movementLineageIds.length > 0) {
    blockers.push({
      code: "DOWNSTREAM_MOVEMENT_LINEAGE",
      message: "The transaction or its active items have sale/return movement history that cannot be rewritten as a simple correction.",
      referenceIds: movementLineageIds,
    });
  }

  const invoicesSnapshot = await readQuery(accountCollection(db, "invoices"), firestoreTransaction);
  const invoiceReferenceIds = invoicesSnapshot.docs
    .filter((doc) => invoiceReferencesAggregate(
      { ...(doc.data() as Invoice), id: doc.id },
      input.transactionId,
      aggregateItemIds
    ))
    .map((doc) => doc.id);
  if (invoiceReferenceIds.length > 0) {
    blockers.push({
      code: "INVOICE_REFERENCES",
      message: "Invoices reference this transaction or one of its active items.",
      referenceIds: invoiceReferenceIds,
    });
  }

  const quickDraftSnapshots = await Promise.all([
    readQuery(
      accountCollection(db, "protoItems").where("transactionId", "==", input.transactionId),
      firestoreTransaction
    ),
    readQuery(
      accountCollection(db, "protoItems").where("candidateTransactionId", "==", input.transactionId),
      firestoreTransaction
    ),
  ]);
  const quickDraftReferenceIds = unique(quickDraftSnapshots.flatMap((snapshot) =>
    snapshot.docs.map((doc) => doc.id)
  ));
  if (quickDraftReferenceIds.length > 0) {
    blockers.push({
      code: "QUICK_DRAFT_REFERENCES",
      message: "Quick Draft items reference this transaction and must be resolved first.",
      referenceIds: quickDraftReferenceIds,
    });
  }

  const spaceIds = unique(aggregateItems
    .map((item) => item.spaceId)
    .filter((id): id is string => typeof id === "string" && id.length > 0));
  const spaceSnapshots = await readDocuments(
    db,
    spaceIds.map((id) => accountCollection(db, "spaces").doc(id)),
    firestoreTransaction
  );
  const spacesById = new Map(spaceSnapshots.map((snapshot) => [
    snapshot.id,
    snapshot.exists ? snapshot.data() ?? {} : null,
  ]));
  const detachedSpaceAssignments: DetachedSpaceAssignment[] = [];

  const transactionUpdates: Record<string, unknown> = {};
  const transactionChanges: Record<string, unknown> = {};
  addChange(transactionUpdates, transactionChanges, "projectId", sourceProjectId, destinationProjectId);
  addChange(
    transactionUpdates,
    transactionChanges,
    "budgetCategoryId",
    sourceCategoryId,
    destinationProjectId ? destinationCategoryId : null
  );

  if (type === "purchase") {
    if (destinationProjectId === null) {
      addChange(transactionUpdates, transactionChanges, "purchaseHandling", transaction.purchaseHandling, "inventory_resale");
      addChange(transactionUpdates, transactionChanges, "reimbursementType", transaction.reimbursementType, null, true);
    } else if (input.destinationPurchaseHandlingWasProvided) {
      addChange(
        transactionUpdates,
        transactionChanges,
        "purchaseHandling",
        transaction.purchaseHandling,
        input.destinationPurchaseHandling,
        true
      );
      addChange(
        transactionUpdates,
        transactionChanges,
        "reimbursementType",
        transaction.reimbursementType,
        input.destinationPurchaseHandling === "project_reimbursement" ? "owed-to-company" : null,
        true
      );
    }
  }
  addChange(transactionUpdates, transactionChanges, "intendedProjectId", transaction.intendedProjectId, null, true);
  addChange(transactionUpdates, transactionChanges, "intendedBudgetCategoryId", transaction.intendedBudgetCategoryId, null, true);
  addChange(transactionUpdates, transactionChanges, "inventoryIntentResolvedAt", transaction.inventoryIntentResolvedAt, null, true);

  const itemWrites: ItemWrite[] = [];
  for (const item of listedItems) {
    const updates: Record<string, unknown> = {};
    const publicChanges: Record<string, unknown> = {};
    addChange(updates, publicChanges, "projectId", scopeId(item.projectId), destinationProjectId);
    addChange(
      updates,
      publicChanges,
      "budgetCategoryId",
      categoryId(item.budgetCategoryId),
      destinationProjectId ? destinationCategoryId : null
    );

    if (item.spaceId) {
      const space = spacesById.get(item.spaceId) ?? null;
      const spaceProjectId = scopeId(space?.projectId);
      if (space === null || spaceProjectId !== destinationProjectId) {
        updates.spaceId = null;
        publicChanges.spaceId = null;
        detachedSpaceAssignments.push({
          itemId: item.id,
          spaceId: item.spaceId,
          spaceProjectId,
          spaceFound: space !== null,
        });
      }
    }

    if (destinationProjectId !== null) {
      const normalizedProjectPrice = effectiveProjectPriceCents(item);
      if (normalizedProjectPrice > 0 && item.projectPriceCents !== normalizedProjectPrice) {
        updates.projectPriceCents = normalizedProjectPrice;
        publicChanges.projectPriceCents = normalizedProjectPrice;
      }
    }

    if (Object.keys(updates).length > 0) {
      itemWrites.push({ itemId: item.id, updates, publicChanges });
    }
  }

  const structuralChange = sourceProjectId !== destinationProjectId ||
    sourceCategoryId !== (destinationProjectId ? destinationCategoryId : null);
  const lineageItemIds = structuralChange ? listedItemIds : [];
  const transactionWriteCount = Object.keys(transactionUpdates).length > 0 ? 1 : 0;
  const writeCount = transactionWriteCount + itemWrites.length + lineageItemIds.length;
  if (writeCount > MAX_ATOMIC_WRITES) {
    blockers.push({
      code: "ATOMIC_WRITE_LIMIT_EXCEEDED",
      message: `This correction requires ${writeCount} writes, exceeding Firestore's ${MAX_ATOMIC_WRITES}-write atomic limit.`,
    });
  }

  const noOp = writeCount === 0;
  const publicPlan = {
    requestId: input.requestId,
    transactionId: input.transactionId,
    transactionType: transaction.type ?? null,
    current: {
      projectId: sourceProjectId,
      budgetCategoryId: sourceCategoryId,
    },
    destination: {
      projectId: destinationProjectId,
      budgetCategoryId: destinationProjectId ? destinationCategoryId : null,
    },
    activeItemIds: listedItemIds,
    activeItemCount: listedItemIds.length,
    transactionChanges,
    itemChanges: itemWrites.map((write) => ({
      itemId: write.itemId,
      changes: write.publicChanges,
    })),
    detachedSpaceAssignments,
    lineageWrites: lineageItemIds.length,
    writeCount,
    noOp,
    eligible: blockers.length === 0,
    blockers,
  };

  return {
    publicPlan,
    transactionRef: txRef,
    transactionUpdates,
    itemWrites,
    lineageItemIds,
    sourceProjectId,
    destinationProjectId,
  };
}

function blockedResponse(plan: InternalCorrectionPlan) {
  const missing = plan.publicPlan.blockers.some((blocker) => blocker.code === "TRANSACTION_NOT_FOUND");
  return toolError({
    code: missing ? "NOT_FOUND" : "CONFLICT",
    message: missing
      ? "The transaction could not be found."
      : "The transaction and its items cannot be safely corrected as requested.",
    hint: "Review the dry-run blockers and resolve them before retrying. Do not replace this correction with a Sale or Return unless a real business movement occurred.",
    retryable: !missing,
    details: { plan: plan.publicPlan },
  });
}

export function registerTransactionItemCorrectionTools(server: McpServer, db: Firestore) {
  server.tool(
    "correct_transaction_and_its_items",
    "[correction, mutating] Correct one ordinary transaction and every currently attached item as one atomic aggregate. Supports project → Business Inventory, Business Inventory → project, and project → project without creating a Sale, Return, or other financial movement. Preserves transaction/item associations, validates exact two-sided membership, blocks invoice/provenance/movement-history conflicts, and detaches incompatible spaces with a receipt. Defaults to dry-run. For an inventory Purchase moving directly into a project, pass destinationPurchaseHandling explicitly: project_reimbursement, or null for an ordinary project Purchase.",
    {
      transactionId: z.string().min(1).describe("Transaction aggregate to correct."),
      destinationProjectId: z.string().min(1).nullable().describe("Destination project ID, or null for Business Inventory."),
      destinationBudgetCategoryId: z.string().min(1).nullable().optional().describe("Required for a project destination; omit or pass null for Business Inventory."),
      destinationPurchaseHandling: z.enum(["project_reimbursement"]).nullable().optional().describe("For a Purchase moving from inventory into a project, explicitly pass project_reimbursement or null for an ordinary project Purchase. Omit for other directions to preserve applicable project handling."),
      requestId: z.string().min(1).max(200).optional().describe("Optional caller request ID included in correction lineage."),
      dryRun: z.boolean().default(true),
    },
    withTelemetry("correct_transaction_and_its_items", async (args) => {
      const requestId = args.requestId?.trim() || randomUUID();
      const input: CorrectionInput = {
        transactionId: args.transactionId,
        destinationProjectId: args.destinationProjectId,
        destinationBudgetCategoryId: args.destinationBudgetCategoryId,
        destinationPurchaseHandling: args.destinationPurchaseHandling,
        destinationPurchaseHandlingWasProvided: Object.prototype.hasOwnProperty.call(
          args,
          "destinationPurchaseHandling"
        ),
        requestId,
      };

      if (args.dryRun) {
        const plan = await buildCorrectionPlan(db, input);
        return asToolResponse({ dryRun: true, plan: plan.publicPlan });
      }

      try {
        const committedPlan = await db.runTransaction(async (firestoreTransaction) => {
          const plan = await buildCorrectionPlan(db, input, firestoreTransaction);
          if (!plan.publicPlan.eligible) throw new CorrectionBlockedError(plan);
          if (plan.publicPlan.noOp || !plan.transactionRef) return plan;

          const now = FieldValue.serverTimestamp();
          const actor = getUid();
          if (Object.keys(plan.transactionUpdates).length > 0) {
            firestoreTransaction.update(plan.transactionRef, {
              ...plan.transactionUpdates,
              updatedAt: now,
              updatedBy: actor,
            });
          }
          for (const itemWrite of plan.itemWrites) {
            firestoreTransaction.update(accountCollection(db, "items").doc(itemWrite.itemId), {
              ...itemWrite.updates,
              updatedAt: now,
              updatedBy: actor,
            });
          }
          for (const itemId of plan.lineageItemIds) {
            firestoreTransaction.set(accountCollection(db, "lineageEdges").doc(), {
              accountId: getAccountId(),
              itemId,
              fromTransactionId: input.transactionId,
              toTransactionId: input.transactionId,
              fromProjectId: plan.sourceProjectId,
              toProjectId: plan.destinationProjectId,
              movementKind: "correction",
              source: "mcp",
              requestId,
              note: "Corrected transaction and all active items as one aggregate",
              createdBy: actor,
              createdAt: now,
            });
          }
          return plan;
        });
        return asToolResponse({
          dryRun: false,
          corrected: !committedPlan.publicPlan.noOp,
          plan: committedPlan.publicPlan,
        });
      } catch (error) {
        if (error instanceof CorrectionBlockedError) return blockedResponse(error.plan);
        throw error;
      }
    })
  );
}
