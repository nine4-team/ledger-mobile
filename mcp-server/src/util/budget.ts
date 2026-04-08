import type { Transaction } from "../types.js";

/**
 * Mirrors normalizeSpendAmount from backfill-budget-summaries.mjs.
 * Determines the signed spend contribution of a transaction.
 *
 * - Canceled → $0
 * - Returns → negate
 * - Canonical sales → sign based on inventorySaleDirection
 * - Everything else → positive
 */
export function normalizeSpendAmount(tx: Transaction): number {
  if (tx.status === "canceled") return 0;
  if (typeof tx.amountCents !== "number") return 0;

  const amount = tx.amountCents;

  const raw = tx.type;
  const txType = typeof raw === "string" ? raw.trim().toLowerCase() : null;

  if (txType === "return") {
    return -Math.abs(amount);
  }

  if (tx.isCanonicalInventorySale && tx.inventorySaleDirection) {
    return tx.inventorySaleDirection === "project_to_business"
      ? -Math.abs(amount)
      : Math.abs(amount);
  }

  return amount;
}
