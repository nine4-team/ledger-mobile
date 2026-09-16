import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const fail = (code = "invoice_payload_invalid"): never => { throw new TargetMCPFailure(code); };
const identifier = z.string().refine(value => { try { validateIdentifier(value, "invoice_payload_invalid"); return true; } catch { return false; } });
const integer = z.string().refine(value => /^(0|-?[1-9][0-9]*)$/.test(value) && value.length <= 20
  && BigInt(value) >= -9223372036854775808n && BigInt(value) <= 9223372036854775807n);
const source = z.object({ kind: z.enum(["item", "expense", "fee_installment"]), sourceId: identifier,
  expectedRevision: integer.refine(value => /^[1-9][0-9]*$/.test(value)), amountMinorUnits: integer,
  currency: z.string().regex(/^[A-Z]{3}$/) }).strict();
export const invoiceCreationInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: z.object({ projectId: identifier, clientId: identifier, invoiceId: identifier,
    name: z.string(), notes: z.string(), sources: z.array(source).nonempty() }).strict(),
}).strict();
export type InvoiceCreationInput = z.input<typeof invoiceCreationInputSchema>;
export type InvoiceCreationRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  invoiceId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface InvoiceCreationServing {
  apply(request: InvoiceCreationRequest, context: TargetMCPRequestContext): Promise<unknown>;
}
export function makeInvoiceCreationRequest(input: InvoiceCreationInput, context: TargetMCPRequestContext): InvoiceCreationRequest {
  const parsed = invoiceCreationInputSchema.safeParse(input);
  if (!parsed.success) return fail();
  const sources = parsed.data.payload.sources;
  if (new Set(sources.map(row => `${row.kind}:${row.sourceId}`)).size !== sources.length
    || sources.some(row => row.currency !== sources[0].currency)) return fail();
  let total = 0n;
  for (const row of sources) {
    total += BigInt(row.amountMinorUnits);
    if (total < -9223372036854775808n || total > 9223372036854775807n) return fail();
  }
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = `invoice-create-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`;
  const commandJSON = canonicalJSON({ ...parsed.data.payload, operationId, accountId, actorPrincipalId,
    contractVersion: "invoice-create-v1", createdAtMs: String(parsed.data.clientCreatedAtMilliseconds) }, "invoice_payload_invalid");
  return { operationId, accountId, actorPrincipalId, invoiceId: parsed.data.payload.invoiceId,
    createdAtMs: parsed.data.clientCreatedAtMilliseconds, commandJSON,
    fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
const rejections = new Set(["invoice_project_unavailable", "invoice_empty_selection", "invoice_duplicate_source",
  "invoice_source_invalid", "invoice_source_unavailable", "invoice_source_changed", "invoice_source_collected",
  "invoice_source_reserved", "invoice_currency_mismatch", "invoice_total_overflow", "invoice_integrity_conflict"]);
export function validateInvoiceCreationResult(value: unknown, request: InvoiceCreationRequest) {
  const mismatch = () => fail("invoice_server_result_mismatch");
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const row = value as Record<string, unknown>;
  if (row.operation_id !== request.operationId || row.account_id !== request.accountId
    || row.actor_principal_id !== request.actorPrincipalId || row.subject_id !== request.invoiceId
    || row.command_type !== "create_invoice" || row.contract_version !== "invoice-create-v1"
    || row.command_fingerprint !== request.fingerprint || row.envelope_sha256 !== request.fingerprint
    || row.request_sha256 !== null || row.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(row.server_received_at_ms) || !Number.isSafeInteger(row.completed_at_ms)
    || (row.server_received_at_ms as number) < 0 || (row.completed_at_ms as number) < (row.server_received_at_ms as number)) return mismatch();
  if (!(row.phase === "applied" && row.result_code === "invoice_created" && row.error_code === null)
    && !(row.phase === "rejected" && row.result_code === null && typeof row.error_code === "string" && rejections.has(row.error_code))) return mismatch();
  return { operationId: request.operationId, phase: row.phase as "applied" | "rejected",
    resultCode: row.result_code as string | null, errorCode: row.error_code as string | null };
}
export async function invoiceCreationTool(input: InvoiceCreationInput, context: TargetMCPRequestContext, service: InvoiceCreationServing) {
  userCredential(context.accessToken);
  const request = makeInvoiceCreationRequest(input, context);
  return validateInvoiceCreationResult(await service.apply(request, context), request);
}
export class SupabaseInvoiceCreationService implements InvoiceCreationServing {
  readonly #url: URL;
  constructor(url: URL, readonly key: string, readonly fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("invoice_configuration_invalid");
    }
    userCredential(key);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/spike_create_invoice`);
  }
  async apply(request: InvoiceCreationRequest, context: TargetMCPRequestContext): Promise<unknown> {
    userCredential(context.accessToken);
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) return fail("account_not_authorized");
    const response = await this.fetchImplementation(this.#url, { method: "POST", redirect: "error", signal: AbortSignal.timeout(15000),
      headers: { "Content-Type": "application/json", Accept: "application/json", apikey: this.key,
        Authorization: `Bearer ${context.accessToken}` }, body: JSON.stringify({ p_command: request.commandJSON }) });
    if (!response.ok) throw new TargetMCPFailure("invoice_request_rejected", response.status);
    const result: unknown = await response.json();
    validateInvoiceCreationResult(result, request);
    return result;
  }
}
