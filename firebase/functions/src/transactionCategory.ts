export type TransactionCategoryFields = {
  budgetCategoryId?: unknown;
  intendedBudgetCategoryId?: unknown;
};

function realCategoryId(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Inventory resale acquisitions keep their project category as planning
 * metadata because their active project scope/category are both null. Their
 * completeness audit must still use that intended category so itemized
 * purchases remain in Needs Review until their receipt lines reconcile.
 */
export function transactionCategoryIdForCompleteness(
  txData: TransactionCategoryFields
): string | null {
  return realCategoryId(txData.budgetCategoryId)
    ?? realCategoryId(txData.intendedBudgetCategoryId);
}
