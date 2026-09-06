# EVID-BUDGET-CATEGORY-REFERENCE-POWERSYNC-PROVIDER-001 — Local Budget-Category Reference Provider

- Status: implemented locally after a separately reviewed reliability
  correction; exact synchronized correction CI pending
- Date: 2026-09-06
- Environment: isolated target worktree and synthetic local fixtures only
- Production/Firebase impact: none
- Slice: `budget-category-reference-powersync-provider`

## Selected Outcome

The next bounded slice supplies the missing real local
`BudgetCategoryReferenceQuerying` implementation needed to replace the target
Project-setup shell's hardcoded category. It observes only category rows already
materialized in one encrypted Principal/Account workspace and exposes them
through the existing close-aware runtime facade.

This is an incomplete-first local projection, not final category authorization.
O-026 remains open for category administration and download visibility. The
adapter cannot inspect or interpret `visibility_class`, `financial_access`,
role, hidden rows, or hidden counts.

## Selection Audit

Three candidate directions were independently checked after the Account
workspace runtime passed immutable CI:

- physical session ending/workspace activation is blocked by A-007, A-016,
  O-023 and absent hosted synchronization/authorization proof;
- a direct Transfer-destination provider was rejected before implementation
  because the current Project directory merges caller-owned pending Projects
  into the same `ProjectSummary` shape as authoritative rows, while canonical
  Transfer eligibility requires authoritative Client identity; and
- the local budget-category provider is decision-independent when it consumes
  only the already-materialized subset, remains incomplete by default, and
  makes no visibility decision.

The rejected Transfer comment scaffolds were removed before classification or
commit. No executable Transfer behavior or durable false ownership remains.

## Frozen READY Boundary

Primary comment-only surfaces:

- `LedgeriOS/LedgerTargetPowerSync/BudgetCategoryReferencePowerSyncQuery.swift`;
- `LedgeriOS/LedgerTargetPowerSyncTests/BudgetCategoryReferencePowerSyncQueryTests.swift`.

Future implementation may also modify these shared surfaces under their
existing primary owners:

- `LedgerOfflineClientRuntime.swift` for one Account-bound public watch;
- `AccountWorkspacePendingWorkRuntime.swift` for exactly-one construction and
  the existing stream lease;
- `AccountWorkspacePendingWorkRuntimeTests.swift` for construction, close,
  cancellation and post-close proof; and
- deterministic public-symbol and target-environment controls.

That future touch set is frozen by exact manifest identity and the source hash
at this READY boundary:

| Manifest identity | Exact path | READY source hash | Permitted change |
| --- | --- | --- | --- |
| `SWIFT-548A8A928FAE` | `LedgeriOS/LedgerTargetPowerSync/LedgerOfflineClientRuntime.swift` | `20ccef5cbb04e905d113135b87b2bd22c38d75e0aa990021e7ba80faa4012b61` | Account-bound category-watch facade only |
| `SWIFT-75CFE285AF37` | `LedgeriOS/LedgerTargetPowerSync/AccountWorkspacePendingWorkRuntime.swift` | `608d3d9319cbcc3082dc750e36545f00da43825702d4639b3311ee38038da987` | exactly-one provider construction, existing stream lease, and a module-internal provider cancel-and-join before database close; no public lifecycle API |
| `TEST-8D6A15063B2D` | `LedgeriOS/LedgerTargetPowerSyncTests/AccountWorkspacePendingWorkRuntimeTests.swift` | `f70ed4ea57e30cbc8287b097644b56881b19627b8dd453be92cd85045df47137` | category construction/facade/close/restart proof only |
| `CONFIG-81235587F306`, `FILE-A6E49E3815F4` | `scripts/check-target-environment.mjs` | `af4ccc5b6401059f2d26326127a7d482b265cf5383ad18d2008bf542dff965bd` | exact facade/provider/completeness source and build-graph rejection only |

The two control identities intentionally describe the same physical script.
Any other executable path or any mismatch from these READY hashes requires a
new review before implementation; listing these touchpoints does not transfer
their existing primary ownership to this slice.

Existing Supabase migrations, RLS policies, Data API grants,
`powersync/sync-streams.yaml`, the target staging app, MCP, and Firebase source
remain byte-unchanged and outside this READY package.

