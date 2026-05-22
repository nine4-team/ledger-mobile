import type { BudgetCategory, Transaction } from "../types.js";

/**
 * Derive `supportedTypes` for a budget category, falling back to the legacy
 * `metadata.categoryType` when the new field is absent. Mirrors the
 * Swift-side `BudgetCategory.resolvedSupportedTypes`. See
 * `docs/specs/transaction-type.md`.
 */
export function resolveSupportedTypes(c: BudgetCategory): string[] {
  if (c.supportedTypes && c.supportedTypes.length > 0) return c.supportedTypes;
  switch (c.metadata?.categoryType) {
    case "fee":
      return ["fee"];
    case "expense":
      return ["expense"];
    case "itemized":
      return ["purchase", "return"];
    case "general":
    default:
      return ["expense"];
  }
}

/**
 * Human-readable category-type label derived from supportedTypes.
 * "Fee" / "Expense" / "Items" / "General" — matches the iOS pill label.
 */
export function categoryPillLabel(c: BudgetCategory): string {
  const supported = new Set(resolveSupportedTypes(c));
  if (supported.size === 1 && supported.has("fee")) return "Fee";
  if (supported.size === 1 && supported.has("expense")) return "Expense";
  if (supported.has("purchase") && supported.has("return")) return "Items";
  return "General";
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
 *   3. Inventory → project Purchase             → +amount (normal purchase)
 *      (type == "Purchase", inventory source)
 *      Project → inventory Sale has no category and is not attributed to a
 *      destination budget category.
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

  // Case 3: Non-legacy Sale — project → inventory acquisition. These normally
  // have no category, but remain positive here for historical/defensive reads.
  if (rawType === "sale") {
    return Math.abs(amount);
  }

  // Case 4: Everything else (Purchase, etc.) — positive as-stored.
  return amount;
}
