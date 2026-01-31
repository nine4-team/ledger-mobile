# Chat C — Accounting rollups + report entrypoints

## Goal
Specify (and/or implement) the project “Accounting” sub-tab rollups and its report entrypoints, compatible with offline-first constraints.

## Critical constraints (must obey)
- Rollups must be derivable offline from Firestore-cached data (Firestore-native offline persistence; `OFFLINE_FIRST_V2_SPEC.md`).
- If listeners are used, they must be scoped/bounded to the active project scope (no unbounded “listen to everything” listeners).

## Exact output files
Update only:
- `40_features/budget-and-accounting/feature_spec.md`
- `40_features/budget-and-accounting/acceptance_criteria.md`

## What to produce
- Deterministic definitions for:
  - “Owed to Design Business”
  - “Owed to Client”
- Clarify inclusion/exclusion:
  - exclude canceled transactions
  - define whether pending vs completed matters (web includes both as long as not canceled)
- Define the report entrypoints contract (routes/screens), but do not re-spec report generation (owned elsewhere).

## Parity evidence (web sources)
- Accounting rollups + report entrypoints live in:
  - `src/pages/ProjectLayout.tsx` (`owedTo1584`, `owedToClient`, report buttons)
- Reimbursement constants:
  - `src/constants/company.ts`

## Evidence rule
For each non-obvious behavior, include either parity evidence or an intentional delta statement.

