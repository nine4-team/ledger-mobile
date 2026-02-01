# `NetworkStatus` (global connectivity banner) — contract

## Purpose
Make connectivity state legible without blocking the UI.

## Inputs (state)
- `isOnline: boolean`
- `isSlowConnection: boolean`

Parity evidence:
- `src/components/NetworkStatus.tsx`
- `src/hooks/useNetworkState.ts`
- `src/services/networkStatusService.ts`

Note: parity pointers refer to the Ledger **web** codebase (not this React Native repo). Use them as behavioral reference only.

## Render rules
- If `!isOnline`: render a **compact, single-line** fixed top banner/strip:
  - copy: **“Offline - Changes will sync when reconnected”**
- Else if `isSlowConnection`: render a **compact, single-line** fixed top banner/strip:
  - copy: **“Slow connection detected”**
- Else: render nothing.

## UX constraints
- Prefer a thin strip (non-intrusive); avoid large/persistent banners.
- Must not block interaction with the rest of the UI.

## Non-goals
- Do not display per-project “stale channel” telemetry in the UI (web computes it but does not render it).

