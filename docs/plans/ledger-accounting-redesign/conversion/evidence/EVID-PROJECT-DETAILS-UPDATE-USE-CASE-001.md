# EVID-PROJECT-DETAILS-UPDATE-USE-CASE-001 — Project Details Update Use Case

- Timestamp: 2026-09-03
- Class: verification / provider-free Project-description form-to-application dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; source worktree and released Firebase app unchanged
- Prior verified conversion baseline: exact commit `0a8cc53a909951c31fc8be6377e2e5f62b93e87c`; immutable Actions run `33794464360` passed both jobs
- Ready baseline: exact commit `22c6cc01d499ce024e1a4c4157bc3c5e5d5a680e`; immutable Actions run `33797480692` passed both jobs
- Claimed target surfaces: `SWIFT-B95AD78B8CEC`, `TEST-315066B94566`
- Preserved source surfaces: `SWIFT-CF459111B7BB`, `SWIFT-E1A771F6A409`, `SWIFT-27CA6EAC7092`, `SWIFT-7500FDB4FDB6`, `MCPTOOL-A9FCDED31D3F` retain their prior statuses
- Verified dependency: `SWIFT-1A34CF88E95E`, `TEST-22878D176671` at exact implementation `a532ac9d`; immutable run `33642777864`
- Slice dossier: `conversion/implementation-slices/project-details-update-use-case-contracts.json`
- Verification state: verified at exact implementation commit `55baae9d47a40b14bd05418ca2bbf9cc2c11d480`; immutable Actions run `33799751617` passed both jobs

## Selection and Authority

Root independently confirmed the canonical Projects target requirement and two
read-only preflights selected this description-only application boundary above
the existing verified Project details update operation. The candidate IDs were
independently derived from the canonical new paths; neither path nor ID existed
at the prior verified baseline.

The Projects spec makes optional-description set/clear a distinct
`UpdateProjectDetails` intent. It trims outer whitespace, treats
whitespace-only input as clear and expressly cannot rename or reassign the
Project or change categories, media, lifecycle, children or accounting history.
That later canonical requirement—not older broad Edit Project behavior—governs
this slice.

O-023/O-024/O-025/O-026 do not block the narrow boundary because it implements
no media retention, Project lifecycle/delete, Client/Project correction or
reference mutation. Those decisions remain open and unadvanced.

## Frozen Boundary

