# EVID-SPACE-DETAILS-UPDATE-USE-CASE-001 — Space Details Update Use Case

- Timestamp: 2026-09-03
- Class: corrected ready design / provider-free Space-details save submission
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; source worktree and released Firebase app unchanged
- Claimed target surfaces: `SWIFT-306643A5CD0D`, `TEST-235F73A8DC9E`
- Partially mapped source evidence: `SWIFT-9F4789704808` remains `target_mapped`
- Slice dossier: `conversion/implementation-slices/space-details-update-use-case-contracts.json`
- Verification state: independent preflight, two corrected actual-ready-diff reviews and the complete local ready gate pass; immutable exact-ready-SHA CI pending

## Selection and Authority

A fresh post-verification scout ranked Space-details update submission ahead of
chosen-Project note capture and Project archive dispatch. Canonical Spaces
authority defines one complete name/optional-notes replacement for a stable
Space and expected revision. The verified `SpaceDetailsUpdateOperation` owns
canonical values, complete-replacement command construction, one revision
precondition, receipt validation and the narrow `SpaceDetailsUpdating` port.
The verified direct-create use case provides application-layer precedent for
raw validation, exact caller metadata, one call, bounded errors and cancellation.

## Preflight Correction

Independent preflight rejected the scout's initial source-closure description.
`EditSpaceDetailsModal.swift` is an entire SwiftUI surface: it owns initial
population, transient edits, immediate error display, save normalization and
callback, success/cancel dismissal, layout and copy. A provider-free application
use case can replace only its save-intent normalization/dispatch responsibility.
The source surface therefore remains `target_mapped`; later UI composition must
replace the generic callback and Firebase service before it can be verified.

Preflight also rejected consuming `SpaceCoreDetailsUpdate` or choosing whether
waiting, partial, stale, cached-failure, active or archived evidence may submit.
Future composition supplies exact AccountID, SpaceID and ExpectedSpaceRevision.
Readiness, lifecycle, initial-population and dirty/no-op policy stay outside.

The current modal disables Save using `.whitespaces` only, but later normalizes
with `.whitespacesAndNewlines`; newline-only input can therefore reach its
callback as an empty name. Canonical `SpaceDisplayName` validation intentionally
corrects this shipped defect rather than preserving it.

## Frozen Boundary

Exactly two comment-only target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/SpaceDetailsUpdateUseCase.swift`; and
- `LedgeriOS/LedgerTargetCoreTests/SpaceDetailsUpdateUseCaseTests.swift`.

`SpaceDetailsUpdateFormInput` will be non-Codable transient state carrying exact
AccountID, SpaceID, ExpectedSpaceRevision and caller raw name/optional notes.
Immutable replacement changes one raw field only. `validatedIntent` reuses
`SpaceDisplayName` and `SpaceCreationNotes`; it invents no validator, default,
length cap, uniqueness query, readiness/lifecycle field, fingerprint, restart
contract or no-op policy.

`SpaceDetailsUpdateUseCase` receives raw input plus caller OperationID,
PrincipalID, operation contract version and finite capture time. It revalidates,
constructs the existing `SpaceDetailsUpdateDraft` and
`UpdateSpaceDetailsCommand`, invokes `SpaceDetailsUpdating` exactly once only
after successful validation/construction, validates the matching receipt and
returns every local state unchanged. Swift `CancellationError` remains
structured-concurrency control flow. Existing normalized `SpaceCreationFailure`
and `SpaceDetailsUpdateFailure` values remain stable; unexpected transport
errors map to `SpaceDetailsUpdateFailure.localAcceptanceFailed`.

## Required Verification

Focused tests must independently prove raw empty/nil/whitespace/padded/interior-
whitespace/long boundaries; empty/spaces/newline name refusal; notes-to-nil;
immutable replacement; duplicate-name validity without a directory; revision
zero and UInt64.max; reciprocal exact forwarding of every input/operation field;
one complete payload and same-Space revision precondition; validation-before-
call and exactly-one-call; every receipt state; mismatch; distinct normalized
failures; raw transport normalization; Swift cancellation; stable diagnostics;
and absence of unrelated/readiness/lifecycle/accounting/provider fields.

The ready and implementation checkpoints must also pass conversion/capability/
query/residual/M0 controls, target isolation and generated contracts, focused
and complete warnings-as-errors tests, repeatable project generation, macOS and
generic iOS Simulator staging builds, JSON/formatting checks, exact path scope
and immutable CI.

## Ready Review and Local Gate

Two independent read-only reviewers examined the actual ready diff. They first
blocked it for five contract overclaims and one control-plane gap: diagnostics
privacy had been conflated with command encoding, absence of accounting fields
had been overstated as proof of no physical effects, no-op policy had been
decided without base values, source-status authority was misassigned, source
metadata exclusions were too broad, and the correct status authority was not in
the batch crosswalk. The corrected package separates those claims and registers
`target-mapping-method.md` only as conversion-control authority. Both reviewers
then returned GO with no remaining P0-P3 finding.

The current ready package passes conversion sync/check, capability/query/
residual checks, M0, target isolation and generated-contract controls, all 249
target tests in 55 suites, warnings-as-errors, repeatable project generation,
macOS and generic iOS Simulator staging builds, JSON validation and clean diff
formatting. The two new target leaves are comment-only at this checkpoint, so no
new executable focused test exists until implementation. Exact-ready-SHA CI is
the sole remaining gate before code may replace the scaffolds.

## Permanent Exclusions

This evidence does not authorize initial form population, raw draft restart,
physical persistence, dirty/no-op policy, immediate error presentation, success
or cancel dismissal, SwiftUI layout/copy/navigation, current-read admission,
active/archive eligibility, Space scope/lifecycle/checklists/templates/Items/
review/media/accounting, membership or update authorization, Postgres, Data API,
RLS, PowerSync, provider composition, MCP, migration, hosted resources,
production access, release or cutover. O-023/O-026/O-037 and A-003/A-004/A-007/
A-015/A-016 remain open or outside. D-023 contributes only the invariant that
Space detail changes carry no accounting state. Product specs and confirmed
decisions remain authority.
