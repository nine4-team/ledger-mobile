# Connectivity + sync status (Firebase mobile migration feature spec)

This folder defines the parity-grade behavior spec for Ledger’s **global connectivity + sync UX**, grounded in the existing web app and adapted to the React Native + Firebase **offline-first** architecture.

## Scope
- Global connectivity banner:
  - offline (“Changes will sync when reconnected”)
  - slow connection indicator
- Global sync status banner:
  - pending Firestore writes / pending request-doc operations
  - syncing / waiting / error states (user-friendly; no “sync engine” jargon)
  - retry affordance when in error (best-effort “try again now”)
- Retry behavior:
  - “Retry sync” warms offline prerequisites when online
  - triggers a foreground “retry now” attempt (reattach scoped listeners + refresh request-doc statuses)
- Background/automatic sync error surfacing:
  - toast notifications for background-triggered sync failures

## Non-scope (for this feature folder)
- Per-entity “pending” UI markers in lists/details/forms (owned by each feature).
- Conflict resolution UX (owned by domain workflows / request-doc specs where relevant).
- React Native-specific library choices (e.g. which NetInfo/background-task package) beyond required capabilities.

## Key docs
- **Feature spec**: `feature_spec.md`
- **Acceptance criteria**: `acceptance_criteria.md`
- **Component contracts**:
  - `ui/components/NetworkStatus.md`
  - `ui/components/SyncStatus.md`
  - `ui/components/RetrySyncButton.md`
  - `ui/components/BackgroundSyncErrorNotifier.md`

## Cross-cutting dependencies
- Offline Data v2 architecture (canonical): `OFFLINE_FIRST_V2_SPEC.md`
- Request-doc workflows: multi-doc correctness is expressed as request-doc status (pending/applied/failed), not a client outbox.
- Offline prerequisites hydration (metadata caches): used by “Retry sync” and some forms; see parity evidence in `src/hooks/useOfflinePrerequisites.ts`.

## Parity evidence (web sources)
- Connectivity banner UI: `src/components/NetworkStatus.tsx`
- Sync status banner UI: `src/components/SyncStatus.tsx`
- Retry sync button (hydrates prerequisites + triggers sync): `src/components/ui/RetrySyncButton.tsx`
- Background sync error toasts: `src/components/BackgroundSyncErrorNotifier.tsx`
- Network detection + “actual online” ping: `src/services/networkStatusService.ts`, `src/hooks/useNetworkState.ts`
- Foreground sync scheduler state + backoff (web parity only): `src/services/syncScheduler.ts`
- Outbox queue state (web parity only): `src/services/operationQueue.ts`
- Realtime telemetry (staleness/disconnect signals used for logging today): `src/contexts/ProjectRealtimeContext.tsx`

