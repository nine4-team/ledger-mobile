import type {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Query,
  QuerySnapshot,
  Transaction as FirestoreTransaction,
} from "firebase-admin/firestore";
import type { Invoice, Transaction } from "../types.js";
import { accountCollection } from "./query.js";
import { normalizeSpendAmount } from "./budget.js";

export const MAX_TRANSACTION_DELETION_BATCH_SIZE = 20;

export interface DeletionBlocker {
  code: string;
  message: string;
  referenceIds?: string[];
}

export interface TransactionDeletionChecks {
  canceled: boolean;
  budgetNeutral: boolean;
  normalizedBudgetContributionCents: number;
  activeItemIds: string[];
  currentItemReferenceIds: string[];
  inventoryProvenanceItemIds: string[];
  invoiceReferenceIds: string[];
  settlementInvoiceId: string | null;
  attachmentCount: number;
  lineageFromEdgeIds: string[];
  lineageToEdgeIds: string[];
  quickDraftReferenceIds: string[];
  repricingEventIds: string[];
  linkedIngestionTransactionIds: string[];
}

export interface TransactionDeletionPreflight {
  transactionId: string;
  found: boolean;
  alreadyDeleted: boolean;
  eligible: boolean;
  transactionSummary: Record<string, unknown> | null;
  checks: TransactionDeletionChecks | null;
  blockers: DeletionBlocker[];
  transactionSnapshot: DocumentData | null;
  existingTombstone: DocumentData | null;
}

type ReferenceIdsByTransaction = Map<string, string[]>;

function addReference(
  references: ReferenceIdsByTransaction,
  transactionId: string,
  referenceId: string
) {
  const ids = references.get(transactionId) ?? [];
  if (!ids.includes(referenceId)) ids.push(referenceId);
  references.set(transactionId, ids);
}

function referencesFor(
  references: ReferenceIdsByTransaction,
  transactionId: string
): string[] {
  return references.get(transactionId) ?? [];
}

function invoiceReferencesTransaction(invoice: Invoice, transactionId: string): boolean {
  if ((invoice.transactionIds ?? []).includes(transactionId)) return true;
  return (invoice.lines ?? []).some((line) => {
    const raw = line as typeof line & { sourceTransactionId?: string };
    return (
      (raw.sourceType === "transaction" && raw.sourceId === transactionId) ||
      raw.sourceTransactionId === transactionId ||
      (raw.settlementTransactionIds ?? []).includes(transactionId)
    );
  });
}

function transactionSummary(transactionId: string, data: DocumentData): Record<string, unknown> {
  return {
    id: transactionId,
    type: data.type ?? null,
    status: data.status ?? null,
    source: data.source ?? null,
    transactionDate: data.transactionDate ?? null,
    projectId: data.projectId ?? null,
    budgetCategoryId: data.budgetCategoryId ?? null,
    amountCents: data.amountCents ?? null,
    subtotalCents: data.subtotalCents ?? null,
    itemCount: Array.isArray(data.itemIds) ? data.itemIds.length : 0,
  };
}

function attachmentCount(data: DocumentData): number {
  return [data.receiptImages, data.otherImages, data.transactionImages]
    .reduce<number>((count, value) => count + (Array.isArray(value) ? value.length : 0), 0);
}

async function readDocuments(
  db: Firestore,
  refs: DocumentReference[],
  firestoreTransaction?: FirestoreTransaction
): Promise<DocumentSnapshot[]> {
  return firestoreTransaction
    ? firestoreTransaction.getAll(...refs)
    : db.getAll(...refs);
}

async function readQuery(
  query: Query,
  firestoreTransaction?: FirestoreTransaction
): Promise<QuerySnapshot> {
  return firestoreTransaction
    ? firestoreTransaction.get(query)
    : query.get();
}

