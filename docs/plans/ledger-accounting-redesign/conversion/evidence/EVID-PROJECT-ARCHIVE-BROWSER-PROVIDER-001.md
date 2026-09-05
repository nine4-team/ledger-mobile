# EVID-PROJECT-ARCHIVE-BROWSER-PROVIDER-001 — Project Archive Through Browser READY Candidate

- Status: independently reviewed comment-only READY candidate; exact commit and
  immutable CI pending
- Date: 2026-09-05
- Reviewed base: `318ff300e03bff123c39480cba15dac84911dbcc`
- Environment: isolated target worktree and synthetic local fixtures only
- Production/Firebase impact: none
- Slice: `project-archive-browser-supabase-powersync-vertical-slice`
- Claimed target surfaces: nine new comment/placeholder leaves listed below

## Selected Outcome and Authority

One explicit confirmation bound to the currently selected active Project and
its observed revision in the isolated target browser will be accepted without
network, move that stable Project from Active to Archived immediately as honest
partial local evidence, survive an encrypted restart, upload FIFO, and reconcile
on exact applied or durable rejected server evidence. Cancel makes no call, and
a changed selection, lifecycle or revision invalidates the captured confirmation
rather than retargeting it. A revision conflict restores current active evidence
and permits only a new explicit retry derived from the refreshed revision.

Canonical Projects authority already says archived Projects leave Active,
appear in Archived, and preserve transactions, Items, Spaces and budget
allocations. The target contract further separates ArchiveProject from rename,
details update, Client reassignment and deletion. The verified archive operation
and use case own exact Project identity, UInt64 revision, operation envelope,
fingerprint, receipt, cancellation and bounded failure semantics. The verified
Project browser owns atomic segments, provider order, current-evidence selection,
detail truth, false-empty semantics and observation drainage. No new product
decision is required.

O-024 does not block this slice because physical delete is absent. O-025 does
not block it because Client identity and relationship are immutable. O-023 does
not block it because no attachment reference or byte is changed. Restore/
unarchive, rename, reassign, media mutation and every other lifecycle operation
are expressly excluded. A-003/A-004 remain proposed and prevent hosted or
architecture-promotion claims, not this isolated local implementation.

## Reserved Comment-Only Leaves

| Manifest identity | Exact path | READY hash | Future responsibility |
| --- | --- | --- | --- |
| `SWIFT-53B8C9C37D3F` | `LedgeriOS/LedgerTargetPowerSync/ProjectArchivePowerSyncStore.swift` | `7b78c35b5116dcf27d0b4f438fedcdf28819b58d14372b62cb3ccfcf22be7b9d` | encrypted atomic archive acceptance, exact overlay and reconciliation |
| `SWIFT-0753297CA29A` | `LedgeriOS/LedgerTargetPowerSync/SupabaseProjectArchiveRPC.swift` | `f8d2a610c3405229a65de9f61761e23265a1d0279943b042e2873f8ce1e755e5` | scoped-user archive RPC and terminal-result validation |
| `TEST-475355568D74` | `LedgeriOS/LedgerTargetPowerSyncTests/ProjectArchivePowerSyncVerticalSliceTests.swift` | `564e11ab07d6a0fd430c56e911c84951d0ffdcf387d645b09d8119c97eb27b95` | deterministic offline/provider/reconciliation/preservation matrix |
| `SWIFT-D58BDD1F45EE` | `LedgeriOS/LedgerTargetAppModel/ProjectArchiveBrowserStagingExercise.swift` | `b079de9943b69b63675565e2aa9d6751154c2f771fff93ae21856623d0976105` | Core-only evidence-bound confirmation, submission, operation truth and retry lifecycle |
| `TEST-EAAB5CD74000` | `LedgeriOS/LedgerTargetAppModelTests/ProjectArchiveBrowserStagingExerciseTests.swift` | `135558a27811c2a69ba86e7ed44cac1bb98e46318e94f1f160108f5bcb462831` | deterministic confirmation, browser/archive admission, recovery and drainage matrix |
| `SWIFT-4F36B1F525D0` | `LedgeriOS/LedgerTargetApp/ProjectArchiveBrowserStagingRuntimeAdapter.swift` | `cb7f79f07e6616817111c3da66a40aba3655c32ab76a38c67588f04d56790cb9` | thin runtime archive/operation-state forwarding only |
| `CONFIG-20D251EF21F6` | `supabase/migrations/20260905095803_project_archive_vertical_slice.sql` | `f6ee6c04b8c91ecf49cd35896b4e52b30eab3bf7d513207913a79850edc19c0f` | trusted Postgres handler and authenticated RPC |
| `CONFIG-062839A9903C` | `supabase/tests/project_archive_vertical_slice.test.sql.ready` | `964cc5e8caa6a377393e51d063b7e03ad1d3c6fcc66530926f91ce93c37129c6` | non-runnable reservation for database/RLS/replay/concurrency/preservation tests; implementation retains the file as an inert retired marker with replacement evidence when runnable `.sql` becomes `CONFIG-CAB6A5DAD1C0` |
| `CONFIG-78696A3C79AA` | `scripts/test-local-project-archive-rpc.mjs` | `5e209e3987f8cd355295b68631d5ad3880d0892cd1b64db7f2bd6d5e5dd40a9e` | disposable scoped-user local Data API verification |

