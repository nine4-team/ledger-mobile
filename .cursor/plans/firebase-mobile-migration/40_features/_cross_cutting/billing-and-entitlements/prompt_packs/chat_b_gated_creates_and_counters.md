# Prompt Pack — Chat B: Gated creates + server-owned counters

## Goal
Specify the server-owned enforcement strategy for the free-tier limits (counters + gated creates).

## Outputs (required)
Update:

- `40_features/_cross_cutting/billing-and-entitlements/feature_spec.md`

Optional (only if needed):

- `40_features/_cross_cutting/billing-and-entitlements/acceptance_criteria.md`

## Inputs to review (source of truth)
- Security model callable guidance: `10_architecture/security_model.md`
- Architecture: `OFFLINE_FIRST_V2_SPEC.md` (request-doc workflows; scoped listeners; Firestore-native offline persistence)
- Projects create delta requirements:
  - `40_features/projects/feature_spec.md` (must reference this cross-cutting spec for gated creates)

## What to capture
- Server-owned counters shape:
  - `accounts/{accountId}/billing/usage` (`projectCount`, `itemCount`, `transactionCount`)
- Required gated create processing:
  - preferred: request-doc workflows processed by Functions (`createProject` request, etc.)
  - alternative (online-only): callable functions for creates that cannot be queued offline
- Idempotency expectations + request status semantics (`pending | applied | denied | failed`)

## Evidence rule (anti-hallucination)
Net-new feature: cite architecture docs and label intentional deltas.

