export type ItemPriceData = {
  purchasePriceCents?: unknown;
  projectPriceCents?: unknown;
};

function cents(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

export function normalizedProjectPriceCents(data: ItemPriceData): number | null {
  const purchasePrice = cents(data.purchasePriceCents);
  const projectPrice = cents(data.projectPriceCents);
  if (purchasePrice == null && projectPrice == null) return null;
  return Math.max(purchasePrice ?? 0, projectPrice ?? 0);
}

export function needsProjectPriceRepair(data: ItemPriceData): boolean {
  const normalized = normalizedProjectPriceCents(data);
  return normalized != null && cents(data.projectPriceCents) !== normalized;
}
