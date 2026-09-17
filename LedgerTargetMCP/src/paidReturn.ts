import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const fail = (code = "paid_return_invalid"): never => { throw new TargetMCPFailure(code); };
const id = z.string().refine(value => {
  try { validateIdentifier(value, "paid_return_invalid"); return true; } catch { return false; }
});
const item = z.object({ itemId: id, placementId: id, chargeId: id, paidInvoiceLineId: id,
  inventoryPlacementId: id, returnOccurrenceId: id, creditId: id }).strict();
export const paidReturnInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: z.object({ projectId: id, items: z.array(item).min(1).max(100).refine(rows =>
    Object.keys(item.shape).every(key => new Set(rows.map(row => row[key as keyof typeof row])).size === rows.length)
    && rows.every(row => !rows.some(other => other.placementId === row.inventoryPlacementId))) }).strict(),
}).strict();
export type PaidReturnInput = z.input<typeof paidReturnInputSchema>;
export const paidReturnReviewInputSchema = z.object({ projectId: id,
  itemIds: z.array(id).min(1).max(100).refine(ids => new Set(ids).size === ids.length) }).strict();
type ReviewInput = z.input<typeof paidReturnReviewInputSchema>;
const cents = z.string().refine(value => /^[1-9][0-9]{0,18}$/.test(value) && BigInt(value) <= 9223372036854775807n);
const reviewSchema = z.object({ accountId: id, principalId: id, projectId: id,
  items: z.array(z.object({ itemId: id, placementId: id, chargeId: id, paidInvoiceLineId: id,
    paidAmountMinorUnits: cents, currency: z.string().regex(/^[A-Z]{3}$/), categoryId: id }).strict()).min(1).max(100) }).strict();
export function validatePaidReturnReview(value: unknown, input: ReviewInput, context: TargetMCPRequestContext) {
  const parsed = reviewSchema.safeParse(value);
  if (!parsed.success) return fail("paid_return_review_mismatch");
  const row = parsed.data;
  if (row.accountId !== context.accountId || row.principalId !== context.principalId || row.projectId !== input.projectId
    || row.items.length !== input.itemIds.length || row.items.some(item => !input.itemIds.includes(item.itemId))
    || ["itemId", "placementId", "chargeId", "paidInvoiceLineId"].some(key =>
      new Set(row.items.map(item => item[key as keyof typeof item])).size !== row.items.length)) return fail("paid_return_review_mismatch");
  return row;
}
export type PaidReturnRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  projectId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface PaidReturnServing {
  apply(request: PaidReturnRequest, context: TargetMCPRequestContext): Promise<unknown>;
  review(input: ReviewInput, context: TargetMCPRequestContext): Promise<unknown>;
}
export function makePaidReturnRequest(input: PaidReturnInput, context: TargetMCPRequestContext): PaidReturnRequest {
  const parsed = paidReturnInputSchema.safeParse(input);
  if (!parsed.success) return fail();
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = `paid-return-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`;
  const { projectId, items } = parsed.data.payload;
  const commandJSON = canonicalJSON({ operationId, accountId, actorPrincipalId, projectId, items,
    contractVersion: "return-paid-items-v1", createdAtMs: String(parsed.data.clientCreatedAtMilliseconds) }, "paid_return_invalid");
  return { operationId, accountId, actorPrincipalId, projectId, createdAtMs: parsed.data.clientCreatedAtMilliseconds,
    commandJSON, fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
const rejections = new Set(["return_project_unavailable", "return_item_invalid", "return_item_unavailable", "return_duplicate_item",
  "return_placement_stale", "return_charge_stale", "return_charge_unavailable", "return_paid_basis_unavailable",
  "return_origin_unproven", "return_integrity_conflict"]);
export function validatePaidReturnResult(value: unknown, request: PaidReturnRequest) {
  const mismatch = () => fail("paid_return_result_mismatch");
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const row = value as Record<string, unknown>;
  if (row.operation_id !== request.operationId || row.account_id !== request.accountId
    || row.actor_principal_id !== request.actorPrincipalId || row.subject_id !== request.projectId
    || row.command_type !== "return_paid_items" || row.contract_version !== "return-paid-items-v1"
    || row.command_fingerprint !== request.fingerprint || row.envelope_sha256 !== request.fingerprint
    || row.request_sha256 != null || row.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(row.server_received_at_ms) || !Number.isSafeInteger(row.completed_at_ms)
    || (row.server_received_at_ms as number) < 0 || (row.completed_at_ms as number) < (row.server_received_at_ms as number)) return mismatch();
  if (!(row.phase === "applied" && row.result_code === "paid_items_returned" && row.error_code === null)
    && !(row.phase === "rejected" && row.result_code === null && typeof row.error_code === "string" && rejections.has(row.error_code))) return mismatch();
  return { operationId: request.operationId, phase: row.phase as "applied" | "rejected",
    resultCode: row.result_code as string | null, errorCode: row.error_code as string | null };
}
export async function paidReturnTool(input: PaidReturnInput, context: TargetMCPRequestContext, service: PaidReturnServing) {
  userCredential(context.accessToken);
  const request = makePaidReturnRequest(input, context);
  return validatePaidReturnResult(await service.apply(request, context), request);
}

export class SupabasePaidReturnService implements PaidReturnServing {
  constructor(private readonly url: URL, private readonly key: string,
              private readonly fetchImplementation: typeof fetch = fetch) { userCredential(key); }
  private async rpc(name: string, body: unknown, context: TargetMCPRequestContext): Promise<unknown> {
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.fetchImplementation(new URL(`${this.url.href.replace(/\/$/, "")}/rest/v1/rpc/${name}`), {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(15_000),
      headers: { "Content-Type": "application/json", Accept: "application/json", apikey: this.key,
        Authorization: `Bearer ${context.accessToken}` }, body: JSON.stringify(body) });
    if (!response.ok) throw new TargetMCPFailure("paid_return_request_rejected", response.status);
    try { return await response.json(); } catch { return fail("paid_return_result_mismatch"); }
  }
  async apply(request: PaidReturnRequest, context: TargetMCPRequestContext): Promise<unknown> {
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) return fail("account_not_authorized");
    const result = await this.rpc("spike_return_paid_items", { p_command: request.commandJSON }, context);
    validatePaidReturnResult(result, request);
    return result;
  }
  async review(input: ReviewInput, context: TargetMCPRequestContext): Promise<unknown> {
    const parsed = paidReturnReviewInputSchema.parse(input);
    return validatePaidReturnReview(await this.rpc("spike_read_paid_return_review", {
      p_account_id: context.accountId, p_project_id: parsed.projectId, p_item_ids: parsed.itemIds }, context), parsed, context);
  }
}
