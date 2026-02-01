# Prompt pack — Auth boot + ProtectedRoute

## Goal
You are helping migrate Ledger to **React Native + Firebase** with an **offline‑first** architecture:
- Firestore-native offline persistence (Firestore is canonical; cache + queued writes)
- Scoped listeners only (no “listen to everything”)
- Request-doc workflows for multi-doc correctness (Cloud Function transaction applies changes)
- Optional SQLite is allowed only as a **derived search index** (non-authoritative)

Your job in this chat:
- Refine the parity spec for auth bootstrap + protected-route gating, grounded in the existing web codebase.

## Outputs (required)
Update or create the following docs:
- `40_features/auth-and-invitations/feature_spec.md`
- `40_features/auth-and-invitations/acceptance_criteria.md`
- `40_features/auth-and-invitations/ui/screens/Login.md`

## Source-of-truth code pointers
Mobile grounding (this repo):
- Spec source of truth: `40_features/auth-and-invitations/feature_spec.md`
- Root auth gating + redirects: `ledger_mobile/app/_layout.tsx`, `ledger_mobile/app/index.tsx`
- Auth store (Firebase Auth + persistence): `ledger_mobile/src/auth/authStore.ts`

Web parity references (evidence only):
- `src/components/auth/ProtectedRoute.tsx`
- `src/components/auth/Login.tsx`

Related services/hooks:
- `src/contexts/AuthContext.tsx`
- `src/main.tsx` (provider boot order)
- `src/App.tsx` (route placement + offline init ordering)
- `src/services/supabase.ts` (redirect target + auth config parity reference)

## What to capture (required sections)
- Owned screens
- Primary user flows
- Offline behavior:
  - what works with cached auth vs what requires network
  - restart behavior
- Error states:
  - auth timeout / “stuck loading” behavior
- Risk level + dependencies

## Evidence rule (anti-hallucination)
For each non-obvious behavior:
- Provide **parity evidence** (file + component/function), OR
- Mark as an **intentional change** and explain why.

## Constraints / non-goals
- Do not prescribe “subscribe to everything” listeners; realtime must use **scoped/bounded listeners** only.
- Do not do pixel-perfect design specs.
- Focus on behaviors where multiple implementations would diverge.

