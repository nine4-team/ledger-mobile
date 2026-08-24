import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { FeeInstallment, Invoice, InvoiceLine, InvoiceLineSign, InvoiceLineSourceType, Item, Transaction } from "../types.js";
import { accountCollection, accountPath, getDoc, queryDocs } from "../util/query.js";
import { formatCents } from "../util/format.js";
import {
  ProjectionMode,
  ResponseLimitArg,
  asToolResponse,
  capResponse,
  invoiceSummary,
  pickFields,
} from "../util/projections.js";
import { notFound, validation } from "../util/errors.js";
import { withTelemetry } from "../util/telemetry.js";

const otherClientChargesAndCreditsId = "system-other-client-charges-and-credits";
const otherClientChargesAndCreditsName = "Other Client Charges & Credits";

const invoiceLineInput = z.object({
  id: z.string().optional().describe("Stable invoice line id. Omit to generate one."),
  sourceType: z.enum(["item", "transaction", "feeInstallment", "manual"]).describe("Line source. Use feeInstallment for planned/future fees; manual is an invoice-only charge or credit."),
  sourceId: z.string().optional().describe("Item, transaction, or fee installment id. Omit for manual lines."),
  amountCents: z.coerce.number().int().nonnegative().describe("Positive line amount in cents."),
  sign: z.union([z.literal(1), z.literal(-1)]).default(1).describe("1 = charge, -1 = credit."),
  budgetCategoryId: z.string().optional().describe("Budget category for source-backed lines. Manual lines automatically use Other Client Charges & Credits."),
  snapshotName: z.string().optional().describe("Frozen display name for the line."),
});

function normalizeInvoiceStatus(status: string | undefined) {
  if (status === "draft") return "created";
  if (status === "voided") return "canceled";
  return status;
}

function serializeLine(line: InvoiceLine): Record<string, unknown> {
  return {
    id: line.id ?? randomUUID(),
    sourceType: line.sourceType,
    ...(line.sourceId ? { sourceId: line.sourceId } : {}),
    amountCents: line.amountCents,
    sign: line.sign,
    ...(line.budgetCategoryId ? { budgetCategoryId: line.budgetCategoryId } : {}),
    ...(line.snapshotName ? { snapshotName: line.snapshotName } : {}),
    ...(line.settlementTransactionIds?.length ? { settlementTransactionIds: line.settlementTransactionIds } : {}),
  };
}

function normalizeLine(input: z.infer<typeof invoiceLineInput>): InvoiceLine {
  return {
    id: input.id ?? randomUUID(),
    sourceType: input.sourceType as InvoiceLineSourceType,
    sourceId: input.sourceType === "manual" ? undefined : input.sourceId,
    amountCents: input.amountCents,
    sign: input.sign as InvoiceLineSign,
    budgetCategoryId: input.sourceType === "manual" ? otherClientChargesAndCreditsId : input.budgetCategoryId,
    snapshotName: input.snapshotName,
  };
}

