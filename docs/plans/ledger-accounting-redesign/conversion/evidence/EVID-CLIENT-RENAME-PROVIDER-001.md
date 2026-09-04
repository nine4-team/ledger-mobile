# EVID-CLIENT-RENAME-PROVIDER-001 — Client Rename Provider DRAFT

- Timestamp: 2026-09-04
- Class: reviewed design/DRAFT evidence; no executable implementation
- Reviewed base: `e6620875ef6a8c5488929972329545a2204750ed`
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the Firebase worktree and released app were not opened or changed
- Target branch: `codex/supabase-powersync-implementation`
- Slice dossier:
  `conversion/implementation-slices/client-rename-supabase-powersync-vertical-slice.json`
- Verification state: independent READY review rejected the first package;
  corrections are in progress and no commit, immutable run, executable rename
  behavior or hosted rehearsal exists

## Outcome

The smallest complete provider-backed Client rename boundary is drafted before
implementation. It reuses the verified provider-free command/use case and the
existing local Client/Project read foundations, then proposes one trusted target
mutation path through Postgres, encrypted PowerSync optimism, the isolated app
and gated MCP. It creates no Firebase adapter or second Client authority.

Independent review correctly found that the first READY draft inferred two
user-visible behaviors without canonical authority: whether archived Clients
may be renamed and how a same-value save affects result/revision. It also found
that the existing Swift `ClientDisplayName` admits U+0000 and has no shared
cross-runtime scalar/byte rule even though PostgreSQL text/jsonb cannot represent
NUL. O-042/O-043 now block READY and executable work. The review also corrected
restricted-member read expectations and required machine discovery for all nine
new leaves plus ordering-sensitive replay and unknown-result tests.

## Bounded Draft Contract

- Postgres reuses the one `spike_clients` row and immutable operation results.
  One auth-first, capability-checked, Account/Client-locked handler may update
  only current display name, revision and server update time.
- Client lifecycle, Account, identity, creation audit, Project rows and frozen
  Invoice/report/paid-history/audit snapshots are outside the mutation set.
  O-042 must decide archived eligibility and same-value result/revision behavior.
- Exact replay returns the immutable result, changed/cross-command replay cannot
  rebind, and true same-revision concurrency yields one apply and one durable
  conflict. Signed-bigint maximum rejects as exhausted rather than wrapping.
- The verified `UInt64` revision contract remains exact. Swift and MCP send the
  canonical command as text; MCP accepts decimal text and emits an unquoted
  integer token without JavaScript `Number`. Postgres validates the full
  `0...18446744073709551615` lexical/numeric range; values beyond signed storage
  cannot match an authoritative Client row.
- Local optimism uses distinct `spike_pending_client_renames` and
  `spike_client_rename_commands` tables. It never rewrites a synchronized Client
  row as local authority.
- Pending Client creation precedes rename in FIFO order. Multiple offline
  renames chain from the latest effective revision. A command using an older
  base revision refuses before local mutation. Local signed-bigint maximum
  rejects as exhausted, while a UInt64 expected revision above signed range is
  compared exactly as decimal command evidence but cannot match authority or
  create an overlay.
- Client and Project queries resolve one shared effective Client value. Pending
  rename evidence always makes the view partial. Rejection removes only the
  exact overlay; applied optimism remains until matching locally applied
  evidence and authoritative readback satisfy one of two cleanup conditions:
  authoritative revision is newer than the projection, or revision equals the
  projection and name bytes match. Stale readback cannot clear optimism.
- The app and MCP share the same command bytes, scoped-user RPC, terminal-result
  validation and privacy-safe identifiers after O-043 defines one exact accepted
  display-name boundary. No Client name, command JSON, token, key or service-role
  credential may be logged or accepted.
- Postgres implementation must preserve least privilege and indexed composite
  scope paths, hoist stable auth identity evaluation where the policy form
  permits it, keep the RPC transaction free of external I/O, and acquire result/
  Client locks in one documented deterministic order.

## Machine-Discovered DRAFT Scaffolds

All nine new leaves are stable, automatically discovered conversion surfaces in
`M0-CLIENT-RENAME-POWERSYNC-PROVIDER-001`:

| Surface | DRAFT path | SHA-256 |
|---|---|---|
| `SWIFT-5ABC145B2FAF` | `LedgeriOS/LedgerTargetPowerSync/ClientRenamePowerSyncStore.swift` | `e2c09d388dc6c734c08351da3153476ccfcbd46e1a02e0c842de02b059603db1` |
| `SWIFT-5CB20A965406` | `LedgeriOS/LedgerTargetPowerSync/SupabaseClientRenameRPC.swift` | `13255b9fdf010ea5b7ca3a39be692561e44eb3aef5046a1c56841c07ebb378a4` |
| `SWIFT-6816C6E0F96A` | `LedgeriOS/LedgerTargetApp/ClientRenameStagingExercise.swift` | `04171cd86ba08792967a334589d966812d62ac69d09fac3e668a2fbcb62a2186` |
| `TEST-77ABFEE573E1` | `LedgeriOS/LedgerTargetPowerSyncTests/ClientRenamePowerSyncVerticalSliceTests.swift` | `5373b887b621042e955748fa132f1a6f03375c52580651e1de18dc4762fe0520` |
| `MCPMOD-A23569C60118` | `LedgerTargetMCP/src/clientRename.ts` | `a2446da3a66b962eac540374d6a79f7c2ba300010cfb48e3cbdacc4846fee1a1` |
| `MCPMOD-EFFAAFBBD1AD` | `LedgerTargetMCP/tests/clientRename.test.ts` | `1213872f6c49a36d853bf2ee1322e10c3591b1ad0b2f70001ed55d9c3f92c155` |
| `CONFIG-EC93D3BAC0C4` | `supabase/migrations/20260904181245_client_rename_vertical_slice.sql` | `c82b363d7bf4f06bae01f5d1dcd7033f383de139a10fec430cc70cb2ab8e0090` |
| `CONFIG-3193C7F8A5F9` | `supabase/tests/client_rename_vertical_slice.test.sql` | `7a894a5aea85405a7f86bf0f2ace5f0abf48e83743ac3cf5f250f26e3eda7715` |
| `CONFIG-B3D8C4F9F504` | `scripts/test-local-client-rename-rpc.mjs` | `bb4eb534d3941a1fa95433959e1196e404dd567212464aa2277c2436a2b15b0e` |

