/**
 * Response projections and size budgeting.
 *
 * Every list/search/get response should pass through here so the AI can
 * choose between a compact `summary` (default) and the `full` document,
 * and we can enforce a hard size cap so a single tool call can't blow
 * the context window.
 */

import { z } from "zod";
import type { Transaction, Item, ProtoItem, Project, Invoice } from "../types.js";
import { formatCents } from "./format.js";

/**
 * Default and hard-ceiling sizes (in serialized JSON bytes) for a single
 * tool response. Callers can opt into a larger budget via `responseLimit`
 * on list/search/bulk tools — but never above the hard ceiling.
 */
export const RESPONSE_SIZE_LIMIT_BYTES = 75_000;
export const RESPONSE_SIZE_HARD_CEILING_BYTES = 200_000;

/**
 * Zod schema for the optional `responseLimit` parameter on list/search/bulk tools.
 * Use `z.coerce` so MCP clients that send numbers as strings still validate.
 */
export const ResponseLimitArg = z
  .coerce
  .number()
  .int()
  .positive()
  .max(RESPONSE_SIZE_HARD_CEILING_BYTES)
  .optional()
  .describe(
    `Optional override for the per-response byte budget. Defaults to ${RESPONSE_SIZE_LIMIT_BYTES.toLocaleString()}; hard ceiling ${RESPONSE_SIZE_HARD_CEILING_BYTES.toLocaleString()}. Use only when generating reports — narrow filters and \`fields\` projection are usually a better answer.`
  );

export const ProjectionMode = z.enum(["summary", "full"]).default("summary");
export type ProjectionModeValue = z.infer<typeof ProjectionMode>;

// ── Summary shapes ─────────────────────────────────────────────────────────

export function transactionSummary(tx: Transaction & { id: string }) {
  return {
    id: tx.id,
    type: tx.type ?? "",
    source: tx.source ?? "",
    amount: formatCents(tx.amountCents),
    discount: tx.discount ?? null,
    date: tx.transactionDate ?? "",
    projectId: tx.projectId ?? null,
    budgetCategoryId: tx.budgetCategoryId ?? null,
    purchaseHandling: tx.purchaseHandling ?? null,
    intendedProjectId: tx.intendedProjectId ?? null,
    intendedBudgetCategoryId: tx.intendedBudgetCategoryId ?? null,
    inventoryIntentResolvedAt: tx.inventoryIntentResolvedAt ?? null,
    itemCount: tx.itemIds?.length ?? 0,
    isComplete: tx.isComplete ?? null,
    status: tx.status ?? "",
  };
}

export function itemSummary(item: Item & { id: string }) {
  return {
    id: item.id,
    name: item.name ?? item.description ?? "",
    status: item.status ?? "",
    projectId: item.projectId ?? null,
    spaceId: item.spaceId ?? null,
    transactionId: item.transactionId ?? null,
    purchasePrice: formatCents(item.purchasePriceCents),
    budgetCategoryId: item.budgetCategoryId ?? null,
  };
}

export function quickDraftItemSummary(draft: ProtoItem & { id: string }) {
  const isFromInventory = draft.assignmentHint === "from_inventory"
    || (draft.assignmentHint == null && (draft.isFromInventory ?? draft.sourceHint === "from_inventory"));
  return {
    id: draft.id,
    name: draft.name ?? "",
    status: draft.status ?? "open",
    captureContext: draft.captureContext ?? "",
    projectId: draft.projectId ?? null,
    intendedProjectId: draft.intendedProjectId ?? null,
    transactionId: draft.transactionId ?? null,
    spaceId: draft.spaceId ?? null,
    assignmentHint: draft.assignmentHint ?? (isFromInventory ? "from_inventory" : "undecided"),
    isFromInventory,
    sku: draft.sku ?? "",
    quantity: draft.quantity ?? 1,
    notes: draft.notes ?? "",
    photoCount: draft.photos?.length ?? 0,
    candidateItemId: draft.candidateItemId ?? null,
    convertedItemId: draft.convertedItemId ?? null,
  };
}

