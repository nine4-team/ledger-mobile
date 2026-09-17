import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { receiptLineInputSchema } from "./expenseCreation.js";
import { userCredential } from "./categoryManagement.js";

const invalid = "transaction_receipt_edit_invalid";
const identifier = z.string().refine(value => {
  try { validateIdentifier(value, invalid); return true; } catch { return false; }
});
const lines = z.array(receiptLineInputSchema).refine(value => new Set(value.map(line => line.id)).size === value.length
  && value.every(line => !line.description.includes("\0")));
export const transactionReceiptLinesEditInputSchema = z.object({
  operationUUID: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload: z.object({ transactionId: identifier, scopeKind: z.enum(["project", "business_inventory"]),
    projectId: identifier.nullable(), clientId: identifier.nullable(), currency: z.string().regex(/^[A-Z]{3}$/),
    expectedLines: lines, lines }).strict().refine(value =>
      (value.scopeKind === "project" ? value.projectId !== null && value.clientId !== null
        : value.projectId === null && value.clientId === null)
      && [...value.expectedLines, ...value.lines].every(line => line.currency === value.currency)),
}).strict();
export type TransactionReceiptLinesEditInput = z.infer<typeof transactionReceiptLinesEditInputSchema>;
export type TransactionReceiptLinesEditRequest = Readonly<{ operationId: string; accountId: string; actorPrincipalId: string;
  transactionId: string; createdAtMs: number; commandJSON: string; fingerprint: string }>;
export interface TransactionReceiptLinesEditServing {
  applyTransactionReceiptLinesEdit(request: TransactionReceiptLinesEditRequest, context: TargetMCPRequestContext): Promise<unknown>;
}
export function makeTransactionReceiptLinesEditRequest(input: TransactionReceiptLinesEditInput,
  context: TargetMCPRequestContext): TransactionReceiptLinesEditRequest {
  const parsed = transactionReceiptLinesEditInputSchema.safeParse(input);
  if (!parsed.success) throw new TargetMCPFailure(invalid);
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const operationId = validateIdentifier(`transaction-receipt-edit-${createHash("sha256").update(accountId).digest("hex")}-${parsed.data.operationUUID}`, invalid);
  const wireLines = (values: z.infer<typeof receiptLineInputSchema>[]) => {
    const result = values.map(line => ({ id: line.id, description: line.description,
      amountMinorUnits: line.magnitudeMinorUnits, effect: line.effect, quantity: line.quantity }));
    const spacing = result.length === 0 ? 0 : result.length * 10 - 1;
    if (Buffer.byteLength(canonicalJSON(result, invalid), "utf8") + spacing > 262_144) {
      throw new TargetMCPFailure("transaction_receipt_edit_payload_too_large");
    }
    return result;
  };
  const commandJSON = canonicalJSON({ ...parsed.data.payload, expectedLines: wireLines(parsed.data.payload.expectedLines),
    lines: wireLines(parsed.data.payload.lines), operationId, accountId, actorPrincipalId,
    contractVersion: "transaction-receipt-lines-edit-v1", createdAtMs: String(parsed.data.clientCreatedAtMilliseconds) }, invalid);
  if (Buffer.byteLength(commandJSON, "utf8") > 4 * 1024 * 1024) throw new TargetMCPFailure("transaction_receipt_edit_payload_too_large");
  return { operationId, accountId, actorPrincipalId, transactionId: parsed.data.payload.transactionId,
    createdAtMs: parsed.data.clientCreatedAtMilliseconds, commandJSON,
    fingerprint: createHash("sha256").update(commandJSON).digest("hex") };
}
export function validateTransactionReceiptLinesEditResult(value: unknown, request: TransactionReceiptLinesEditRequest) {
  const mismatch = (): never => { throw new TargetMCPFailure("transaction_receipt_edit_result_mismatch"); };
  if (!value || typeof value !== "object" || Array.isArray(value)) return mismatch();
  const r = value as Record<string, unknown>;
  const validRevision = typeof r.receipt_lines_revision === "string"
    && /^[1-9][0-9]*$/.test(r.receipt_lines_revision)
    && BigInt(r.receipt_lines_revision) <= 9223372036854775807n;
  if (r.operation_id !== request.operationId || r.account_id !== request.accountId
    || r.actor_principal_id !== request.actorPrincipalId || r.subject_id !== request.transactionId
    || r.command_type !== "edit_transaction_receipt_lines" || r.contract_version !== "transaction-receipt-lines-edit-v1"
    || r.command_fingerprint !== request.fingerprint || r.envelope_sha256 !== request.fingerprint
    || r.request_sha256 != null || r.client_created_at_ms !== request.createdAtMs
    || !Number.isSafeInteger(r.server_received_at_ms) || !Number.isSafeInteger(r.completed_at_ms)
    || (r.server_received_at_ms as number) < 0 || (r.completed_at_ms as number) < (r.server_received_at_ms as number)
    || !((r.phase === "applied" && r.result_code === "transaction_receipt_lines_updated" && r.error_code === null && validRevision)
      || (r.phase === "rejected" && r.result_code === null && r.receipt_lines_revision == null
        && ["transaction_receipt_edit_stale", "transaction_receipt_edit_integrity_conflict"].includes(r.error_code as string)))) return mismatch();
  return { operationId: request.operationId, phase: r.phase as "applied" | "rejected",
    resultCode: r.result_code as string | null, errorCode: r.error_code as string | null };
}
export async function transactionReceiptLinesEditTool(input: TransactionReceiptLinesEditInput, context: TargetMCPRequestContext,
  service: TransactionReceiptLinesEditServing) {
  userCredential(context.accessToken);
  const request = makeTransactionReceiptLinesEditRequest(input, context);
  return validateTransactionReceiptLinesEditResult(await service.applyTransactionReceiptLinesEdit(request, context), request);
}
