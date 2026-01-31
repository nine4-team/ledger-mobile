# Offline-First Principles (UX + Correctness Invariants)

This doc defines the offline-first principles that every feature must follow. These are **product invariants** and **architecture constraints**.

Related canonical specs:

- [`OFFLINE_FIRST_V2_SPEC.md`](../../../../OFFLINE_FIRST_V2_SPEC.md)
- [`target_system_architecture.md`](./target_system_architecture.md)

---

## North star: local-first correctness

### Principle 1: Firestore (native) is the UI source of truth

- Screens render from **Firestore reads** using the **native SDK’s local cache**.
- User edits write to Firestore **immediately**; the native SDK applies them locally and syncs when network is available.
- A mutation is “done” for the user when it is **accepted locally** by Firestore (even if not yet synced).

Notes:

- “Firestore as source of truth” means **Firestore documents**, not an extra canonical SQLite store.
- SQLite is allowed only as a **derived, rebuildable index** (e.g., offline search), never as the authoritative entity store.

### Principle 2: Sync is asynchronous and visible (but we don’t build a sync engine)

- Network is unreliable; sync must be **durable** and **recoverable**.
- We rely on **Firestore’s built-in queued writes + cache** for baseline offline behavior.
- The app surfaces simple, user-trustworthy status:
  - pending writes (e.g., from snapshot metadata / SDK APIs)
  - last-known online/offline state
  - last sync error (where observable)

### Principle 3: Collaboration without read amplification

- We do not subscribe to unbounded data.
- While foregrounded in a scope (e.g., active project / active inventory), the app may attach **scoped listeners** only:
  - bounded queries (e.g., by `projectId`, with reasonable limits)
  - small, explicit “current context” listeners (e.g., active project doc, memberships)
- Listener lifecycle is explicit:
  - detach on background
  - reattach on resume

---

## UX invariants (what users must always experience)

### Invariant A: No “spinners of doom”

- If local data exists, show it immediately.
- Use visible “staleness”/sync indicators rather than blocking the UI.

### Invariant B: Offline is a first-class state

When offline:

- all browsing works from cached Firestore data when available
- create/update/delete works locally (queued writes)
- media capture works locally (queued upload)
- actions that truly require network (e.g., login) show a clear message and a retry path

### Invariant C: Make pending changes obvious, not scary

- Always show a global pending changes indicator when Firestore has pending writes.
- Provide a manual “Retry” action that:
  - attempts to refresh connectivity / reattach listeners (where applicable)
  - re-issues any explicit “pull to refresh” reads (where your UI supports it)

### Invariant D: Never lose user work silently

- queued writes are durable (Firestore persistence)
- failed operations surface as actionable errors (not just logs)
- user can retry or revert a local pending change (where feasible)

---

## Background limitations (mobile reality)

iOS background execution is constrained. The architecture assumes:

- foreground = strong guarantees (fast propagation)
- background = best effort

Rules of thumb:

- detach listeners when backgrounded
- on resume, reattach scoped listeners for the active scope (and re-run any explicit refresh reads if the UI supports it)
- don’t promise “instant sync in background”; promise “syncs when you reopen / when network returns”

---

## Correctness rules for writes (local-first)

### Local write contract

Every user mutation must be safe locally:

- validate inputs (domain layer)
- write to Firestore (single-doc where possible)
- if the operation is multi-doc or requires invariants, use **request-doc workflows** (see below)

Do not implement “multi-doc client updates” as the default; they are the easiest way to create inconsistent state offline.

### Idempotency (request-doc workflows)

- For request-doc operations, retries must not double-apply server-side changes.
- Prefer “retry = create a new request doc” unless the specific request type is explicitly designed to be reset/replayed safely.

### Tombstones for deletes

Deletes must be observable and listener-safe:

- remote delete = set `deletedAt` (and `updatedAt`) rather than hard delete
- clients filter out tombstoned records (or move them to “archived/deleted” views)

---

## Conflict stance (simple and user-trustworthy)

Conflicts are inevitable in collaboration. The goal is not “zero conflicts”; the goal is **trust**.

### Default policy

- For low-risk fields (text, notes, descriptions): prefer automatic merge/“last write wins” with auditability.
- For high-risk fields (money, tax, category allocation): do not silently overwrite if the remote changed since the user’s base version.

### Concrete mechanism (feature-specific)

- For high-risk edits, implement one of:
  - **request-doc** workflow (server validates base conditions and either applies or fails)
  - explicit “compare before commit” UX (re-read, show diff, ask user to confirm)

Avoid introducing a general-purpose conflict table unless the product truly needs it; prefer request-doc flows where correctness matters.

---

## Media is also offline-first

- Captured images/PDFs are stored locally immediately.
- Upload is queued and retried.
- The UI must show clear attachment states:
  - `local_only`
  - `uploading`
  - `uploaded`
  - `failed` (with retry)

---

## Feature author checklist (use in every feature spec)

When writing/implementing any feature:

- Does the UI read/write Firestore (native) in a cache-friendly way?
- Is your listener/query scope bounded?
- Do deletes use tombstones (`deletedAt`)?
- Does the feature avoid unbounded listeners?
- Are pending/error states visible and actionable?
- For multi-doc/critical invariants: did you use a request-doc workflow (or justify why not)?

