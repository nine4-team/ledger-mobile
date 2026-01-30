# Option A Rewrite Handoff: Firestore-Native Offline (“Magic Notebook”) + Offline Item Search

This doc is the **multi-chat handoff plan** for rewriting the migration specs under:

- `.cursor/plans/firebase-mobile-migration/`

We are switching the architecture from:

- **SQLite as UI source of truth + explicit outbox + delta cursors + `meta/sync`**

to:

- **Firestore-native offline (native RN SDK)** as the canonical source of truth
- **Real-time listeners** (scoped to the active project/inventory)
- A **local, derived search index** (SQLite FTS) to support **offline multi-field item search** for **< 1k items per project**
- A **request-doc pattern** for operations that must update multiple docs consistently (inventory flows / lineage maintenance), so we keep correctness without building our own sync engine

This work is intentionally phased so that each phase fits in a single AI dev chat context window.

---

## North Star (what “done” looks like)

### Product goals

- Offline reads + writes “just work” via Firestore’s native offline persistence.
- Collaboration updates propagate via normal Firestore listeners (no custom signal doc).
- Items have **offline, multi-field search** (name/description/sku/notes/source/etc.) that is fast at < 1k items/project.
- Complex “one action updates many records” workflows still behave correctly and are debuggable.

### Spec goals

- No spec instructs feature authors to:
  - write SQLite entity tables as the canonical truth
  - enqueue an outbox op
  - run delta sync cursors
  - depend on `accounts/.../meta/sync`
- SQLite (if present) is documented as **search-index-only**, rebuildable, and non-authoritative.
- `20_data/data_contracts.md` remains the canonical field-list source of truth.

---

## Critical context (read this before editing)

### Key decision already made

- We are willing to **leave Expo managed** and use **native modules**, so we can use a **native Firestore SDK** and actually get mobile offline persistence.

### Known constraints from existing specs

- Money must be persisted as **integer cents** (correctness-critical).
- Two collaboration scopes:
  - **Project scope**: docs under `accounts/{accountId}/projects/{projectId}/...`
  - **Business inventory scope**: docs under `accounts/{accountId}/inventory/...` and `projectId = null` in domain model
- Attachments have an offline lifecycle: capture locally, queued upload, visible states.

### Files that reflect the *old* architecture (must be rewritten/deprecated)

- `40_features/sync_engine_spec.plan.md` (custom sync engine: outbox + delta + `meta/sync`)
- `10_architecture/offline_first_principles.md` (asserts SQLite source-of-truth)
- `10_architecture/target_system_architecture.md` (bakes in outbox/delta/meta/sync invariants)
- `20_data/local_sqlite_schema.md` (mirrored entity tables + outbox + cursors + conflicts)
- `70_ops/observability_and_cost_guardrails.md` (forbids “large listeners”; enforces single listener strategy)
- `30_app_skeleton/app_skeleton_spec.md` (boot + “sync wiring” based on outbox/delta/meta/sync)
- `40_features/connectivity-and-sync-status/README.md` (sync status depends on outbox/delta language)

### Files that should remain canonical (but may need small edits to remove old references)

- `20_data/data_contracts.md` (canonical entity shapes + money rules)

### Firestore model doc to update

- `20_data/firebase_data_model.md` currently references:
  - delta sync cursors
  - `meta/sync` change-signal
  - outbox idempotency fields
These need to be rewritten for Option A.

---

## Architecture summary (Option A)

### Core mental model

- Firestore is a **synced local database** (the SDK keeps a local cache).
- Reads come from local cache and update from the network when available.
- Writes are applied locally immediately and synced to the server when possible.

### Allowed runtime behavior

- Use Firestore listeners for:
  - active scope project item lists, transaction lists, spaces, attachments, etc.
- Detach listeners in background; reattach on resume.

### Offline search (the only local DB we keep)

Firestore is not a full-text search engine. We add a **derived local search index**:

- A SQLite FTS table for items (per project scope)
- Updated from Firestore snapshots in the active project
- Rebuildable from Firestore cache (and/or from a one-time fetch)
- Not authoritative; only used to return candidate item ids for the UI

### Multi-document “correctness operations”

Some operations must update multiple docs consistently. Instead of a client outbox/scheduler:

- Client writes one **request doc** (queued offline by Firestore)
- Server (Cloud Function) processes the request in a transaction when it reaches the server
- Request doc records status + error info
- UI shows “pending / failed / applied”

This keeps Option A “simple” while avoiding corrupt states.

---

## Phased plan (each phase fits one AI dev chat)

### Phase 0 — Inventory + alignment (read-only sweep + decision points)

**Goal**: Establish a shared baseline and identify all docs that must change.

**Tasks**
- List all spec files under `.cursor/plans/firebase-mobile-migration/` that mention any of:
  - `outbox`, `delta`, `cursor`, `meta/sync`, “SQLite is the UI source of truth”, “no large listeners”
