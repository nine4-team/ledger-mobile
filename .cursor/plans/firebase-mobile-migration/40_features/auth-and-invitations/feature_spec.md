# Auth + invitations — Feature spec (Firebase mobile migration)

## Intent
Deliver a mobile-native auth + invitation bootstrap that is consistent with:

- Expo Router navigation (`app/_layout.tsx`, `app/index.tsx`, `app/(auth)/*`)
- Firebase Auth persistence (native SDK via `@react-native-firebase/auth`)
- Firestore-native offline baseline (cache-first reads + queued writes)
- Security model: membership-gated access; server-owned invitation acceptance

This feature must provide:

- fast “already signed in” startup (offline-capable when a prior session exists)
- clear “requires connection” gating when unauthenticated and offline
- invitation acceptance via tokenized deep links (no web-only callback routes)

## Reality check (what is already implemented in `ledger_mobile` today)

Already implemented:

- **Email/password auth store**: `ledger_mobile/src/auth/authStore.ts` implements:
  - `signIn(email, password)` → Firebase `signInWithEmailAndPassword`
  - `signUp(email, password)` → Firebase `createUserWithEmailAndPassword`
  - `initialize()` → `auth.onAuthStateChanged` and sets `isInitialized`
- **Root auth gating + redirects**:
  - `ledger_mobile/app/_layout.tsx` initializes auth and redirects unauthenticated users into `/(auth)`
  - `ledger_mobile/app/index.tsx` redirects to `/(tabs)` vs `/(auth)/sign-in`
- **Auth screens**:
  - `ledger_mobile/app/(auth)/sign-in.tsx` supports email/password sign-in and includes a Google tab/button UI that currently shows “Not set up yet”.
  - `ledger_mobile/app/(auth)/sign-up.tsx` supports email/password sign-up.

Not yet implemented (must be captured as work, not “assumed done”):

- Invite deep link route `/(auth)/invite/<token>`
- Pending invite token persistence (AsyncStorage/SecureStore)
- Callable invite acceptance (`acceptInvite`) and membership/account context bootstrap
- Explicit offline gating UX on auth screens (unauthenticated + offline)
- Auth safety timeout (web parity uses 7s timeout to avoid infinite spinner; mobile currently does not)
- Mobile-native Google OAuth → Firebase credential sign-in (web has Google OAuth; mobile currently has placeholder UI)

## Architecture alignment (non-negotiable)

- **No web-router assumptions**: do not specify `/auth/callback` routes or “poll session” behavior. Mobile auth is “Firebase user exists” (native persistence), not “redirect callback route”.
- **No client-written memberships**: the client never creates `accounts/{accountId}/members/{uid}` directly.
- **Invite acceptance is server-owned**: performed via a callable Cloud Function (idempotent).
- **Offline-first UX**: if local data exists, show it; auth/sign-in is the primary network-dependent exception.

## Owned screens / navigation (Expo Router)

Auth group screens (existing in the skeleton):

- `app/(auth)/sign-in.tsx`: sign in (email/password implemented; Google UI exists but is currently a placeholder)
- `app/(auth)/sign-up.tsx`: sign up (email/password)

Auth group screens (to add for this feature):

- `app/(auth)/invite/[token].tsx`: invite landing + acceptance flow (deep link entrypoint)
  - Note: dynamic route is required so `myapp://invite/<token>` can open the correct screen.

Root auth gating (existing in the skeleton):

- `app/_layout.tsx`: global auth gate. If unauthenticated, routes into `(auth)`; if authenticated, routes into `(tabs)`.
- `app/index.tsx`: initial redirect based on auth.

## Data dependencies (Firebase)

### Auth
- Firebase Auth user identity: `uid`, `email`, `emailVerified` (if/when used).

### Firestore security-critical documents
- Membership doc: `accounts/{accountId}/members/{uid}`
- Invite doc: `accounts/{accountId}/invites/{inviteId}`

### Cloud Function (callable)
Required callable:

- `acceptInvite`
  - Accepts an invite token and creates/updates membership server-side (see “Callable contract” below).

## Primary flows (mobile)

### 1) App boot → resolve auth → enter app or show auth
Behavior:

- On boot, `useAuthStore.initialize()` subscribes to `auth.onAuthStateChanged` and resolves `isInitialized`.
- Root navigation redirects:
  - authenticated → `/(tabs)`
  - unauthenticated → `/(auth)/sign-in`
- If unauthenticated and offline, show “requires connection” messaging on auth screens (sign-in cannot complete offline).

Grounding in skeleton:

- Boot + redirect gating: `app/_layout.tsx`, `app/index.tsx`
- Auth store: `src/auth/authStore.ts`

Required hardening (add to implementation when wiring real auth UX):

- Add a **bounded auth init timeout** (e.g. 7s) so we never show an indefinite loading overlay if native auth hangs.
  - On timeout, show the auth UI plus a “Retry” action (re-run `initialize()` or restart auth subscription).
  - Parity evidence (web): `/Users/benjaminmackenzie/Dev/ledger/src/contexts/AuthContext.tsx` uses a 7s safety timeout and sets `timedOutWithoutAuth`.

### 2) Sign in (email + password)
Behavior:

- User enters email/password on `/(auth)/sign-in`.
- Calls `useAuthStore.signIn(email, password)`.
- Success is expressed as an Auth state change (user becomes non-null), and root routing moves the user into `/(tabs)`.

Grounding in skeleton:

- `app/(auth)/sign-in.tsx` → `useAuthStore.signIn`

### 3) Sign up (email + password)
Behavior:

- User enters email/password on `/(auth)/sign-up`.
- Calls `useAuthStore.signUp(email, password)`.
- Root routing moves to `/(tabs)`.

