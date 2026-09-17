import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";
import { invoiceSchema, validateFrozenInvoice } from "./transactionPaymentContents.js";

const fail = (code = "expense_payload_invalid"): never => { throw new TargetMCPFailure(code); };
const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "expense_payload_invalid"); return true; } catch { return false; }
});
const integer = z.string().refine(value => /^(0|-?[1-9][0-9]*)$/.test(value)
  && value.length <= 20 && BigInt(value) >= -9223372036854775808n && BigInt(value) <= 9223372036854775807n);
const currency = z.string().regex(/^[A-Z]{3}$/);
const date = z.string().refine(value => {
  if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value) || value.startsWith("0000")) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
});
export const receiptLineInputSchema = z.object({ id: identifier, description: z.string().refine(value => value.trim().length > 0),
  magnitudeMinorUnits: integer.refine(value => /^[1-9][0-9]*$/.test(value)), currency,
  effect: z.enum(["increase", "decrease"]), quantity: integer.nullable() }).strict();
const payloadSchema = z.object({ projectId: identifier, expenseId: identifier, vendor: z.string(), date,
  amountMinorUnits: integer, currency, categoryId: identifier, notes: z.string(),
  receiptLines: z.array(receiptLineInputSchema), receiptAttachmentIds: z.array(identifier) }).strict();
const validReferences = (value: z.infer<typeof payloadSchema>) =>
  new Set(value.receiptAttachmentIds).size === value.receiptAttachmentIds.length
  && new Set(value.receiptLines.map(row => row.id)).size === value.receiptLines.length
  && value.receiptLines.every(row => row.currency === value.currency);
export const expenseCreationInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: payloadSchema.refine(validReferences),
}).strict();
export const expenseReadInputSchema = z.object({ projectId: identifier, expenseId: identifier }).strict();
export const expenseListInputSchema = expenseReadInputSchema.pick({ projectId: true });
export type ExpenseListInput = z.infer<typeof expenseListInputSchema>;
export const expenseEditInputSchema = expenseCreationInputSchema.extend({
  expectedRevision: integer.refine(value => /^[1-9][0-9]*$/.test(value) && BigInt(value) < 9223372036854775807n),
}).strict();
export type ExpenseEditInput = z.input<typeof expenseEditInputSchema>;
export type ExpenseReadInput = z.infer<typeof expenseReadInputSchema>;
export const expenseReceiptInputSchema = expenseReadInputSchema.extend({ attachmentId: identifier }).strict();
export type ExpenseReceiptInput = z.infer<typeof expenseReceiptInputSchema>;
const snapshotSchema = payloadSchema.extend({ accountId: identifier,
  revision: integer.refine(value => /^[1-9][0-9]*$/.test(value)) }).strict().refine(validReferences);
