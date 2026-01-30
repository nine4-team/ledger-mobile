## Offline Data v2 (Skeleton Spec)

This document updates the template’s “offline-first” direction for a **native-first** skeleton.

We standardize on:

- **Firebase Native (React Native native modules)** for Auth + Firestore
- **Firestore-native offline persistence** (“Magic Notebook” behavior)
- **Scoped listeners**
- **Request-doc workflows** for multi-doc invariant correctness

We explicitly do **not** support an Expo Go runtime for apps that claim to be offline-ready.

### Goals (what this skeleton should support)

- **Default is native-first**: the skeleton uses Firebase native modules and a dev client workflow.
- **Offline-ready is the baseline**: offline reads/writes and queued writes “just work” via **Firestore-native offline persistence**.
- **No custom sync engine**: the skeleton should not push a “SQLite as source of truth + outbox + delta cursors” architecture.
- **Optional robust offline item search**: apps that need multi-field offline search can add a **derived local search index** without making SQLite authoritative.
- **Multi-doc correctness is not optional**: the skeleton must support a safe default for actions that update multiple docs or enforce invariants. The recommended default is a **request-doc pattern** (Cloud Function applies the change atomically).

### Non-goals

- Building a generic “sync engine” (outbox, cursors, conflict tables, meta sync docs).
- Making SQLite a canonical datastore for entities.
- Mandating robust offline local search for every app.

---

## Architecture: extracted “Option A” primitives (generalizable)

### 1) Firestore is the canonical datastore (when offline-ready mode is enabled)

When the app opts into native Firestore, treat Firestore (via native RN SDK) as a **synced local database**:

- Reads return cached data immediately when available.
- Writes apply locally immediately and sync when network is available.
- Real-time listeners drive UI state (bounded to the active scope).

This is the skeleton default for offline-ready apps because it avoids building and maintaining a bespoke sync pipeline.

### 2) Scoped listeners (never unbounded)

Listeners are allowed, but must be **scoped**:

- **Allowed**: active project / active inventory scope listeners.
- **Disallowed**: “listen to everything across all projects/accounts”.
- **Lifecycle**: detach listeners on background; reattach on resume.

### 3) SQLite is allowed only as a derived index (optional module)

Firestore is not a full-text search engine. For apps that require offline multi-field search over “items”, we add a **local derived search index**:

- SQLite/FTS stores searchable text for items.
- The index is **rebuildable** and **non-authoritative**.
- UI uses the index only to get candidate IDs; item details still come from Firestore.

Apps that don’t need offline local search should not pay the complexity cost of this module.

### 4) Request-doc operations (the default for multi-doc correctness)

For user actions that must update multiple docs consistently, the default is **request docs**:

- Client writes a `request` doc (works offline if Firestore-native offline is enabled).
- Cloud Function processes the request in a transaction once it reaches the server.
- Request doc records `status` and error info for debuggable UX.

This enforces correctness (no partial multi-doc client updates) without requiring an outbox/sync engine.

Direct client writes are allowed for:

- **single-doc** changes, or
- **provably safe** multi-doc changes that cannot create inconsistent states (rare; must be justified in the feature spec).

---

## Skeleton decisions / configuration surface

### Runtime and workflow (required)

- **Expo Go is not supported** for this skeleton.
- Use an **EAS dev client** (or equivalent native build) for development.
- Firebase must be the **native** SDK so Firestore offline persistence works as designed.

### Optional modules

- `offlineSearchIndex: boolean`
  - Enables SQLite FTS indexing for item search within a bounded scope.

Notes:

- **Request-doc workflows are not “optional correctness.”** Some apps may never need multi-doc invariant workflows, but the skeleton should still provide the request-doc framework (types, helpers, UI states) so teams don’t invent unsafe ad-hoc multi-doc client updates.
- **Offline search index is optional in the skeleton, not optional in every product.** Product templates that require robust offline multi-field search should enable this by default and treat it as required for that template.

---

## Required documentation changes in this repo (to align the skeleton)

These changes remove the old “outbox + cursor pulls” guidance and replace it with v2 guidance.

### Update `src/data/offline-first.md`

Replace the current “future implementation” section (SQLite + outbox + sync engine) with:

- **Two-track guidance**:
  - **Native-first default**: listeners + offline writes “just work”
- **Optional search index module** (SQLite FTS) explicitly labeled “index-only”
- **Request-doc workflows** as the default for multi-doc invariant operations
- Explicitly mark: “We do not build an outbox/delta sync engine in this skeleton.”

### Update `README.md`

In the “Offline-First vs Online-First” section:

- Replace: “Offline-first = SQLite + outbox + batch sync (recommended)”
- With:
  - **Native-first** (default): native Firestore SDK + scoped listeners (offline-ready baseline)
  - **Optional offline search**: SQLite FTS index (only if the app needs robust offline search)
- Replace “Cost levers” guidance that recommends cursor pulls/outbox as the default.
  - Keep cost guidance, but express it in listener-scoping terms:
    - bounded queries
    - avoid broad listeners
    - detach on background
    - instrument reads/writes/listener count

### Update `.cursor/plans/expofirebaseskeleton_16dcfb2b.plan.md`

Replace the “offline-first implementation” direction:

- Remove: “SQLite + outbox + sync engine”
- Add: “Offline-ready (Firestore-native offline) + optional search index + request-doc correctness workflows”

---

## Optional module spec: Offline “Item Search Index” (SQLite FTS)

This module should only be implemented/used by apps that require **robust local search** while offline.

### Assumptions / scope

- Target scale: **< 1k items per scope** (e.g., per project).
- Search is multi-field: name/description/sku/notes/source/vendor/etc.
- The index can be rebuilt from Firestore-cached items (or an explicit fetch).

