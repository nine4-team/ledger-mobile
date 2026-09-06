# EVID-CLIENT-RENAME-USE-CASE-001 — Client Rename Use Case

- Timestamp: 2026-09-03
- Class: verified implementation / provider-free typed Client-rename application dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; source worktree and released Firebase app unchanged
- Prior verified conversion baseline: exact commit
  `2fa5a536d4b4b8b490da4c7fea2691b53aaf9d1a`; Project-rename implementation
  `9c8e27cfb26252f6d068841a822be578412c82e6` passed immutable Actions run
  `33816585123`
- Ready baseline: exact commit
  `9cc34f4ca6004e7c3b3e1816f07112c55a70fe54`; immutable Actions run
  `33819792298` passed both jobs
- Claimed target surfaces: `SWIFT-2F4458F40735`, `TEST-341B2CD23B6A`
- Preserved verified dependencies: `SWIFT-9CB51D74D41C`,
  `TEST-D1C8EFBDFDDE` at exact implementation `3282f8e3` / run `33612902860`;
  `SWIFT-401EBD892749`, `TEST-0911D1BF8A05` at exact implementation
  `3c0b58b6` / run `33584456794`; `SWIFT-D7F3D08FA568`,
  `TEST-F304037D32B6` at exact implementation `6cea8459` / run `33702499992`
- Preserved source surfaces: `SWIFT-CF459111B7BB` and
  `MCPTOOL-A9FCDED31D3F` remain `characterized` on O-025;
  `SWIFT-D73C92887393` remains `characterized` on O-024;
  `SWIFT-E1A771F6A409` and `SWIFT-27CA6EAC7092` remain `characterized` on
  O-024/O-025; `SWIFT-7500FDB4FDB6`, `SWIFT-038E6D4248AF`,
  `TEST-E591BE8A4B58`, `SWIFT-A9748507A27A` and `MCPMOD-8FC7F6247E2F`
  remain `target_mapped`
- Slice dossier:
  `conversion/implementation-slices/client-rename-use-case-contracts.json`
- Verification state: verified at exact implementation commit
  `0f000b8e491019a9307c46437312b7ae0f5711dc` and immutable Actions run
  `33821354656`

## Selection and Authority

A read-only feature-specific authority audit selected the typed Client rename
application boundary above the verified Client rename operation and stable
Client display-value contracts. The candidate IDs were derived from the exact
new paths and did not exist at baseline.

Canonical Client authority makes the current Client name mutable display text,
requires edits to occur on the stable Client rather than independently on each
Project, and freezes Invoice/report/paid-history display snapshots. The exact
expected revision, already-validated `ClientDisplayName` bytes, precondition,
command and failure semantics come from the verified Client rename operation
and display-value contracts, not from the product spec. This slice therefore
accepts the existing typed value; it does not accept a raw String or decide
trimming, blank-name, length, dirty/no-op, initial-value or other presentation
behavior. Current Edit Project UI and generic Firebase/MCP update mechanics are
source evidence, not target application authority.

O-024/O-025 do not block this narrow dispatch boundary because it performs no
lifecycle/delete/merge/correction/reassignment policy and does not wire any
app, service, MCP or provider implementation. Those decisions remain
unadvanced.

## Frozen Boundary

