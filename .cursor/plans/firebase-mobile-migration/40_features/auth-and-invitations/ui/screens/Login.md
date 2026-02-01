# Login — Screen contract

## Intent
Allow users to authenticate via **email/password** (implemented) and optionally **Google** (UI exists; implementation is a known parity gap).

In `ledger_mobile`, this contract maps to the Expo Router screen `/(auth)/sign-in` (`app/(auth)/sign-in.tsx`) and is shown when the app routes unauthenticated users into the auth group.

## Inputs
- Route params: none
- Query params: none
- Entry points:
  - Root auth gating redirects unauthenticated users to `/(auth)/sign-in` (`app/_layout.tsx`, `app/index.tsx`).

## Reads (local-first)
- Auth state:
  - `user`, `isInitialized` (via `useAuthStore()`)
- Offline state (required for UX hardening per spec):
  - whether the device is offline so sign-in can show “requires connection” messaging when unauthenticated.

## Writes (local-first)
- Initiate email/password sign-in:
  - Calls `useAuthStore.signIn(email, password)` (Firebase Auth `signInWithEmailAndPassword`).
- Initiate Google sign-in:
  - **Not implemented** in `ledger_mobile` today; the current UI shows “Not set up yet”.

## UI structure (high level)
- Ledger logo + tagline
- Method tabs:
  - Google
  - Email & Password
- Error banner area
- Primary CTA for the chosen method

## User actions → behavior (the contract)
- Switch method tabs:
  - Switches between Google and email/password form
  - Clears any existing error message
- Google “Continue” (current skeleton behavior):
  - Shows “Not set up yet”
- Email/password “Sign In”:
  - Validates required email/password
  - Shows inline error message on validation or auth failure
  - On success, auth state changes and root routing moves the user into `/(tabs)`
- Offline gating (required behavior per spec; not yet implemented in UI):
  - If unauthenticated and offline, show “requires connection” messaging and provide a retry action.

## States
- Loading:
  - While global auth is initializing, `app/_layout.tsx` shows a loading overlay (Login may not render).
- Error:
  - Shows a red banner with message

## Collaboration / realtime expectations
- Not applicable.

## Performance notes
- Not applicable.

## Parity evidence
- `ledger_mobile` auth gating + redirects: `app/_layout.tsx`, `app/index.tsx`
- `ledger_mobile` sign-in screen (tabs + email/password + Google placeholder): `app/(auth)/sign-in.tsx`
- `ledger_mobile` Firebase Auth store: `src/auth/authStore.ts`
- Web parity reference (method UI + validation): `src/components/auth/Login.tsx`

