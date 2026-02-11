/**
 * Item status constants
 * These represent the canonical list of item statuses used throughout the app.
 */
export const ITEM_STATUSES = [
  { key: 'to purchase', label: 'To Purchase' },
  { key: 'purchased', label: 'Purchased' },
  { key: 'to return', label: 'To Return' },
  { key: 'returned', label: 'Returned' },
] as const;

/**
 * Get the display label for an item status key
 */
export function getItemStatusLabel(statusKey: string | null | undefined): string {
  if (!statusKey?.trim()) return '';
  const status = ITEM_STATUSES.find(s => s.key === statusKey.trim());
  return status?.label || statusKey;
}
