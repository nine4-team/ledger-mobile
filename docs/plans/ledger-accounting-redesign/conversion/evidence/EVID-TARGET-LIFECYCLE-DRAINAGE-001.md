# EVID-TARGET-LIFECYCLE-DRAINAGE-001 — Target Lifecycle Drainage Correction

- Status: implemented locally and independently reviewed; exact synchronized CI pending
- Date: 2026-09-06
- Environment: isolated Supabase/PowerSync target worktree and synthetic local fixtures only
- Production/Firebase impact: none

## Scope

This correction closes target-only task-lifecycle gaps discovered while
investigating two non-reproducing hosted Swift test-process timeouts. It does
not claim that either gap caused those timeouts.

The Project Setup application model now:

- owns every Client/category observer and admitted submission in one shared
  task registry until the task actually completes;
- invalidates the active generation before awaiting drainage, so concurrent
  start/start, stop/stop, and stop/start calls share predecessor work while
  only the latest start may activate replacement observers;
- propagates caller cancellation to owned submission work and rechecks
  cancellation after a noncooperative dependency returns, preventing a late
  success receipt from being published;
- preserves stable retry identity and user input across cancellation; and
- drains all admitted work before the staging application closes its Account
  runtime.

Five provider-free Core cancellation fixtures now cancel and join their
producer before reporting termination. Their assertions are bounded so a
cleanup regression fails with evidence instead of hanging the complete job.
No product-domain value, command, schema, RLS policy, Sync Stream, provider,
MCP behavior, migration rule, hosted resource, or production path changes.

## Surfaces and hashes

- `SWIFT-061553E63650` —
  `7560f25080299feeb28f5e5d85aa479d3989a4b90251d127a921b2c1beed537f`
- `SWIFT-64E1171C47C5` —
  `3c665e7f68d75a2b9a04691e69e1dbe497b65b6218b5c9ee4f817fedb0b2d7ef`
- `TEST-E92B32DB7642` —
  `9ab72864683360044c0907c6e8b083ee7ae8673240bd1681f30859328539b504`
- `TEST-F304037D32B6` —
  `c622b6869bcd4811633a40473c15f51c718e04a0ef177e09e9cf885dec785343`
- `TEST-A0B2D5B97695` —
  `04dad151c390dcab722a71725521da8758998d00044b841cb0dcc81f62b66371`
- `TEST-5F24EA7C310A` —
  `199c2a4d5580d697a569836c6cc657ec2db481762f937734a57b19b1280697e0`
- `TEST-8B902DC97729` —
  `8c577052bd9b5dca768cf170636a2d150af5c34310616e5a8c9653ccc776b7ed`
- `TEST-377B0FDAF4D4` —
  `25f7013ca31f9d3c3599e7752cf8dd90fdfe601475e1c7181e6b2ed7a0aedd75`

## Review and local verification

The first independent review returned NO-GO for reentrant handle loss,
unowned submission work, incomplete race coverage and unbounded fixture
cleanup. The second returned NO-GO for cancelled noncooperative late success
and nondeterministic suspension cleanup. All findings were corrected. Final
independent re-review returned GO with no P0-P3 finding.

Passing local evidence:

- `swift test --package-path LedgeriOS --filter ProjectSetupStagingExerciseTests --no-parallel`
  — 14 tests;
- 25 exact repetitions of each of four adversarial caller-cancellation and
  concurrent lifecycle tests — 100/100;
- the six affected suites — 44 tests; and
- `swift test --package-path LedgeriOS --no-parallel` — 611 tests in 93 suites.

The first synchronized implementation checkpoint `b7dba780` triggered Actions
run `34034920599`. It failed fast in the Linux query-inventory control because
the checkpoint had administratively downgraded five unchanged verified Core
query owners together with their strengthened test fixtures. The inventory is
deliberately defined only over verified query owners, so that bookkeeping was
invalid. No Swift, Supabase or build job ran and this is not passing evidence.
The correction restores those unchanged domain/query implementations and their
test-only slice status to verified while retaining the new test hashes and this
evidence; only the changed Project Setup application-flow implementation stays
at `implemented`. The complete local Linux control sequence, including all 20
query-inventory and 23 query-authority tests, passes after correction.

The Project Setup application-flow slice is deliberately `implemented`, not
`verified`, and its exact-CI obligation is reopened until the synchronized
correction commit passes every immutable workflow job. The five provider-free
read contracts retain their verified domain implementations because only their
test producer-drain fixtures changed; the strengthened fixtures pass locally
and remain tied to this evidence. Hosted Swift stack capture remains the
required diagnostic if the earlier non-reproducing timeout recurs.

## Explicit non-advancement

This evidence authorizes no production or hosted access, Firebase change,
schema/RLS/Sync modification, migration, release, or cutover. It proves a local
target lifecycle correction only.
