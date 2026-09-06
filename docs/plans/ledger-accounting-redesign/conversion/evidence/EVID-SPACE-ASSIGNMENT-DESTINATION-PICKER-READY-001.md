# EVID-SPACE-ASSIGNMENT-DESTINATION-PICKER-READY-001 — Provider-Backed Offline Picker READY Boundary

- Timestamp: 2026-09-05
- Class: reviewed READY design evidence; no executable implementation or hosted rehearsal
- Reviewed base: `ec5960efff4630c0e1fbe6e130e84a6adad715c1`
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6`; the Firebase worktree and released app were not opened or changed
- Target branch: `codex/supabase-powersync-implementation`
- Slice dossier: `conversion/implementation-slices/space-assignment-destination-powersync-picker.json`
- Verification state: the corrected comment-only candidate passed exact-head
  immutable CI at `5f3888b2` / run `33979632287`; a pre-implementation review
  then found one missing public-facade touchpoint, whose exact correction passed
  narrow independent review and awaits immutable CI before executable edits

## Outcome

The bounded next end-user slice is one provider-backed offline destination
picker: an isolated user opens an exact Project or Business Inventory scope,
sees honest local readiness/empty/failure state, browses active same-scope Spaces
in canonical order and may select one represented stable SpaceID. It deliberately
stops before Item selection or any Assign, Clear, Space create/update/archive,
MCP, source-data migration, hosted call, production access, Firebase change,
release or cutover behavior.

The six new Swift files contain comments only. READY freezes their future
provider/runtime/AppModel/view/test responsibilities plus the bounded physical
implementation touchpoints. It does not claim executable behavior, local or
hosted schema application, RLS enforcement, authenticated Sync, migration or
production authority.

## Authority and Existing Contract Preservation

Canonical authority is `docs/specs/spaces.md` section `Item Assignment`. It
defines exact Account plus Project-or-Business-Inventory scope, active-only
rows, stable Space identity/name/revision, deterministic order and distinct
authoritative-empty/incomplete/partial/stale/failure semantics. Cached scope and
revision support offline selection but never authorize.

This slice consumes, and does not reinterpret, the existing verified contract:

- `SWIFT-164554FA1456` —
  `LedgeriOS/LedgerTargetCore/SpaceAssignmentDestinationData.swift`;
- `TEST-A3D73145E3EC` —
  `LedgeriOS/LedgerTargetCoreTests/SpaceAssignmentDestinationDataTests.swift`;
- `EVID-SPACE-ASSIGNMENT-DESTINATION-001`; and
- `SpaceAssignmentDestinationQuerying.watchEligibleDestinations(_:)`.

At this READY checkpoint their SHA-256 values are respectively
`4ce6ea0cbdb263fe3d31bc811e448bc3486c7faa5ecaf7460f91822904da6121`,
`d41afcc7cb1ecab6a369401d84f98ae7255d57fae87da0c7a260b3144eac1573`
and `4dd3e452896ca782ee6cb7ea9daa9db9ff1651e861919da79469e4405017bb5a`.
Any change to those bytes is outside this slice and invalidates READY.

## Six-Axis Logical Authority Review

`TACCESS-14FBA8E573D3` / `TQUERY-A95F4BE0B9D8` maps to
`SWIFT-164554FA1456`, protocol `SpaceAssignmentDestinationQuerying`, selector
`watchEligibleDestinations`, review class `mapped`, signature hash
`1993ff350fadb2e748510c75e442be1313bc746efee28d6f08e0b7272e0a4052`
and mapping hash
`9a829702f2486506701159d54fcf32645f25d515dcc163bb71e90991c99b1596`.
All six axes are reviewed and `unresolvedAxes` is empty:

| Axis | Frozen authority |
|---|---|
| Authorization | Scope is selection evidence only and narrows an already-authorized local working set. |
| Ordering | Case-folded display name, exact display name, then stable Space ID ascending. |
| Pagination | Unpaged scoped destination observation. |
| Readiness | Authoritative empty, incomplete, partial, stale and failure are distinct. |
| Result | Only active destination Spaces with stable identity, normalized display name and revision. |
| Scope | Exact Account and exact Project-or-Business-Inventory placement scope. |

The proposed data domain remains
`project_workspace_or_inventory_by_immutable_scope`. The generated crosswalk's
physical planes remain `local: A-004/deferred` and
`postgres: A-003/deferred`; this package preserves those decisions as proposed.

## Frozen Provider-Backed Physical Boundary

Future implementation must be complete enough to be honestly provider-backed,
not merely a picker over injected rows:

- one pinned-CLI-generated, newly discovered, classified and claimed isolated
  Postgres migration at
  `supabase/migrations/20260905164622_space_assignment_destination_picker.sql`
  creates `spike_spaces` with stable identity, Account, conditional Project or
  Business Inventory scope, normalized representable display text, lifecycle,
  positive revision and exact scope/order indexes;
- authenticated gets SELECT only; PUBLIC/anon/authenticated direct writes are
  revoked; active-lifecycle plus active-membership Account-scoped RLS provides
  positive owner/admin/employee reads and fails closed for anonymous, revoked,
  cross-Account and archived-row callers;
- one newly discovered, classified and claimed runnable pgTAP leaf proves the
  schema, index, positive/negative RLS, direct-write denial and absence of Space
  or Item mutation surfaces;
- one disposable local Data API runner proves the same active-only visibility
  and direct-write denial through the exposed API rather than SQL alone;
- `powersync/sync-streams.yaml` gains separate on-demand active-Space streams
  for stable ProjectID and Business-Inventory AccountID. Each subscription
  parameter only narrows an authenticated active-membership join and downloads
  no unrelated Project, Item, archived row or upload surface;
- the local PowerSync schema mirrors only that read relation, and the
  module-internal provider owns the exact typed-scope Sync Stream subscription,
  combines row evidence only with that subscription's first-sync completion,
  and unsubscribes/joins it on replacement, cancellation and close; and
- a real authenticated PowerSync authorization/completeness/eviction round trip
  remains planned. Until it passes, A-004 and hosted readiness cannot advance.

This schema migration is an isolated target schema definition with no source
rows. Source-data migration, reconciliation and cutover remain excluded.
A-003/A-004 remain proposed because READY executes none of these files and
proves neither the target architecture nor hosted authorization.

## Local Read and Presentation State

The provider waits for initial evidence from both local rows and the exact
Project-or-Inventory subscription, so event arrival order cannot create a
transient false empty or false ready snapshot. Active exact-Principal/Account
membership is a local sentinel only. Missing, removed or rebound membership
clears prior rows and forces incomplete presentation even if an old subscription
finishes later. Generic connection or database sync status is never accepted as
query completeness.

The AppModel exposes waiting, partial, stale, ready nonempty, authoritative
empty and bounded failure as distinct tested presenter states. A user can select
only a represented stable `SpaceID`; display text and row position are never
identity. That transient selection is not an Item assignment draft,
current-placement fact, authorization grant or receipt. This slice does not
freeze unspecified production selection-retention or clearing policy.

## Frozen Surfaces and Shared Touchpoints

The six automatically discovered comment-only leaves are:

| Surface | Path | SHA-256 |
|---|---|---|
| `SWIFT-0A528DE84879` | `LedgeriOS/LedgerTargetPowerSync/SpaceAssignmentDestinationPowerSyncQuery.swift` | `d6230e3b529e2488b8c7193af42a64167d48f76380c8d8d923eacabfdd174faf` |
| `TEST-33BFA84BCBB2` | `LedgeriOS/LedgerTargetPowerSyncTests/SpaceAssignmentDestinationPowerSyncQueryTests.swift` | `83dfb2b2de07653f2f083587715b886eea7c82b08d67f2e82b78e50963104b37` |
| `SWIFT-62E2D7E9B40E` | `LedgeriOS/LedgerTargetAppModel/SpaceAssignmentDestinationStagingExercise.swift` | `10423903b300be66fab630cb5fbf9879e50216a4a13f0669073dc6710f6e5169` |
| `TEST-0126A06E52D0` | `LedgeriOS/LedgerTargetAppModelTests/SpaceAssignmentDestinationStagingExerciseTests.swift` | `295b1ef902e008b12bd81d16795cd490a56792d239c60285081035e6179c50af` |
| `SWIFT-698CCC538675` | `LedgeriOS/LedgerTargetApp/SpaceAssignmentDestinationStagingRuntimeAdapter.swift` | `506117fed436a09ac1fbd6278f4b6f8ab84232f93122d27e3bf741e721cf6e73` |
| `SWIFT-A1156933E12E` | `LedgeriOS/LedgerTargetApp/SpaceAssignmentDestinationStagingExerciseView.swift` | `a07520760bcf323c59def6167977f218c1dc006a587090fbcf112ef56f385745` |

The dossier freezes exact permitted changes to the local PowerSync schema,
Account-workspace runtime, public runtime facade and tests, staging composition,
environment checker, two scoped Sync Streams, conversion discoverer, package
command and CI job. The
future Postgres migration, runnable pgTAP and Data API runner paths are absent at
READY and must be machine-discovered, classified and claimed in the same
synchronized implementation checkpoint that creates them. No silent or
unclaimed physical leaf may advance.

## Required Implementation Proof

Implementation cannot advance beyond READY until evidence proves:

- Postgres conditional scope constraints, same-Account Project relationship,
  positive revision, exact lookup index and no mutation object;
- SELECT-only least privilege, active-lifecycle plus active-membership positive
  reads, anonymous/revoked/cross-Account/archived non-enumeration and direct-write
  denial through both pgTAP and a disposable scoped-user Data API runner;
- exact ProjectID and Inventory-AccountID subscription ownership, first-sync
  completeness and unsubscribe lifecycle plus a separately recorded real
  authorization/completeness/eviction rehearsal still planned for A-004;
- Project and Business Inventory encrypted local reads, canonical ordering,
  duplicate-name acceptance and atomic malformed/foreign/inactive refusal;
- both initial row/completeness event orders, reactive readiness changes,
  restart-incomplete behavior, membership-loss clearing, cancellation and full
  runtime/provider drainage;
- all six executable presenter/AppModel states, generation-safe request
  switching and represented-stable-ID selection without claiming unspecified
  production selection retention; and
- exact source/build boundaries proving no Item selection, Assign/Clear, Space
  mutation, MCP, hosted call, Firebase, source migration, production route or
  cutover behavior.

## Independent Review Corrections

The first actual-diff review returned NO-GO and the candidate was corrected
before commit:

- removed unsupported auto-selection and selection-retention/clearing policy;
- made archived rows non-enumerable through the Data API/RLS and added pgTAP
  plus disposable Data API proof obligations;
- froze the conversion discoverer, package command and CI job needed to discover
  and run the new physical leaves;
- replaced an injectable-only completeness placeholder with an owned exact-scope
  Sync Stream subscription and first-sync lifecycle;
- replaced Account-wide Space download with separate parameterized Project and
  Business Inventory subscriptions;
- generated the monotonic migration filename through pinned Supabase CLI 2.116.0;
- moved all six presentation states into executable presenter/AppModel proof and
  narrowed build evidence to compilation/source boundaries; and
- refreshed current 490/674 control-plane counts and completed Client Archive CI
  evidence.

A narrow re-review found one remaining rollout-boundary omission: its exhaustive
implementation sentence did not name every already-frozen physical and shared
touchpoint. The corrected contract now limits implementation to the six claimed
target leaves, the three absent-at-READY physical leaves and every exact shared
touchpoint in `implementationTouchpoints`. Final independent review returned GO.

After exact-head READY CI passed, pre-implementation source inspection correctly
refused an unsafe workaround: the Account-workspace actor is private behind
`LedgerOfflineClientRuntime`, so the thin staging adapter cannot reach a new
Space watch unless that public facade forwards it. The dossier now freezes
`SWIFT-548A8A928FAE` at exact hash
`6c4e4fa03f17e18c251af121668673f798258ee471874f5c24bab66cbd39d02d`
and permits only one Account-bound typed-scope forwarding method through the
existing tracked-stream lifecycle. No executable edit preceded this correction;
independent narrow review returned GO with matching stable ID, hash and scope.
Exact-head correction commit `9afda220` then passed conversion, local Supabase,
complete target tests and both staging builds in immutable run `33980882831`.

During executable implementation, the first staging build correctly failed
because the two already-claimed `LedgerTargetApp` leaves were not yet members of
the committed generated `LedgerTarget.xcodeproj`. The implementer stopped before
regenerating that project or duplicating the types into an already-compiled
file. The corrected boundary freezes shared generated surface
`CONFIG-2EBA890AF767` at SHA-256
`51404d6282d659bb452e8ca4d356159554459bd9f3d6b398ff490fb4acf14f8e`
and permits only deterministic regeneration from the unchanged
`LedgerTargetProject.yml` to compile those two claimed leaves. The target
identity, platforms, dependencies, build settings and scheme must remain
unchanged, `target-environment-isolation` retains primary ownership, and the
Firebase source project remains excluded. Claimed-leaf implementation was
already in progress when this generated-build dependency was discovered, but
no generated-project or workaround edit preceded the correction. Independent
narrow review recomputed the stable ID and hash, confirmed that the unchanged
project specification recursively includes `LedgerTargetApp`, found exactly the
two claimed picker leaves absent from the generated project, and returned GO:
only deterministic `project.pbxproj` source-membership regeneration is needed.

The complete conversion-control sequence then correctly refused the new
package/workflow integration because the source-query reconciliation checker
freezes both artifacts. The Space package had already authorized exactly one
new local Data API command and exactly one invocation in the existing isolated
Supabase CI job; neither change alters the 386-source-query authority. Before
changing the checker, this correction therefore adds shared control surface
`CONFIG-A8BD153106B8` at SHA-256
`4da9696b3c72f47bac70855a63365b4973b014c543c5e4df766f21ad29aa657e`
and permits only re-acknowledging those two exact integration fingerprints.
Every query count, reviewed mapping, closed schema, lifecycle rule, historical
checkpoint and fail-closed guard remains frozen. This is conversion-control
bookkeeping, not a product query or an Inventory-domain feature.

## Hard Boundary

No executable declaration was added in the six claimed leaves. Pinned Supabase
CLI 2.116.0 generated the future migration filename; the empty file was removed
and remains absent at READY. No SQL, RLS, grant, Sync configuration, local
schema, application runtime, hosted resource, production data, Firebase
worktree, migration data, branch/ref, commit or push was changed by this READY
package. The package authorizes only later isolated implementation after
the completed independent corrected-diff review and immutable READY-commit CI.
It does not
authorize a hosted call or promote A-003/A-004.
