# EVID-ITEM-SPACE-CLEARING-LOCAL-DURABILITY-PROVIDER-001 — Item-to-Space Clearing Local Durability Provider

- Status: corrected comment-only DRAFT; independent re-review and exact READY CI pending
- Date: 2026-09-06
- Base commit: `04843679c1bffa41aab2efecf2723695dc97fc4a`
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

The dossier freezes every shared touchpoint and exact base hash. Implementation
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
CI checkpoints.

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
the A-016 lease description. Independent corrected-DRAFT re-review remains
required before status can advance to READY.

## READY Gate

No executable provider code may replace the comment scaffolds until the shared
OperationID foundation is verified and independent corrected-DRAFT review audits
the exact dossier, authority, touched paths, hashes, test matrix, collision
boundary, and non-advancement clauses and returns GO with no P0–P3 finding. Only
then may the records say READY. That exact READY commit must pass every immutable
workflow job. Passing READY does not authorize
hosted resources, production access, source-backend changes, migration, release,
or cutover.
