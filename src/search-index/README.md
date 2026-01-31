# Search Index Module

Optional module for **offline local search** using SQLite FTS5. This module provides a **non-authoritative, rebuildable search index** - Firestore remains the canonical source of truth.

## When to Use

Use this module when your app requires:
- **Robust offline multi-field search** over items (name, description, SKU, vendor, etc.)
- **Target scale**: < 1k items per scope (e.g., per project)
- **Search while offline** without querying Firestore

**If your app doesn't need offline local search, don't use this module** - it adds complexity that isn't necessary for all apps.

## Architecture

- **SQLite FTS5** stores searchable text for items
- **Index is rebuildable** and **non-authoritative**
- **UI uses the index only to get candidate IDs**; item details still come from Firestore
- **Index stays consistent** with Firestore snapshots via listener callbacks

## Installation

The module requires `expo-sqlite` (already added to `package.json`):

```bash
npm install
```

## Basic Usage

### 1. Create a SearchIndex instance

```typescript
import { SearchIndex } from '@/search-index';

// Use default field mapping (name, description, sku, source, vendor, notes)
const searchIndex = new SearchIndex();

// Or provide custom field mapping
const searchIndex = new SearchIndex((item) => {
  return `${item.name} ${item.description} ${item.customField}`.toLowerCase();
});
```

### 2. Index items from Firestore listeners

```typescript
import { SearchIndex } from '@/search-index';
import { db } from '@/firebase/firebase';

const searchIndex = new SearchIndex();

// When items are added/modified
const unsubscribe = db.collection('items').onSnapshot((snapshot) => {
  snapshot.docChanges().forEach((change) => {
    const item = { id: change.doc.id, ...change.doc.data() };
    
    if (change.type === 'added' || change.type === 'modified') {
      searchIndex.indexItem({
        id: item.id,
        accountId: 'account-1',
        scopeId: 'project-1',
        name: item.name,
        description: item.description,
        sku: item.sku,
        // ... other searchable fields
      });
    } else if (change.type === 'removed') {
      searchIndex.removeItem('account-1', 'project-1', item.id);
    }
  });
});
```

### 3. Search for items

```typescript
// Search returns candidate item IDs
const results = await searchIndex.search('account-1', 'project-1', 'widget');

// results: [{ itemId: 'item-1', accountId: 'account-1', scopeId: 'project-1', updatedAtMs: ... }]

// Then fetch full item details from Firestore
const itemIds = results.map(r => r.itemId);
const items = await Promise.all(
  itemIds.map(id => db.collection('items').doc(id).get())
);
```

### 4. Rebuild index (when needed)

```typescript
// Rebuild on first scope open, version bump, or corruption
const needsRebuild = await searchIndex.rebuildIfNeeded(
  'account-1',
  'project-1',
  allItemsFromFirestore
);

if (needsRebuild) {
  console.log('Index rebuilt');
}
```

## Expected Item Shape

Items should implement the `SearchableItem` interface:

```typescript
interface SearchableItem {
  id: string;
  accountId: string;
  scopeId: string; // e.g., 'project-1' or 'inventory'
  name?: string;
  description?: string;
  sku?: string;
  source?: string;
  vendor?: string;
  notes?: string;
  updatedAt?: number | Date;
  [key: string]: unknown; // Additional fields allowed
}
```

## Custom Field Mapping

Override the default field mapping by providing an `ItemToSearchTextFn`:

```typescript
const customMapper: ItemToSearchTextFn = (item) => {
  return combineSearchFields([
    item.name,
    item.description,
    item.sku,
    item.customField1,
    item.customField2,
  ]);
};

const searchIndex = new SearchIndex(customMapper);
```

## Rebuild Strategy

The index should be rebuilt on:
- **First scope open** (if no index state exists)
- **Index version bump** (schema changes)
- **Detected corruption** (missing tables)
- **Optional debug action** ("Rebuild search index")

The module provides `rebuildIfNeeded()` which checks these conditions automatically.

## Integration with Firestore Listeners

The recommended pattern is to keep the index in sync with Firestore:

```typescript
// When scope opens
const unsubscribe = onSnapshot(
  query(collection(db, 'accounts/account-1/projects/project-1/items')),
  async (snapshot) => {
    // Handle changes
    snapshot.docChanges().forEach((change) => {
      const item = {
        id: change.doc.id,
        accountId: 'account-1',
        scopeId: 'project-1',
        ...change.doc.data(),
      };
      
      if (change.type === 'added' || change.type === 'modified') {
        searchIndex.indexItem(item);
      } else if (change.type === 'removed') {
        searchIndex.removeItem(item.accountId, item.scopeId, item.id);
      }
    });

    // Rebuild if needed (first time or version mismatch)
    if (snapshot.metadata.fromCache) {
      // Offline: check if rebuild needed
      const allItems = snapshot.docs.map(doc => ({
        id: doc.id,
        accountId: 'account-1',
        scopeId: 'project-1',
        ...doc.data(),
      }));
      await searchIndex.rebuildIfNeeded('account-1', 'project-1', allItems);
    }
  }
);

// Clean up on scope close
// unsubscribe();
```

## API Reference

### SearchIndex Class

- `indexItem(item: SearchableItem): Promise<void>` - Index or update an item
- `removeItem(accountId, scopeId, itemId): Promise<void>` - Remove an item
- `search(accountId, scopeId, query, limit?): Promise<SearchResult[]>` - Search for items
- `rebuildIndex(accountId, scopeId, items): Promise<void>` - Rebuild index for a scope
- `rebuildIfNeeded(accountId, scopeId, items): Promise<boolean>` - Rebuild if needed

### Standalone Functions

- `indexItem(item, itemToSearchText?)` - Index an item
- `removeItem(accountId, scopeId, itemId)` - Remove an item
- `search(accountId, scopeId, query, limit?)` - Search
- `rebuildIndex(accountId, scopeId, items, itemToSearchText?)` - Rebuild index
- `rebuildIfNeeded(accountId, scopeId, items, itemToSearchText?)` - Rebuild if needed
- `getIndexState(accountId, scopeId)` - Get index state
- `shouldRebuild(accountId, scopeId, expectedVersion?)` - Check if rebuild needed
- `resetDatabase()` - Reset entire database (for testing/debugging)

## Notes

- **Firestore is canonical**: The index is a derived cache. Always fetch item details from Firestore.
- **Index is scoped**: Each `(accountId, scopeId)` combination has its own index.
- **FTS5 syntax**: The search uses FTS5's MATCH operator. Queries are tokenized automatically.
- **Performance**: Designed for < 1k items per scope. For larger scales, consider pagination or alternative approaches.