export type ExpenseSnapshot = z.infer<typeof snapshotSchema>;
export interface ExpenseReading {
  list?(input: ExpenseListInput, context: TargetMCPRequestContext): Promise<ExpenseSnapshot[]>;
  read(input: ExpenseReadInput, context: TargetMCPRequestContext): Promise<ExpenseSnapshot>;
  receipt?(input: ExpenseReceiptInput, context: TargetMCPRequestContext): Promise<{ mimeType: string; bytes: Uint8Array }>;
  invoice?(input: ExpenseReadInput, context: TargetMCPRequestContext): Promise<ExpenseInvoiceSnapshot>;
}
const expenseInvoiceSchema = z.object({ expense: snapshotSchema, invoice: invoiceSchema.nullable() }).strict();
export type ExpenseInvoiceSnapshot = z.infer<typeof expenseInvoiceSchema>;
export function validateExpenseInvoice(value: unknown, input: ExpenseReadInput, context: TargetMCPRequestContext): ExpenseInvoiceSnapshot {
  const parsed = expenseInvoiceSchema.safeParse(value);
  if (!parsed.success) return fail("expense_server_result_mismatch");
  const result = parsed.data, expense = validateExpenseSnapshot(result.expense,input,context), invoice = result.invoice;
  if (invoice) {
    try {
      validateFrozenInvoice(invoice,{accountId:context.accountId,projectId:input.projectId,
        clientId:invoice.client_id,transactionId:invoice.purchase_id,currency:expense.currency});
      const lines = invoice.lines.filter(line => line.source_kind === "expense" && line.source_id === input.expenseId);
      if (lines.length !== 1 || lines[0].source_revision !== expense.revision
        || lines[0].signed_amount_minor_units !== expense.amountMinorUnits) throw new Error("source mismatch");
    } catch { return fail("expense_server_result_mismatch"); }
  }
  return result;
}
export function validateExpenseSnapshot(value: unknown, input: ExpenseReadInput, context: TargetMCPRequestContext): ExpenseSnapshot {
  const request = expenseReadInputSchema.safeParse(input), snapshot = snapshotSchema.safeParse(value);
  if (!request.success || !snapshot.success || snapshot.data.accountId !== context.accountId
    || snapshot.data.projectId !== request.data.projectId || snapshot.data.expenseId !== request.data.expenseId) {
    return fail("expense_server_result_mismatch");
  }
  return snapshot.data;
}
export function validateExpenseList(value: unknown, input: ExpenseListInput, context: TargetMCPRequestContext): ExpenseSnapshot[] {
  const request = expenseListInputSchema.safeParse(input), rows = z.array(snapshotSchema).safeParse(value);
  if (!request.success || !rows.success) return fail("expense_server_result_mismatch");
  if (new Set(rows.data.map(row => row.expenseId)).size !== rows.data.length) return fail("expense_server_result_mismatch");
  return rows.data.map(row => validateExpenseSnapshot(row,
    { projectId: request.data.projectId, expenseId: row.expenseId }, context));
}
export type ExpenseCreationInput = z.input<typeof expenseCreationInputSchema>;
export type ExpenseCreationRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  expenseId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface ExpenseCreationServing {
  apply(request: ExpenseCreationRequest, context: TargetMCPRequestContext): Promise<unknown>;
  edit?(request: ExpenseCreationRequest, context: TargetMCPRequestContext): Promise<unknown>;
}
export function makeExpenseEditRequest(input: ExpenseEditInput, context: TargetMCPRequestContext): ExpenseCreationRequest {
  const parsed = expenseEditInputSchema.safeParse(input);
  if (!parsed.success) return fail();
  const { expectedRevision, ...creation } = parsed.data;
  const base = makeExpenseCreationRequest(creation, context);
  const operationId = base.operationId.replace(/^expense-create-/, "expense-edit-");
  const commandJSON = canonicalJSON({ ...creation.payload, operationId, accountId: base.accountId,
    actorPrincipalId: base.actorPrincipalId, contractVersion: "expense-edit-v1",
    createdAtMs: String(base.createdAtMs), expectedRevision }, "expense_payload_invalid");
  return { ...base, operationId, commandJSON, fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
export function makeExpenseCreationRequest(input: ExpenseCreationInput, context: TargetMCPRequestContext): ExpenseCreationRequest {
  const parsed = expenseCreationInputSchema.safeParse(input);
  if (!parsed.success) return fail();
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = `expense-create-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`;
  const commandJSON = canonicalJSON({ ...parsed.data.payload, operationId, accountId, actorPrincipalId,
    contractVersion: "expense-create-v1", createdAtMs: String(parsed.data.clientCreatedAtMilliseconds) }, "expense_payload_invalid");
  return { operationId, accountId, actorPrincipalId, expenseId: parsed.data.payload.expenseId,
    createdAtMs: parsed.data.clientCreatedAtMilliseconds, commandJSON,
    fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
const rejections = new Set(["expense_project_unavailable", "expense_category_unavailable",
  "expense_receipt_invalid", "expense_integrity_conflict"]);
export function validateExpenseCreationResult(value: unknown, request: ExpenseCreationRequest) {
  return validateExpenseResult(value, request, false);
}
export function validateExpenseEditResult(value: unknown, request: ExpenseCreationRequest) {
  return validateExpenseResult(value, request, true);
}
function validateExpenseResult(value: unknown, request: ExpenseCreationRequest, edit: boolean) {
  const mismatch = () => fail("expense_server_result_mismatch");
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const row = value as Record<string, unknown>;
  if (row.operation_id !== request.operationId || row.account_id !== request.accountId
    || row.actor_principal_id !== request.actorPrincipalId || row.subject_id !== request.expenseId
    || row.command_type !== (edit ? "edit_expense" : "create_expense")
    || row.contract_version !== (edit ? "expense-edit-v1" : "expense-create-v1")
    || row.command_fingerprint !== request.fingerprint || row.envelope_sha256 !== request.fingerprint
    || row.request_sha256 != null || row.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(row.server_received_at_ms) || !Number.isSafeInteger(row.completed_at_ms)
    || (row.server_received_at_ms as number) < 0 || (row.completed_at_ms as number) < (row.server_received_at_ms as number)) return mismatch();
  const allowed = edit ? new Set([...rejections, "expense_unavailable", "expense_collected",
    "expense_revision_conflict", "expense_receipt_change_unavailable"]) : rejections;
  if (!(row.phase === "applied" && row.result_code === (edit ? "expense_edited" : "expense_created") && row.error_code === null)
    && !(row.phase === "rejected" && row.result_code === null && typeof row.error_code === "string" && allowed.has(row.error_code))) return mismatch();
  return { operationId: request.operationId, phase: row.phase as "applied" | "rejected",
    resultCode: row.result_code as string | null, errorCode: row.error_code as string | null };
}
export async function expenseCreationTool(input: ExpenseCreationInput, context: TargetMCPRequestContext, service: ExpenseCreationServing) {
  userCredential(context.accessToken);
  const request = makeExpenseCreationRequest(input, context);
  return validateExpenseCreationResult(await service.apply(request, context), request);
}
export async function expenseEditTool(input: ExpenseEditInput, context: TargetMCPRequestContext, service: ExpenseCreationServing) {
  userCredential(context.accessToken);
  if (!service.edit) return fail("expense_edit_unavailable");
  const request = makeExpenseEditRequest(input, context);
  return validateExpenseEditResult(await service.edit(request, context), request);
}

export class SupabaseExpenseCreationService implements ExpenseCreationServing, ExpenseReading {
  readonly #url: URL;
  readonly #storage: URL;
  constructor(url: URL, readonly key: string, readonly fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("expense_configuration_invalid");
    }
    userCredential(key);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/`);
    this.#storage = new URL(`${url.href.replace(/\/$/, "")}/storage/v1/object/authenticated/ledger-attachments/`);
  }
  async #rpc(name: string, body: unknown, context: TargetMCPRequestContext): Promise<unknown> {
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.fetchImplementation(new URL(name, this.#url), { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(15_000), headers: { "Content-Type": "application/json", Accept: "application/json",
        apikey: this.key, Authorization: `Bearer ${context.accessToken}` }, body: JSON.stringify(body) });
    if (!response.ok) throw new TargetMCPFailure("expense_request_rejected", response.status);
    try { return await response.json(); } catch { return fail("expense_server_result_mismatch"); }
  }
  async apply(request: ExpenseCreationRequest, context: TargetMCPRequestContext): Promise<unknown> {
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) return fail("account_not_authorized");
    const result = await this.#rpc("spike_create_expense", { p_command: request.commandJSON }, context);
    validateExpenseCreationResult(result, request);
    return result;
  }
  async edit(request: ExpenseCreationRequest, context: TargetMCPRequestContext): Promise<unknown> {
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) return fail("account_not_authorized");
    const result = await this.#rpc("spike_edit_expense", { p_command: request.commandJSON }, context);
    validateExpenseEditResult(result, request);
    return result;
  }
  async read(input: ExpenseReadInput, context: TargetMCPRequestContext): Promise<ExpenseSnapshot> {
    const parsed = expenseReadInputSchema.safeParse(input);
    if (!parsed.success) return fail();
    const result = await this.#rpc("spike_read_expense", { p_account_id: context.accountId,
      p_project_id: parsed.data.projectId, p_expense_id: parsed.data.expenseId }, context);
    return validateExpenseSnapshot(result, parsed.data, context);
  }
  async list(input: ExpenseListInput, context: TargetMCPRequestContext): Promise<ExpenseSnapshot[]> {
    const parsed = expenseListInputSchema.safeParse(input);
    if (!parsed.success) return fail();
    const result = await this.#rpc("spike_list_project_expenses", { p_account_id: context.accountId,
      p_project_id: parsed.data.projectId }, context);
    return validateExpenseList(result, parsed.data, context);
  }
  async invoice(input: ExpenseReadInput, context: TargetMCPRequestContext): Promise<ExpenseInvoiceSnapshot> {
    const parsed = expenseReadInputSchema.safeParse(input);
    if (!parsed.success) return fail();
    const result = await this.#rpc("spike_read_expense_invoice", { p_account_id: context.accountId,
      p_project_id: parsed.data.projectId, p_expense_id: parsed.data.expenseId }, context);
    return validateExpenseInvoice(result, parsed.data, context);
  }
  async receipt(input: ExpenseReceiptInput, context: TargetMCPRequestContext): Promise<{ mimeType: string; bytes: Uint8Array }> {
    const parsed = expenseReceiptInputSchema.safeParse(input);
    if (!parsed.success) return fail();
    const { projectId, expenseId, attachmentId } = parsed.data;
    const selection = { projectId, expenseId };
    const before = await this.read(selection, context);
    if (!before.receiptAttachmentIds.includes(attachmentId)) return fail("expense_receipt_unavailable");
    const headers = { apikey: this.key, Authorization: `Bearer ${context.accessToken}` };
    const objectURL = new URL("../item_image_objects", this.#url);
    objectURL.search = new URLSearchParams({ select: "id,account_id,content_sha256,byte_count,media_type,storage_path",
      id: `eq.${attachmentId}`, account_id: `eq.${context.accountId}`, limit: "2" }).toString();
    const metadata = await this.fetchImplementation(objectURL, { headers, redirect: "error", signal: AbortSignal.timeout(15_000) });
    if (!metadata.ok) throw new TargetMCPFailure("expense_receipt_unavailable", metadata.status);
    let rows: unknown;
    try { rows = await metadata.json(); } catch { return fail("expense_receipt_invalid"); }
    const schema = z.array(z.object({ id: identifier, account_id: identifier,
      content_sha256: z.string().regex(/^[0-9a-f]{64}$/), byte_count: z.number().int().positive().max(64 * 1024 * 1024),
      media_type: z.string().regex(/^(application\/pdf|image\/[a-z0-9][a-z0-9+.\-]{0,126})$/), storage_path: z.string() }).strict()).length(1);
    const result = schema.safeParse(rows);
    if (!result.success) return fail("expense_receipt_invalid");
    const object = result.data[0];
    const expectedPath = `accounts/${context.accountId}/attachments/${attachmentId}/${object.content_sha256}`;
    if (object.id !== attachmentId || object.account_id !== context.accountId || object.storage_path !== expectedPath) return fail("expense_receipt_invalid");
    const response = await this.fetchImplementation(new URL(expectedPath.split("/").map(encodeURIComponent).join("/"), this.#storage),
      { headers: { ...headers, Accept: object.media_type }, redirect: "error", signal: AbortSignal.timeout(60_000) });
    if (!response.ok || !response.body) throw new TargetMCPFailure("expense_receipt_unavailable", response.status);
    const reader = response.body.getReader(), chunks: Uint8Array[] = [];
    let count = 0;
    try {
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        count += chunk.value.byteLength;
        if (count > object.byte_count) { await reader.cancel(); return fail("expense_receipt_invalid"); }
        chunks.push(chunk.value);
      }
    } finally { reader.releaseLock(); }
    const bytes = Buffer.concat(chunks);
    if (count !== object.byte_count || createHash("sha256").update(bytes).digest("hex") !== object.content_sha256) return fail("expense_receipt_invalid");
    const after = await this.read(selection, context);
    if (after.revision !== before.revision || !after.receiptAttachmentIds.includes(attachmentId)) return fail("expense_receipt_unavailable");
    return { mimeType: object.media_type, bytes };
  }
}
