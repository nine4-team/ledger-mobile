# EVID-PROJECT-ARCHIVE-USE-CASE-001 — Project Archive Use Case

- Timestamp: 2026-09-03
- Class: verification / provider-free Project archive application dispatch
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; source worktree and released Firebase app unchanged
- Ready baseline: exact commit `bf4294727f4b2bde117dc0eaf9e74e9769fe8699`; immutable Actions run `33755885978` passed before implementation
- Claimed target surfaces: `SWIFT-7C5BD31FBF71`, `TEST-29C0CCC4353F`
- Partial source evidence: `SWIFT-D73C92887393` remains `characterized` and blocked by O-024; `MCPTOOL-921DA05B3330` remains `target_mapped`
- Slice dossier: `conversion/implementation-slices/project-archive-use-case-contracts.json`
- Implementation baseline: exact commit `232acf922b6c1ab1016017c3ebc3b926b164466c`; immutable Actions run `33758116150` passed
- Verification state: verified at the exact implementation commit after two independent final reviews, complete local integration gates and immutable CI

## Selection and Authority

Fresh authority preflight found one decision-independent application path above
the verified `ProjectArchiveOperation`: accept exact Account/Project/expected-
revision intent, add caller operation metadata, assemble the existing command,
invoke its narrow port once, validate its receipt and bound failures. Canonical
Projects authority distinguishes archive from rename, reassignment and physical
deletion. Architecture assigns transient intent to presentation and command
orchestration to application.

The preflight rejected advancing `ProjectDetailView`. That source surface also
contains tabs, export, quick-note, edit, lifecycle display, archive confirmation,
restore/unarchive, delete, dismissal and composition. It remains characterized
under O-024; current source behavior is evidence, not target implementation
authority. It also rejected implementing the current `archive_project` MCP tool:
the source Boolean is mapped into separate `ArchiveProjectCommand` and
`RestoreProjectCommand` responsibilities, while this slice advances only the
archive-true application dispatch. Restore implementation, MCP wiring,
authorization and result presentation remain unimplemented; the complete source
responsibility nevertheless stays explicitly `target_mapped`.

## Frozen Boundary

Exactly two implemented target leaves are claimed:

- `LedgeriOS/LedgerTargetCore/ProjectArchiveUseCase.swift`; and
- `LedgeriOS/LedgerTargetCoreTests/ProjectArchiveUseCaseTests.swift`.

`ProjectArchiveIntent` is non-Codable and contains exactly AccountID,
ProjectID and ExpectedProjectRevision. The verified archive-operation evidence,
not the Projects spec alone, owns the exact revision/precondition, command,
fingerprint, receipt and stable-failure semantics. `ProjectArchiveUseCase` adds caller
OperationID, PrincipalID, OperationContractVersion and capture time, construct
the existing ProjectArchiveDraft/ArchiveProjectCommand, call ProjectArchiving
exactly once only after construction, validate the receipt, preserve its exact
local state, preserve CancellationError and normalized ProjectArchiveFailure,
and map other errors to localAcceptanceFailed.

This boundary consumes no `ProjectCoreDetailsUpdate` and decides no readiness,
active/already-archived eligibility, no-op, restore/unarchive or delete policy.
It makes no claim that physical rows, children or history have been preserved.

## Required Verification

The dossier defines six obligations, and all six pass. Together they require exact intent
shape including revision zero/max; reciprocal forwarding of every intent and caller metadata
field into the existing command and all derived evidence; exactly one post-
construction port call; zero calls for non-finite time; exact receipt local
states and mismatch refusal; structured cancellation; distinct normalized and
raw-error behavior; bounded diagnostics; authorized reflected/recorded/encoded
command shape; and exact two-leaf implementation scope.

The ready checkpoint must pass conversion sync/check, capability/query/residual
and M0 controls, target isolation and generated-contract controls, existing
warnings-as-errors tests, repeatable generation/build controls as required, JSON
validation and clean diff formatting. Exact-ready-SHA CI must pass before either
scaffold is replaced with executable behavior.