- Produce a short map:
  - file → section heading(s) → what to rewrite/remove
- Confirm the expected offline search fields (item name/description/sku/source/notes/etc.)
- Confirm where request-doc pattern will be required (inventory allocation/sale/transfer + lineage + any other multi-doc flows).

**Deliverable**
- A short “rewrite map” section appended to this doc or a sibling doc listing all hits + sections.

**Done when**
- You can point to every place the old architecture leaks into feature specs.

---

### Phase 1 — Rewrite architecture docs (Option A principles + new invariants)

**Goal**: Replace foundational architecture assumptions so all later spec edits have a stable target.

**Update these files**
- `10_architecture/offline_first_principles.md`
  - Remove: “SQLite is UI source of truth”, outbox/delta/meta/sync/conflicts tables.
  - Add:
    - Firestore-native offline principles
    - “pending write” UX expectations
    - background/resume listener guidance
    - explicit statement: local SQLite is for *search indexing only* (if used)
- `10_architecture/target_system_architecture.md`
  - Replace system diagram and invariants with Firestore-first architecture:
    - UI reads/writes Firestore
    - listeners per active scope
    - derived local search index component
    - request-doc pattern for multi-doc operations

**New sections to include (recommended)**
- “What we no longer do” (outbox, delta cursors, `meta/sync`)
- “What we still measure” (listener count, query scope, write errors, request failures)
- “Failure modes” (rule rejection after offline write, request processing delays)

**Deliverable**
- Updated docs with clear “Option A” invariants and examples.

**Done when**
- These docs no longer reference `40_features/sync_engine_spec.plan.md` as canonical.

---

### Phase 2 — Replace the sync-engine spec with a deprecation + pointer

**Goal**: Prevent future readers from implementing the old system by accident.

**Update file**
- `40_features/sync_engine_spec.plan.md`

**Actions**
- Mark at top: **DEPRECATED** (with date), explain that Option A replaced it.
- Keep it only as historical context or archive it; ensure it is not referenced elsewhere.
- Add pointers to the new architecture docs and the new “search index” doc (created in Phase 3).

**Deliverable**
- A clear deprecation banner + removal of references across the spec set.

**Done when**
- No other specs cite `sync_engine_spec.plan.md` as a dependency.

---

### Phase 3 — Rewrite SQLite doc into “local search index only”

**Goal**: Keep offline multi-field search without bringing back a full local DB architecture.

**Update file**
- `20_data/local_sqlite_schema.md`

**Replace with**
- A minimal schema and rules for a search index, e.g.:
  - `item_search` table: `{ account_id, project_id, item_id, updated_at_ms, search_text }`
  - FTS virtual table over `search_text`
  - optional `search_index_state` table per scope: `{ account_id, project_id, index_version, last_rebuild_at_ms }`

**Must specify**
- Fields included in `search_text`:
  - name, description, sku, source/vendor, notes (and any others you decide)
- Normalization:
  - lowercase, trim, collapse whitespace, strip punctuation (simple + deterministic)
- Update strategy:
  - from Firestore item listeners: added/modified/removed → update index
- Rebuild strategy:
  - on first project open (or if corruption detected): rebuild from Firestore cached items (or an explicit fetch)
- Failure handling:
  - index can be dropped and rebuilt; Firestore remains canonical

**Deliverable**
- A search-index spec that is implementable and explicitly not a sync engine.

**Done when**
- No mirrored entity tables / outbox / cursor tables remain in this doc.

---

### Phase 4 — Update Firestore model doc to Option A + add request docs

**Goal**: Make `firebase_data_model.md` match the new reality: listeners + request docs + offline behavior.

**Update file**
- `20_data/firebase_data_model.md`

**Remove**
- delta cursor strategy sections
- `meta/sync` change-signal sections
- outbox/idempotency fields as requirements (treat any idempotency keys as optional and tied to request docs / functions if needed)

**Add**
- Listener-friendly guidance:
  - queries must be scoped to active project/inventory
  - avoid unbounded cross-project listeners
- Request-doc collections (one recommended shape):
  - `accounts/{accountId}/projects/{projectId}/requests/{requestId}`
  - `accounts/{accountId}/inventory/requests/{requestId}`
  - Common fields:
    - `type` (e.g. `ALLOCATE_ITEM`, `SELL_ITEM`, `TRANSFER_ITEM`)
    - `status: "pending" | "applied" | "failed"`
    - `createdAt`, `createdBy`
    - `appliedAt?`
    - `errorCode?`, `errorMessage?` (safe, non-sensitive)
    - `payload` (minimal ids + fields needed)

**Deliverable**
- A Firestore model doc that doesn’t imply custom sync and includes the request-doc primitive.

**Done when**
- This doc no longer mentions `meta/sync` or delta cursors.

---

