import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { Invoice, InvoiceLine, InvoiceLineSign, InvoiceLineSourceType, Item, Transaction } from "../types.js";
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

const invoiceLineInput = z.object({
  id: z.string().optional().describe("Stable invoice line id. Omit to generate one."),
  sourceType: z.enum(["item", "transaction", "manual"]).describe("Line source. Use manual for a New Charge."),
  sourceId: z.string().optional().describe("Item or transaction id. Omit for manual New Charge lines."),
  amountCents: z.coerce.number().int().nonnegative().describe("Positive line amount in cents."),
  sign: z.union([z.literal(1), z.literal(-1)]).default(1).describe("1 = charge, -1 = credit."),
  snapshotName: z.string().optional().describe("Frozen display name for the line."),
});

function serializeLine(line: InvoiceLine): Record<string, unknown> {
  return {
    id: line.id ?? randomUUID(),
    sourceType: line.sourceType,
    ...(line.sourceId ? { sourceId: line.sourceId } : {}),
    amountCents: line.amountCents,
    sign: line.sign,
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
    snapshotName: input.snapshotName,
  };
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
  if (tx.itemIds?.length) return false;
  if (tx.reimbursementType === "owed-to-client" || tx.reimbursementType === "owed-to-company") return true;
  return tx.type === "Fee" || tx.type === "Expense" || tx.type === "fee" || tx.type === "expense";
}

function lineForItem(item: Item & { id: string }): InvoiceLine {
  return {
    id: randomUUID(),
    sourceType: "item",
    sourceId: item.id,
    amountCents: item.projectPriceCents && item.projectPriceCents > 0 ? item.projectPriceCents : item.purchasePriceCents ?? 0,
    sign: 1,
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
    snapshotName: tx.source ?? tx.notes,
  };
}

async function validateLines(db: Firestore, projectId: string, lines: InvoiceLine[]) {
  for (const line of lines) {
    if (line.sourceType === "manual") continue;
    if (!line.sourceId) {
      return validation("Sourced invoice lines require sourceId.", "Pass an item id for item lines or transaction id for transaction lines.");
    }
    if (line.sourceType === "item") {
      const item = await getDoc<Item>(db, "items", line.sourceId);
      if (!item) return notFound("Item", line.sourceId, "list_items");
      if (item.projectId !== projectId) {
        return validation(`Item ${line.sourceId} is not on project ${projectId}.`, "Invoice lines must belong to the same project as the invoice.");
      }
    }
    if (line.sourceType === "transaction") {
      const tx = await getDoc<Transaction>(db, "transactions", line.sourceId);
      if (!tx) return notFound("Transaction", line.sourceId, "list_transactions");
      if (tx.projectId !== projectId) {
        return validation(`Transaction ${line.sourceId} is not on project ${projectId}.`, "Invoice lines must belong to the same project as the invoice.");
      }
    }
  }
  return null;
}

