# Auth + invitations (Firebase mobile migration feature spec)

This folder defines the parity-grade behavior spec for Ledger’s **authentication** and **invitation acceptance** flows, grounded in the existing web app and adapted to the React Native + Firebase **offline-first** architecture.

## Scope
- Sign in (email + password) — **already implemented** in `ledger_mobile`
- Sign up (email + password) — **already implemented** in `ledger_mobile`
- Protected-route gating (show spinner while auth initializes; redirect into auth group when unauthenticated) — **already implemented** in `ledger_mobile`
- Invitation link acceptance (mobile deep link → `/(auth)/invite/<token>`) — **not yet implemented** in `ledger_mobile`
- Persist minimal “pending invite token” across auth + restarts — **not yet implemented** in `ledger_mobile`
- Invite acceptance is server-owned + idempotent (callable Function / transaction) — **not yet implemented** in `ledger_mobile`

Parity note:
- The **web app supports Google OAuth today**; `ledger_mobile` currently has a Google tab/button UI but the handler is a placeholder (“Not set up yet”). Whether Google OAuth is implemented in this feature is an explicit scope decision; until then it should be treated as a **known parity gap** (not “invented behavior”).

## Non-scope (for this feature folder)
- Settings UI for managing invites (create/revoke/resend) — belongs under `settings-and-admin`
- Roles v2 / scoped permissions — belongs under `roles-v2` (net-new planned)
- Project/business-inventory domain behavior — separate feature folders
- Pixel-perfect UI design

## Key docs
- **Feature spec**: `feature_spec.md`
- **Acceptance criteria**: `acceptance_criteria.md`
- **Screen contracts**:
  - `ui/screens/Login.md`
  - `ui/screens/InviteAccept.md`
  - `ui/screens/AuthCallback.md` (web-only parity reference; **not** a mobile route / owned screen)

## Cross-cutting dependencies
- Offline Data v2 architecture (canonical): `OFFLINE_FIRST_V2_SPEC.md`
  - Firestore-native offline persistence (Firestore is canonical).
  - Scoped listeners only (no “listen to everything”).
  - Request-doc workflows for multi-doc correctness (Cloud Function transaction).

## Parity evidence (web sources)
- Providers/boot order: `src/main.tsx`, `src/App.tsx`
- Auth state lifecycle + safety timeout + offline context persistence: `src/contexts/AuthContext.tsx`
- Protected-route gating: `src/components/auth/ProtectedRoute.tsx`
- Login screen (Google + email/password): `src/components/auth/Login.tsx`
- OAuth callback flow + invitation token bridging: `src/pages/AuthCallback.tsx`
- Invite acceptance screen + email verification branch: `src/pages/InviteAccept.tsx`
- Account context resolution + offline fallback: `src/contexts/AccountContext.tsx`
- Supabase auth configuration + invite helpers (parity reference only): `src/services/supabase.ts`

## Intentional deltas (mobile)
- **No `/auth/callback` route in the mobile app**. Mobile auth should be native-persistent; OAuth (if implemented) must be mobile-native and must not require a web callback route.
- Invite acceptance should be driven from a deep-link route in the auth group (e.g. `myapp://invite/<token>` → `/(auth)/invite/<token>`), and token bridging must use device storage (AsyncStorage/SecureStore), not web `localStorage`.
