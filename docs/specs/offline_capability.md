# Offline Capability (Ledger Mobile) — Spec

## Purpose

Define Ledger Mobile’s **offline capability** as a single, testable contract:

- what “offline-ready” means for users
- what the app guarantees when the network is flaky
- what data is safe to create/edit offline
- how we show connectivity + sync status without being noisy or misleading
- how we handle attachments (images/PDFs) offline
- how we avoid data inconsistencies without building a custom sync engine

This spec consolidates the Firebase migration plan’s “Offline Data v2” direction with the current implementation in `src/`.

## Scope

### In scope

- Firestore-native offline behavior (cache + queued writes)
- Connectivity signal (online/offline/slow) and how we prevent “false offline”
- Sync status UI (pending/syncing/waiting/error) across:
  - Firestore queued writes
  - request-doc workflows (multi-doc correctness)
  - attachment uploads
- Request-doc pattern for multi-doc correctness and conflict handling
- Offline media lifecycle (local cache → upload queue → attach remote URL → cleanup)
- Scoped listeners and lifecycle (detach on background, reattach on resume)
- Optional offline search index (SQLite FTS) as **index-only**
- Testing and local dev guidance (emulators + offline simulation)

### Out of scope

- Exact UI layout/styling and final copywriting (except where copy is part of the contract)
- A bespoke “outbox + delta cursor sync engine” (explicitly not the approach)
- A full “manage offline storage” UI (browse/delete cached blobs)
- Detailed iOS/Android background execution guarantees beyond “best effort”

## Definitions / glossary

- **Offline-ready**: The user can browse cached data, make edits, and capture media without a reliable connection; changes sync later.
- **Firestore-native offline persistence**: Using the native Firestore SDK cache + queued writes. Firestore behaves like a “synced local DB”.
- **Pending writes**: Local writes accepted by Firestore that are not yet acknowledged by the server.
- **Request doc / request-doc workflow**: Client writes a “request” doc (safe offline). A Cloud Function later applies the change in a server transaction and writes `status`.
- **Scoped listeners**: Real-time listeners limited to the currently active scope (e.g., one project), detached on background.
- **AttachmentRef**: A stable reference embedded on a domain doc (e.g., `transaction.receiptImages[]`). `url` can be remote or `offline://<mediaId>`.
- **Local media cache**: Local file copy + local metadata record keyed by `mediaId`.
- **Upload job**: Durable local job record describing “upload mediaId to destinationPath”.

## Core architecture (offline data v2)

### North star

**Firestore (native SDK) is the UI source of truth.**

- Reads should prefer cache where appropriate and show cached data immediately when available.
- Writes should apply locally immediately; syncing is asynchronous.
- A mutation is “done” from the user’s perspective once it is **accepted locally** (even if not yet synced).

### What we are not building

- No canonical SQLite entity store.
- No generic outbox / cursor-based delta sync engine.

SQLite is allowed only as a **derived, rebuildable index** for offline search.

### Listener model (collaboration without read amplification)

- Listeners must be **bounded to an explicit scope** (project/inventory/account).
- Listener lifecycle must be explicit:
  - detach when app backgrounds
  - reattach when app resumes
- Avoid unbounded “listen to everything” patterns.

## UX invariants (always true)

1. **No “spinner of doom”**
   - if local data exists, show it immediately
   - show staleness/sync indicators instead of blocking
2. **Offline is first-class**
   - browsing works from cached Firestore data (when available)
   - create/update/delete works locally (queued writes)
   - media capture works locally (queued upload)
3. **Pending changes are obvious, not scary**
   - show small global UI when there are pending changes or sync errors
4. **Never lose user work silently**
   - queued writes and upload jobs should survive restarts (durable local storage)
   - failures surface in UI with a retry path

## Connectivity signal (stop “lying” on flaky networks)

### Problem statement

On mobile, the OS/network stack can be flaky. A generic connectivity library can report “offline” even when some apps still work (or when only certain hosts are blocked).

We want:

- a connectivity signal that is **stable** (doesn’t flicker)
- “offline” only when it’s likely the app truly can’t reach its services
- “slow” when the network is poor but usable

### Connectivity model (two inputs → one user-facing state)

We combine:

1. **OS reachability** (NetInfo): best-effort “internet reachable”
2. **App-specific health check**: a lightweight check that “Ledger services are reachable”

And we apply a **grace period / debounce** so brief blips do not flip the UI.

### App-specific health check (recommended)

The health check must be:

- **cheap** (one tiny request)
- **rate-limited** (no spam)
- **non-blocking** (never delay initial UI render)
- **environment-aware** (works with emulators when enabled)

Accepted health check options:

- **Firestore ping**: read a known lightweight doc from the server (e.g., `health/ping`) using a server-preferring read.
- **Cloud Function ping**: call a simple HTTP/Callable “ping” function.

Spec requirement:

- A failed health check should *not* immediately force “offline” if we still have cached data; it should contribute to the connectivity state once it fails consistently.

### Grace period / debounce (recommended defaults)

We introduce two timing guards:

