import type { BudgetCategory, Transaction } from "../types.js";

export type BudgetCategoryKind = "items" | "projectCost" | "feeCategory" | "unknown";

export type ResolvedCategoryType = "general" | "itemized" | "fee";

function normalizeCategoryType(value: string | undefined): ResolvedCategoryType | null {
  switch (value?.trim().toLowerCase()) {
    case "fee":
      return "fee";
    case "itemized":
      return "itemized";
    case "standard":
    case "expense":
    case "general":
      return "general";
    default:
      return null;
  }
}

function deriveCategoryTypeFromSupportedTypes(supportedTypes: string[] | undefined): ResolvedCategoryType {
  const supported = new Set((supportedTypes ?? []).map((v) => v.trim().toLowerCase()).filter(Boolean));
  if (supported.size === 1 && supported.has("fee")) return "fee";
  if (supported.size === 2 && supported.has("purchase") && supported.has("return")) return "itemized";
  return "general";
}

/**
 * Resolve canonical category behavior. `metadata.categoryType` is the product
 * model; `supportedTypes` is a compatibility fallback for dirty migration data.
 */
export function resolveCategoryType(c: BudgetCategory): ResolvedCategoryType {
  return normalizeCategoryType(c.metadata?.categoryType) ?? deriveCategoryTypeFromSupportedTypes(c.supportedTypes);
}

/**
 * Compatibility shape derived from canonical category behavior. Do not let raw
 * `supportedTypes` override `metadata.categoryType`.
 */
export function resolveSupportedTypes(c: BudgetCategory): string[] {
  switch (resolveCategoryType(c)) {
    case "fee":
      return ["fee"];
    case "itemized":
      return ["purchase", "return"];
    case "general":
    default:
      return ["expense"];
  }
}

/**
 * App-facing category behavior derived from canonical category type.
 */
export function budgetCategoryKind(c: BudgetCategory): BudgetCategoryKind {
  switch (resolveCategoryType(c)) {
    case "fee":
      return "feeCategory";
    case "itemized":
      return "items";
    case "general":
      return "projectCost";
  }
}

/**
 * Human-readable category-type label derived from categoryKind.
 * "Fee Category" / "Project Cost" / "Items" / "General" — matches the iOS pill label.
 */
export function categoryPillLabel(c: BudgetCategory): string {
  switch (budgetCategoryKind(c)) {
    case "feeCategory":
      return "Fee Category";
    case "projectCost":
      return "Project Cost";
    case "items":
      return "Items";
    case "unknown":
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
