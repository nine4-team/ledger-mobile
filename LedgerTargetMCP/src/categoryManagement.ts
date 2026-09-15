import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJSON, TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";

const version = "category-management-v1";
const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "category_payload_invalid"); return true; } catch { return false; }
});
const revision = z.string().refine(value => value.length <= 19 && /^[1-9][0-9]*$/.test(value)
  && BigInt(value) < 9223372036854775807n);
// Match Foundation's whitespacesAndNewlines, including U+200B but not U+FEFF.
const name = z.string().transform(value => value.replace(/^[\p{White_Space}\u200b]+|[\p{White_Space}\u200b]+$/gu, ""))
  .refine(value => value.length > 0 && !/[\p{Cc}\p{Cf}]/u.test(value)
    && [...value].length <= 100);
const definition = { name, kind: z.enum(["general", "itemized", "fee"]), excludesFromOverallBudget: z.boolean() };
const payload = z.discriminatedUnion("action", [
  z.object({ action: z.literal("create"), categoryId: identifier, ...definition }).strict(),
  z.object({ action: z.literal("edit"), categoryId: identifier, expectedRevision: revision, ...definition }).strict(),
  z.object({ action: z.literal("archive"), categoryId: identifier, expectedRevision: revision }).strict(),
  z.object({ action: z.literal("restore"), categoryId: identifier, expectedRevision: revision }).strict(),
  z.object({ action: z.literal("reorder"), order: z.array(z.object({ categoryId: identifier, expectedRevision: revision }).strict())
    .min(1).refine(rows => new Set(rows.map(row => row.categoryId)).size === rows.length) }).strict(),
]);

export const categoryManagementInputSchema = z.object({
  operationUUID: uuid,
  clientCreatedAtMilliseconds: z.number().int().nonnegative().max(999_999_999_999_999),
  payload,
}).strict();
export type CategoryManagementInput = z.input<typeof categoryManagementInputSchema>;
export type CategoryManagementRequest = Readonly<{
  operationId: string; accountId: string; actorPrincipalId: string;
  clientCreatedAtMilliseconds: number; envelopeJSON: string; fingerprint: string;
}>;
export type CategoryManagementResult = Readonly<{
  operationId: string; phase: "applied" | "rejected"; resultCode: string | null; errorCode: string | null;
}>;
export interface CategoryManagementApplying {
  apply(request: CategoryManagementRequest, context: TargetMCPRequestContext): Promise<unknown>;
  read?(context: TargetMCPRequestContext): Promise<CategoryDirectory>;
}

const categoryDirectorySchema = z.object({ accountId: identifier, principalId: identifier, complete: z.literal(true),
  categories: z.array(z.object({ id: identifier, accountId: identifier, name, kind: z.enum(["general", "itemized", "fee"]),
    lifecycle: z.enum(["active", "archived"]), isSystem: z.boolean(), excludesFromOverallBudget: z.boolean(),
    presentationOrder: z.number().int().min(0).max(4294967295),
    revision: z.string().refine(value => value.length <= 19 && /^[1-9][0-9]*$/.test(value)
      && BigInt(value) <= 9223372036854775807n),
  }).strict()),
}).strict();
export type CategoryDirectory = z.output<typeof categoryDirectorySchema>;

export function validateCategoryDirectory(value: unknown, context: TargetMCPRequestContext): CategoryDirectory {
  const parsed = categoryDirectorySchema.safeParse(value);
  if (!parsed.success || parsed.data.accountId !== context.accountId || parsed.data.principalId !== context.principalId) {
    throw new TargetMCPFailure("category_directory_mismatch");
  }
  const rows = parsed.data.categories;
  if (rows.some(row => row.accountId !== context.accountId)
    || new Set(rows.map(row => row.id)).size !== rows.length
    || new Set(rows.map(row => row.name.toLowerCase().normalize("NFC"))).size !== rows.length
    || new Set(rows.map(row => row.presentationOrder)).size !== rows.length
    || rows.some((row, index) => index > 0 && rows[index - 1].presentationOrder >= row.presentationOrder)) {
    throw new TargetMCPFailure("category_directory_mismatch");
  }
  return parsed.data;
}

export function makeCategoryManagementRequest(input: CategoryManagementInput, context: TargetMCPRequestContext): CategoryManagementRequest {
  const parsed = categoryManagementInputSchema.safeParse(input);
  if (!parsed.success) throw new TargetMCPFailure("category_payload_invalid");
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const accountHash = createHash("sha256").update(accountId).digest("hex");
  const operationId = `category-management-${accountHash}-${parsed.data.operationUUID}`;
  const envelopeJSON = canonicalJSON({ accountId, actorPrincipalId, operationId, contractVersion: version,
    clientCreatedAt: parsed.data.clientCreatedAtMilliseconds, payload: parsed.data.payload, preconditions: [] }, "category_payload_invalid");
  return { operationId, accountId, actorPrincipalId, clientCreatedAtMilliseconds: parsed.data.clientCreatedAtMilliseconds,
    envelopeJSON, fingerprint: createHash("sha256").update(envelopeJSON).digest("hex") };
}

