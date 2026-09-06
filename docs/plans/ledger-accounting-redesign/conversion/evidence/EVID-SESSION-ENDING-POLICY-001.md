# EVID-SESSION-ENDING-POLICY-001 — Session Ending and Pending-Work Contracts

- Timestamp: 2026-09-02
- Class: verification / provider-free session-ending safety policy
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-1599BDC0D574`, `TEST-95498CCCD467`
- Slice dossier:
  `conversion/implementation-slices/session-ending-pending-work-contracts.json`
- Verification state: verified at exact implementation commit
  `bf9a00ca45c8054018ab6f021aab13386ba24872` by immutable GitHub Actions run
  `33663785835`
- Ready scaffold hashes:
  - `SessionEndingPolicy.swift`:
    `e2f8dacf9569a97893673777b04aedef33c345b5f76526b327b1abce30af8d4e`
  - `SessionEndingPolicyTests.swift`:
    `b2ca691096664a6a7d4d245fcf09ea5a8472ddcfa25078840d060ec58f30a50b`

## Selection and Scope

The next-slice audit first considered Item-to-Space assignment. It rejected
that candidate because O-037 still controls archived-destination and retained-
assignment behavior; implementing it would silently approve a proposed product
decision. The audit selected the session-ending pending-work boundary because
the canonical offline requirements and reviewed architecture already fix its
loss-prevention semantics independently of Auth provider and UI wording.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. The future contract may summarize exact local work and authorize
only a typed clean, sync-first, or exact-confirmed destructive disposition. It
cannot sign out Firebase or Supabase Auth, synchronize or delete data, choose an
offline lease, implement UI, touch source app code, access hosted resources, or
claim production behavior.

## Product and Source Cross-Reference

The audit cross-referenced:

- `docs/specs/session-ending-pending-work.md` as the sole canonical target
  authority for the loss-preventing clean/sync-first/cancel/exact-destructive
  boundary;
- `docs/specs/authentication-offline-access.md` for the explicit boundary
  between that fixed safety contract and still-open Auth/lease/copy choices;
- `docs/specs/offline-first.md` for local acceptance, pending attachment
  durability, honest sync state, and conditional logout behavior;
- the reviewed identity/session capability dossier for the current direct
  Firebase signout defect, cross-Account isolation, stable error behavior, and
  target-neutral pending-work/session-ending contract;
- `03-data-sync-and-offline.md` for the exact queued/applying, unresolved-
  rejected, and unverified-attachment categories plus clean, sync-first,
  destructive and interrupted-cleanup behavior;
- `04-backend-ports-and-adapters.md` for the sole `AccountSessionEnding` port
  and prohibition on feature-owned provider signout/cleanup;
- `08-verification-observability-and-operations.md` and the implementation
  tracker for the required clean/pending/sync-first/destructive/interruption
  acceptance outcomes; and
- current `AuthManager`, `RootView`, `AccountContext`, `AccountView`,
  `MediaUploadQueue`, operation lifecycle and attachment-durability contracts
  for shipped behavior, known loss risk, and reusable target primitives.

The canonical spec now states the already-approved safety boundary explicitly.
It deliberately leaves final copy/button layout, identity provider, offline
unlock/lease, revocation retention, platform secure storage and physical
cleanup implementation open.

## Why Open Decisions Do Not Block This Slice

- A-007 chooses identity provider/correlation. This boundary carries only a
  stable Ledger Principal and cannot authenticate or sign out a provider.
- A-016 chooses offline lease/unlock/reauthorization. The boundary does not
  decide whether protected data may currently be opened.
- O-023 controls attachment reference/byte retention. The summary counts
  unverified captures but cannot delete, detach, retain, quarantine or purge
  bytes.
- Exact destructive UX copy/policy remains open. The contract requires an
  explicit confirmation bound to displayed exact counts but contains no copy,
  button layout, default selection or platform presentation.
- A-003/A-004/A-015 and physical verification govern Postgres, PowerSync,
  optimistic state and durable encrypted implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes eight product/conversion/architecture requirements and
requires:

- one target-environment/Principal/Account-scoped summary with a supplied
  revision, finite observation time, exact queued/applying/unresolved-rejected/
  unverified-attachment counts and a deterministic fingerprint;
- distinct clean, sync-first and destructive dispositions;
- clean teardown only from an unchanged all-zero summary;
- sync-first remaining incomplete until a fresh same-scope all-zero summary;
- explicit destructive confirmation bound to the exact current summary and
  invalidated by any scope/count/revision change;
- canonical request/confirmation restart and tamper refusal with stable bounded
  diagnostics;
- cancellation represented by absence of an end-session request and no port
  call; and
- one narrow provider-neutral `AccountSessionEnding` port whose later adapter
  alone coordinates synchronization, queue/media disposition, database/key/
  cache cleanup, provider signout and interruption recovery.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local storage,
media retention/deletion, app/MCP, migration, observability and feature
activation are explicit nonapplicabilities.

## Dependency Evidence

The preceding Space-checklist verification-document checkpoint is immutable at
commit `3cfbcb5a70c0d3620aedf04a57bf46690cd6263a`; GitHub Actions run
`33660769158` passed both conversion traceability and isolated target jobs,
including all 164 then-existing target tests, both staging builds and clean
tracked artifacts.

The source/caller/authority mapping is reviewed in
`EVID-CAPABILITY-IDENTITY-001` and `EVID-M2-IDENTITY-001`. Verified shared
operation lifecycle, target-environment identity and attachment local-
durability receipt contracts supply dependencies without authorizing physical
cleanup or provider behavior by implication.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed identity/
lifecycle batch and are `target_mapped`. The dossier has no blocker; every
requirement is reciprocally covered by domain, offline-restart, offline-
rejection, deterministic port-flow and exact-commit operational obligations.

The synchronized ledger is expected to record 783 surfaces / 768 discovered,
357 mapped-or-later target-relevant surfaces, 164 residual surfaces and 43
validated blockers. Thirty-nine slices claim 99 target surfaces while 82 remain
implementation-advanced. M0 must pass. M1/M2 must retain exactly their expected
2/164 prerequisite blockers, zero structural errors and the same three
explained retired-path warnings.

The complete local ready gate passes:

- conversion sync/check/report and capability/query/residual controls;
- M0, with M1/M2 retaining their expected 2/164 prerequisite blockers;
- all 164 existing target tests while both scaffolds remain comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds; and
- clean diff formatting.

Passing immutable exact-ready-commit CI may authorize only the bounded
provider-free implementation named here.

Exact comment-only ready commit
`caa9a9003c13782780d6107df805b95f2f9240ba` passed immutable GitHub Actions
run `33662071456`: conversion traceability passed in 10 seconds and the
isolated target environment passed in 2 minutes 23 seconds with all 164 then-
existing tests, graph/generated-contract checks, both staging builds and clean
tracked artifacts. That gate authorized only the frozen provider-free
implementation.

## Implemented Contract

- `PendingLocalWorkSummary` binds one target environment, stable Principal and
  Account, supplied snapshot revision, finite observation time, and exact
  queued/applying/unresolved-rejected/unverified-attachment counts. A canonical
  SHA-256 fingerprint covers every field and `hasBlockingWork` derives only
  whether any count is nonzero.
- `SessionEndDisposition` distinguishes ordinary clean logout, synchronize-
  then-logout, and remove-from-device-discarding-pending-work.
  `SessionEndChoice.cancel` produces no request.
- `DestructiveLocalRemovalConfirmation` embeds the exact confirmed summary and
  confirmation time. `SessionEndRequest` binds disposition, expected summary,
  optional confirmation and request time in a second canonical fingerprint;
  construction and decoding reject pending clean logout, missing/mismatched
  destructive confirmation, invalid chronology and tamper.
- `SessionEndPolicy` requires exact unchanged current evidence for clean and
  destructive teardown. Sync-first accepts only nonregressing same-scope
  summaries, reports synchronization-required while any work remains, and
  becomes teardown-ready only at a fresh all-zero summary.
- `AccountSessionEnding` is the sole narrow provider-neutral inspection/end
  port. `SessionEndingFailure` provides stable bounded diagnostics for invalid,
  stale, rebound, incomplete and failed behavior.

The contract contains no identity-provider object, token, filesystem path,
encryption key, operation payload, attachment bytes, database/provider call, or
authoritative cleanup result. The deterministic test port mutates only in-memory
synthetic state and is not a production adapter.

Implementation hashes:

- `SessionEndingPolicy.swift`:
  `dd66111bdf6597114b4be7b49198c679352bc35d61b3a297c4e3151c2007ffe7`
- `SessionEndingPolicyTests.swift`:
  `72230b9f5351b835c807526e3fe077722a40815cf165526879cde2f7f9990f84`

## Local Implementation Verification

Four focused deterministic tests pass. They prove exact count separation;
clean/sync-first/destructive/cancel choices; clean-zero and sync-to-zero
evaluation; exact destructive confirmation; byte-identical summary,
confirmation and request restart; stable invalid/tampered/scope/stale/
regression diagnostics; cancellation no-call; stale destructive refusal; and
no false completion from an incomplete-sync or failing port.

The complete local implementation gate passes: all 168 target tests in 39
suites, target environment isolation, generated app/MCP contracts, macOS and
generic iOS Simulator staging builds, conversion/capability/query/residual
controls, M0 and clean diff formatting. The ledger remains at 783 recorded /
768 discovered and 357 mapped-or-later / 164 residual / 43 blockers; 84 target
surfaces are implementation-advanced. M1/M2 retain the expected 2/164 blockers.

`SESSIONEND-TEST-001` through `-004` pass locally.

## Immutable Exact-Commit Verification

Exact implementation commit
`bf9a00ca45c8054018ab6f021aab13386ba24872` passed immutable GitHub Actions
run `33663785835`. Conversion state and traceability passed in 15 seconds. The
isolated target environment passed in 2 minutes 32 seconds with all 168 target
tests in 39 suites, target environment and generated app/MCP contract checks,
macOS and generic iOS Simulator staging builds, and clean tracked artifacts.

All five dossier obligations pass. `SESSIONEND-TEST-005` is satisfied by that
exact-commit run, and exactly `SWIFT-1599BDC0D574` and `TEST-95498CCCD467` are
now verified. This verification establishes only the bounded provider-free
policy described above.

## Permanent Limits

This evidence cannot verify provider signout, physical queue/media/database/
key/cache cleanup, crash recovery, Auth, offline lease, O-023 retention,
Postgres, RLS, PowerSync, app/MCP UI, migration, hosted resources, production
access, release or cutover. The source Firebase application is unchanged.
