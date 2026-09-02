# EVID-SPACE-ASSIGNMENT-DESTINATION-001 — Space Assignment-Destination Read Contracts

- Timestamp: 2026-09-02
- Class: ready gate / provider-free eligible Space destination directory
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-164554FA1456`, `TEST-A3D73145E3EC`
- Slice dossier:
  `conversion/implementation-slices/space-assignment-destination-read-contracts.json`
- Verification state: complete local ready gate passes; exact ready-commit CI
  pending
- Ready scaffold hashes:
  - `SpaceAssignmentDestinationData.swift`:
    `00a2fcca41b9b42c8b6ae6f7f08b4ebbaea73458158a6b5077ed8953ea0344de`
  - `SpaceAssignmentDestinationDataTests.swift`:
    `624e573e5cc5a9f08c06fb1debdbdc9e6143d126025631fcfba877723c949ad5`

## Selection and Scope

The next-slice audit evaluated the remaining unclaimed target responsibilities
after Item Space assignment and clearing were verified. Full Space detail is not
decision-independent because it combines archive effects, review state and
attachment lifecycle under O-037/O-032/O-023. The assignment destination
directory is independently complete: it answers only which active Spaces may be
selected for one exact Project or Business Inventory scope while offline.

This boundary is required by the verified `AssignItemsToSpace` command. It is
also a direct correction to the current app's caller-supplied arrays: some
screens pass Project- or Inventory-filtered Spaces, while universal search and
other shared flows can pass the Account-wide `allSpaces` listener result into
the same picker. The current picker then filters only `isArchived` and sorts by
display name; it does not own exact scope, revision, completeness or
authorization evidence.

## Product and Source Cross-Reference

The audit cross-referenced:

- `docs/specs/spaces.md` for exact Project/Business-Inventory placement scope,
  active destination eligibility, duplicate-name identity and offline picker
  readiness;
- the reviewed Spaces dossier for duplicate listener graphs, AccountContext/
  route authority defects and the target `SpaceAssignmentDestinationQuerying`
  boundary;
- the verified Item Space assignment and clearing dossiers for exact typed
  scope/revision preconditions and non-accounting behavior;
- `03-data-sync-and-offline.md` and `04-backend-ports-and-adapters.md` for local
  read authority, explicit completeness, scoped streams and narrow ports; and
- current `SpacesService`, `AccountContext`, `ProjectContext`,
  `InventoryContext`, `SetSpaceModal`, `SpacePickerList`, Item detail/create/
  bulk screens and universal search as source behavior evidence.

The target does not preserve Firestore listeners, nullable `projectId` checks,
caller filtering, route authority, provider callbacks, locale-dependent
unstable ties or silent absence from incomplete data.

## Why Open Decisions Do Not Block This Slice

- O-037 controls what archiving a Space does to assigned Items. The directory
  lists only currently active destinations and cannot archive, resolve, hide or
  clear an existing archived assignment.
- O-023 controls attachment reference and byte deletion. Destination rows carry
  no attachment identity, URL, marker, byte or deletion instruction.
- O-032 controls posting/review readiness. Destination eligibility depends only
  on active Space lifecycle and exact scope; no review or accounting state is
  carried.
- A-003/A-004/A-007/A-016 and hosted staging remain proposed/gated. Local rows
  are offline selection and conflict evidence, never current authorization.

## Ready-Gate Contract

The dossier freezes eight requirements and five verification obligations. It
requires one exact Account/scope request; active stable Space ID, normalized
name and revision rows; valid duplicate names; deterministic case-insensitive
name/exact-name/ID ordering; exact visible-count and scope validation; explicit
ready/authoritative-empty/partial/stale/failure truth; byte-identical restart;
stable bounded refusal; and one narrow provider-free query port.

Postgres, handlers, grants, RLS, Sync Streams, Auth, physical local persistence,
assignment mutation, full Space detail/archive/review/media state, app/MCP,
migration, observability, hosted resources and feature activation are explicit
nonapplicabilities.

## Dependency Evidence

The verified Item-to-Space assignment operation's exact implementation commit
`c5fdf5c73763b5a629ff0416bebba92696af6581` passed immutable Actions run
`33672006836`. The verified clear-assignment implementation commit
`f5a7ac7598f77859239b66666bc703ee4639c233` passed immutable run `33677087616`
with all 180 target tests in 42 suites, both staging builds and clean artifacts.

The clear-assignment verification-document commit
`2fd9ccaa183d7a840aa578192c7da3bf2b40c0db` passed immutable Actions run
`33677528131`: conversion traceability passed in 9 seconds and the isolated
target environment passed in 3 minutes 21 seconds with all 180 then-existing
target tests, both builds and clean tracked artifacts.

Verified shared list-query presentation, exact identity, Space creation/details,
operation lifecycle and target-environment slices supply reusable scope, ID,
revision, local-readiness and isolation primitives. This slice neither
redefines them nor claims their physical adapters.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Spaces
batch and are `target_mapped`. The dossier has no blocker; every requirement is
reciprocally covered by domain, offline-restart, offline-rejection, exact-scope
port-flow and exact-commit operational obligations.

The complete local ready gate passes:

- conversion sync/check/report, capability/query/residual checks and M0;
- all 180 existing target tests in 42 suites;
- target environment/source-contamination and generated-contract checks;
- repeatable XcodeGen output with project hash
  `0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
  and scheme hash
  `388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`;
- macOS and generic iOS Simulator staging builds;
- clean diff formatting and no source `LedgeriOS.xcodeproj` change; and
- expected M1/M2 holds of exactly 2/164 coverage blockers with zero structural
  errors.

Executable behavior remains prohibited until the exact ready commit passes
both pull-request CI jobs.

## Permanent Limits

This ready evidence cannot verify or authorize destination-row persistence or
download, current membership, assignment or clearing, full Space list/detail,
archive effects, review state, attachment lifecycle, physical offline behavior,
Postgres/RLS/PowerSync, app/MCP integration, Firebase migration, hosted
resources, production access, release or cutover. The source Firebase
application remains unchanged.
