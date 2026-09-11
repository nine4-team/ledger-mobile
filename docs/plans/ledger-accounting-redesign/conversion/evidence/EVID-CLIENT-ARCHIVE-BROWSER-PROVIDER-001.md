# EVID-CLIENT-ARCHIVE-BROWSER-PROVIDER-001 — Client Archive Browser Supabase/PowerSync Implementation

- Timestamp: 2026-09-05
- Class: local implementation / independently reviewed executable vertical slice
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; source worktree and released Firebase app remain unchanged
- Target baseline: `574f285b67a9779a45a9bfc7ce22d6d7cee0323a` on
  `codex/supabase-powersync-implementation`
- Exact green READY checkpoint: commit `7187fa1e1415a0f820554e7f78cc62e1e42a34f4`,
  immutable Actions run `33968952286`
- Exact green implementation checkpoint: commit
  `f2b9945b163e8cf64561facb2e57b7cf54941b0b`, immutable Actions run
  `33976469527`
- Slice dossier:
  `conversion/implementation-slices/client-archive-browser-supabase-powersync-vertical-slice.json`
- Claimed target surfaces: `CONFIG-2DBC5A626444`, `CONFIG-86F1E734BC70`, `CONFIG-8A30E46E3901`,
  `CONFIG-8F9EA6CCC0DB`, `SWIFT-35D653A39618`, `SWIFT-375BF832F772`,
  `SWIFT-4D4DB03E0A24`, `SWIFT-BD7BF890CB6C`, `SWIFT-E431F314B326`,
  `TEST-3B1F3E444423`, `TEST-E65089F7DC26`
- Verification state: locally implemented and independently reviewed GO with no
  P0-P3; exact implementation commit passed all three immutable CI jobs

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

## Implemented Leaves and Retired Marker

| Manifest identity | Exact path | Current SHA-256 | Implemented responsibility |
| --- | --- | --- | --- |
| `SWIFT-35D653A39618` | `LedgeriOS/LedgerTargetPowerSync/AccountBoundOperationIdentity.swift` | `d8a2c63b39e2f7ca808f2b3d3e0fd00410ff7537af5b175c7afadc7ee53e3ef5` | generic trusted-prefix, Account-digest and canonical-UUID identity used by both archive families |
| `SWIFT-E431F314B326` | `LedgeriOS/LedgerTargetPowerSync/ClientArchivePowerSyncStore.swift` | `a4f3077f9a310fc7e062da11d54d9d5bef1c9fe912282604121e908edb256df7` | encrypted atomic acceptance, exact replay, dependency ordering and strict reconciliation |
| `SWIFT-375BF832F772` | `LedgeriOS/LedgerTargetPowerSync/SupabaseClientArchiveRPC.swift` | `e313791f9593fe4d3a53c8201121d02c702ab66fcf55aa1cbd29303c91a874b8` | scoped-user RPC and strict terminal-result validation |
| `TEST-3B1F3E444423` | `LedgeriOS/LedgerTargetPowerSyncTests/ClientArchivePowerSyncVerticalSliceTests.swift` | `2ce1e381c0f0181560ecddd661feda3cf6828d7a499fc12c6e85184428a5d917` | 12-test deterministic provider/reconciliation/security matrix |
| `SWIFT-4D4DB03E0A24` | `LedgeriOS/LedgerTargetAppModel/ClientArchiveBrowserStagingExercise.swift` | `b9bcc3e51b3bcd992d10dbb337525d746575b499dfee129742b81f246049a897` | Core-only admission, submission/retry and operation-state orchestration |
| `TEST-E65089F7DC26` | `LedgeriOS/LedgerTargetAppModelTests/ClientArchiveBrowserStagingExerciseTests.swift` | `90406a19380221995d6926adfe7c1d7e358000dd16557e7e5581af0a03845c18` | 9-test browser lifecycle, failure and drainage matrix |
| `SWIFT-BD7BF890CB6C` | `LedgeriOS/LedgerTargetApp/ClientArchiveBrowserStagingRuntimeAdapter.swift` | `4a8104ee8fabaf829e6cf4c4675fc3b42359f18b5e933f79cdf89bdaccfdf84e` | thin runtime forwarding only |
| `CONFIG-8F9EA6CCC0DB` | `supabase/migrations/20260905125208_client_archive_vertical_slice.sql` | `8014b85dd620e47dabfe1f5d4608116c01453f1e4f9cf5653572797bb65aec76` | auth-first Client archive handler/RPC and Project-setup locking repair |
| `CONFIG-86F1E734BC70` | `supabase/tests/client_archive_vertical_slice.test.sql` | `3977c2391a394cba7b440abc6b619403bc1469cc0c551a96d553cb25a46147f5` | runnable 53-assertion database/RLS/replay/concurrency suite |
| `CONFIG-8A30E46E3901` | `scripts/test-local-client-archive-rpc.mjs` | `9005840174642c6d2cbcbdab37abbdf515aaef1ed52fe6ec92ab4f125b5f0890` | disposable scoped-user local Data API verification |

