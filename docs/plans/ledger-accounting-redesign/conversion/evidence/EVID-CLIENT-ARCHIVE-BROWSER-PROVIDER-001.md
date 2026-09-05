# EVID-CLIENT-ARCHIVE-BROWSER-PROVIDER-001 — Client Archive Browser Supabase/PowerSync READY Boundary

- Timestamp: 2026-09-05
- Class: implementation plan / comment-only READY candidate
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; source worktree and released Firebase app remain unchanged
- Target baseline: `574f285b67a9779a45a9bfc7ce22d6d7cee0323a` on
  `codex/supabase-powersync-implementation`
- Slice dossier:
  `conversion/implementation-slices/client-archive-browser-supabase-powersync-vertical-slice.json`
- Claimed target surfaces: `CONFIG-2DBC5A626444`, `CONFIG-8A30E46E3901`,
  `CONFIG-8F9EA6CCC0DB`, `SWIFT-35D653A39618`, `SWIFT-375BF832F772`,
  `SWIFT-4D4DB03E0A24`, `SWIFT-BD7BF890CB6C`, `SWIFT-E431F314B326`,
  `TEST-3B1F3E444423`, `TEST-E65089F7DC26`
- Verification state: comment-only READY candidate; exact READY commit,
  independent review and immutable CI are pending

## Selected Outcome and Product Authority

The next decision-independent product slice is: archive one currently observed
active Client offline through the isolated Client browser while preserving every
Project and all history.

Canonical target authority is intentionally narrow:

- `docs/specs/client-identity-and-project-transfers.md` **Client Entity / Storage
  and identity** defines stable Account-scoped Client identity and says archived
  Clients are hidden from new-Project selection without deleting history.
- Its **Client lifecycle** section says Clients with Projects or accounting
  history are archived rather than hard-deleted and separates merge and Project
  reassignment from ordinary lifecycle behavior.
- D-006 confirms that stable `clientId`, never name text, is Client identity and
  relationship authority.

Project Archive is used only as reviewed technical implementation-pattern
evidence for durable operations, local overlays, auth-first handlers, immutable
results and reconciliation. It is not Client product authority and does not
import Project-specific confirmation, lifecycle, dependency or resubmission
semantics.

## Authority Ambiguity and Safe Bounded Policy

No canonical target section decides whether resubmitting archive for an already
archived Client should succeed as a no-op, return the prior operation, increment
revision or reject. O-042 likewise governs archived-Client *rename*, not archive
resubmission. This READY package therefore does not invent a general policy.

The bounded slice instead:

1. exposes archive only from exact currently observed **active** Client detail
   evidence and its revision;
2. makes waiting, absent, unavailable, uncached, archived, mismatched or stale
   selection evidence dispatch nothing;
3. requires the trusted handler to reject non-active state only as the safe
   precondition for this command; and
4. reserves any broader already-archived retry/no-op semantics for explicit
   product authority.

The client-archive command cannot restore/unarchive, hard-delete, rename, merge,
reassign or cascade. O-023/O-024/O-025/O-040/O-042/O-043 remain unselected.

## Frozen Comment-Only Leaves

Exactly ten new target leaves are reserved by this synchronized READY package.
Only nine may become executable after independent review and immutable CI; the
  `.sql.ready` marker in item 9 must remain physically present and byte-identical.
  Its frozen replacement identity is `CONFIG-86F1E734BC70` for
  `supabase/tests/client_archive_vertical_slice.test.sql`:

1. `LedgeriOS/LedgerTargetPowerSync/AccountBoundOperationIdentity.swift` — one
   generic trusted-prefix + Account-digest + canonical-UUID primitive used by
   both archive families;
2. `LedgeriOS/LedgerTargetPowerSync/ClientArchivePowerSyncStore.swift` — atomic
   encrypted operation/command/overlay acceptance, dependency ordering and
   reconciliation;
3. `LedgeriOS/LedgerTargetPowerSync/SupabaseClientArchiveRPC.swift` — scoped-user
   Client archive request/result adapter;
4. `LedgeriOS/LedgerTargetPowerSyncTests/ClientArchivePowerSyncVerticalSliceTests.swift`;
5. `LedgeriOS/LedgerTargetAppModel/ClientArchiveBrowserStagingExercise.swift`;
6. `LedgeriOS/LedgerTargetAppModelTests/ClientArchiveBrowserStagingExerciseTests.swift`;
7. `LedgeriOS/LedgerTargetApp/ClientArchiveBrowserStagingRuntimeAdapter.swift`;
8. `supabase/migrations/20260905125208_client_archive_vertical_slice.sql`,
   created by pinned `supabase@2.116.0 migration new`;
9. `supabase/tests/client_archive_vertical_slice.test.sql.ready`, an inert,
   non-runnable reservation; and
10. `scripts/test-local-client-archive-rpc.mjs`, a no-request runner reservation.

