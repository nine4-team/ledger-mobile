import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "transaction_edit_invalid"); return true; } catch { return false; }
});
const text = z.string().refine(value => !value.includes("\0")).nullable();
const revision = z.string().refine(value => /^[1-9][0-9]*$/.test(value) && value.length <= 19
  && BigInt(value) < 9223372036854775807n && BigInt(value).toString() === value);
export const transactionDetailsEditInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: z.object({ transactionId: identifier, scopeKind: z.enum(["project", "business_inventory"]),
    projectId: identifier.nullable(), clientId: identifier.nullable(), expectedRevision: revision,
    changes: z.object({ source: text.optional(), notes: text.optional(), paymentMethod: text.optional(),
      hasEmailReceipt: z.boolean().optional() }).strict(),
  }).strict().refine(value => Object.values(value.changes).some(field => field !== undefined)
    && (value.scopeKind === "project" ? value.projectId !== null && value.clientId !== null
      : value.projectId === null && value.clientId === null)),
}).strict();
export type TransactionDetailsEditInput = z.infer<typeof transactionDetailsEditInputSchema>;
export type TransactionDetailsEditRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  transactionId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface TransactionDetailsEditServing {
  applyTransactionDetailsEdit(request: TransactionDetailsEditRequest, context: TargetMCPRequestContext): Promise<unknown>;
}
export function makeTransactionDetailsEditRequest(input: TransactionDetailsEditInput, context: TargetMCPRequestContext): TransactionDetailsEditRequest {
  const parsed = transactionDetailsEditInputSchema.safeParse(input);
  if (!parsed.success) throw new TargetMCPFailure("transaction_edit_invalid");
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = `transaction-details-edit-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`;
  const commandJSON = canonicalJSON({ ...parsed.data.payload, operationId, accountId, actorPrincipalId,
    contractVersion: "transaction-details-edit-v1", createdAtMs: String(parsed.data.clientCreatedAtMilliseconds) }, "transaction_edit_invalid");
  if (Buffer.byteLength(commandJSON, "utf8") > 4 * 1024 * 1024) {
    throw new TargetMCPFailure("transaction_edit_payload_too_large");
  }
  return { operationId, accountId, actorPrincipalId, transactionId: parsed.data.payload.transactionId,
    createdAtMs: parsed.data.clientCreatedAtMilliseconds, commandJSON,
    fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
const rejections = new Set(["transaction_edit_stale", "transaction_edit_integrity_conflict"]);
export function validateTransactionDetailsEditResult(value: unknown, request: TransactionDetailsEditRequest) {
  const mismatch = (): never => { throw new TargetMCPFailure("transaction_edit_result_mismatch"); };
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const row = value as Record<string, unknown>;
  if (row.operation_id !== request.operationId || row.account_id !== request.accountId
    || row.actor_principal_id !== request.actorPrincipalId || row.subject_id !== request.transactionId
    || row.command_type !== "edit_transaction_details" || row.contract_version !== "transaction-details-edit-v1"
    || row.command_fingerprint !== request.fingerprint || row.envelope_sha256 !== request.fingerprint
    || row.request_sha256 != null || row.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(row.server_received_at_ms) || !Number.isSafeInteger(row.completed_at_ms)
    || (row.server_received_at_ms as number) < 0 || (row.completed_at_ms as number) < (row.server_received_at_ms as number)
    || !((row.phase === "applied" && row.result_code === "transaction_details_updated" && row.error_code === null)
      || (row.phase === "rejected" && row.result_code === null && typeof row.error_code === "string" && rejections.has(row.error_code)))) return mismatch();
  return { operationId: request.operationId, phase: row.phase as "applied" | "rejected",
    resultCode: row.result_code as string | null, errorCode: row.error_code as string | null };
}
export async function transactionDetailsEditTool(input: TransactionDetailsEditInput, context: TargetMCPRequestContext,
                                               service: TransactionDetailsEditServing) {
  userCredential(context.accessToken);
  const request = makeTransactionDetailsEditRequest(input, context);
  return validateTransactionDetailsEditResult(await service.applyTransactionDetailsEdit(request, context), request);
}