### Schema (minimum viable, index-only)

- Table `item_search`:
  - `account_id` (TEXT)
  - `scope_id` (TEXT) – e.g. `project_id` or `inventory` sentinel
  - `item_id` (TEXT PRIMARY KEY in scope, or composite uniqueness)
  - `updated_at_ms` (INTEGER)
  - `search_text` (TEXT)
- FTS virtual table over `search_text` (FTS5 preferred).
- Optional: `search_index_state`:
  - `account_id`, `scope_id`
  - `index_version` (INTEGER)
  - `last_rebuild_at_ms` (INTEGER)

### Indexed fields (deterministic)

Define a single function to generate `search_text` from an item. Include only what the app needs. Recommended baseline fields:

- `name`
- `description`
- `sku`
- `source` / `vendor`
- `notes`

Normalization (simple + deterministic):

- lowercase
- trim
- collapse repeated whitespace
- optionally strip punctuation

### Update strategy (from Firestore snapshots)

When the active scope is open:

- On added/Request-doc-applied/modified item docs: upsert into index.
- On removed item docs: delete from index.

### Rebuild strategy

Rebuild on:

- first scope open
- `index_version` bump (fields changed)
- detected corruption (missing tables)
- optional debug action “Rebuild search index”

Failure handling:

- the index may be dropped and rebuilt at any time; Firestore remains canonical.

---

## Request-doc workflows (multi-doc correctness)

### When to use

Use request docs when a user action would otherwise require:

- updating multiple docs atomically, or
- enforcing invariants that should not live in client code.

### Collection shape (recommended)

Use a scoped requests collection; choose one or both depending on your domain:

- `accounts/{accountId}/projects/{projectId}/requests/{requestId}`
- `accounts/{accountId}/inventory/requests/{requestId}`

Common fields:

- `type`: string enum (e.g. `ALLOCATE_ITEM`, `SELL_ITEM`, `TRANSFER_ITEM`)
- `status`: `"pending" | "applied" | "failed"`
- `createdAt`, `createdBy`
- `appliedAt?`
- `errorCode?`, `errorMessage?` (safe, non-sensitive)
- `payload`: minimal IDs + fields needed

### Server processing

- Cloud Function triggers on request creation.
- Validates auth/permissions.
- Applies changes in a Firestore transaction.
- Updates request status and writes any resulting docs.

### Required plumbing (to make this safe, not a half-measure)

The skeleton must (eventually) include, or explicitly require:

- **Cloud Function** that processes request docs and is the *only* writer of `status = applied|failed`.
- **Security rules** that allow clients to:
  - create request docs (typically only with `status: "pending"`)
  - read request docs/status
  - **not** forge “applied” (clients must not be able to set/overwrite `status`, `appliedAt`, or server error fields)
- **Retry model**: default retry is **create a new request doc** (avoid resetting/rewriting an existing request unless the operation is explicitly designed for it).

### UX requirements

UI must represent:

- pending (queued/offline)
- applied
- failed (with retry)

Retry mechanism:

- “Retry” can write a new request doc (preferred) or reset status if safe.

---

## Phased work plan (each phase fits one AI-dev chat)

### Phase 1 — Doc realignment (skeleton-wide)

**Goal**: remove the outbox/cursor offline-first recommendation and replace it with Offline Data v2.

- Update `src/data/offline-first.md`
- Update `README.md` (offline-first + cost levers language)
- Update `.cursor/plans/expofirebaseskeleton_16dcfb2b.plan.md` (offline-first direction)

**Done when**: the repo no longer recommends “SQLite + outbox + cursor pulls” as the default offline approach.

### Phase 2 — Add “offline-ready backend mode” spec + scaffolding hooks

**Goal**: implement the native Firebase initialization module and ensure the template is fully dev-client-first.

- Add/standardize `src/firebase/firebase.native.ts` (native SDK init)
- Stop documenting any non-native runtime as the **offline-ready** path
- Document build requirements (dev client / prebuild)

**Done when**: an app author can follow docs to choose **online-only vs offline-ready**, and understands both use the native SDK (offline-ready relies on native offline persistence).

### Phase 3 — Optional module: local search index

**Goal**: implement (or at least scaffold) the “search-index-only” module in a way apps can opt into.

- Add `src/search-index/` (or `src/data/searchIndex/`) with:
  - schema/migrations
  - `indexItem`, `removeItem`, `search(query) -> itemIds`
  - rebuild utilities
- Document expected item shape / mapping function

**Status**: implemented in `src/search-index/` (SQLite FTS, rebuild utilities, docs).

**Done when**: offline search can return candidate IDs from local SQLite and stays consistent with Firestore snapshots.

### Phase 4 — Correctness framework: request docs

**Goal**: add a generalized request-doc pattern that can be reused by apps.

- Add function template(s) in `firebase/functions/`:
  - `onCreate` handler for `requests/*` docs
  - shared status/error helpers
- Add Firestore rules guidance (or starter rules) so clients can create/read requests but cannot forge “applied”.
- Add client helpers:
  - `createRequestDoc(type, payload, scope)`
  - `subscribeToRequest(requestId)` / status UI helpers

**Done when**: the skeleton supports “queued offline request → server applies later → UI reflects status”.

---

## Acceptance checklist (repo-level)

- `README.md` does not recommend outbox/cursor-based sync as the skeleton default.
- `src/data/offline-first.md`:
  - treats SQLite as optional search-index-only
  - describes native Firestore offline as the offline-ready path
  - describes request-doc workflows as the multi-doc correctness primitive
- `.cursor/plans/expofirebaseskeleton_16dcfb2b.plan.md` aligns with Offline Data v2.

