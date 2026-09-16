import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const fail = (code = "fee_payload_invalid"): never => { throw new TargetMCPFailure(code); };
const identifier = z.string().refine(value => { try { validateIdentifier(value, "fee_payload_invalid"); return true; } catch { return false; } });
export const feeCreationInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: z.object({ projectId: identifier, installmentId: identifier, categoryId: identifier,
    label: z.string().refine(value => value.trim().length > 0),
    amountMinorUnits: z.string().refine(value => /^[1-9][0-9]{0,18}$/.test(value) && BigInt(value) <= 9223372036854775807n),
    currency: z.string().regex(/^[A-Z]{3}$/),
    sortOrder: z.number().int().min(-2147483648).max(2147483647).optional(),
  }).strict(),
}).strict();
export type FeeCreationInput = z.input<typeof feeCreationInputSchema>;
export type FeeCreationRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  installmentId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface FeeCreationServing {
  apply(request: FeeCreationRequest, context: TargetMCPRequestContext): Promise<unknown>;
}
export function makeFeeCreationRequest(input: FeeCreationInput, context: TargetMCPRequestContext): FeeCreationRequest {
  const parsed = feeCreationInputSchema.safeParse(input);
  if (!parsed.success) return fail();
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = `fee-create-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`;
  const commandJSON = canonicalJSON({ ...parsed.data.payload, sortOrder: parsed.data.payload.sortOrder?.toString() ?? "",
    operationId, accountId, actorPrincipalId, contractVersion: "fee-installment-create-v1",
    createdAtMs: String(parsed.data.clientCreatedAtMilliseconds) }, "fee_payload_invalid");
  return { operationId, accountId, actorPrincipalId, installmentId: parsed.data.payload.installmentId,
    createdAtMs: parsed.data.clientCreatedAtMilliseconds, commandJSON,
    fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
const rejections = new Set(["fee_invalid_draft", "fee_project_unavailable", "fee_category_unavailable",
  "fee_currency_mismatch", "fee_total_overflow", "fee_total_exceeded", "fee_integrity_conflict"]);
export function validateFeeCreationResult(value: unknown, request: FeeCreationRequest) {
  const mismatch = () => fail("fee_server_result_mismatch");
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const row = value as Record<string, unknown>;
  if (row.operation_id !== request.operationId || row.account_id !== request.accountId
    || row.actor_principal_id !== request.actorPrincipalId || row.subject_id !== request.installmentId
    || row.command_type !== "create_fee_installment" || row.contract_version !== "fee-installment-create-v1"
    || row.command_fingerprint !== request.fingerprint || row.envelope_sha256 !== request.fingerprint
    || row.request_sha256 !== null || row.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(row.server_received_at_ms) || !Number.isSafeInteger(row.completed_at_ms)
    || (row.server_received_at_ms as number) < 0 || (row.completed_at_ms as number) < (row.server_received_at_ms as number)) return mismatch();
  if (!(row.phase === "applied" && row.result_code === "fee_installment_created" && row.error_code === null)
    && !(row.phase === "rejected" && row.result_code === null && typeof row.error_code === "string" && rejections.has(row.error_code))) return mismatch();
  return { operationId: request.operationId, phase: row.phase as "applied" | "rejected",
    resultCode: row.result_code as string | null, errorCode: row.error_code as string | null };
}
export async function feeCreationTool(input: FeeCreationInput, context: TargetMCPRequestContext, service: FeeCreationServing) {
  userCredential(context.accessToken);
  const request = makeFeeCreationRequest(input, context);
  return validateFeeCreationResult(await service.apply(request, context), request);
}
export class SupabaseFeeCreationService implements FeeCreationServing {
  readonly #url: URL;
  constructor(url: URL, readonly key: string, readonly fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("fee_configuration_invalid");
    }
    userCredential(key);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/spike_create_fee_installment`);
  }
  async apply(request: FeeCreationRequest, context: TargetMCPRequestContext): Promise<unknown> {
    userCredential(context.accessToken);
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) return fail("account_not_authorized");
    const response = await this.fetchImplementation(this.#url, { method: "POST", redirect: "error", signal: AbortSignal.timeout(15000),
      headers: { "Content-Type": "application/json", Accept: "application/json", apikey: this.key,
        Authorization: `Bearer ${context.accessToken}` }, body: JSON.stringify({ p_command: request.commandJSON }) });
    if (!response.ok) throw new TargetMCPFailure("fee_request_rejected", response.status);
    const result: unknown = await response.json();
    validateFeeCreationResult(result, request);
    return result;
  }
}
