import { z } from "zod";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const id = z.string().refine(value => {
  try { validateIdentifier(value, "invoicing_invalid"); return true; } catch { return false; }
});
const amount = z.string().refine(value => /^-?[1-9][0-9]*$/.test(value)
  && BigInt(value) >= -9223372036854775808n && BigInt(value) <= 9223372036854775807n);
export const projectInvoicingItemsInputSchema = z.object({ projectId: id }).strict();
export type ProjectInvoicingItemsInput = z.infer<typeof projectInvoicingItemsInputSchema>;
const rowSchema = z.object({
  occurrenceId: id, itemId: id, polarity: z.enum(["charge", "credit"]),
  amountMinorUnits: amount, currency: z.string().regex(/^[A-Z]{3}$/),
  availability: z.enum(["available", "created", "sent", "paid"]),
  invoiceId: id.nullable(), invoiceName: z.string().nullable(),
  title: z.string(), categoryId: id.nullable(), categoryName: z.string().nullable(),
}).strict();
const resultSchema = z.object({ accountId: id, principalId: id, projectId: id,
  rows: z.array(rowSchema) }).strict();
export type ProjectInvoicingItemsRead = z.infer<typeof resultSchema>;
export interface ProjectInvoicingItemsReading {
  read(input: ProjectInvoicingItemsInput, context: TargetMCPRequestContext): Promise<ProjectInvoicingItemsRead>;
}

/** Mirrors ProjectInvoicingItems: occurrence identity includes charge/credit kind,
 * never physical location; amounts remain exact signed Int64 strings. */
export function validateProjectInvoicingItems(value: unknown, input: ProjectInvoicingItemsInput,
  context: TargetMCPRequestContext): ProjectInvoicingItemsRead {
  try {
    const request = projectInvoicingItemsInputSchema.parse(input), result = resultSchema.parse(value);
    if (result.accountId !== context.accountId || result.principalId !== context.principalId
      || result.projectId !== request.projectId) throw new Error();
    const identities = new Set<string>();
    for (const row of result.rows) {
      const identity = `${row.polarity}:${row.occurrenceId}`;
      if (identities.has(identity) || (BigInt(row.amountMinorUnits) > 0n) !== (row.polarity === "charge")) throw new Error();
      identities.add(identity);
      if (row.availability === "available") {
        if (row.invoiceId !== null || row.invoiceName !== null) throw new Error();
      } else if (row.invoiceId === null) throw new Error();
    }
    return result;
  } catch { throw new TargetMCPFailure("invoicing_server_result_mismatch"); }
}

export class SupabaseProjectInvoicingItemsReader implements ProjectInvoicingItemsReading {
  readonly #url: URL;
  constructor(url: URL, readonly key: string, readonly fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("invoicing_configuration_invalid");
    }
    userCredential(key);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/spike_read_project_invoicing_items`);
  }
  async read(input: ProjectInvoicingItemsInput, context: TargetMCPRequestContext): Promise<ProjectInvoicingItemsRead> {
    const request = projectInvoicingItemsInputSchema.safeParse(input);
    if (!request.success) throw new TargetMCPFailure("invoicing_invalid");
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.fetchImplementation(this.#url, { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(15_000), headers: { "Content-Type": "application/json", Accept: "application/json",
        apikey: this.key, Authorization: `Bearer ${context.accessToken}` },
      body: JSON.stringify({ p_account_id: context.accountId, p_project_id: request.data.projectId }) });
    if (!response.ok) throw new TargetMCPFailure("invoicing_request_rejected", response.status);
    let value: unknown;
    try { value = await response.json(); } catch { throw new TargetMCPFailure("invoicing_server_result_mismatch"); }
    return validateProjectInvoicingItems(value, request.data, context);
  }
}