Retired in place: `CONFIG-2DBC5A626444`,
`supabase/tests/client_archive_vertical_slice.test.sql.ready`, remains
byte-identical at SHA-256
`ca53ebcb44c7556f12cb34122a221501779e5e0f712d410f843837f9d807a17d`.
Its sole runnable replacement is `CONFIG-86F1E734BC70`, and every database-test
owner now names the runnable `.sql` leaf. The root `package.json` remains
byte-identical at
`640c8f0da118503fe14f93437385f049fcf5183ea290069e2f06e9bddda8fd89`.

## Frozen Shared Touchpoints

Implementation changed only the minimum reviewed portions of these existing
target surfaces; they retain their current primary owners and are not silently
claimed by this slice:

- `LedgerPowerSyncSchema.swift` — add exactly one insert-only Client archive
  command table and one local-only Client lifecycle overlay table;
- `ClientProjectDirectoryPowerSyncQuery.swift` and
  `ClientCoreDetailsPowerSyncQuery.swift` — merge the same exact Client archive
  overlay into directory and detail truth so every consumer sees one lifecycle
  outcome without changing order, readiness, or source completeness;
- `ProjectSetupPowerSyncStore.swift` — resolve exact replay accepted before
  archive first, then refuse only new or not-yet-accepted stale/current Project
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

Current hashes of the bounded shared touchpoints are:

- Client directory query `655c27d2cb6033ae6742e0277449531b669015f884dd7272cdfac3006a3b528b`;
- Client detail query `652405ab61f5675865259134db3b80da043eb820dbffc08c3c5684d396b0e726`;
- PowerSync schema `6678300e8281b1120bef06610b91ecb97bf7352eeadde488c666643d057a67a8`;
- Project Setup store `c77ca15a1d5c998569ec2d6cd79bf1783f18f1c867ea16f6159479ef48b775f6`;
- upload connector `e3032c3950a524908a0cd89535c3a9556f783b70833910af1bc35adaa495b940`;
- Account runtime `6b56658bdf353eb19cfae79c2d9b94c6b41806bf69f13ee0c2746982ae2afff6`;
- offline Client runtime `6c4e4fa03f17e18c251af121668673f798258ee471874f5c24bab66cbd39d02d`;
- staging app `672a8a4dcb1f0eaf2a83bbc3aa385eb3d5501a7b6b01b60cb2641c8fdba77c29`;
- Client browser model `130e391cb72cc4f6a3ad6283a2753949d0b4dc0bc1a1947394caba1caed419c8`;
- Client browser view `536f567812a276ca7b157703d234da04493f5d89e6584da02f01d3b03286b8cd`;
- Project archive store `139bb47e03652990c511b87dcc65825392aa40de0caa2c4c4a12775168ffe0dd`;
- target checker `baccb3f0d5aabc01a4984995fa59d62a1011cdb64982daf84937947a96da0092`;
- conversion discovery control `cc7fd00f869eba5d75861d7b4ff246b4f92221b7c6d530f033b611998bae7ef6`;
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

## Executable Review and Verification

`CARCHIVEBROWSER-TEST-001` remains covered by the verified provider-free Client
archive operation/use-case suites. Tests `-002` through `-011` now pass locally:

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
- exact READY checkpoint preservation through the local implementation.

The exact local results are 12/12 focused provider tests, 9/9 focused
AppModel/browser tests, and 494/494 complete Swift tests in 82 suites. A clean
local database reset and lint passed with zero findings; pgTAP passed 176/176
assertions overall including 53/53 Client archive assertions; all four local
Data API runners passed; target environment/contracts/read controls and both
staging builds passed. Root and independent executable review closed strict
replay/terminal linkage, canonical numeric parsing, missing-overlay Project
Setup admission, negative timestamp, principal binding, proof-matrix and
sensitive-logging defects; final review returned GO with no P0-P3.

`CARCHIVEBROWSER-TEST-012` remains planned until real isolated authenticated
PowerSync proves authorized row receipt and unauthorized local-row absence.
A-003/A-004 therefore remain proposed. Exact implementation commit
`f2b9945b163e8cf64561facb2e57b7cf54941b0b` passed all three immutable jobs in
Actions run `33976469527`, satisfying `CARCHIVEBROWSER-TEST-013` without
claiming the separate real authenticated Sync proof.

## Gate State and Permanent Exclusions

Exact READY commit `7187fa1e1415a0f820554e7f78cc62e1e42a34f4` passed all
three immutable jobs in Actions run `33968952286` before executable work. The
nine change-authorized READY leaves, bounded shared touchpoints and separately
registered runnable pgTAP leaf `CONFIG-86F1E734BC70` are now implemented and
locally verified. The inert `CONFIG-2DBC5A626444` `.sql.ready` marker was never
modified. Exact implementation commit `f2b9945b163e8cf64561facb2e57b7cf54941b0b`
passed all three immutable jobs in Actions run `33976469527` before this
evidence-promotion checkpoint.

This package does not implement or authorize Client restore/delete/rename/merge,
Project reassignment/deletion, cascade, accounting rewrite, preference behavior,
media deletion, target MCP, source transform, Firebase adapter/worktree change,
hosted resource, production access, migration, deployment, release or cutover.
It cannot advance A-003/A-004/A-007/A-015/A-016 or settle
O-023/O-024/O-025/O-040/O-042/O-043. Product specs and confirmed decisions remain
product authority.