const rejectionCodes = new Set(["category_payload_invalid", "category_name_invalid", "category_unavailable",
  "category_order_invalid", "category_protected", "category_revision_conflict", "category_name_unavailable"]);

export function validateCategoryManagementResult(value: unknown, request: CategoryManagementRequest): CategoryManagementResult {
  const fail = (): never => { throw new TargetMCPFailure("category_server_result_mismatch"); };
  if (value === null || typeof value !== "object" || Array.isArray(value)) return fail();
  const result = value as Record<string, unknown>;
  if (result.operation_id !== request.operationId || result.account_id !== request.accountId
    || result.actor_principal_id !== request.actorPrincipalId || result.command_type !== "manage_categories"
    || result.contract_version !== version || result.command_fingerprint !== request.fingerprint
    || result.envelope_sha256 !== request.fingerprint || result.request_sha256 != null
    || result.subject_id !== request.accountId || result.client_created_at_ms !== request.clientCreatedAtMilliseconds
    || !Number.isSafeInteger(result.server_received_at_ms) || !Number.isSafeInteger(result.completed_at_ms)
    || (result.server_received_at_ms as number) < 0
    || (result.completed_at_ms as number) < (result.server_received_at_ms as number)) return fail();
  if (result.phase === "applied" && result.result_code === "categories_updated" && result.error_code === null) {
    return { operationId: request.operationId, phase: "applied", resultCode: "categories_updated", errorCode: null };
  }
  if (result.phase === "rejected" && result.result_code === null && typeof result.error_code === "string"
    && rejectionCodes.has(result.error_code)) {
    return { operationId: request.operationId, phase: "rejected", resultCode: null, errorCode: result.error_code };
  }
  return fail();
}

export function userCredential(value: string): void {
  if (!value.trim() || value.startsWith("sb_secret_")) throw new TargetMCPFailure("category_credential_refused");
  const parts = value.split(".");
  if (parts.length === 3) {
    let role: unknown;
    try { role = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")).role; } catch { /* server validates JWTs */ }
    if (role === "service_role") throw new TargetMCPFailure("category_credential_refused");
  }
}

export async function manageCategoriesTool(input: CategoryManagementInput, context: TargetMCPRequestContext,
  applier: CategoryManagementApplying): Promise<CategoryManagementResult> {
  userCredential(context.accessToken);
  const request = makeCategoryManagementRequest(input, context);
  return validateCategoryManagementResult(await applier.apply(request, context), request);
}

export class SupabaseCategoryManagementApplier implements CategoryManagementApplying {
  readonly #url: URL;
  readonly #key: string;
  readonly #fetch: typeof fetch;
  constructor(url: URL, publishableKey: string, fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("category_configuration_invalid");
    }
    userCredential(publishableKey);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/spike_manage_categories`);
    this.#key = publishableKey;
    this.#fetch = fetchImplementation;
  }
  async apply(request: CategoryManagementRequest, context: TargetMCPRequestContext): Promise<unknown> {
    userCredential(context.accessToken);
    if (request.accountId !== context.accountId || request.actorPrincipalId !== context.principalId) {
      throw new TargetMCPFailure("account_not_authorized");
    }
    const response = await this.#fetch(this.#url, { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(15_000),
      headers: { "Content-Type": "application/json", Accept: "application/vnd.pgrst.object+json",
        apikey: this.#key, Authorization: `Bearer ${context.accessToken}` },
      body: JSON.stringify({ p_envelope_json: request.envelopeJSON }) });
    if (!response.ok) throw new TargetMCPFailure("category_request_rejected", response.status);
    let result: unknown;
    try { result = await response.json(); } catch { throw new TargetMCPFailure("category_server_result_mismatch"); }
    validateCategoryManagementResult(result, request);
    return result;
  }

  async read(context: TargetMCPRequestContext): Promise<CategoryDirectory> {
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.#fetch(new URL("spike_read_budget_categories", this.#url), {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(15_000),
      headers: { "Content-Type": "application/json", Accept: "application/json",
        apikey: this.#key, Authorization: `Bearer ${context.accessToken}` },
      body: JSON.stringify({ p_account_id: context.accountId }),
    });
    if (!response.ok) throw new TargetMCPFailure("category_read_rejected", response.status);
    let result: unknown;
    try { result = await response.json(); } catch { throw new TargetMCPFailure("category_directory_mismatch"); }
    return validateCategoryDirectory(result, context);
  }
}
