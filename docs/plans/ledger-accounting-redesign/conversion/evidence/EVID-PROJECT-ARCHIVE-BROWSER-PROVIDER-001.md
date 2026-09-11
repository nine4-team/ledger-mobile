# EVID-PROJECT-ARCHIVE-BROWSER-PROVIDER-001 — Project Archive Through Browser Implementation

- Status: locally implemented; independently reviewed GO with no P0-P3; exact
  implementation commit passed all immutable CI jobs
- Date: 2026-09-05
- Reviewed base: `318ff300e03bff123c39480cba15dac84911dbcc`
- Exact green READY checkpoint: commit `089dc562`, immutable Actions run
  `33961281661`
- Exact green implementation checkpoint: commit
  `939d745319794936daf66832d5fec77f30b20762`, immutable Actions run
  `33966132401`
- Environment: isolated target worktree and synthetic local fixtures only
- Production/Firebase impact: none
- Slice: `project-archive-browser-supabase-powersync-vertical-slice`
- Claimed target surfaces: nine executable leaves listed below; the original
  `.sql.ready` identity remains physically present and retired as inert evidence

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

## Implemented Leaves and Retired Marker

| Manifest identity | Exact path | Current hash | Implemented responsibility |
| --- | --- | --- | --- |
| `SWIFT-53B8C9C37D3F` | `LedgeriOS/LedgerTargetPowerSync/ProjectArchivePowerSyncStore.swift` | `72ac2c1ed552299dba0658bc3a10894da1cb2d7ea675086eb0dc2694e322e479` | encrypted atomic archive acceptance, Account-bound identity, exact overlay and reconciliation |
| `SWIFT-0753297CA29A` | `LedgeriOS/LedgerTargetPowerSync/SupabaseProjectArchiveRPC.swift` | `7dfc97dc8fa344fc460d73a06238a8d3e71ef87bd5967f5a44a17458ceba55a2` | scoped-user archive RPC, exact command encoding and terminal-result validation |
| `TEST-475355568D74` | `LedgeriOS/LedgerTargetPowerSyncTests/ProjectArchivePowerSyncVerticalSliceTests.swift` | `bb45930f943dcdbf2494064ed40453598b71da692a31fb5d3334cecae70041ad` | deterministic offline/provider/reconciliation/identity matrix |
| `SWIFT-D58BDD1F45EE` | `LedgeriOS/LedgerTargetAppModel/ProjectArchiveBrowserStagingExercise.swift` | `d4522a1f3f7d14ad87ce97e2aa48a1234223df1078354bbf8e9ee01289670451` | Core-only evidence-bound confirmation, submission, operation truth and retry lifecycle |
| `TEST-EAAB5CD74000` | `LedgeriOS/LedgerTargetAppModelTests/ProjectArchiveBrowserStagingExerciseTests.swift` | `a792b675301c16ef6807088e7d230f907be3e08aa94573ac3ee288a25468decb` | deterministic confirmation, admission, selection/retry, recovery and drainage matrix |
| `SWIFT-4F36B1F525D0` | `LedgeriOS/LedgerTargetApp/ProjectArchiveBrowserStagingRuntimeAdapter.swift` | `fc460794ca7f6cee07ff2401778463cb8ef4bb599ac1d6ddde0fe30f073e513f` | thin runtime archive/operation-state forwarding only |
| `CONFIG-20D251EF21F6` | `supabase/migrations/20260905095803_project_archive_vertical_slice.sql` | `e45ef69c82363a384a559d1991cf5a1080ec3dc6f9901defaf0e52345c8f5269` | trusted Postgres handler and authenticated RPC |
| `CONFIG-CAB6A5DAD1C0` | `supabase/tests/project_archive_vertical_slice.test.sql` | `9723eb9d935dd0d3aa8d1a0b3ca00d0c5aaff3768151db40af03dc6b11d94412` | runnable 81-assertion database/RLS/replay/concurrency/preservation suite |
| `CONFIG-78696A3C79AA` | `scripts/test-local-project-archive-rpc.mjs` | `f5d1771d40faf1a7b229ceb16465b2239c7598bf6041a4b32e0daa827453a932` | disposable scoped-user local Data API verification |

Retired in place: `CONFIG-062839A9903C`,
`supabase/tests/project_archive_vertical_slice.test.sql.ready`, remains
byte-identical at SHA-256
`964cc5e8caa6a377393e51d063b7e03ad1d3c6fcc66530926f91ce93c37129c6`.
Its sole runnable replacement is `CONFIG-CAB6A5DAD1C0`.

