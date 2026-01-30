/**
 * Search functions: query the FTS index and return item IDs
 */

import { getDatabase } from './database';
import type { SearchResult } from './types';

/**
 * Search for items matching the query string
 * Returns candidate item IDs that match the search query
 * 
 * @param accountId - Account ID to scope the search
 * @param scopeId - Scope ID (e.g., project_id or 'inventory')
 * @param query - Search query string
 * @param limit - Maximum number of results (default: 100)
 * @returns Array of search results with item IDs
 */
export async function search(
  accountId: string,
  scopeId: string,
  query: string,
  limit = 100
): Promise<SearchResult[]> {
  const db = await getDatabase();

  // Normalize query for FTS5
  // FTS5 uses a simple tokenizer, so we can pass the query as-is
  // For better results, apps might want to pre-process the query
  const normalizedQuery = query.trim().toLowerCase();

  if (!normalizedQuery) {
    return [];
  }

  // FTS5 search query syntax: use "query" for phrase matching or query* for prefix matching
  // For simple token matching, we can use the query directly
  const ftsQuery = normalizedQuery.split(/\s+/).join(' OR ');

  const results = await db.getAllAsync<{
    item_id: string;
    account_id: string;
    scope_id: string;
    updated_at_ms: number;
  }>(
    `SELECT item_id, account_id, scope_id, updated_at_ms
     FROM item_search
     WHERE account_id = ? AND scope_id = ?
       AND rowid IN (
         SELECT rowid FROM item_search_fts 
         WHERE item_search_fts MATCH ?
         ORDER BY bm25(item_search_fts)
         LIMIT ?
       )
     ORDER BY updated_at_ms DESC`,
    [accountId, scopeId, ftsQuery, limit]
  );

  return results.map((row) => ({
    itemId: row.item_id,
    accountId: row.account_id,
    scopeId: row.scope_id,
    updatedAtMs: row.updated_at_ms,
  }));
}

/**
 * Get all item IDs for a scope (useful for rebuilds)
 */
export async function getAllItemIds(
  accountId: string,
  scopeId: string
): Promise<string[]> {
  const db = await getDatabase();

  const results = await db.getAllAsync<{ item_id: string }>(
    `SELECT item_id FROM item_search 
     WHERE account_id = ? AND scope_id = ?`,
    [accountId, scopeId]
  );

  return results.map((row) => row.item_id);
}