The migration filename was created with
`npx --yes supabase@2.116.0 migration new client_rename_vertical_slice`; SQL was
not invented under an ad hoc timestamp. Root extended the existing explicit
configuration discovery list so the migration, pgTAP suite and local Data API
runner now fail conversion checks on unreviewed source drift.

## Shared Integration Dependencies, Not Duplicate Slice Claims

Implementation will require bounded reviewed edits to existing shared surfaces:

- `LedgerPowerSyncSchema.swift`, `LedgerOfflineClientRuntime.swift`,
  `LedgerPowerSyncUploadConnector.swift`, `ClientCoreDetailsPowerSyncQuery.swift`
  and `ProjectCoreDetailsPowerSyncQuery.swift`;
- `LedgerTargetStagingApp.swift`, `contractSupport.ts`, the generated contract
  catalog inputs/outputs and privacy-safe telemetry identifiers;
- `powersync/sync-streams.yaml`, `supabase/seed.sql`, root package/workflow test
  wiring and the existing Postgres operation-result constraint; and
- the new migration, pgTAP, local Data API, Swift provider/app/test and MCP
  leaves listed above.

Those existing files keep their current primary implementation slices and
statuses. The Client-rename dossier claims only the nine new leaves, preventing
duplicate ownership while requiring actual implementation evidence to record
every shared diff and rerun its existing Client/Project regressions.

## Required Negative and Fault Proof

Implementation cannot advance unless tests prove:

- exact and changed replay, lost response and parallel same-revision calls;
- missing Client, stale/future/out-of-signed-range revision and revision
  exhaustion without wrap;
- owner success; restricted-member rename/direct-write denial with existing
  same-Account read visibility preserved; revoked, anonymous, actor-mismatch and
  cross-Account non-enumeration;
- encrypted atomic acceptance and restart, pending-create FIFO, multiple rename
  chaining, stale-local refusal and exact queue/overlay linkage;
- transient retention, durable rejection isolation, applied-waits-for-readback,
  stale readback retention, exact/newer authoritative cleanup and no stale
  resurrection;
- the approved O-042 active/archived and same-value outcomes with lifecycle,
  Project and frozen-history scope unchanged;
- exact Swift/MCP/Postgres bytes across JavaScript safe-integer and signed/UInt64
  boundaries plus approved O-043 whitespace/control/NUL/Unicode/UTF-8 fixtures,
  scoped credentials and privacy-safe telemetry;
- exact replay after a later chained overlay and after pending-create successor
  state, plus fail-closed unknown result/error codes;
- indexed membership/capability/Client/Project/result paths, bounded transaction
  scope and deterministic lock order under replay and same-Client concurrency; and
- unauthorized Sync rows absent locally, not merely hidden by an app query.

## Prior Author Validation and Required Revalidation

Before independent rejection, the uncommitted draft passed these local gates on
2026-09-04:

- conversion sync/check/report and M0, residual, capability, Firestore-query,
  target-query-port, target-query-authority and source-query-reconciliation
  controls; the conversion ledger retained only its three pre-existing retired-
  path warnings (`FILE-9F65BB694716`, `SWIFT-FE0D03920D59`, and
  `TEST-16A01A0FF3D5`);
- target environment and generated-contract checks, strict target MCP typecheck,
  11 MCP tests, and all 342 Swift package tests in 68 suites;
- isolated target macOS and generic iOS Simulator staging builds;
- a disposable local Supabase start/reset applying all three migrations, database
  lint at warning-as-error for `public,ledger_private`, and 42 pgTAP tests across
  the existing Client-create/Project-setup suites plus this DRAFT placeholder;
  and
- existing local Client-create and Project-setup Data API RPC regressions.

The local stack was stopped without backup after validation. These checks prove
that the original scaffolds did not execute Client rename behavior; they do not
prove the corrected DRAFT. Root must rerun every applicable control after hash,
authority and discovery synchronization.

`LedgerTargetProject.yml` already includes the `LedgerTargetApp` directory, but
the checked-in generated Xcode project predates the new comment-only app leaf.
The prior build therefore does not claim that leaf as compiled app behavior.
When implementation replaces it with Swift code, the bounded diff must regenerate
the project and rerun both builds so the executable leaf is actually linked.

## Explicit Exclusions and Gates

- A-003/A-004 remain proposed. Local evidence cannot approve Supabase or
  PowerSync architecture, Auth bridging, hosted Sync, deployment or cutover.
- Permanent authorization loss for a previously queued command remains a shared
  connected-phase policy gate; this DRAFT package does not weaken authorization
  or invent silent discard.
- Full frozen-history tables are not present in the spike schema. The local
  handler test must prove its exact mutation set now; later Invoice/report/
  paid-history slices must repeat the non-rewrite test when those tables exist.
- No Client delete/merge/reassignment/archive mutation, production Client UI,
  migration correlation, source import, Firebase change, hosted operation,
  production access, release or authority switch is included.

No executable Client rename behavior was added at this checkpoint.
