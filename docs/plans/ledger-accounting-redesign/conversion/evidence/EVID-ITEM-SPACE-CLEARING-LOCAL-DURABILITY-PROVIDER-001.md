# EVID-ITEM-SPACE-CLEARING-LOCAL-DURABILITY-PROVIDER-001 — Item-to-Space Clearing Local Durability Provider

- Status: implemented and independently reviewed; complete implementation gate pending
- Date: 2026-09-06
- Base commit: `5d3d093710178f5f8da85dbc4c7e706b052c97e4`
- Environment: dedicated target worktree and disposable encrypted local databases only
- Production/Firebase impact: none

## Selected Boundary

This slice supplies encrypted local acceptance for the already-verified
`ClearItemSpaceAssignmentsCommand`. One accepted command will atomically create
one shared queued local-operation row and one command-specific localOnly row,
survive restart, and be observable through the existing Account runtime.

It is not authoritative clearing. It writes no Item, Space, marker, attachment,
accounting, `ps_crud`, or upload state and grants no membership or capability.
O-037 Space-archive behavior, O-023 attachment reference/byte deletion, O-027
Item identity evidence, A-015 optimistic projection, and the A-016 production-
facing workspace/offline-access lease remain unadvanced.

## Clearing-Specific Semantics

Clearing is not assignment with a nullable destination:

- one command may clear Items from different current Spaces in the same exact
  Project or Business Inventory scope;
- each canonical Item evidence entry owns stable Item ID, exact expected Item
  revision, and exact current Space ID;
- the generic operation subject is the Project for Project scope or Account for
  Business Inventory scope;
- there is no destination Space and generic `command_expected_revision` is null;
- current placement/scope evidence is a conflict claim, not authorization; and
- later authoritative apply derives and closes affected green Item-marker
  relationships without deleting Space photos or bytes.

## Proposed Implementation Boundary

The only new executable leaves are the current comment scaffolds:

- `LedgeriOS/LedgerTargetPowerSync/ItemSpaceClearingPowerSyncStore.swift`;
- `LedgeriOS/LedgerTargetPowerSyncTests/ItemSpaceClearingPowerSyncStoreTests.swift`.

The dossier freezes every shared touchpoint and exact base hash. Its bounded
shared-test boundary also permits only the sixth-family fixture, exhaustive-
switch, and matrix extensions required in
`LocalOperationIdentityGuardTests.swift`; existing-family proof may not be
weakened. Implementation
may add one localOnly `spike_item_space_clearing_commands` table, one finite
runtime submission, one dedicated queued-operation watch, close drainage, and
static containment checks. It must reuse the verified Core command/use case and
the separately verified shared local OperationID guard. The slice may register
only its one sixth command family/relation in that centralized inventory; it may
not add pairwise lookups or change an existing provider's semantics.

The local command table uses OperationID as implicit text `id`, exact Account/
Principal/contract/scope/canonical command evidence, nullable Project ID, exact
canonical Item evidence, provider acceptance milliseconds, and one Account
index. The shared operation row uses Project-or-Account subject,
`clear_item_space_assignments`, null expected revision, queued state, canonical
envelope, and null terminal fields. Exact replay is clock-independent.

## Cross-Command Identity Safety

The shared operation journal is one namespace. The separate identity foundation
inspects every registered operation-bearing relation inside each accepting
provider's transaction. Clearing must extend that one inventory and prove
complete, command-only orphan, malformed, deliberately equal-fingerprint, and
concurrent collisions against all five existing families in both directions.
Changed clearing replay, same-family command/operation orphans, terminal/result
evidence, and concurrent same-ID admission receive the same fail-closed proof.

## Required Proof

`ITEMSPACECLEARLOCAL-TEST-001` through `-013` cover both scopes, mixed Spaces,
opaque non-UUID identity, exact UInt64 boundary evidence, byte-identical client-
time codec evidence, complete provider-time bounds, named checkpoints, atomic
rollback, replay/collision/concurrency, exhaustive tamper/orphan/terminal
refusal, encrypted restart, cancellation, watch and runtime drainage,
exactly-one pending-work accounting, zero `ps_crud`/projection/upload changes,
finite diagnostics, static containment, and separate exact READY/implementation
CI checkpoints. The named admission boundary includes `inventoryConstruction`,
`inventoryRead`, and `afterOwnershipInspection` around the verified shared guard;
each injected failure and cancellation must roll back and map through the
clearing provider's bounded contract. The shared guard suite must add the sixth
family to every exact relation/family set, exhaustive switch, family matrix,
orphan destination, restart fixture, and provider-completeness assertion.

## Independent DRAFT Review Corrections

