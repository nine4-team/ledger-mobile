import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const fail = (code = "return_payload_invalid"): never => { throw new TargetMCPFailure(code); };
const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "return_payload_invalid"); return true; } catch { return false; }
});
const revision = z.string().refine(value => /^[1-9][0-9]*$/.test(value) && value.length <= 19
  && BigInt(value) < 9223372036854775807n);
const item = z.object({ itemId: identifier, placementId: identifier, chargeId: identifier,
  expectedChargeRevision: revision, inventoryPlacementId: identifier, returnOccurrenceId: identifier }).strict();
export const uninvoicedReturnInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: z.object({ projectId: identifier, items: z.array(item).min(1).max(500).refine(rows => {
    const keys = ["itemId", "placementId", "chargeId", "inventoryPlacementId", "returnOccurrenceId"] as const;
    return keys.every(key => new Set(rows.map(row => row[key])).size === rows.length)
      && rows.every(row => !rows.some(other => other.placementId === row.inventoryPlacementId));
  }) }).strict(),
}).strict();
export type UninvoicedReturnInput = z.input<typeof uninvoicedReturnInputSchema>;
export const uninvoicedReturnReviewInputSchema = z.object({ projectId: identifier,
  itemIds: z.array(identifier).min(1).max(500).refine(ids => new Set(ids).size === ids.length) }).strict();
export type UninvoicedReturnReviewInput = z.input<typeof uninvoicedReturnReviewInputSchema>;
const reviewSchema = z.object({ accountId: identifier, principalId: identifier, projectId: identifier,
  items: z.array(z.object({ itemId: identifier, placementId: identifier, chargeId: identifier, revision }).strict()).min(1).max(500) }).strict();
export function validateUninvoicedReturnReview(value: unknown, input: UninvoicedReturnReviewInput, context: TargetMCPRequestContext) {
  const parsed = reviewSchema.safeParse(value);
  if (!parsed.success) return fail("return_review_mismatch");
  const result = parsed.data;
  if (result.accountId !== context.accountId || result.principalId !== context.principalId || result.projectId !== input.projectId
    || result.items.length !== input.itemIds.length || result.items.some(row => !input.itemIds.includes(row.itemId))
    || ["itemId", "placementId", "chargeId"].some(key => new Set(result.items.map(row => row[key as keyof typeof row])).size !== result.items.length)) {
    return fail("return_review_mismatch");
  }
  return result;
}
export type UninvoicedReturnRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  projectId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface UninvoicedReturnServing {
  apply(request: UninvoicedReturnRequest, context: TargetMCPRequestContext): Promise<unknown>;
  review(input: UninvoicedReturnReviewInput, context: TargetMCPRequestContext): Promise<unknown>;
}
export function makeUninvoicedReturnRequest(input: UninvoicedReturnInput, context: TargetMCPRequestContext): UninvoicedReturnRequest {
  const parsed = uninvoicedReturnInputSchema.safeParse(input);
  if (!parsed.success) return fail();
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = `uninvoiced-return-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`;
  const { projectId, items } = parsed.data.payload;
  const commandJSON = canonicalJSON({ operationId, accountId, actorPrincipalId, projectId, items,
    contractVersion: "return-uninvoiced-items-v1", createdAtMs: String(parsed.data.clientCreatedAtMilliseconds) }, "return_payload_invalid");
  return { operationId, accountId, actorPrincipalId, projectId, createdAtMs: parsed.data.clientCreatedAtMilliseconds,
    commandJSON, fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
const rejections = new Set(["return_project_unavailable", "return_item_invalid", "return_item_unavailable", "return_duplicate_item",
  "return_placement_stale", "return_charge_stale", "return_charge_unavailable", "return_charge_invoiced",
  "return_charge_collected", "return_origin_unproven", "return_integrity_conflict"]);
export function validateUninvoicedReturnResult(value: unknown, request: UninvoicedReturnRequest) {
  const mismatch = () => fail("return_server_result_mismatch");
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const row = value as Record<string, unknown>;
  if (row.operation_id !== request.operationId || row.account_id !== request.accountId
    || row.actor_principal_id !== request.actorPrincipalId || row.subject_id !== request.projectId
    || row.command_type !== "return_uninvoiced_items" || row.contract_version !== "return-uninvoiced-items-v1"
    || row.command_fingerprint !== request.fingerprint || row.envelope_sha256 !== request.fingerprint
    || row.request_sha256 != null || row.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(row.server_received_at_ms) || !Number.isSafeInteger(row.completed_at_ms)
    || (row.server_received_at_ms as number) < 0 || (row.completed_at_ms as number) < (row.server_received_at_ms as number)) return mismatch();
  if (!(row.phase === "applied" && row.result_code === "uninvoiced_items_returned" && row.error_code === null)
    && !(row.phase === "rejected" && row.result_code === null && typeof row.error_code === "string" && rejections.has(row.error_code))) return mismatch();
  return { operationId: request.operationId, phase: row.phase as "applied" | "rejected",
    resultCode: row.result_code as string | null, errorCode: row.error_code as string | null };
}
export async function uninvoicedReturnTool(input: UninvoicedReturnInput, context: TargetMCPRequestContext, service: UninvoicedReturnServing) {
  userCredential(context.accessToken);
  const request = makeUninvoicedReturnRequest(input, context);
  return validateUninvoicedReturnResult(await service.apply(request, context), request);
}

export class SupabaseUninvoicedReturnService implements UninvoicedReturnServing {
  readonly #url: URL;
  constructor(url: URL, readonly key: string, readonly fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("return_configuration_invalid");
    }
    userCredential(key);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/spike_return_uninvoiced_items`);
  }
  async review(input: UninvoicedReturnReviewInput, context: TargetMCPRequestContext): Promise<unknown> {
    const parsed = uninvoicedReturnReviewInputSchema.safeParse(input);
    if (!parsed.success) return fail();
    const result = await this.rpc(new URL("spike_read_uninvoiced_return_review", this.#url), {
      p_account_id: context.accountId, p_project_id: parsed.data.projectId, p_item_ids: parsed.data.itemIds }, context);
    return validateUninvoicedReturnReview(result, parsed.data, context);
  }
  private async rpc(url: URL, body: unknown, context: TargetMCPRequestContext): Promise<unknown> {
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.fetchImplementation(url, { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(15_000), headers: { "Content-Type": "application/json", Accept: "application/json",
        apikey: this.key, Authorization: `Bearer ${context.accessToken}` }, body: JSON.stringify(body) });
    if (!response.ok) throw new TargetMCPFailure("return_request_rejected", response.status);
    let result: unknown;
    try { result = await response.json(); } catch { return fail("return_server_result_mismatch"); }
    return result;
  }
  async apply(request: UninvoicedReturnRequest, context: TargetMCPRequestContext): Promise<unknown> {
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) return fail("account_not_authorized");
    const result = await this.rpc(this.#url, { p_command: request.commandJSON }, context);
    validateUninvoicedReturnResult(result, request);
    return result;
  }
}
