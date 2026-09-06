# EVID-ITEM-SPACE-ASSIGNMENT-USE-CASE-001 — Item Space Assignment Use Case

- Timestamp: 2026-09-03
- Class: verified implementation / provider-free local-destination validation and
  typed Item assignment dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; source worktree and released Firebase app unchanged
- Exact READY commit:
  `d51ea1d338110d73a6c76ef3ffcf21f0b9113f99`; immutable Actions run
  `33827181145` passed
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
- Exact implementation commit:
  `04331950dc9fe4dea32493e11a9c367530e3baea`; immutable Actions run
  `33828908233` passed traceability in 11 seconds and isolated target in
  6 minutes 32 seconds, including all 309 tests and both builds
- Verification state: `verified`; `ITEMSPACEUSE-TEST-001` through `-010` pass

## Selection and Authority

A read-only feature-specific authority audit selected the smallest application
boundary joining the verified Item-to-Space assignment operation and the
verified operation-specific Space destination directory. Canonical Space
authority requires stable Item and Space identity, one exact Project-or-
Business-Inventory scope, active same-scope destination evidence, exact Item
and Space revisions, atomic/idempotent application, and explicit ready/partial/
stale local truth. It also says cached rows support offline selection and
conflict detection but do not grant authorization, and absence from incomplete
local data cannot prove no destination exists. D-019/D-023 make Space placement
optional and independent from accounting state.

The exact command shape, canonical nonempty Item ordering, revision
preconditions, operation lifecycle, receipt validation and 16 operation
failures remain owned by the verified assignment operation. Exact directory
request, active row, stable ID, revision and readiness/completeness semantics
remain owned by the verified destination read. This implementation composes
those authorities without recreating or extending either one.

O-037, O-023, O-007 and O-015 do not block this narrow dispatch boundary
because Space archive, media/marker retention, accounting/provenance and
physical authoritative apply remain excluded and unadvanced.

## Implemented Contract

Exactly two target leaves changed after the READY gate:

- `LedgeriOS/LedgerTargetCore/ItemSpaceAssignmentUseCase.swift`;
- `LedgeriOS/LedgerTargetCoreTests/ItemSpaceAssignmentUseCaseTests.swift`.

`ItemSpaceAssignmentIntent` is public, transient and non-Codable, with exactly
`accountId`, `scope`, `destinationSpaceId` and typed
`ItemSpaceAssignmentCandidate` values. It carries no copied Space revision,
name, route, backend path, media/marker or accounting value.

`ItemSpaceAssignmentUseCase<A: ItemSpaceAssigning>` receives that intent, the
current validated `SpaceAssignmentDestinationDirectorySnapshot`, and exact
Operation, Principal, contract-version and finite capture-time values. It
validates that the directory request matches the intent Account/scope, resolves
only the exact stable destination ID, and derives `ExpectedSpaceRevision` from
that row. A represented row is admissible at ready, partial or stale quality in
both Project and Business Inventory scope. An absent row returns
`destinationNotRepresented` for every completeness/quality shape; the failure
describes only the supplied evidence and does not assert the Space is
authoritatively nonexistent.

After evidence validation, the use case constructs
`ItemSpaceAssignmentDraft` and `AssignItemsToSpaceCommand` before invoking
`ItemSpaceAssigning.assignItemsToSpace` exactly once. Receipt validation remains
outside the port-error catch. The three application failures arise before the
port and remain exact. All 16 operation failures thrown by the port and
`CancellationError` remain exact. Every other port error—including an
impossible port-originated `ItemSpaceAssignmentUseCaseFailure`—maps to
`ItemSpaceAssignmentFailure.localAcceptanceFailed`.

## Verified Artifacts

The exact verified implementation hashes are:

- `ItemSpaceAssignmentUseCase.swift` —
  `e8425a84155c07b6ab860a23cf298246b0ab43a45a55fcf931523300e9db24a9`;
- `ItemSpaceAssignmentUseCaseTests.swift` —
  `1c8f9e557cf6f8c059d1040fc7eb7054854c8c8ba4d11457681a4399908106b9`.

The exact READY commit
`d51ea1d338110d73a6c76ef3ffcf21f0b9113f99` passed immutable Actions run
`33827181145` before executable implementation began. Exact implementation
commit `04331950dc9fe4dea32493e11a9c367530e3baea` then passed immutable Actions
run `33828908233` with all steps green.

## Local Verification

Seven focused tests in one suite pass and prove `ITEMSPACEUSE-TEST-001` through
`ITEMSPACEUSE-TEST-008`:

1. ordinary non-`@testable` construction, exact four-field shape,
   Equatable/Sendable and runtime non-Codable intent;
2. all six Project/Business-Inventory × ready/partial/stale represented-row
   combinations, directory-derived boundary Space revisions, boundary Item
   revisions and canonical Item input order;
3. directory Account/scope mismatch, every missing-row completeness/quality
   shape, empty/duplicate Items and all nonfinite times making zero calls;
4. every `LocalOperationState`, exact receipt and one-call mismatch boundary;
5. literal reciprocal encoded-leaf ownership across Account, scope, Space,
   directory revision, each Item/revision, Operation, actor, contract and time,
   without reconstructing expectations through production validation;
6. three pre-port application failures, all 16 operation failures, structured
   cancellation, bounded arbitrary errors and bounded impossible lower-layer
   application failures;
7. exact stable privacy-safe diagnostics, command topology and permanent
   exclusions.

Exact READY CI plus primary and independent corrected-diff reviews prove
`ITEMSPACEUSE-TEST-009`: the two-leaf implementation allowlist and unchanged
dependency, source app, MCP and provider surfaces.

The complete local gate passes all 309 tests in 64 suites with warnings as
errors. Conversion sync/check/report, capability/query/residual controls, M0,
target isolation/contracts, JSON parsing and clean diff formatting pass. The
root review confirms only the two allowlisted Swift leaves changed relative to
the exact READY commit.

`ITEMSPACEUSE-TEST-010` passes: exact implementation commit
`04331950dc9fe4dea32493e11a9c367530e3baea` passed immutable traceability in
11 seconds and isolated-target CI in 6 minutes 32 seconds. The isolated target
job passed all 309 tests and both staging builds, so the dossier and both target
surfaces are `verified`.

## Review Findings and Corrections

Primary and independent actual-diff review found two material proof/boundary
issues before this local implementation checkpoint:

1. The first implementation preserved a port-originated
   `ItemSpaceAssignmentUseCaseFailure`, which leaked an application-layer
   selection type from an impossible lower-layer path. The catch boundary now
   preserves only `ItemSpaceAssignmentFailure` and cancellation; every other
   port error maps to `localAcceptanceFailed`. An adversarial test deliberately
   throws the application failure from the port and proves it is bounded.
2. Initial positive coverage did not exercise every scope/quality combination.
   The corrected suite covers all six Project/Business-Inventory × ready/
   partial/stale represented-row paths and proves each row supplies the exact
   expected Space revision.

Root and independent reviewers re-reviewed the corrected implementation and
returned GO with no remaining P0-P3 finding.

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
