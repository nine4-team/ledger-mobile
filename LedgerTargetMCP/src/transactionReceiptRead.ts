import { z } from "zod";
import { calculateItemAdjustments } from "./liveItemAdjustments.js";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { credential, validateReportConfiguration } from "./propertyManagementReportRead.js";

const integer = z.string().regex(/^(0|[1-9][0-9]*)$/).refine(v => BigInt(v) <= 9223372036854775807n);
const positive = integer.refine(v => BigInt(v) > 0n);
const identifier = z.string().refine(v => {
  try { validateIdentifier(v, "invalid"); return true; } catch { return false; }
});
const line = z.object({ id: identifier, description: z.string().refine(v => v.trim().length > 0),
  amountMinorUnits: positive, effect: z.enum(["increase", "decrease"]),
  quantity: z.string().regex(/^-?(0|[1-9][0-9]*)$/)
    .refine(v => BigInt(v) >= -9223372036854775808n && BigInt(v) <= 9223372036854775807n).nullable().optional(),
}).strict();
export const receiptSchema = z.object({
  requiresLiveAdjustments: z.boolean().optional(),
  liveAdjustments: z.object({ totalMinorUnits: z.string(), adjustmentsMinorUnits: z.string(),
    differenceNumerator: z.string().nullable(), differenceDenominator: z.string().nullable(),
    isBalanced: z.boolean(), isProvisional: z.boolean(),
    items: z.array(z.object({ itemId: identifier, numerator: z.string().nullable(), denominator: z.string().nullable(),
      requestedProjectPriceMinorUnits: z.string().nullable().optional(), unadjustedMinorUnits: z.string().nullable(),
      adjustmentsMinorUnits: z.string().nullable(), projectPriceMinorUnits: z.string().nullable(),
      issue: z.enum(["unknownInput", "nonpositiveBase", "zeroFactor", "arithmeticRange"]).nullable() }).strict()),
  }).strict().nullable().optional(),
  accountId: identifier, principalId: identifier, transactionId: identifier,
  scopeKind: z.enum(["project", "business_inventory"]), projectId: identifier.nullable(), clientId: identifier.nullable(),
  type: z.enum(["purchase", "return"]), amountMinorUnits: integer, currency: z.string().regex(/^[A-Z]{3}$/),
  category: z.object({ id: identifier, name: z.string().min(1), kind: z.enum(["general", "itemized", "fee"]), revision: positive }).strict(),
  nonItemReceiptLines: z.array(line),
  items: z.array(z.object({ itemId: identifier, amountMinorUnits: integer.nullable(),
    name: z.string().nullable().optional(), sku: z.string().nullable().optional(),
    source: z.string().nullable().optional(), currentSource: z.string().nullable().optional(),
    currentSpaceName: z.string().nullable().optional(), imageCount: integer.nullable().optional(),
    membershipKind: z.enum(["linked", "returned", "sold"]) }).strict()),
}).strict();

function exact(value: bigint): bigint {
  if (value < -9223372036854775808n || value > 9223372036854775807n) throw new Error("overflow");
  return value;
}

/** Same exact arithmetic as TransactionReceiptReconstruction. This consumes one
 * complete server snapshot; it must not label partial PowerSync rows complete. */
