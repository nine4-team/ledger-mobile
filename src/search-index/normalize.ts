/**
 * Text normalization utilities for search indexing
 */

/**
 * Normalize text for search indexing:
 * - lowercase
 * - trim whitespace
 * - collapse repeated whitespace
 * - optionally strip punctuation (optional, can be enabled)
 */
export function normalizeSearchText(text: string, stripPunctuation = false): string {
  if (!text) {
    return '';
  }

  let normalized = text.toLowerCase().trim();

  // Collapse repeated whitespace
  normalized = normalized.replace(/\s+/g, ' ');

  // Optionally strip punctuation (disabled by default to preserve SKUs like "ABC-123")
  if (stripPunctuation) {
    normalized = normalized.replace(/[^\w\s]/g, '');
  }

  return normalized;
}

/**
 * Combine multiple fields into a single searchable text string
 */
export function combineSearchFields(fields: (string | undefined | null)[]): string {
  return fields
    .filter((field): field is string => Boolean(field))
    .map((field) => normalizeSearchText(field))
    .filter((field) => field.length > 0)
    .join(' ');
}