Both independent first-pass reviews returned NO-GO. They first found that the
existing assignment store could not see a clearing-command-only orphan. A later
corrected-DRAFT review found the deeper defect: pairwise assignment/clearing
checks still ignored command, result, pending, and overlay evidence from four
other executable families. Three bounded audits confirmed the global blind spot.

The corrected boundary now depends on
`local-operation-identity-ownership-guard`. That separate technical slice keeps
the generic operation row as the normal ownership claim and inventories every
current operation-bearing relation in one transaction. Clearing will add one
central family/relation registration and test against all five existing
families; no reciprocal pairwise provider edit remains authorized.

The reviews also drove exact non-UUID identity proof, the sibling's complete
UInt64/client-time/provider-time/checkpoint matrix—including the high positive
Date-round-trippable success case—sole ownership of runtime and
pending-work proof by the new clearing test suite, nominal use-case conformance,
live bootstrap/resource binding, comment-stripped structural checks, removal of
premature READY wording and false source-coupling metadata, and correction of
the A-016 lease description. After the identity foundation passed exact
implementation commit `5d3d093710178f5f8da85dbc4c7e706b052c97e4` / immutable
run `34047249986`, the next independent audit returned NO-GO and caught three
stale shared hashes, omission of the necessarily changed shared guard test
suite, and missing guard-specific failure/cancellation checkpoints. The
corrected DRAFT is rebased to that verified checkpoint, includes the bounded
shared suite extension, and freezes all three guard admission boundaries.
Independent corrected-DRAFT re-review returned GO with no P0–P3 finding after
confirming all 14 touchpoint hashes, the verified guard dependency, bounded
shared-suite extension, exact checkpoint matrix, authority traceability, and
non-advancement boundary.

## READY Gate

The shared OperationID foundation is verified, and independent corrected-DRAFT
review audited the exact dossier, authority, touched paths, all 14 hashes, test
matrix, collision boundary, and non-advancement clauses and returned GO with no
P0–P3 finding. No executable provider code may replace either comment scaffold
until this exact synchronized READY commit passes every immutable workflow job.
Passing READY does not authorize
hosted resources, production access, source-backend changes, migration, release,
or cutover.

Exact READY commit `72b8274f4258936bb35490e4172e4d7684bb28b9`
passed all three immutable workflow jobs in run `34048439511` attempt two. The
first attempt timed out in an existing Budget-category malformed-evidence test;
the unchanged retry passed the complete Swift suite and both target builds. A
separate read-only investigation found that the test returned after receiving
its public failure without awaiting provider-watch drainage. That owning test
correction is tracked separately in the same integration batch and does not
widen the clearing provider's eight-path executable authority.

## Executable Implementation and Review

The implementation replaces both comment scaffolds and changes only the six
reviewed shared schema/runtime/identity/checker surfaces. It creates one
`localOnly` clearing-command table, atomically admits exactly one canonical
clearing row plus one queued generic operation, and exposes one finite runtime
submission and one dedicated queued-operation watch. Project scope uses the
Project as generic subject; Business Inventory uses the Account. Generic
expected revision and all terminal fields remain null. No Item, Space, marker,
attachment, synchronized, `ps_crud`, upload, server, UI, MCP, hosted, Firebase,
migration, production, or cutover behavior advances.

The first executable review found no production defect and one P2 proof gap:
the tamper matrix did not cover forbidden non-null `project_id` for Business
Inventory, and exhaustive corrupt command/operation rows proved submission
refusal without also proving zero-emission watch refusal. The corrected suite
adds the Inventory case, asserts exact `malformedLocalEvidence` versus
scope-filtered `operationNotFound` watch outcomes for every tamper/null/orphan/
terminal/result shape, and drains each admitted watch. Independent corrected-
diff re-review returned GO with no P0–P3 finding.

Focused local evidence after correction is 21/21 clearing-provider tests, 9/9
six-family identity-guard tests, 20/20 Budget malformed-matrix drainage
repetitions, clean script syntax, the target-environment checker, and compact
conversion-state validation. The one complete local implementation gate then
passed on 2026-09-06: all conversion and traceability controls, the complete
serial Swift package, generated app/MCP contracts and MCP tests, both macOS and
iOS Simulator staging builds, disposable Supabase lint plus 374 database
assertions and the scoped read/RPC probes, and clean-diff validation. The slice
Exact synchronized implementation commit
`049455223afd3147b596913667f43b3f43d93642` then passed every immutable job
in run `34052053056`: conversion/traceability, the complete serial Swift suite,
target/MCP contracts and tests, disposable local Supabase, both staging builds,
and clean artifacts. This satisfies `ITEMSPACECLEARLOCAL-TEST-013` and promotes
the bounded local-durability provider to `verified`; it does not advance any
authoritative apply, projection, hosted, migration, production, or cutover
claim.