function buildPreflight(
  transactionId: string,
  transactionDocument: DocumentSnapshot,
  tombstoneDocument: DocumentSnapshot,
  references: {
    currentItems: ReferenceIdsByTransaction;
    inventoryItems: ReferenceIdsByTransaction;
    lineageFrom: ReferenceIdsByTransaction;
    lineageTo: ReferenceIdsByTransaction;
    invoices: ReferenceIdsByTransaction;
    quickDrafts: ReferenceIdsByTransaction;
    repricingEvents: ReferenceIdsByTransaction;
    linkedIngestion: ReferenceIdsByTransaction;
  }
): TransactionDeletionPreflight {
  const existingTombstone = tombstoneDocument.exists
    ? (tombstoneDocument.data() ?? {})
    : null;

  if (!transactionDocument.exists) {
    return {
      transactionId,
      found: false,
      alreadyDeleted: existingTombstone != null,
      eligible: false,
      transactionSummary: existingTombstone?.transactionSnapshot
        ? transactionSummary(transactionId, existingTombstone.transactionSnapshot as DocumentData)
        : null,
      checks: (existingTombstone?.checks as TransactionDeletionChecks | undefined) ?? null,
      blockers: [],
      transactionSnapshot: null,
      existingTombstone,
    };
  }

  const data = transactionDocument.data() ?? {};
  const ledgerTransaction = { id: transactionId, ...data } as Transaction & { id: string };
  const activeItemIds = Array.isArray(data.itemIds)
    ? data.itemIds.filter((id: unknown): id is string => typeof id === "string")
    : [];
  const currentItemReferenceIds = referencesFor(references.currentItems, transactionId);
  const inventoryProvenanceItemIds = referencesFor(references.inventoryItems, transactionId);
  const lineageFromEdgeIds = referencesFor(references.lineageFrom, transactionId);
  const lineageToEdgeIds = referencesFor(references.lineageTo, transactionId);
  const invoiceReferenceIds = referencesFor(references.invoices, transactionId);
  const quickDraftReferenceIds = referencesFor(references.quickDrafts, transactionId);
  const repricingEventIds = referencesFor(references.repricingEvents, transactionId);
  const linkedIngestionTransactionIds = referencesFor(references.linkedIngestion, transactionId)
    .filter((id) => id !== transactionId);
  const normalizedBudgetContributionCents = normalizeSpendAmount(ledgerTransaction);

  const checks: TransactionDeletionChecks = {
    canceled: data.status === "canceled",
    budgetNeutral: normalizedBudgetContributionCents === 0,
    normalizedBudgetContributionCents,
    activeItemIds,
    currentItemReferenceIds,
    inventoryProvenanceItemIds,
    invoiceReferenceIds,
    settlementInvoiceId: typeof data.settlementInvoiceId === "string" ? data.settlementInvoiceId : null,
    attachmentCount: attachmentCount(data),
    lineageFromEdgeIds,
    lineageToEdgeIds,
    quickDraftReferenceIds,
    repricingEventIds,
    linkedIngestionTransactionIds,
  };

  const blockers: DeletionBlocker[] = [];
  if (existingTombstone != null) {
    blockers.push({
      code: "TOMBSTONE_CONFLICT",
      message: "A deletion tombstone already exists while the live transaction is still present.",
    });
  }
  if (!checks.canceled) {
    blockers.push({ code: "TRANSACTION_NOT_CANCELED", message: "Transaction must be canceled before deletion." });
  }
  if (!checks.budgetNeutral) {
    blockers.push({ code: "BUDGET_NOT_NEUTRAL", message: "Transaction still contributes to a project budget." });
  }
  if (activeItemIds.length > 0) {
    blockers.push({ code: "ACTIVE_ITEM_IDS", message: "Transaction still owns active items.", referenceIds: activeItemIds });
  }
  if (currentItemReferenceIds.length > 0) {
    blockers.push({ code: "ITEM_BACK_REFERENCES", message: "Items still point to this transaction.", referenceIds: currentItemReferenceIds });
  }
  if (inventoryProvenanceItemIds.length > 0) {
    blockers.push({ code: "INVENTORY_PROVENANCE", message: "Items use this transaction as inventory-entry provenance.", referenceIds: inventoryProvenanceItemIds });
  }
  if (invoiceReferenceIds.length > 0) {
    blockers.push({ code: "INVOICE_REFERENCES", message: "Invoices still reference this transaction.", referenceIds: invoiceReferenceIds });
  }
  if (checks.settlementInvoiceId) {
    blockers.push({ code: "SETTLEMENT_REFERENCE", message: "This transaction records collection for an invoice.", referenceIds: [checks.settlementInvoiceId] });
  }
  if (checks.attachmentCount > 0) {
    blockers.push({ code: "ATTACHMENTS", message: "Transaction still has receipt or supporting attachments." });
  }
  if (lineageFromEdgeIds.length > 0 || lineageToEdgeIds.length > 0) {
    blockers.push({
      code: "MOVEMENT_LINEAGE",
      message: "Movement lineage references this transaction.",
      referenceIds: [...lineageFromEdgeIds, ...lineageToEdgeIds],
    });
  }
  if (quickDraftReferenceIds.length > 0) {
    blockers.push({ code: "QUICK_DRAFT_REFERENCES", message: "Quick Draft items still reference this transaction.", referenceIds: quickDraftReferenceIds });
  }
  if (repricingEventIds.length > 0) {
    blockers.push({ code: "REPRICING_AUDIT_REFERENCES", message: "Project-price adjustment audit events reference this transaction.", referenceIds: repricingEventIds });
  }
  if (linkedIngestionTransactionIds.length > 0) {
    blockers.push({
      code: "INGESTION_REFERENCES",
      message: "Related ingested transactions still reference this transaction.",
      referenceIds: linkedIngestionTransactionIds,
    });
  }

  return {
    transactionId,
    found: true,
    alreadyDeleted: false,
    eligible: blockers.length === 0,
    transactionSummary: transactionSummary(transactionId, data),
    checks,
    blockers,
    transactionSnapshot: { id: transactionId, ...data },
    existingTombstone,
  };
}

