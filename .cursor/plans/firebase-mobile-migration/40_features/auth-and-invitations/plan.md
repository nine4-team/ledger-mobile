# Feature plan (`40_features/auth-and-invitations/plan.md`)

## Goal
Produce parity-grade specs for `auth-and-invitations`.

## Inputs to review (source of truth)
- Feature map entry: `40_features/feature_list.md` → “1) Authentication (Google + email/password) + invitation acceptance”
- Offline Data v2 architecture (canonical): `OFFLINE_FIRST_V2_SPEC.md` (Firestore-native offline persistence + scoped listeners + request-doc workflows)
- Existing web parity sources:
  - Providers/boot: `src/main.tsx`, `src/App.tsx`
  - Auth lifecycle: `src/contexts/AuthContext.tsx`
  - Login + protected route: `src/components/auth/{ProtectedRoute,Login}.tsx`
  - Auth callback: `src/pages/AuthCallback.tsx`
  - Invite accept: `src/pages/InviteAccept.tsx`
  - Account context + offline fallback: `src/contexts/AccountContext.tsx`
  - Offline context persistence: `src/services/offlineContext.ts`

## Owned screens (list)
- `Login` — contract required? **yes** — multiple auth methods + error/loading states
- `InviteAccept` — contract required? **yes** — token verification + OAuth bridging + email verification branch
- `AuthCallback` — contract required? **yes** — bounded polling + invitation handoff behavior

## Cross-cutting dependencies (link)
- `OFFLINE_FIRST_V2_SPEC.md` (boot order expectations; offline-ready architecture primitives)

## Output files (this work order will produce)
Minimum:
- `README.md`
- `feature_spec.md`
- `acceptance_criteria.md`

Screen contracts (required):
- `ui/screens/Login.md`
- `ui/screens/InviteAccept.md`
- `ui/screens/AuthCallback.md`

## Prompt packs (copy/paste)
Create `prompt_packs/` with 2–4 slices:
- Slice A: boot + ProtectedRoute + auth lifecycle (`AuthContext`)
- Slice B: invite acceptance + OAuth bridging across redirects
- Slice C: account context + offline fallback + role semantics

## Done when (quality gates)
- Acceptance criteria all have parity evidence or explicit deltas.
- Offline behaviors are explicit (signed-in offline boot vs sign-in-required offline).
- Cross-links are complete.