- **Offline confirmation delay**: do not show “Offline” until the combined signal has been “offline” for at least \(T_{offline}\).
  - Recommended default: \(T_{offline} = 5s\) to \(15s\) (tune after dogfooding).
- **Online confirmation delay**: once we think we’re back online, require a short stable period before clearing “Offline”.
  - Recommended default: \(T_{online} = 1s\) to \(3s\).

Rationale:

- avoids banner flicker on blips
- prevents false “offline” when the reachability check URL is briefly blocked

### User-facing connectivity UI

Global top strip (`NetworkStatusBanner` behavior):

- If offline: show **“Offline - Changes will sync when reconnected”**
- If online but slow: show **“Slow connection detected”**
- Otherwise: show nothing

Notes:

- This banner should reflect the **debounced combined** connectivity state (not raw NetInfo).
- Slow vs offline should prefer “slow” when health checks succeed but the network is poor.

## Sync status (what’s pending, what failed, what can be retried)

### What sync status covers

Sync status is a combined, user-facing summary of:

- **Firestore pending writes**
- **request docs** (pending / failed)
- **attachment uploads** (pending / failed)

It is intentionally not “listener health” or “realtime subscription health”.

### Sync status UI surfaces

- **Sync status pill**: small floating pill that appears only when relevant
- **Retry sync** button: available only in error state (expand-on-tap)
- **Background sync error toast**: small toast for best-effort background errors

### Status precedence (highest wins)

1. **error**
2. **syncing**
3. **waiting** (pending + offline)
4. **queue** (pending + online)
5. **idle** (renders nothing)

### Manual recovery (“Retry sync”)

When the user taps **Retry sync**, the app performs a best-effort foreground recovery:

- reattach scoped listeners / refresh scopes
- refresh tracked request doc statuses
- retry pending uploads

This must be safe to run repeatedly.

## Data behaviors by category

### 1) Reads (browse while offline)

Requirements:

- Show cached data immediately if available.
- If cache is empty and the network is unavailable, show a clear empty/offline state (not an infinite spinner).
- Prefer scoped listeners for “live” screens (bounded to current scope).

### 2) Simple writes (single-doc)

Default approach:

- direct Firestore writes (create/update/delete) are allowed when they only update one doc and cannot violate multi-doc invariants
- writes should be accepted offline (queued) and reflected immediately in UI

Deletes:

- prefer tombstones (`deletedAt`) over hard delete so listeners stay stable and conflict handling is simpler

### 3) Correctness-critical writes (multi-doc / invariants)

Default approach:

- use a **request-doc workflow**
- client creates request doc while offline
- server applies later in a transaction
- request doc updates `status` to `applied` or `failed/denied`
- UI reflects request state and supports retry

Examples of operations that should be request-doc by default:

- anything that must update multiple docs atomically
- anything money/tax/category-related where silent overwrites would break trust
- anything that must enforce permissions/roles in a server-verified way

## Request-doc workflow: contract

### Request doc shape (minimum)

Fields:

- `type` (string)
- `status`: `pending | applied | failed | denied`
- `opId` (idempotency key)
- `createdAt`, `createdBy`
- `appliedAt?`
- `errorCode?`, `errorMessage?`
- `payload` (minimal required fields)

### Retry model

Default retry behavior:

- **retry = create a new request doc**

This avoids tricky “reset/replay” semantics unless a request type is explicitly designed for it.

### Security + ownership

- Clients may create request docs and read statuses.
- Clients must not be able to forge `applied/failed` status or server fields.

## Attachments offline (media lifecycle)

### Domain data model

Domain entities store attachment references inline (embedded), using a shared shape:

- `AttachmentRef`:
  - `url: string` (remote URL or `offline://<mediaId>`)
  - `kind: "image" | "pdf" | "file"`
  - `contentType?`
  - `fileName?`
  - `isPrimary?`

**Important**: Domain docs do **not** store transient upload state.

### Required UI states (derived locally)

Any attachment renderer must support:

- `local_only`
- `uploading`
- `uploaded`
- `failed` (with retry)

State is derived by joining:

- the entity’s `AttachmentRef.url` (`offline://<mediaId>`) with
- the local media record + upload job

### Required behaviors

- Selecting/capturing media persists a local copy immediately (best effort).
- Create an `AttachmentRef` pointing to `offline://<mediaId>`.
- Enqueue an upload job with an idempotency key.
- When upload succeeds:
  - replace the `AttachmentRef.url` with the remote URL
- Cleanup must exist (best effort) to avoid leaking storage:
  - user cancels after local save
  - entity deleted while upload pending
  - attachment replaced
  - post-upload local cache policy

### Global retry integration

The global “Retry sync” action should also attempt to process pending uploads.

## Offline local search (optional module)

If enabled, the SQLite search index must follow these rules:

- index-only, rebuildable, non-authoritative
- returns candidate IDs only
- UI still reads full details from Firestore
- scoped by `(accountId, scopeId)` (e.g., per project)
- rebuild triggers:
  - first scope open
  - version bump
  - corruption detected
  - optional debug “Rebuild index”