export function transactionReceiptAudit(value: unknown, transactionId: string, context: TargetMCPRequestContext) {
  try {
    const receipt = receiptSchema.parse(value);
    if (receipt.accountId !== context.accountId || receipt.principalId !== context.principalId
      || receipt.transactionId !== transactionId
      || (receipt.amountMinorUnits === "0" && (receipt.type !== "purchase" || !receipt.requiresLiveAdjustments))
      || (receipt.scopeKind === "project" ? receipt.projectId === null || receipt.clientId === null
        : receipt.projectId !== null || receipt.clientId !== null)) throw new Error("scope mismatch");
    if (new Set(receipt.items.map(i => i.itemId)).size !== receipt.items.length
      || new Set(receipt.nonItemReceiptLines.map(l => l.id)).size !== receipt.nonItemReceiptLines.length) throw new Error("duplicate evidence");
    let increase = 0n, decrease = 0n;
    for (const line of receipt.nonItemReceiptLines) {
      if (line.effect === "increase") increase = exact(increase + BigInt(line.amountMinorUnits));
      else decrease = exact(decrease + BigInt(line.amountMinorUnits));
    }
    const net = exact(increase - decrease);
    if (receipt.requiresLiveAdjustments) {
      const allocation = receipt.liveAdjustments;
      const coherent = allocation && allocation.totalMinorUnits === receipt.amountMinorUnits
        && allocation.adjustmentsMinorUnits === net.toString()
        && allocation.items.length === receipt.items.length
        && allocation.items.every(item => receipt.items.some(source => source.itemId === item.itemId));
      const result = coherent ? calculateItemAdjustments(BigInt(receipt.amountMinorUnits), net, allocation.items) : null;
      if (result && allocation && (result.differenceNumerator !== allocation.differenceNumerator
        || result.differenceDenominator !== allocation.differenceDenominator || result.isBalanced !== allocation.isBalanced
        || result.items.some(item => {
          const reported = allocation.items.find(row => row.itemId === item.itemId)!;
          return item.projectPriceMinorUnits !== reported.projectPriceMinorUnits
            || item.unadjustedMinorUnits !== reported.unadjustedMinorUnits || item.issue !== reported.issue
            || item.adjustmentsMinorUnits !== reported.adjustmentsMinorUnits;
        }))) throw new Error("calculation mismatch");
      const known = result?.differenceNumerator !== null && result?.differenceNumerator !== undefined;
      const difference = known && result?.differenceDenominator === "1" ? result.differenceNumerator : null;
      const subtotal = difference === null ? null : (BigInt(receipt.amountMinorUnits) - net - BigInt(difference)).toString();
      return { ...receipt, audit: { status: receipt.category.kind !== "itemized" ? "notApplicable"
        : !known ? "incompleteEvidence" : result!.isBalanced ? "balanced" : "mismatch",
        physicalItemTotalMinorUnits: subtotal, lineIncreaseMinorUnits: increase.toString(),
        lineDecreaseMinorUnits: decrease.toString(), lineNetMinorUnits: net.toString(),
        reconstructedTotalMinorUnits: difference === null ? null : (BigInt(receipt.amountMinorUnits) - BigInt(difference)).toString(),
        varianceMinorUnits: difference, differenceNumerator: result?.differenceNumerator ?? null,
        differenceDenominator: result?.differenceDenominator ?? null } } as const;
    }
    let items = 0n;
    for (const item of receipt.items) if (item.amountMinorUnits !== null) items = exact(items + BigInt(item.amountMinorUnits));
    const known = receipt.items.every(i => i.amountMinorUnits !== null);
    const reconstructed = known ? exact(items + net) : null;
    const variance = reconstructed === null ? null : exact(reconstructed - BigInt(receipt.amountMinorUnits));
    const status = receipt.category.kind !== "itemized" ? "notApplicable"
      : variance === null ? "incompleteEvidence" : variance === 0n ? "balanced" : "mismatch";
    return { ...receipt, audit: { status, physicalItemTotalMinorUnits: known ? items.toString() : null,
      lineIncreaseMinorUnits: increase.toString(), lineDecreaseMinorUnits: decrease.toString(),
      lineNetMinorUnits: net.toString(), reconstructedTotalMinorUnits: reconstructed?.toString() ?? null,
      varianceMinorUnits: variance?.toString() ?? null } } as const;
  } catch { throw new TargetMCPFailure("transaction_receipt_server_result_mismatch"); }
}
export type TransactionReceiptAudit = ReturnType<typeof transactionReceiptAudit>;
export interface TransactionReceiptReading {
  read(input: Readonly<{ transactionId: string }>, context: TargetMCPRequestContext): Promise<TransactionReceiptAudit>;
}

export class SupabaseTransactionReceiptReader implements TransactionReceiptReading {
  readonly #url: URL;
  constructor(url: URL, private readonly key: string, private readonly fetcher: typeof fetch = fetch) {
    validateReportConfiguration(url, key, "transaction_receipt_configuration_invalid");
    this.#url = new URL("/rest/v1/rpc/spike_read_transaction_receipt", url);
  }
  async read(input: Readonly<{ transactionId: string }>, context: TargetMCPRequestContext): Promise<TransactionReceiptAudit> {
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    validateIdentifier(input.transactionId, "transaction_receipt_invalid_identifier");
    if (!credential(context.accessToken, "authenticated")) throw new TargetMCPFailure("authentication_required");
    let response: Response;
    try {
      response = await this.fetcher(this.#url, { method: "POST", redirect: "error", signal: AbortSignal.timeout(30_000),
        headers: { apikey: this.key, Authorization: `Bearer ${context.accessToken}`, Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify({ p_account_id: context.accountId, p_transaction_id: input.transactionId }) });
    } catch { throw new TargetMCPFailure("transaction_receipt_transport_failed"); }
    if (!response.ok) throw new TargetMCPFailure(response.status === 401 ? "authentication_required"
      : response.status === 403 ? "transaction_not_available" : "transaction_receipt_read_failed", response.status);
    try { return transactionReceiptAudit(await response.json(), input.transactionId, context); }
    catch { throw new TargetMCPFailure("transaction_receipt_server_result_mismatch"); }
  }
}