The migration filename was generated with
`npx --yes supabase@2.116.0 migration new project_archive_vertical_slice`.
Every leaf is comment-only. The `.sql.ready` reservation is not a runnable SQL
test and remains outside the existing run-all pgTAP discovery until an exact
green READY commit authorizes adding the real `.sql` suite. The
run-all database-test command remains unchanged. There is no executable Swift,
DDL/DML, request, MCP registration or product UI at this checkpoint.

Because conversion identity is path-derived, implementation must perform one
explicit synchronized replacement rather than an ordinary rename: retain the
`.sql.ready` file byte-for-byte as an inert marker, retire
`CONFIG-062839A9903C` with this evidence and the new test identity as its
replacement, create/discover/classify/claim runnable
`supabase/tests/project_archive_vertical_slice.test.sql` as
`CONFIG-CAB6A5DAD1C0`, and update every slice/test-owner path to the runnable
file. The authorized conversion-control touchpoint must add literal discovery
of that runnable path without changing validator semantics or suppressing
warnings. That checkpoint must contain exactly one runnable Project-archive
pgTAP leaf plus the inert marker, no new missing-surface warning, and
byte-unchanged package.json run-all test discovery.

## Frozen Existing Touchpoints

The later executable checkpoint may modify only these existing shared surfaces,
for the stated rule, while preserving their current primary owner:

| Manifest identity | Exact path | READY-preparation hash | Permitted archive-only change |
| --- | --- | --- | --- |
| `SWIFT-19D4AA7B766B` | `LedgeriOS/LedgerTargetPowerSync/LedgerPowerSyncSchema.swift` | `a11de86c5552eac7cc6597ae3f144b04e501f2afe99634c970a4635925bbcbed` | add one insert-only archive command and one local-only archive overlay table |
| `SWIFT-A9F7D22095F8` | `LedgeriOS/LedgerTargetPowerSync/LedgerPowerSyncUploadConnector.swift` | `2e136d56055a91dbbe6bba5a8c500657e2c2acc47dfa8ab2bd862739f545daee` | validate/dispatch archive command FIFO and record only exact terminal evidence/overlay cleanup |
| `SWIFT-B23F91245E50` | `LedgeriOS/LedgerTargetPowerSync/ClientProjectDirectoryPowerSyncQuery.swift` | `49af060c1b8c9a1fc499a5f6b6b2c8e7de5eed8a69e57d60f212d7431fb24944` | merge archive lifecycle/revision overlay without changing upstream order, scope or readiness truth |
| `SWIFT-56CB8BCDD85C` | `LedgeriOS/LedgerTargetPowerSync/ProjectCoreDetailsPowerSyncQuery.swift` | `983e5d79a903893f509e3ac2caf4add5b90c15be794faa200f232325d8a08b09` | merge the same archive overlay and perform exact safe readback reconciliation |
| `SWIFT-548A8A928FAE` | `LedgeriOS/LedgerTargetPowerSync/LedgerOfflineClientRuntime.swift` | `efe7838b0b73e340da27891d21684704ca3ae1c1ac9f4e0a0dd21c16ac597fcc` | expose one public archive call and one exact operation-state stream through the existing facade |
| `SWIFT-75CFE285AF37` | `LedgeriOS/LedgerTargetPowerSync/AccountWorkspacePendingWorkRuntime.swift` | `aa0dfd77900dd4eb7c06f0940d362ad7bdd2958e3499fa04aa37e9192880d6da` | own one archive store, scope finite/stream leases and drain active archive observation before database close |
| `SWIFT-CAB085E24751` | `LedgeriOS/LedgerTargetAppModel/ProjectBrowsingStagingExercise.swift` | `b5f8a92f92ef3347086257d3951cd674d1367b9f10e7ba36f29b183ab61f4c7d` | derive an atomic exact archive intent only from current selected active detail evidence; keep browsing lifecycle unchanged |
| `SWIFT-07427FF0DA84` | `LedgeriOS/LedgerTargetApp/ProjectBrowsingStagingExerciseView.swift` | `6e05906efccea572bbc772fe5efa9a82df06289b65ad4841d085fae3a5d6ffca` | add typed Archive/retry controls and exact state/diagnostic labels only |
| `SWIFT-061553E63650` | `LedgeriOS/LedgerTargetApp/LedgerTargetStagingApp.swift` | `0efbb8fec335ce5ae6789bed11e3d6bdeaeecc9807cf3073295d99c7041aefb8` | own/start/stop archive flow and drain it with both browsers before the single runtime close on normal/failure paths |
| `CONFIG-81235587F306` / `FILE-A6E49E3815F4` | `scripts/check-target-environment.mjs` | `13dbb0e3df7413d1e1d759aa15ad2796bc4551eb92d602f3da9e5fa9d83ded18` | add exact containment, wiring, exclusions, preservation and accessibility-source checks |
| `FILE-208B7E9D7F47` | `scripts/supabase-conversion-ledger.mjs` | `eff99a0d15c8601192105bb74e132d6fc3d6e9e563ab0666d3f0409c7123f2c5` | add literal discovery of runnable `supabase/tests/project_archive_vertical_slice.test.sql` and refresh this control's existing owner hash/evidence only; do not change validation or warning semantics |
| `CONFIG-7AE45AD102EA` | `package.json` | `640c8f0da118503fe14f93437385f049fcf5183ea290069e2f06e9bddda8fd89` | remain byte-unchanged; run-all pgTAP discovery executes `.sql`, never the retained `.sql.ready` marker |
| `CONFIG-2EBA890AF767` | `LedgeriOS/LedgerTarget.xcodeproj/project.pbxproj` | `63e896b09c19330a0b22e8b5707b21816dfc2246dbc803a2b237b0d959c8ca9d` | deterministic XcodeGen membership only; later implementation must regenerate reproducibly |

