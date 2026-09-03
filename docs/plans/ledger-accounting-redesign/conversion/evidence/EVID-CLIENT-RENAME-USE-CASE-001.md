# EVID-CLIENT-RENAME-USE-CASE-001 — Client Rename Use Case

- Timestamp: 2026-09-03
- Class: READY / provider-free typed Client-rename application dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; source worktree and released Firebase app unchanged
- Prior verified conversion baseline: exact commit
  `2fa5a536d4b4b8b490da4c7fea2691b53aaf9d1a`; Project-rename implementation
  `9c8e27cfb26252f6d068841a822be578412c82e6` passed immutable Actions run
  `33816585123`
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
- Verification state: comment-only READY prepared; implementation remains
  unauthorized until the reviewed exact READY commit passes immutable CI

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

Exactly two comment-only target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ClientRenameUseCase.swift`;
- `LedgeriOS/LedgerTargetCoreTests/ClientRenameUseCaseTests.swift`.

The future public `ClientRenameIntent` is a transient, non-Codable value with
exactly `accountId`, `clientId`, `expectedRevision` and `newDisplayName`, where
the display name is the existing `ClientDisplayName`. The future generic
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

Ten planned obligations freeze proof for:

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

The exact current scaffold hashes are:

- `ClientRenameUseCase.swift` —
  `5b8a81c4ade68f37b30e9ad2155bed1d3dbecdaba41cbfaa0ee69207b03e8e18`;
- `ClientRenameUseCaseTests.swift` —
  `94dca4aa8156e8b084f2e5a63c50691e9637f67459ee7c7b6ac095f6a3dc6431`.

The prior clean conversion baseline is exact commit
`2fa5a536d4b4b8b490da4c7fea2691b53aaf9d1a`. Local validation is recorded
below. Independent actual-diff review and an immutable exact-READY-SHA CI run
remain required before either scaffold may contain executable code.

## Local READY Gate

Fast authoring validation passes: conversion sync/check/report records 831
surfaces / 816 currently discovered with zero errors and only the three
established retired-path warnings; residual controls are current at 397 mapped /
174 residual / 45 blockers; capability/query checks, JSON parsing and clean
diff formatting pass. The parent integration agent also reports the unchanged
294-test baseline suite passing with the comment scaffolds.

This local result does not authorize implementation. Complete READY review and
remaining target gates, followed by an exact READY commit passing immutable CI,
remain required before either scaffold may contain executable code.

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
