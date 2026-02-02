# Prompt pack — Invite acceptance (deep link; no web callback route)

## Goal
You are helping migrate Ledger to **React Native + Firebase** with an **offline‑first** architecture:
- Firestore-native offline persistence (Firestore is canonical; cache + queued writes)
- Scoped listeners only (no “listen to everything”)
- Request-doc workflows for multi-doc correctness (Cloud Function transaction applies changes)
- Optional SQLite is allowed only as a **derived search index** (non-authoritative)

Your job in this chat:
- Refine the parity spec for invitation acceptance via tokenized deep links, and pending-token persistence across auth flows (**without** any `/auth/callback` route in the mobile app).

## Outputs (required)
Update or create the following docs:
- `40_features/auth-and-invitations/feature_spec.md`
- `40_features/auth-and-invitations/acceptance_criteria.md`
- `40_features/auth-and-invitations/ui/screens/InviteAccept.md`
Optional parity reference (do not implement as a mobile route):
- `40_features/auth-and-invitations/ui/screens/AuthCallback.md`

## Source-of-truth code pointers
Primary screens/components:
- Mobile spec source of truth: `40_features/auth-and-invitations/feature_spec.md`
- Web parity reference (invite UI + token persistence): `src/pages/InviteAccept.tsx`
- Web parity reference (callback bridging only; web-only): `src/pages/AuthCallback.tsx`

Related services/hooks:
- `src/services/supabase.ts` (invitation helpers + signup/signin methods)
- `src/contexts/AuthContext.tsx` (SIGNED_IN handler + user doc creation)

## What to capture (required sections)
- Token verification + expiry behavior
- Local persistence of invitation token across restarts/auth flows (AsyncStorage/SecureStore; not web `localStorage`)
- Offline behavior: token screen can render; acceptance requires network + retry UX
- Where invitation acceptance actually happens (server-side or user-doc creation)
- Firebase migration deltas (server-owned invitation acceptance + idempotency)

## Evidence rule (anti-hallucination)
For each non-obvious behavior:
- Provide **parity evidence** (file + component/function), OR
- Mark as an **intentional change** and explain why.

## Constraints / non-goals
- Do not specify or implement any `/auth/callback` route in the mobile app.
- Do not suggest client-written account user docs like `accounts/{accountId}/users/{uid}`; invite acceptance must be server-owned (callable Function, idempotent).
- Do not do pixel-perfect design specs.
- Focus on behaviors where multiple implementations would diverge (timeouts, retries, token persistence, idempotency).

