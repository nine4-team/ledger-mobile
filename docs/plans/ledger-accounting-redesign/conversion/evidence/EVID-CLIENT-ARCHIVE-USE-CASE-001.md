# EVID-CLIENT-ARCHIVE-USE-CASE-001 — Client Archive Use Case

- Timestamp: 2026-09-03
- Class: implementation / local integration evidence for provider-free selected-Client archive dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; source worktree and released Firebase app unchanged
- Target-branch baseline: exact note-candidate rejection commit `7d759c8a6853b774a2077bd4a070b0188cb1abfd`; immutable Actions run `33763753929` passed both jobs
- Ready baseline: exact commit `a4bc1daa73f640a42f8b0de50240801619339f95`; immutable Actions run `33765054735` passed before implementation
- Claimed target surfaces: `SWIFT-7A484C80FD98`, `TEST-E10E6D44CC8A`
- Related source evidence retained without promotion: `SWIFT-7500FDB4FDB6`, `SWIFT-58A14BD25578`, `SWIFT-CF459111B7BB`, `SWIFT-E23DAF7A18FA`, `MCPMOD-8FC7F6247E2F`
- Slice dossier: `conversion/implementation-slices/client-archive-use-case-contracts.json`
- Verification state: corrected implementation passes root review, two independent final reviews and the complete local integration gate; exact implementation-commit CI pending

## Selection and Authority

Fresh root and independent strict-authority preflight selected one application
path above the verified `ClientArchiveOperation`. Canonical target authority says
Clients have stable Account-scoped identity, archived state removes a Client
from future Project selection without deleting history, and a Client with
Projects or accounting history is archived rather than hard-deleted. D-006
confirms Client identity; no source Firebase Client implementation is needed or
treated as target authority.

The slice accepts an already-selected stable Client and exact expected revision;
adds caller operation metadata; assembles the existing archive command; invokes
its narrow port once; validates its receipt; and bounds failure behavior.

## Frozen Boundary

Exactly two implemented target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ClientArchiveUseCase.swift`; and
- `LedgeriOS/LedgerTargetCoreTests/ClientArchiveUseCaseTests.swift`.

The non-Codable `ClientArchiveIntent` contains exactly AccountID,
ClientID and ExpectedClientRevision. `ClientArchiveUseCase` separately receives
OperationID, PrincipalID, OperationContractVersion and finite capture time;
constructs the existing `ClientArchiveDraft` and `ArchiveClientCommand`; calls
`ClientArchiving.archive` exactly once after construction; validates the
receipt; preserves its exact local state, `CancellationError` and normalized
`ClientArchiveFailure`; and maps other errors to `localAcceptanceFailed`.

## Source and Decision Accounting

The target adds a Client entity that the Firebase app does not currently have.
Related Project model, new/edit/list screens and MCP Project tooling therefore
remain source/migration or future-integration evidence at their prior statuses
and content. The use case does not implement actual hiding from a picker, read a
Client row, inspect active Projects or accounting history, or choose local
eligibility.

O-025 remains open because merge, Project reassignment, dependency correction
and history rewrite are absent. Archive does not cascade to Projects and does
not impersonate restore, delete, merge, rename or reassignment.

## Required Verification

Eight planned obligations require exact transient intent shape, revision
boundaries, reciprocal independent variation of all intent/caller fields, every
receipt state, construction-before-call, mismatch refusal, distinct normalized/
raw/cancellation failures, exact command/diagnostic exclusions, actual READY
diff review, and separate immutable READY and implementation CI checkpoints.

The local READY checkpoint passes conversion sync/check/report, capability/
query/residual and M0 controls, target isolation and generated contracts, all
261 existing target tests in 57 suites with warnings as errors, repeatable Xcode
generation at hashes `0657194a` / `388303af`, both staging builds, JSON
validation and clean diff formatting while the two leaves contain no executable
behavior. Two read-only reviewers inspected the complete diff. Authority review
caught one stale baseline/run line; root review clarified that actor and capture
time are separate application inputs rather than fields in the three-field
intent. Both corrections passed regenerated controls and both reviewers then
returned GO. Exact ready commit
`a4bc1daa73f640a42f8b0de50240801619339f95` then passed immutable Actions
run `33765054735` (traceability 7 seconds; isolated target 2 minutes 33 seconds),
authorizing only the two frozen implementation leaves.

## Local Implementation Verification

The two frozen leaves now implement one transient exact Account/Client/revision
intent and application use case. The use case constructs the existing verified
archive draft/command, invokes `ClientArchiving` exactly once after successful
construction, validates the receipt, preserves every local operation state,
preserves structured cancellation and normalized `ClientArchiveFailure`, and
maps unexpected port errors to `localAcceptanceFailed`.

One tightly bounded writer edited only the two frozen leaves and made no Git or
documentation change. Root inspected every implementation/test line and reran
six focused tests plus all 267 target tests in 58 suites with warnings as errors;
both runs pass. Tests cover exact three-field intent shape with compile-time
`Equatable & Sendable` and runtime non-Codable checks, zero and maximum revision,
reciprocal independent variation of all seven intent/caller inputs, every
receipt state, Infinity/NaN before zero calls, receipt mismatch
after one call, typed/raw/cancellation failures, every stable diagnostic, exact
nested encoded-command structure and the permanent negative boundary.

Implementation hashes:

- `ClientArchiveUseCase.swift` —
  `92661d6dd90db46c6f0da58ec7fee818b9cfcab481e7c32a57233e4a99514415`; and
- `ClientArchiveUseCaseTests.swift` —
  `477782ae8c3d65a19381099ecce4630b910b17a684bf1bb9f5fd002ab6a03d25`.

The complete local implementation gate also passes: conversion sync/check/
report, capability/query/residual and M0 controls; target isolation/generated
contracts; all 267 target tests in 58 suites with warnings as errors; repeatable
project hashes `0657194a` / `388303af`; both staging builds; JSON validation;
clean formatting; and the exact two-executable-path allowlist. The first
authority-focused implementation review found
that removing either declared `Equatable` or `Sendable` conformance would not
fail a test; the added constrained compile-time assertion closes that proof gap
without changing runtime behavior. Corrected-diff authority and adversarial
continuity reviews both return GO with no remaining P0-P3. Exact implementation-
commit CI remains required before verification.

## Permanent Exclusions

This package cannot choose Client picker/list/detail/readiness, archive
confirmation/dismissal, local lifecycle eligibility, actual hiding, optimistic
projection, physical persistence/restart, authorization, membership, Client
existence, authoritative revision lock, dependency/history transaction or audit
assignment. It cannot restore/unarchive, delete, merge, rename, reassign or
cascade Projects.

No Postgres schema/handler, Data API grant, RLS policy, PowerSync Stream,
provider adapter, app/MCP wiring, Firebase migration/reconciliation, hosted
resource, production access, deployment, release or cutover is authorized.
O-025 and A-003/A-004/A-007/A-015/A-016 remain open or outside. Product specs
and confirmed decisions remain authority.