At READY every leaf contains comments only. The synchronized scaffold hashes are
recorded in `M0-CLIENT-ARCHIVE-BROWSER-VERTICAL-SLICE-001.json`; the
`CONFIG-2DBC5A626444` `.sql.ready` hash must remain byte-identical through
implementation, when it is retired with explicit replacement evidence pointing
to separately registered runnable `CONFIG-86F1E734BC70`, and every planned
database-test owner path must move from `.sql.ready` to `.sql` in that same
synchronized checkpoint.

## Frozen Shared Touchpoints

Implementation may change only the minimum reviewed portions of these existing
target surfaces; they retain their current primary owners and are not silently
claimed by this slice:

- `LedgerPowerSyncSchema.swift` — add exactly one insert-only Client archive
  command table and one local-only Client lifecycle overlay table;
- `ClientProjectDirectoryPowerSyncQuery.swift` and
  `ClientCoreDetailsPowerSyncQuery.swift` — merge the same exact Client archive
  overlay into directory and detail truth so every consumer sees one lifecycle
  outcome without changing order, readiness, or source completeness;
- `ProjectSetupPowerSyncStore.swift` — refuse stale or current local Project
  acceptance when its existing Client is effectively archived;
- `LedgerPowerSyncUploadConnector.swift` — upload client-archive-v1 FIFO, resolve
  terminal dependencies, validate exact result linkage and retain transient work;
- `AccountWorkspacePendingWorkRuntime.swift` — own one archive store/RPC through
  the existing runtime lease and drainage boundary;
- `LedgerOfflineClientRuntime.swift` — expose only one Account-bound Client
  archive call and its exact operation-state observation through the existing
  facade;
- `ClientBrowsingStagingExercise.swift` and
  `ClientBrowsingStagingExerciseView.swift` — expose exact selected active Client
  evidence and the bounded archive action/state without changing read semantics;
- `LedgerTargetStagingApp.swift` — compose and drain the Client archive model;
- `ProjectArchivePowerSyncStore.swift` — delegate its existing public identity
  wrapper to the generic primitive without changing any accepted Project archive
  byte;
- `scripts/check-target-environment.mjs` — enforce adapter, wiring,
  accessibility, direct-command, identity and drainage boundaries;
- `scripts/supabase-conversion-ledger.mjs` — retain the READY identities and,
  only at implementation, register the separately runnable pgTAP replacement
  without altering discovery or warning semantics;
- `supabase/migrations/20260904151946_project_setup_vertical_slice.sql` behavior,
  redefined only as necessary by the new migration so existing-Client Project
  setup takes the same deterministic Client-row lock and rechecks lifecycle;
- `LedgeriOS/LedgerTarget.xcodeproj/project.pbxproj` — generated membership only;
  `LedgeriOS/Package.swift`, `LedgeriOS/LedgerTargetProject.yml`,
  `powersync/sync-streams.yaml` and root `package.json` must remain byte-identical.

Baseline hashes for review are recorded before implementation:

- Client directory query `82a351eb5589801e009c4d5a398db0440c9ecbd22aeffee121e1ab657389c51f`;
- Client detail query `23b7f779871cd613cc5a945449c3c24c167ea26260c2b9c37466234551a19745`;
- PowerSync schema `c4c3755977832d6626e42b3ad66358d819cb850043774e619b98cdffc17c888e`;
- Project Setup store `d1e8cce89445e70d0b026a45e8e4a1893ecc69ae01baa5c633d862f0cf6af598`;
- upload connector `4efeb90c96f7a5165ba0db49bd2402e2e941b1bfbae5e901ff99fc76eba23182`;
- Account runtime `cb49720cb9eda68fe92e07e02e0ac6fd35bba29f9c71dbd8036c7012f62fe7f5`;
- offline Client runtime `644eb3a6386f1430bf293a1ea6c418bfe143ab0df2df0e103c11cd0a5119ab10`;
- staging app `8ca878f9464a87b0249514e16380a868b100296bec748459781c590b91e1cf68`;
- Client browser model `5f14814fb7c7892eee8ae7fa515d6424ac112f4cec36238d5844e9f57b64ad67`;
- Client browser view `f13948872c11e0fc95d43e793a49e63da590532819c75598e60c81d604954d03`;
- Project archive store `72ac2c1ed552299dba0658bc3a10894da1cb2d7ea675086eb0dc2694e322e479`;
- target checker `c0f0258eead43671e04dfa8fd661ce162f784b95a4ff047a65a7902782eec113`;
- conversion discovery control `68e2190d72494bdc620559782df150382e6d229642629e7276d6848af6089852`;
- existing Project-setup migration `e3da858f16caee3dd6a7f6e0c686ed3f7662006f078712ac1d348de29afb68c4`;
- Sync Streams `bc694cc89c4723fbd7fd7fbda6b2129123c5d3f96b65e70920620cd45aebe528`;
- root package `640c8f0da118503fe14f93437385f049fcf5183ea290069e2f06e9bddda8fd89`;
- Swift package `fb9b93c681860bab95a6fc18fc2f1962aff9f99da2367d188082fc5569736c9c`;
- XcodeGen source `e74a2659e366d98f41181318a8e5ea1d259888b0e1f8555af797b0cdf02196c9`.

