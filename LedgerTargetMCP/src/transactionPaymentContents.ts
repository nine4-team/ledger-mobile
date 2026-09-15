import { z } from "zod";
import { validateIdentifier } from "./contractSupport.js";

const minimum = -9223372036854775808n, maximum = 9223372036854775807n;
const identifier = z.string().refine(value => {
  try { validateIdentifier(value, "invalid"); return true; } catch { return false; }
});
const integer = z.string().regex(/^-?(0|[1-9][0-9]*)$/).refine(value => value !== "-0"
  && BigInt(value) >= minimum && BigInt(value) <= maximum);
const positive = integer.refine(value => BigInt(value) > 0n);
const lineSchema = z.object({ id: identifier, line_position: z.number().int().nonnegative().safe(),
  source_kind: z.enum(["item", "expense", "fee_installment"]), source_id: identifier,
  item_id: identifier.nullable(), source_revision: positive, category_id: identifier,
  signed_amount_minor_units: integer, description: z.string().refine(value => !value.includes("\0")),
  source_snapshot_json: z.string(),
}).strict();
const invoiceTimestamp = z.string().refine(value => /^(0|-?[1-9][0-9]*)$/.test(value)
  && BigInt(value) >= -62135596800000n && BigInt(value) <= 253402300799999n);
const invoiceText = z.string().refine(value => !value.includes("\0"));
export const invoiceDisplayMetadataSchema = z.object({
  invoiceNumber: invoiceText.nullable().optional(), notes: invoiceText.nullable().optional(),
  issuedAtMilliseconds: invoiceTimestamp.nullable().optional(), sentAtMilliseconds: invoiceTimestamp.nullable().optional(),
  paidAtMilliseconds: invoiceTimestamp.nullable().optional(), canceledAtMilliseconds: invoiceTimestamp.nullable().optional(),
  voidedAtMilliseconds: invoiceTimestamp.nullable().optional(),
}).strict();
export const invoiceSchema = z.object({ invoice_id: identifier, invoice_revision: positive,
  account_id: identifier, project_id: identifier, client_id: identifier, purchase_id: identifier,
  currency: z.string().regex(/^[A-Z]{3}$/), total_minor_units: positive,
  lines: z.array(lineSchema).min(1), display_metadata: invoiceDisplayMetadataSchema.nullable().optional(),
}).strict();
export const paymentContentsSchema = z.object({
  accountId: identifier, principalId: identifier, transactionId: identifier, projectId: identifier, clientId: identifier,
  connections: z.array(z.object({ id: identifier, itemId: identifier, placementId: identifier,
    endedAt: z.string().min(1).nullable().optional() }).strict()),
  invoice: invoiceSchema.nullable().optional(),
  items: z.array(z.object({ itemId: identifier, name: z.string().nullable().optional(),
    sku: z.string().nullable().optional(), source: z.string().nullable().optional(),
    currentSource: z.string().nullable().optional(), currentSpaceName: z.string().nullable().optional(),
    imageCount: integer.refine(value => BigInt(value) >= 0n).nullable().optional(),
  }).strict()).nullable().optional(),
}).strict();

function exact(value: bigint): bigint {
  if (value < minimum || value > maximum) throw new Error("frozen amount overflow");
  return value;
}

