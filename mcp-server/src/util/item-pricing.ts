import type { Item } from "../types.js";

type ItemPriceFields = Pick<Item, "purchasePriceCents" | "projectPriceCents">;

/** Canonical client-facing price: project price may never be below cost. */
export function normalizedProjectPriceCents(
  purchasePriceCents: number | null | undefined,
  projectPriceCents: number | null | undefined
): number | undefined {
  if (purchasePriceCents == null && projectPriceCents == null) return undefined;
  return Math.max(purchasePriceCents ?? 0, projectPriceCents ?? 0);
}

/** Defensive reader for documents written before the persisted invariant. */
export function effectiveProjectPriceCents(item: ItemPriceFields): number {
  return normalizedProjectPriceCents(
    item.purchasePriceCents,
    item.projectPriceCents
  ) ?? 0;
}

/** Apply the invariant to a create payload. */
export function applyItemPriceFloorToCreate(
  data: Record<string, unknown>,
  prices: ItemPriceFields
): Record<string, unknown> {
  const normalized = normalizedProjectPriceCents(
    prices.purchasePriceCents,
    prices.projectPriceCents
  );
  if (normalized !== undefined) data.projectPriceCents = normalized;
  return data;
}

/**
 * Apply the invariant to the merged post-update state. Even a non-price edit
 * repairs a legacy item whose stored project price is below purchase cost.
 */
export function applyItemPriceFloorToUpdate(
  existing: ItemPriceFields,
  updates: Record<string, unknown>
): Record<string, unknown> {
  const purchasePrice = mergedPrice(
    existing.purchasePriceCents,
    updates,
    "purchasePriceCents"
  );
  const projectPrice = mergedPrice(
    existing.projectPriceCents,
    updates,
    "projectPriceCents"
  );
  const normalized = normalizedProjectPriceCents(purchasePrice, projectPrice);
  if (normalized !== undefined) updates.projectPriceCents = normalized;
  return updates;
}

function mergedPrice(
  existing: number | null | undefined,
  updates: Record<string, unknown>,
  key: "purchasePriceCents" | "projectPriceCents"
): number | null | undefined {
  if (!(key in updates)) return existing;
  const value = updates[key];
  if (value == null) return value as null | undefined;
  return typeof value === "number" ? value : existing;
}