Two consecutive READY-generation runs produced identical standalone target
project hash `51404d6282d659bb452e8ca4d356159554459bd9f3d6b398ff490fb4acf14f8e`;
the source Firebase application project remains untouched.

## Identity, Replay and Namespace Boundary

Client archive Operation IDs must be exactly:

```text
client-archive-<sha256(accountId UTF-8), 64 lowercase hex>-<lowercase canonical UUID>
```

The new generic primitive accepts a trusted internal command-family prefix,
exact AccountID and UUID. It is not a caller-controlled general string builder.
Validation recomputes every byte. ProjectArchiveOperationIdentity must delegate
to it with byte-identical existing output and rejection behavior.

The shared operation-result table reserves the entire `client-archive-` prefix:
only canonical same-Account Client archive identities may use it. Create Client,
create Project, Project archive and future non-archive commands cannot squat that
namespace. Auth/actor/capability checks precede OperationID, existing-result and
Client disclosure; cross-Account and cross-command probes cannot reveal or
rebind results. Exact same-ID replay returns the immutable result; any changed
binding is rejected.

## Offline Dependency and Project-Safety Contract

Acceptance atomically writes immutable local operation evidence, an insert-only
Client archive command and one local-only lifecycle overlay. Synchronized Client
rows are never rewritten optimistically.

Dependency semantics are explicit rather than copied from Project Archive:

- an earlier queued/applying Client creation for this Client waits ahead of
  archive; if creation is terminally rejected, it unblocks archive for trusted
  missing/non-active disposition without fabricating a local server result or
  retrying forever, and the overlay remains until authoritative terminal archive
  evidence;
- an earlier queued/applying Project setup referencing this Client also waits
  ahead of archive; if Project setup is rejected, it no longer blocks because no
  Project exists to preserve; if applied, the created Project remains unchanged;
- accepted ordering is FIFO, but terminal dependency failure cannot create an
  infinite retry loop; and
- after the Client archive overlay is accepted, shared Project Setup selection
  removes that Client and local acceptance independently rejects new or not-yet-
  accepted stale/current attempts against the effective archived lifecycle;
  exact replay of a Project-setup OperationID accepted before archive returns
  its prior receipt before this overlay validation.

Server authority closes the same race. Client archive and existing-Client
`spike_create_project` serialize on the same deterministic Client-row lock and
Project setup rechecks active lifecycle under that lock. If Project creation
wins, it may apply and archive then preserves it. If archive wins, later Project
setup returns an immutable `project_setup_client_not_selectable` outcome rather
than raw constraint failure/retry. Neither interleaving deadlocks, and no
successful Project can attach after authoritative archive.

## Required Executable Proof

`CARCHIVEBROWSER-TEST-001` already passes through the verified provider-free
Client archive operation and use-case suites. Implementation must make
`CARCHIVEBROWSER-TEST-002` through `-011` and `-013` executable and passing:

- exact mutation-set, no-cascade/no-related-write and byte-identical preservation
  for every currently represented related row, with the same regression required
  whenever a later Client-related table is introduced;
- exact/lost/changed/cross-command replay, reserved-prefix protection, archive/
  archive concurrency and archive/Project-create interleavings;
- positive/negative RLS/Data API and auth-first non-enumeration;
- encrypted offline acceptance, restart, shared projection, dependency outcomes,
  Project-setup replay-before-overlay validation, rejection/readback cleanup and
  no resurrection;
- Client browser and Project Setup admission/refusal plus operation-state,
  cancellation, termination, restart and drainage;
- byte-identical Project archive identity regression;
- schema/RLS/index/lock/numeric/advisor review; and
- exact READY and implementation immutable-CI checkpoints.

`CARCHIVEBROWSER-TEST-012` remains planned until real isolated authenticated
PowerSync proves authorized row receipt and unauthorized local-row absence.
A-003/A-004 therefore remain proposed.

## READY Gate and Permanent Exclusions

Before executable work, root and an independent reviewer must return GO on the
complete comment-only diff. The exact READY commit must pass all three immutable
workflow jobs: conversion control, disposable local Supabase and isolated target
tests/builds. Only then may the nine change-authorized READY leaves, the frozen
shared touchpoints above, and separately registered runnable pgTAP leaf
`CONFIG-86F1E734BC70` change in one synchronized `implemented` checkpoint. The
inert `CONFIG-2DBC5A626444` `.sql.ready` marker is never change-authorized.

This package does not implement or authorize Client restore/delete/rename/merge,
Project reassignment/deletion, cascade, accounting rewrite, preference behavior,
media deletion, target MCP, source transform, Firebase adapter/worktree change,
hosted resource, production access, migration, deployment, release or cutover.
It cannot advance A-003/A-004/A-007/A-015/A-016 or settle
O-023/O-024/O-025/O-040/O-042/O-043. Product specs and confirmed decisions remain
product authority.
