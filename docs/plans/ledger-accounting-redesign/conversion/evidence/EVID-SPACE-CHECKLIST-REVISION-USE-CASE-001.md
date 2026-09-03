# EVID-SPACE-CHECKLIST-REVISION-USE-CASE-001 — Space Checklist Revision Use Case

- Timestamp: 2026-09-03
- Class: implementation / local integration evidence for provider-free Space checklist edit submission
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; source worktree and released Firebase app unchanged
- Target-branch baseline: exact Client-archive verification-promotion commit `b0fcd6cbba8c7312fc4f4f8ae3d8c1c74f4a4b47`; immutable Actions run `33768000016` passed both jobs
- Ready baseline: exact commit `6534da3361b3b52b3713ac558799a1a70ab00f26`; immutable Actions run `33785649411` passed before implementation
- Claimed target surfaces: `SWIFT-1FDB27E18B95`, `TEST-674E6F23E5BE`
- Related source evidence retained without promotion: `SWIFT-B5661A312D65` remains `target_mapped`
- Verified dependencies: `SWIFT-02BF0EA3C433`, `SWIFT-A9BCA70B7F9C`, `SWIFT-EB8803C0864A` and their verified tests
- Slice dossier: `conversion/implementation-slices/space-checklist-revision-use-case-contracts.json`
- Verification state: corrected implementation passes root review, two independent final reviews and the complete local integration gate; exact implementation-commit CI pending

## Selection and Authority

A bounded strict-authority scout ranked checklist revision submission ahead of
Project setup and Item-to-Space assignment. Root independently confirmed the
canonical `spaces.md` target requirements: one complete ordered checklist
replacement, stable nested identities, canonical outer-whitespace normalization,
preserved accepted interior text, explicit checked state, empty/zero-item
validity and atomic expected-revision conflict. No open product decision changes
that boundary. O-026 governs shared template authorization; O-037 governs Space
archive effects on assigned Items. This slice implements neither.

The verified editing-presentation contract already owns restart-safe draft
mutation, exact semantic-base evidence and command derivation. The verified
revision-operation contract already owns canonical hierarchy values, operation
binding, expected-revision precondition, receipt validation and the narrow port.
This slice adds only the application dispatch between them.

## Frozen Boundary

