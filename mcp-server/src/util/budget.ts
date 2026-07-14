import type { BudgetCategory, Transaction } from "../types.js";

export type ResolvedCategoryType = "general" | "itemized" | "fee";

function normalizeCategoryType(value: string | undefined): ResolvedCategoryType | null {
  switch (value?.trim().toLowerCase()) {
    case "fee":
      return "fee";
    case "itemized":
      return "itemized";
    case "general":
      return "general";
    default:
      return null;
  }
}

/** Resolve canonical category behavior. */
export function resolveCategoryType(c: BudgetCategory): ResolvedCategoryType {
  return normalizeCategoryType(c.metadata?.categoryType) ?? "general";
}

/**
 * Human-readable category-type label.
 */
export function categoryPillLabel(c: BudgetCategory): string {
  switch (resolveCategoryType(c)) {
    case "fee":
      return "Fee";
    case "itemized":
      return "Itemized";
    case "general":
      return "General";
  }
}

/**
 * Sign convention for budget rollups.
 *
 * Dual-read path — three cases:
 *   1. Returns (type == "Return")               → always -1 (-|amount|)
 *   2. Legacy canonical sales                   → direction-based (-1 for
 *      (isCanonicalInventorySale == true)           project_to_business, +1 for
 *                                                   business_to_project). See
 *                                                   docs/specs/canonical-sales.md.
 *   3. Non-legacy project → inventory Sale      → always -1 (-|amount|)
 *   4. Everything else (Purchase, etc.)         → +amount (unchanged)
 *
 * Canceled transactions contribute $0.
 *
 * Any new reader computing budget totals MUST call this function rather than
 * reimplementing the convention. See docs/specs/budget-management.md.
 */
export function normalizeSpendAmount(tx: Transaction): number {
  if (tx.status === "canceled") return 0;
  if (typeof tx.amountCents !== "number") return 0;

  const amount = tx.amountCents;
  const rawType = typeof tx.type === "string" ? tx.type.trim().toLowerCase() : null;

  if (rawType === "paymenttobusiness" || rawType === "payment_to_business" || rawType === "payment-to-business") {
    return 0;
  }

  // Case 1: Returns — always negative.
  if (rawType === "return") {
    return -Math.abs(amount);
  }

  // Case 2: Legacy canonical sales — direction-based sign.
  // These are historical records produced by the old aggregator system.
  // New writes must never set isCanonicalInventorySale; the dual-read path
  // exists only to preserve budget math for the 8 existing 1584 Design docs
  // and any legacy Assiist Biz docs.
  if (tx.isCanonicalInventorySale && tx.inventorySaleDirection) {
    return tx.inventorySaleDirection === "project_to_business"
      ? -Math.abs(amount)
      : Math.abs(amount);
  }

  // Case 3: Non-legacy Sale — project → inventory/project egress.
  if (rawType === "sale") {
    return -Math.abs(amount);
  }

  // Case 4: Everything else (Purchase, etc.) — positive as-stored.
  return amount;
}
