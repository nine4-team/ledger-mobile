# EVID-PENDING-WORK-POWERSYNC-PROVIDER-001 — Local Pending-Work Summary Provider

- Status: READY reviewed; comment-only new implementation leaves; immutable CI pending
- Date: 2026-09-04
- Environment: isolated target worktree and disposable encrypted local fixtures only
- Production/Firebase impact: none
- Slice: `pending-work-powersync-provider`

## Outcome

This package freezes a bounded provider that will derive the existing canonical
`PendingLocalWorkSummary` from actual Account-workspace operation evidence and
the separate protected attachment-durability store. It is the local evidence
provider required before a later `AccountSessionEnding` coordinator can safely
evaluate clean, sync-first, or explicitly destructive dispositions.

Only the new provider and focused-test leaves contain comments. Existing schema,
runtime, operation lifecycle, attachment store/vault, policy, and tests remain
byte-unchanged until this READY package passes independent review and immutable
CI.

## Exact Evidence Boundary

The provider will count:

- local operation state `queued`;
- local operation state `applying`;
- local operation state `rejected` until a separate workflow records
  `resolved`; and
- every still-present attachment-durability row because no current provider API
  can establish remote verification, including rows whose bytes are explicitly
  missing or corrupt; and
- the protected byte-vault orphan inventory. Because orphan staging/final bytes
  cannot be identified as exact Attachments, any orphan refuses summary
  construction instead of being guessed into a count or omitted as clean.

It will validate all lifecycle states before excluding `applied`, `superseded`,
or `resolved`. It will not use `pendingUploadCount()` or `ps_crud` as summary
authority because those reflect PowerSync transport work, not the complete
pending-work safety contract.

## Stable Observation Design

Counts alone cannot detect replacing one operation or attachment with another,
and timestamps alone can collide. The implementation will therefore derive one
canonical digest from sorted, identity-bearing structured and attachment
evidence. A local-only, scope-bound observation journal in the encrypted Account
workspace will preserve the same snapshot revision, observation time, and final
summary fingerprint while that digest remains unchanged, including after
close/reopen. Any changed digest advances the durable revision monotonically,
even when the four counts are identical.

Because structured operations and attachment evidence currently live in
separate encrypted stores, one actor-owned observation authority will serialize
callers. Each attempt compares before/after identity-bearing evidence from both
stores, commits the journal transactionally, and then revalidates both stores.
A change during either collection or journal commit causes bounded retry;
persistent change refuses. The implementation will explicitly add a path-free
attachment observation API that returns validated queue evidence plus vault
orphans, maps actual missing/corrupt-byte evidence to blocking states, and
propagates unavailable/interrupted enumeration or journal failures instead of
collapsing them into `corrupt` or zero.

Two query instances cannot become a public composition path: the Account
runtime owns one internal actor authority. Transactional journal compare/update
plus post-journal revalidation still prevents an older digest from returning as
a later authoritative observation if an internal/test-only second instance
exists.

## Independent READY Review

The initial review returned NO-GO. It found that the first candidate omitted
orphaned vault bytes, underspecified mutation during/after journal update, relied
on an attachment API that swallows some vault failures into `corrupt`, and named
affected shared surfaces only generically. This corrected package:

- includes vault orphan inventory and refuses queue-free orphaned bytes;
- serializes the provider, uses transactional journal compare/update, and
  revalidates both stores after journal commit;
- requires a new path-free attachment observation API that distinguishes
  missing/corrupt evidence from unavailable/interrupted observation; and
- freezes every affected shared file, surface ID, and READY hash while leaving
  primary ownership unchanged.

The independent corrected-diff review returned GO with no remaining P0-P3
finding. It confirmed that the two new leaves remain comments only, existing
executable files remain unchanged, and all four prior findings are now explicit
implementation and test obligations.

## Planned Verification

- exact zero, each pending class independently, mixtures, and large valid
  counts;
- terminal operation-state exclusion only after complete state validation;
- unknown, null, malformed, foreign-Principal, foreign-Account, rebound-
  environment, and overflow evidence refusal;
- pending, missing, and corrupt attachment rows all remain blocking;
- queue-free staging/final vault orphans refuse rather than returning zero,
  including after restart;
- `ps_crud` divergence cannot change or substitute for summary evidence;
- unchanged observations return byte-identical summary evidence;
- lifecycle transitions and same-count identity replacement advance revision;
- revision/time/fingerprint survive encrypted process-style close/reopen;
- mutation after the apparently stable second read, mutation during journal
  commit, persistent churn, and two concurrent callers remain monotonic and
  retry or fail closed;
- operation database, attachment database/vault, and observation-journal
  failures never become zero;
- the result composes with the existing `SessionEndPolicy` while performing no
  end-session action; and
- complete conversion, target, local provider, macOS, and iOS CI gates pass on
  exact synchronized READY and implementation commits.

## Hard Boundary

This slice does not synchronize work, mark attachments uploaded, resolve a
rejection, delete a queue/media/database/key, sign out a provider, switch or
activate an Account, choose Auth or offline-lease policy, implement a screen or
MCP tool, access hosted Supabase/PowerSync, read Firebase, migrate data, or
authorize release/cutover.

A-003/A-004 remain proposed. A-007/A-016 and O-023 remain open. The later
physical session-ending coordinator must own synchronization quiescence, a fresh
final summary, exact destructive confirmation, cleanup journaling, interruption
recovery, secure deletion, and provider signout.

## Frozen Affected Surfaces

Primary READY leaves:

- `SWIFT-4AB6FC526AA5` — `PendingWorkPowerSyncQuery.swift` — READY hash
  `7edf895286fd9d19a0c733cd41aa4607a6504dbc3e91135be34bc6eaab7e19b6`;
- `TEST-2053D13BB3B5` — `PendingWorkPowerSyncQueryTests.swift` — READY hash
  `37d2888f2fffb13a924976c0dd8efa553f46a3e51e7e0127529b694935b9e38d`.

Affected/shared implementation surfaces that retain their existing primary
owners:

- `SWIFT-19D4AA7B766B` — `LedgerPowerSyncSchema.swift` —
  `669344548be498d1dd0a065f78de7e47d6048110203bab27468d44fa65adec1a`;
- `SWIFT-548A8A928FAE` — `LedgerOfflineClientRuntime.swift` —
  `ff86a0126707ff116529582644e93c91c938fd4c4a1ac4261f1264ef919ad565`;
- `SWIFT-F850F907B87F` — `AttachmentCapturePowerSyncStore.swift` —
  `d5fc58365db81a619d1600208997d0108a19c701486a02f88a7139263600fade`;
- `TEST-CE5D3D0516D1` — `AttachmentDurabilityProviderTests.swift` —
  `2a648c0affc727337a7936f1a3789c1b170e876666d37b2f9b80376fc76a86c9`.

`AttachmentLocalByteVault.swift`, `SessionEndingPolicy.swift`,
`OperationLifecycle.swift`, and their existing tests are unchanged
dependencies, not affected implementation surfaces.
