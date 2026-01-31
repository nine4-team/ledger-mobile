# Offline Data v2 (Optional Modules)

This template supports online-only apps (still using native Firebase), while providing a clear path for apps that need robust offline behavior.

**Canonical doc**: see `SETUP.md` (“Offline-ready + multi-doc correctness (request docs)”).

## Current Status

- ✅ **Native Firestore implementation**: `FirestoreRepository` (direct reads/writes via native SDK)
- ✅ **Offline persistence baseline**: Firestore-native offline persistence is enabled by default (native SDK)
- ✅ **Listener-based API**: `subscribe()` and `subscribeList()` methods available for real-time updates
- ✅ **Scoped listener manager**: implemented in `src/data/listenerManager.ts` with lifecycle management
- ✅ **Offline UX primitives**: implemented in `src/components/OfflineUX.tsx` and `src/offline/offlineUxStore.ts`
- ✅ **Offline search index (SQLite FTS)**: implemented in `src/search-index/` (optional module)
- ✅ **Request-doc workflows (multi-doc correctness)**: implemented (functions + rules + client helpers)

## Two-track guidance

### Native-first default: listeners + offline writes "just work"

For apps that need offline to "just work", the recommended primitive is:

- **Firestore-native offline persistence** (via native RN Firebase SDK) + **scoped listeners**
- Reads return cached data immediately when available
- Writes apply locally immediately and sync when network is available
- Real-time listeners drive UI state (bounded to the active scope)

This is the skeleton default for offline-ready apps because it avoids building and maintaining a bespoke sync pipeline.

**We do not build an outbox/delta sync engine in this skeleton.**

### Optional search index module (SQLite FTS) — index-only

SQLite is allowed only as an **optional, rebuildable local search index** (not an authoritative database).

- SQLite/FTS stores searchable text for items
- The index is **rebuildable** and **non-authoritative**
- UI uses the index only to get candidate IDs; item details still come from Firestore
- Apps that don't need offline local search should not pay the complexity cost of this module

**Implementation**: See `src/search-index/README.md` for usage and API documentation.

### Request-doc workflows: the default for multi-doc invariant operations

For any operation that updates multiple documents or enforces invariants, the recommended default is a **request-doc workflow**:

- Client writes a `request` doc (works offline if Firestore-native offline is enabled)
- Cloud Function processes the request in a transaction once it reaches the server
- Request doc records `status` and error info for debuggable UX

This enforces correctness (no partial multi-doc client updates) without requiring an outbox/sync engine.

**Implementation in this repo**:

- Cloud Functions: `firebase/functions/src/index.ts` (request processing triggers + helpers)
- Rules: `firebase/firestore.rules` (clients can create/read, cannot forge applied/failed)
- Client helpers: `src/data/requestDocs.ts`

## What changed from v1 guidance

This skeleton no longer recommends implementing a generic:

- SQLite "source of truth" entity store
- outbox queue
- delta cursors / "pull since cursor"

## Repository Usage Examples

### Online-first usage

```typescript
import { createRepository } from '@/data/repository';

const repo = createRepository<MyEntity>('users/{uid}/objects', 'online');
const items = await repo.list();
const item = await repo.get('item-id');
await repo.upsert('item-id', { name: 'Updated' });
```

### Offline-ready usage with real-time listeners

```typescript
import { createRepository } from '@/data/repository';
import { useEffect, useState } from 'react';

// Create repository with offline mode (cache-first reads)
const repo = createRepository<MyEntity>('users/{uid}/objects', 'offline');

// Subscribe to collection updates (works offline with cached data)
function MyComponent() {
  const [items, setItems] = useState<MyEntity[]>([]);

  useEffect(() => {
    // subscribeList returns an unsubscribe function
    const unsubscribe = repo.subscribeList((updatedItems) => {
      setItems(updatedItems);
    });

    // Cleanup on unmount
    return unsubscribe;
  }, []);

  return <ItemList items={items} />;
}

// Subscribe to a single document
function ItemDetail({ itemId }: { itemId: string }) {
  const [item, setItem] = useState<MyEntity | null>(null);

  useEffect(() => {
    const unsubscribe = repo.subscribe(itemId, (updatedItem) => {
      setItem(updatedItem);
    });

    return unsubscribe;
  }, [itemId]);

  return item ? <ItemView item={item} /> : <Loading />;
}
```

**Key points:**
- Both `'online'` and `'offline'` modes use the native Firestore SDK
- `'offline'` mode prefers cache-first reads (fallback to server)
- `subscribe()` and `subscribeList()` work offline with cached data
- Listeners fire immediately with cached data when available
- Always call the returned unsubscribe function in cleanup (useEffect return)

### Offline-ready usage with scoped listener manager

For apps that need lifecycle-aware listener management (automatic detach on background, reattach on resume), use the scoped listener manager:

```typescript
import { useScopedListeners } from '@/data/useScopedListeners';
import { createRepository } from '@/data/repository';

function ProjectScreen({ projectId }: { projectId: string }) {
  const scopeId = `project:${projectId}`;
  const [items, setItems] = useState<MyEntity[]>([]);

  // Listeners are automatically detached on background and reattached on resume
  useScopedListeners(scopeId, () => {
    const repo = createRepository<MyEntity>(
      `projects/${projectId}/items`,
      'offline'
    );
    return repo.subscribeList((updatedItems) => {
      setItems(updatedItems);
    });
  });

  return <ItemList items={items} />;
}
```

**Benefits of scoped listener manager:**
- Automatic lifecycle management (detach on background, reattach on resume)
- Centralized cleanup
- Scope-based organization (e.g., `project:{id}`, `account:{id}`)
- Prevents listener leaks

**See `src/data/LISTENER_SCOPING.md` for conventions and best practices.**

## Offline-ready apps (additional guidance)

See `SETUP.md` for:

- the native-first runtime assumptions (dev client, not Expo Go)
- scoped listener rules (bounded queries, detach on background)
- optional SQLite FTS "search-index-only" module
- request-doc workflows (the default for multi-doc invariant operations)

See `src/data/LISTENER_SCOPING.md` for:

- listener scoping conventions and naming patterns
- recommended scope limits
- usage examples with hooks and manual management
- debugging and monitoring tools

Important (React Native): this skeleton assumes **native Firestore** for durable offline persistence.