function systemCategoryFields() {
  return {
    accountId: accountPath().split("/")[1],
    name: otherClientChargesAndCreditsName,
    slug: "other-client-charges-and-credits",
    isSystem: true,
    metadata: {
      categoryType: "general",
      excludeFromOverallBudget: true,
    },
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function needsSystemCategory(lines: InvoiceLine[]) {
  return lines.some((line) => line.budgetCategoryId === otherClientChargesAndCreditsId);
}

function membership(lines: InvoiceLine[]) {
  const itemIds: string[] = [];
  const transactionIds: string[] = [];
  const seenItems = new Set<string>();
  const seenTx = new Set<string>();
  for (const line of lines) {
    if (line.sourceType === "item" && line.sourceId && !seenItems.has(line.sourceId)) {
      seenItems.add(line.sourceId);
      itemIds.push(line.sourceId);
    } else if (line.sourceType === "transaction" && line.sourceId && !seenTx.has(line.sourceId)) {
      seenTx.add(line.sourceId);
      transactionIds.push(line.sourceId);
    }
  }
  return { itemIds, transactionIds };
}

function totalCents(lines: InvoiceLine[]) {
  return lines.reduce((sum, line) => sum + line.amountCents * line.sign, 0);
}

function todayString() {
  return new Date().toISOString().slice(0, 10);
}

function canBillTransaction(tx: Transaction & { id: string }) {
  if (tx.status === "canceled") return false;
  if (tx.settlementInvoiceId) return false;
  if (tx.type === "PaymentToBusiness" || tx.type === "paymentToBusiness") return false;
  if (tx.itemIds?.length) return false;
  if (tx.reimbursementType === "owed-to-client" || tx.reimbursementType === "owed-to-company") return true;
  return tx.type === "Purchase" || tx.type === "purchase";
}

function lineForItem(item: Item & { id: string }): InvoiceLine {
  return {
    id: randomUUID(),
    sourceType: "item",
    sourceId: item.id,
    amountCents: item.projectPriceCents && item.projectPriceCents > 0 ? item.projectPriceCents : item.purchasePriceCents ?? 0,
    sign: 1,
    budgetCategoryId: item.budgetCategoryId,
    snapshotName: item.name ?? item.description,
  };
}

function lineForTransaction(tx: Transaction & { id: string }): InvoiceLine | null {
  if (!canBillTransaction(tx)) return null;
  const sign = tx.reimbursementType === "owed-to-client" ? -1 : 1;
  return {
    id: randomUUID(),
    sourceType: "transaction",
    sourceId: tx.id,
    amountCents: tx.amountCents ?? 0,
    sign,
    budgetCategoryId: tx.budgetCategoryId ?? undefined,
    snapshotName: tx.source ?? tx.notes,
  };
}

async function getFeeInstallment(
  db: Firestore,
  projectId: string,
  feeInstallmentId: string
): Promise<(FeeInstallment & { id: string }) | null> {
  const ref = accountCollection(db, "projects")
    .doc(projectId)
    .collection("feeInstallments")
    .doc(feeInstallmentId);
  const snap = await ref.get();
  if (!snap.exists) return null;
  return { ...(snap.data() as FeeInstallment), id: snap.id };
}

async function validateLines(db: Firestore, projectId: string, lines: InvoiceLine[]) {
  for (const line of lines) {
    if (line.sourceType === "manual") {
      if (line.sourceId) {
        return validation("Manual invoice lines cannot have sourceId.", "Use item, transaction, or feeInstallment when a source record exists.");
      }
      if (line.amountCents <= 0) {
        return validation("Manual invoice lines need a positive amount.", "Pass amountCents greater than zero and use sign -1 for a credit.");
      }
      if (!line.snapshotName?.trim()) {
        return validation("Manual invoice lines need a description.", "Pass snapshotName with the client-facing charge or credit description.");
      }
      line.budgetCategoryId = otherClientChargesAndCreditsId;
      continue;
    }
    if (!line.sourceId) {
      return validation("Sourced invoice lines require sourceId.", "Pass an item id, transaction id, or fee installment id for sourced invoice lines.");
    }
    if (line.sourceType === "item") {
      const item = await getDoc<Item>(db, "items", line.sourceId);
      if (!item) return notFound("Item", line.sourceId, "list_items");
      if (item.projectId !== projectId) {
        return validation(`Item ${line.sourceId} is not on project ${projectId}.`, "Invoice lines must belong to the same project as the invoice.");
      }
      line.budgetCategoryId = line.budgetCategoryId ?? item.budgetCategoryId;
      if (!line.budgetCategoryId) {
        return validation(`Item ${line.sourceId} is missing budgetCategoryId.`, "Repair the item category before invoicing it.");
      }
    }
    if (line.sourceType === "transaction") {
      const tx = await getDoc<Transaction>(db, "transactions", line.sourceId);
      if (!tx) return notFound("Transaction", line.sourceId, "list_transactions");
      if (tx.projectId !== projectId) {
        return validation(`Transaction ${line.sourceId} is not on project ${projectId}.`, "Invoice lines must belong to the same project as the invoice.");
      }
      line.budgetCategoryId = line.budgetCategoryId ?? tx.budgetCategoryId ?? undefined;
      if (!line.budgetCategoryId) {
        return validation(`Transaction ${line.sourceId} is missing budgetCategoryId.`, "Repair the transaction category before invoicing it.");
      }
    }
    if (line.sourceType === "feeInstallment") {
      const installment = await getFeeInstallment(db, projectId, line.sourceId);
      if (!installment) return notFound("FeeInstallment", line.sourceId, "get_invoice");
      if (installment.projectId && installment.projectId !== projectId) {
        return validation(`Fee installment ${line.sourceId} is not on project ${projectId}.`, "Invoice lines must belong to the same project as the invoice.");
      }
      line.amountCents = installment.amountCents;
      line.sign = 1;
      line.budgetCategoryId = installment.budgetCategoryId;
      line.snapshotName = line.snapshotName ?? installment.label;
      if (!line.budgetCategoryId) {
        return validation(`Fee installment ${line.sourceId} is missing budgetCategoryId.`, "Repair the fee installment category before invoicing it.");
      }
    }
  }
  return null;
}

function hasSettledLine(invoice: Invoice, selected: InvoiceLine[]) {
  const selectedIds = new Set(selected.map((line) => line.id).filter(Boolean));
  if (!selectedIds.size) return false;
  return (invoice.lines ?? []).some((line) =>
    line.id && selectedIds.has(line.id) && (line.settlementTransactionIds?.length ?? 0) > 0
  );
}

function selectedInvoiceLines(invoice: Invoice, settlementInvoiceLineIds?: string[]) {
  const lines = invoice.lines ?? [];
  if (!settlementInvoiceLineIds?.length) return lines;
  const lineSet = new Set(settlementInvoiceLineIds);
  return lines.filter((line) => line.id && lineSet.has(line.id));
}

function groupLinesByCategory(lines: InvoiceLine[]) {
  const groups = new Map<string, InvoiceLine[]>();
  for (const line of lines) {
    if (!line.budgetCategoryId) {
      return { error: validation(`Invoice line ${line.id ?? "(missing id)"} is missing budgetCategoryId.`, "Backfill invoice line categories before marking it collected.") };
    }
    const existing = groups.get(line.budgetCategoryId) ?? [];
    existing.push(line);
    groups.set(line.budgetCategoryId, existing);
  }
  return { groups };
}

async function writeGroupedPaymentTransactions(args: {
  db: Firestore;
  invoice: Invoice;
  invoiceId: string;
  source?: string;
  settlementInvoiceLineIds?: string[];
  userId?: string;
  markPaid: boolean;
}) {
  const { db, invoice, invoiceId, source, settlementInvoiceLineIds, userId, markPaid } = args;
  if (!invoice.projectId) return validation("Invoice is missing projectId.", "Repair the invoice before marking it collected.");
  const selected = selectedInvoiceLines(invoice, settlementInvoiceLineIds);
  if (settlementInvoiceLineIds?.length && selected.length !== settlementInvoiceLineIds.length) {
    return validation("One or more line IDs are not on this invoice.", "Call get_invoice and pass exact line ids.");
  }
  if (!selected.length) return validation("Invoice has no collectible lines.", "Send or backfill invoice lines before collection.");
  if (markPaid && selected.length !== (invoice.lines ?? []).length) {
    return validation(
      "Marking an invoice paid requires collecting all of its lines.",
      "Use mark_invoice_lines_collected for a partial payment, then mark the full invoice collected once every line is settled."
    );
  }
  if (hasSettledLine(invoice, selected)) {
    return validation(
      "One or more selected invoice lines already have settlement transactions.",
      "Do not collect the same invoice line twice. Inspect settlementTransactionIds or create a separate adjustment invoice if more money moved."
    );
  }

  const selectedLineIds = selected.map((line) => line.id).filter((id): id is string => Boolean(id));
  if (selectedLineIds.length) {
    const existingSettlements = await queryDocs<Transaction>(
      accountCollection(db, "transactions").where("settlementInvoiceId", "==", invoiceId)
    );
    const activeSettledLineIds = new Set(
      existingSettlements
        .filter((tx) => tx.status !== "canceled")
        .flatMap((tx) => tx.settlementInvoiceLineIds ?? [])
    );
    if (selectedLineIds.some((id) => activeSettledLineIds.has(id))) {
      return validation(
        "One or more selected invoice lines are already settled by an active payment transaction.",
        "Do not collect the same invoice line twice. Void the mistaken payment first or collect only unsettled lines."
      );
    }
  }

  const grouped = groupLinesByCategory(selected);
  if (grouped.error) return grouped.error;
  const selectedTotal = totalCents(selected);
  if (selectedTotal <= 0) {
    return validation(
      "Selected invoice lines do not represent money received from the client.",
      "Use collection only for positive client payments. Credit-only or net-negative invoices should be handled as client credits, not paymentToBusiness transactions."
    );
  }

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  if (needsSystemCategory(selected)) {
    batch.set(
      db.doc(`${accountPath()}/presets/default/budgetCategories/${otherClientChargesAndCreditsId}`),
      systemCategoryFields(),
      { merge: true }
    );
  }
  const transactionIds: string[] = [];
  const paymentSource = source ?? `Collected ${invoice.invoiceNumber || invoice.id || invoiceId}`;

  for (const [budgetCategoryId, lines] of Array.from(grouped.groups!.entries()).sort(([a], [b]) => a.localeCompare(b))) {
    const amountCents = totalCents(lines);
    if (amountCents <= 0) {
      return validation(
        "A settled budget category nets to zero or a client credit.",
        "Do not create paymentToBusiness transactions for non-positive category totals."
      );
    }
    const txId = randomUUID();
    transactionIds.push(txId);
    batch.set(accountCollection(db, "transactions").doc(txId), {
      projectId: invoice.projectId,
      budgetCategoryId,
      amountCents,
      type: "paymentToBusiness",
      source: paymentSource,
      transactionDate: todayString(),
      isComplete: true,
      settlementInvoiceId: invoiceId,
      settlementInvoiceLineIds: lines.map((line) => line.id).filter(Boolean),
      createdAt: now,
      updatedAt: now,
    });
  }

  if (!transactionIds.length) return validation("Collected invoice lines net to zero.", "Choose charge lines or handle zero-net credits outside collection.");

  batch.update(accountCollection(db, "invoices").doc(invoiceId), {
    ...(markPaid ? { status: "paid", datePaid: now } : {}),
    lines: (invoice.lines ?? []).map((line) => {
      if (!line.id || !selectedLineIds.includes(line.id)) return serializeLine(line);
      return serializeLine({ ...line, settlementTransactionIds: transactionIds });
    }),
    updatedAt: now,
    ...(userId ? { updatedBy: userId } : {}),
  });
  await batch.commit();

  return asToolResponse({
    invoiceId,
    status: markPaid ? "paid" : invoice.status,
    transactionIds,
    amountCents: selected.reduce((sum, line) => sum + line.amountCents * line.sign, 0),
    amount: formatCents(selected.reduce((sum, line) => sum + line.amountCents * line.sign, 0)),
    settledLineIds: selected.map((line) => line.id).filter(Boolean),
  });
}

export function registerInvoiceTools(server: McpServer, db: Firestore) {
  server.tool(
    "apply_contract_setup",
    "[mutating] Apply structured contract details to a project and optionally create a created invoice with invoice-only manual charges. Prefer FeeInstallments for planned fee schedules. This never creates payment transactions.",
    {
      projectId: z.string().optional().describe("Existing project to update. Omit to create a new project."),
      projectName: z.string().optional().describe("Project name for create or update."),
      clientName: z.string().optional(),
      description: z.string().optional(),
      notes: z.string().optional().describe("Contract summary or audit note to append/store."),
      designFeePayments: z.array(z.object({
        label: z.string().describe("Line label, e.g. Design Fee 1 of 3."),
        amountCents: z.coerce.number().int().nonnegative(),
      })).optional().describe("Invoice-only manual charges to place on a created invoice. Prefer FeeInstallment-backed lines for planned fee schedules."),
      invoiceNumber: z.string().optional(),
      userId: z.string().optional(),
    },
    withTelemetry("apply_contract_setup", async ({ projectId, projectName, clientName, description, notes, designFeePayments, invoiceNumber, userId }) => {
      const now = FieldValue.serverTimestamp();
      let targetProjectId = projectId;
      if (targetProjectId) {
        const project = await getDoc(db, "projects", targetProjectId);
        if (!project) return notFound("Project", targetProjectId, "list_projects");
        const update: Record<string, unknown> = { updatedAt: now };
        if (projectName !== undefined) update.name = projectName;
        if (clientName !== undefined) update.clientName = clientName;
        if (description !== undefined) update.description = description;
        if (Object.keys(update).length > 1) {
          await accountCollection(db, "projects").doc(targetProjectId).update(update);
        }
      } else {
        if (!projectName) return validation("projectName is required when projectId is omitted.", "Pass projectId to update an existing project, or projectName to create one.");
        const ref = accountCollection(db, "projects").doc(randomUUID());
        targetProjectId = ref.id;
        await ref.set({
          name: projectName,
          clientName: clientName ?? "",
          ...(description ? { description } : {}),
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        });
      }

      if (notes) {
        await db.collection(`${accountPath()}/projects/${targetProjectId}/notes`).add({
          text: notes,
          source: "mcp",
          createdBy: userId ?? "mcp-agent",
          createdByName: "AI Assistant",
          createdAt: new Date(),
        });
      }

      let invoiceId: string | null = null;
      if (designFeePayments?.length) {
        const lines: InvoiceLine[] = designFeePayments.map((payment: { label: string; amountCents: number }) => ({
          id: randomUUID(),
          sourceType: "manual",
          amountCents: payment.amountCents,
          sign: 1,
          budgetCategoryId: otherClientChargesAndCreditsId,
          snapshotName: payment.label,
        }));
        const ref = accountCollection(db, "invoices").doc(randomUUID());
        const data: Record<string, unknown> = {
          accountId: accountPath().split("/")[1],
          projectId: targetProjectId,
          status: "created",
          itemIds: [],
          transactionIds: [],
          lines: lines.map(serializeLine),
          dateIssued: now,
          createdAt: now,
          updatedAt: now,
        };
        if (invoiceNumber) data.invoiceNumber = invoiceNumber;
        if (notes) data.notes = notes;
        if (userId) {
          data.createdBy = userId;
          data.updatedBy = userId;
        }
        const batch = db.batch();
        batch.set(ref, data);
        batch.set(
          db.doc(`${accountPath()}/presets/default/budgetCategories/${otherClientChargesAndCreditsId}`),
          systemCategoryFields(),
          { merge: true }
        );
        await batch.commit();
        invoiceId = ref.id;
      }

      return asToolResponse({ projectId: targetProjectId, invoiceId, manualChargeCount: designFeePayments?.length ?? 0 });
    })
  );

  server.tool(
    "list_invoices",
    "[read-only] List project invoices. Invoices are demands for money, not records of money movement.",
    {
      projectId: z.string().optional().describe("Filter by project ID."),
      status: z.enum(["created", "sent", "paid", "canceled"]).optional().describe("Filter by canonical invoice lifecycle status."),
      limit: z.coerce.number().default(50),
      offset: z.coerce.number().default(0),
      mode: ProjectionMode,
      fields: z.array(z.string()).optional().describe("Optional explicit field list. Overrides mode."),
      responseLimit: ResponseLimitArg,
    },
    withTelemetry("list_invoices", async ({ projectId, status, limit, offset, mode, fields, responseLimit }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "invoices");
      if (projectId) query = query.where("projectId", "==", projectId);
      if (status) query = query.where("status", "==", normalizeInvoiceStatus(status));
      query = query.offset(offset).limit(limit);
      const invoices = await queryDocs<Invoice>(query);
      const projected = invoices.map((inv) => {
        if (fields?.length) return pickFields(inv as unknown as Record<string, unknown>, fields);
        return mode === "full" ? inv as unknown as Record<string, unknown> : invoiceSummary(inv) as unknown as Record<string, unknown>;
      });
      return asToolResponse(capResponse(projected, { limitBytes: responseLimit }));
    })
  );

  server.tool(
    "get_invoice",
    "[read-only] Get a single invoice demand, including its source lines and settlement links.",
    { invoiceId: z.string().describe("Invoice document ID.") },
    withTelemetry("get_invoice", async ({ invoiceId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      return asToolResponse(invoice);
    })
  );

  server.tool(
    "billable_pool",
    "[read-only] Return billable project sources not already claimed by a non-canceled invoice. Includes item lines, non-itemized transaction lines, and fee installment lines.",
    {
      projectId: z.string().describe("Project document ID."),
      responseLimit: ResponseLimitArg,
    },
    withTelemetry("billable_pool", async ({ projectId, responseLimit }) => {
      const [items, transactions, invoices, feeInstallments] = await Promise.all([
        queryDocs<Item>(accountCollection(db, "items").where("projectId", "==", projectId)),
        queryDocs<Transaction>(accountCollection(db, "transactions").where("projectId", "==", projectId)),
        queryDocs<Invoice>(accountCollection(db, "invoices").where("projectId", "==", projectId)),
        queryDocs<FeeInstallment>(accountCollection(db, "projects").doc(projectId).collection("feeInstallments")),
      ]);
      const claimedItems = new Set<string>();
      const claimedTx = new Set<string>();
      const claimedFeeInstallments = new Set<string>();
      for (const inv of invoices) {
        if (normalizeInvoiceStatus(inv.status) === "canceled") continue;
        for (const id of inv.itemIds ?? []) claimedItems.add(id);
        for (const id of inv.transactionIds ?? []) claimedTx.add(id);
        for (const line of inv.lines ?? []) {
          if (line.sourceType === "feeInstallment" && line.sourceId) claimedFeeInstallments.add(line.sourceId);
        }
      }
      const lines = [
        ...items
          .filter((item) => !claimedItems.has(item.id) && item.status !== "returned")
          .map(lineForItem),
        ...transactions
          .filter((tx) => !claimedTx.has(tx.id))
          .map(lineForTransaction)
          .filter((line): line is InvoiceLine => line !== null),
        ...feeInstallments
          .filter((installment) => !claimedFeeInstallments.has(installment.id))
          .map((installment) => ({
            id: randomUUID(),
            sourceType: "feeInstallment" as const,
            sourceId: installment.id,
            amountCents: installment.amountCents,
            sign: 1 as const,
            budgetCategoryId: installment.budgetCategoryId,
            snapshotName: installment.label,
          })),
      ];
      return asToolResponse(capResponse(lines, { limitBytes: responseLimit }));
    })
  );

  server.tool(
    "create_invoice",
    "[mutating] Create a created invoice demand. Lines may include item, transaction, feeInstallment, or invoice-only manual charges/credits. This does not create any transaction.",
    {
      projectId: z.string().describe("Project document ID."),
      lines: z.array(invoiceLineInput).min(1).describe("Invoice demand lines."),
      invoiceNumber: z.string().optional(),
      notes: z.string().optional(),
      userId: z.string().optional(),
    },
    withTelemetry("create_invoice", async ({ projectId, lines: inputLines, invoiceNumber, notes, userId }) => {
      const project = await getDoc(db, "projects", projectId);
      if (!project) return notFound("Project", projectId, "list_projects");
      const lines = inputLines.map(normalizeLine);
      const error = await validateLines(db, projectId, lines);
      if (error) return error;
      const { itemIds, transactionIds } = membership(lines);
      const now = FieldValue.serverTimestamp();
      const ref = accountCollection(db, "invoices").doc(randomUUID());
      const data: Record<string, unknown> = {
        accountId: accountPath().split("/")[1],
        projectId,
        status: "created",
        itemIds,
        transactionIds,
        lines: lines.map(serializeLine),
        dateIssued: now,
        createdAt: now,
        updatedAt: now,
      };
      if (invoiceNumber) data.invoiceNumber = invoiceNumber;
      if (notes) data.notes = notes;
      if (userId) {
        data.createdBy = userId;
        data.updatedBy = userId;
      }
      if (needsSystemCategory(lines)) {
        const batch = db.batch();
        batch.set(ref, data);
        batch.set(
          db.doc(`${accountPath()}/presets/default/budgetCategories/${otherClientChargesAndCreditsId}`),
          systemCategoryFields(),
          { merge: true }
        );
        await batch.commit();
      } else {
        await ref.set(data);
      }
      return asToolResponse({ invoiceId: ref.id, status: "created", totalCents: totalCents(lines), total: formatCents(totalCents(lines)) });
    })
  );

  server.tool(
    "add_invoice_line",
    "[mutating] Add one line to a created invoice. Use feeInstallment for planned fees; manual creates an invoice-only charge or credit. This does not create a transaction.",
    {
      invoiceId: z.string(),
      line: invoiceLineInput,
      userId: z.string().optional(),
    },
    withTelemetry("add_invoice_line", async ({ invoiceId, line: inputLine, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      if (normalizeInvoiceStatus(invoice.status) !== "created") return validation("Only created invoices can be edited.", "Cancel and recreate, or create a new adjustment invoice.");
      if (!invoice.projectId) return validation("Invoice is missing projectId.", "Repair the invoice before editing lines.");
      const nextLine = normalizeLine(inputLine);
      const error = await validateLines(db, invoice.projectId, [nextLine]);
      if (error) return error;
      const lines = [...(invoice.lines ?? []), nextLine];
      const { itemIds, transactionIds } = membership(lines);
      const update: Record<string, unknown> = {
        lines: lines.map(serializeLine),
        itemIds,
        transactionIds,
        totalCents: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (userId) update.updatedBy = userId;
      const invoiceRef = accountCollection(db, "invoices").doc(invoiceId);
      if (needsSystemCategory(lines)) {
        const batch = db.batch();
        batch.update(invoiceRef, update);
        batch.set(
          db.doc(`${accountPath()}/presets/default/budgetCategories/${otherClientChargesAndCreditsId}`),
          systemCategoryFields(),
          { merge: true }
        );
        await batch.commit();
      } else {
        await invoiceRef.update(update);
      }
      return asToolResponse({ invoiceId, lineId: nextLine.id, status: "created" });
    })
  );

  server.tool(
    "update_invoice_line",
    "[mutating] Replace or remove a line on a created invoice. Set remove: true to delete the line. This does not create a transaction.",
    {
      invoiceId: z.string(),
      lineId: z.string(),
      line: invoiceLineInput.optional(),
      remove: z.boolean().default(false),
      userId: z.string().optional(),
    },
    withTelemetry("update_invoice_line", async ({ invoiceId, lineId, line: inputLine, remove, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      if (normalizeInvoiceStatus(invoice.status) !== "created") return validation("Only created invoices can be edited.", "Cancel and recreate, or create a new adjustment invoice.");
      if (!invoice.projectId) return validation("Invoice is missing projectId.", "Repair the invoice before editing lines.");
      const lines = invoice.lines ?? [];
      const index = lines.findIndex((line) => line.id === lineId);
      if (index === -1) return notFound("InvoiceLine", lineId, "get_invoice");
      let nextLines: InvoiceLine[];
      if (remove) {
        nextLines = lines.filter((line) => line.id !== lineId);
      } else {
        if (!inputLine) return validation("line is required unless remove is true.", "Pass the replacement line or set remove: true.");
        const replacement = { ...normalizeLine(inputLine), id: lineId };
        const error = await validateLines(db, invoice.projectId, [replacement]);
        if (error) return error;
        nextLines = [...lines];
        nextLines[index] = replacement;
      }
      const { itemIds, transactionIds } = membership(nextLines);
      const update: Record<string, unknown> = {
        lines: nextLines.map(serializeLine),
        itemIds,
        transactionIds,
        totalCents: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (userId) update.updatedBy = userId;
      const invoiceRef = accountCollection(db, "invoices").doc(invoiceId);
      if (needsSystemCategory(nextLines)) {
        const batch = db.batch();
        batch.update(invoiceRef, update);
        batch.set(
          db.doc(`${accountPath()}/presets/default/budgetCategories/${otherClientChargesAndCreditsId}`),
          systemCategoryFields(),
          { merge: true }
        );
        await batch.commit();
      } else {
        await invoiceRef.update(update);
      }
      return asToolResponse({ invoiceId, status: "created", lineCount: nextLines.length });
    })
  );

  server.tool(
    "mark_invoice_sent",
    "[mutating] Mark a created invoice as sent and freeze its current lines and total. This is still only a demand for money; it does not create a transaction.",
    {
      invoiceId: z.string(),
      userId: z.string().optional(),
    },
    withTelemetry("mark_invoice_sent", async ({ invoiceId, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      if (normalizeInvoiceStatus(invoice.status) !== "created") return validation("Only created invoices can be marked sent.", "Use get_invoice to inspect the current status.");
      const lines = invoice.lines ?? [];
      const { itemIds, transactionIds } = membership(lines);
      const now = FieldValue.serverTimestamp();
      const update: Record<string, unknown> = {
        status: "sent",
        dateSent: now,
        totalCents: totalCents(lines),
        lines: lines.map(serializeLine),
        itemIds,
        transactionIds,
        updatedAt: now,
      };
      if (userId) update.updatedBy = userId;
      await accountCollection(db, "invoices").doc(invoiceId).update(update);
      return asToolResponse({ invoiceId, status: "sent", totalCents: update.totalCents, total: formatCents(update.totalCents as number) });
    })
  );

  server.tool(
    "void_invoice",
    "[mutating] Cancel an invoice demand. Existing settlement transactions are not deleted.",
    {
      invoiceId: z.string(),
      userId: z.string().optional(),
    },
    withTelemetry("void_invoice", async ({ invoiceId, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      const update: Record<string, unknown> = {
        status: "canceled",
        dateCanceled: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (userId) update.updatedBy = userId;
      await accountCollection(db, "invoices").doc(invoiceId).update(update);
      return asToolResponse({ invoiceId, status: "canceled" });
    })
  );

  server.tool(
    "mark_invoice_collected",
    "[mutating] Record collection for an invoice by creating categorized paymentToBusiness transaction(s) linked with settlementInvoiceId, then marking the invoice paid. Use for money actually received from the client.",
    {
      invoiceId: z.string(),
      source: z.string().optional().describe("Transaction source label. Defaults to Collected <invoice number/id>."),
      settlementInvoiceLineIds: z.array(z.string()).optional().describe("Optional subset of invoice line ids settled by this collection."),
      userId: z.string().optional(),
    },
    withTelemetry("mark_invoice_collected", async ({ invoiceId, source, settlementInvoiceLineIds, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      if (!invoice.projectId) return validation("Invoice is missing projectId.", "Repair the invoice before marking it collected.");
      if (normalizeInvoiceStatus(invoice.status) === "canceled") return validation("Canceled invoices cannot be collected.", "Create a new invoice demand if money is owed.");
      return writeGroupedPaymentTransactions({ db, invoice, invoiceId, source, settlementInvoiceLineIds, userId, markPaid: true });
    })
  );

  server.tool(
    "mark_invoice_lines_collected",
    "[mutating] Record real payment event(s) that settle selected invoice lines. Creates categorized paymentToBusiness transaction(s) linked to settlementInvoiceId and settlementInvoiceLineIds.",
    {
      invoiceId: z.string(),
      settlementInvoiceLineIds: z.array(z.string()).min(1),
      source: z.string().optional(),
      userId: z.string().optional(),
    },
    withTelemetry("mark_invoice_lines_collected", async ({ invoiceId, settlementInvoiceLineIds, source, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      if (!invoice.projectId) return validation("Invoice is missing projectId.", "Repair the invoice before marking it collected.");
      return writeGroupedPaymentTransactions({ db, invoice, invoiceId, source, settlementInvoiceLineIds, userId, markPaid: false });
    })
  );
}