Exactly two target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ClientRenameUseCase.swift`;
- `LedgeriOS/LedgerTargetCoreTests/ClientRenameUseCaseTests.swift`.

The public `ClientRenameIntent` is a transient, non-Codable value with
exactly `accountId`, `clientId`, `expectedRevision` and `newDisplayName`, where
the display name is the existing `ClientDisplayName`. The generic
`ClientRenameUseCase<R: ClientRenaming>` receives that intent plus exact
Operation, Principal, contract-version and finite capture-time values. It
constructs `ClientRenameDraft` and `RenameClientCommand` before invoking
`ClientRenaming.rename` exactly once, validates the receipt outside the catch,
and returns the exact receipt and local state.

The application error boundary preserves `CancellationError` and all 12
`ClientRenameFailure` cases. Only an unknown error thrown by the port maps to
`localAcceptanceFailed`; construction and receipt-validation failures cannot be
silently reclassified.

The verified Client rename operation remains sole owner of accepted display-
name bytes, expected revision, same-Client precondition, draft, command,
subject, fingerprint, receipt validation and typed failure semantics. The use
case may compose those contracts but cannot reproduce or extend them.

## Required Verification

Ten obligations freeze proof for:

1. ordinary non-`@testable` public construction, exact four-field shape,
   Equatable/Sendable, runtime non-Codable intent, and zero/maximum revisions;
2. already-validated ClientDisplayName bytes, including accepted whitespace and
   more than 8 KiB Unicode, reaching the command without second normalization;
3. zero/maximum revisions, every `LocalOperationState` and one-call dispatch;
4. reciprocal encoded-leaf ownership across Account, Client, revision, display
   name, Operation, actor, contract and time, using literal flattened baseline
   expectations and exact literal changed-leaf sets for all eight axes;
   recording/canned fakes and expected-value helpers may not reconstruct
   expectations with the production draft, command or validation logic;
5. both nonfinite times at zero calls and receipt mismatch after one call;
6. all 12 typed port failures, structured cancellation and bounded unknown
   errors;
7. exact stable privacy-safe diagnostic enumeration;
8. exact narrow nested command topology and broader-field exclusions;
9. exact READY/implementation allowlists plus preserved dependency/source
   statuses; and
10. separate immutable READY and implementation CI before verification
    promotion.

## Comment-Only READY Artifacts

The exact READY scaffold hashes were:

- `ClientRenameUseCase.swift` —
  `5b8a81c4ade68f37b30e9ad2155bed1d3dbecdaba41cbfaa0ee69207b03e8e18`;
- `ClientRenameUseCaseTests.swift` —
  `94dca4aa8156e8b084f2e5a63c50691e9637f67459ee7c7b6ac095f6a3dc6431`.

The prior clean conversion baseline was exact commit
`2fa5a536d4b4b8b490da4c7fea2691b53aaf9d1a`. Exact READY commit
`9cc34f4ca6004e7c3b3e1816f07112c55a70fe54` passed immutable Actions run
`33819792298`: traceability completed in 13 seconds and the isolated target job
completed in 7 minutes 1 second with all tests, both staging builds and clean
generated artifacts.

## Local READY Gate

The complete READY gate passed: conversion sync/check/report recorded 831
surfaces / 816 currently discovered with zero errors and only the three
established retired-path warnings; residual controls are current at 397 mapped /
174 residual / 45 blockers; capability/query checks, M0, target isolation and
generated contracts, JSON parsing and clean diff formatting passed. All 294
target tests in 62 suites passed with Swift warnings as errors, as did
repeatable Xcode generation at unchanged hashes `0657194a` / `388303af` and
both staging builds.

Two independent preflight reviews caught stale checkpoint metadata, authority
overstatement and an omitted preserved MCP module. The corrected package
assigned command mechanics to conversion-control evidence, preserved the
projects MCP module explicitly and recorded the current checkpoint. Both
corrected-diff reviewers returned GO, and the immutable READY run above
authorized implementation.

## Local Implementation Verification

The exact implementation hashes are:

- `ClientRenameUseCase.swift` —
  `9ea0ee0f7b88ea1f3b835644282303dcead3fc51427e7d498b3734d07433cd76`;
- `ClientRenameUseCaseTests.swift` —
  `e7bf7f4bbc1bb1296cbf87bed91b7969a1c341e0cfd1738cec0ace1ee51617d1`.

Eight focused tests prove ordinary public non-`@testable` construction, exact
transient shape, UTF-8-byte-identical accepted whitespace and more-than-8-KiB
Unicode display names, zero/maximum revisions, every receipt state, one-call
dispatch, literal baseline and eight-axis changed-leaf ownership, zero/one-call
failure boundaries, all 12 typed failures, cancellation, bounded unknown
errors, exact privacy-safe diagnostics, command topology and permanent
exclusions.

The focused suite and all 302 target tests in 63 suites pass with Swift warnings
as errors. Target isolation and generated contracts, repeatable project
generation at `0657194a` / `388303af`, macOS and generic iOS Simulator staging
builds, conversion/capability/query/residual/M0 controls and clean diff
formatting pass. The implementation diff changes exactly the two authorized
executable leaves plus synchronized control/evidence artifacts.

One independent implementation reviewer found that the initial large-Unicode
test used Swift String equality without separately proving UTF-8 byte equality.
The test now compares `Data` built from the actual and expected UTF-8 views.
That reviewer and a second independent full-slice reviewer both return GO with
no remaining P0-P3 finding. This local evidence satisfies
`CRENAMEUSE-TEST-001` through `CRENAMEUSE-TEST-009`. Exact implementation
commit `0f000b8e491019a9307c46437312b7ae0f5711dc` passed immutable Actions run
`33821354656`: traceability completed in 11 seconds and the isolated target job
completed in 6 minutes 59 seconds with all tests, both staging builds and clean
tracked artifacts. The immutable run satisfies `CRENAMEUSE-TEST-010`; the
dossier and its two target leaves are verified.

## Permanent Exclusions

This evidence does not authorize raw String normalization; initial/current
Client reads; readiness, lifecycle, dirty/no-op, dismissal or error UX; Client
archive/delete/merge/alias behavior; Project ownership/reassignment or current
projection updates; frozen Invoice/report/paid-history/audit rewrites; physical
persistence, optimistic projection, retry policy or rejection-recovery behavior;
trusted authorization/audit/apply; Postgres, Data API, RLS, PowerSync,
provider/Auth; SwiftUI/app composition; MCP wiring; Firebase decoding,
`clientName` clustering or migration; hosted resources; production access;
release or cutover. O-022/O-023/O-024/O-025/O-026 and
A-003/A-004/A-007/A-015/A-016 remain open or outside.
