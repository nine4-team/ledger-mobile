import { z } from "zod";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";
import { invoiceSchema, validateFrozenInvoice } from "./transactionPaymentContents.js";

const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "invoice_payload_invalid"); return true; } catch { return false; }
});
export const collectedInvoiceInputSchema = z.object({ projectId: identifier, invoiceId: identifier }).strict();
export type CollectedInvoiceInput = z.infer<typeof collectedInvoiceInputSchema>;
export type CollectedInvoice = z.infer<typeof invoiceSchema>;
export interface CollectedInvoiceReading {
  read(input: CollectedInvoiceInput, context: TargetMCPRequestContext): Promise<CollectedInvoice>;
}
export function validateCollectedInvoice(value: unknown, input: CollectedInvoiceInput,
  context: TargetMCPRequestContext): CollectedInvoice {
  try {
    const request = collectedInvoiceInputSchema.parse(input), invoice = invoiceSchema.parse(value);
    if (invoice.invoice_id !== request.invoiceId) throw new Error("Invoice mismatch");
    validateFrozenInvoice(invoice, { accountId: context.accountId, projectId: request.projectId,
      clientId: invoice.client_id, transactionId: invoice.purchase_id, currency: invoice.currency });
    return invoice;
  } catch { throw new TargetMCPFailure("invoice_server_result_mismatch"); }
}
export class SupabaseCollectedInvoiceReader implements CollectedInvoiceReading {
  readonly #url: URL;
  constructor(url: URL, readonly key: string, readonly fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("invoice_configuration_invalid");
    }
    userCredential(key);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/spike_read_collected_invoice`);
  }
  async read(input: CollectedInvoiceInput, context: TargetMCPRequestContext): Promise<CollectedInvoice> {
    const request = collectedInvoiceInputSchema.safeParse(input);
    if (!request.success) throw new TargetMCPFailure("invoice_payload_invalid");
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.fetchImplementation(this.#url, { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(15_000), headers: { "Content-Type": "application/json", Accept: "application/json",
        apikey: this.key, Authorization: `Bearer ${context.accessToken}` },
      body: JSON.stringify({ p_account_id: context.accountId, p_project_id: request.data.projectId,
        p_invoice_id: request.data.invoiceId }) });
    if (!response.ok) throw new TargetMCPFailure("invoice_request_rejected", response.status);
    let value: unknown;
    try { value = await response.json(); } catch { throw new TargetMCPFailure("invoice_server_result_mismatch"); }
    return validateCollectedInvoice(value, request.data, context);
  }
}
