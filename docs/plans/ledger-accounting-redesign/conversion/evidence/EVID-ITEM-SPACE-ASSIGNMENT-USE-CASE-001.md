# EVID-ITEM-SPACE-ASSIGNMENT-USE-CASE-001 — Item Space Assignment Use Case

- Timestamp: 2026-09-03
- Class: READY / provider-free local-destination validation and typed Item
  assignment dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; source worktree and released Firebase app unchanged
- Prior verified conversion baseline: exact O-040 remediation commit
  `471f61a004a92afa961aba41ea6544a90a391cda` passed immutable Actions run
  `33825756789`
- Claimed target surfaces: `SWIFT-0540BE125F5A`, `TEST-DA67EAC9C2EF`
- Preserved verified dependencies: `SWIFT-4B007A00C393`,
  `TEST-51D893DD949E` at exact implementation
  `c5fdf5c73763b5a629ff0416bebba92696af6581` / run `33672006836`;
  `SWIFT-164554FA1456`, `TEST-A3D73145E3EC` at exact checkpoint
  `b0ffef836cc82f6011b802a5cb5f6a6ade05680a` / run `33682239349`
- Preserved source surfaces: `SWIFT-5A16999D5F3A`,
  `SWIFT-4C8A8E236450`, `SWIFT-BDF8928A5FC7`, `SWIFT-DDFAC91775DA`,
  `SWIFT-CD04095425B1`, `SWIFT-D2EEB690D6AD` and `SWIFT-C593225376EB`
  remain `characterized`; `SWIFT-7F24BFB8649C` remains `target_mapped`
- Slice dossier:
  `conversion/implementation-slices/item-space-assignment-use-case-contracts.json`
- Verification state: comment-only READY prepared; implementation remains
  unauthorized until the reviewed exact READY commit passes immutable CI

## Selection and Authority

A read-only feature-specific authority audit selected the smallest application
boundary joining the verified Item-to-Space assignment operation and the
verified operation-specific Space destination directory. The proposed target
paths produce the predetermined IDs above and did not exist at the prior
checkpoint.

Canonical Space authority requires stable Item and Space identity, one exact
Project-or-Business-Inventory scope, active same-scope destination evidence,
exact Item and Space revisions, atomic/idempotent application, and explicit
ready/partial/stale local truth. It also says cached rows support offline
selection and conflict detection but do not grant authorization, and absence
from incomplete local data cannot prove no destination exists. D-019/D-023 make
Space placement optional and independent from accounting state.

The exact command shape, canonical nonempty Item ordering, revision
preconditions, operation lifecycle, receipt validation and 16 operation
failures come from the already-verified assignment operation. Exact directory
request, active row, stable ID, revision and readiness/completeness semantics
come from the already-verified destination read. This slice composes them; it
does not recreate or extend either authority.

O-037, O-023, O-007 and O-015 do not block this narrow dispatch boundary
because Space archive, media/marker retention, accounting/provenance and
physical authoritative apply remain excluded and unadvanced.

## Frozen Boundary

Exactly two comment-only target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ItemSpaceAssignmentUseCase.swift`;
- `LedgeriOS/LedgerTargetCoreTests/ItemSpaceAssignmentUseCaseTests.swift`.

The future public `ItemSpaceAssignmentIntent` is transient and non-Codable,
with exactly `accountId`, `scope`, `destinationSpaceId` and typed
`ItemSpaceAssignmentCandidate` values. It carries no copied Space revision,
name, route, backend path, media/marker or accounting value.

The future generic `ItemSpaceAssignmentUseCase<A: ItemSpaceAssigning>` receives
that intent, the current validated
`SpaceAssignmentDestinationDirectorySnapshot`, and exact Operation, Principal,
contract-version and finite capture-time values. It first validates that the
directory request matches the intent Account/scope, resolves only the exact
stable destination ID, and derives `ExpectedSpaceRevision` from that row. A
represented row is admissible at ready, partial or stale quality. An absent row
returns `destinationNotRepresented` for every completeness/quality shape; the
failure describes only the supplied evidence and does not assert the Space is
authoritatively nonexistent.

After evidence validation, the use case constructs
`ItemSpaceAssignmentDraft` and `AssignItemsToSpaceCommand` before invoking
`ItemSpaceAssigning.assignItemsToSpace` exactly once. Receipt validation remains
outside that catch boundary. The three application failures arise before the
port and remain exact. All 16 operation failures thrown by the port and
`CancellationError` remain exact; only an unknown port error maps to
`ItemSpaceAssignmentFailure.localAcceptanceFailed`.

## Required Verification

Ten planned obligations freeze proof for:

1. ordinary non-`@testable` public construction, exact four-field shape,
   Equatable/Sendable and runtime non-Codable intent;
2. exact represented ready/partial/stale Project and Business Inventory rows,
   directory-derived boundary Space revisions, boundary Item revisions and
   canonical Item input order;
3. directory Account/scope mismatch, every missing-row completeness/quality
   shape, empty/duplicate Items and all nonfinite times making zero calls;
4. every `LocalOperationState`, exact receipt and one-call mismatch boundary;
5. literal reciprocal encoded-leaf ownership across Account, scope, Space,
   directory revision, each Item/revision, Operation, actor, contract and time,
   without reconstructing expectations through production validation;
6. three application failures, 16 operation failures, structured cancellation
   and bounded unknown errors;
7. exact stable privacy-safe diagnostic enumerations;
8. exact transient-intent and nested command topology plus broader-field
   exclusions;
9. exact READY/implementation allowlists and preserved dependency/source
   statuses; and
10. separate immutable READY and implementation CI before verification
    promotion.

## Comment-Only READY Artifacts

The exact current scaffold hashes are:

- `ItemSpaceAssignmentUseCase.swift` —
  `9a99462ee952e78c8eb788fef3ea4e6f5eb09bb5ad61026f57cd3b8207f0084b`;
- `ItemSpaceAssignmentUseCaseTests.swift` —
  `8cc26f267f49f47588587a4af80f64638e59ed01a605719a636bd7db0d7a1ece`.

The prior clean conversion checkpoint is exact commit
`471f61a004a92afa961aba41ea6544a90a391cda`, proven by immutable run
`33825756789`. Local validation is recorded below. Independent actual-diff
review and an immutable exact-READY-SHA CI run remain required before either
scaffold may contain executable code.

## Local READY Gate

The local READY gate passes conversion sync/check/report at 833 recorded / 818
currently discovered surfaces with zero errors and the three established
retired-path warnings; capability/query checks; residual generation/check at
389 mapped / 184 residual / 46 blockers; M0; target isolation/contracts; JSON;
and clean diff formatting. The unchanged baseline suite passes all 302 tests in
63 suites with warnings as errors. Repeatable Xcode generation preserves exact
project/scheme hashes `0657194a` / `388303af`, and both staging builds pass.

This local result does not authorize implementation. Root review, independent
actual-diff review and an exact READY commit passing immutable CI
remain required before either scaffold may contain executable code.

## Permanent Exclusions

This evidence does not authorize assignment clearing or no-op policy; Item
selection UI/read models; Space archive effects; attachment/marker mutation or
retention; Item scope movement; accounting, occurrence or provenance mutation;
physical local persistence, optimistic placement/marker projection, retry or
rejection-recovery behavior; trusted authorization/audit/apply; Postgres, Data
API, RLS, PowerSync, provider/Auth; SwiftUI/app composition; MCP wiring; source
Item/Space decoding or migration; hosted resources; production access; release
or cutover. O-007/O-015/O-023/O-037 and
A-003/A-004/A-007/A-015/A-016 remain open or outside.
