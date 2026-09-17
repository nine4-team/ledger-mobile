import { z } from "zod";
import { validateTransactionReceiptLinesEditResult, type TransactionReceiptLinesEditRequest,
  type TransactionReceiptLinesEditServing } from "./transactionReceiptLinesEdit.js";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { credential, validateReportConfiguration } from "./propertyManagementReportRead.js";
import { receiptSchema, transactionReceiptAudit } from "./transactionReceiptRead.js";
import { paymentContentsSchema, validatePaymentContents } from "./transactionPaymentContents.js";
import { attachmentResponseJSON, transactionAttachmentInputSchema, transactionAttachmentPage,
  type TransactionAttachmentInput, type TransactionAttachmentPage } from "./transactionAttachmentRead.js";
import { validateTransactionDetailsEditResult, type TransactionDetailsEditRequest,
  type TransactionDetailsEditServing } from "./transactionDetailsEdit.js";

const integer = z.string().regex(/^-?(0|[1-9][0-9]*)$/).refine(v => v !== "-0"
  && BigInt(v) >= -9223372036854775808n && BigInt(v) <= 9223372036854775807n);
const positive = integer.refine(v => BigInt(v) > 0n);
const identifier = z.string().refine(v => {
  try { validateIdentifier(v, "invalid"); return true; } catch { return false; }
});
const calendarDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(v => {
  const [year, month, day] = v.split("-").map(Number);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  return year >= 1 && year <= 9999 && month >= 1 && month <= 12 && day >= 1
    && day <= [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
});
const detailSchema = z.object({
  accountId: identifier, principalId: identifier, transactionId: identifier,
  scopeKind: z.enum(["project", "business_inventory"]), projectId: identifier.nullable(), clientId: identifier.nullable(),
  type: z.enum(["purchase", "return"]), role: z.literal("standalone"),
  origin: z.enum(["firebase_client_payment", "vendor_payment"]),
  amountMinorUnits: positive, currency: z.string().regex(/^[A-Z]{3}$/),
  category: z.object({ id: identifier, name: z.string().refine(v => v.trim().length > 0),
    kind: z.enum(["general", "itemized", "fee"]), revision: positive }).strict().nullable(),
  source: z.string().nullable(), transactionDate: calendarDate.nullable(),
  createdAtMilliseconds: integer.nullable(), notes: z.string().nullable(),
  paymentMethod: z.string().nullable(), hasEmailReceipt: z.boolean().nullable(),
  detailsRevision: positive.refine(v => BigInt(v).toString() === v).nullable().optional(),
  legacySubtotalMinorUnits: integer.nullable().optional(),
  legacyTaxRatePct: z.string().regex(/^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/)
    .refine(v => !v.includes("\n") && !v.includes("\r")).nullable().optional(),
  receipt: receiptSchema.nullable().optional(),
  paymentContents: paymentContentsSchema.nullable().optional(),
  currentItemCategories: z.array(z.object({ itemId: identifier, placementId: identifier,
    categoryId: identifier.nullable() }).strict()).nullable().optional(),
}).strict();

/** Display evidence only: no receipt completeness or mutation permission inferred. */
export function transactionDetail(value: unknown, transactionId: string, context: TargetMCPRequestContext) {
  try {
    const detail = detailSchema.parse(value);
    if (detail.accountId !== context.accountId || detail.principalId !== context.principalId
      || detail.transactionId !== transactionId
      || (detail.scopeKind === "project" ? detail.projectId === null || detail.clientId === null
        : detail.projectId !== null || detail.clientId !== null)
      || (detail.origin === "vendor_payment" ? detail.category === null
        : detail.category !== null || detail.type !== "purchase" || detail.scopeKind !== "project")) {
      throw new Error("invalid evidence");
    }
    if (detail.currentItemCategories) {
      const items = detail.currentItemCategories;
      if ((detail.scopeKind !== "project" && items.length !== 0)
        || new Set(items.map(v => v.itemId)).size !== items.length
        || new Set(items.map(v => v.placementId)).size !== items.length) throw new Error("invalid current Item attribution");
    }
    if (detail.paymentContents) {
      if (detail.origin !== "firebase_client_payment") throw new Error("vendor receipt cannot contain client payment history");
      validatePaymentContents(detail.paymentContents, detail);
    }
    if (detail.receipt) {
      const receipt = transactionReceiptAudit(detail.receipt, transactionId, context);
      if (detail.origin !== "vendor_payment" || receipt.scopeKind !== detail.scopeKind
        || receipt.projectId !== detail.projectId || receipt.clientId !== detail.clientId
        || receipt.type !== detail.type || receipt.amountMinorUnits !== detail.amountMinorUnits || receipt.currency !== detail.currency
        || receipt.category.id !== detail.category?.id || receipt.category.name !== detail.category.name
        || receipt.category.kind !== detail.category.kind || receipt.category.revision !== detail.category.revision) throw new Error("receipt mismatch");
    }
    return detail;
  } catch { throw new TargetMCPFailure("transaction_detail_server_result_mismatch"); }
}
export type TransactionDetail = ReturnType<typeof transactionDetail>;
export const transactionListInputSchema = z.discriminatedUnion("scopeKind", [
  z.object({ scopeKind: z.literal("project"), projectId: identifier }).strict(),
  z.object({ scopeKind: z.literal("business_inventory") }).strict(),
]);
export type TransactionListInput = z.infer<typeof transactionListInputSchema>;
const listSchema = z.object({ accountId: identifier, principalId: identifier,
  scopeKind: z.enum(["project", "business_inventory"]), projectId: identifier.nullable(), clientId: identifier.nullable(),
  coverage: z.literal("partial"), transactions: z.array(detailSchema) }).strict();

export function transactionList(value: unknown, input: TransactionListInput, context: TargetMCPRequestContext) {
  try {
    const result = listSchema.parse(value);
    const projectId = input.scopeKind === "project" ? input.projectId : null;
    if (result.accountId !== context.accountId || result.principalId !== context.principalId
      || result.scopeKind !== input.scopeKind || result.projectId !== projectId
      || (input.scopeKind === "project" ? result.clientId === null : result.clientId !== null)) throw new Error("scope");
    const seen = new Set<string>();
    for (const raw of result.transactions) {
      const row = transactionDetail(raw, raw.transactionId, context);
      if (seen.has(row.transactionId) || row.scopeKind !== result.scopeKind
        || row.projectId !== result.projectId || row.clientId !== result.clientId) throw new Error("row scope");
      seen.add(row.transactionId);
    }
    return result;
  } catch { throw new TargetMCPFailure("transaction_list_server_result_mismatch"); }
}
export type TransactionList = ReturnType<typeof transactionList>;
export interface TransactionDetailReading {
  read(input: Readonly<{ transactionId: string }>, context: TargetMCPRequestContext): Promise<TransactionDetail>;
  list?(input: TransactionListInput, context: TargetMCPRequestContext): Promise<TransactionList>;
  attachments?(input: TransactionAttachmentInput, context: TargetMCPRequestContext): Promise<TransactionAttachmentPage>;
}

export class SupabaseTransactionDetailReader implements TransactionDetailReading, TransactionDetailsEditServing, TransactionReceiptLinesEditServing {
  readonly #url: URL;
  constructor(url: URL, private readonly key: string, private readonly fetcher: typeof fetch = fetch) {
    validateReportConfiguration(url, key, "transaction_detail_configuration_invalid");
    this.#url = new URL("/rest/v1/rpc/spike_read_transaction_detail", url);
  }
  async applyTransactionDetailsEdit(request: TransactionDetailsEditRequest, context: TargetMCPRequestContext): Promise<unknown> {
    const result = await this.applyTransactionEdit("spike_edit_transaction_details", request, context);
    validateTransactionDetailsEditResult(result, request);
    return result;
  }
  async applyTransactionReceiptLinesEdit(request: TransactionReceiptLinesEditRequest, context: TargetMCPRequestContext): Promise<unknown> {
    const result = await this.applyTransactionEdit("spike_edit_transaction_receipt_lines", request, context);
    validateTransactionReceiptLinesEditResult(result, request);
    return result;
  }
  private async applyTransactionEdit(endpoint: "spike_edit_transaction_details" | "spike_edit_transaction_receipt_lines",
    request: TransactionDetailsEditRequest, context: TargetMCPRequestContext): Promise<unknown> {
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) {
      throw new TargetMCPFailure("account_not_authorized");
    }
    if (!credential(context.accessToken, "authenticated")) throw new TargetMCPFailure("authentication_required");
    let response: Response;
    try {
      response = await this.fetcher(new URL(endpoint, this.#url), {
        method: "POST", redirect: "error", signal: AbortSignal.timeout(30_000),
        headers: { apikey: this.key, Authorization: `Bearer ${context.accessToken}`, Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify({ p_command: request.commandJSON }),
      });
    } catch { throw new TargetMCPFailure("transaction_edit_transport_failed"); }
    if (!response.ok) throw new TargetMCPFailure(response.status === 401 ? "authentication_required"
      : response.status === 403 ? "transaction_edit_unavailable" : "transaction_edit_request_failed", response.status);
    let result: unknown;
    try { result = await response.json(); } catch { throw new TargetMCPFailure("transaction_edit_result_mismatch"); }
    return result;
  }
  async attachments(input: TransactionAttachmentInput, context: TargetMCPRequestContext): Promise<TransactionAttachmentPage> {
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const request = transactionAttachmentInputSchema.safeParse(input);
    if (!request.success) throw new TargetMCPFailure("transaction_attachment_page_invalid");
    if (!credential(context.accessToken, "authenticated")) throw new TargetMCPFailure("authentication_required");
    let response: Response;
    try {
      response = await this.fetcher(new URL("spike_read_transaction_attachments", this.#url), {
        method: "POST", redirect: "error", signal: AbortSignal.timeout(30_000),
        headers: { apikey: this.key, Authorization: `Bearer ${context.accessToken}`, Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify({ p_account_id: context.accountId, p_transaction_id: request.data.transactionId,
          p_section: request.data.section, p_start_position: request.data.startPosition,
          p_limit: request.data.limit, p_revision: request.data.revision ?? null }),
      });
    } catch { throw new TargetMCPFailure("transaction_attachment_transport_failed"); }
    if (!response.ok) throw new TargetMCPFailure(response.status === 401 ? "authentication_required"
      : response.status === 403 ? "transaction_not_available"
      : response.status === 409 ? "transaction_attachment_revision_changed"
      : "transaction_attachment_read_failed", response.status);
    try { return transactionAttachmentPage(await attachmentResponseJSON(response), input, context); }
    catch (error) {
      if (error instanceof TargetMCPFailure) throw error;
      throw new TargetMCPFailure("transaction_attachment_server_result_mismatch");
    }
  }
  async list(input: TransactionListInput, context: TargetMCPRequestContext): Promise<TransactionList> {
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const scope = transactionListInputSchema.safeParse(input);
    if (!scope.success) throw new TargetMCPFailure("transaction_scope_invalid");
    if (!credential(context.accessToken, "authenticated")) throw new TargetMCPFailure("authentication_required");
    let response: Response;
    try {
      response = await this.fetcher(new URL("spike_read_transaction_list", this.#url), {
        method: "POST", redirect: "error", signal: AbortSignal.timeout(30_000),
        headers: { apikey: this.key, Authorization: `Bearer ${context.accessToken}`, Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify({ p_account_id: context.accountId, p_scope_kind: scope.data.scopeKind,
          p_project_id: scope.data.scopeKind === "project" ? scope.data.projectId : null }),
      });
    } catch { throw new TargetMCPFailure("transaction_list_transport_failed"); }
    if (!response.ok) throw new TargetMCPFailure(response.status === 401 ? "authentication_required"
      : response.status === 403 ? "transaction_scope_not_available" : "transaction_list_read_failed", response.status);
    try { return transactionList(await response.json(), scope.data, context); }
    catch { throw new TargetMCPFailure("transaction_list_server_result_mismatch"); }
  }
  async read(input: Readonly<{ transactionId: string }>, context: TargetMCPRequestContext): Promise<TransactionDetail> {
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    validateIdentifier(input.transactionId, "transaction_detail_invalid_identifier");
    if (!credential(context.accessToken, "authenticated")) throw new TargetMCPFailure("authentication_required");
    let response: Response;
    try {
      response = await this.fetcher(this.#url, { method: "POST", redirect: "error", signal: AbortSignal.timeout(30_000),
        headers: { apikey: this.key, Authorization: `Bearer ${context.accessToken}`, Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify({ p_account_id: context.accountId, p_transaction_id: input.transactionId }) });
    } catch { throw new TargetMCPFailure("transaction_detail_transport_failed"); }
    if (!response.ok) throw new TargetMCPFailure(response.status === 401 ? "authentication_required"
      : response.status === 403 ? "transaction_not_available" : "transaction_detail_read_failed", response.status);
    try { return transactionDetail(await response.json(), input.transactionId, context); }
    catch { throw new TargetMCPFailure("transaction_detail_server_result_mismatch"); }
  }
}
