# InviteAccept — Screen contract

## Intent
Allow an invited user to join an account via a **tokenized deep link**.

In `ledger_mobile`, invite acceptance is **server-owned** (callable `acceptInvite`) and the app must persist a `pendingInviteToken` across restarts and auth flows so the invite can be accepted after the user signs in/up.

## Inputs
- Route params:
  - `token` (required)
- Query params: none
- Entry points:
  - External link / deep link to `/(auth)/invite/<token>` (Expo Router: `app/(auth)/invite/[token].tsx`, to add)

## Reads (local-first)
- Route param `token`
- Device storage for invitation bridging:
  - reads/writes `pendingInviteToken` (AsyncStorage is sufficient; SecureStore optional)
- Auth state:
  - `user`, `isInitialized` (via `useAuthStore()`)

## Writes (local-first)
User actions:
- Persist the token:
  - if `token` is present, store it as `pendingInviteToken` immediately so it survives restarts/auth flows
- Accept the invite (server-owned):
  - if authenticated, call callable `acceptInvite(token)` (idempotent)
  - the client **does not** write account user docs directly (no `accounts/{accountId}/users/{uid}` writes)
- Navigation:
  - on successful acceptance, navigate to `/(tabs)` (and set account context from `{ accountId, role }` returned by the server)

## UI structure (high level)
- Error state (“Invalid invitation link”)
- Auth required state (when unauthenticated):
  - CTA to sign in (`/(auth)/sign-in`)
  - CTA to sign up (`/(auth)/sign-up`)
- Accepting state (“Accepting invitation…”)
- Offline state (when token exists but device is offline):
  - clear offline message + retry CTA

## User actions → behavior (the contract)
- On mount:
  - if `token` missing → show “Invalid invitation link”
  - otherwise persist `pendingInviteToken`
  - if authenticated:
    - attempt acceptance via `acceptInvite(token)`
    - if offline: block acceptance and show retry UX
  - if unauthenticated:
    - show sign-in / sign-up CTAs
    - after auth completes, detect `pendingInviteToken` and attempt acceptance automatically

## States
- Accepting:
  - full screen spinner + copy “Accepting invitation…”
- Error (invalid token):
  - show “Invalid invitation link” card with message
- Offline:
  - show “Requires connection to accept invitation” + retry

## Media (if applicable)
- None.

## Collaboration / realtime expectations
- Not applicable.

## Performance notes
- Acceptance should be bounded (avoid infinite spinners) and idempotent server-side.

## Parity evidence
- Token screen UX + pending token persistence + timeouts (web parity reference): `src/pages/InviteAccept.tsx`
- Mobile spec source of truth: `40_features/auth-and-invitations/feature_spec.md` (deep link route + server-owned `acceptInvite`)

