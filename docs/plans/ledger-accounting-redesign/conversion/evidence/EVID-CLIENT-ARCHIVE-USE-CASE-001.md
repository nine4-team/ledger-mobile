# EVID-CLIENT-ARCHIVE-USE-CASE-001 — Client Archive Use Case

- Timestamp: 2026-09-03
- Class: ready design / provider-free selected-Client archive dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; source worktree and released Firebase app unchanged
- Target-branch baseline: exact note-candidate rejection commit `7d759c8a6853b774a2077bd4a070b0188cb1abfd`; immutable Actions run `33763753929` passed both jobs
- Claimed target surfaces: `SWIFT-7A484C80FD98`, `TEST-E10E6D44CC8A`
- Related source evidence retained without promotion: `SWIFT-7500FDB4FDB6`, `SWIFT-58A14BD25578`, `SWIFT-CF459111B7BB`, `SWIFT-E23DAF7A18FA`, `MCPMOD-8FC7F6247E2F`
- Slice dossier: `conversion/implementation-slices/client-archive-use-case-contracts.json`
- Verification state: comment-only ready package; strict authority preflight, complete local gate and two corrected-diff reviews pass; exact-ready-SHA CI pending

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

Exactly two comment-only target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ClientArchiveUseCase.swift`; and
- `LedgeriOS/LedgerTargetCoreTests/ClientArchiveUseCaseTests.swift`.

The future non-Codable `ClientArchiveIntent` contains exactly AccountID,
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
returned GO. Immutable exact-ready-SHA CI remains required before implementation.

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
