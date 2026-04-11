import type { Transaction } from "../types.js";

/**
 * Sign convention for budget rollups.
 *
 * Dual-read path — three cases:
 *   1. Returns (type == "Return")               → always -1 (-|amount|)
 *   2. Legacy canonical sales                   → direction-based (-1 for
 *      (isCanonicalInventorySale == true)           project_to_business, +1 for
 *                                                   business_to_project). See
 *                                                   docs/specs/canonical-sales.md.
 *   3. New per-batch Sale (type == "Sale",      → always +1 (+|amount|)
 *      no isCanonicalInventorySale flag)            Sales always go
 *                                                   business → project.
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

  // Case 3: New per-batch Sale — always positive.
  // Per the per-batch redesign, sales only ever go business → project, and
  // the amount is a frozen snapshot captured at creation time.
  if (rawType === "sale") {
    return Math.abs(amount);
  }

  // Case 4: Everything else (Purchase, etc.) — positive as-stored.
  return amount;
}
