# EVID-LOCAL-OPERATION-IDENTITY-OWNERSHIP-001 — Shared Local OperationID Ownership

- Status: implemented locally; exact implementation CI pending
- Date: 2026-09-06
- Base commit: `04843679c1bffa41aab2efecf2723695dc97fc4a`
- Environment: dedicated target worktree and disposable encrypted local databases only
- Production/source-backend impact: none

## Finding

The Item-to-Space clearing review exposed a cross-cutting defect in the local
target foundation. `OperationID` is globally unique, but the existing stores
primarily detect collisions through `spike_local_operations`. If that generic
row is absent while command, result, pending, or overlay evidence remains,
another command family can currently reuse the same ID.

Three independent read-only audits confirmed five executable families and the
same blind spot. They also found that create-Client and create-Project replay
currently checks only generic fingerprint/state and writes no explicit command
family or canonical envelope into its generic operation row.

## Selected Design

`spike_local_operations.id` remains the single normal-path ownership claim. A
new shared, stateless guard inspects every operation-bearing local relation for
one exact opaque ID inside each provider's existing serialized write
transaction. It includes local operations, synchronized results, all four exact
command entry types in `ps_crud`, any forbidden local operation-result mutation
queued in `ps_crud`, pending Client/Project/allocation rows, archive overlays,
and the local-only assignment command. Under pinned PowerSync 0.5.3,
an insert-only command view writes only the queue entry and no second backing
row, so the inventory and orphan matrix deliberately model only that supported
representation. `LedgeriOS/Package.resolved` is a frozen no-change input, and
the suite must execute all four view inserts to prove this representation rather
than relying only on source inspection.

This is intentionally not a second ownership table. A newly added empty table
would not own pre-existing rows and would still require the exhaustive audit.
The centralized inventory supplies migration-safe fail-closed behavior now; a
future relation or provider must extend it once and satisfy static completeness
before implementation can advance.

## Admission Semantics

- no evidence permits the provider to continue toward one atomic claim;
- one typed matching-family owner may proceed only to that provider's state-aware
  exact replay validation; a canonical typed applied or rejected create operation
  may be the sole survivor after queue and reconciled/rejected pending drainage,
  while any pending graph still present must validate exactly and gains no new
  cleanup behavior;
- a different family or changed payload produces stable mismatch;
- equal fingerprints do not make different command families equivalent;
- orphaned, malformed, ambiguous, result-only, result-mutation-queue-only,
  untyped/malformed/nonterminal operation-only, pending-only, overlay-only,
  command-only, or multi-family evidence reserves the ID but
  cannot replay, repair, delete, or rebind it; and
- all inspection, claim, family evidence, projection/overlay, and command writes
  remain in one write transaction.

The stable mismatch may carry only the caller-supplied `OperationID` already in
the command. No failure exposes stored foreign identifiers, payload, scope, SQL,
paths, credentials, provider messages, or ownership detail.

Client and Project creation begin writing explicit `create_client` and
`create_project` family plus canonical envelope evidence into new generic rows.
An untyped pre-foundation row may derive its family only from one unambiguous
surviving graph; otherwise it remains reserved. No shipped target local database
exists, and synthetic target databases may be discarded, so this adds no
production migration or repair authority.

## Required Proof

`LOCALOPID-TEST-001` through `-012` cover direct synthetic guard classification
for all current ordered family pairs, public sequential/concurrent submission for
every pair whose ID formats overlap, and pre-database identity refusal plus
synthetic classification for the deliberately disjoint Project-archive/Client-
archive pair. They also cover equal- and changed-payload races for every family
through independent store instances, every operation-bearing relation as an isolated
orphan against every destination provider, including forbidden result-mutation
queue evidence; applied create replay after queue drainage with its pending graph
intact and after authoritative reconciliation removes it; rejected replay after
queue/pending drainage; exact typed-row/pending tampering; the frozen PowerSync package pin and
four executable insert-only representation cases, same-family replay, deliberately
equal cross-family fingerprints, all owner/scope/contract/envelope/lifecycle
tampering, failure and cancellation checkpoints, encrypted restart, bounded
errors, unchanged upload/pending/runtime behavior, and exact static inventory
completeness.

The later clearing provider becomes the sixth family only after this foundation
is verified. Its slice must add one family/relation entry to the centralized
inventory and prove clearing against all five existing families; it no longer
owns ad hoc reciprocal pairwise checks.

## Executable Outcome

Exact READY commit `4d16d68945fb68116db794a15e0d12b258dad1d6`
passed immutable workflow run `34040671631` before executable work began. The
bounded implementation changes exactly the shared guard, its matrix suite, the
five accepting stores, and the target static checker. It:

- inspects every current ID-bearing local relation and every supported or
  forbidden ID-bearing `ps_crud` representation inside the accepting store's
  existing write transaction;
- preserves the five existing command families and rejects cross-family or
  changed-payload reuse without disclosing stored ownership detail;
- persists and checks explicit creation-family and canonical-envelope evidence;
- recognizes exact applied/rejected creation results after supported graph
  drainage while validating every auxiliary row that remains;
- treats malformed JSON queue evidence containing the exact generated
  top-level operation ID as a fail-closed reservation; and
- adds no registry table, server schema, upload transaction shape, projection,
  cleanup, hosted dependency, or source-backend behavior.

## Review Corrections

Primary executable review found and corrected three material gaps before the
local gate: invalid `ps_crud` JSON could escape attribution, partially reconciled
Project graphs were rejected even when each surviving row was exact, and
terminal creation-result validation did not match the current handler contract.
The corrected suite now exercises all five family matrices, queue/result/orphan
representations, same- and cross-family races, lifecycle drainage, every
injected provider failure boundary, and encrypted restart. Independent
adversarial re-review of the corrected eight-file diff returned GO with no
P0–P3 finding.

## Local Verification

The following isolated checks passed on 2026-09-06 without hosted or production
access:

- focused shared-guard suite: 9 of 9 tests;
- seven affected provider suites: 94 of 94 tests;
- complete serial Swift package suite;
- complete target MCP suite;
- target environment checker and unchanged PowerSync package pin;
- disposable local Supabase schema lint, pgTAP/database checks, Space-destination
  read, Project-note read, and Data API/RPC checks;
- macOS staging build and iOS Simulator staging build; and
- clean patch validation.

`LOCALOPID-TEST-001` through `-009` and `-011` through `-012` are therefore
passed. `LOCALOPID-TEST-010` remains planned until the exact implementation
commit passes every immutable workflow job.

## Non-Advancement

This implementation creates no second registry table, synchronized row, new
upload entry, optimistic product projection, cleanup/retention behavior, server
schema, handler, grant, RLS policy, Sync Stream, app/MCP feature, hosted
resource, source-backend change, migration execution, production access,
release, or cutover authority. A-003/A-004/A-015/A-016 remain unadvanced.
