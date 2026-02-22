/**
 * Pure category resolution logic for bulk sale operations.
 *
 * Extracted from component callbacks so it can be unit tested.
 * See docs/specs/canonical_sale_system.md "Bulk sale operations" for spec.
 */

export type ItemForCategoryResolution = {
  id: string;
  budgetCategoryId?: string | null;
};

export type ResolvedItem = {
  id: string;
  resolvedCategoryId: string;
  categoryWasAssigned: boolean;
};

/**
 * Flow A: Sell to Business (Project → Business)
 *
 * Items with a budgetCategoryId keep it.
 * Items without get the fallbackCategoryId.
 * Returns only items that could be resolved (skips items with no category and no fallback).
 */
export function resolveSourceCategories(
  items: ItemForCategoryResolution[],
  fallbackCategoryId: string | null,
): ResolvedItem[] {
  const results: ResolvedItem[] = [];
  for (const item of items) {
    const existing = item.budgetCategoryId;
    if (existing) {
      results.push({ id: item.id, resolvedCategoryId: existing, categoryWasAssigned: false });
    } else if (fallbackCategoryId) {
      results.push({ id: item.id, resolvedCategoryId: fallbackCategoryId, categoryWasAssigned: true });
    }
    // If no existing and no fallback, item is skipped (caller should validate beforehand)
  }
  return results;
}

/**
 * Flow B/C: Sell to Project (Business → Project, or Project → Project destination hop)
 *
 * Items whose budgetCategoryId is present in validCategoryIds keep it.
 * Items whose category is missing or not in validCategoryIds get the fallbackCategoryId.
 * Returns only items that could be resolved.
 */
export function resolveDestinationCategories(
  items: ItemForCategoryResolution[],
  validCategoryIds: Set<string>,
  fallbackCategoryId: string | null,
): ResolvedItem[] {
  const results: ResolvedItem[] = [];
  for (const item of items) {
    const existing = item.budgetCategoryId;
    if (existing && validCategoryIds.has(existing)) {
      results.push({ id: item.id, resolvedCategoryId: existing, categoryWasAssigned: false });
    } else if (fallbackCategoryId) {
      results.push({ id: item.id, resolvedCategoryId: fallbackCategoryId, categoryWasAssigned: true });
    }
  }
  return results;
}

/**
 * Returns true if any item has no budgetCategoryId (needs source category picker).
 */
export function needsSourceCategoryPicker(items: ItemForCategoryResolution[]): boolean {
  return items.some((item) => !item.budgetCategoryId);
}

/**
 * Returns true if any item's category is missing or not in the valid set
 * (needs destination category picker).
 */
export function needsDestinationCategoryPicker(
  items: ItemForCategoryResolution[],
  validCategoryIds: Set<string>,
): boolean {
  return items.some((item) => !item.budgetCategoryId || !validCategoryIds.has(item.budgetCategoryId));
}