## Background behavior (mobile reality)

- Background execution is constrained (especially on iOS).
- Correctness must not depend on background sync.
- Promise to users should be:
  - “syncs when you reopen / when the network returns”
  - not “instant sync in the background”

## Current implementation map (what exists in `src/` today)

This section helps keep the spec grounded. It lists the current building blocks and the notable gaps to close.

### Connectivity + banners

- ✅ `src/hooks/useNetworkStatus.ts`: NetInfo-based reachability snapshot (`isOnline`, `isSlowConnection`).
- ✅ `src/components/NetworkStatusBanner.tsx`: renders offline/slow banner based on `useNetworkStatus`.
- ⚠️ **Missing (planned by this spec)**:
  - debounce / grace period before flipping offline/online
  - app-specific health check (Firestore/Function ping)

### Sync status + manual retry

- ✅ `src/sync/syncStatusStore.ts`: global counts + error surfaces.
- ✅ `src/components/SyncStatusPill.tsx`: pending/syncing/waiting/error pill + “Retry sync” in error.
- ✅ `src/sync/syncActions.ts`: manual sync refresh (refresh scopes + refresh request docs + retry uploads).
- ⚠️ `src/sync/pendingWrites.ts`: pending writes indicator is **best-effort**:
  - Firestore queued writes are durable, but the in-memory counter may reset on app restart.

### Request docs

- ✅ `src/data/requestDocs.ts`: create + subscribe helpers (creates are offline-safe).
- ✅ `src/sync/requestDocTracker.ts`: durable tracking of request doc paths via AsyncStorage + updates sync counts.
- ⚠️ Must be wired at app start: `startRequestDocTracking()` needs to be called from the app shell.

### Offline media (attachments)

- ✅ `src/offline/media/mediaStore.ts`: durable local records + upload jobs (AsyncStorage) and `offline://<mediaId>` contract.
- ✅ Cleanup helpers: `deleteLocalMediaByUrl`, `cleanupOrphanedMedia`.
- ⚠️ Upload execution is “pluggable”:
  - an upload handler must be registered via `registerUploadHandler(...)`
  - `hydrateMediaStore()` must run on app start so offline attachments resolve after restart

### Scoped listeners

- ✅ `src/data/listenerManager.ts` + `src/data/useScopedListeners.ts`: lifecycle-aware scoped listeners (detach on background, reattach on resume).
- ✅ Listener scoping conventions: `src/data/LISTENER_SCOPING.md`.

### Offline local search (optional)

- ✅ `src/search-index/*`: SQLite FTS index-only module with rebuild utilities.

## Testing + local dev

### Emulator setup (required for offline-ready dev)

- Use Firebase emulators for Auth/Firestore/Functions (and Storage if used by uploads).
- Ensure the app uses native Firebase modules (dev client), not Expo Go.

### How to test offline behavior (manual checklist)

Connectivity + banner stability:

- Start online → no banner.
- Introduce brief network blips → banner should **not** flicker rapidly (debounce).
- Fully offline for > \(T_{offline}\) → show offline banner.
- Restore online → banner clears after \(T_{online}\).

Pending writes:

- Make an edit while offline → UI updates immediately, SyncStatus shows pending/waiting.
- Restore network → pending clears after server ack, SyncStatus returns to idle.

Request docs:

- Trigger a request-doc operation while offline → request remains pending locally.
- Restore network → request becomes applied/failed and UI updates accordingly.

Attachments:

- Capture/select attachment while offline → renders as `local_only`.
- Restore network → upload progresses to `uploaded`, attachment URL becomes remote.
- Force an upload failure → shows `failed` with retry.

### How to simulate flakiness

- Use the simulator’s network conditioning tools (slow/very bad network).
- Toggle Wi‑Fi off/on quickly to reproduce flicker.
- Test with a VPN/proxy/content filter enabled (common false-offline cause).

## Open questions / follow-ups (intentionally tracked)

These are known gaps to resolve as we harden offline behavior:

1. **Cache limits and eviction**: what’s our expected behavior if Firestore cache is cleared/evicted?
2. **Health check target**: do we standardize on Firestore doc ping or Function ping?
3. **Retry backoff policy**: classify retryable vs terminal errors for uploads and request-doc failures.
4. **Conflict UX**: specific UI patterns for “high-risk conflicts” (money/tax/category) beyond request-doc failure messaging.
5. **Listener timing**: define expected attach/detach timing and how we measure “healthy” listeners.
6. **Media quota thresholds**: define concrete thresholds + user-visible guidance for freeing space.

---

## References (source docs)

These were the main sources consolidated into this spec:

- `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`
- `.cursor/plans/firebase-mobile-migration/00_working_docs/OFFLINE_FIRST_V2_SPEC.md`
- `.cursor/plans/firebase-mobile-migration/40_features/connectivity-and-sync-status/*`
- `.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
- `.cursor/plans/firebase-mobile-migration/20_data/data_contracts.md` (AttachmentRef + `offline://` contract)

