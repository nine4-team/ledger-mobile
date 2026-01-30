/**
 * Types for the search index module
 */

export interface SearchableItem {
  id: string;
  accountId: string;
  scopeId: string;
  name?: string;
  description?: string;
  sku?: string;
  source?: string;
  vendor?: string;
  notes?: string;
  updatedAt?: number | Date;
  [key: string]: unknown; // Allow additional fields
}

export interface SearchIndexState {
  accountId: string;
  scopeId: string;
  indexVersion: number;
  lastRebuildAtMs: number;
}

export interface SearchResult {
  itemId: string;
  accountId: string;
  scopeId: string;
  updatedAtMs: number;
}

/**
 * Function to extract searchable text from an item
 * Apps should override this to match their item schema
 */
export type ItemToSearchTextFn = (item: SearchableItem) => string;
