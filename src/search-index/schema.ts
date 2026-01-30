/**
 * Database schema and migrations for the search index
 */

export const SCHEMA_VERSION = 1;

/**
 * SQL statements to create the search index tables
 */
export const CREATE_TABLES = `
  -- Main search index table
  CREATE TABLE IF NOT EXISTS item_search (
    account_id TEXT NOT NULL,
    scope_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    search_text TEXT NOT NULL,
    PRIMARY KEY (account_id, scope_id, item_id)
  );

  -- FTS5 virtual table for full-text search
  CREATE VIRTUAL TABLE IF NOT EXISTS item_search_fts USING fts5(
    search_text,
    content='item_search',
    content_rowid='rowid'
  );

  -- Triggers to keep FTS table in sync
  CREATE TRIGGER IF NOT EXISTS item_search_fts_insert AFTER INSERT ON item_search BEGIN
    INSERT INTO item_search_fts(rowid, search_text) VALUES (new.rowid, new.search_text);
  END;

  CREATE TRIGGER IF NOT EXISTS item_search_fts_delete AFTER DELETE ON item_search BEGIN
    INSERT INTO item_search_fts(item_search_fts, rowid, search_text) VALUES('delete', old.rowid, old.search_text);
  END;

  CREATE TRIGGER IF NOT EXISTS item_search_fts_update AFTER UPDATE ON item_search BEGIN
    INSERT INTO item_search_fts(item_search_fts, rowid, search_text) VALUES('delete', old.rowid, old.search_text);
    INSERT INTO item_search_fts(rowid, search_text) VALUES (new.rowid, new.search_text);
  END;

  -- Index state table (optional, for tracking rebuilds)
  CREATE TABLE IF NOT EXISTS search_index_state (
    account_id TEXT NOT NULL,
    scope_id TEXT NOT NULL,
    index_version INTEGER NOT NULL DEFAULT ${SCHEMA_VERSION},
    last_rebuild_at_ms INTEGER NOT NULL,
    PRIMARY KEY (account_id, scope_id)
  );

  -- Indexes for faster lookups
  CREATE INDEX IF NOT EXISTS idx_item_search_account_scope ON item_search(account_id, scope_id);
  CREATE INDEX IF NOT EXISTS idx_item_search_updated ON item_search(updated_at_ms);
`;

/**
 * Drop all tables (for rebuild/reset)
 */
export const DROP_TABLES = `
  DROP TABLE IF EXISTS item_search_fts;
  DROP TABLE IF EXISTS item_search;
  DROP TABLE IF EXISTS search_index_state;
`;