These dependencies are exact and must remain byte-unchanged:

| Manifest identity | Exact path | Hash | Owner/rule |
| --- | --- | --- | --- |
| `SWIFT-10A07B52B82D` | `LedgeriOS/LedgerTargetCore/ProjectArchiveOperation.swift` | `5a3421b470e4cd99639c6f2a91ac7240d2fddb3b1ac0bc9660b4ff97788202f9` | verified Project archive command semantics; consume unchanged |
| `SWIFT-7C5BD31FBF71` | `LedgeriOS/LedgerTargetCore/ProjectArchiveUseCase.swift` | `9285d1663a78dfba79b33fb12635ce5ccdf5095d5aaff18614d7d0f1675fa8d4` | verified archive application dispatch; consume unchanged |
| `SWIFT-AA91CE0C3FAB` | `LedgeriOS/LedgerTargetApp/ProjectBrowsingStagingRuntimeAdapter.swift` | `f8b3ba21024d29ec5aa8da47a8f6e0db0f51817bca0ab42a6d33169d19de922f` | existing two-watch browser adapter; archive uses the separate new adapter |
| `CONFIG-428FDE11BBE4` | `powersync/sync-streams.yaml` | `bc694cc89c4723fbd7fd7fbda6b2129123c5d3f96b65e70920620cd45aebe528` | reuse existing Project/result download streams; add no stream |
| `CONFIG-031396750B85` | `LedgeriOS/Package.swift` | `fb9b93c681860bab95a6fc18fc2f1962aff9f99da2367d188082fc5569736c9c` | recursive SPM membership is consumed as-is; this file may not change |
| `CONFIG-77D38BB6819B` | `LedgeriOS/LedgerTargetProject.yml` | `e74a2659e366d98f41181318a8e5ea1d259888b0e1f8555af797b0cdf02196c9` | recursive app-source membership is consumed as-is; this file may not change |

Existing regression owners remain mandatory even when the new test leaf holds
new cases: `ClientProjectDirectoryPowerSyncQueryTests.swift`
(`TEST-5AAEE26660C8`, hash
`581aa186a186005cee27690712b77d020027ccac5b2282c9344fa6c625c6e237`),
`ProjectPowerSyncVerticalSliceTests.swift` (`TEST-3F2CAFC760D5`, hash
`709d0c95ac1f6194e5d4a933278b3da2c22bc984f0c6017c98fd5d7eacaeb6f3`),
`LedgerPowerSyncVerticalSliceTests.swift` (`TEST-E0636D89C442`, hash
`a6d9a90ae3435e605fbae996446d389fe5d96fb4678ade94169639072c3bc160`),
`AccountWorkspacePendingWorkRuntimeTests.swift` (`TEST-8D6A15063B2D`, hash
`073d00c37343ee3a159ed89a5031aef0a49854d58e9d3a6bea0a76bedcfe942c`),
and `ProjectBrowsingStagingExerciseTests.swift` (`TEST-5C7E5E715EAE`, hash
`ccf2b062c6e6c96f3c45aef2a3bfb2a873ca783c8f0a47f1c71c3c9519a7eb41`).
Any necessary change to one of those tests is evidence support only and must
retain its primary owner and be recorded in the implementation diff.

