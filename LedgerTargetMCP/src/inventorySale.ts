import { createHash } from "node:crypto";
import { z } from "zod";
import { validateItemDetailsEditResult, type ItemDetailsEditRequest, type ItemDetailsEditServing } from "./itemDetailsEdit.js";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";
import { itemPriceEditReviewInputSchema, validateItemPriceEditReview,
  validateItemPriceEditResult, type ItemPriceEditRequest, type ItemPriceEditServing,
  type ItemPriceEditReviewInput } from "./itemPriceEdit.js";

const fail = (code = "sale_payload_invalid"): never => { throw new TargetMCPFailure(code); };
const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "sale_payload_invalid"); return true; } catch { return false; }
});
const integer = z.string().refine(value => /^(0|[1-9][0-9]*)$/.test(value)
  && value.length <= 19 && BigInt(value) <= 9223372036854775807n);
const positive = integer.refine(value => BigInt(value) > 0n);
const currency = z.string().regex(/^[A-Z]{3}$/);
const item = z.object({ itemId: identifier, placementId: identifier, priceRevision: integer,
  reviewedPriceMinorUnits: positive, newPlacementId: identifier, occurrenceId: identifier }).strict()
  .refine(row => row.placementId !== row.newPlacementId);
export const inventorySaleInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: z.object({ projectId: identifier, currency, items: z.array(item).min(1).max(500)
    .refine(rows => ["itemId", "newPlacementId", "occurrenceId"].every(key =>
      new Set(rows.map(row => row[key as keyof typeof row])).size === rows.length)) }).strict(),
}).strict();
export const inventorySaleReviewInputSchema = z.object({ itemIds: z.array(identifier).min(1).max(500)
  .refine(ids => new Set(ids).size === ids.length) }).strict();
export type InventorySaleInput = z.input<typeof inventorySaleInputSchema>;
export type InventorySaleRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  projectId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface InventorySaleServing {
  apply(request: InventorySaleRequest, context: TargetMCPRequestContext): Promise<unknown>;
  review(itemIds: string[], context: TargetMCPRequestContext): Promise<unknown>;
}

