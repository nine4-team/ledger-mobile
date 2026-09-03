# EVID-DIRECT-SPACE-CREATION-USE-CASE-001 — Direct Space Creation Use Case

- Timestamp: 2026-09-03
- Class: implementation / local integration evidence for provider-free direct Space creation presentation-to-application path
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed conversion surfaces: `SWIFT-3615734A053E`, `TEST-EBA9C48BC4EE`, `SWIFT-517FA18158D9`, `TEST-915EC8E0BFC9`
- Slice dossier: `conversion/implementation-slices/direct-space-creation-use-case-contracts.json`
- Verification state: verified at exact implementation commit
  `c35f1cefc88d964035976d537c2f829b4db62a8a` in immutable Actions run
  `33746648677`

## Selection and Authority

A read-only scout ranked direct Space creation ahead of details editing and
rejected the complete Set/Clear picker because selected-Item/current-placement
evidence and archive/no-op behavior are not settled. The canonical Space spec
defines the direct-create outcome completely: one stable Project-or-Business-
Inventory identity/scope, canonical required name, optional notes, duplicate-
name validity and no checklist/template/media/Item/review/accounting side effect.

The verified `SpaceCreationOperation` owns canonical values, operation identity,
command construction, receipt validation and the `SpaceCreating` port. Current
`SpaceFormValidation` and its tests prove only the shipped required-name rule;
their target responsibility now converges on the canonical `SpaceDisplayName`
validator and focused target tests. The current source files remain unchanged.

The shipped `NewSpaceView` remains current evidence for the source route and its
template stub, not target authority for initial field values, cancellation,
identity generation, service invocation or error presentation.

## Independent Rejection and Correction

Independent preflight rejected the first ready draft. It incorrectly let a
presentation object add actor/Operation/contract/time and build a command,
froze initially blank fields and cancellation from current behavior without
canonical target authority, added two unnecessary unkeyed fingerprints, called
in-memory serialization offline restart, left the two original validation
surfaces unconverted, overextended O-026 from template administration to apply,
and claimed a product outcome while excluding operation invocation.

The corrected boundary removes every one of those choices. Raw initial values
are caller-supplied transient state; no form codec or fingerprint exists.
Presentation emits typed intent only. A separately named application use case
adds operation metadata, invokes the existing port, validates the receipt and
propagates failure. O-026 is mentioned only as outside authority for shared
template administration/save. This is a real provider-free application path,
not a claim that physical offline durability or UI wiring already exists.

## Frozen Boundary

Exactly two target leaves may be implemented:

- `LedgeriOS/LedgerTargetCore/DirectSpaceCreationUseCase.swift`; and
- `LedgeriOS/LedgerTargetCoreTests/DirectSpaceCreationUseCaseTests.swift`.

`SpaceCreationFormInput` carries typed Account/Space/scope plus caller-supplied
raw name and notes. Immutable raw-field replacement preserves the other values.
`validatedIntent` alone reuses `SpaceDisplayName` and `SpaceCreationNotes` and
returns `DirectSpaceCreationIntent`; there is no second validation algorithm,
automatic blank/default policy, directory query, uniqueness rule, operation
metadata or authorization claim.

`DirectSpaceCreationUseCase` receives raw `SpaceCreationFormInput`, OperationID,
actor, operation contract version and finite capture time. It reuses
`validatedIntent`, then constructs the verified `SpaceCreationDraft` and
`CreateSpaceCommand`, invokes one injected `SpaceCreating` port call only after
validation, validates the returned receipt and returns it with its exact local
state unchanged. Form, domain, command-construction and receipt-mismatch
failures return no receipt. An already-normalized `SpaceCreationFailure` from
the port is preserved, while any unexpected raw transport error is mapped to
`SpaceCreationFailure.localAcceptanceFailed`; infrastructure/provider errors
are outside this slice and may not cross the application boundary raw. A
deterministic in-memory port is test evidence only.

`CancellationError` remains Swift structured-concurrency control flow under
the architecture's port rule; it is not normalized as a transport failure.
This does not choose the separate form-cancel UI behavior that the first draft
incorrectly copied from current presentation behavior.

The two current Firebase-app validation surfaces are conversion responsibilities
claimed by this slice, but remain untouched. Their target replacement is the
canonical domain conversion and tests in the two target leaves. The broader
`NewSpaceView` stays target-mapped because template UI, app composition and
production submission are not converted here.

## Required Verification

