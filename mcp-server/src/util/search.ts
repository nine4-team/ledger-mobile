import type { Transaction, Item } from "../types.js";

/** Case-insensitive substring match. */
export function textMatch(
  query: string,
  text: string | null | undefined
): boolean {
  if (!text) return false;
  return text.toLowerCase().includes(query.toLowerCase());
}

/** Strips all non-alphanumeric characters and lowercases. */
export function normalizedSKU(sku: string): string {
  return sku.replace(/[^a-zA-Z0-9]/g, "").toLowerCase();
}

/**
 * Checks if a cents value's formatted dollar amount starts with the query.
 * Formats cents as a decimal string (e.g. 637000 → "6370.00") and checks
 * prefix match. Handles commas, $, trailing dots, and negative amounts.
 *
 * - "637" matches 637000 ($6,370.00) — "6370.00".startsWith("637")
 * - "407.87" matches 40787 — exact
 * - "6370." matches 637000 — trailing dot works
 * - "29" matches 2999 ($29.99) but NOT 12999 ($129.99)
 */
export function amountMatch(
  query: string,
  cents: number | null | undefined
): boolean {
  if (cents == null) return false;
  const cleaned = query.replace(/[$,]/g, "");
  if (!cleaned || !/^[\d.]/.test(cleaned)) return false;
  const formatted = (Math.round(Math.abs(cents)) / 100).toFixed(2);
  return formatted.startsWith(cleaned);
}

/** Matches a transaction against a search query using text + amount strategies. */
export function transactionMatches(
  tx: Transaction & { id: string },
  query: string
): boolean {
  if (!query) return true;

  // Text fields: source, type, notes, purchasedBy
  const textFields = [
    tx.source,
    tx.type,
    tx.notes,
    tx.purchasedBy,
  ];
  if (textFields.some((f) => textMatch(query, f))) return true;

  // Amount field
  if (amountMatch(query, tx.amountCents)) return true;

  return false;
}

/** Matches an item against a search query using text + SKU + amount strategies. */
export function itemMatches(
  item: Item & { id: string },
  query: string
): boolean {
  if (!query) return true;

  // Text fields: name, description, source, sku (raw), notes
  const textFields = [
    item.name,
    item.description,
    item.source,
    item.sku,
    item.notes,
  ];
  if (textFields.some((f) => textMatch(query, f))) return true;

  // Normalized SKU match
  const sku = item.sku;
  if (sku) {
    const normalizedItemSKU = normalizedSKU(sku);
    const normalizedQuery = normalizedSKU(query);
    if (normalizedQuery && normalizedItemSKU.includes(normalizedQuery))
      return true;
  }

  // Amount fields
  const amounts = [
    item.purchasePriceCents,
    item.projectPriceCents,
    item.marketValueCents,
  ];
  if (amounts.some((a) => amountMatch(query, a))) return true;

  return false;
}
