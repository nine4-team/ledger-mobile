import { z } from "zod";
import { createHash } from "node:crypto";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "price_review_mismatch"); return true; } catch { return false; }
});
const integer = z.string().refine(value => /^(0|[1-9][0-9]*)$/.test(value)
  && value.length <= 19 && BigInt(value) <= 9223372036854775807n);
const revision = integer.refine(value => BigInt(value) < 9223372036854775807n);
const currency = z.string().regex(/^[A-Z]{3}$/);
const money = z.object({ amountMinorUnits: integer, currency }).strict();
export const itemPriceEditReviewInputSchema = z.object({ projectId: identifier.nullable(), itemId: identifier }).strict();
export type ItemPriceEditReviewInput = z.infer<typeof itemPriceEditReviewInputSchema>;
const reviewSchema = z.object({ accountId: identifier, principalId: identifier,
  projectId: identifier.nullable(), itemId: identifier, placementId: identifier, occurrenceId: identifier.nullable(),
  currency: currency.nullable(), priceRevision: revision, chargeRevision: revision.refine(value => BigInt(value) > 0n).nullable(),
  currentPrice: money.nullable(), purchaseCost: z.discriminatedUnion("state", [
    z.object({ state: z.literal("absent") }).strict(),
    money.extend({ state: z.literal("known") }).strict(),
  ]),
}).strict();

/** Preserve absent evidence and exact minor units; never infer zero from missing data. */
export function validateItemPriceEditReview(value: unknown, input: ItemPriceEditReviewInput,
  context: TargetMCPRequestContext) {
  const parsed = reviewSchema.safeParse(value);
  if (!parsed.success) throw new TargetMCPFailure("price_review_mismatch");
  const row = parsed.data;
  if (row.accountId !== context.accountId || row.principalId !== context.principalId
    || row.projectId !== input.projectId || row.itemId !== input.itemId
    || (row.projectId === null
      ? row.occurrenceId !== null || row.chargeRevision !== null
      : row.occurrenceId === null || row.chargeRevision === null || row.currency === null)
    || (row.priceRevision !== "0" && row.currency === null)
    || (row.priceRevision === "0" && row.currentPrice !== null)
    || (row.currentPrice !== null && row.currentPrice.currency !== row.currency)
    || (row.purchaseCost.state === "known" && row.purchaseCost.currency !== row.currency)) {
    throw new TargetMCPFailure("price_review_mismatch");
  }
  return row;
}

export const itemPriceEditInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: z.union([z.object({ projectId: identifier, itemId: identifier, placementId: identifier,
    occurrenceId: identifier, expectedPriceRevision: revision,
    expectedChargeRevision: revision.refine(value => BigInt(value) > 0n),
    requestedPriceMinorUnits: integer, reviewedPriceMinorUnits: integer.refine(value => BigInt(value) > 0n),
    currency }).strict(),
    z.object({ itemId: identifier, placementId: identifier, expectedPriceRevision: revision,
      requestedPriceMinorUnits: integer, reviewedPriceMinorUnits: integer, currency,
      clearPrice: z.boolean() }).strict().refine(value => !value.clearPrice || value.requestedPriceMinorUnits === "0"),
  ]).refine(value => BigInt(value.reviewedPriceMinorUnits) >= BigInt(value.requestedPriceMinorUnits)),
}).strict();
export type ItemPriceEditInput = z.infer<typeof itemPriceEditInputSchema>;
export type ItemPriceEditRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  itemId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface ItemPriceEditServing {
  reviewItemPriceEdit(input: ItemPriceEditReviewInput, context: TargetMCPRequestContext): Promise<unknown>;
  applyItemPriceEdit(request: ItemPriceEditRequest, context: TargetMCPRequestContext): Promise<unknown>;
}
export function makeItemPriceEditRequest(input: ItemPriceEditInput, context: TargetMCPRequestContext): ItemPriceEditRequest {
  const parsed = itemPriceEditInputSchema.safeParse(input);
  if (!parsed.success) throw new TargetMCPFailure("price_payload_invalid");
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = `item-price-edit-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`;
  const inventory = "clearPrice" in parsed.data.payload;
  const payload = "clearPrice" in parsed.data.payload
    ? { ...parsed.data.payload, clearPrice: String(parsed.data.payload.clearPrice) } : parsed.data.payload;
  const commandJSON = canonicalJSON({ ...payload, operationId, accountId, actorPrincipalId,
    contractVersion: inventory ? "item-inventory-price-edit-v2" : "item-uncollected-price-edit-v1",
    createdAtMs: String(parsed.data.clientCreatedAtMilliseconds) }, "price_payload_invalid");
  return { operationId, accountId, actorPrincipalId, itemId: parsed.data.payload.itemId,
    createdAtMs: parsed.data.clientCreatedAtMilliseconds, commandJSON,
    fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
const rejections = new Set(["price_project_unavailable", "price_invoice_unavailable", "price_item_unavailable",
  "price_placement_stale", "price_invoice_changed", "price_charge_unavailable", "price_charge_stale",
  "price_charge_collected", "price_acquisition_ambiguous", "price_currency_mismatch", "price_review_stale",
  "price_revision_stale", "price_integrity_conflict"]);
export function validateItemPriceEditResult(value: unknown, request: ItemPriceEditRequest) {
  const mismatch = (): never => { throw new TargetMCPFailure("price_server_result_mismatch"); };
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const row = value as Record<string, unknown>;
  if (row.operation_id !== request.operationId || row.account_id !== request.accountId
    || row.actor_principal_id !== request.actorPrincipalId || row.subject_id !== request.itemId
    || row.command_type !== "edit_uncollected_item_price" || row.contract_version !== JSON.parse(request.commandJSON).contractVersion
    || row.command_fingerprint !== request.fingerprint || row.envelope_sha256 !== request.fingerprint
    || row.request_sha256 != null || row.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(row.server_received_at_ms) || !Number.isSafeInteger(row.completed_at_ms)
    || (row.server_received_at_ms as number) < 0 || (row.completed_at_ms as number) < (row.server_received_at_ms as number)
    || !((row.phase === "applied" && row.result_code === "item_price_updated" && row.error_code === null)
      || (row.phase === "rejected" && row.result_code === null && typeof row.error_code === "string" && rejections.has(row.error_code)))) return mismatch();
  return { operationId: request.operationId, phase: row.phase as "applied" | "rejected",
    resultCode: row.result_code as string | null, errorCode: row.error_code as string | null };
}
export async function itemPriceEditTool(input: ItemPriceEditInput, context: TargetMCPRequestContext, service: ItemPriceEditServing) {
  userCredential(context.accessToken);
  const request = makeItemPriceEditRequest(input, context);
  return validateItemPriceEditResult(await service.applyItemPriceEdit(request, context), request);
}
export async function itemPriceEditReviewTool(input: ItemPriceEditReviewInput, context: TargetMCPRequestContext, service: ItemPriceEditServing) {
  userCredential(context.accessToken);
  const parsed = itemPriceEditReviewInputSchema.safeParse(input);
  if (!parsed.success) throw new TargetMCPFailure("price_payload_invalid");
  return validateItemPriceEditReview(await service.reviewItemPriceEdit(parsed.data, context), parsed.data, context);
}
