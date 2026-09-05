# EVID-PENDING-WORK-POWERSYNC-PROVIDER-001 — Local Pending-Work Summary Provider

- Status: locally implemented and independently reviewed; exact implementation CI pending
- Date: 2026-09-04
- Environment: isolated target worktree and disposable encrypted local fixtures only
- Production/Firebase impact: none
- Slice: `pending-work-powersync-provider`

## Outcome

This package implements a bounded provider that derives the existing canonical
`PendingLocalWorkSummary` from actual Account-workspace operation evidence and
the separate protected attachment-durability store. It is the local evidence
provider required before a later `AccountSessionEnding` coordinator can safely
evaluate clean, sync-first, or explicitly destructive dispositions.

The exact corrected READY commit
`2072af47c908738fd01f4fa6405074c87ee1df95` passed all three jobs in immutable
Actions run `33930443887` before executable work began.

## Exact Evidence Boundary

The provider counts:

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

It validates all lifecycle states before excluding `applied`, `superseded`,
or `resolved`. It does not use `pendingUploadCount()` or `ps_crud` as summary
authority because those reflect PowerSync transport work, not the complete
pending-work safety contract.

## Stable Observation Design

Counts alone cannot detect replacing one operation or attachment with another,
and timestamps alone can collide. The implementation derives one
canonical digest from sorted, identity-bearing structured and attachment
evidence. A local-only, scope-bound observation journal in the encrypted Account
workspace preserves the same snapshot revision, observation time, and final
summary fingerprint while that digest remains unchanged, including after
close/reopen. Any changed digest advances the durable revision monotonically,
even when the four counts are identical.

Because structured operations and attachment evidence currently live in
separate encrypted stores, one provider instance uses an explicit async permit
to serialize whole summary operations despite Swift actor reentrancy. Each
attempt compares before/after identity-bearing evidence from both stores,
commits the journal transactionally, revalidates both stores, and rereads the
journal before returning. A change during either collection or journal commit
causes bounded retry; persistent change refuses. The path-free attachment
observation API returns validated queue evidence plus vault orphans, maps actual
missing/corrupt-byte evidence to blocking states, and propagates unavailable or
interrupted enumeration instead of collapsing it into `corrupt` or zero.

This slice is intentionally uncomposed. A later `AccountSessionEnding`
composition must construct the attachment database/vault/key lifecycle and own
exactly one provider instance. The final journal reread detects completed
cross-instance changes as defense-in-depth, but it is not claimed to lock an
accidental second instance through return.

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

The independent corrected-diff READY review returned GO with no remaining P0-P3
finding. It confirmed that the two new leaves remained comments only, existing
executable files remained unchanged, and all four prior findings were explicit
implementation and test obligations. The exact READY commit then passed
immutable run `33930443887`.

## Executable Review Corrections

The first executable review returned NO-GO. It found that Swift actor
reentrancy allowed an overlapping ABA observation, normal runtime composition
was absent despite the draft claiming runtime ownership, extreme finite time
conversion could trap, and the frozen fault/concurrency matrix was not yet
directly exercised. The corrected implementation:

- holds an explicit non-reentrant permit across the complete summary operation;
- rereads the exact scope-bound journal after final cross-store validation;
- uses failable exact epoch-millisecond conversion and nondecreasing journal
  time;
- tests the same-instance ABA window and completed cross-instance change;
- uses the real attachment store across encrypted restart for orphan refusal;
- injects real unavailable orphan enumeration through a bounded vault
  checkpoint; and
- removes all runtime changes and states plainly that safe composition is a
  later slice requiring one owned provider instance plus attachment
  database/vault/key lifecycle.

The final independent corrected-diff review returned GO with no P0-P3 finding.
It independently reran all 16 focused provider tests and confirmed the exact
six implementation-file hashes recorded below.

## Local Verification

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
- all 16 focused provider tests and all 13 attachment-provider tests pass;
- all 391 target Swift tests in 72 suites and both staging builds pass locally;
  and
- exact synchronized implementation CI and local Supabase checks remain to be
  recorded on the implementation commit.

## Hard Boundary

This slice is not composed into `LedgerOfflineClientRuntime` and does not
synchronize work, mark attachments uploaded, resolve a
rejection, delete a queue/media/database/key, sign out a provider, switch or
activate an Account, choose Auth or offline-lease policy, implement a screen or
MCP tool, access hosted Supabase/PowerSync, read Firebase, migrate data, or
authorize release/cutover.

A-003/A-004 remain proposed. A-007/A-016 and O-023 remain open. The later
physical session-ending coordinator must own exactly one provider instance, the
attachment database/vault/key lifecycle, synchronization quiescence, a fresh
final summary, exact destructive confirmation, cleanup journaling, interruption
recovery, secure deletion, and provider signout.

## Frozen Affected Surfaces

Primary implementation leaves:

- `SWIFT-4AB6FC526AA5` — `PendingWorkPowerSyncQuery.swift` — implementation hash
  `036ea69b475795f04ce5820f4884969cd02461948a9ac40e9ac13f86d3d11bf1`;
- `TEST-2053D13BB3B5` — `PendingWorkPowerSyncQueryTests.swift` — implementation hash
  `31edc5a70e6711b69ae36746ab9409815c8af547351a689f64cf5da6b01b801f`.

Affected/shared implementation surfaces that retain their existing primary
owners:

- `SWIFT-19D4AA7B766B` — `LedgerPowerSyncSchema.swift` —
  `a11de86c5552eac7cc6597ae3f144b04e501f2afe99634c970a4635925bbcbed`;
- `SWIFT-F850F907B87F` — `AttachmentCapturePowerSyncStore.swift` —
  `349110050cd2ed4b8b8fbca8393ab8e13599e79ce5d523f9e200725e20458850`;
- `SWIFT-68F4E18977D4` — `AttachmentLocalByteVault.swift` —
  `9581e01d5087e2fa39f12906c8022bf5e5db21e076a16db454bf4340c4829dcb`;
- `TEST-CE5D3D0516D1` — `AttachmentDurabilityProviderTests.swift` —
  `c4964bc23dd67aebf6e9eb6425f668ebfb3aa7f103db6237759405aae27185d1`.

`LedgerOfflineClientRuntime.swift`, `SessionEndingPolicy.swift`, and
`OperationLifecycle.swift` are unchanged dependencies, not affected
implementation surfaces.
