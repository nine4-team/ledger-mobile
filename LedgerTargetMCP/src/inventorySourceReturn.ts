import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const fail = (code = "source_return_payload_invalid"): never => { throw new TargetMCPFailure(code); };
const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "source_return_payload_invalid"); return true; } catch { return false; }
});
const item = z.object({ itemId: identifier, placementId: identifier, inventoryEntryId: identifier,
  projectPlacementId: identifier, occurrenceId: identifier }).strict();
export const inventorySourceReturnInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: z.object({ projectId: identifier, items: z.array(item).min(1).max(100).refine(rows => {
    const keys = ["itemId", "placementId", "inventoryEntryId", "projectPlacementId", "occurrenceId"] as const;
    return keys.every(key => new Set(rows.map(row => row[key])).size === rows.length)
      && rows.every(row => !rows.some(other => other.placementId === row.projectPlacementId));
  }) }).strict(),
}).strict();
export type InventorySourceReturnInput = z.input<typeof inventorySourceReturnInputSchema>;
export const inventorySourceReturnReviewInputSchema = z.object({ itemIds: z.array(identifier).min(1).max(100)
  .refine(ids => new Set(ids).size === ids.length) }).strict();
export type InventorySourceReturnReviewInput = z.input<typeof inventorySourceReturnReviewInputSchema>;
const amount = z.string().refine(value => /^[1-9][0-9]*$/.test(value) && value.length <= 19 && BigInt(value) <= 9223372036854775807n);
const reviewSchema = z.object({ accountId: identifier, principalId: identifier, projectId: identifier,
  items: z.array(z.object({ itemId: identifier, placementId: identifier, inventoryEntryId: identifier,
    sourceProjectId: identifier, sourceCategoryId: identifier, amountMinorUnits: amount,
    currency: z.string().regex(/^[A-Z]{3}$/) }).strict()).min(1).max(100) }).strict();
export function validateInventorySourceReturnReview(value: unknown, input: InventorySourceReturnReviewInput, context: TargetMCPRequestContext) {
  const parsed = reviewSchema.safeParse(value);
  if (!parsed.success) return fail("source_return_review_mismatch");
  const result = parsed.data;
  if (result.accountId !== context.accountId || result.principalId !== context.principalId
    || result.items.length !== input.itemIds.length || result.items.some(row => !input.itemIds.includes(row.itemId)
      || row.sourceProjectId !== result.projectId || row.currency !== result.items[0].currency)
    || ["itemId", "placementId", "inventoryEntryId"].some(key => new Set(result.items.map(row => row[key as keyof typeof row])).size !== result.items.length)) {
    return fail("source_return_review_mismatch");
  }
  return result;
}
export type InventorySourceReturnRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  projectId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface InventorySourceReturnServing {
  applySourceReturn(request: InventorySourceReturnRequest, context: TargetMCPRequestContext): Promise<unknown>;
  reviewSourceReturn(input: InventorySourceReturnReviewInput, context: TargetMCPRequestContext): Promise<unknown>;
}
export function makeInventorySourceReturnRequest(input: InventorySourceReturnInput, context: TargetMCPRequestContext): InventorySourceReturnRequest {
  const parsed = inventorySourceReturnInputSchema.safeParse(input);
  if (!parsed.success) return fail();
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = `source-return-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`;
  const { projectId, items } = parsed.data.payload;
  const createdAtMs = parsed.data.clientCreatedAtMilliseconds;
  const commandJSON = canonicalJSON({ operationId, accountId, actorPrincipalId, projectId,
    contractVersion: "return-inventory-to-source-v1", createdAtMs: String(createdAtMs), items }, "source_return_payload_invalid");
  return { operationId, accountId, actorPrincipalId, projectId, createdAtMs, commandJSON,
    fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
const rejections = new Set(["source_return_duplicate_item", "source_return_destination_unavailable", "source_return_item_invalid",
  "source_return_item_unavailable", "source_return_placement_stale", "source_return_entry_unavailable", "source_return_integrity_conflict"]);
export function validateInventorySourceReturnResult(value: unknown, request: InventorySourceReturnRequest) {
  const mismatch = () => fail("source_return_server_result_mismatch");
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const row = value as Record<string, unknown>;
  if (row.operation_id !== request.operationId || row.account_id !== request.accountId
    || row.actor_principal_id !== request.actorPrincipalId || row.subject_id !== request.projectId
    || row.command_type !== "return_inventory_to_source" || row.contract_version !== "return-inventory-to-source-v1"
    || row.command_fingerprint !== request.fingerprint || row.envelope_sha256 !== request.fingerprint
    || row.request_sha256 != null || row.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(row.server_received_at_ms) || !Number.isSafeInteger(row.completed_at_ms)
    || (row.server_received_at_ms as number) < 0 || (row.completed_at_ms as number) < (row.server_received_at_ms as number)) return mismatch();
  if (!(row.phase === "applied" && row.result_code === "inventory_items_returned_to_source" && row.error_code === null)
    && !(row.phase === "rejected" && row.result_code === null && typeof row.error_code === "string" && rejections.has(row.error_code))) return mismatch();
  return { operationId: request.operationId, phase: row.phase as "applied" | "rejected",
    resultCode: row.result_code as string | null, errorCode: row.error_code as string | null };
}
export async function inventorySourceReturnTool(input: InventorySourceReturnInput, context: TargetMCPRequestContext, service: InventorySourceReturnServing) {
  userCredential(context.accessToken);
  const request = makeInventorySourceReturnRequest(input, context);
  return validateInventorySourceReturnResult(await service.applySourceReturn(request, context), request);
}
export async function inventorySourceReturnReviewTool(input: InventorySourceReturnReviewInput, context: TargetMCPRequestContext, service: InventorySourceReturnServing) {
  userCredential(context.accessToken);
  const parsed = inventorySourceReturnReviewInputSchema.safeParse(input);
  if (!parsed.success) return fail();
  return validateInventorySourceReturnReview(await service.reviewSourceReturn(parsed.data, context), parsed.data, context);
}
