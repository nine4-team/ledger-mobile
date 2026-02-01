# Connectivity + sync status — Acceptance criteria (parity + Firebase deltas)

Each non-obvious criterion includes **parity evidence** (web code pointer) or is labeled **intentional delta** (Firebase mobile requirement).

## NetworkStatus (connectivity banner)
- [ ] **Offline banner shows when offline**: When `isOnline=false`, render a **compact, single-line** fixed top banner/strip with copy “Offline - Changes will sync when reconnected”.  
  Observed in `src/components/NetworkStatus.tsx`.
- [ ] **No banner when online and not slow**: When `isOnline=true` and `isSlowConnection=false`, `NetworkStatus` renders nothing.  
  Observed in `src/components/NetworkStatus.tsx` (`shouldShow`).
- [ ] **Slow connection banner**: When `isOnline=true` and `isSlowConnection=true`, render a **compact, single-line** fixed top banner/strip with “Slow connection detected”.  
  Observed in `src/components/NetworkStatus.tsx`.
- [ ] **Banner is non-intrusive**: The connectivity UI must remain visually small (no large/persistent panels) and must not block interaction.
- [ ] **Connectivity snapshot is local and subscribable**: Network state is exposed via a subscription and can be read synchronously on startup (no “await network before render”).  
  Observed in `src/services/networkStatusService.ts` (`getNetworkStatusSnapshot`, `subscribeToNetworkStatus`) and `src/hooks/useNetworkState.ts`.
- [ ] **Actual-online check (web parity)**: “Online” status is validated via a lightweight remote health ping (not only `navigator.onLine`).  
  Observed in `src/services/networkStatusService.ts` (`REMOTE_HEALTH_URL` + `fetch`).
- [ ] **RN connectivity detection**: React Native uses OS reachability (and may optionally add a health ping), but must not block UI rendering on it.  
  **Intentional delta** (React Native platform constraint).

## SyncStatus (global sync banner)
- [ ] **Visibility rules**: `SyncStatus` renders (as a compact floating pill by default) if any are true: `pending>0`, scheduler is running, background/automatic sync is active, or there is a sync error.  
  Observed in `src/components/SyncStatus.tsx` (`shouldShowBanner`).
- [ ] **Status precedence**: `error` > `syncing` > `waiting` > `queue`.  
  Observed in `src/components/SyncStatus.tsx` (`statusVariant` logic).
- [ ] **Error copy includes message**: When in error, show “Sync error: <message>”.  
  Observed in `src/components/SyncStatus.tsx` (`combinedError` + `statusMessage`).
- [ ] **Retry button appears only in error**: `RetrySyncButton` is shown when `statusVariant==='error'`.  
  Observed in `src/components/SyncStatus.tsx`.
- [ ] **Syncing copy**: While syncing, show “Syncing changes…”.  
  Observed in `src/components/SyncStatus.tsx`.
- [ ] **Queue copy (online)**: When pending and online, show “N changes pending”.  
  Observed in `src/components/SyncStatus.tsx`.
- [ ] **Queue/waiting copy (offline)**: When pending and offline, show “Changes will sync when you're back online”.  
  Observed in `src/components/SyncStatus.tsx`.
- [ ] **Non-error UI stays compact**: In `queue`/`waiting`/`syncing`, the default presentation should be a compact pill (tap may expand for details). Large/persistent banners are discouraged.

## RetrySyncButton (manual recovery)
- [ ] **Retry warms prerequisites (best effort)**: If online and caches are `blocked` or `warming`, pressing Retry triggers prerequisites hydration first, but does not fail the whole retry if hydration fails.  
  Observed in `src/components/ui/RetrySyncButton.tsx` (`hydrateNow` try/catch) and `src/hooks/useOfflinePrerequisites.ts`.
- [ ] **Retry triggers a foreground sync request**: Pressing Retry attempts to request a foreground sync run.  
  Observed in `src/components/ui/RetrySyncButton.tsx` (`requestForegroundSync('manual')`).
- [ ] **Pending count shown**: When `showPendingCount=true` and pending > 0, show “(N pending)” next to the button label.  
  Observed in `src/components/ui/RetrySyncButton.tsx`.
- [ ] **Offline enqueue timestamp hint**: If there are pending ops and `lastOfflineEnqueueAt` is set, show a hint line “Offline save queued at <time>”.  
  Observed in `src/components/ui/RetrySyncButton.tsx`.
- [ ] **Background sync availability warning**: If background sync is unavailable, show a warning hint explaining why (environment-specific).  
  Observed in `src/components/ui/RetrySyncButton.tsx` (`formatBackgroundSyncWarning`).
- [ ] **React Native has no Service Worker**: Do not require a “reload to activate the service worker” recovery path; replace with mobile-appropriate copy (e.g., “keep the app open to sync”).  
  **Intentional delta** (React Native platform constraint).

## BackgroundSyncErrorNotifier (toasts)
- [ ] **Only background/automatic errors toast**: Do not toast foreground/manual sync errors here (those are already surfaced via banners/UI).  
  Observed in `src/components/BackgroundSyncErrorNotifier.tsx` (guards on `payload.source`).
- [ ] **Deduplicate repeated identical errors**: Do not show the same toast more than once per ~5 seconds.  
  Observed in `src/components/BackgroundSyncErrorNotifier.tsx` (`ERROR_DEBOUNCE_MS`).
- [ ] **Offline errors are warnings**: If the error message contains “offline” or “Network offline”, show as warning; otherwise show as error.  
  Observed in `src/components/BackgroundSyncErrorNotifier.tsx`.

## Architecture alignment (Firebase target)
- [ ] **Sync status reflects Firestore + request-doc state**: The UI reflects queued Firestore writes + request-doc pending/applied/failed (and any scoped listener health if available), not a bespoke outbox/delta-sync engine or broad “listen to everything” realtime subscriptions.  
  **Intentional delta** required by `OFFLINE_FIRST_V2_SPEC.md`.

