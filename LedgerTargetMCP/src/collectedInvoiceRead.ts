import { z } from "zod";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";
import { invoiceSchema, validateFrozenInvoice } from "./transactionPaymentContents.js";

const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "invoice_payload_invalid"); return true; } catch { return false; }
});
export const collectedInvoiceInputSchema = z.object({ projectId: identifier, invoiceId: identifier }).strict();
export const collectedInvoiceListInputSchema = collectedInvoiceInputSchema.pick({ projectId: true });
export type CollectedInvoiceListInput = z.infer<typeof collectedInvoiceListInputSchema>;
export type CollectedInvoiceInput = z.infer<typeof collectedInvoiceInputSchema>;
export type CollectedInvoice = z.infer<typeof invoiceSchema>;
export interface CollectedInvoiceReading {
  list?(input: CollectedInvoiceListInput, context: TargetMCPRequestContext): Promise<CollectedInvoice[]>;
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
    return validateCollectedInvoice(await this.request(this.#url, request.data, context), request.data, context);
  }
  async list(input: CollectedInvoiceListInput, context: TargetMCPRequestContext): Promise<CollectedInvoice[]> {
    const request = collectedInvoiceListInputSchema.safeParse(input);
    if (!request.success) throw new TargetMCPFailure("invoice_payload_invalid");
    return validateCollectedInvoiceList(await this.request(new URL("spike_list_project_collected_invoices", this.#url),
      request.data, context), request.data, context);
  }
  private async request(url: URL, input: CollectedInvoiceListInput & { invoiceId?: string }, context: TargetMCPRequestContext): Promise<unknown> {
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.fetchImplementation(url, { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(15_000), headers: { "Content-Type": "application/json", Accept: "application/json",
        apikey: this.key, Authorization: `Bearer ${context.accessToken}` },
      body: JSON.stringify({ p_account_id: context.accountId, p_project_id: input.projectId,
        ...(input.invoiceId === undefined ? {} : { p_invoice_id: input.invoiceId }) }) });
    if (!response.ok) throw new TargetMCPFailure("invoice_request_rejected", response.status);
    let value: unknown;
    try { value = await response.json(); } catch { throw new TargetMCPFailure("invoice_server_result_mismatch"); }
    return value;
  }
}
export function validateCollectedInvoiceList(value: unknown, input: CollectedInvoiceListInput,
  context: TargetMCPRequestContext): CollectedInvoice[] {
  const request = collectedInvoiceListInputSchema.safeParse(input), rows = z.array(invoiceSchema).safeParse(value);
  if (!request.success || !rows.success || new Set(rows.data.map(row => row.invoice_id)).size !== rows.data.length) {
    throw new TargetMCPFailure("invoice_server_result_mismatch");
  }
  return rows.data.map(row => validateCollectedInvoice(row, { ...request.data, invoiceId: row.invoice_id }, context));
}
