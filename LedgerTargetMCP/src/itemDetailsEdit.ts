import { z } from "zod";
import { createHash } from "node:crypto";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "item_edit_invalid"); return true; } catch { return false; }
});
const revision = z.string().refine(value => /^[1-9][0-9]*$/.test(value)
  && value.length <= 19 && BigInt(value) < 9223372036854775807n);
const text = z.string().refine(value => !value.includes("\0")).nullable();
const marketValue = z.object({
  minorUnits: z.string().refine(value => /^(0|[1-9][0-9]*)$/.test(value)
    && value.length <= 19 && BigInt(value) <= 9223372036854775807n),
  currency: z.string().regex(/^[A-Z]{3}$/),
}).strict().nullable();
export const itemDetailsEditInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: z.object({
    items: z.array(z.object({ itemId: identifier, expectedRevision: revision }).strict()).min(1),
    changes: z.object({ name: text.optional(), sku: text.optional(), notes: text.optional(),
      status: z.enum(["to purchase", "purchased", "to return", "returned"]).nullable().optional(),
      bookmark: z.boolean().optional(), marketValue: marketValue.optional() }).strict(),
  }).strict().refine(value => {
    const keys = Object.keys(value.changes).filter(key => value.changes[key as keyof typeof value.changes] !== undefined);
    return keys.length > 0 && new Set(value.items.map(item => item.itemId)).size === value.items.length
      && (value.items.length === 1 || (keys.length === 1 && keys[0] === "status"));
  }),
}).strict();
export type ItemDetailsEditInput = z.infer<typeof itemDetailsEditInputSchema>;
export type ItemDetailsEditRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  itemId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface ItemDetailsEditServing {
  applyItemDetailsEdit(request: ItemDetailsEditRequest, context: TargetMCPRequestContext): Promise<unknown>;
}
export function makeItemDetailsEditRequest(input: ItemDetailsEditInput, context: TargetMCPRequestContext): ItemDetailsEditRequest {
  const parsed = itemDetailsEditInputSchema.safeParse(input);
  if (!parsed.success) throw new TargetMCPFailure("item_edit_invalid");
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = `item-details-edit-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`;
  const commandJSON = canonicalJSON({ ...parsed.data.payload, operationId, accountId, actorPrincipalId,
    contractVersion: parsed.data.payload.changes.marketValue === undefined ? "item-details-edit-v1" : "item-details-edit-v2",
    createdAtMs: String(parsed.data.clientCreatedAtMilliseconds) }, "item_edit_invalid");
  return { operationId, accountId, actorPrincipalId, itemId: parsed.data.payload.items[0]!.itemId,
    createdAtMs: parsed.data.clientCreatedAtMilliseconds, commandJSON,
    fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
const rejections = new Set(["item_edit_unavailable", "item_edit_stale", "item_edit_integrity_conflict"]);
export function validateItemDetailsEditResult(value: unknown, request: ItemDetailsEditRequest) {
  const mismatch = (): never => { throw new TargetMCPFailure("item_edit_result_mismatch"); };
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const row = value as Record<string, unknown>;
  if (row.operation_id !== request.operationId || row.account_id !== request.accountId
    || row.actor_principal_id !== request.actorPrincipalId || row.subject_id !== request.itemId
    || row.command_type !== "edit_item_details" || row.contract_version !== JSON.parse(request.commandJSON).contractVersion
    || row.command_fingerprint !== request.fingerprint || row.envelope_sha256 !== request.fingerprint
    || row.request_sha256 != null || row.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(row.server_received_at_ms) || !Number.isSafeInteger(row.completed_at_ms)
    || (row.server_received_at_ms as number) < 0 || (row.completed_at_ms as number) < (row.server_received_at_ms as number)
    || !((row.phase === "applied" && row.result_code === "item_details_updated" && row.error_code === null)
      || (row.phase === "rejected" && row.result_code === null && typeof row.error_code === "string" && rejections.has(row.error_code)))) return mismatch();
  return { operationId: request.operationId, phase: row.phase as "applied" | "rejected",
    resultCode: row.result_code as string | null, errorCode: row.error_code as string | null };
}
export async function itemDetailsEditTool(input: ItemDetailsEditInput, context: TargetMCPRequestContext, service: ItemDetailsEditServing) {
  userCredential(context.accessToken);
  const request = makeItemDetailsEditRequest(input, context);
  return validateItemDetailsEditResult(await service.applyItemDetailsEdit(request, context), request);
}
