# EVID-PROJECT-DETAILS-UPDATE-USE-CASE-001 — Project Details Update Use Case

- Timestamp: 2026-09-03
- Class: READY / provider-free Project-description form-to-application dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; source worktree and released Firebase app unchanged
- Prior verified conversion baseline: exact commit `0a8cc53a909951c31fc8be6377e2e5f62b93e87c`; immutable Actions run `33794464360` passed both jobs
- Claimed target surfaces: `SWIFT-B95AD78B8CEC`, `TEST-315066B94566`
- Preserved source surfaces: `SWIFT-CF459111B7BB`, `SWIFT-E1A771F6A409`, `SWIFT-27CA6EAC7092`, `SWIFT-7500FDB4FDB6`, `MCPTOOL-A9FCDED31D3F` retain their prior statuses
- Verified dependency: `SWIFT-1A34CF88E95E`, `TEST-22878D176671` at exact implementation `a532ac9d`; immutable run `33642777864`
- Slice dossier: `conversion/implementation-slices/project-details-update-use-case-contracts.json`
- Verification state: local READY gate and independent corrected-diff review pass; implementation is not authorized until exact READY CI passes

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

Exactly two comment-only target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ProjectDetailsUpdateUseCase.swift`;
- `LedgeriOS/LedgerTargetCoreTests/ProjectDetailsUpdateUseCaseTests.swift`.

The future `ProjectDetailsUpdateFormInput` is a transient, non-Codable value
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

Ten planned obligations freeze executable proof for:

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

The exact current scaffold hashes are:

- `ProjectDetailsUpdateUseCase.swift` — `7bd32006b76076256f58be5d73cafd7d2c2e223d63d1b8c4ed1c8db7f39b4745`;
- `ProjectDetailsUpdateUseCaseTests.swift` — `590fd99a4f0c745be3cc614fab6c732bc093db807a55d024c4072eab32eb547b`.

The prior verified baseline is exact commit
`0a8cc53a909951c31fc8be6377e2e5f62b93e87c`; immutable Actions run
`33794464360` passed traceability and isolated-target jobs.

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
and records the completed gate here. Both corrected-diff reviewers return GO
with no remaining P0-P3 finding. Immutable exact-READY-SHA CI is the sole remaining
authorization gate before either leaf may contain executable code.

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