## Authority and Safety Result

The verified category-reference contract already defines stable category
identity, kind, lifecycle, system/exclusion flags, order, revision, visible-row
privacy, and partial/stale/ready distinctions. The provider may materialize
those values without deciding who may view or administer them.

The exact READY design requires:

- Account mismatch rejection before database observation;
- active same-Principal local membership only as a scope sentinel;
- no local category visibility or hidden-count logic;
- every materialized ordinary- and restricted-class row preserved;
- query-specific completeness false by default and independent of generic
  PowerSync status;
- authoritative empty only after explicit current-process completeness;
- atomic malformed/duplicate-row refusal;
- content-bound local versions and deterministic query identity;
- database/completeness reactivity, cancellation and restart proof; and
- live active-to-inactive/revoked-to-deleted membership changes immediately
  clear previously emitted rows as incomplete even when the independent
  completeness source remains true;
- a reciprocal literal-field and content-version matrix over every category,
  scope, completeness and quality axis; and
- runtime close cancellation/drainage before either database closes.

Executable review showed that draining only the runtime's forwarding task did
not prove that the provider-owned row and completeness observers had stopped.
The runtime touchpoint is therefore explicitly refrozen to include one
module-internal provider cancel-and-join call during the existing close
operation, after public stream drainage and before either database close. This
does not add a second public shutdown path or change the runtime's terminal
semantics.

## READY Evidence Before Implementation

The independent reviewer inspected the corrected exact comment-only surfaces,
dossier, classification, affected shared files and test matrix and returned GO
with no remaining P0-P3 finding. Exact READY commit `8eafd6c9` then passed all
three jobs in immutable Actions run `33943581567` before executable work began.

Implementation remains separate from verification promotion. It cannot advance
A-003/A-004/A-007/A-016/O-026, authorize hosted resources, access production,
read or modify Firebase, migrate data, release, or cut over.

## Executable Review and Local Verification

The implementation provides one module-internal, exact Account/Principal-bound
PowerSync query over the already-materialized category subset and exposes only
the zero-argument Account-bound runtime watch. It preserves every literal
category field, orders canonically, distinguishes partial/stale/ready truth,
resets completeness after restart, clears rows reactively when local membership
is revoked or deleted, and refuses malformed, duplicate, overflow, or cross-
Account evidence atomically.

The first executable review returned NO-GO because runtime shutdown drained the
public forwarding task without proving the provider-owned database and
completeness observers had stopped; the reciprocal version matrix and post-
cancellation proof were also incomplete. The corrected implementation uses a
race-safe internal watch registry, joins both provider observations, and makes
runtime close await that internal drain before either database closes. The
refrozen shared touchpoint explicitly authorizes this internal lifecycle hook
without adding a public shutdown API. Corrected tests directly prove drain
ordering, source termination, same-public-stream termination, literal Account
ownership, all category fields, row membership, scope, completeness, quality,
canonical order, fingerprint, and LocalDataVersion axes.

Final corrected-diff review returned GO with no remaining P0-P3 finding. Fourteen
focused provider tests, 14 focused runtime tests, all 419 Swift tests in 74
suites, target-environment checks, and both staging builds pass locally. Exact
implementation checkpoint `376685f5` then exposed a nondeterministic provider
ordering defect in immutable run `33945825011`: the macOS job timed out after
the test process stopped advancing, and local repetition independently produced
an out-of-order readiness failure on repeat eight. The provider now waits for
both its row source and explicit completeness source before emitting a snapshot,
instead of treating task scheduling order as completeness evidence. The affected
provider/pending-work suites pass 30 consecutive serialized repetitions. An
independent correction review then returned NO-GO on one proof gap: repetition
was not deterministic evidence of both source-arrival orders or cancellation
before the first combined snapshot. A testable module-internal accumulator now
proves both orders, and a real provider test proves cancellation drains both
observers without an initial completeness value or public emission. All 419
tests pass after the correction. Exact corrected implementation commit
`9eecacfd0e686b932b1568aa333deaefc0dbdf21` then passed all three jobs in
immutable Actions run `33947678048`: conversion state and traceability, the
disposable local Supabase provider checks, all 419 nonparallel target tests,
target boundaries/contracts, and both staging builds. The cancelled predecessor
run remains recorded as non-passing evidence.

