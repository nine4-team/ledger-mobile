import { z } from "zod";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const fail = (): never => { throw new TargetMCPFailure("invoice_server_result_mismatch"); };
const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "invoice_payload_invalid"); return true; } catch { return false; }
});
const integer = z.string().refine(value => /^(0|-?[1-9][0-9]*)$/.test(value)
  && value.length <= 20 && BigInt(value) >= -9223372036854775808n && BigInt(value) <= 9223372036854775807n);
const revision = integer.refine(value => /^[1-9][0-9]*$/.test(value));
const currency = z.string().regex(/^[A-Z]{3}$/);
export const liveInvoiceInputSchema = z.object({ projectId: identifier, invoiceId: identifier }).strict();
export type LiveInvoiceInput = z.infer<typeof liveInvoiceInputSchema>;
const snapshot = z.object({ accountId: identifier, projectId: identifier, clientId: identifier,
  invoiceId: identifier, revision, status: z.enum(["created", "sent"]), name: z.string(), notes: z.string(),
  currency, totalMinorUnits: integer,
  lines: z.array(z.object({ kind: z.enum(["item", "expense", "fee_installment"]), sourceId: identifier,
    sourceRevision: revision, amountMinorUnits: integer, currency, categoryId: identifier,
    description: z.string() }).strict()).nonempty(),
}).strict();
export type LiveInvoiceSnapshot = z.infer<typeof snapshot>;
export interface LiveInvoiceReading {
  read(input: LiveInvoiceInput, context: TargetMCPRequestContext): Promise<LiveInvoiceSnapshot>;
}
export function validateLiveInvoice(value: unknown, input: LiveInvoiceInput, context: TargetMCPRequestContext): LiveInvoiceSnapshot {
  const request = liveInvoiceInputSchema.safeParse(input), parsed = snapshot.safeParse(value);
  if (!request.success || !parsed.success) return fail();
  const result = parsed.data;
  if (result.accountId !== context.accountId || result.projectId !== request.data.projectId
    || result.invoiceId !== request.data.invoiceId) return fail();
  const identities = new Set<string>();
  let total = 0n;
  for (const line of result.lines) {
    const identity = JSON.stringify([line.kind, line.sourceId]);
    if (identities.has(identity) || line.currency !== result.currency) return fail();
    identities.add(identity);
    total += BigInt(line.amountMinorUnits);
  }
  if (total !== BigInt(result.totalMinorUnits)) return fail();
  return result;
}

export class SupabaseLiveInvoiceReader implements LiveInvoiceReading {
  readonly #url: URL;
  constructor(url: URL, readonly key: string, readonly fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("invoice_configuration_invalid");
    }
    userCredential(key);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/spike_read_live_invoice`);
  }
  async read(input: LiveInvoiceInput, context: TargetMCPRequestContext): Promise<LiveInvoiceSnapshot> {
    const parsed = liveInvoiceInputSchema.safeParse(input);
    if (!parsed.success) throw new TargetMCPFailure("invoice_payload_invalid");
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.fetchImplementation(this.#url, { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(15_000), headers: { "Content-Type": "application/json", Accept: "application/json",
        apikey: this.key, Authorization: `Bearer ${context.accessToken}` },
      body: JSON.stringify({ p_account_id: context.accountId, p_project_id: parsed.data.projectId, p_invoice_id: parsed.data.invoiceId }) });
    if (!response.ok) throw new TargetMCPFailure("invoice_request_rejected", response.status);
    let value: unknown;
    try { value = await response.json(); } catch { return fail(); }
    return validateLiveInvoice(value, parsed.data, context);
  }
}
