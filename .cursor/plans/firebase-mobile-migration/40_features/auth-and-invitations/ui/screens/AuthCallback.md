# AuthCallback — Screen contract

## Intent
**Web-only parity reference.**

The mobile app must **not** implement a `/auth/callback` route. Mobile auth is driven by native Firebase Auth persistence and auth state listeners; invitation acceptance is handled via the tokenized deep link route `/(auth)/invite/<token>` + a server-owned callable (`acceptInvite`).

This document is retained only to describe the legacy web behavior the spec is grounded in.

## Inputs
- Route params: none
- Query params: none (auth SDK may use hash/query internally)
- Entry points:
  - N/A on mobile (no `/auth/callback` route)

## Reads (local-first)
- N/A on mobile (legacy web flow):
  - web polls for session availability and reads a pending invitation token from web storage.

## Writes (local-first)
- N/A on mobile (legacy web flow):
  - web may bridge a pending invitation token into pending invitation data and then navigates home.

## UI structure (high level)
- Legacy web behavior: full-screen spinner + “Completing sign in…”

## User actions → behavior (the contract)
- No user actions; this screen is purely transitional.

## States
- Loading:
  - always (until it navigates away)
- Error:
  - errors are logged; user is navigated to `/`

## Collaboration / realtime expectations
- Not applicable.

## Performance notes
- Must be bounded (avoid infinite waits).

## Parity evidence
- Bounded polling loop + invitation token bridging + navigation: `src/pages/AuthCallback.tsx`
- Invitation lookup by token (pending or accepted): `checkInvitationByToken()` in `src/services/supabase.ts`
- User doc creation consumes `pendingInvitationData`: `createOrUpdateUserDocument()` in `src/services/supabase.ts`