export function registerInvoiceTools(server: McpServer, db: Firestore) {
  server.tool(
    "apply_contract_setup",
    "[mutating] Apply structured contract details to a project and optionally create a draft invoice with manual New Charge design-fee lines. The agent should parse the contract text, then pass explicit fields here. This never creates payment transactions.",
    {
      projectId: z.string().optional().describe("Existing project to update. Omit to create a new project."),
      projectName: z.string().optional().describe("Project name for create or update."),
      clientName: z.string().optional(),
      description: z.string().optional(),
      notes: z.string().optional().describe("Contract summary or audit note to append/store."),
      designFeePayments: z.array(z.object({
        label: z.string().describe("Line label, e.g. Design Fee 1 of 3."),
        amountCents: z.coerce.number().int().nonnegative(),
      })).optional().describe("Manual New Charge lines to place on a draft invoice."),
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
          snapshotName: payment.label,
        }));
        const ref = accountCollection(db, "invoices").doc(randomUUID());
        const data: Record<string, unknown> = {
          accountId: accountPath().split("/")[1],
          projectId: targetProjectId,
          status: "draft",
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
        await ref.set(data);
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
      status: z.enum(["draft", "sent", "paid", "voided"]).optional().describe("Filter by invoice lifecycle status."),
      limit: z.coerce.number().default(50),
      offset: z.coerce.number().default(0),
      mode: ProjectionMode,
      fields: z.array(z.string()).optional().describe("Optional explicit field list. Overrides mode."),
      responseLimit: ResponseLimitArg,
    },
    withTelemetry("list_invoices", async ({ projectId, status, limit, offset, mode, fields, responseLimit }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "invoices");
      if (projectId) query = query.where("projectId", "==", projectId);
      if (status) query = query.where("status", "==", status);
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
    "[read-only] Return billable project sources not already claimed by a non-void invoice. Includes item lines and non-itemized transaction lines; manual New Charge lines can always be added during invoice creation.",
    {
      projectId: z.string().describe("Project document ID."),
      responseLimit: ResponseLimitArg,
    },
    withTelemetry("billable_pool", async ({ projectId, responseLimit }) => {
      const [items, transactions, invoices] = await Promise.all([
        queryDocs<Item>(accountCollection(db, "items").where("projectId", "==", projectId)),
        queryDocs<Transaction>(accountCollection(db, "transactions").where("projectId", "==", projectId)),
        queryDocs<Invoice>(accountCollection(db, "invoices").where("projectId", "==", projectId)),
      ]);
      const claimedItems = new Set<string>();
      const claimedTx = new Set<string>();
      for (const inv of invoices) {
        if (inv.status === "voided") continue;
        for (const id of inv.itemIds ?? []) claimedItems.add(id);
        for (const id of inv.transactionIds ?? []) claimedTx.add(id);
      }
      const lines = [
        ...items
          .filter((item) => !claimedItems.has(item.id) && item.status !== "returned")
          .map(lineForItem),
        ...transactions
          .filter((tx) => !claimedTx.has(tx.id))
          .map(lineForTransaction)
          .filter((line): line is InvoiceLine => line !== null),
      ];
      return asToolResponse(capResponse(lines, { limitBytes: responseLimit }));
    })
  );

  server.tool(
    "create_invoice",
    "[mutating] Create a draft invoice demand. Lines may include existing item/transaction sources and manual New Charge lines. This does not create any transaction.",
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
        status: "draft",
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
      await ref.set(data);
      return asToolResponse({ invoiceId: ref.id, status: "draft", totalCents: totalCents(lines), total: formatCents(totalCents(lines)) });
    })
  );

  server.tool(
    "add_invoice_line",
    "[mutating] Add one line to a draft invoice. Use sourceType manual for a user-facing New Charge. This does not create a transaction.",
    {
      invoiceId: z.string(),
      line: invoiceLineInput,
      userId: z.string().optional(),
    },
    withTelemetry("add_invoice_line", async ({ invoiceId, line: inputLine, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      if (invoice.status !== "draft") return validation("Only draft invoices can be edited.", "Void and recreate, or create a new adjustment invoice.");
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
      await accountCollection(db, "invoices").doc(invoiceId).update(update);
      return asToolResponse({ invoiceId, lineId: nextLine.id, status: "draft" });
    })
  );

  server.tool(
    "update_invoice_line",
    "[mutating] Replace or remove a line on a draft invoice. Set remove: true to delete the line. This does not create a transaction.",
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
      if (invoice.status !== "draft") return validation("Only draft invoices can be edited.", "Void and recreate, or create a new adjustment invoice.");
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
      await accountCollection(db, "invoices").doc(invoiceId).update(update);
      return asToolResponse({ invoiceId, status: "draft", lineCount: nextLines.length });
    })
  );

  server.tool(
    "mark_invoice_sent",
    "[mutating] Mark a draft invoice as sent and freeze its current lines and total. This is still only a demand for money; it does not create a transaction.",
    {
      invoiceId: z.string(),
      userId: z.string().optional(),
    },
    withTelemetry("mark_invoice_sent", async ({ invoiceId, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      if (invoice.status !== "draft") return validation("Only draft invoices can be marked sent.", "Use get_invoice to inspect the current status.");
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
    "[mutating] Void an invoice demand. Existing settlement transactions are not deleted.",
    {
      invoiceId: z.string(),
      userId: z.string().optional(),
    },
    withTelemetry("void_invoice", async ({ invoiceId, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      const update: Record<string, unknown> = {
        status: "voided",
        dateVoided: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (userId) update.updatedBy = userId;
      await accountCollection(db, "invoices").doc(invoiceId).update(update);
      return asToolResponse({ invoiceId, status: "voided" });
    })
  );

  server.tool(
    "mark_invoice_collected",
    "[mutating] Record collection for an invoice by creating one normal Fee transaction linked with settlementInvoiceId, then marking the invoice paid. Use for money actually received from the client.",
    {
      invoiceId: z.string(),
      amountCents: z.coerce.number().int().positive().optional().describe("Collected amount. Defaults to positive invoice net total."),
      source: z.string().optional().describe("Transaction source label. Defaults to Collected <invoice number/id>."),
      budgetCategoryId: z.string().optional().describe("Optional fee budget category id."),
      settlementInvoiceLineIds: z.array(z.string()).optional().describe("Optional subset of invoice line ids settled by this transaction."),
      userId: z.string().optional(),
    },
    withTelemetry("mark_invoice_collected", async ({ invoiceId, amountCents, source, budgetCategoryId, settlementInvoiceLineIds, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      if (!invoice.projectId) return validation("Invoice is missing projectId.", "Repair the invoice before marking it collected.");
      if (invoice.status === "voided") return validation("Voided invoices cannot be collected.", "Create a new invoice demand if money is owed.");
      const computedTotal = invoice.totalCents ?? totalCents(invoice.lines ?? []);
      const collectedCents = amountCents ?? Math.max(computedTotal, 0);
      if (collectedCents <= 0) return validation("Collected amount must be positive.", "Pass amountCents for a partial or adjusted collection.");
      const txId = randomUUID();
      const now = FieldValue.serverTimestamp();
      const txData: Record<string, unknown> = {
        projectId: invoice.projectId,
        amountCents: collectedCents,
        type: "Fee",
        source: source ?? `Collected ${invoice.invoiceNumber || invoice.id}`,
        transactionDate: todayString(),
        isComplete: true,
        settlementInvoiceId: invoiceId,
        createdAt: now,
        updatedAt: now,
      };
      if (budgetCategoryId) txData.budgetCategoryId = budgetCategoryId;
      if (settlementInvoiceLineIds?.length) txData.settlementInvoiceLineIds = settlementInvoiceLineIds;
      const invoiceUpdate: Record<string, unknown> = {
        status: "paid",
        datePaid: now,
        updatedAt: now,
      };
      if (userId) invoiceUpdate.updatedBy = userId;
      const batch = db.batch();
      batch.set(accountCollection(db, "transactions").doc(txId), txData);
      batch.update(accountCollection(db, "invoices").doc(invoiceId), invoiceUpdate);
      await batch.commit();
      return asToolResponse({ invoiceId, status: "paid", transactionId: txId, amountCents: collectedCents, amount: formatCents(collectedCents) });
    })
  );

  server.tool(
    "mark_invoice_lines_collected",
    "[mutating] Record one real payment event that settles selected invoice lines. Creates one normal Fee transaction linked to settlementInvoiceId and settlementInvoiceLineIds.",
    {
      invoiceId: z.string(),
      settlementInvoiceLineIds: z.array(z.string()).min(1),
      amountCents: z.coerce.number().int().positive().optional().describe("Collected amount. Defaults to the selected line net total when available."),
      source: z.string().optional(),
      budgetCategoryId: z.string().optional(),
      userId: z.string().optional(),
    },
    withTelemetry("mark_invoice_lines_collected", async ({ invoiceId, settlementInvoiceLineIds, amountCents, source, budgetCategoryId, userId }) => {
      const invoice = await getDoc<Invoice>(db, "invoices", invoiceId);
      if (!invoice) return notFound("Invoice", invoiceId, "list_invoices");
      if (!invoice.projectId) return validation("Invoice is missing projectId.", "Repair the invoice before marking it collected.");
      const lineSet = new Set(settlementInvoiceLineIds);
      const selected = (invoice.lines ?? []).filter((line) => line.id && lineSet.has(line.id));
      if (selected.length !== settlementInvoiceLineIds.length) {
        return validation("One or more line IDs are not on this invoice.", "Call get_invoice and pass exact line ids.");
      }
      const selectedTotal = Math.max(totalCents(selected), 0);
      const collectedCents = amountCents ?? selectedTotal;
      if (collectedCents <= 0) return validation("Collected amount must be positive.", "Pass amountCents for a partial or adjusted collection.");
      const txId = randomUUID();
      const now = FieldValue.serverTimestamp();
      const batch = db.batch();
      batch.set(accountCollection(db, "transactions").doc(txId), {
        projectId: invoice.projectId,
        amountCents: collectedCents,
        type: "Fee",
        source: source ?? `Collected ${invoice.invoiceNumber || invoice.id}`,
        transactionDate: todayString(),
        isComplete: true,
        settlementInvoiceId: invoiceId,
        settlementInvoiceLineIds,
        ...(budgetCategoryId ? { budgetCategoryId } : {}),
        createdAt: now,
        updatedAt: now,
      });
      batch.update(accountCollection(db, "invoices").doc(invoiceId), {
        updatedAt: now,
        ...(userId ? { updatedBy: userId } : {}),
      });
      await batch.commit();
      return asToolResponse({ invoiceId, transactionId: txId, amountCents: collectedCents, amount: formatCents(collectedCents), settledLineIds: settlementInvoiceLineIds });
    })
  );
}