Exactly two implemented target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/SpaceChecklistRevisionUseCase.swift`; and
- `LedgeriOS/LedgerTargetCoreTests/SpaceChecklistRevisionUseCaseTests.swift`.

`SpaceChecklistRevisionUseCase` receives an existing
`SpaceChecklistEditingDraft`, current `SpaceCoreDetailsUpdate`, OperationID,
PrincipalID, OperationContractVersion and finite capture time. It asks the draft
to derive and revalidate one `ReviseSpaceChecklistsCommand`, then calls
`SpaceChecklistRevising.reviseChecklists` exactly once only after derivation,
validates the receipt and returns its exact local state. It preserves Swift
`CancellationError`, `SpaceChecklistEditingFailure`, and
`SpaceChecklistRevisionFailure`; any other port error becomes
`SpaceChecklistRevisionFailure.localAcceptanceFailed`.

## Source and Decision Accounting

`EditChecklistModal.swift` remains `target_mapped`. This use case replaces only
its eventual save/dispatch responsibility. Initial loading, raw draft controls,
immediate validation and error presentation, cancel/success dismissal, layout,
copy, navigation and app composition remain unconverted. No current Firebase
mechanic is treated as target authority.

D-023 supplies only the no-accounting invariant. O-023/O-026/O-032/O-037 remain
open or outside but do not block this slice because media, templates, Transaction/
completion policy and Space archive are excluded. The
slice cannot create/apply/save templates, archive a Space, assign or clear Items,
change details/scope/lifecycle, attach media, create review evidence, set the
legacy completion flag, or mutate accounting.

## Required Verification

Eight obligations require successful one-call dispatch of the same draft
against both ready-complete current and retryable ready-complete cached evidence,
including nonsemantic version/as-of/name/notes/audit refreshes over an unchanged
semantic base; canonical complete replacement including empty and zero-item
cases; reciprocal variation of every semantic/operation field; every receipt
state; zero-call derivation failures; one-call mismatch; distinct presentation/
revision/raw/cancellation failures; exact diagnostics/encoded shape; actual
READY diff review; and separate immutable READY and implementation CI checkpoints.

The READY checkpoint must pass conversion sync/check/report, capability/query/
residual and M0 controls, target isolation and generated contracts, all existing
target tests with warnings as errors, repeatable project generation, both staging
builds, JSON validation, clean diff formatting and the exact two-comment-path
allowlist. Immutable exact-ready-SHA CI is required before executable code.

The reviewed comment-only package passed conversion sync/check/report,
capability/query/residual and M0 controls, target isolation and generated
contracts, all 267 existing target tests in 58 suites with warnings as errors,
repeatable Xcode generation at hashes `0657194a` / `388303af`, macOS and generic
iOS Simulator staging builds, JSON validation and clean diff formatting. The
READY checkpoint control state was 823 recorded / 808 discovered, 389 mapped-or-later / 174
residual / 45 blockers with only the three established retired-path warnings.
The first READY review found that both admissible current and retryable cached
paths were not explicitly frozen at the application boundary. The corrected
plan requires the same draft to dispatch exactly once through both paths,
including nonsemantic refreshes over an unchanged semantic base. Both
independent reviewers then returned GO. Exact READY commit
`6534da3361b3b52b3713ac558799a1a70ab00f26` passed immutable Actions run
`33785649411` (traceability 15 seconds; isolated target 3 minutes 48 seconds),
authorizing only the two frozen implementation leaves.

## Local Implementation Verification

A bounded writer changed only the two frozen leaves and made no Git or
documentation change. The use case asks the existing draft to derive and
revalidate one command before any port call, invokes `SpaceChecklistRevising`
once, validates the receipt, preserves every local operation state, preserves
`CancellationError` plus both typed failure families, and maps only unknown port
errors to `localAcceptanceFailed`.

Six focused tests prove both ready-complete current and retryable-ready-complete
cached paths, including nonsemantic refreshes; active/archived Project and
Business Inventory transparency; more than 8 KB of Unicode name/item text with
outer normalization and exact interior preservation; duplicate text; empty and
zero-item collections; zero and `UInt64.max` revisions on both readiness paths;
exact reciprocal encoded leaf deltas; every receipt state; derivation-before-
call failures; receipt mismatch; typed/raw/cancellation behavior; all 41 stable
diagnostics; exact nested command shape; and permanent exclusions.

Implementation hashes:

- `SpaceChecklistRevisionUseCase.swift` —
  `4694ad8c4322d5cc4ad21edb38f5b7e8a3f3c3eb367c545ba393556c18ca3ace`; and
- `SpaceChecklistRevisionUseCaseTests.swift` —
  `e4d975662cc555269f54c5e670e084e40a73cc50fe36441540c317a0319574f3`.

Root inspected every implementation/test line and reran the six focused tests
plus all 273 target tests in 59 suites with warnings as errors; both pass.
Repeatable project generation retains hashes `0657194a` / `388303af`, and both
macOS and generic iOS Simulator staging builds pass. The first implementation
reviews found test-only proof gaps for scope/lifecycle transparency, both
revision boundaries on both readiness paths, long UTF-8 values and exact
owning-field-only forwarding. The corrected tests close every gap; both
independent final reviewers return GO with no remaining P0-P3. Complete
conversion/target controls, JSON validation, exact-path scope and clean
formatting pass. Exact implementation-commit CI remains required before
verification.

## Permanent Exclusions

This package does not authorize a new edit model, UI admission, draft controls,
physical persistence or restart writes, optimistic projection, rejection
recovery, current membership, update authorization, authoritative apply/audit,
Postgres schema/handler, Data API grant, RLS policy, PowerSync Stream, provider
adapter, app/MCP wiring, Firebase migration/reconciliation, hosted resource,
production access, deployment, release or cutover.

O-023/O-026/O-032/O-037 and A-003/A-004/A-007/A-015/A-016 remain open or outside. Product
specs and confirmed decisions remain authority.