The first two independent actual-diff reviews found two documentation/control
defects before commit: the package omitted the current MCP archive/unarchive
surface from its partial-source accounting, and it incorrectly attributed exact
revision/precondition mechanics to the Projects product spec. Corrected-diff
review then caught that retaining `target_mapped` while naming only the archive
half still overclaimed complete mapping. The next review found that restore was
still missing from migration reconciliation and that continuity incorrectly
called both commands future. The corrected package splits the source Boolean
into the existing `ArchiveProjectCommand` and separate future
`RestoreProjectCommand` responsibilities while implementing neither MCP path,
and assigns the exact implemented archive revision, fingerprint, receipt and
failure semantics to the already-verified archive-operation evidence. The
final review also caught that the first reconciliation correction had landed on
the broad MCP module instead of the exact tool; that unrelated change was
reverted and archive/restore reconciliation now belongs to the tool record. The
complete corrected local ready gate
passes at 819 recorded / 804 discovered surfaces, zero errors and the three
established retired-path warnings; 392 mapped / 167 residual / 44 blockers; M0;
all 255 target tests in 56 suites with warnings as errors; target isolation and
generated contracts; repeatable project hashes `0657194a` / `388303af`; both
staging builds; JSON validation; and clean diff formatting. Final corrected-diff
re-review returned GO from both independent reviewers. Exact ready commit
`bf4294727f4b2bde117dc0eaf9e74e9769fe8699` passed immutable Actions run
`33755885978` (traceability 7 seconds; isolated target 2 minutes 49 seconds),
authorizing only the two frozen implementation leaves.

## Local Implementation Verification

The two frozen leaves now implement the transient exact Account/Project/revision
intent and one application use case that assembles the existing verified archive
draft/command, invokes `ProjectArchiving` once after construction, validates the
receipt, preserves every local state, preserves structured cancellation and
normalized `ProjectArchiveFailure`, and maps unexpected port errors to
`localAcceptanceFailed`.

Initial implementation review found no production-flow defect but rejected weak
schema-exclusion tests and a comment that implied physical durability. The
corrected tests assert every stable diagnostic, exact nested encoded-command key
set, every caller/derived field, every receipt state, zero/one call counts and
the complete forbidden-field boundary. The comment now distinguishes canonical
command encoding from physical durability/restart, which remain unimplemented.
Both independent final reviewers return GO with no P0-P3.

Six focused and all 261 target tests in 57 suites pass with warnings as errors.
Conversion/target controls, repeatable project hashes `0657194a` / `388303af`,
both staging builds and clean formatting also pass. Exact implementation commit
`232acf922b6c1ab1016017c3ebc3b926b164466c` passed immutable Actions run
`33758116150` (traceability 9 seconds; isolated target 3 minutes 8 seconds).
The first local conversion check correctly detected the changed frozen hashes;
the implementation checkpoint acknowledged them before resynchronizing generated
state, and the exact implementation CI verified that synchronized result.

Implementation hashes:

- `ProjectArchiveUseCase.swift` — `9285d1663a78dfba79b33fb12635ce5ccdf5095d5aaff18614d7d0f1675fa8d4`; and
- `ProjectArchiveUseCaseTests.swift` — `0f6fb8be145258a3fa811223bda589c3d78bfb5c64d6e0aac87ecd83ce5c7507`.

## Permanent Exclusions

This evidence does not authorize `ProjectDetailView`, initial/read/readiness
state, active/archive eligibility, confirmation/cancel/dismiss UX, tabs, export,
quick notes, edit, restore/unarchive, physical delete or history-preservation
proof, child/accounting mutation, authorization, persistence, Postgres, Data API,
RLS, PowerSync, provider composition, app/MCP wiring, source migration, hosted
resources, production access, deployment, release or cutover. O-024/O-025 and
A-003/A-004/A-007/A-015/A-016 remain open or outside. Product specs and confirmed
decisions remain authority.
