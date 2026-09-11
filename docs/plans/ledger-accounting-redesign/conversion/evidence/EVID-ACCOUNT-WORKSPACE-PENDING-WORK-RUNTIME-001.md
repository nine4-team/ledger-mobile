# EVID-ACCOUNT-WORKSPACE-PENDING-WORK-RUNTIME-001 — Account Workspace Pending-Work Runtime

- Status: implemented, independently reviewed, and exact implementation CI passed
- Date: 2026-09-04
- Environment: isolated target worktree and disposable encrypted local fixtures only
- Production/Firebase impact: none
- Slice: `account-workspace-pending-work-runtime`

## Outcome

This package implements one bounded Account-workspace lifecycle owner over the
structured PowerSync database, separate encrypted attachment-queue database,
authenticated protected-byte vault, existing Client/Project stores and queries,
and the verified pending-work provider. Product callers receive one narrow
`LedgerOfflineClientRuntime`; they cannot construct or retain the concrete
database, key, store, query, vault, connector, or lifecycle resources.

The exact corrected READY commit
`15218cbbc44b7e7c28ef718c1770c7b6294a03c4` passed all three jobs in immutable
Actions run `33935937733` before executable work began.

Implementation commit `462b757606841a49d8b2812b98c13c273a0b7ca6` passed
the conversion-control and disposable-local-Supabase jobs in Actions run
`33939963766`. Its macOS job timed out in the complete Swift package gate after
four independent `.serialized` PowerSync/SQLCipher suites advanced together;
the log reported no assertion failure and killed the still-running
`swiftpm-testing` process at the 20-minute job boundary. Swift Testing
serializes within a suite, not across independent suites. Twenty consecutive
local parallel full-suite runs passed, an explicit process-wide nonparallel run
passed all 403 tests in 6.8 seconds, and independent diagnosis found no shared
fixture path or deterministic test failure. The workflow and its fail-closed
integration control now require `--no-parallel`; the focused tests still drive
simultaneous databases, operations, four watches, ABA callers and close callers
inside the production-relevant boundaries. Implementation and CI-harness
commit `f41a5ab78df1ec3cc9581fe8f4dad2083c8920f4` passed all three jobs in
immutable Actions run `33941609019`: conversion controls, the macOS target job
with the process-wide nonparallel 403-test gate and both staging builds, and
disposable local Supabase verification. Operational verification
`WORKRUNTIME-TEST-009` is therefore passed. Failed run `33939963766` remains
part of the evidence history rather than being replaced by the corrected run.

## Implemented Boundary

- Async bootstrap validates environment, Principal, Account, contained local
  locations, and separate Keychain identities before opening storage.
- The structured and attachment databases receive the same 32-byte SQLCipher
  key. The media vault receives a separate 32-byte key whose value must differ.
- The vault authenticates a scope-bound encrypted media-key sentinel during
  construction. A wrong media key therefore fails before a usable vault or
  runtime can escape, including when no attachment is currently read.
- Sentinel creation uses exclusive creation and rename, directory-relative
  validation, authenticated associated data, durable file/directory sync, and
  validation of a concurrent winner. Existing non-empty media directories
  without the sentinel fail closed instead of silently adopting a new key.
- Bootstrap opens the structured database, attachment database, then vault. A
  later failure releases any vault and attempts attachment-then-structured
  database close without deleting local data or keys.
- One actor owns every finite operation and all four Client/Project list/detail
  streams. Once close begins, new leases refuse; active streams are cancelled
  and drained, finite calls drain, both databases receive a close attempt, and
  one terminal outcome is retained for repeated close calls.
- Staging startup is reentrancy guarded, publishes a runtime only after its
  local diagnostics succeed, and closes a locally opened runtime after
  cancellation or any post-open failure.
- Ordinary close preserves both encrypted databases, protected media, queue
  evidence, and Keychain items. Reopening the identical scope recovers the
  same accepted local work.

## Compiler-Enforced Public Boundary

