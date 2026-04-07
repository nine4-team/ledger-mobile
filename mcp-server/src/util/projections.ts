/**
 * Response projections and size budgeting.
 *
 * Every list/search/get response should pass through here so the AI can
 * choose between a compact `summary` (default) and the `full` document,
 * and we can enforce a hard size cap so a single tool call can't blow
 * the context window.
 */

import { z } from "zod";
import type { Transaction, Item, Project } from "../types.js";
import { formatCents } from "./format.js";

/** Max serialized bytes for a single tool response before we truncate. */
export const RESPONSE_SIZE_LIMIT_BYTES = 50_000;

export const ProjectionMode = z.enum(["summary", "full"]).default("summary");
export type ProjectionModeValue = z.infer<typeof ProjectionMode>;

// ── Summary shapes ─────────────────────────────────────────────────────────

export function transactionSummary(tx: Transaction & { id: string }) {
  return {
    id: tx.id,
    type: tx.type ?? "",
    source: tx.source ?? "",
    amount: formatCents(tx.amountCents),
    date: tx.transactionDate ?? "",
    projectId: tx.projectId ?? null,
    budgetCategoryId: tx.budgetCategoryId ?? null,
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
 * until the budget would be exceeded, then stops. If truncated, adds
 * `truncated: true` and a hint so the AI knows to narrow the filter.
 */
export function capResponse<T>(
  items: T[],
  options: { totalCount?: number; limitBytes?: number } = {}
): {
  items: T[];
  returnedCount: number;
  totalCount: number;
  truncated: boolean;
  hint?: string;
} {
  const limit = options.limitBytes ?? RESPONSE_SIZE_LIMIT_BYTES;
  const total = options.totalCount ?? items.length;
  const kept: T[] = [];
  let bytes = 0;

  for (const item of items) {
    const s = JSON.stringify(item);
    if (bytes + s.length > limit && kept.length > 0) break;
    bytes += s.length;
    kept.push(item);
  }

  const truncated = kept.length < items.length || total > items.length;
  const response: {
    items: T[];
    returnedCount: number;
    totalCount: number;
    truncated: boolean;
    hint?: string;
  } = {
    items: kept,
    returnedCount: kept.length,
    totalCount: total,
    truncated,
  };
  if (truncated) {
    response.hint =
      "Response was capped for size. Narrow the filter (by project, date, status) or request fewer records.";
  }
  return response;
}

/** Serialize a capped list response to MCP tool text content. */
export function asToolResponse(payload: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(payload, null, 2) }] };
}
