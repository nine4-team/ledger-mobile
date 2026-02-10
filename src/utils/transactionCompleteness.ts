import type { Transaction } from '../data/transactionsService';
import type { Item } from '../data/itemsService';

export type CompletenessStatus = 'complete' | 'near' | 'incomplete' | 'over';

export interface TransactionCompleteness {
  /** Sum of purchasePriceCents for all linked items (cents) */
  itemsNetTotalCents: number;
  /** Total count of linked items */
  itemsCount: number;
  /** Count of items where purchasePriceCents is null/undefined/0 */
  itemsMissingPriceCount: number;
  /** Resolved pre-tax subtotal (cents) — explicit > inferred > fallback */
  transactionSubtotalCents: number;
  /** itemsNetTotalCents / transactionSubtotalCents (0-N, where 1.0 = 100%) */
  completenessRatio: number;
  /** Classified status based on threshold rules */
  status: CompletenessStatus;
  /** True if no explicit subtotal and no valid taxRatePct */
  missingTaxData: boolean;
  /** Tax amount inferred from taxRatePct (cents), undefined if not inferred */
  inferredTax?: number;
  /** itemsNetTotalCents - transactionSubtotalCents (positive = over, negative = under) */
  varianceCents: number;
  /** (varianceCents / transactionSubtotalCents) * 100 */
  variancePercent: number;
}

/**
 * Compute transaction completeness by comparing linked item prices
 * against the transaction subtotal.
 *
 * Returns null when the resolved subtotal is zero or invalid (N/A state).
 */
export function computeTransactionCompleteness(
  transaction: Transaction,
  items: Pick<Item, 'purchasePriceCents'>[],
): TransactionCompleteness | null {
  // Resolve subtotal using priority: explicit > inferred from tax > fallback to amount
  let transactionSubtotalCents: number;
  let missingTaxData = false;
  let inferredTax: number | undefined;

  if (transaction.subtotalCents != null && transaction.subtotalCents > 0) {
    // Priority 1: explicit subtotal
    transactionSubtotalCents = transaction.subtotalCents;
  } else if (
    transaction.amountCents != null &&
    transaction.amountCents > 0 &&
    transaction.taxRatePct != null &&
    transaction.taxRatePct > 0
  ) {
    // Priority 2: infer subtotal from amount and tax rate
    transactionSubtotalCents = Math.round(
      transaction.amountCents / (1 + transaction.taxRatePct / 100),
    );
    inferredTax = transaction.amountCents - transactionSubtotalCents;
  } else if (transaction.amountCents != null && transaction.amountCents > 0) {
    // Priority 3: fallback to full amount
    transactionSubtotalCents = transaction.amountCents;
    missingTaxData = true;
  } else {
    // No valid subtotal — N/A
    return null;
  }

  // Items total
  const itemsNetTotalCents = items.reduce(
    (sum, item) => sum + (item.purchasePriceCents ?? 0),
    0,
  );

  const itemsCount = items.length;

  // Missing price: null, undefined, or 0
  const itemsMissingPriceCount = items.filter(
    (item) => !item.purchasePriceCents,
  ).length;

  // Completeness ratio and variance
  const completenessRatio = itemsNetTotalCents / transactionSubtotalCents;
  const varianceCents = itemsNetTotalCents - transactionSubtotalCents;
  const variancePercent = (varianceCents / transactionSubtotalCents) * 100;

  // Status classification — check order matters
  let status: CompletenessStatus;
  if (completenessRatio > 1.2) {
    status = 'over';
  } else if (Math.abs(variancePercent) <= 1) {
    status = 'complete';
  } else if (Math.abs(variancePercent) <= 20) {
    status = 'near';
  } else {
    status = 'incomplete';
  }

  return {
    itemsNetTotalCents,
    itemsCount,
    itemsMissingPriceCount,
    transactionSubtotalCents,
    completenessRatio,
    status,
    missingTaxData,
    inferredTax,
    varianceCents,
    variancePercent,
  };
}
