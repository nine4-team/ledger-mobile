# Connectivity + sync status — Feature spec (Firebase mobile migration)

## Intent
Make offline-first behavior legible and trustworthy by providing **always-on, global UI** for:
- connectivity state (offline / slow)
- sync state (pending / syncing / waiting / error) for:
  - Firestore local queued writes
  - request-doc operations (multi-doc correctness workflows)
- a deterministic “Retry sync” affordance
- background/automatic sync error surfacing

This feature must align with Offline Data v2: **Firestore-native offline persistence** (Firestore is canonical), **scoped listeners**, and **request-doc workflows** for multi-doc correctness. See `OFFLINE_FIRST_V2_SPEC.md`.

## Owned UI surface (global)
These are global components mounted in the app shell, not routed screens:
- `NetworkStatus` (top banner)
- `SyncStatus` (floating bottom-right banner)
- `RetrySyncButton` (inline affordance, typically inside error state)
- `BackgroundSyncErrorNotifier` (toast-only; no visible UI)

## State model (sources of truth)

### Connectivity state
The app computes a local, cached **connectivity snapshot** that can be consumed without network calls:
- `isOnline`: best-effort “internet reachable”, not just “has network interface”
- `isSlowConnection`: coarse slow-connection indicator
- `lastOnline`: last time we were known-online
- `lastOfflineReason`: optional debug string (not required to show to users)

Parity evidence (web):
- `src/services/networkStatusService.ts` (navigator events + remote health ping + `isSlowConnection`)
- `src/hooks/useNetworkState.ts`

Firebase/RN adaptation notes (intentional delta):
- React Native should use platform reachability (e.g. NetInfo’s `isInternetReachable`) and may optionally do a lightweight health ping.
- Any health ping must be rate-limited and must not block UI rendering.

### Sync state
The global sync banner reflects **pending Firestore writes + request-doc operation state**, not “realtime subscription status”:
- whether there are **pending local writes** that have not been acknowledged by the server yet (best-effort)
- pending request-doc operations (queued / applying / failed)
- last request-doc error message (if any)
- background/automatic “sync attempt” errors (best-effort; not required for correctness)

Parity evidence (web):
- `src/components/SyncStatus.tsx` (derives status from queue + scheduler + worker events)
- `src/services/syncScheduler.ts`
- `src/services/operationQueue.ts`

Firebase/RN adaptation notes (intentional delta):
- There is no Service Worker in React Native. “background sync” becomes **best-effort background execution** (or “automatic sync attempt”) and must never be required for correctness.
- Mobile does **not** implement the web outbox/delta sync engine. Instead, reflect:
  - Firestore queued writes + pending writes acknowledgement
  - request-doc status (queued/applied/failed)
  - scoped listener attach/health (if exposed)

## Primary user-visible behaviors

### 1) Offline banner (NetworkStatus)
Show a fixed top banner when the device is offline:
- Copy: “Offline - Changes will sync when reconnected”
- Behavior: banner appears immediately on offline detection and disappears when back online.

Parity evidence:
- `src/components/NetworkStatus.tsx`

### 2) Slow connection banner (NetworkStatus)
Show a top banner when the device is online but slow:
- Copy: “Slow connection detected”
- This should not block interaction; it is informational.

Parity evidence:
- `src/components/NetworkStatus.tsx`
- slow-connection derivation: `src/services/networkStatusService.ts` (`navigator.connection.effectiveType`)

### 3) Sync status banner (SyncStatus) — when it shows
Show the floating sync status banner if any of these are true:
- there are pending Firestore writes or pending request-doc operations
- foreground sync is currently running
- an automatic/background sync attempt is active
- there is a sync error to surface

Parity evidence:
- `src/components/SyncStatus.tsx` (`shouldShowBanner`)

### 4) Sync status banner — status precedence and copy
Derive one of four status variants (highest precedence wins):

1. **error**
   - show “Sync error: <message>”
   - show `RetrySyncButton`
2. **syncing**
   - show “Syncing changes…”
3. **waiting**
   - when there are pending ops and a retry is scheduled for the future
   - copy is still user-friendly and does not show a countdown
4. **queue**
   - when there are pending ops (but not syncing, not error)
   - if offline: “Changes will sync when you're back online”
   - if online: “N changes pending”

Parity evidence:
- `src/components/SyncStatus.tsx` (`statusVariant`, `statusMessage`)

### 5) Retry sync behavior (RetrySyncButton)
When the user taps “Retry sync”:
- If online and offline prerequisites are cold (`blocked` or `warming`), attempt to hydrate prerequisites first (best-effort; do not fail the whole retry if hydration fails).
- Then request a best-effort **foreground retry**:
  - reattach scoped listeners / refresh listener scopes
  - refresh request-doc statuses

Parity evidence:
- `src/components/ui/RetrySyncButton.tsx` (`hydrateNow`, `triggerManualSync`, `requestForegroundSync('manual')`)
- prerequisite model: `src/hooks/useOfflinePrerequisites.ts`

Firebase/RN adaptation notes (intentional delta):
- Replace Service Worker “manual sync trigger” with an app-internal “retry now” signal. The key requirement is deterministic user recovery UX, not an outbox flush.

### 6) Background/automatic sync error toasts (BackgroundSyncErrorNotifier)
Background-triggered sync failures must surface as toast notifications:
- Deduplicate repeated identical errors for ~5s.
- If the error is an “offline”/“network offline” style failure, show it as a warning (expected).
- Otherwise show it as an error (unexpected).

Parity evidence:
- `src/components/BackgroundSyncErrorNotifier.tsx`

## Telemetry / diagnostics (non-blocking)
The web app computes “project channel stale/disconnected” telemetry and currently only logs it (not shown in UI).

Parity evidence:
- `src/components/NetworkStatus.tsx` (computes `channelWarnings`, does not render them)
- `src/components/SyncStatus.tsx` (computes `projectsNeedingAttention`, does not render them)
- `src/contexts/ProjectRealtimeContext.tsx` (telemetry fields)

Firebase/RN note:
- Replace “realtime channel” telemetry with scoped listener health + request-doc failure counters/timestamps (if available).