Swift access control makes the lifecycle owner and concrete factories, keys,
stores, queries, vault, and connector module-internal. The source guard is a
deterministic regression check, not the sole enforcement mechanism.

`swift package dump-symbol-graph --minimum-access-level public` independently
confirmed that none of the lifecycle-owned implementation types appear in the
`LedgerTargetPowerSync` public symbol graph. The public
`LedgerOfflineClientRuntime` surface is exactly:

- `createClient`, `watchClient`, `createProject`, and `watchProject`;
- `watchClients` and `watchProjects`;
- `pendingUploadCount` and `encryptionCipher` diagnostics;
- `captureAttachment` and `pendingWorkSummary`; and
- non-destructive `close`.

It exposes no public initializer, raw resource, session-ending choice,
synchronization, cleanup, signout, workspace switch, or backend selector.

## Independent Executable Review

The first executable review returned NO-GO on four concrete issues:

1. A wrong media key could survive bootstrap until a later byte read, allowing
   newly captured data to mix with media encrypted under another key.
2. Public concrete constructors allowed product code to bypass the lifecycle
   facade and retain databases/stores/queries independently.
3. Staging startup could reenter, and a failure after open could retain or leak
   the new runtime.
4. Tests did not drive real PowerSync watches and did not prove vault release
   plus valid recovery after every bootstrap-stage fault.

The corrected implementation added the authenticated media-key sentinel,
internalized every lifecycle-owned concrete provider, serialized and cleaned up
staging startup, and added real-watch, weak-vault, and full fault/reopen proof.

The final corrected-diff re-review returned GO with no P0-P3 finding. It found
no new security, durability, cleanup-order, or concurrency race in the
sentinel or runtime lifecycle.

## Local Verification

- 12 focused Account-workspace runtime tests pass.
- 13 attachment durability provider tests pass.
- 4 workspace-isolation tests pass.
- All 403 Swift tests in 73 suites pass.
- Twenty consecutive local parallel full-suite runs pass; one explicit
  process-wide nonparallel run passes all 403 tests in 6.8 seconds.
- The target environment guard, generated target contracts, 11 MCP tests, and
  `git diff --check` pass.
- The compiler public-symbol graph contains the narrow facade and excludes all
  lifecycle-owned implementation types.
- `LedgerTargetStaging` builds successfully for macOS and the generic iOS
  Simulator destination.
- Local Supabase database verification was not rerun in this shell because no
  disposable local Supabase database is listening on `127.0.0.1:54322`; exact-
  head Actions run `33941609019` started its own isolated local Supabase stack
  and passed that verification.
- Actions run `33939963766` proves its conversion-control and disposable-local-
  Supabase jobs. Its macOS test-process timeout is recorded as failed evidence,
  not promoted or silently retried.
- Exact-head Actions run `33941609019` proves all three jobs on
  `f41a5ab78df1ec3cc9581fe8f4dad2083c8920f4`, including 403 nonparallel Swift
  tests, both staging builds, clean generated artifacts, and disposable local
  Supabase checks.

## Frozen Affected Surfaces

Primary implementation leaves:

- `SWIFT-75CFE285AF37` — `AccountWorkspacePendingWorkRuntime.swift` —
  `608d3d9319cbcc3082dc750e36545f00da43825702d4639b3311ee38038da987`;
- `TEST-8D6A15063B2D` — `AccountWorkspacePendingWorkRuntimeTests.swift` —
  `f70ed4ea57e30cbc8287b097644b56881b19627b8dd453be92cd85045df47137`.

Affected/shared implementation surfaces retaining their existing primary
owners:

- `SWIFT-548A8A928FAE` — `LedgerOfflineClientRuntime.swift` —
  `20ccef5cbb04e905d113135b87b2bd22c38d75e0aa990021e7ba80faa4012b61`;
- `SWIFT-4E250D0D302E` — `LedgerWorkspaceRuntimeIsolation.swift` —
  `924538cf13c8e3e6e50c815065b178f95512492c0b26622693943cb9376ffb59`;