## Frozen Offline and Reconciliation Semantics

Local acceptance stores operation, insert-only command and local-only overlay
in one transaction. The overlay never edits a synchronized Project row. It can
layer over an authoritative Project or a pending-created Project. Exact replay
is checked before current-effective-revision validation, so the same command
remains idempotent after later evidence. A pending create command must upload
before its dependent archive command.

The directory and detail queries apply exactly one valid latest archive overlay
to lifecycle and projected revision, retaining Project/Client identity, name,
description, creation audit and provider row order. Pending evidence makes both
views partial and cannot establish authoritative empty or readiness. Archive
does not alter source completeness, source exhaustiveness, membership sentinel
or Client relationship completeness.

Transient failure retains the command and overlay. A durable rejection updates
only its exact local operation and removes only its exact overlay; the Project
returns to the segment and revision represented by current underlying evidence.
An explicit retry must capture refreshed active detail evidence and a new
OperationID. Applied optimism remains until the matching local applied result
exists and authoritative lifecycle is archived at the projected revision, or a
newer authoritative revision supersedes it. Stale readback cannot clear or
later resurrect optimism.

## Frozen Browser, Lifecycle and Accessibility Proof

The Core-only archive model first captures a confirmation bound to exact current
Account, Project, active lifecycle and revision evidence. Cancel makes zero calls.
Confirm revalidates every captured field against the current selection; changed
selection, lifecycle or revision discards stale confirmation rather than
retargeting it. Only an unchanged confirmation accepts represented active content from found,
incomplete, partial, stale, retryable-cached or required-update-cached detail
states because exact revision conflicts remain authoritative server outcomes.
Waiting, authoritative absence, unavailable, uncached retryable/required-update,
archived, mismatched or stale-selection evidence dispatches zero calls.

Two simultaneous confirms issue one archive call. An ambiguous local acceptance
error retains exact OperationID, captured time and intent so explicit retry
replays byte-identically. A queued receipt cannot be submitted again. The exact
operation observation renders all six `LocalOperationState` values without
inventing server authority. Durable rejection/conflict requires refreshed
current active evidence and explicit new-identity retry.

Selection change, stop and restart cancel and join archive observation. Tests
must cover throw, spontaneous cancellation and unexpected normal completion
before and after first evidence; noncooperative late values cannot mutate a new
generation. Staging normal and failed cleanup drain archive and both existing
browsers before the single runtime close. Runtime close drains archive operation
observation before structured database close.

Exact source-level identifiers are:

- `target-project-archive-action`;
- `target-project-archive-confirm`;
- `target-project-archive-cancel`;
- `target-project-archive-state`;
- `target-project-archive-diagnostic`; and
- `target-project-archive-retry`.

Existing Project browser identifiers remain unchanged. These are source/build
claims only; no interactive accessibility claim is made without an app UI test.

## Preservation and Explicit Proof Limit

The trusted handler may update only the selected `spike_projects.lifecycle`,
its monotonic revision and server update time, plus insert one immutable result.
Database and provider tests must snapshot and compare every other extant Project
field, the Client relationship/row, budget-category definitions and allocations.
The handler contains no delete or update of note, attachment/media, Item, Space,
Transaction, Invoice or accounting/history relations.

The current isolated spike does not yet physically represent every future child
and accounting table. This READY candidate therefore freezes their strict
non-mutation contract but does not overclaim physical row proof. Each later
schema slice must repeat archive-preservation regression before promotion. No
trigger/cascade may turn the lifecycle update into child mutation or deletion.

## Required Gate and Exclusions

Before executable work, an independent reviewer must verify this exact package,
the nine leaf hashes, all shared touchpoints, reciprocal requirements/tests,
scope exclusions and generated outputs. The reviewed READY commit must then pass
all immutable jobs. Only that exact green commit authorizes implementation of
the other eight reserved leaves, creation of the separately tracked runnable
`.sql` leaf and bounded shared edits; the `.sql.ready` marker stays byte-unchanged.

Required implementation checks include conversion sync/check/report, residual
and product-authority generation/check, target environment/contracts/query/MCP
checks, focused and complete nonparallel Swift tests, clean local Supabase reset,
lint, pgTAP and scoped Data API tests, repeatable XcodeGen, both staging builds,
clean artifacts and independent executable review. Hosted Sync authorization and
real device/reconnect evidence remain planned and cannot be inferred locally.
The same implementation gate must prove the retained inert `.sql.ready`
retirement marker and separately discovered runnable `.sql` replacement
transition described above before any surface advances.

Restore/unarchive, delete, rename, details edit, Client reassignment/merge,
category/note/media/Item/Space/Transaction/Invoice/accounting mutation, new child
schema, target MCP implementation, Firebase, source import, migration, hosted
resources, production access, release and cutover are outside this slice.
