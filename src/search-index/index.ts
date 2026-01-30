/**
 * Search Index Module
 * 
 * Optional module for offline local search using SQLite FTS5.
 * This is a non-authoritative, rebuildable index - Firestore remains canonical.
 * 
 * Usage:
 * ```typescript
 * import { SearchIndex } from '@/search-index';
 * 
 * const searchIndex = new SearchIndex();
 * 
 * // Index an item
 * await searchIndex.indexItem({
 *   id: 'item-1',
 *   accountId: 'account-1',
 *   scopeId: 'project-1',
 *   name: 'Widget',
 *   description: 'A useful widget',
 *   sku: 'WID-001'
 * });
 * 
 * // Search
 * const results = await searchIndex.search('account-1', 'project-1', 'widget');
 * // Returns: [{ itemId: 'item-1', accountId: 'account-1', scopeId: 'project-1', updatedAtMs: ... }]
 * 
 * // Remove an item
 * await searchIndex.removeItem('account-1', 'project-1', 'item-1');
 * ```
 */

export { indexItem, removeItem, removeScope } from './indexer';
export { search, getAllItemIds } from './search';
export {
  rebuildIndex,
  rebuildIfNeeded,
  shouldRebuild,
  getIndexState,
  updateIndexState,
} from './rebuild';
export { getDatabase, closeDatabase, resetDatabase, checkTablesExist } from './database';
export { normalizeSearchText, combineSearchFields } from './normalize';
export type { SearchableItem, SearchIndexState, ItemToSearchTextFn, SearchResult } from './types';
export { SCHEMA_VERSION } from './schema';

/**
 * Main SearchIndex class for convenient usage
 */
import type { SearchableItem, ItemToSearchTextFn, SearchResult } from './types';
import { indexItem as _indexItem, removeItem as _removeItem } from './indexer';
import { search as _search } from './search';
import { rebuildIndex as _rebuildIndex, rebuildIfNeeded as _rebuildIfNeeded } from './rebuild';

export class SearchIndex {
  private itemToSearchText?: ItemToSearchTextFn;

  constructor(itemToSearchText?: ItemToSearchTextFn) {
    this.itemToSearchText = itemToSearchText;
  }

  /**
   * Index or update an item in the search index
   */
  async indexItem(item: SearchableItem): Promise<void> {
    return _indexItem(item, this.itemToSearchText);
  }

  /**
   * Remove an item from the search index
   */
  async removeItem(accountId: string, scopeId: string, itemId: string): Promise<void> {
    return _removeItem(accountId, scopeId, itemId);
  }

  /**
   * Search for items matching the query
   */
  async search(
    accountId: string,
    scopeId: string,
    query: string,
    limit?: number
  ): Promise<SearchResult[]> {
    return _search(accountId, scopeId, query, limit);
  }

  /**
   * Rebuild the index for a scope from a list of items
   */
  async rebuildIndex(
    accountId: string,
    scopeId: string,
    items: SearchableItem[]
  ): Promise<void> {
    return _rebuildIndex(accountId, scopeId, items, this.itemToSearchText);
  }

  /**
   * Rebuild index if needed (checks version/corruption)
   */
  async rebuildIfNeeded(
    accountId: string,
    scopeId: string,
    items: SearchableItem[]
  ): Promise<boolean> {
    return _rebuildIfNeeded(accountId, scopeId, items, this.itemToSearchText);
  }
}