/**
 * Read every known transaction reference used by Ledger for one exact batch.
 * Shared collections are read once, and a maximum of 20 IDs keeps the
 * Firestore `in` / `array-contains-any` queries and atomic write count bounded.
 * When a Firestore transaction is supplied, every read participates in the
 * same serializable transaction as the tombstone writes and deletes.
 */
export async function readTransactionDeletionPreflights(
  db: Firestore,
  transactionIds: string[],
  firestoreTransaction?: FirestoreTransaction
): Promise<TransactionDeletionPreflight[]> {
  if (transactionIds.length < 1 || transactionIds.length > MAX_TRANSACTION_DELETION_BATCH_SIZE) {
    throw new Error(
      `Transaction deletion preflight requires 1-${MAX_TRANSACTION_DELETION_BATCH_SIZE} transaction IDs.`
    );
  }

  const transactionRefs = transactionIds.map((id) => accountCollection(db, "transactions").doc(id));
  const tombstoneRefs = transactionIds.map((id) => accountCollection(db, "transactionDeletionTombstones").doc(id));

  const [
    transactionDocuments,
    tombstoneDocuments,
    currentItemsSnapshot,
    inventoryItemsSnapshot,
    lineageFromSnapshot,
    lineageToSnapshot,
    invoicesSnapshot,
    quickDraftSnapshot,
    candidateDraftSnapshot,
    repricingSnapshot,
    linkedIngestionSnapshot,
  ] = await Promise.all([
    readDocuments(db, transactionRefs, firestoreTransaction),
    readDocuments(db, tombstoneRefs, firestoreTransaction),
    readQuery(accountCollection(db, "items").where("transactionId", "in", transactionIds), firestoreTransaction),
    readQuery(accountCollection(db, "items").where("inventoryEntryTransactionId", "in", transactionIds), firestoreTransaction),
    readQuery(accountCollection(db, "lineageEdges").where("fromTransactionId", "in", transactionIds), firestoreTransaction),
    readQuery(accountCollection(db, "lineageEdges").where("toTransactionId", "in", transactionIds), firestoreTransaction),
    readQuery(accountCollection(db, "invoices"), firestoreTransaction),
    readQuery(accountCollection(db, "protoItems").where("transactionId", "in", transactionIds), firestoreTransaction),
    readQuery(accountCollection(db, "protoItems").where("candidateTransactionId", "in", transactionIds), firestoreTransaction),
    readQuery(accountCollection(db, "transactionRepricingEvents").where("transactionId", "in", transactionIds), firestoreTransaction),
    readQuery(accountCollection(db, "transactions").where("ingestionMeta.linkedIngestionIds", "array-contains-any", transactionIds), firestoreTransaction),
  ]);

  const references = {
    currentItems: new Map<string, string[]>(),
    inventoryItems: new Map<string, string[]>(),
    lineageFrom: new Map<string, string[]>(),
    lineageTo: new Map<string, string[]>(),
    invoices: new Map<string, string[]>(),
    quickDrafts: new Map<string, string[]>(),
    repricingEvents: new Map<string, string[]>(),
    linkedIngestion: new Map<string, string[]>(),
  };

  for (const doc of currentItemsSnapshot.docs) {
    const id = doc.data().transactionId;
    if (typeof id === "string") addReference(references.currentItems, id, doc.id);
  }
  for (const doc of inventoryItemsSnapshot.docs) {
    const id = doc.data().inventoryEntryTransactionId;
    if (typeof id === "string") addReference(references.inventoryItems, id, doc.id);
  }
  for (const doc of lineageFromSnapshot.docs) {
    const id = doc.data().fromTransactionId;
    if (typeof id === "string") addReference(references.lineageFrom, id, doc.id);
  }
  for (const doc of lineageToSnapshot.docs) {
    const id = doc.data().toTransactionId;
    if (typeof id === "string") addReference(references.lineageTo, id, doc.id);
  }
  for (const doc of invoicesSnapshot.docs) {
    const invoice = doc.data() as Invoice;
    for (const transactionId of transactionIds) {
      if (invoiceReferencesTransaction(invoice, transactionId)) {
        addReference(references.invoices, transactionId, doc.id);
      }
    }
  }
  for (const doc of quickDraftSnapshot.docs) {
    const id = doc.data().transactionId;
    if (typeof id === "string") addReference(references.quickDrafts, id, doc.id);
  }
  for (const doc of candidateDraftSnapshot.docs) {
    const id = doc.data().candidateTransactionId;
    if (typeof id === "string") addReference(references.quickDrafts, id, doc.id);
  }
  for (const doc of repricingSnapshot.docs) {
    const id = doc.data().transactionId;
    if (typeof id === "string") addReference(references.repricingEvents, id, doc.id);
  }
  for (const doc of linkedIngestionSnapshot.docs) {
    const ids = doc.data().ingestionMeta?.linkedIngestionIds;
    if (!Array.isArray(ids)) continue;
    for (const id of ids) {
      if (typeof id === "string" && transactionIds.includes(id)) {
        addReference(references.linkedIngestion, id, doc.id);
      }
    }
  }

  return transactionIds.map((transactionId, index) => buildPreflight(
    transactionId,
    transactionDocuments[index],
    tombstoneDocuments[index],
    references
  ));
}

export async function readTransactionDeletionPreflight(
  db: Firestore,
  transactionId: string,
  firestoreTransaction?: FirestoreTransaction
): Promise<TransactionDeletionPreflight> {
  const [preflight] = await readTransactionDeletionPreflights(
    db,
    [transactionId],
    firestoreTransaction
  );
  return preflight;
}

export function publicDeletionPreflight(preflight: TransactionDeletionPreflight) {
  return {
    transactionId: preflight.transactionId,
    found: preflight.found,
    alreadyDeleted: preflight.alreadyDeleted,
    eligible: preflight.eligible,
    transaction: preflight.transactionSummary,
    checks: preflight.checks,
    blockers: preflight.blockers,
  };
}
