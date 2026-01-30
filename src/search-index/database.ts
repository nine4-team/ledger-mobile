/**
 * Database initialization and connection management
 */

import * as SQLite from 'expo-sqlite';
import { CREATE_TABLES, DROP_TABLES } from './schema';

let db: SQLite.SQLiteDatabase | null = null;
let hasInitializedSchema = false;

/**
 * Get or create the search index database connection
 */
export async function getDatabase(
  options?: { initialize?: boolean }
): Promise<SQLite.SQLiteDatabase> {
  if (!db) {
    db = await SQLite.openDatabaseAsync('search_index.db');
  }

  const shouldInitialize = options?.initialize !== false;
  if (shouldInitialize && !hasInitializedSchema) {
    // Initialize schema
    await db.execAsync(CREATE_TABLES);
    hasInitializedSchema = true;
  }

  return db;
}

/**
 * Close the database connection
 */
export async function closeDatabase(): Promise<void> {
  if (db) {
    await db.closeAsync();
    db = null;
    hasInitializedSchema = false;
  }
}

/**
 * Reset the database (drop and recreate tables)
 * Useful for rebuilds or testing
 */
export async function resetDatabase(): Promise<void> {
  const database = await getDatabase();
  await database.execAsync(DROP_TABLES);
  await database.execAsync(CREATE_TABLES);
}

/**
 * Check if tables exist (for corruption detection)
 */
export async function checkTablesExist(): Promise<boolean> {
  try {
    const database = await getDatabase({ initialize: false });
    const result = await database.getFirstAsync<{ count: number }>(
      "SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND name IN ('item_search', 'item_search_fts', 'search_index_state')"
    );
    return result?.count === 3;
  } catch {
    return false;
  }
}
