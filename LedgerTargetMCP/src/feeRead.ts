import { z } from "zod";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const identifier = z.string().refine(value => { try { validateIdentifier(value, "fee_payload_invalid"); return true; } catch { return false; } });
const positive = z.string().refine(value => /^[1-9][0-9]{0,18}$/.test(value) && BigInt(value) <= 9223372036854775807n);
export const feeReadInputSchema = z.object({ projectId: identifier }).strict();
export type FeeReadInput = z.infer<typeof feeReadInputSchema>;
const schema = z.object({ accountId: identifier, projectId: identifier, clientId: identifier, canCreate: z.boolean(),
  fees: z.array(z.object({ id: identifier, label: z.string(), amountMinorUnits: positive,
    currency: z.string().regex(/^[A-Z]{3}$/), categoryId: identifier, categoryName: z.string().nullable(),
    revision: positive, status: z.enum(["available", "created", "sent", "paid"]),
    invoiceId: identifier.nullable(), invoiceName: z.string().nullable() }).strict()),
}).strict();
export type FeeSnapshot = z.infer<typeof schema>;
export interface FeeReading { read(input: FeeReadInput, context: TargetMCPRequestContext): Promise<FeeSnapshot>; }
export function validateFees(value: unknown, input: FeeReadInput, context: TargetMCPRequestContext): FeeSnapshot {
  const request = feeReadInputSchema.safeParse(input), result = schema.safeParse(value);
  if (!request.success || !result.success || result.data.accountId !== context.accountId
    || result.data.projectId !== request.data.projectId) throw new TargetMCPFailure("fee_server_result_mismatch");
  const ids = new Set<string>();
  for (const fee of result.data.fees) {
    if (ids.has(fee.id) || (fee.status === "available") !== (fee.invoiceId === null)
      || (fee.status === "available" && fee.invoiceName !== null)
      || (fee.status === "paid" && fee.categoryName !== null)) throw new TargetMCPFailure("fee_server_result_mismatch");
    ids.add(fee.id);
  }
  return result.data;
}
export class SupabaseFeeReader implements FeeReading {
  readonly #url: URL;
  constructor(url: URL, readonly key: string, readonly fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("fee_configuration_invalid");
    }
    userCredential(key);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/spike_read_project_fees`);
  }
  async read(input: FeeReadInput, context: TargetMCPRequestContext): Promise<FeeSnapshot> {
    const parsed = feeReadInputSchema.safeParse(input);
    if (!parsed.success) throw new TargetMCPFailure("fee_payload_invalid");
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.fetchImplementation(this.#url, { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(15000), headers: { "Content-Type": "application/json", Accept: "application/json",
        apikey: this.key, Authorization: `Bearer ${context.accessToken}` },
      body: JSON.stringify({ p_account_id: context.accountId, p_project_id: parsed.data.projectId }) });
    if (!response.ok) throw new TargetMCPFailure("fee_request_rejected", response.status);
    return validateFees(await response.json(), parsed.data, context);
  }
}
