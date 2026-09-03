# EVID-PROJECT-RENAME-USE-CASE-001 — Project Rename Use Case

- Timestamp: 2026-09-03
- Class: implementation candidate / provider-free typed Project-rename application dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; source worktree and released Firebase app unchanged
- Prior verified conversion baseline: exact commit `83581721f2337a81be07f98a19cd007d80e99e90`; Project-details implementation `55baae9d47a40b14bd05418ca2bbf9cc2c11d480` passed immutable Actions run `33799751617`
- Ready baseline: exact commit `dc7c9779efb4d176e507e0c683f2dffc4814110b`; immutable Actions run `33808493496` passed both jobs
- Claimed target surfaces: `SWIFT-5A812E7B8C95`, `TEST-E1BAA8DF70B4`
- Preserved verified dependencies: `SWIFT-797909434B82`, `TEST-3CE7B387E9B7` at exact implementation `7f395bbe` / run `33615145061`; `SWIFT-401EBD892749` at exact implementation `3c0b58b6` / run `33584456794`
- Preserved source surfaces: `SWIFT-CF459111B7BB` and `MCPTOOL-A9FCDED31D3F` remain `characterized` on O-025; `SWIFT-D73C92887393` remains `characterized` on O-024; `SWIFT-E1A771F6A409` and `SWIFT-27CA6EAC7092` remain `characterized` on O-024/O-025; `SWIFT-7500FDB4FDB6`, `SWIFT-038E6D4248AF`, `TEST-E591BE8A4B58` and `SWIFT-A9748507A27A` remain `target_mapped`
- Slice dossier: `conversion/implementation-slices/project-rename-use-case-contracts.json`
- Verification state: local implementation gate and two independent implementation reviews pass; exact implementation commit and CI remain pending

## Selection and Authority

Two independent read-only scouts selected the typed Project rename application
boundary above the verified Project rename operation and Client/Project display
value contracts. The candidate IDs were independently derived from the exact
new paths and did not exist at baseline.

The canonical Projects target separates `RenameProject` from Project details,
Client relationship, category, media, lifecycle and history changes. The exact
expected revision, already-validated `ProjectDisplayName` bytes, precondition,
command and failure semantics come from the verified Project rename operation
and display-value contracts, not from the product spec. This slice therefore
accepts the existing typed value; it does not accept a raw String or decide
trimming, blank-name, length, dirty/no-op, initial-value or other presentation
behavior. Current Edit Project UI and generic Firebase/MCP update mechanics are
source evidence, not target application authority.

O-024/O-025 do not block this narrow dispatch boundary because it performs no
lifecycle/delete/correction/reassignment policy and does not wire any app,
service, MCP or provider implementation. Those decisions remain unadvanced.

## Frozen Boundary