export function makeInventorySaleRequest(input: InventorySaleInput, context: TargetMCPRequestContext): InventorySaleRequest {
  const parsed = inventorySaleInputSchema.safeParse(input);
  if (!parsed.success) return fail();
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = `inventory-sale-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`;
  const { projectId, currency, items } = parsed.data.payload;
  const commandJSON = canonicalJSON({ operationId, accountId, actorPrincipalId, projectId, currency, items,
    contractVersion: "inventory-sale-v1", createdAtMs: String(parsed.data.clientCreatedAtMilliseconds) }, "sale_payload_invalid");
  return { operationId, accountId, actorPrincipalId, projectId, createdAtMs: parsed.data.clientCreatedAtMilliseconds,
    commandJSON, fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
const rejections = new Set(["sale_duplicate_item", "sale_destination_unavailable", "sale_furnishings_unresolved",
  "sale_item_invalid", "sale_item_unavailable", "sale_placement_stale", "sale_acquisition_unavailable",
  "sale_acquisition_ambiguous", "sale_currency_mismatch", "sale_price_stale", "sale_price_review_stale", "sale_integrity_conflict"]);
export function validateInventorySaleResult(value: unknown, request: InventorySaleRequest) {
  const mismatch = () => fail("sale_server_result_mismatch");
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const row = value as Record<string, unknown>;
  if (row.operation_id !== request.operationId || row.account_id !== request.accountId
    || row.actor_principal_id !== request.actorPrincipalId || row.subject_id !== request.projectId
    || row.command_type !== "sell_inventory_items" || row.contract_version !== "inventory-sale-v1"
    || row.command_fingerprint !== request.fingerprint || row.envelope_sha256 !== request.fingerprint
    || row.request_sha256 != null || row.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(row.server_received_at_ms) || !Number.isSafeInteger(row.completed_at_ms)
    || (row.server_received_at_ms as number) < 0 || (row.completed_at_ms as number) < (row.server_received_at_ms as number)) return mismatch();
  if (!(row.phase === "applied" && row.result_code === "inventory_items_sold" && row.error_code === null)
    && !(row.phase === "rejected" && row.result_code === null && typeof row.error_code === "string" && rejections.has(row.error_code))) return mismatch();
  return { operationId: request.operationId, phase: row.phase as "applied" | "rejected",
    resultCode: row.result_code as string | null, errorCode: row.error_code as string | null };
}

const evidence = z.discriminatedUnion("state", [
  z.object({ state: z.literal("absent") }).strict(), z.object({ state: z.literal("unavailable") }).strict(),
  z.object({ state: z.literal("known"), amountMinorUnits: z.string().refine(value =>
    /^-?(0|[1-9][0-9]*)$/.test(value) && value !== "-0" && value.length <= 20
    && BigInt(value) >= -9223372036854775808n && BigInt(value) <= 9223372036854775807n), currency }).strict(),
]);
const reviewSchema = z.object({ accountId: identifier, principalId: identifier,
  items: z.array(z.object({ itemId: identifier, placementId: identifier, priceRevision: integer,
    projectPrice: evidence, purchaseCost: evidence }).strict()).min(1).max(500) }).strict();
export function validateInventorySaleReview(value: unknown, ids: string[], context: TargetMCPRequestContext) {
  const parsed = reviewSchema.safeParse(value);
  if (!parsed.success) return fail("sale_review_mismatch");
  const review = parsed.data;
  if (review.accountId !== context.accountId || review.principalId !== context.principalId
    || review.items.length !== ids.length || new Set(review.items.map(row => row.itemId)).size !== ids.length
    || new Set(review.items.map(row => row.placementId)).size !== ids.length
    || review.items.some(row => !ids.includes(row.itemId) || row.projectPrice.state === "unavailable"
      || (row.projectPrice.state === "known"
        && (row.priceRevision === "0" || BigInt(row.projectPrice.amountMinorUnits) < 0n)))) return fail("sale_review_mismatch");
  return review;
}
export async function inventorySaleTool(input: InventorySaleInput, context: TargetMCPRequestContext, service: InventorySaleServing) {
  userCredential(context.accessToken);
  const request = makeInventorySaleRequest(input, context);
  return validateInventorySaleResult(await service.apply(request, context), request);
}
export async function inventorySaleReviewTool(input: { itemIds: string[] }, context: TargetMCPRequestContext, service: InventorySaleServing) {
  userCredential(context.accessToken);
  const parsed = inventorySaleReviewInputSchema.safeParse(input);
  if (!parsed.success) return fail();
  return validateInventorySaleReview(await service.review(parsed.data.itemIds, context), parsed.data.itemIds, context);
}

export class SupabaseInventorySaleService implements InventorySaleServing, ItemPriceEditServing, ItemDetailsEditServing {
  readonly #url: URL;
  constructor(url: URL, readonly key: string, readonly fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("sale_configuration_invalid");
    }
    userCredential(key);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/`);
  }
  async #rpc(name: string, body: unknown, context: TargetMCPRequestContext): Promise<unknown> {
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.fetchImplementation(new URL(name, this.#url), { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(15_000), headers: { "Content-Type": "application/json",
        Accept: "application/json", apikey: this.key, Authorization: `Bearer ${context.accessToken}` }, body: JSON.stringify(body) });
    if (!response.ok) throw new TargetMCPFailure("sale_request_rejected", response.status);
    try { return await response.json(); } catch { return fail("sale_server_result_mismatch"); }
  }
  async apply(request: InventorySaleRequest, context: TargetMCPRequestContext): Promise<unknown> {
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) return fail("account_not_authorized");
    const result = await this.#rpc("spike_sell_inventory_items", { p_command: request.commandJSON }, context);
    validateInventorySaleResult(result, request);
    return result;
  }
  async review(itemIds: string[], context: TargetMCPRequestContext): Promise<unknown> {
    const result = await this.#rpc("spike_read_inventory_sale_review", { p_account_id: context.accountId, p_item_ids: itemIds }, context);
    return validateInventorySaleReview(result, itemIds, context);
  }
  async reviewItemPriceEdit(input: ItemPriceEditReviewInput, context: TargetMCPRequestContext) {
    const parsed = itemPriceEditReviewInputSchema.safeParse(input);
    if (!parsed.success) throw new TargetMCPFailure("price_payload_invalid");
    const result = await this.#rpc("spike_read_item_price_edit", {
      p_account_id: context.accountId, p_project_id: parsed.data.projectId, p_item_id: parsed.data.itemId,
    }, context);
    return validateItemPriceEditReview(result, parsed.data, context);
  }
  async applyItemPriceEdit(request: ItemPriceEditRequest, context: TargetMCPRequestContext): Promise<unknown> {
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) return fail("account_not_authorized");
    const result = await this.#rpc("spike_edit_uncollected_item_price", { p_command: request.commandJSON }, context);
    validateItemPriceEditResult(result, request);
    return result;
  }
  async applyItemDetailsEdit(request: ItemDetailsEditRequest, context: TargetMCPRequestContext): Promise<unknown> {
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) return fail("account_not_authorized");
    const result = await this.#rpc("spike_edit_item_details", { p_command: request.commandJSON }, context);
    validateItemDetailsEditResult(result, request);
    return result;
  }
}