Notes:

- Email verification UX is **TBD**. If we require verified email for some operations, add a dedicated “Verify email” screen and gate account entry accordingly.

Grounding in skeleton:

- `app/(auth)/sign-up.tsx` → `useAuthStore.signUp`

### 4) Sign in with Google (planned, mobile-native; no web callback)
Planned behavior (phase 2):

- User taps “Continue with Google”.
- App performs a mobile-native Google sign-in and exchanges the result for a Firebase credential.
- Auth state change drives navigation; no `/auth/callback` route exists in the mobile app.

Implementation note:

- The current mobile app UI shows Google as “not set up yet” and supports email/password only (`ledger_mobile/app/(auth)/sign-in.tsx`).
- Web parity evidence that Google OAuth exists today: `/Users/benjaminmackenzie/Dev/ledger/src/components/auth/Login.tsx` + `/Users/benjaminmackenzie/Dev/ledger/src/services/supabase.ts` (`signInWithGoogle()`).

### 5) Invite deep link → sign in/up → accept invite (server-owned)
Deep link behavior:

- Opening an invite link routes to `/(auth)/invite/<token>`.
- The invite token is persisted locally so it survives app restarts and auth flows.
  - Store `pendingInviteToken` in device KV storage (AsyncStorage is sufficient; SecureStore optional).

Invite screen behavior:

- If token is missing/empty: show “Invalid invitation link”.
- If user is already authenticated:
  - immediately attempt to accept the invite via callable `acceptInvite(token)`
  - on success: navigate to `/(tabs)` (and select the account context implied by the invite)
- If user is not authenticated:
  - show sign-in / sign-up CTAs (navigate to `/(auth)/sign-in` or `/(auth)/sign-up`)
  - after auth completes, the app must detect `pendingInviteToken` and attempt acceptance automatically.

Network behavior:

- Invite acceptance requires network (callable Function). If offline:
  - show a clear offline message + retry.

## Account context bootstrap (membership-gated)

After auth resolves, the app must establish an `accountId` context that drives all Firestore paths.

Required behavior:

- Determine candidate `accountId`:
  - **MVP assumption**: the app has a single “current account” (e.g. stored on a user profile doc like `users/{uid}.defaultAccountId`, or cached locally from the last successful session).
  - Multi-account selection is **TBD** and should become an explicit “Choose account” screen if needed.
- Verify membership:
  - attach a **bounded** listener to `accounts/{accountId}/members/{uid}` (or perform a cache-aware read first)
  - if membership is missing or disabled: show a “No access” UI and sign out

Implementation status note:
- `ledger_mobile` does not yet include an account context store/provider. This section defines required behavior that must be implemented before any account-scoped Firestore paths are safe to use.

Constraints:

- Do not “guess” an account id while offline without a cached membership-backed source; prefer:
  - Firestore cached membership doc, or
  - locally cached `accountId` from a previously validated session.

## Callable contract (invite acceptance)

### `acceptInvite` (callable Function)
Inputs:

- `token: string`
- optional `deviceInfo` (for diagnostics) and optional `profileDefaults` (if required by product)

Server behavior (must be idempotent):

- validate token (exists, not expired, not already used)
- enforce entitlements (e.g. free tier user limits)
- in a Firestore transaction/batch:
  - create/update `accounts/{accountId}/members/{uid}` with the invited role
  - mark invite as accepted/used (record `acceptedAt`, `acceptedByUid`)
  - create any required user/profile defaults (server-owned)
- return `{ accountId, role }` (minimum) so the client can set account context

Failure modes (structured errors):

- invalid/expired invite
- invite already accepted
- entitlement limit reached
- permission denied (non-authenticated)

## Offline-first behavior

### Auth while offline

- **If a prior Firebase session exists** (cached credentials): allow boot into the app and render cached Firestore content (subject to membership gating from cache).
- **If no prior session exists**: show “requires connection” on sign-in/sign-up and provide a retry action.

### Invite acceptance while offline

- Allow the invite screen to render (token parsed + persisted), but block acceptance until online.

## Acceptance criteria (implementation-ready)

- App has **no** web-only callback routes (no `/auth/callback`).
- Auth bootstrap uses native Firebase Auth persistence and gates navigation via Expo Router.
- Invite links open `/(auth)/invite/<token>` and can be accepted after signing in/up.
- `acceptInvite` is callable, server-owned, and idempotent; clients do not write membership docs directly.
- Offline behavior is explicit:
  - existing sessions can enter and view cached data
  - new sign-in and invite acceptance clearly require network
- Account context is membership-gated and does not rely on unsafe “fallback account id” guessing.  

## Parity evidence pointers (web app)

The following web files define the behaviors this spec is grounded in (parity reference only; not 1:1 mobile implementation):

- Auth safety timeout + auth lifecycle: `/Users/benjaminmackenzie/Dev/ledger/src/contexts/AuthContext.tsx`
- Protected-route gating + spinner/login fallback: `/Users/benjaminmackenzie/Dev/ledger/src/components/auth/ProtectedRoute.tsx`
- Login methods (Google + email/password): `/Users/benjaminmackenzie/Dev/ledger/src/components/auth/Login.tsx`
- Invite accept (token check + timeout + local token persistence): `/Users/benjaminmackenzie/Dev/ledger/src/pages/InviteAccept.tsx`
- OAuth callback token bridging: `/Users/benjaminmackenzie/Dev/ledger/src/pages/AuthCallback.tsx`
- Invite helpers + Google OAuth implementation (Supabase): `/Users/benjaminmackenzie/Dev/ledger/src/services/supabase.ts`