Exactly two target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ProjectRenameUseCase.swift`;
- `LedgeriOS/LedgerTargetCoreTests/ProjectRenameUseCaseTests.swift`.

The public `ProjectRenameIntent` is a transient, non-Codable value with
exactly `accountId`, `projectId`, `expectedRevision` and `newDisplayName`, where
the display name is the existing `ProjectDisplayName`. The generic
`ProjectRenameUseCase<R: ProjectRenaming>` receives that intent plus exact
Operation, Principal, contract-version and finite capture-time values. It
constructs `ProjectRenameDraft` and `RenameProjectCommand` before invoking
`ProjectRenaming.rename` exactly once, validates the receipt outside the catch,
and returns the exact receipt and local state.

The application error boundary preserves `CancellationError` and all 12
`ProjectRenameFailure` cases. Only an unknown error thrown by the port maps to
`localAcceptanceFailed`; construction and receipt-validation failures cannot be
silently reclassified.

The verified Project rename operation remains sole owner of accepted display-
name bytes, expected revision, same-Project precondition, draft, command,
subject, fingerprint, receipt validation and typed failure semantics. The use
case may compose those contracts but cannot reproduce or extend them.

## Required Verification

Ten obligations freeze proof for:

1. ordinary non-`@testable` public construction, exact four-field shape, Equatable/Sendable, runtime non-Codable intent, and zero/maximum revisions;
2. already-validated ProjectDisplayName bytes, including accepted whitespace and more than 8 KiB Unicode, reaching the command without second normalization;
3. zero/maximum revisions, all six receipt states and one-call dispatch;
4. reciprocal encoded-leaf ownership across Account, Project, revision, display name, Operation, actor, contract and time, using literal flattened baseline expectations and exact literal changed-leaf sets for all eight axes; recording/canned fakes and expected-value helpers may not reconstruct expectations with the production draft, command or validation logic;
5. both nonfinite times at zero calls and receipt mismatch after one call;
6. all 12 typed port failures, structured cancellation and bounded unknown errors;
7. exact stable privacy-safe diagnostic enumeration;
8. exact narrow nested command topology and broader-field exclusions;
9. exact READY/implementation allowlists plus preserved dependency/source statuses; and
10. separate immutable READY and implementation CI before verification promotion.

## Comment-Only READY Artifacts

The exact READY scaffold hashes were:

- `ProjectRenameUseCase.swift` — `d7c8eaaaa182501df1c689581a0723d73aaa437d37355b41cde5885be81cb33d`;
- `ProjectRenameUseCaseTests.swift` — `b8ba3c9d935dec5324328d3ddf3c6e352011c9e88dfc2284a7c80dff4214c69e`.

Exact READY commit `dc7c9779efb4d176e507e0c683f2dffc4814110b`
passed immutable Actions run `33808493496`: traceability completed in 10 seconds
and the isolated target job completed in 3 minutes 31 seconds with all tests,
both staging builds and clean generated artifacts.

## Local READY Gate

The comment-only candidate passes:

- conversion sync/check/report at 829 recorded / 814 discovered, zero errors
  and only the three established retired-path warnings;
- capability/query checks, regenerated residual controls at 395 mapped / 174
  residual / 45 blockers, M0, target isolation and generated target contracts;
- all 286 existing target tests in 61 suites with Swift warnings as errors;
- repeatable project generation at unchanged hashes `0657194a` / `388303af`;
- macOS and generic iOS Simulator staging builds; and
- complete JSON parsing and clean diff formatting.

This local result did not authorize implementation until the exact READY commit
and immutable run above passed.

The first independent READY reviews caught one P2 mirrored-proof risk and one
P2 authority overstatement: the matrix did not require literal expectations,
and product authority was credited with operation-layer revision and byte-
preservation mechanics. They also caught two P3 omissions around
ProjectDetailView status and rejection-recovery wording. The corrected contract
requires literal baseline/delta evidence with recording-only fakes, assigns
revision/name/command semantics to the verified operation dependency, preserves
ProjectDetailView explicitly, and distinguishes a returned rejected receipt
from unimplemented rejection recovery.
The final authority correction registers the verified Project rename operation
evidence as conversion-control authority for this batch and points the use-case
dependency requirement directly to its Implemented Contract. Both corrected-
diff reviewers confirmed the resulting authority chain and returned GO.

## Local Implementation Verification

The exact implementation hashes are:

- `ProjectRenameUseCase.swift` — `5048a8e4a615a5723e58bd13ba4378b5adb2ca2ae7be769954ce1c56003e4c56`;
- `ProjectRenameUseCaseTests.swift` — `238e170ca652f21a15ca2354895b8b6d66571395dfc109fed52e4cf0dc52d39a`.

Eight focused tests prove public non-`@testable` construction, exact transient
shape, byte-identical accepted whitespace and more-than-8-KiB Unicode display
names, zero/maximum revisions, every receipt state, one-call dispatch, literal
baseline and eight-axis changed-leaf ownership, zero/one-call failure
boundaries, all 12 typed failures, cancellation, bounded unknown errors, exact
privacy-safe diagnostics, command topology and permanent exclusions.

The focused suite and all 294 target tests in 62 suites pass with Swift warnings
as errors. Target isolation and generated contracts, repeatable project
generation at `0657194a` / `388303af`, macOS and generic iOS Simulator staging
builds, and clean diff formatting pass. The implementation diff changes exactly
the two authorized leaves. Both independent implementation reviewers return GO
with no remaining P0-P3 finding. Immutable exact-implementation-SHA CI remains
the sole verification-promotion prerequisite.

## Permanent Exclusions

This evidence does not authorize raw String normalization; initial/current
Project reads; readiness, lifecycle, dirty/no-op, dismissal or error UX;
Client, description, category, allocation, budget, media, child, history or
accounting changes; physical persistence, optimistic projection, retry policy
or rejection-recovery behavior; trusted authorization/audit/apply; Postgres, Data API, RLS,
PowerSync, provider/Auth; SwiftUI/app composition; MCP wiring; Firebase decoding
or migration; hosted resources; production access; release or cutover.
O-022/O-023/O-024/O-025/O-026 and A-003/A-004/A-007/A-015/A-016 remain open or
outside.
