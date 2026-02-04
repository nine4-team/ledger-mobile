# Auth + invitations — Acceptance criteria (parity + Firebase deltas)

Each non-obvious criterion includes **parity evidence** (web code pointer) or is labeled **intentional delta** (Firebase mobile requirement).

This file also marks **what is already implemented** in `ledger_mobile` vs **what remains to implement**, so we don’t “spec” work that’s already done.

## Routing + boot
- [x] **Mobile auth gating exists**: root layout initializes auth store and redirects based on auth state.  
  Implemented in `ledger_mobile/app/_layout.tsx` and `ledger_mobile/app/index.tsx`.
- [x] **Email/password auth store exists**: sign-in/sign-up/sign-out + auth state subscription.  
  Implemented in `ledger_mobile/src/auth/authStore.ts`.
- [x] **Auth safety timeout**: auth initialization has a bounded timeout (e.g. 7s) so we never show an indefinite loading overlay if native auth hangs.  
  Parity evidence (web): `/Users/benjaminmackenzie/Dev/ledger/src/contexts/AuthContext.tsx` (7s timeout + `timedOutWithoutAuth`).  
  Mobile status: **not implemented** (today `ledger_mobile/app/_layout.tsx` shows a loading overlay while `isInitialized` is false).
- [x] **Offline “requires connection” messaging on auth screens**: when unauthenticated and offline, sign-in/sign-up must not appear “broken”; show explicit offline gating + retry.  
  Intentional delta (mobile constraint): sign-in cannot complete offline unless a prior session exists; current `ledger_mobile` auth screens do not yet implement offline gating UX.

## Protected route gating
- [x] **Spinner while auth is resolving (mobile)**: an overlay is shown until auth store initializes.  
  Implemented in `ledger_mobile/app/_layout.tsx` via `LoadingScreen`.
- [x] **Redirect to sign-in when unauthenticated (mobile)**.  
  Implemented in `ledger_mobile/app/_layout.tsx` + `ledger_mobile/app/index.tsx`.

## Login (Google + email/password)
- [x] **Mobile login UI offers Google + Email tabs** (Google is currently a placeholder).  
  Implemented in `ledger_mobile/app/(auth)/sign-in.tsx` (tabs + Google button shows “Not set up yet”).
- [x] **Email/password validation exists (mobile)**.  
  Implemented in `ledger_mobile/app/(auth)/sign-in.tsx`.
- [x] **Email/password sign-in uses Firebase Auth password flow (mobile)**.  
  Implemented in `ledger_mobile/src/auth/authStore.ts` (`signInWithEmailAndPassword`).
- [x] **Google sign-in required**: web app supports Google OAuth; mobile must implement mobile-native Google→Firebase credential sign-in.  
  Parity evidence (web): `/Users/benjaminmackenzie/Dev/ledger/src/components/auth/Login.tsx` and `/Users/benjaminmackenzie/Dev/ledger/src/services/supabase.ts` (`signInWithGoogle()`).
  Intentional delta (mobile): **no `/auth/callback` route**; it must be mobile-native.

## Auth callback (web-only parity reference)
- [ ] **No web callback route in mobile** (`/auth/callback` must not exist in the RN app).  
  Intentional delta (mobile constraint): native Firebase Auth persistence replaces web OAuth redirect callbacks.
  Parity evidence (web-only): `/Users/benjaminmackenzie/Dev/ledger/src/pages/AuthCallback.tsx`.

## Invite acceptance
- [ ] **Invite deep link route exists (mobile)**: `/(auth)/invite/<token>` opens from `myapp://invite/<token>`.  
  Mobile status: **not implemented** (no invite route exists under `ledger_mobile/app/(auth)` today).
- [ ] **Token required + bounded verification**: missing/invalid token shows an error state; token lookup is bounded by a timeout.  
  Parity evidence (web): `/Users/benjaminmackenzie/Dev/ledger/src/pages/InviteAccept.tsx` + `/Users/benjaminmackenzie/Dev/ledger/src/services/supabase.ts` (`getInvitationByToken()`).
- [ ] **Persist pending invite token across auth + restarts (mobile)**.  
  Intentional delta (mobile): use AsyncStorage (SecureStore optional), not web `localStorage`.
- [ ] **Invite acceptance is server-owned + idempotent (Firebase)**.  
  Intentional delta (migration requirement): client must not write membership docs directly; acceptance happens via a callable Function / transaction.

## Account context + offline context persistence
- [ ] **Account context exists (mobile)**: after auth, determine a safe `accountId` and verify membership.  
  Mobile status: **not implemented** (no account context store/context found in `ledger_mobile/src/**` yet).
  Parity evidence (web): `/Users/benjaminmackenzie/Dev/ledger/src/contexts/AccountContext.tsx`.

## Firebase migration requirements (intentional deltas)
- [ ] **Auth provider**: replace Supabase Auth with Firebase Auth but preserve the behavioral contracts above.  
  **Intentional delta** (migration requirement).
- [ ] **Invitation acceptance is server-owned**: token validation + membership creation + invitation acceptance is implemented via server-owned Functions/transactions and is idempotent.  
  **Intentional delta** (migration requirement).
- [ ] **Offline policy**: if no cached session exists, sign-in/invite acceptance is blocked while offline with explicit messaging; if cached session exists, allow offline boot.  
  **Intentional delta** (mobile constraint; auth requires network).