The migration filename was generated with
`npx --yes supabase@2.116.0 migration new project_archive_vertical_slice`.
Implementation began only after exact READY commit `089dc562` passed immutable
Actions run `33961281661`. The authorized discovery touchpoint now registers
the runnable `.sql` identity without changing validation or warning semantics.
The `.sql.ready` marker remains outside pgTAP execution, exactly one runnable
Project-archive pgTAP leaf exists, and package.json remains byte-identical at
`640c8f0da118503fe14f93437385f049fcf5183ea290069e2f06e9bddda8fd89`.
No target MCP behavior, hosted access, Firebase work, production data access,
migration, release or cutover authority is introduced.

## Frozen Existing Touchpoints

The executable checkpoint modified only these existing shared surfaces for the
stated rule while preserving their primary owner:

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
| `CONFIG-2EBA890AF767` | `LedgeriOS/LedgerTarget.xcodeproj/project.pbxproj` | `63e896b09c19330a0b22e8b5707b21816dfc2246dbc803a2b237b0d959c8ca9d` | deterministic XcodeGen membership only; regenerated reproducibly and remained byte-identical |

The bounded shared touchpoints currently hash to:

- schema `c4c3755977832d6626e42b3ad66358d819cb850043774e619b98cdffc17c888e`;
- upload connector `4efeb90c96f7a5165ba0db49bd2402e2e941b1bfbae5e901ff99fc76eba23182`;
- directory query `82a351eb5589801e009c4d5a398db0440c9ecbd22aeffee121e1ab657389c51f`;
- detail query `32e0bcc431035a15945a0beaa3047437c4524527bc6e7d6ed093050b92871632`;
- offline runtime `644eb3a6386f1430bf293a1ea6c418bfe143ab0df2df0e103c11cd0a5119ab10`;
- workspace runtime `cb49720cb9eda68fe92e07e02e0ac6fd35bba29f9c71dbd8036c7012f62fe7f5`;
- Project browser AppModel `da3874dfb1f911da0bc2d9b202f2a22f3f49a020f6e5bd389451857b82e2617c`;
- Project browser view `2bc3cf4d58889b1ec3b5c27595db6116bf236bebd280cc779e114e4caae13363`;
- staging shell `8ca878f9464a87b0249514e16380a868b100296bec748459781c590b91e1cf68`;
- target checker `c0f0258eead43671e04dfa8fd661ce162f784b95a4ff047a65a7902782eec113`; and
- conversion discovery control `5ce47fe0d1758bcede282d4ba5a0067a5908c4e204b6b1fc9603e05871a4e68b`.

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
and accounting table. This implementation therefore enforces their strict
non-mutation contract but does not overclaim physical row proof. Each later
schema slice must repeat archive-preservation regression before promotion. No
trigger/cascade may turn the lifecycle update into child mutation or deletion.

## Executable Review and Verification

Independent review returned GO with no P0-P3 after root and reviewer-driven
corrections closed Account-bound OperationID enumeration, exact request replay
binding, local command/overlay validation, device-clock regression, browser
selection/retry ownership and observation drainage. The retained marker hash,
package.json hash and unchanged PowerSync Sync Streams were rechecked.

Local executable evidence is:

- 28/28 focused ProjectArchive Swift tests passed;
- 473/473 Swift tests in 80 suites passed with process-wide nonparallel execution;
- 123/123 pgTAP assertions passed, including 81/81 Project archive assertions;
- Supabase database lint reported zero findings;
- the disposable scoped-user Project archive Data API runner passed;
- the target-environment checker passed; and
- repeatable XcodeGen plus both iOS and macOS staging builds passed.

Conversion synchronization/check/report, product-authority and implementation-
slice freshness, residual controls and the cumulative M0 gate passed in exact
implementation commit `939d745319794936daf66832d5fec77f30b20762` and all
three immutable jobs passed in Actions run `33966132401`. Real authenticated
PowerSync authorization remains planned as PARCHIVEBROWSER-TEST-012, so A-003
and A-004 remain proposed and no hosted result is inferred from local proof.

Restore/unarchive, delete, rename, details edit, Client reassignment/merge,
category/note/media/Item/Space/Transaction/Invoice/accounting mutation, new child
schema, target MCP implementation, Firebase, source import, migration, hosted
resources, production access, release and cutover are outside this slice.
