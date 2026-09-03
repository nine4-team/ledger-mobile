# EVID-CLIENT-CORE-DETAILS-001 — Client Core-Details Read Contracts

- Timestamp: 2026-09-02
- Class: ready gate / provider-free single-Client core-record read
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-D7F3D08FA568`, `TEST-F304037D32B6`
- Slice dossier: `conversion/implementation-slices/client-core-details-read-contracts.json`
- Verification state: implementation integrated/reviewed and complete local
  integration gate passed; exact integration-commit CI remains pending
- Ready scaffold hashes:
  - `ClientCoreDetailsData.swift`: `efc9dd853b0905edaa24815e430c160042dda7e5acd77457e42c7af50d420c86`
  - `ClientCoreDetailsDataTests.swift`: `b62320f3c9a27c94c8a9a64927ac4d3f8cb8cb27c74967e46055449eb1647b5f`

## Independent Scope Preflight

The primary agent, a read-only scout and an independent adversarial reviewer
separately read D-006, the canonical Client identity/lifecycle specification,
the architecture and verified directory/rename/archive dependencies. All
approved one exact Client core record, not a Client workspace or CRM model.
The independent review then rejected an imprecise workspace-query citation,
stale Project wording and ambiguous row-tamper language before freeze; the
contract now cites the Client port family and distinguishes malformed/rebound
evidence from separately valid later Client snapshots.

The review requires exact Account/Client fingerprint binding, exact reuse of
`ClientSummary`, and a `locallyObservedRevision: ExpectedClientRevision` only
because verified rename/archive commands require that conflict precondition.
Revision remains distinct from LocalDataVersion and updatedAt and is never
server-current authority under incomplete, partial or stale evidence.

An archived Client remains found. Nonblank padded names must be preserved rather
than normalized because canonical authority requires a current name but does
not establish trimming. Finite ordered timestamps, including equality, are
preserved without claiming producer, actor or server provenance.

## Frozen Boundary and Tests

The dossier freezes zero-or-one exact-request evidence, exact visible count,
ready-complete-zero-only authoritative absence, explicit incomplete/partial/
stale/failure truth, structured restart, stable bounded diagnostics and one
narrow query port. Tests must cover both identities independently, active/
archived and revision 0/max, padded names, equal timestamps, all readiness
variants, identical/distinct multiple rows, negative/mismatched counts,
partial+complete and stale+complete refusal, malformed or missing audit/name/
lifecycle/revision evidence, same-name/wrong-ID and request/query/update/cache
rebinding, acceptance of separately valid later name/time/lifecycle/revision
snapshots, the literal valid and invalid waiting-state sets, non-enumerating
unavailable, raw-consumer-without-validation port refusal,
upstream failure, cancellation and encoded exclusions.

It excludes Projects/counts, Transfer eligibility, frozen history, contacts/
CRM, billing/financial data, media, mutation, archive effects, restore/delete,
merge/reassignment, authorization, physical persistence, provider/schema/RLS/
Sync/Auth, app/MCP, migration, hosted resources, release and production.
O-025 and A-003/A-004/A-007/A-015/A-016 remain untouched.

## Local Ready-Gate Evidence

- Conversion sync/check/report: `801` recorded, `786` discovered, zero errors;
  only the three established retired-surface warnings remain.
- Capability/query/residual controls: pass; `372` mapped and `167` residual
  surfaces, including `44` blockers.
- Milestones: M0 passes; M1 remains honestly blocked by `2` coverage decisions
  and M2 by `167`, both with zero structural errors.
- Target verification: environment and generated-contract checks pass; all
  `205` tests in `47` suites pass.
- Project generation is byte-repeatable: project hash
  `0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
  and staging-scheme hash
  `388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`
  are unchanged.
- macOS and generic iOS Simulator staging builds and diff formatting pass.
- The Firebase checkout remains clean on `firebase`; no provider or production
  action occurred.

## Immutable Ready Commit and Assignment

Exact ready commit `e925a7a07a0eccf5e1563c4b4a4abee58238e7db`
passed Actions run `33700564469`: conversion traceability in 7 seconds and the
isolated target job in 2 minutes 22 seconds, including all tests, both staging
builds and clean tracked artifacts.

`SUBAGENT-WORK-005` is pinned to that commit on
`codex/supabase-slice-client-core-details` in the isolated
`/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_client_core_details`
worktree. The worker owns only the two registered Swift paths. The candidate is
untrusted until primary every-line review, independent adversarial review,
complete local gates and exact integration-commit CI all pass.

## Candidate and Enhanced Review

Worker candidate `549ecfa6896533fa34b9d8f81efb8e57559e6312`
was an exact child of the ready commit and changed only the two registered paths.
Primary every-line review found no implementation defect. Independent
adversarial review nevertheless rejected one P3 false-positive test: a helper
treated unrelated errors as success for nominally valid waiting states.

Correction `cd433de292a917eaef3ee9db81ef89b52bc88c1e`
replaced that helper path with direct throwing construction and exact state
assertions for `notRequested`/`loading`/`blocked`, while retaining exact
`invalidWaitingState` assertions for `ready`/`partial`/`stale`. Primary and
independent re-review report no remaining P0-P3 issue. Worker, primary and
reviewer focused runs pass all six tests; worker and primary full runs pass all
211 tests in 48 suites.

The candidate was integrated as
`b96377d76df634210dfee4367deb34dbbfdf658d` and correction
`de85667ce55fbc30b5ee576b2ba7c087d588ea53`.

## Complete Local Integration Gate

- Conversion sync/check/report, capability, query, residual and M0 controls
  pass at `801` recorded/`786` discovered, zero errors, the three established
  retired warnings, `372` mapped/`167` residual/`44` blockers.
- Target environment and generated-contract checks pass; all 6 focused and 211
  target tests in 48 suites pass.
- Xcode project and staging-scheme hashes remain byte-identical at
  `0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
  and `388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`.
- macOS and generic iOS Simulator staging builds, diff formatting and tracked
  artifact checks pass.
- M1/M2 remain honestly blocked at `2`/`167` with zero structural errors. The
  Firebase checkout remains clean on `firebase`.

Immutable CI on the exact integration checkpoint remains the final prerequisite
for verification.

## Permanent Limits

Ready status proves only that authority, boundary and verification obligations
are traceable. It proves no executable behavior, physical offline durability,
authorization, synchronization, database policy, migration reconciliation,
app/MCP behavior, hosted resource, production behavior, release or cutover.
