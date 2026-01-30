/**
 * Rebuild utilities for the search index
 */

import { getDatabase, checkTablesExist, resetDatabase } from './database';
import { indexItem, removeScope } from './indexer';
import { SCHEMA_VERSION } from './schema';
import type { SearchableItem, SearchIndexState, ItemToSearchTextFn } from './types';

/**
 * Get or create index state for a scope
 */
export async function getIndexState(
  accountId: string,
  scopeId: string
): Promise<SearchIndexState | null> {
  const db = await getDatabase();

  const result = await db.getFirstAsync<{
    account_id: string;
    scope_id: string;
    index_version: number;
    last_rebuild_at_ms: number;
  }>(
    `SELECT account_id, scope_id, index_version, last_rebuild_at_ms
     FROM search_index_state
     WHERE account_id = ? AND scope_id = ?`,
    [accountId, scopeId]
  );

  if (!result) {
    return null;
  }

  return {
    accountId: result.account_id,
    scopeId: result.scope_id,
    indexVersion: result.index_version,
    lastRebuildAtMs: result.last_rebuild_at_ms,
  };
}

/**
 * Update index state after a rebuild
 */
export async function updateIndexState(
  accountId: string,
  scopeId: string,
  indexVersion: number = SCHEMA_VERSION
): Promise<void> {
  const db = await getDatabase();
  const now = Date.now();

  await db.runAsync(
    `INSERT INTO search_index_state (account_id, scope_id, index_version, last_rebuild_at_ms)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(account_id, scope_id)
     DO UPDATE SET index_version = ?, last_rebuild_at_ms = ?`,
    [accountId, scopeId, indexVersion, now, indexVersion, now]
  );
}

/**
 * Rebuild the search index for a scope from a list of items
 */
export async function rebuildIndex(
  accountId: string,
  scopeId: string,
  items: SearchableItem[],
  itemToSearchText?: ItemToSearchTextFn
): Promise<void> {
  // Remove existing items for this scope
  await removeScope(accountId, scopeId);

  // Index all items
  for (const item of items) {
    await indexItem(item, itemToSearchText);
  }

  // Update index state
  await updateIndexState(accountId, scopeId);
}

/**
 * Check if rebuild is needed based on index version or corruption
 */
export async function shouldRebuild(
  accountId: string,
  scopeId: string,
  expectedIndexVersion: number = SCHEMA_VERSION
): Promise<boolean> {
  // Check if tables exist
  const tablesExist = await checkTablesExist();
  if (!tablesExist) {
    return true;
  }

  // Check index version
  const state = await getIndexState(accountId, scopeId);
  if (!state) {
    return true; // No state means first build needed
  }

  if (state.indexVersion < expectedIndexVersion) {
    return true; // Schema version mismatch
  }

  return false;
}

/**
 * Rebuild index if needed
 */
export async function rebuildIfNeeded(
  accountId: string,
  scopeId: string,
  items: SearchableItem[],
  itemToSearchText?: ItemToSearchTextFn
): Promise<boolean> {
  const needsRebuild = await shouldRebuild(accountId, scopeId);
  
  if (needsRebuild) {
    await rebuildIndex(accountId, scopeId, items, itemToSearchText);
    return true;
  }

  return false;
}