### Phase 5 — Rewrite app skeleton spec (Firestore-first + search index + request UX)

**Goal**: Align the foundational app architecture with Option A so features naturally follow it.

**Update file**
- `30_app_skeleton/app_skeleton_spec.md`

**Replace sections**
- “Local-first data access pattern (hooks + services)”
  - Screens subscribe to Firestore queries/listeners (scoped).
  - Mutations write Firestore directly.
  - For request-type operations, create request doc.
- “Sync wiring”
  - Remove outbox/delta/meta/sync logic.
  - Add:
    - attach/detach listeners per active scope
    - on resume: reattach; optionally force a refresh/read (implementation detail)
- “Global UX components”
  - Sync status = pending writes + pending/failed requests + upload states.

**Add a new section**
- “Local search index initialization”
  - open SQLite search DB
  - keep it project-scoped
  - rebuild rules

**Deliverable**
- A skeleton spec that feature authors can follow without touching the old sync engine.

**Done when**
- Skeleton no longer references outbox/delta/conflicts as infrastructure.

---

### Phase 6 — Rewrite ops + cost guardrails for listener-based Firestore

**Goal**: Replace “no listeners” dogma with scoped-listener guardrails appropriate for < 1k items/project.

**Update file**
- `70_ops/observability_and_cost_guardrails.md`

**Replace**
- “Only one listener allowed” rule
- adapter that disallows general `onSnapshot`

**With**
- Listener scoping rules:
  - listeners must be scoped to active project/inventory only
  - detach when backgrounded
  - no unbounded “all projects” listeners
- Instrumentation:
  - count active listeners
  - log query paths / scope
  - track Firestore reads/writes over time
  - track request-doc failure rates

**Deliverable**
- Practical guardrails + telemetry for the new architecture.

---

### Phase 7 — Rewrite connectivity + sync status UX spec

**Goal**: Ensure UX spec matches Firestore-native offline and request-doc pattern.

**Update file**
- `40_features/connectivity-and-sync-status/README.md` (and related docs in that folder if needed)

**Replace language**
- outbox pending count → pending writes / pending requests
- delta catch-up → “listener catch-up / refresh”
- retry sync → retry failed request(s), retry uploads, reattach listeners

**Deliverable**
- A UX spec that a dev can implement without a sync engine.

---

### Phase 8 — Sweep + fix feature specs that reference outbox/delta/SQLite

**Goal**: Remove contradictions and update feature assumptions.

**Tasks**
- Search specs for the old architecture phrases and update:
  - “reads from SQLite only”
  - “enqueue outbox op”
  - “delta cursor”
  - “meta/sync”
- For features that relied on explicit conflict UI:
  - decide whether conflict UI becomes:
    - request-doc failure UI, or
    - “last-write wins” acceptance, or
    - a specialized flow for critical money edits (only if needed)

**Deliverable**
- Feature specs that don’t require the old system.

---

## Concrete grep checklist (spec directory)

Run a sweep in `.cursor/plans/firebase-mobile-migration/` for:

- `outbox`
- `delta`
- `cursorUpdatedAt` / `cursor_doc_id` / `sync_state`
- `meta/sync`
- `localPending` / `conflicts` (as infra tables)
- `SQLite is the UI source of truth`
- `no large listeners`

Every hit must be:

- removed, or
- replaced with Option A language, or
- explicitly marked DEPRECATED/historical.

---

## Notes on offline search implementation (spec-level guidance)

### Search UX expectation

- Offline search returns results from local index built from the items currently cached for that project.
- If the user has never opened the project (no cached items), search may be empty until initial data loads.

### Index rebuild triggers

- First project open
- App version upgrade that changes which fields are indexed (`index_version` bump)
- Index corruption detection (simple: missing tables/fts)
- “Rebuild search index” debug action (optional)

---

## Notes on request-doc operations (spec-level guidance)

Use request docs when a user action would otherwise require:

- updating multiple entity docs atomically, or
- enforcing correctness rules that shouldn’t live in client code.

UI should always be able to represent:

- pending
- applied
- failed (with retry)

This keeps offline UX honest: “I requested it; it’ll finalize when online.”

---

## Final completion criteria (for the whole rewrite)

You are done when:

- The architecture docs (`10_architecture/*`) describe Firestore-native offline, not custom sync.
- `40_features/sync_engine_spec.plan.md` is deprecated and not referenced.
- `20_data/local_sqlite_schema.md` describes only search indexing (no mirrored entity tables/outbox/cursors/conflicts).
- `30_app_skeleton/app_skeleton_spec.md` is Firestore-first and includes search-index init + request-doc UX.
- `70_ops/observability_and_cost_guardrails.md` supports scoped listeners, not “one listener only”.
- `40_features/connectivity-and-sync-status/*` no longer references outbox/delta.
- A repo-wide spec sweep finds **no active references** to outbox/delta/meta/sync as required architecture.