Tests must prove caller-supplied raw-state preservation and immutable field
replacement; canonical name/notes conversion with blank-name refusal; Project
and Inventory identity/scope; duplicate names under distinct IDs; exact
operation-field/zero-precondition forwarding; exactly one port call; receipt
validation with exact local-state preservation; validation and normalized/
unexpected-port failure behavior; stable bounded diagnostics; absence of
unrelated/accounting fields; and no Firebase/provider imports.

The ready and implementation checkpoints must also pass conversion/capability/
query/residual/M0 controls, target isolation and generated contracts, focused
and complete tests, warnings-as-errors, repeatable project generation, both
staging builds, clean artifacts, exact implementation path scope and immutable
CI.

The corrected ready package passes the complete local gate: conversion,
capability, query, residual and M0 controls; target isolation and generated
contracts; all 243 target tests in 54 suites with warnings as errors; repeatable
XcodeGen project/scheme hashes `0657194a` / `388303af`; macOS and generic iOS
Simulator staging builds; valid JSON and clean diff formatting. The manifest
contains 815 recorded / 800 discovered surfaces with zero errors and only the
three established retired-path warnings; 388 target-relevant surfaces are
mapped or later and 167 remain tied to 44 explicit blockers. This local result
does not satisfy the immutable CI obligation. Two independent corrected-diff
reviews subsequently returned GO with no remaining P0-P3 finding after the
package split D-023 accounting independence into its own requirement, required
unexpected port-error normalization and exact receipt local-state preservation,
corrected continuity counts/state, and clarified raw-form/application ownership.

Exact ready commit `b8869ac2a0b3cfc48c4c197cc39baa8ceec60cfe`
passed immutable Actions run `33744781549` (conversion traceability 16 seconds;
isolated target 3 minutes 7 seconds).

## Implementation Review and Local Gate

Implementation changes exactly the two frozen target leaves. The first green
candidate passed its focused tests, but independent review found nonreciprocal
caller-field assertions, normalized-failure evidence identical to the fallback
result, cross-scope duplicate-name evidence, and missing exact empty/nil/long
raw-value cases. The reviewers initially disagreed about `CancellationError`:
one treated passthrough as outside the ready boundary, while the other identified
normalization as violating architecture rule 7. The final authority adjudication
preserves Swift structured-concurrency cancellation and keeps rule 8 transport-
error normalization separate.

The correction keeps form-cancel UX outside the slice while preserving
structured-concurrency `CancellationError`; asserts every caller-owned and
derived command field reciprocally; proves a distinct normalized failure is
preserved; proves equal canonical names for distinct Space IDs within the same
Project scope; and covers exact empty, nil, whitespace-only, padded, interior-
whitespace and long accepted name/notes input without inventing a cap. Both
independent final reviews return GO with no remaining P0-P3 finding.

The complete local integration gate passes conversion, capability, query,
residual and M0 controls; target isolation and generated contracts; six focused
and all 249 tests in 55 suites; warnings-as-errors; repeatable XcodeGen project/
scheme hashes `0657194a` / `388303af`; macOS and generic iOS Simulator staging
builds; valid JSON and clean formatting. Implemented leaf hashes are:

- `DirectSpaceCreationUseCase.swift` — `3c1583999b27d6a325434ba8a5036dbb5f7e465c059da61bf57ab1cf1f9610ea`; and
- `DirectSpaceCreationUseCaseTests.swift` — `1ee444d5e3c026efa1b35a903e9e11243fd26df295b6faf29c9424e64d1c6588`.

Exact implementation commit `c35f1cefc88d964035976d537c2f829b4db62a8a`
passed immutable Actions run `33746648677`: conversion state and traceability
passed in 10 seconds, and the isolated target environment passed all tests,
generated contracts, macOS/iOS staging builds and clean-artifact checks in 2
minutes 58 seconds. The slice, both target leaves and both converted current
validation responsibilities are verified.

Promotion commit `880727f74355699e10466e68d29e1265d5f95fe1`
passed immutable Actions run `33747118216` (traceability 7 seconds; isolated
target 2 minutes 39 seconds), confirming the synchronized verified state and
clean tracked artifacts.

## Permanent Exclusions

This evidence does not authorize SwiftUI layout/copy/navigation, physical form
or operation persistence, an optimistic/authoritative Space row, membership or
Project-parent create authorization, Postgres, Data API, RLS, PowerSync,
provider composition, MCP, templates, checklists, attachments/media, Items,
archive, review, completion, accounting, migration, hosted resources,
production access, release or cutover. O-023/O-026/O-037 and
A-003/A-004/A-007/A-015/A-016 remain open or outside this boundary. Product
specs and confirmed decisions, not this evidence file, remain product authority.