// JSON source is retained as text on the wire. Node 24's reviver source also
// lets validation inspect embedded Int64 values without a lossy Number hop.
// Accept equivalent integral JSON spellings, as Swift's Int64 decoder does.
function jsonInteger(raw: string): bigint {
  const match = /^(-?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$/.exec(raw);
  if (!match) throw new Error("invalid frozen number");
  const digits = match[2] + (match[3] ?? "");
  if (/^0+$/.test(digits)) return 0n;
  const point = match[2].length + Number(match[4] ?? "0");
  if (!Number.isSafeInteger(point) || point <= 0) throw new Error("nonintegral frozen number");
  if (point < digits.length && /[1-9]/.test(digits.slice(point))) throw new Error("nonintegral frozen number");
  const whole = digits.slice(0, point).replace(/^0+/, "");
  const zeroes = Math.max(0, point - digits.length);
  if (whole.length + zeroes > 19) throw new Error("frozen amount overflow");
  return exact(BigInt(match[1] + (whole || "0") + "0".repeat(zeroes)));
}
function frozenSource(raw: string): any {
  return JSON.parse(raw, (_key: string, value: unknown, context?: { source?: string }) => {
    if (typeof value !== "number") return value;
    if (context?.source) return jsonInteger(context.source);
    if (Number.isSafeInteger(value)) return exact(BigInt(value));
    throw new Error("Exact frozen JSON validation requires Node 24");
  });
}
function sourceIdentity(line: z.infer<typeof lineSchema>, currency: string): void {
  const source = frozenSource(line.source_snapshot_json);
  if (!source || typeof source !== "object" || Array.isArray(source) || Object.keys(source).length !== 1) {
    throw new Error("invalid frozen source");
  }
  if (line.source_kind === "item") {
    const item = source.item, price = item?.price;
    if (line.item_id === null || item?.itemId !== line.item_id || item?.occurrenceId !== line.source_id || !price
      || price.amount?.currency !== currency || typeof price.amount?.minorUnits !== "bigint"
      || price.amount.minorUnits !== (BigInt(line.signed_amount_minor_units) < 0n
        ? -BigInt(line.signed_amount_minor_units) : BigInt(line.signed_amount_minor_units))) throw new Error("frozen Item mismatch");
    const basis = price.basis;
    if (!basis || typeof basis !== "object" || Array.isArray(basis) || Object.keys(basis).length !== 1) throw new Error("invalid price basis");
    if ("projectPrice" in basis) {
      if (!basis.projectPrice || typeof basis.projectPrice !== "object" || Array.isArray(basis.projectPrice)) throw new Error("invalid price basis");
    } else if ("purchaseCost" in basis) identifier.parse(basis.purchaseCost?.acquisitionId);
    else if ("paidInvoiceLine" in basis) {
      identifier.parse(basis.paidInvoiceLine?.invoiceId); identifier.parse(basis.paidInvoiceLine?.lineId);
    } else if ("inventoryEntry" in basis) identifier.parse(basis.inventoryEntry?.entryId);
    else throw new Error("unknown price basis");
  } else if (line.item_id !== null || (line.source_kind === "expense"
      ? source.expense?.expenseId !== line.source_id : source.feeInstallment?.installmentId !== line.source_id)) {
    throw new Error("frozen source mismatch");
  }
}

export function validatePaymentContents(value: z.infer<typeof paymentContentsSchema>, binding: {
  accountId: string; principalId: string; transactionId: string; projectId: string | null; clientId: string | null; currency: string;
}): void {
  for (const key of ["accountId", "principalId", "transactionId", "projectId", "clientId"] as const) {
    if (value[key] !== binding[key]) throw new Error("payment scope mismatch");
  }
  if (new Set(value.connections.map(link => link.id)).size !== value.connections.length) throw new Error("duplicate payment link");
  const invoice = value.invoice;
  if (value.items) {
    const ids = new Set(value.connections.map(link => link.itemId));
    for (const line of invoice?.lines ?? []) if (line.item_id !== null) ids.add(line.item_id);
    if (value.items.length !== ids.size || new Set(value.items.map(item => item.itemId)).size !== ids.size
      || value.items.some(item => !ids.has(item.itemId))) throw new Error("payment Item metadata membership mismatch");
  }
  if (!invoice) return;
  validateFrozenInvoice(invoice, binding);
}

export function validateFrozenInvoice(invoice: z.infer<typeof invoiceSchema>, binding: {
  accountId: string; projectId: string | null; clientId: string | null; transactionId: string; currency: string;
}): void {
  if (invoice.account_id !== binding.accountId || invoice.project_id !== binding.projectId
    || invoice.client_id !== binding.clientId || invoice.purchase_id !== binding.transactionId
    || invoice.currency !== binding.currency) throw new Error("frozen Invoice scope mismatch");
  const ids = new Set<string>(), sources = new Set<string>(), categories = new Map<string, bigint>();
  let total = 0n;
  const lines = [...invoice.lines].sort((a, b) => a.line_position - b.line_position);
  for (const [position, line] of lines.entries()) {
    const source = `${line.source_kind}\0${line.source_id}`;
    if (line.line_position !== position || ids.has(line.id) || sources.has(source)) throw new Error("duplicate or unordered frozen line");
    ids.add(line.id); sources.add(source); sourceIdentity(line, invoice.currency);
    const amount = BigInt(line.signed_amount_minor_units);
    total = exact(total + amount);
    categories.set(line.category_id, exact((categories.get(line.category_id) ?? 0n) + amount));
  }
  if (total !== BigInt(invoice.total_minor_units)) throw new Error("frozen Invoice total mismatch");
  // The retained Invoice total is not an invented allocation of payment cash.
  // O-033's migration/collection equality policy is not decided by this reader.
}
