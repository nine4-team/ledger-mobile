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
 * Parses a query string into a cents range for amount prefix matching.
 *
 * - "40"    → [4000, 4099]  (any amount from $40.00 to $40.99)
 * - "40.0"  → [4000, 4009]  (any amount from $40.00 to $40.09)
 * - "40.00" → [4000, 4000]  (exact $40.00)
 * - "$1,200" → [120000, 120099]
 * - "abc"   → null
 */
export function parseAmountQuery(
  query: string
): [number, number] | null {
  const cleaned = query.replace(/[$,]/g, "");
  if (!cleaned) return null;

  const parts = cleaned.split(".");
  if (parts.length > 2) return null;

  const integerPart = parseInt(parts[0], 10);
  if (isNaN(integerPart)) return null;

  if (parts.length === 1) {
    const low = integerPart * 100;
    return [low, low + 99];
  }

  const decimalString = parts[1];
  if (!decimalString || !/^\d+$/.test(decimalString)) return null;

  if (decimalString.length === 1) {
    const d = parseInt(decimalString, 10);
    const low = integerPart * 100 + d * 10;
    return [low, low + 9];
  }

  if (decimalString.length === 2) {
    const decimalCents = parseInt(decimalString, 10);
    const cents = integerPart * 100 + decimalCents;
    return [cents, cents];
  }

  // More than 2 decimal digits — not a valid amount query
  return null;
}

function amountInRange(
  cents: number | null | undefined,
  range: [number, number]
): boolean {
  if (cents == null) return false;
  return cents >= range[0] && cents <= range[1];
}

/** Matches a transaction against a search query using text + amount strategies. */
export function transactionMatches(
  tx: Transaction & { id: string },
  query: string
): boolean {
  if (!query) return true;

  // Text fields: source, transactionType/type, notes, purchasedBy
  const textFields = [
    tx.source,
    tx.transactionType ?? tx.type,
    tx.notes,
    tx.purchasedBy,
  ];
  if (textFields.some((f) => textMatch(query, f))) return true;

  // Amount field
  const range = parseAmountQuery(query);
  if (range && amountInRange(tx.amountCents, range)) return true;

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
  const range = parseAmountQuery(query);
  if (range) {
    const amounts = [
      item.purchasePriceCents,
      item.projectPriceCents,
      item.marketValueCents,
    ];
    if (amounts.some((a) => amountInRange(a, range))) return true;
  }

  return false;
}
