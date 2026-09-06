# EVID-CLIENT-PROJECT-DIRECTORY-PROVIDER-001 — Client/Project PowerSync Directory Provider

- Status: implemented; original exact implementation CI passed; lifecycle correction exact CI pending; hosted Sync proof pending
- Date: 2026-09-06
- Environment: isolated target worktree and disposable local fixtures only
- Production/Firebase impact: none
- Slice: `client-project-directory-powersync-provider`
- Surfaces: `SWIFT-B23F91245E50`, `TEST-5AAEE26660C8`

## Outcome

This checkpoint implements Ledger's already-verified backend-neutral Client and
Project directory contracts against the local PowerSync database and isolated
staging app. The adapter and its 16-test suite are executable target-only code.

The local flow now shows offline-created Clients and Projects immediately,
selects any currently represented active Client, splits Projects into active and
archived segments, and derives the exact existing detail request from a selected
row. Local rows remain useful while completeness is stated honestly.

## Implemented Safety and Offline Behavior

- The runtime is bound to one exact Principal and Account. Wrong-Account reads
  or writes and wrong-Principal writes fail before any operation, overlay or
  upload row exists.
- Authoritative rows appear only behind locally visible active-membership
  evidence. The same Principal's accepted pending rows remain visible as
  partial evidence before membership readback; hidden authority cannot replace
  or reconcile them in either directory or exact-detail reads.
- Client and Project stream completeness are independent reactive inputs. A
  global connection/has-synced flag cannot make either directory ready.
- Raw Project rows are counted before Client joining. A delayed Client produces
  incomplete evidence, never an authoritative empty result.
- LocalDataVersion binds exact content and readiness rather than a maximum
  timestamp. Stable ID order is technical only and settles no final sorting.
- Project-core readback may remove the exact Project overlay only after its
  relationship is locally complete. It cannot delete pending category
  allocations without aggregate-aware authoritative allocation evidence.
- Encrypted restart, consumer cancellation, provider shutdown drainage, and
  rejection of watches after shutdown begins are explicit executable
  obligations.

## Existing Physical Dependencies

The slice adds no Postgres object. It reuses the current spike-prefixed Client,
Project and membership tables, explicit grants, RLS policies, indexes, Sync
Stream rows, encrypted schema, pending-create overlays, create stores, detail
queries, staging target, and provider-free projection contracts. Those surfaces
retain their existing primary slice ownership.

## Excluded Scope

This implementation does not decide or implement Project/Client archive
mutation, text mutation, final sorting/search, Project card or budget preview,
MCP pagination/list/get APIs, Firebase compatibility, source migration, hosted
Auth/PowerSync, deployment, production access, release or cutover. O-024/O-025,
O-040 and O-042/O-043 remain outside. A-003/A-004 remain proposed.

## Independent Review

The first independent implementation review rejected the candidate for four P1
defects and two P2 integration defects: one shared non-reactive completeness
flag, fresh pending rows hidden until membership arrived, missing runtime scope
guards, Project core readback deleting allocation optimism, stale Client
selection at Project submission, and directory tasks escaping the SwiftUI task
lifetime. Each defect was corrected with direct regression coverage.

A second independent review found one remaining P1: a matching authoritative row
could replace and reconcile the caller's pending row before membership became
visible. SQL precedence now hides authority until active membership, retains the
same Principal's pending values without a reconciliation ID, and a direct test
proves both overlays survive.

A third independent final review then rejected the corrected directory because
exact Client/Project detail readers still preferred matching authoritative rows
without requiring membership. The Principal/Account-bound detail readers now
use the same membership-gated precedence and reconciliation policy as the
directory. An end-to-end regression selects pending rows, opens both exact
details while conflicting authority is locally present but membership is not,
and proves the pending values and overlays survive. Another adversarial case
proves pending rows owned by a different Principal do not enter either local
directory. Final corrected-diff review returned executable GO with no P0-P2;
its sole P3 was this evidence package's stale 14-test label, corrected to 16
before commit. Local SQL isolation is still not reported as hosted RLS/Sync
proof.

