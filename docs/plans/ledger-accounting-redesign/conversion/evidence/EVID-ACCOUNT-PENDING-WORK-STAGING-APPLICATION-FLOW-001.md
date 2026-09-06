# EVID-ACCOUNT-PENDING-WORK-STAGING-APPLICATION-FLOW-001 — Account Pending Work Staging Application Flow

- Status: VERIFIED / exact implementation commit and immutable CI passed
- Date: 2026-09-06
- Exact implementation base: corrected READY commit `eeec46508014e64c8f3876c2157eb1cb6e5e9406`
- Exact READY CI: Actions run `34021709793` passed all three jobs
- Exact implementation: `67decdd5897af309a98c5067abb647bdc3e0d56c`
- Exact implementation CI: Actions run `34023379271` attempt 2 passed all three jobs
- Environment: dedicated target worktree only
- Production/Firebase impact: none

## Implemented Outcome

Add a read-only target-staging section that manually refreshes the existing
exact Account-scoped `PendingLocalWorkSummary`. It presents queued operations,
applying operations, unresolved rejected operations, and the count of captured
attachments whose bytes are not upload-verified as four separate exact counts.
Only a validated all-zero summary may say there is no pending local work.

This is local status evidence, not a logout screen or a Sync-health claim. It
does not synchronize, upload, delete Account/database/key/media state, invoke a
destructive Account/session cleanup API, sign out, switch Accounts, choose a
session disposition, or state that work is remotely durable or safe to discard.
Ordinary model stop/drain and runtime resource teardown remain required.

## Frozen Implementation Boundary

- Reuse the existing summary, encrypted local provider, finite runtime lease and
  public runtime method without changing their semantics.
- Keep AppModel dependent on Core only; only the thin target-app adapter imports
  the PowerSync runtime.
- Manual refresh owns not-requested/loading/clean/pending/failed truth.
- Preserve exact scope, four `UInt64` counts, revision, observation time and
  fingerprint in typed state; never aggregate the counts.
- Register every refresh in a MainActor-serialized admitted-task registry before
  launch, retain replaced/cancelled tasks until joined, and use a fresh UUID
  generation token to reject cooperative and noncooperative late results without
  relying on a wrapping counter.
- Stop becomes terminal for that child instance atomically, refuses late
  admission, clears evidence/runtime closure, cancels and drains the complete
  retired-plus-current task set before Account runtime close on every normal or
  failed staging resource-teardown path. Each reopened runtime gets a fresh child.
- Render bounded diagnostics and stable accessibility identifiers only.

## Implemented Leaves

- `SWIFT-5165512013CB` — AppModel
- `TEST-0B0E0C9D531B` — AppModel tests
- `SWIFT-BBA33BDFCD93` — thin runtime adapter
- `SWIFT-87B098BA9F12` — staging view

All four contain the bounded executable implementation and tests. Existing
Core/provider/runtime dependencies remain byte-identical.

## Required Review and Proof

Initial independent READY review returned NO-GO and identified three P1 and five
P2/P3 recording defects: no exact delivery/touchpoint boundary, broken/stale
evidence reconciliation, incomplete retired-task drainage, wrong Core API and
authority heading, unfrozen expected scope, ambiguous cleanup wording, missing
dependency authorities and an ambiguous attachment-count label. A separate
feasibility review found that no executable-app test target exists and that a
stopped child cannot be reused when the staging `.task` reopens. The corrected
independent re-review is GO with no remaining P0-P3 finding.

The ten frozen verification obligations cover exact count and identity
projection, every pending class, all-zero truth, failure-not-clean, overlapping
refresh, retired-plus-current noncooperative tasks, terminal per-instance stop,
composite staging close-order proof, source containment, full controls/builds
and immutable CI.

## Implementation Review and Local Proof

Two independent executable reviews found and closed comment/decoy checker
bypasses, insufficiently exact adapter/constructor/cleanup enforcement, a
missing late-refresh-during-stop assertion, incomplete status-copy proof, and a
wrapping generation counter. Final independent re-review is GO with no
remaining P0-P3 finding.

- Focused AppModel suite: 8 tests passed.
- Complete Swift package: 585 tests in 92 suites passed.
- Target environment checker and its syntax check passed.
- Adversarial mutations proved a commented-out stop and an adapter with an
  extra runtime call are both rejected, after which the real sources were
  restored and rechecked.
- Deterministic target project generation and both macOS and iOS Simulator
  staging builds passed.
- Exact implementation commit `67decdd5897af309a98c5067abb647bdc3e0d56c`
  passed all three immutable jobs in Actions run `34023379271` attempt 2.
  Attempt 1 timed out in the pre-existing synchronous Space-creation restart
  test. The same exact implementation passed 50 consecutive focused
  Space-creation suites locally and the complete no-parallel Swift suite on
  attempt 2, so the retry is recorded without inventing a product-code fix.

## Explicit Non-Advancement

A-003/A-004/A-007/A-016 and O-023 remain unadvanced. The candidate adds no
Postgres, RLS, Data API, Sync Stream, provider, Storage, attachment-byte access,
MCP, Auth, hosted resource, Firebase, source data, migration, release,
production access or cutover authority.