## Independent Review Correction

The first exact-package review returned NO-GO before executable work. It found
that generic prose did not freeze shared touchpoints, static membership cases
did not prove same-watch retraction, this enabling provider was incorrectly
classified as a product outcome, field/version proof was not reciprocal, the
compiler-symbol claim exceeded the repository's tooling, and one source token
caused conservative Firebase-coupling metadata. This corrected candidate:

- records exact shared manifest IDs, hashes, permitted responsibility and
  unchanged primary ownership;
- adds same-watch active-to-revoked/deleted clearing with stale-completeness
  rejection;
- classifies the provider as a technical control inheriting the verified
  category-reference contract;
- adds a literal-field, version and fingerprint matrix;
- narrows compiler-boundary proof to explicit compile-time assertions and exact
  checks added to the frozen environment script; and
- removes the misleading source token from the test scaffold.

Final independent re-review returned GO with no remaining P0-P3 finding. The
exact corrected implementation commit and immutable run above satisfy
`CATPOWER-TEST-007` and promote this bounded local provider slice to verified.

## Post-verification Shutdown Reliability Correction

Exact Item-to-Space assignment implementation commit
`0e097a35c89336c7a90396e4eda9280222e3ab1a` triggered immutable Actions run
`34029102593`. Its conversion and disposable-local-Supabase jobs passed, but
the macOS job timed out after entering the existing `Provider shutdown joins
row and completeness observers` test. The log identifies the stopped test and
the 20-minute workflow cancellation; the assignment suite itself was not the
stopped suite.

That failure exposed a pre-existing cancellation cycle in this provider. Once
both upstream observers were open and idle, registry shutdown cancelled the
owner task, but the owner remained suspended awaiting another internal event.
The code that cancelled and joined the upstream observers ran only after that
event loop returned, so no component could wake the loop.

The separately bounded correction changes only
`BudgetCategoryReferencePowerSyncQuery.swift`. A task-cancellation handler now
cancels both owned observers and finishes the internal event channel, waking
the idle loop. The unchanged cleanup then cancels idempotently, awaits both
child results, and only afterward lets the registry mark the watch finished.
Cancellation remains normal stream completion and database/domain failures
retain their prior bounded mapping.

Two independent executable reviewers found no P0-P3 issue in the code and
agreed that it must be recorded under this owning provider slice rather than
silently folded into Item assignment. Local proof passes:

- 14/14 focused provider tests;
- 100/100 consecutive post-emission shutdown repetitions;
- 100/100 consecutive pre-completeness idle-shutdown repetitions;
- 606/606 Swift tests in 93 suites with normal parallel execution; and
- 606/606 Swift tests in 93 suites with CI's `--no-parallel` execution.

The corrected source hash is
`9a2627996d0541aa3a965a0c0fb57a4c22943af2979107b51508ef1722af826d`.
`CATPOWER-TEST-010` remains planned until an exact synchronized correction
commit passes all immutable workflow jobs. Until then the current slice state
is `implemented`, not re-verified. This correction adds no schema, RLS, Sync,
app UI, MCP, hosted, Firebase, migration, production or cutover behavior.

The separately committed correction
`a54719140a305012e3978eb809908ee77a17587a` triggered exact Actions run
`34030874960`. Conversion/traceability and disposable local Supabase passed
again. The macOS target-test step timed out again, but this time its terminal
test was the unrelated provider-free Space-creation canonical-restart test,
which passes locally in 0.004 seconds. Independent event-order analysis confirms
that both timed-out runs executed suites serially; SwiftPM `--no-parallel` was
honored. The first run remains valid evidence of the corrected Budget-category
cancellation defect, while the second is a distinct unresolved shared-process
failure rather than proof against that correction.

Because the second terminal test performs synchronous codec work, the next
verification step is bounded execution of that test after its exact preceding
suite prefix with process/task/thread diagnostics captured before timeout, plus
an audit that provider/runtime registries and spawned tasks drain at suite
return. No CI-harness correction or causal explanation is claimed yet. A causal
correction, independent review and exact synchronized all-job pass remain
required for `CATPOWER-TEST-010`.