export function projectSummary(p: Project & { id: string }) {
  return {
    id: p.id,
    name: p.name || "",
    clientName: p.clientName || "",
    isArchived: p.isArchived,
    budget: formatCents(p.budgetSummary?.totalBudgetCents),
    spent: formatCents(p.budgetSummary?.spentCents),
  };
}

export function invoiceSummary(inv: Invoice & { id: string }) {
  return {
    id: inv.id,
    projectId: inv.projectId ?? null,
    status: inv.status ?? "",
    invoiceNumber: inv.invoiceNumber ?? "",
    total: formatCents(inv.totalCents),
    itemCount: inv.itemIds?.length ?? 0,
    transactionCount: inv.transactionIds?.length ?? 0,
    lineCount: inv.lines?.length ?? 0,
  };
}

// ── Field picker ───────────────────────────────────────────────────────────

/** Return a new object containing only the requested field names. */
export function pickFields<T extends Record<string, unknown>>(
  obj: T,
  fields: string[]
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const f of fields) {
    if (f in obj) out[f] = obj[f];
  }
  return out;
}

// ── Size cap ───────────────────────────────────────────────────────────────

/**
 * Build a size-capped list response. Serializes items one at a time
 * until the byte budget would be exceeded, then stops.
 *
 * When truncated, the response leads with a `_truncationNotice` (first key,
 * so an agent scanning a large payload can't miss it) and a `nextOffset` to
 * resume pagination. If the caller requested `fetchAll`, the notice says so
 * explicitly — the "give me everything" promise was broken, and the agent
 * should either page from `nextOffset` or narrow the filter.
 */
export interface CappedResponse<T> {
  _truncationNotice?: string;
  nextOffset?: number;
  items: T[];
  returnedCount: number;
  totalCount: number;
  truncated: boolean;
}

export function capResponse<T>(
  items: T[],
  options: {
    totalCount?: number;
    limitBytes?: number;
    offset?: number;
    fetchAll?: boolean;
  } = {}
): CappedResponse<T> {
  const limit = options.limitBytes ?? RESPONSE_SIZE_LIMIT_BYTES;
  const total = options.totalCount ?? items.length;
  const baseOffset = options.offset ?? 0;
  const kept: T[] = [];
  let bytes = 0;

  for (const item of items) {
    const s = JSON.stringify(item);
    if (bytes + s.length > limit && kept.length > 0) break;
    bytes += s.length;
    kept.push(item);
  }

  const truncated = kept.length < items.length || total > items.length;

  if (!truncated) {
    return {
      items: kept,
      returnedCount: kept.length,
      totalCount: total,
      truncated: false,
    };
  }

  const nextOffset = baseOffset + kept.length;
  const narrowHint =
    `Narrow the filter (by project, status, hasImages, etc.), pass \`fields: [...]\` to slim each row, or raise \`responseLimit\` (max ${RESPONSE_SIZE_HARD_CEILING_BYTES.toLocaleString()}).`;
  const notice = options.fetchAll
    ? `fetchAll requested, but the response hit the ${limit.toLocaleString()}-byte budget before all items fit. Returned ${kept.length} of ${total} matching items. Continue with offset=${nextOffset}, or ${narrowHint.charAt(0).toLowerCase() + narrowHint.slice(1)}`
    : `Response truncated at the ${limit.toLocaleString()}-byte budget. Returned ${kept.length} items starting at offset ${baseOffset}. Continue with offset=${nextOffset}. ${narrowHint}`;

  // `_truncationNotice` and `nextOffset` are emitted first on purpose:
  // JSON.stringify preserves key insertion order, so they land at the top
  // of the payload where an agent is far less likely to scan past them.
  return {
    _truncationNotice: notice,
    nextOffset,
    items: kept,
    returnedCount: kept.length,
    totalCount: total,
    truncated: true,
  };
}

/** Serialize a capped list response to MCP tool text content. */
export function asToolResponse(payload: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(payload, null, 2) }] };
}
