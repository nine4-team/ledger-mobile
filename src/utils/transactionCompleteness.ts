import type { Transaction } from '../data/transactionsService';
import type { Item } from '../data/itemsService';

export type CompletenessStatus = 'complete' | 'near' | 'incomplete' | 'over';

export interface TransactionCompleteness {
  /** Sum of purchasePriceCents for all linked items (cents) */
  itemsNetTotal: number;
  /** Total count of linked items */
  itemsCount: number;
  /** Count of items where purchasePriceCents is null/undefined/0 */
  itemsMissingPriceCount: number;
  /** Resolved pre-tax subtotal (cents) — explicit > inferred > fallback */
  transactionSubtotal: number;
  /** itemsNetTotal / transactionSubtotal (0-N, where 1.0 = 100%) */
  completenessRatio: number;
  /** Classified status based on threshold rules */
  completenessStatus: CompletenessStatus;
  /** True if no explicit subtotal and no valid taxRatePct */
  missingTaxData: boolean;
  /** Tax amount inferred from taxRatePct (cents), undefined if not inferred */
  inferredTax?: number;
  /** itemsNetTotal - transactionSubtotal (positive = over, negative = under) */
  varianceCents: number;
  /** (varianceCents / transactionSubtotal) * 100 */
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
  let transactionSubtotal: number;
  let missingTaxData = false;
  let inferredTax: number | undefined;

  if (transaction.subtotalCents != null && transaction.subtotalCents > 0) {
    // Priority 1: explicit subtotal
    transactionSubtotal = transaction.subtotalCents;
  } else if (
    transaction.amountCents != null &&
    transaction.amountCents > 0 &&
    transaction.taxRatePct != null &&
    transaction.taxRatePct > 0
  ) {
    // Priority 2: infer subtotal from amount and tax rate
    transactionSubtotal = Math.round(
      transaction.amountCents / (1 + transaction.taxRatePct / 100),
    );
    inferredTax = transaction.amountCents - transactionSubtotal;
  } else if (transaction.amountCents != null && transaction.amountCents > 0) {
    // Priority 3: fallback to full amount
    transactionSubtotal = transaction.amountCents;
    missingTaxData = true;
  } else {
    // No valid subtotal — N/A
    return null;
  }

  // Items total
  const itemsNetTotal = items.reduce(
    (sum, item) => sum + (item.purchasePriceCents ?? 0),
    0,
  );

  const itemsCount = items.length;

  // Missing price: null, undefined, or 0
  const itemsMissingPriceCount = items.filter(
    (item) => !item.purchasePriceCents,
  ).length;

  // Completeness ratio and variance
  const completenessRatio = itemsNetTotal / transactionSubtotal;
  const varianceCents = itemsNetTotal - transactionSubtotal;
  const variancePercent = (varianceCents / transactionSubtotal) * 100;

  // Status classification — check order matters
  let completenessStatus: CompletenessStatus;
  if (completenessRatio > 1.2) {
    completenessStatus = 'over';
  } else if (Math.abs(variancePercent) <= 1) {
    completenessStatus = 'complete';
  } else if (Math.abs(variancePercent) <= 20) {
    completenessStatus = 'near';
  } else {
    completenessStatus = 'incomplete';
  }

  return {
    itemsNetTotal,
    itemsCount,
    itemsMissingPriceCount,
    transactionSubtotal,
    completenessRatio,
    completenessStatus,
    missingTaxData,
    inferredTax,
    varianceCents,
    variancePercent,
  };
}
