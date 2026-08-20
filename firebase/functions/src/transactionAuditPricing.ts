export type AuditPriceBasis = 'purchase' | 'project';

type TransactionPriceContext = {
  type?: unknown;
  transactionType?: unknown;
  source?: unknown;
  projectId?: unknown;
};

type ItemPriceContext = {
  purchasePriceCents?: unknown;
  projectPriceCents?: unknown;
};

/**
 * Project-destination Purchases from business inventory are charged at the
 * client-facing project price. Vendor Purchases and Returns reconcile to cost.
 * The Inventory suffix is the repository-wide discriminator for inventory
 * movement sources, including historical branded labels.
 */
export function auditPriceBasis(txData: TransactionPriceContext): AuditPriceBasis {
  const rawType = txData.type ?? txData.transactionType;
  const type = typeof rawType === 'string' ? rawType.trim().toLowerCase() : '';
  const source = typeof txData.source === 'string' ? txData.source.trim() : '';
  const hasProject = typeof txData.projectId === 'string' && txData.projectId.trim().length > 0;

  return type === 'purchase' && hasProject && source.endsWith(' Inventory')
    ? 'project'
    : 'purchase';
}

export function auditItemPriceCents(
  basis: AuditPriceBasis,
  itemData: ItemPriceContext
): number {
  const value = basis === 'project'
    ? itemData.projectPriceCents
    : itemData.purchasePriceCents;
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}
