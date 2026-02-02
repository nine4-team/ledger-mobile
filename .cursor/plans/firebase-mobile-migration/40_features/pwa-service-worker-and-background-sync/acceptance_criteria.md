# Acceptance criteria — Mobile background execution + sync scheduling (parity-informed)

Each criterion must have **parity evidence** (Observed in …) or an **intentional delta**.

Note: any “Observed in `public/...` / `src/...`” pointers in this doc refer to the legacy Ledger **web** codebase (not files in this React Native repo). Treat them as behavioral reference only.

## A) Intentional deltas (must be explicit)
- [ ] **No Service Worker / PWA on mobile**: The RN app does not implement a service worker or PWA installation flow.  
  **Intentional delta** (platform constraint).
- [ ] **Background sync is not correctness-critical**: If the OS never grants background time, user data remains correct locally and sync completes on next foreground/resume.  
  **Intentional delta** (mobile OS scheduling constraints; correctness owned by Firestore-native offline persistence + request-doc workflows).

## B) Guaranteed correctness behaviors (foreground path)
- [ ] **Local-first durability**: user edits are persisted locally immediately and survive app restart.  
  **Intentional delta**: on mobile we standardize on **Firestore-native offline persistence** (see `OFFLINE_FIRST_V2_SPEC.md`) rather than a custom outbox engine.
- [ ] **Foreground recovery**: on app open/resume while online, the app reattaches scoped listeners and allows Firestore to reconcile pending writes and remote changes; if progress is blocked (auth/permissions/request-doc failure), the UI surfaces an actionable “needs attention” state.  
  **Intentional delta**: codifies the mobile guarantee; aligns with `OFFLINE_FIRST_V2_SPEC.md`.

## C) Opportunistic background behavior (bounded + safe to skip)
- [ ] **Bounded background work unit**: one background wake attempts at most one bounded “sync work unit”:
  - if no pending ops: no-op
  - if pending ops: best-effort assist Firestore in pushing pending writes (bounded)  
  **Intentional delta** (mobile policy; cost guardrail).
- [ ] **No thrash**: repeated background failures apply backoff and do not create tight retry loops.  
  **Parity evidence**: web SW has cooldown/backoff/loop-stopper logic (Observed in `public/sw-custom.js`).  
  **Intentional delta**: the exact mobile mechanism differs but must preserve “no thrash”.

## D) Cost control (must not be expensive)
- [ ] **No background listeners**: when app is backgrounded, there are no Firestore listeners.  
  **Intentional delta** (cost + platform policy; consistent with `OFFLINE_FIRST_V2_SPEC.md` scoped-listener lifecycle).
- [ ] **No polling loop**: the app does not implement a “wake every N seconds/minutes and check” loop to emulate realtime.  
  **Intentional delta** (cost guardrail).
- [ ] **Realtime only via scoped listeners (foreground)**: while foregrounded, collaboration propagation is implemented via scoped/bounded listeners; no listeners on large/unbounded collections.  
  **Parity evidence** (migration requirement): `OFFLINE_FIRST_V2_SPEC.md`.

## E) User-visible UX expectations (make it better than “Retry” everywhere)
- [ ] **Automatic-first**: when online and there are pending changes, the app attempts to sync automatically (no manual action required in the common case).  
  **Parity evidence**: scheduler-driven behavior exists in web (Observed in `src/components/SyncStatus.tsx` + scheduler integration).
- [ ] **Actionable manual control is optional**: if a manual control exists, it is shown only when actionable (typically online + error/stalled), and it triggers a foreground sync work unit.  
  **Intentional delta**: we do not require a persistent “Retry Sync” UI.
- [ ] **Offline messaging**: when offline, the UI does not suggest actions that cannot succeed (no “retry” that just fails); it explains “waiting for connection.”  
  **Parity evidence**: web status message logic distinguishes offline (Observed in `src/components/SyncStatus.tsx`).

## F) Diagnostics/telemetry (for cost regressions)
- [ ] **Background sync metrics** exist (even if only in logs initially): background wakes, attempts, successes, failures by reason, and estimated Firestore reads/writes attributable to sync.  
  **Intentional delta**: required to detect accidental cost creep early.

