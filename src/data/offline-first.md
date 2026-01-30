# Offline Data v2 (Optional Modules)

This template supports online-only apps (still using native Firebase), while providing a clear path for apps that need robust offline behavior.

**Canonical doc**: see `SETUP.md` (“Offline-ready + multi-doc correctness (request docs)”).

## Current Status

- ✅ **Online-first implementation**: `FirestoreRepository` (direct Firestore reads/writes)
- ⏳ **Offline-ready mode (native Firestore)**: native Firebase scaffolding exists; wiring a full offline-ready repository is still app-specific
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

## Online-first usage (current)

```typescript
import { createRepository } from '@/data/repository';

const repo = createRepository<MyEntity>('users/{uid}/objects', 'online');
const items = await repo.list();
```

## Offline-ready apps (planned)

See `SETUP.md` for:

- the native-first runtime assumptions (dev client, not Expo Go)
- scoped listener rules
- optional SQLite FTS "search-index-only" module
- request-doc workflows (the default for multi-doc invariant operations)

Important (React Native): this skeleton assumes **native Firestore** for durable offline persistence.