- `SWIFT-D9F0F491C95C` — `LedgerPowerSyncKeychain.swift` —
  `95d4c3f7f194302a5b8be469f80e0696259c00c47138c45a632512c819bae407`;
- `SWIFT-A9434A1623BC` — `LedgerPowerSyncDatabase.swift` —
  `52b7af7d80d7991ec2bffa06b9a6850cdda30ce2cc4389a012e3fa500dd38d47`;
- `SWIFT-F850F907B87F` — `AttachmentCapturePowerSyncStore.swift` —
  `38906911a9166a80aa28627d038795e6218d9447768fadbcc1a635cacde7b61a`;
- `SWIFT-68F4E18977D4` — `AttachmentLocalByteVault.swift` —
  `ce6e07ba93e35c45c85adc587a691ff9730809b6eb9c8112cb0f118b6f7bd210`;
- `SWIFT-2FAE0364C908` — `ClientCreationPowerSyncStore.swift` —
  `79fb9a8fe191c190101b600c312912562911c13126340ea58249c57752ce791b`;
- `SWIFT-5D88C2B47970` — `ProjectSetupPowerSyncStore.swift` —
  `d1e8cce89445e70d0b026a45e8e4a1893ecc69ae01baa5c633d862f0cf6af598`;
- `SWIFT-2ADDF7B64EA0` — `ClientCoreDetailsPowerSyncQuery.swift` —
  `23b7f779871cd613cc5a945449c3c24c167ea26260c2b9c37466234551a19745`;
- `SWIFT-56CB8BCDD85C` — `ProjectCoreDetailsPowerSyncQuery.swift` —
  `983e5d79a903893f509e3ac2caf4add5b90c15be794faa200f232325d8a08b09`;
- `SWIFT-B23F91245E50` — `ClientProjectDirectoryPowerSyncQuery.swift` —
  `49af060c1b8c9a1fc499a5f6b6b2c8e7de5eed8a69e57d60f212d7431fb24944`;
- `SWIFT-A9F7D22095F8` — `LedgerPowerSyncUploadConnector.swift` —
  `2e136d56055a91dbbe6bba5a8c500657e2c2acc47dfa8ab2bd862739f545daee`;
- `SWIFT-061553E63650` — `LedgerTargetStagingApp.swift` —
  `ed81e5d9171f89deafe255fcbfcd5d2f59c7ef152fece0c4f25762403b3fd839`;
- `TEST-CE5D3D0516D1` — `AttachmentDurabilityProviderTests.swift` —
  `859a45c76914eaa3a468beecf1c6f83cdf1af21ad2f73597077d31a05f12c041`;
- `TEST-5AAEE26660C8` — `ClientProjectDirectoryPowerSyncQueryTests.swift` —
  `581aa186a186005cee27690712b77d020027ccac5b2282c9344fa6c625c6e237`;
- `TEST-3FCFFC5C8AD8` — `LedgerWorkspaceRuntimeIsolationTests.swift` —
  `7604f6bcfcc6b85131b9595ca066cdc1bf18a1fc56a8c113ab8b5cd414ad79aa`;
- `CONFIG-81235587F306` and `FILE-A6E49E3815F4` —
  `scripts/check-target-environment.mjs` —
  `af4ccc5b6401059f2d26326127a7d482b265cf5383ad18d2008bf542dff965bd`.

`PendingWorkPowerSyncQuery.swift` remains byte-identical and retains its
verified primary ownership.

## Hard Boundary

This runtime is not `AccountSessionEnding`. It cannot synchronize or resolve an
operation, verify an upload, choose clean/sync-first/destructive disposition,
sign out a provider, switch an Account, delete or clean a queue/database/key/
file, choose retention, access hosted services, read or modify Firebase state,
migrate production data, release the app, or authorize cutover.

A-003 and A-004 remain proposed. A-007, A-016 and O-023 remain unadvanced. The
Supabase architecture remains a target implementation direction, not production
migration authorization.
