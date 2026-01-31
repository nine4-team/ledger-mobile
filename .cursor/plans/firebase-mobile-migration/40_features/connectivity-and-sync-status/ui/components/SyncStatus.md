# `SyncStatus` (global sync banner) — contract

## Purpose
Expose offline-first “pending changes” state globally so users understand when changes are pending, syncing, waiting, or errored.

## Inputs (state)
- Pending Firestore writes (best-effort): “there are local writes not yet acknowledged by the server”
- Pending request-doc operations (multi-doc correctness workflows): count + last error (if any)
- Optional: scoped listener health snapshot (attach errors / stale listeners) if the app exposes it
- Optional: background/automatic “sync attempt” state (best-effort; not required for correctness)
- Connectivity: `isOnline`

Parity evidence:
- `src/components/SyncStatus.tsx`
- `src/services/operationQueue.ts`
- `src/services/syncScheduler.ts`
- `src/hooks/useNetworkState.ts`

## Render rules

### When to show
Show the banner if any are true:
- pending Firestore writes or pending request-doc operations > 0
- `isRunning === true`
- background/automatic sync attempt is active
- there is a non-null sync error

### Variant precedence
Pick exactly one:
1. **error**: any sync error present
2. **syncing**: foreground syncing or background syncing active
3. **waiting**: pending > 0 and `nextRunAt` is in the future
4. **queue**: pending > 0

### Copy rules
- **error**: `Sync error: <message>` + show `RetrySyncButton`
- **syncing**: `Syncing changes…`
- **queue/waiting**:
  - if offline: `Changes will sync when you're back online`
  - else: `N changes pending`

## Firebase/RN adaptation note
This banner must reflect **Firestore queued writes + request-doc status (+ scoped listener health if available)**, not a custom outbox/delta sync engine or Supabase realtime channels.

