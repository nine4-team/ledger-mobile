/**
 * Indexing functions: add, update, and remove items from the search index
 */

import { getDatabase } from './database';
import { normalizeSearchText, combineSearchFields } from './normalize';
import type { SearchableItem, ItemToSearchTextFn } from './types';

/**
 * Default function to extract searchable text from an item
 * Apps can override this via the SearchIndex class
 */
export function defaultItemToSearchText(item: SearchableItem): string {
  return combineSearchFields([
    item.name,
    item.description,
    item.sku,
    item.source,
    item.vendor,
    item.notes,
  ]);
}

/**
 * Index or update an item in the search index
 */
export async function indexItem(
  item: SearchableItem,
  itemToSearchText: ItemToSearchTextFn = defaultItemToSearchText
): Promise<void> {
  const db = await getDatabase();
  
  const searchText = itemToSearchText(item);
  const normalizedText = normalizeSearchText(searchText);
  const updatedAtMs = item.updatedAt 
    ? typeof item.updatedAt === 'number' 
      ? item.updatedAt 
      : item.updatedAt.getTime()
    : Date.now();

  await db.runAsync(
    `INSERT INTO item_search (account_id, scope_id, item_id, updated_at_ms, search_text)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(account_id, scope_id, item_id) 
     DO UPDATE SET updated_at_ms = ?, search_text = ?`,
    [
      item.accountId,
      item.scopeId,
      item.id,
      updatedAtMs,
      normalizedText,
      updatedAtMs,
      normalizedText,
    ]
  );
}

/**
 * Remove an item from the search index
 */
export async function removeItem(
  accountId: string,
  scopeId: string,
  itemId: string
): Promise<void> {
  const db = await getDatabase();
  
  await db.runAsync(
    `DELETE FROM item_search 
     WHERE account_id = ? AND scope_id = ? AND item_id = ?`,
    [accountId, scopeId, itemId]
  );
}

/**
 * Remove all items for a given scope (useful for rebuilds)
 */
export async function removeScope(
  accountId: string,
  scopeId: string
): Promise<void> {
  const db = await getDatabase();
  
  await db.runAsync(
    `DELETE FROM item_search 
     WHERE account_id = ? AND scope_id = ?`,
    [accountId, scopeId]
  );
}