Exactly two target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ProjectDetailsUpdateUseCase.swift`;
- `LedgeriOS/LedgerTargetCoreTests/ProjectDetailsUpdateUseCaseTests.swift`.

`ProjectDetailsUpdateFormInput` is a transient, non-Codable value
with exactly `accountId`, `projectId`, `expectedRevision` and `rawDescription`,
plus an exact public four-argument initializer so an ordinary non-`@testable`
module consumer can construct it.
The use case receives that input plus caller-supplied Operation, Principal,
contract-version and finite capture-time values. It constructs the existing
canonical `ProjectDescriptionReplacement`, `ProjectDetailsUpdateDraft` and
`UpdateProjectDetailsCommand` before invoking
`ProjectDetailsUpdating.updateDetails` exactly once, validates the receipt
outside the port catch and returns that exact receipt and local state.

The application error boundary preserves `CancellationError` and each of the
13 `ProjectDetailsUpdateFailure` cases. Only an unknown error thrown by the port
maps to `localAcceptanceFailed`; construction and receipt-validation failures
cannot be silently reclassified.

The use case owns no initial/current Project read, readiness or lifecycle
admission, dirty/no-op policy, dismissal/error UX, multi-command sequencing or
atomicity, rename, Client/category/allocation/budget/media/child/history/
accounting mutation, persistence, authorization or service implementation.

## Required Verification

Ten obligations freeze executable proof for:

1. a non-`@testable` consumer constructing the exact four-field public initializer, Equatable/Sendable and runtime non-Codable input shape, including exact raw String bytes before canonical construction;
2. nil/empty/whitespace clearing, outer trimming, interior Unicode preservation and more than 8 KiB of UTF-8 text through the actual command without an invented cap;
3. exact zero and maximum revisions plus all six receipt states and one-call dispatch;
4. reciprocal encoded-leaf ownership across every caller input and normalization-equivalent command/fingerprint identity;
5. both nonfinite times at zero calls and receipt mismatch after one call;
6. all 13 typed port failures, structured cancellation and bounded unknown errors;
7. exact stable diagnostic enumeration and privacy;
8. exact nested command topology with every broader edit/service field excluded;
9. exact READY/implementation allowlists and preserved source statuses; and
10. separate immutable READY and implementation CI before verification promotion.

## Comment-Only READY Artifacts

The exact READY scaffold hashes were:

- `ProjectDetailsUpdateUseCase.swift` — `7bd32006b76076256f58be5d73cafd7d2c2e223d63d1b8c4ed1c8db7f39b4745`;
- `ProjectDetailsUpdateUseCaseTests.swift` — `590fd99a4f0c745be3cc614fab6c732bc093db807a55d024c4072eab32eb547b`.

Exact READY commit `22c6cc01d499ce024e1a4c4157bc3c5e5d5a680e`
passed immutable Actions run `33797480692`: traceability completed in 8 seconds
and the isolated target job completed in 3 minutes 36 seconds with all tests,
both staging builds and clean generated artifacts.

## Local READY Gate and Review

The corrected comment-only package passes:

- `conversion:sync` and `conversion:check`: 827 recorded / 812 discovered,
  zero errors and only the three established retired-path warnings;
- capability/query checks, regenerated residual controls at 393 mapped / 174
  residual / 45 blockers, M0, target isolation and generated target contracts;
- all 279 existing target tests in 60 suites with Swift warnings as errors;
- repeatable project generation with unchanged project/scheme hashes
  `0657194a` / `388303af`;
- macOS and generic iOS Simulator staging builds; and
- complete JSON parsing plus clean diff formatting.

The first verification review caught a P1 public-access hole: the frozen form
input had no explicit public initializer and `@testable` tests could have hidden
that defect. The correction freezes an exact public four-argument initializer
and requires ordinary non-`@testable` consumer compilation. The authority
review caught a P2 lifecycle overstatement (`in_progress` for comment-only
READY) and a P3 stale local-gate claim. The package now uses `ready` throughout
and records the completed gate here. Both corrected-diff reviewers returned GO
with no remaining P0-P3 finding before exact READY CI passed.

## Implementation Candidate and Local Gate

Implementation changes exactly the two frozen target leaves. The production
leaf exposes the exact public non-Codable four-field input and constructs
`ProjectDescriptionReplacement`, `ProjectDetailsUpdateDraft` and
`UpdateProjectDetailsCommand` before one `ProjectDetailsUpdating.updateDetails`
call. It preserves every typed failure and `CancellationError`, bounds only
unknown port errors, and validates and returns the exact receipt outside the
catch.

Seven focused tests use ordinary `import LedgerTargetCore`. Those tests plus
review evidence satisfy `PDETAILUSE-TEST-001` through `PDETAILUSE-TEST-009`;
immutable exact-implementation-SHA CI satisfies `PDETAILUSE-TEST-010`.
Initial independent review found one P2
false-green path: revision zero stopped at the form input. The correction
dispatches revision zero through the real use case and proves the exact draft,
same-subject precondition and three-leaf encoded delta. Both final
corrected-diff reviewers returned GO with no remaining P0-P3 finding.

The corrected implementation passes seven focused tests and all 286 target
tests in 61 suites with warnings as errors; target isolation/contracts;
repeatable project generation at `0657194a` / `388303af`; both staging builds;
and clean formatting. Implementation hashes are:

- `ProjectDetailsUpdateUseCase.swift` — `cf27b0177ffcb3933e599e3b8f8d167da6de819c399d254dc1f700d2446d7a50`;
- `ProjectDetailsUpdateUseCaseTests.swift` — `1961c7c450ffa0503fd6b88fcbaf8d4d8ffba69061950933e71b9c0ea3807fae`.

Conversion synchronization and complete control checks passed after the hash
update in this checkpoint. Exact implementation commit
`55baae9d47a40b14bd05418ca2bbf9cc2c11d480` passed immutable Actions run
`33799751617` (traceability 15 seconds; isolated target 2 minutes 38 seconds),
including all target tests, both staging builds and clean tracked artifacts.
The dossier and both target surfaces are verified.

## Permanent Exclusions

This evidence does not authorize initial/current Project reads, readiness,
lifecycle eligibility, dirty/no-op or dismissal/error UX, Project rename,
Client reassignment, category/allocation/budget/media/child/history/accounting
mutation, multi-command sequencing, physical local durability, optimistic
projection, retry/rejection behavior, trusted authorization/audit/apply,
Postgres, Data API, RLS, PowerSync, provider/Auth, SwiftUI or app composition,
MCP wiring, Firebase decoding or migration, hosted resources, production
access, release or cutover. O-022/O-023/O-024/O-025/O-026 and
A-003/A-004/A-007/A-015/A-016 remain open or outside.