## READY Validation

The synchronized comment-only package passed locally and at exact READY commit
`2417d20bd03540288575bb2a33b96130e7edd4c2` / immutable Actions run
`33915624174`:

- conversion/query-port/query-authority/source-query/capability/residual checks
  and M0, with only the three pre-existing retired-path warnings;
- all 342 target Swift tests in 68 suites;
- all 11 target MCP tests and strict TypeScript/contract checks;
- byte-stable target Xcode project generation;
- macOS and generic iOS Simulator staging builds;
- local Supabase database lint, 42 pgTAP assertions, and the Client and Project
  RPC/Data API authorization/replay checks.

These results prove the READY control package did not break existing target
behavior. They do not claim that hosted PowerSync authorization was exercised.

The generated Xcode project also catches up its source-directory membership for
the pre-existing comment-only `ClientRenameStagingExercise.swift` DRAFT file.
That deterministic generated-project change adds no executable rename behavior;
the file remains blocked by O-042/O-043 under its existing primary ownership.

## Local Implementation Verification

The synchronized implementation passes locally:

- 16 focused Client/Project directory tests;
- all seven Project provider tests, including the corrected core-only readback
  case that retains all three pending allocations;
- all 358 target Swift tests in 69 suites;
- cross-Account and cross-Principal runtime mutation/read refusal before any
  operation, overlay or PowerSync upload row exists;
- independently reactive Client/Project completeness, zero-row transitions,
  hidden-authority/pending precedence across directory and exact detail,
  same-Principal pending-row isolation, missing-relationship truth, encrypted
  restart, content-version change, exact selection/detail navigation and
  cancellation;
- all 11 target MCP tests, strict TypeScript/contract checks, byte-stable Xcode
  generation, both staging builds, local schema lint, all 42 pgTAP assertions,
  and Client/Project RPC/RLS/replay checks.

Exact synchronized implementation commit
`a1b57a37a750486246273664606e33d086b2801c` passed immutable Actions run
`33918240622`: conversion traceability completed in 41 seconds, local Supabase
provider slices in 1 minute 52 seconds, and the isolated target environment in
7 minutes 6 seconds. All three jobs passed with no tracked rewrite.

`DIRPROVIDER-TEST-004` remains planned because it requires real isolated
authenticated PowerSync streams; that prevents `verified` or `rehearsed`
status and keeps A-004 proposed.

## Directory Watch Lifecycle Correction

GitHub Actions run `34011514963` attempt 1 passed conversion and local Supabase
jobs but timed out in the target job after the Client archive suite. Rerunning
the unchanged exact commit as attempt 2 passed every job, test, and build. Local
reproduction also passed, identifying a nondeterministic process-lifecycle
defect rather than a deterministic product failure.

The directory provider previously relied on consumer-stream termination alone
to cancel unstructured database and completeness tasks. Runtime shutdown could
therefore reach PowerSync database close while a directory reader still held a
lease. The correction gives the provider a close-aware registry, rejects watch
registration after shutdown begins, cancels every admitted outer watch, and
joins both nested tasks before reporting the watch finished. The account
workspace runtime now drains this provider before archive stores and SQLite.
Every direct test consumer retains and drains its provider before closing its
database.

The first independent correction review found one P1 test-lifecycle defect:
two malformed Project-archive paths still constructed anonymous directory
queries and could resume from an expected error before nested teardown joined.
Both paths now reuse one retained query and await its drain on every later
early-return or normal close. Re-review returned GO with no P0-P3 findings.

Corrected local verification passes:

- 17 of 17 focused directory tests, including simultaneous active Client and
  Project watches, provider shutdown, database close, and late-watch refusal;
- 8 of 8 focused Project archive tests after the review correction;
- all 567 Swift tests in 90 suites nonparallel;
- 20 consecutive focused directory-suite runs;
- conversion source synchronization, target-environment checks, deterministic
  target generation, both isolated staging builds, and immutable exact-commit
  CI remain required before this correction is promoted as final evidence.
