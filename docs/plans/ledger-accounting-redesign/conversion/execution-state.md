# Supabase Conversion Execution State

Last updated: 2026-09-06
State version: 332

## Objective

Create a complete, evidence-backed backend surface map and Supabase/PowerSync
target mapping for the entire Ledger application, then implement and rehearse it
without modifying the running Firebase application before hard cutover.

## Current Checkpoint

- Phase: provider-backed target implementation is active after the completed
  backend-surface mapping, architecture, and provider-free foundation work
- Checkpoint: POWERSYNC-WATCH-LIFECYCLE-CORRECTION-EXACT-CI-VERIFIED
- Branch: `codex/supabase-powersync-implementation`
- Source commit: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6`
- Worktree: dedicated conversion branch/worktree. The current Firebase release
  baseline is committed and shared by `firebase` and `main`; conversion planning,
  architecture, control, and evidence remain isolated on this branch.
- Production export: profilers and artifact format are ready; execution is
  blocked on an acceptable external project-matching service-account key or a
  separately proven canonical immutable production export. Existing local
  `firebase-export*` directories do not have sufficient recorded provenance to
  promote silently.
- Production mutations authorized: no.
- Supabase/PowerSync implementation authorized: isolated local provider slices,
  target app/MCP integration, and test infrastructure on this branch. Hosted
  resources, production data access, migration, cutover, and production
  authority remain gated. A-003/A-004 remain proposed pending the complete
  vertical-spike exit gate.

## Program Progress Basis

- Planning/control coverage is **531 of 721 target-relevant surfaces mapped or
  later (73.6%)**. Local surface-implementation coverage is **229 of 721
  implemented or later (31.8%)**. The dedicated Project category-configuration
  revision adds two implemented leaves but no new provider-backed workflow,
  hosted-rehearsal or cutover-ready credit.
  These are repository-surface measures, not percentages of shipped app
  behavior or elapsed implementation time; the implemented/verified numerator
  includes provider-free contracts and technical controls.
- Ten provider-backed product workflows have working local behavior after the
  current slice: four mutations and six reads. Forty-seven additional product
  slices are verified provider-free contracts, not shipped workflows. Hosted
  authenticated Supabase/PowerSync rehearsal remains zero, and both rehearsed
  and cutover-ready surface counts remain zero.
- The previous rough 15–20% end-to-end estimate is retired because repository
  surfaces do not weight product complexity and repeating it obscured real
  movement. Progress reports must use the exact four lanes above; a new overall
  percentage may be introduced only with a checked-in weighted scope model.
- The implementation tracker currently contains 279 status-bearing rows: 68
  done, eight verified, 12 implemented, zero ready and zero awaiting verification,
  12 in progress, 27 design, 60 blocked, 90 not started, and two existing rows. Most completed rows are
  architecture, conversion controls, or provider-free foundations; they are
  prerequisites, not migrated features.
- Ten provider-backed product slices have working local behavior: Client
  creation, Project setup, Project archive and Client archive through their
  browsers, the Client/Project directory, Principal-scoped Account discovery,
  the exact Project-or-Business-Inventory Space destination picker, and the
  derived same-Client Transfer destination picker, Project note-history
  continuity across Project archival, and one exact active/archived Space
  core-details read. Four are mutation workflows and six are
  reads. Client creation and Project setup have local
  identity, ordinary-name command, encrypted-offline, RLS, replay and readback
  mechanics; Project archive has the corresponding lifecycle/revision command,
  optimistic overlay and reconciliation mechanics; Client archive adds the
  corresponding Client lifecycle, dependency and Project-setup interlock. O-043 correctly gates final Client-name
  submission parity for Client creation and only the new-Client Project branch;
  current Swift, MCP and PostgreSQL validators disagree on edge inputs, so the
  ordinary-name fixture is not final validation evidence. The exact Project
  archive and Client archive implementation checkpoints pass immutable CI. Both
  archive slices remain incomplete until a real isolated PowerSync/Auth round-trip passes. Account
  discovery is intentionally local-only and cannot advance beyond implemented
  until safe hosted identity bootstrap and authorization are proven.
- One supporting provider slice now durably accepts encrypted attachment bytes
  offline in an isolated, scope-bound local PowerSync database and passes exact
  immutable CI. It is not yet an upload/display product path and does not
  advance the physical hosted media spike.
- Future progress reports must separately state (1) planning/control coverage,
  (2) locally executable provider-backed slices, (3) hosted rehearsal, and
  (4) cutover readiness. A single percentage may be given only with that
  denominator stated.

## Corrected at This Checkpoint

- Corrected the implementation tracker's stale Space core-details row from
  `ready`/comment-only to the already-proven `implemented` state. The owning
  evidence and this execution state already recorded exact implementation
  `a1be2ffd` / immutable run `34003366795`; this is bookkeeping reconciliation
  only and does not add an eleventh product workflow or advance hosted/cutover
  readiness.

- Implemented `project-category-configuration-revision-foundation` from frozen
  READY `dec9a5703fc9d723d02f60ff6b1037f2db8e9dd2`. Every synthetic target
  Project now has an independent exact numeric full-`UInt64` configuration
  revision defaulted/backfilled to 1; both existing Project Sync queries project
  canonical decimal text; authoritative and pending SQLite columns store text;
  and offline Project creation writes projected 1 in its existing complete-
  aggregate transaction. Two independent reviews initially rejected weak
  creation/backfill, access, Sync-scope, restart and rollback proof. After two
  correction rounds, both returned GO with no P0-P3 findings. Local 33/33
  focused and 373/373 complete pgTAP, 10/10 focused and 566/566 complete Swift,
  strict database lint, MCP/contracts and the exact normalized Sync/config guard
  and both staging builds pass. Exact implementation
  `ac9fdcd4bb43c979526503862d715de61a9ee4e6` passed all three jobs in immutable
  run `34011514963` attempt 2. Attempt 1 timed out during target-test shutdown
  after green conversion and local-Supabase jobs; the unchanged rerun passed,
  and the separately owned directory-watch lifecycle defect exposed by the
  nondeterminism is corrected below. Six provider/app leaves remain comment-only under O-026; real
  hosted Auth/Sync, A-003/A-004/A-015, Firebase, migration, production and
  cutover remain unadvanced;
  `EVID-PROJECT-CATEGORY-CONFIGURATION-REVISION-001`.

- Corrected Client/Project directory and core-details watch ownership after the first attempt of
  run `34011514963` exposed a nondeterministic target-test process shutdown. The
  directory provider now registers every Client/Project watch before execution, rejects
  watches after close begins, cancels each admitted outer task, and joins its
  database and completeness observations before runtime database close. Direct
  Client archive, Project archive, Transfer destination and directory tests now
  retain and explicitly drain the shared query. The first independent review
  found one P1 test-lifecycle hole in two anonymous malformed Project-archive
  watches; both were corrected to reuse a retained query and drain on every
  later close path. Re-review returned GO with no P0-P3. Local 17/17 directory,
  8/8 Project archive and 567/567 complete Swift tests, conversion controls,
  target-environment checks, MCP/contracts and both staging builds pass. The
  directory-only checkpoint `b4bcbe8c` then repeated the CI timeout in run
  `34013428800`, proving the initial diagnosis incomplete. A fresh independent
  audit found the same unjoined-task flaw in both core-details providers plus
  archive/direct-test helper close paths. Both detail providers now own
  cancel-and-drain registries; runtime close joins them before the directory,
  archive stores and database; and retained helpers drain on success, expected
  error and assertion-return paths. Final review returned GO with no P0-P3
  after one stale-count correction. Local 62/62 affected and 569/569 complete
  Swift tests, full conversion/query controls, 26 MCP tests and both builds pass.
  Exact corrected commit `758afefb6302cc44a4909262e9050ad93ba25dc7`
  passed all three jobs in immutable run `34014750385`: conversion in 42 seconds,
  local Supabase in 2 minutes 2 seconds, and the isolated target environment in
  7 minutes 55 seconds. The complete target tests exited normally before both
  staging builds, closing the CI-only teardown defect. No SQL/query result/product policy,
  Firebase, hosted, migration, production or cutover behavior changed;
  `EVID-CLIENT-PROJECT-DIRECTORY-PROVIDER-001`.

- Implemented `space-core-details-powersync-provider` from frozen READY
  `9b62bec1403261a7d966c570af981da461d80f12`. Eight claimed leaves now provide
  separate relational detail/checklist read tables with forced RLS and no client
  grants, one exact signed active/archived Space stream, positive signed-bigint
  revision transport, causal encrypted local completeness, close-aware runtime
  ownership, exhaustive Core-only presentation and isolated staging. Independent
  review rejected an unapproved timestamp-order constraint, expanded the
  privilege proof to all table privileges, then found missing real encrypted
  restart/startup/invalidation coverage and progress counts rendered from
  incomplete evidence; all four defects were corrected. The existing
  seven-column active-only destination rows/Data API/grant/policy/streams remain
  unchanged. Local pgTAP, Data API regression, database lint, provider/runtime/
  AppModel/complete Swift suites, target controls and both builds pass. Exact
  implementation `a1be2ffd` passed all three jobs in immutable run
  `34003366795`; real authenticated PowerSync remains pending. A-003/A-004/A-016
  and O-023/O-026/O-037/O-044/O-045/O-046 remain unadvanced; broad Space UI,
  every writer/archive effect, Items, media, templates, accounting, MCP, hosted,
  Firebase, migration, production and cutover remain excluded;
  `EVID-SPACE-CORE-DETAILS-PROVIDER-001`.

- Implemented the ten-leaf Project archival-review delivery batch from frozen
  READY `1e893c6c02dc22a52cb1332e3a98a26c714d5fba`. It now provides forced-RLS
  Project-note reads, complete exact-Project on-demand Sync, causally fresh
  encrypted keyset pages, active/archived browser continuity, byte-identical
  preservation through the existing archive command, and gated unregistered
  MCP read/archive parity. Three independent reviews found and drove fixes for
  causal freshness, cancellation disclosure, archive-watch drainage, stale
  selection, authoritative empty, Unicode validation parity, HTTP failure
  classification, local keyset indexing, MCP non-registration and combined
  archive continuity. All 546 Swift tests in 88 suites, 256 pgTAP assertions,
  26 MCP tests, eight local Data API/RPC runners, database lint, target controls
  and both staging builds pass locally. Corrected exact implementation
  `7d42bad01aa5473750d212a631158b079629d3d6` passed all three immutable jobs in
  run `33998369665`. Only the real authenticated PowerSync authorization/
  revocation rehearsal remains planned, so A-003/A-004 stay proposed and no
  hosted, Firebase, migration,
  production or cutover authority advances;
  `EVID-PROJECT-ARCHIVAL-REVIEW-PROVIDER-001`.

- Corrected the blocked Space-create DRAFT's repository-wide pgTAP integration.
  Initial commit `2cf4bdb2` passed conversion and target jobs but immutable run
  `33988334645` failed the local Supabase job because the entirely comment-only
  `.test.sql` leaf emitted no TAP plan. The leaf now contains one passing runner
  placeholder and zero Space assertions; its classification/evidence no longer
  calls it comment-only. Database lint, all 211 local pgTAP checks, the Space
  destination Data API matrix and both existing RPC runners pass. Exact-head
  correction evidence is immutable run `33999054644`, where all three jobs
  passed at `42d484cf`.

- Implemented the six-leaf target-local Transfer destination picker from exact
  green READY `2f87445cd51d6911a0655ad611fdedf035246665` / immutable run
  `33989797244`. It reuses `TQUERY-2D53E545A090`,
  `TACCESS-626ED0857269` and the existing encrypted Project-directory provider
  without SQL, schema, RLS, Sync Streams, completeness sources, storage, upload,
  MCP or write behavior. Independent executable review first returned NO-GO and
  forced literal encrypted retained-row and retained-empty restart proof,
  consumer-cancellation drainage, and destination removal/reappearance without
  selection resurrection. Corrected re-review returns GO with no P0/P1.
  Automated provider/runtime and AppModel behavior, target boundaries and both
  builds pass; compilation is not claimed as interactive UI rendering proof.
  Exact implementation `1e893c6c02dc22a52cb1332e3a98a26c714d5fba`
  passed all three immutable jobs in run `33992331027`, including 522 Swift
  tests and both builds. Source-action eligibility, Items,
  amount, confirmation, Transfer execution/accounting and
  O-002/O-011–O-015/O-025/D-017 remain outside;
  `EVID-TRANSFER-DESTINATION-PICKER-PROVIDER-001`.

- Audited provider-backed direct Space creation before implementation and
  stopped it at DRAFT after independent review found three missing product
  authorities: exact cross-runtime Space name/notes acceptance, command-specific
  writer authorization, and archived-Project parent eligibility. O-044/O-045/
  O-046 and one combined decision packet now own those choices. Eleven
  machine-discovered comment-only target leaves, one pgTAP runner placeholder
  with no Space assertion, a full verification matrix and
  every shared implementation touchpoint are recorded; none executes Swift,
  TypeScript, SQL, a Data API request or a test. Immediate destination-picker
  readback is explicitly partial, exact Principal/Account/scope-bound and causal:
  membership loss cannot be bypassed, result arrival cannot clear optimism before
  authoritative row readback, and durable rejection removes only matching work.
  Broad source Space UI/CRUD surfaces remain mapped rather than falsely advanced;
  `EVID-SPACE-CREATION-PROVIDER-READY-001`. The next selected candidate is the
  provider-backed Transfer destination picker derived from the already-verified
  local Project directory, because its mapped query has no unresolved logical
  axis and requires no schema, handler, RLS, Sync, upload or MCP change.

- Implemented the provider-backed offline Space assignment-destination picker
  from exact green READY commit `5f3888b2` plus public-facade correction
  `9afda220`. Nine claimed target surfaces now provide additive SELECT-only
  Postgres/RLS, exact Project/Inventory on-demand Sync Streams, encrypted local
  PowerSync observation, Core-only presentation, a thin runtime adapter and an
  isolated staging picker. Independent review repeatedly returned NO-GO until
  retained PowerSync epochs, delayed-row causality, ready/completeness
  coherence, raw-name preservation and subscription lifetime were corrected.
  The final database and Swift reviews return GO with no remaining P0-P3.
  Fourteen focused provider tests, all 512 Swift tests in 84 suites, all 210
  pgTAP assertions including 34 Space assertions, local Data API denial/read
  proof, zero database-lint errors, target controls, deterministic project
  generation and both staging builds pass locally. Exact implementation commit
  `f89e9bda2c7b7192de41a85bbc586cff2519336b` passed all three immutable jobs in
  run `33985685659`. TEST-012 real authenticated
  PowerSync remains planned; A-003/A-004 remain proposed; no hosted, Firebase,
  source-data migration, production, release or cutover action exists;
  `EVID-SPACE-ASSIGNMENT-DESTINATION-PICKER-PROVIDER-001`.

- Prepared the comment-only READY candidate for the provider-backed offline
  Space assignment-destination picker. Six automatically discovered target
  leaves reserve the PowerSync query/tests, Core-only AppModel/tests, thin
  runtime adapter and isolated staging picker without executable declarations.
  Canonical `spaces.md#Item Assignment`, `TACCESS-14FBA8E573D3` /
  `TQUERY-A95F4BE0B9D8`, verified `SWIFT-164554FA1456` /
  `TEST-A3D73145E3EC` and its unchanged evidence freeze all six logical axes:
  already-authorized local scope only, name/name/ID ordering, unpaged shape,
  distinct authoritative-empty/incomplete/partial/stale/failure, active stable
  ID/name/revision result and exact Account plus Project-or-Business-Inventory
  scope. `unresolvedAxes` is empty. The corrected physical contract is not a
  synthetic-row-only picker: future implementation must create, discover,
  classify and claim the pinned-CLI-generated `spike_spaces` active-only SELECT/
  RLS migration, runnable pgTAP leaf and disposable Data API runner; add separate
  exact ProjectID and Inventory-AccountID on-demand Sync Streams; then implement
  subscription-first-sync completeness, encrypted local membership-loss/restart/
  cancellation/drainage and presenter-tested represented-SpaceID selection. The
  package deliberately does not freeze unspecified production selection-retention
  policy. The six new mapped leaves
  increase target-relevant inventory from 668 to 674 and mapped-or-later from
  484 to 490; implemented-or-verified remains 194 (28.8%). A-003/A-004 remain
  proposed because this package executes no SQL/Sync/provider/app behavior and
  proves no hosted authorization. Item selection, Assign/Clear, Space create/
  update/archive, MCP, source-data migration, hosted calls, Firebase, production,
  release and cutover remain excluded;
  `EVID-SPACE-ASSIGNMENT-DESTINATION-PICKER-READY-001`.
  The first independent review rejected eight authority, security, discovery,
  scope, migration and test-proof gaps. After correction, a narrow re-review
  found one remaining rollout-boundary omission; that was corrected, and final
  independent review returned GO with no remaining finding.
  Exact-head READY commit `5f3888b2` passed all three jobs in immutable run
  `33979632287`. Pre-implementation source inspection then found that the public
  `LedgerOfflineClientRuntime` facade, which privately owns the Account-workspace
  lifecycle actor, was missing from the frozen touchpoints. No executable edit
  or workaround was made. The correction freezes `SWIFT-548A8A928FAE` at its
  exact READY hash and permits only one typed-scope forwarding watch through the
  existing tracked-stream lifecycle. Narrow independent review recomputed the
  stable ID/hash, confirmed necessity/minimality and returned GO; exact-head CI
  run `33980882831` then passed conversion, local Supabase, complete target
  tests and both staging builds at correction commit `9afda220`. During the
  subsequent executable implementation, the first staging build correctly
  found that the two claimed target-app leaves were not members of the committed
  generated target Xcode project. The implementer stopped before regenerating
  it or duplicating types into an already-compiled file. The dossier now freezes
  shared generated surface `CONFIG-2EBA890AF767` at its exact pre-regeneration
  hash and permits only deterministic regeneration from the unchanged target
  project specification to add those claimed leaves. Claimed-leaf executable
  work was already in progress, but no generated-project or workaround edit
  preceded this correction. Independent narrow review recomputed the stable ID
  and hash, verified that the unchanged project spec recursively includes the
  App directory and found exactly the two claimed picker leaves absent; it
  returned GO for project-only deterministic regeneration.

- Implemented archiving one currently observed active Client through the isolated
  Client browser after exact READY commit `7187fa1e` passed immutable Actions
  run `33968952286`. Nine executable READY leaves plus runnable pgTAP identity
  `CONFIG-86F1E734BC70` now provide generic Account-bound archive identity,
  encrypted atomic operation/command/overlay acceptance, exact replay, terminal-
  evidence validation, dependency-aware FIFO upload, principal-bound lifecycle
  projection through every shared Client consumer, Project-setup replay-before-
  overlay admission, Core-only browser orchestration, scoped-user RPC and an
  auth-first Postgres handler. Server Client archive and existing-Client Project
  setup serialize through the same Client-row lock, preserving earlier Projects
  and durably rejecting post-archive creation without deadlock. Runnable pgTAP
  replaces but does not delete byte-identical inert marker
  `CONFIG-2DBC5A626444`; every database-test owner names `.sql`, while package.json
  and PowerSync Sync Streams remain unchanged. Root and independent executable
  review drove corrections for strict replay/terminal linkage, canonical numeric
  parsing, missing-overlay Project Setup admission, negative timestamp, principal
  binding, proof completeness and sensitive logging; final review returned GO
  with no P0-P3. All 21 focused and 494 Swift tests in 82 suites, 176/176 pgTAP
  including 53/53 Client archive, zero database-lint findings, four Data API
  runners, target controls and both staging builds pass locally. Exact counts are
  194/668 implemented-or-later (29.0%) and 484/668 mapped-or-later. The
  exact implementation commit `f2b9945b` passed all three immutable jobs in
  Actions run `33976469527`. TEST-012 real authenticated PowerSync remains
  pending; A-003/A-004 stay proposed.
  O-023/O-024/O-025/O-040/O-042/O-043 remain unadvanced; no target MCP, hosted,
  Firebase, migration, production or cutover authority exists;
  `EVID-CLIENT-ARCHIVE-BROWSER-PROVIDER-001`.

- Implemented archiving one active Project through the verified local browser
  after exact READY commit `089dc562` passed immutable Actions run
  `33961281661`. Nine claimed executable leaves now bind explicit confirmation
  to exact current Account/Project/lifecycle/revision evidence, make cancel and
  stale confirmation zero-call, accept one Account-bound operation/command/
  lifecycle overlay atomically without network, project the stable Project
  Active→Archived as honest partial local evidence, survive encrypted restart,
  upload FIFO after pending Project creation, replay exactly, recover rejected
  work through refreshed evidence/new identity, and clear optimism only after
  qualifying authoritative readback. The auth-first Postgres handler verifies
  actor, active membership and Project-management capability before identity/
  result/subject disclosure, enforces an Account-bound archive OperationID
  namespace, locks deterministically and mutates only lifecycle, revision,
  server time and immutable terminal result. Runnable pgTAP identity
  `CONFIG-CAB6A5DAD1C0` is registered/classified/claimed; byte-identical inert
  READY marker `CONFIG-062839A9903C` is retired in place, every owner names the
  runnable `.sql`, and package.json plus PowerSync Sync Streams remain unchanged.
  Root and independent review drove corrections for identity enumeration,
  request replay binding, overlay/command validation, device-clock regression,
  browser selection/retry ownership and observer drainage; final review returned
  GO with no P0-P3. All 28 focused and 473 Swift tests in 80 suites, 123/123
  pgTAP including 81/81 archive, zero database-lint findings, scoped Data API,
  target checker, XcodeGen and both staging builds pass locally. The exact count
  advances from 175/658 to 184/658 implemented-or-verified (28.0%);
  mapped-or-later remains 474/658. Exact implementation commit `939d7453`
  passed all three jobs in immutable Actions run `33966132401`. TEST-012 real
  authenticated PowerSync, restore/delete/rename/details/
  Client reassignment/media/target MCP/Auth/hosted/Firebase/migration/production/
  cutover remain excluded; A-003/A-004 remain proposed;
  `EVID-PROJECT-ARCHIVE-BROWSER-PROVIDER-001`.

- Verified the Client-browsing staging application flow after exact
  comment-only READY commit `db89ef36339f48bff249b2973ea3bc9c5607bb61`
  passed all three immutable jobs in run `33956835407`: conversion in 38
  seconds, disposable local Supabase in 1 minute 41 seconds and isolated target
  in 6 minutes 40 seconds. Six claimed leaves advance the exact count from
  169/649 (26.0%) to 175/649 (27.0%); mapped-or-later remains 465/649 and the
  tracker remains 272 status-bearing rows. A pure Core presenter atomically
  projects active/archived Clients in upstream order, binds stable selection to
  exact current evidence and preserves every detail readiness/failure/audit/
  revision state. A Core-only observable model, thin runtime adapter and typed
  SwiftUI view compose those contracts without replacing Client creation's
  post-create one-shot confirmation. Root review hardened exact adapter/view
  containment, staging wiring, accessibility IDs, both cleanup orders and
  confirmation preservation. It also strengthened rapid reselection with a
  delayed noncooperative A source and added direct proof that stop joins both
  active directory and detail observations. Independent executable review
  returned GO with no P0-P3. Fourteen focused and all 455 nonparallel Swift
  tests in 78 suites, 42 local pgTAP checks plus Client/Project RPC checks, a
  clean local-stack stop, exact controls, repeatable generation and both staging
  builds pass. Exact implementation commit
  `872e7fc990dba23a5ebaaa3ab7662ba5e5806886` passed all three immutable jobs
  in run `33958657934`: conversion in 37 seconds, disposable local Supabase in
  1 minute 44 seconds and isolated target in 5 minutes 33 seconds. The slice
  and six leaves are verified. Related
  Projects, sort/search/cards/routes, raw-name input, mutation, provider/schema/
  RLS/Sync/MCP/Auth/hosted/Firebase/migration/production/cutover remain excluded;
  `EVID-CLIENT-BROWSING-STAGING-APPLICATION-FLOW-001`.

- Implemented the Project-browsing staging application candidate after exact
  comment-only READY commit `90874031` passed all three immutable jobs in run
  `33953298649`. Four claimed leaves now advance the exact implementation count
  from 165/643 (25.7%) to 169/643 (26.3%); mapped-or-later remains 459/643 and
  the tracker remains 271 status-bearing rows. A Core-only observable model,
  thin runtime adapter and typed SwiftUI view replace the staging shell's inline
  Project directory projection, stable-ID selection and detail observation.
  Thirteen focused and all 441 Swift tests in 76 suites, exact target controls,
  MCP tests and both staging builds pass locally. Root review added active-
  detail drainage and newer-detail-name semantics. Independent executable
  review caught false numeric-zero counts before represented evidence, missing
  reciprocal source-exhaustiveness proof and missing noncooperative late-detail
  restart proof; all were corrected and final re-review returned GO with no
  P0-P3. Exact synchronized implementation commit `547af4d7` then passed all
  three immutable jobs in run `33954955566`: conversion control in 41 seconds,
  disposable local Supabase in 1 minute 36 seconds, and the isolated target
  environment in 5 minutes 56 seconds. Exact docs-only promotion `4b9aecae`
  then passed all three immutable jobs in run `33955342320`, marking the slice
  verified without changing executable behavior. Full Project shell,
  schema/RLS/Sync/MCP changes, hosted resources, Firebase, migration, production
  and cutover remain unadvanced;
  `EVID-PROJECT-BROWSING-STAGING-APPLICATION-FLOW-001`.

- Verified existing-Client Project Setup after exact READY commit
  `bc2de1ba` passed all three jobs in run `33949737440`. A Core-only observable
  AppModel, thin runtime adapter and dynamic staging form now combine independent
  Client/category evidence, preserve ready/partial/stale plus false-empty truth,
  avoid all default selection, admit zero or selected-null categories, and
  submit only through the verified setup use case. Executable review found and
  drove corrections for a regenerated retry timestamp that changed the
  PowerSync fingerprint, missing failure proof, unbounded test waits, and stale
  submission after invalid newer evidence. Final re-review returned GO with no
  P0-P3. Nine focused and all 428 Swift tests in 75 suites pass locally. Exact
  implementation `2dc519e6` passed all three immutable jobs in run
  `33951550789`: conversion controls, disposable local Supabase schema/RLS/RPC
  checks, the complete nonparallel target suite, both staging builds and clean
  tracked artifacts. Exact promotion commit `1428f533` also passed all three
  jobs in run `33952081491`. A duplicate same-head dispatch
  (`33952088099`) timed out before the first Account-workspace-isolation test;
  it remains recorded as a CI flake rather than being misreported as product
  failure because the exact same commit's complete immutable run is green and
  the complete 428-test suite passes locally.
  O-043/O-026/O-040, hosted/Auth/media/MCP/schema/RLS/Sync, Firebase, migration,
  production, release and cutover remain unadvanced;
  `EVID-PROJECT-SETUP-APPLICATION-FLOW-001`.

- Implemented the local budget-category reference provider after exact READY
  commit `8eafd6c9` passed all three jobs in immutable run `33943581567`. One
  module-internal PowerSync query now maps every already-materialized category
  field without interpreting visibility, binds exact Account/Principal scope,
  remains incomplete by default, reacts to explicit completeness and live
  membership loss, preserves encrypted rows across restart, and exposes only
  `watchBudgetCategories()` through the Account-bound runtime. The first
  executable review returned NO-GO because runtime drainage did not join the
  provider-owned database/completeness observers and the reciprocal version and
  cancellation tests were incomplete. The corrected provider owns a race-safe
  watch registry, joins both observations, and runtime close awaits that
  module-internal drain before either database closes; the shared touchpoint was
  explicitly refrozen to authorize this internal lifecycle obligation without
  adding a public shutdown API. Corrected-diff review returned GO with no
  remaining P0-P3 finding. Implementation checkpoint `376685f5` did not pass:
  immutable run `33945825011` timed out in the macOS test process, and local
  repetition then exposed a row/completeness scheduling race on repeat eight.
  The corrected query waits for initial evidence from both sources before its
  first snapshot. Thirty consecutive affected-suite repetitions pass. An
  independent correction review required deterministic proof for both arrival
  orders and pre-snapshot cancellation/drainage; those tests are now executable.
  Fourteen focused provider and all 419 Swift tests in 74 suites pass locally.
  Final independent re-review returned GO with no remaining P0-P3 finding.
  Exact corrected implementation `9eecacfd` passed all three immutable jobs in
  run `33947678048`, including conversion controls, disposable local Supabase,
  the complete target suite and both staging builds. O-026 and A-003/A-004/
  A-007/A-016 remain unadvanced; no category administration, app UI, MCP,
  hosted access, Firebase work, migration, production or cutover action exists;
  `EVID-BUDGET-CATEGORY-REFERENCE-POWERSYNC-PROVIDER-001`.

- Promoted the Account-workspace pending-work runtime after corrected exact-head
  implementation/harness commit `f41a5ab7` passed all three jobs in run
  `33941609019`; the evidence-only promotion commit `819900b2` also passed all
  three jobs in run `33942161659`. Independent next-slice audits then correctly
  rejected physical session ending/workspace activation because A-007/A-016/
  O-023 and hosted authority remain open, and rejected a proposed Transfer-
  destination provider because the current directory erases authoritative-
  versus-pending Project provenance even though canonical Transfer eligibility
  requires authoritative Client identity. Those Transfer scaffolds were removed
  before classification or commit. Selected the next unblocked enabling slice:
  an incomplete-first local BudgetCategoryReferenceQuerying PowerSync provider
  over only already-materialized rows. The first exact comment-only review
  returned NO-GO before executable work: shared runtime/control touchpoints were
  not frozen by manifest ID/hash; same-watch membership-loss clearing was
  absent; the enabling provider was incorrectly labeled a product outcome; the
  literal-field/version matrix was incomplete; symbol-graph proof exceeded the
  actual tooling; and one scaffold token caused conservative source-coupling
  metadata. The corrected technical-control candidate froze exact shared
  touchpoints and primary ownership, requires live active-to-revoked/deleted
  row retraction with completeness still true, adds reciprocal field/version/
  fingerprint proof, narrows the public-boundary claim to concrete compile-time
  and source/build checks, and removed the misleading token. Final exact-diff
  re-review returned GO with no remaining P0-P3 finding; immutable READY commit
  `8eafd6c9` subsequently passed run `33943581567` before implementation. O-026 remains fully open for
  administration and final download visibility; existing schema/RLS/Sync/app/MCP stay unchanged;
  `EVID-BUDGET-CATEGORY-REFERENCE-POWERSYNC-PROVIDER-001`.

- Implemented the normal Account-workspace pending-work and attachment runtime
  after corrected READY commit `15218cbbc44b7e7c28ef718c1770c7b6294a03c4`
  passed all three immutable jobs in run `33935937733`. One async lifecycle
  owner now contains the structured and attachment databases, authenticated
  media-key vault, verified pending-work provider, Client/Project stores and all
  four read streams behind a narrow runtime facade. The first executable review
  returned NO-GO because a wrong media key survived bootstrap, lifecycle-owned
  concrete providers were publicly constructible, staging startup could reenter
  and retain a failed runtime, and tests did not prove real-watch drainage or
  vault release/recovery across every staged fault. The corrected implementation
  authenticates a scope-bound encrypted key sentinel during vault construction,
  makes every owned provider compiler-internal, serializes and cleans failed
  staging startup, and adds direct real-watch, weak-vault and fault/reopen proof.
  Final corrected-diff review returned GO with no P0-P3 finding. Twelve focused
  runtime, 13 attachment and four isolation tests pass; all 403 Swift tests in
  73 suites, the compiler public-symbol boundary, target environment/contracts,
  11 MCP tests, both staging builds and diff checks pass locally. Implementation
  commit `462b757606841a49d8b2812b98c13c273a0b7ca6` passed the conversion-control
  and disposable-local-Supabase jobs in run `33939963766`, but its macOS job
  timed out after four independent `.serialized` PowerSync/SQLCipher suites
  advanced concurrently and then stopped completing. The log contained no
  assertion failure. Twenty consecutive local parallel full-suite runs passed,
  and an explicit process-wide nonparallel run passed all 403 tests in 6.8
  seconds. Swift Testing serializes only within one suite, so the workflow and
  its fail-closed integration control now require `--no-parallel`; focused
  runtime tests retain simultaneous databases, operations, four watches and
  close concurrency. Independent diagnosis agreed this is the smallest robust
  containment and found no shared fixture path. Corrected implementation and
  CI-harness commit `f41a5ab78df1ec3cc9581fe8f4dad2083c8920f4` then passed
  all three immutable jobs in Actions run `33941609019`, including the
  process-wide nonparallel 403-test gate, both staging builds, clean generated
  artifacts and disposable local Supabase verification. The runtime is
  explicitly not `AccountSessionEnding`; no sync, result resolution, upload
  verification, deletion, cleanup, signout, workspace switch, hosted access,
  Firebase work, migration, production or cutover behavior exists, and
  A-003/A-004/A-007/A-016/O-023 remain unadvanced;
  `EVID-ACCOUNT-WORKSPACE-PENDING-WORK-RUNTIME-001`.

- Audited the next provider boundary after Account discovery. The proposed
  pending-work summary is not yet trustworthy because the existing Account
  workspace runtime omits environment from its database/key identity, accepts a
  free namespace prefix, uses raw Principal/Account strings as path components
  and exposes a public destructive-close flag. Prepared an exact comment-only
  READY candidate that first carries `ValidatedLedgerEnvironment` through the
  staging composition, derives an opaque bundle/environment/persistence-relevant-
  manifest/Principal/Account namespace, validates before filesystem/Keychain/database side
  effects, preserves exact encrypted state across restart and makes ordinary
  close non-destructive. Only two new leaves contain comments; the existing
  runtime, staging root and shared directory-provider tests remain byte-unchanged
  until independent review and exact READY CI pass. Pending-work aggregation
  and physical session ending are separate later slices. A changed persistence
  binding selects an isolated namespace rather than being compared with
  separately stored metadata; callers cannot supply a free binding. The
  architecture now distinguishes the Principal/environment bootstrap database
  from the Account-workspace database; a later activation/switch coordinator
  owns authorization-lease and one-open-at-a-time enforcement. No Firebase,
  hosted or production state changed;
  `EVID-ACCOUNT-WORKSPACE-RUNTIME-ISOLATION-001`.
  The initial independent review returned NO-GO over an omitted shared test
  surface, incorrect authority citations, overclaimed stored-binding rejection,
  imprecise manifest scope and an unenforced workspace-exclusivity claim. All
  were corrected; final corrected-diff review returned GO with no remaining
  P0-P3 finding. Exact READY commit `428f5225` then passed all three immutable
  jobs in run `33927257913`. The executable slice now derives an opaque contained
  database path and composite Keychain identity, passes validated environment
  evidence through staging/bootstrap, rejects invalid namespace evidence before
  Keychain/filesystem work, and removes the runtime delete flag. Executable
  review twice returned NO-GO until every individual contract/resource/prefix
  and Principal/Account Keychain dimension plus the old dotted-ID collision had
  direct assertions; final corrected-diff review returned GO with no remaining
  P0-P3. Four focused/all 372 target tests in 71 suites and both staging builds
  pass locally. Exact implementation commit `3bf8e9ed4e4251b7adcd9c276d0e7259cad8bf18`
  passes all three jobs in immutable run `33928708863`. The next bounded slice is
  the local pending-work summary provider; physical synchronization, logout,
  deletion, Auth and workspace switching remain excluded.

- Implemented the target-local pending-work summary provider after exact
  corrected READY commit `2072af47c908738fd01f4fa6405074c87ee1df95`
  passed all three jobs in immutable run `33930443887`. It derives exact scoped
  operation and protected attachment evidence, refuses orphaned or unavailable
  vault evidence, and preserves restart-stable identity-bearing journal state.
  The first executable review returned NO-GO because Swift actor reentrancy
  allowed an ABA revision regression, the draft falsely claimed normal runtime
  composition, extreme finite time conversion could trap, and real
  store/restart/fault coverage was incomplete. The corrected provider holds an
  explicit permit across the whole summary operation, rereads the journal after
  final cross-store validation, uses exact nontrapping time conversion, and has
  16 focused provider plus 13 attachment-provider tests including same-instance
  ABA, completed cross-instance defense-in-depth, real orphan restart and
  unavailable enumeration. `LedgerOfflineClientRuntime` remains unchanged: a
  later physical session-ending composition must own exactly one provider
  instance and the attachment database/vault/key lifecycle. Final independent
  corrected-diff review returned GO with no P0-P3 finding and independently
  reran all 16 provider tests. All 391 target tests in 72 suites and both staging
  builds pass locally. Exact synchronized implementation commit
  `3ac05bd01399e6b2043f57fcc22fd4d5bb3eb0ed` passed all three jobs, including
  isolated Supabase schema/RLS/RPC/replay checks, in immutable run
  `33932915626`. No synchronization, cleanup, signout, Auth, workspace switch,
  hosted access, migration, Firebase work or cutover action exists.

- Implemented the four-leaf local-only Account discovery provider slice after
  exact corrected READY commit `5a5f2defbdaf15a8198fb4ce22b27a41216e93af`
  passed all three jobs in immutable Actions run `33922033391`. The executable
  boundary includes the Principal/environment-bound `AccountQuerying` adapter,
  a principal-scoped encrypted bootstrap runtime, ten focused tests covering
  false-empty/readiness/freshness/bounded-failure/restart/cancellation and a
  build-only isolated explicit-selection component. Existing staging-root
  runtime wiring is excluded. A
  feature-specific authority audit confirmed that the canonical Account spec
  settles this local outcome and that session-ending/pending-work can follow as
  a separate slice because selection intent activates and tears down nothing.
  Independent scouting also identified a hard boundary: the current
  illustrative `sync-streams.yaml` selects broad Principal data and globally
  auto-subscribes Account content, so this slice uses only disposable/injected
  local rows plus injected typed query-specific completeness/freshness and
  explicitly does not reuse or advance that config. Server schema/grants/RLS/
  Data API, safe hosted bootstrap/authorization and actual workspace activation
  remain gated by A-004/A-007/A-016. Project-note work was
  deferred because O-039 blocks mutation and note history also needs this
  shared scope/readiness foundation. The first independent review returned
  NO-GO over accidental unclaimed pgTAP/root work and underspecified freshness,
  failure and pre-query scope-refusal tests. A second READY review caught three
  stale wording inconsistencies. During executable review, six additional
  issues were corrected before commit: completeness/freshness coupling,
  destructive close exposure, malformed sentinel/cardinality acceptance,
  malformed membership IDs, raw Principal filesystem traversal and Keychain
  mutation before namespace validation. Final corrected-diff implementation
  review returned GO with no P0-P3 finding; ten focused tests pass, including
  contained opaque namespaces and encrypted close/reopen. All 368 Swift tests
  in 70 suites, generated app/MCP contracts, 11 MCP tests, conversion controls,
  target isolation, deterministic project generation and sequential macOS/iOS
  staging builds pass locally. Initial exact READY
  commit `a34a51e9` was rejected by immutable
  run `33921833216` solely because the M2 residual report was stale; the
  shorthand local gate had omitted that check. CI correctly prevented dependent
  jobs. The report is now regenerated at 443 mapped / 184 residual / 47 blocker
  rows. Follow-up commit `900fcd67` omitted other regenerated audit/manifest
  outputs still visible in the local status; run `33921970523` was cancelled
  immediately and supplies no evidence. Corrected READY commit `5a5f2def` then
  included the complete generated-artifact set and passed the complete workflow
  plus clean-checkout proof. The local implementation is being synchronized and
  exact implementation commit `011a9d0521c425e6b2e78fab7970826896c730dd`
  passed all three immutable workflow jobs in run `33925008015`, satisfying its
  operational verification item. The slice remains `implemented`, not hosted
  `verified` or `rehearsed`. No Firebase, hosted or production state changed;
  `EVID-ACCOUNT-DISCOVERY-PROVIDER-001`.

- Implemented the reviewed Client/Project directory and browse provider after
  exact READY commit `2417d20bd03540288575bb2a33b96130e7edd4c2`
  passed all three immutable workflow jobs in run `33915624174`. The target-only
  adapter now combines local PowerSync rows with independent reactive Client and
  Project completeness streams, exposes only the same Principal's pending rows
  before membership, gates authoritative rows and reconciliation on active
  membership, treats missing Project-to-Client joins as incomplete, binds local
  versions to exact content/readiness and cancels both observations with the
  consumer. The Account/Principal-bound runtime rejects cross-Account reads and
  writes plus cross-Principal writes before persistence. The isolated staging
  app supports fresh offline create, Client selection, active/archived Project
  browsing and exact selected-row detail navigation with structured task
  lifetime. Core readback now removes only exact Project/Client core overlays;
  pending allocations survive until allocation-aware authority exists, while a
  durable rejection still removes the whole aggregate. Three independent review
  passes
  found and drove corrections for shared/non-reactive completeness, fresh-
  pending invisibility, runtime scope, premature allocation cleanup, stale
  selection, task lifetime, pre-membership authoritative replacement and a
  remaining exact-detail authority/reconciliation bypass. The corrected detail
  readers now bind the same Principal/Account and membership policy as the
  directories, preserve pending values through exact navigation, and exclude
  other-Principals' pending rows. Final corrected-diff review returned
  executable GO with no P0-P2; its sole P3 stale test-count label was corrected
  before commit. Sixteen focused directory tests, seven Project tests and all
  358 target tests in 69 suites pass locally. Exact synchronized implementation
  commit `a1b57a37a750486246273664606e33d086b2801c` passes all three jobs in
  immutable run `33918240622`. Real hosted Auth/Sync proof remains planned, so
  the slice and its two owned
  leaves are `implemented`, not `verified` or `rehearsed`. A-003/A-004 remain
  proposed; no Firebase, hosted or production state changed.

- Prepared the Client/Project directory and browse PowerSync provider as an
  exact comment-only READY checkpoint. Two automatically discovered leaves
  (`SWIFT-B23F91245E50`, `TEST-5AAEE26660C8`) now have a complete dossier,
  reviewed classification, evidence-index entry and tracker row before any
  executable code advances. The boundary reuses the verified backend-neutral
  read/projection contracts and current local Client/Project membership,
  schema, grants, RLS, Sync and pending-create mechanics. It requires exact
  Account/Principal scope, membership-gated authoritative rows, caller-owned
  pending visibility, independent reactive Client/Project completeness,
  missing-relationship truth, content-bound local versions, encrypted restart,
  cancellation, exact selection/detail navigation and aggregate-safe overlay
  reconciliation. The already developed implementation has received two
  independent reviews and was corrected for completeness coupling, pre-
  membership authority leakage, runtime scope enforcement, premature Project-
  allocation cleanup, stale current selection and task-lifetime defects; it
  remains outside this READY checkpoint until the exact READY commit passes
  immutable CI. O-024/O-025, O-040, O-042/O-043, hosted Auth/Sync, MCP list/
  search, migration, production and cutover remain excluded. A-003/A-004 stay
  proposed. Deterministic Xcode generation also incorporated the pre-existing
  comment-only `ClientRenameStagingExercise.swift` file committed in the prior
  DRAFT checkpoint because the staging target owns that source directory; the
  file still declares no executable behavior. No Firebase or production state
  changed.

- Independent review rejected the first comment-only Client rename READY package
  from base `e6620875ef6a8c5488929972329545a2204750ed`. It correctly found that the
  draft inferred archived-Client rename eligibility and same-value revision
  advancement without canonical authority; incorrectly denied same-Account
  restricted-member Client/result reads that existing RLS and Sync intentionally
  permit; left the migration, pgTAP suite and local Data API runner outside
  machine discovery; omitted replay-after-later-overlay and unknown-terminal-code
  cases; and ignored that Swift accepts U+0000/unbounded names that PostgreSQL
  text/jsonb cannot represent. The corrected dossier is DRAFT on O-042/O-043.
  All nine new comment-only leaves are now automatically discovered and hash-
  enforced in `M0-CLIENT-RENAME-POWERSYNC-PROVIDER-001`; the pgTAP leaf still
  contains only its runner-validity placeholder. The bounded design retains
  separate local rename command/overlay state, pending-create/chained FIFO,
  exact readback reconciliation, auth-first trusted-handler mutation, UInt64
  precision, and app/MCP parity without choosing the unresolved user-visible
  policies. No executable rename behavior, hosted call, Firebase/source-app
  change, migration, production access, commit or push exists. A-003/A-004 stay
  proposed.

- Follow-up O-043 audit found that the same cross-runtime boundary also gates
  promotion of the already local Client-create path and the new-Client branch
  of Project setup. Their stable identity, existing-Client selection,
  encrypted-offline queue, RLS, replay and readback mechanics remain valid, but
  Foundation whitespace handling, JavaScript `trim`, PostgreSQL `btrim`, NUL
  representation and unbounded name indexes are not equivalent. A locally
  accepted edge input can currently fail before a durable terminal server
  result. Both provider dossiers now record planned shared-vector and zero-local-
  dispatch proof, ordinary-name parity claims are narrowed, and dedicated
  `EVID-CLIENT-CREATION-PROVIDER-001` replaces the incorrectly reused
  provider-free evidence. O-043 is not silently decided or implemented.

- Implemented the protected local attachment-byte durability provider behind
  the existing backend-neutral capture port. Acceptance now encrypts bytes with
  a distinct media key, authenticates scope/parent/identity/count/digest,
  promotes through directory-descriptor-relative atomic storage, commits exact
  localOnly SQLCipher queue evidence, rereads/decrypts/re-hashes, and only then
  returns a path-free receipt. Pending/missing/corrupt work survives recreation;
  exact replay deduplicates; changed concurrent replay, scope rebinding, missing
  scope bindings, wrong keys, malformed evidence, links, and unsafe identities
  fail closed. Independent review found and drove corrections for path races,
  unbounded reads, mutable-scope hiding, ineffective wrong-key/SQLCipher tests,
  a CI filter that omitted the suite, and physical-fault overclaims. Ten focused
  tests pass with Swift warnings as errors, and the actual 19-test PowerSync
  command also passes. Exact implementation commit
  `ecfcdc3ba3fc928d77cab575cc64d46c08f1f71f` passed immutable Actions run
  `33902466636`, including conversion controls, all 342 Swift tests, both
  staging builds, isolated local Supabase provider checks and clean artifacts.
  Hosted upload/Storage/Auth/Sync,
  physical-device/low-storage/power-loss/soak evidence, app composition,
  O-023 retention/deletion behavior, migration, production and cutover remain
  unadvanced; `EVID-ATTACHMENT-DURABILITY-PROVIDER-001`.

- Implemented the first complete Project setup provider slice locally on top of
  the verified provider-free contracts. One offline transaction stores local
  operation evidence, an optional new-Client overlay, the Project overlay, the
  complete absent/null/zero/positive allocation set and one insert-only upload
  command in encrypted PowerSync SQLite. The trusted spike-prefixed Postgres
  handler validates the exact canonical command/fingerprint, re-derives
  authenticated membership/capabilities, enforces Project/category/allocation
  RLS and financial visibility, locks Operation/Project/new-Client identities,
  atomically creates the optional Client, Project, allocations and immutable
  terminal result, and refuses OperationID rebinding. Swift and target MCP use
  the same scoped-user RPC and exact fingerprint. The later directory-provider
  correction establishes the precise boundary: authoritative Client/Project
  core readback removes only linked core overlays so they cannot resurrect,
  while allocation optimism remains until allocation-aware proof; durable
  rejection still removes the complete aggregate. Independent early SQL/PowerSync reviews
  found missing grants, a null-discriminator bypass, capability/visibility and
  identity-race gaps, canonical byte/order mismatches, missing command dispatch,
  missing local-link verification and missing overlay reconciliation; all were
  independently inspected and corrected with regression coverage. Local reset,
  41 combined pgTAP assertions, Client/Project REST checks, 9 Client plus 7
  Project PowerSync tests, 10 MCP tests, strict TypeScript, generated contracts
  and complete conversion controls, all 332 Swift tests, database lint, and both
  macOS and generic iOS Simulator staging builds pass. Exact implementation
  commit `e57b874d4c75f7f833f77221df794cafa0c0d72c` passed immutable Actions run
  `33894323498`, including the new local-Supabase provider job. A-003/A-004 and
  O-026 remain open;
  real Auth/Sync/device/media/performance/fault rehearsal, permanent-
  authorization terminal handling, production migration and cutover are not
  claimed; `EVID-PROJECT-SETUP-PROVIDER-001`.

- Implemented the first provider-backed Client vertical slice locally without
  changing the Firebase application. A spike-prefixed Postgres schema and
  trusted RPC enforce stable Account-scoped Client identity, authenticated
  membership/capability checks, RLS, least-privilege grants, exact OperationID
  replay, payload-rebinding refusal, and immutable terminal results. The target
  PowerSync adapter uses an encrypted per-Principal/Account SQLite database,
  atomically records the operation plus optimistic Client row, preserves it
  across restart, exposes partial readiness while pending, validates upload
  transactions/results, and drains applied or durably rejected operations. The
  isolated target app exercises offline creation/readback and the gated target
  MCP tool uses the same canonical command/RPC boundary. Local pgTAP (19
  assertions), Data API/RLS integration, MCP tests, nine focused PowerSync
  tests, all 332 Swift tests, contract/environment checks, and the latest iOS
  Simulator build pass. Immutable CI, real hosted Sync Streams/Auth, media,
  evolution, scale, and fault rehearsal remain open; this is not migration or
  cutover authority.

- Implemented the separate 386-occurrence source-query reconciliation control
  from exact READY base `4618c7e5b9fc3a24cd917239bf795aec6117ea5c`
  and its frozen 30-path boundary. The dependency-free generator/checker emits
  one deterministic 386-row / 584-outcome JSON artifact and validates exact
  source/target bytes, source identities/hashes, human-selected owner and target
  projections, scope-selected blockers/evidence, content-hashed retirement
  authority, retention ordering, compatibility scope, canonical outcome
  ordering/cardinality/conflicts, synchronized lifecycle and exact Git diff.
  Closed schemas prevent hidden physical/provider authority; contained regular
  non-symlink inputs, exclusive atomic 0644 output, exact high-level destination
  and byte-exact read-only checking close filesystem drift. Root package and
  complete workflow artifacts are bound so npm pre/post hooks, missing PR
  triggers, conditional/failure-tolerant jobs, execution-context overrides,
  missing diff guards or loss of the Linux-before-Swift dependency fail closed.
  All 23 focused tests, the complete CI-portable conversion-control command
  sequence run on macOS, all 316 Swift tests in 65 suites, and both isolated
  staging builds pass locally. Exact implementation commit
  `aefa7acd57957ebe4e136540b1f6034ae8131130` passed immutable Actions run
  `33880331322`. Independent
  implementation review found real authority-path, physical-field, split-brain,
  symlink, output-path, CI and malformed-input bypasses; each is corrected with
  regression coverage, and final review returned GO with no remaining P0-P2
  finding. `SQUERY-TEST-001` through `-010` pass; only the separate
  administrative VERIFIED metadata promotion remains. The artifact deliberately
  preserves 115 authority-blocked and six
  evidence-blocked outcomes, so no dependent target-domain work may treat this
  as product-decision, production-read, schema/RLS/Sync/provider, migration,
  retirement or cutover authority; `EVID-SOURCE-QUERY-RECONCILIATION-001`.

- Earlier, promoted the separate 386-occurrence source-query reconciliation control to
  classification-only READY from its initial design at
  clean baseline `76b2ff45ba4fffe68097919c32ec7b4fec48047c`. One aggregate
  registry binds the full unchanged source and target-authority artifacts plus
  stable selected manifest projections. Human semantic review assigned every
  QUERY ID exactly once across ten capability batches. Bounded subagent
  authoring plus root and independent review covered the first 375 rows. All
  386 rows now carry 584 explicit outcomes: six rows bind same-owner E-001/E-002
  production-read requirements, eight bind exact product authority, five carry
  both independent blocker types, and two retain compiled Firebase BatchWriting
  reads only as current-source compatibility through verified cutover
  reconciliation. O-041 now separately owns Business Vendor Cash Movement
  semantics because O-035 owns Client Summary only. At that checkpoint, the two
  future aggregate generator/test leaves were comment-only. The frozen row
  corrected model requires one QUERY ID, canonical full-occurrence hash,
  human-selected exact manifest source owner/ref with a stable projection hash,
  and a nonempty canonical set of exactly seven outcome classes:
  verified target query port, approved future target query, approved target
  nonquery surface, source-only, retired, typed authority-blocked or typed
  evidence-blocked. Blocked outcomes bind the exact source owner, TQUERY row or
  target surface that structurally carries every blocker; evidence outcomes now
  bind the complete selected owner/ref/hash/blocker tuple. Registry, batches and
  slice shared one closed lifecycle; nested schemas and batch paths were closed;
  `current_source_compatibility` is frozen to the two BatchWriting reads; 137
  source-retention/mechanism-retirement pairs use an ordered milestone model,
  with 102 retirement gates corrected to follow reconciliation/audit retention;
  behavior retirement uses four independently extracted, content-hashed
  authorities and never manifest self-authorization; every outcome pair is
  governed by a complete symmetric conflict matrix. The M0 control crosswalk
  directly grants the exact architecture-decisions authority used by
  A-003/A-004 boundaries.
  No outcome
  is inferred from subsystem/path/symbol/expression. A-003/A-004 remain global-
  only physical deferrals. The stable control CONFIG owners are `target_mapped`
  with empty blockers while all 386 rows have explicit outcomes. Exact
  complete-DRAFT commit `92a609a75dd5d3530bcf1a1e61a8d6cb2c72e9b7`
  passed immutable Actions run `33871918545`; the dossier, registry and all ten
  non-template batches were synchronized as `ready` against an exact
  22-path freeze containing lifecycle/evidence documentation and deterministic
  conversion metadata regenerated from the dossier status. READY certifies
  classification completeness only. At that checkpoint, no
  package/workflow/generated reconciliation artifact, executable
  control, runtime, provider, hosted, production, release or cutover behavior
  advances. Exact DRAFT commit
  `570f54a50405376ee4b642f1abc11ea04eb0a4bb` passed immutable GitHub Actions
  run `33861320397`, including conversion traceability, target contracts and
  macOS/iOS Simulator builds. Its evidence-sync commit
  `b4d948e41f9ca6d5ea50da0ba9d8db6504ea06ae` passed immutable run
  `33861762639`, including the same gates and both isolated builds. Root and an
  independent reviewers returned GO after substantive corrections to target
  mappings, blocker scope and retirement authority. Completion review then
  re-derived all 386 occurrence/owner hashes and validated all 584 outcomes; its
  one O-041 heterogeneous-event/scope finding is corrected. Separate adversarial
  review correctly returned NO-GO on the control weaknesses summarized above.
  Corrected-model completion and adversarial re-reviews then independently
  returned GO with no P0-P3 finding after re-deriving the complete row/outcome,
  evidence, authority, compatibility, retention and conflict controls;
  `EVID-SOURCE-QUERY-RECONCILIATION-001`.

  Exact READY commit `4618c7e5b9fc3a24cd917239bf795aec6117ea5c`
  then passed immutable Actions run `33872927608`, including traceability, all
  316 target tests and both staging builds. Read-only implementation preflight
  matched the prior query-control topology and froze the exact 30-path
  implementation diff plus the two READY scaffold hashes against that full
  commit SHA. The generated artifact remains excluded from capability discovery
  to prevent an artifact-to-manifest-to-artifact hash cycle.

- Verified the complete target query logical-authority crosswalk
  above the verified TQUERY inventory. One reviewed JSON registry binds the
  exact inventory digest and all 18 method signature hashes, then records only
  authority references, six logical axes, proposed architecture data-domain
  dependencies and explicit unresolved axes. Project preference is
  decision-blocked by O-040; O-026 is limited to exact reference-data
  visibility/download/capability; O-007/O-015 remain only on Item occurrence/
  provenance persistence. Item section/upstream order is reviewed while only
  physical storage order remains undefined; budget contribution-source
  eligibility/taxonomy is explicitly not defined; unresolved Operations include
  only queued/applying/rejected and transient failure requeues. Account issuer/
  subject correlation and Operation authorization/merge/routing remain explicit
  uncertainty. Every row cites its owning verified query-contract evidence and
  every domain label is `proposed_architecture_dependency`. Postgres and local physical planes are
  globally deferred under proposed A-003/A-004; there are no per-row physical
  IDs, names, indexes, SQL, RLS or Sync assignments. Exactly
  `CONFIG-5422E6C6A047` and `CONFIG-ED6818A70D4E` advance to `verified`.
  From amended immutable READY commit `fcfaec8397f08b17ef54e9cffc651dfa3fce2b6a`,
  whose Actions run `33849974363` passed, a dependency-free JSON generator/checker
  and 23-test adversarial suite now enforce exact structural validation, fully
  re-derive the upstream inventory, enforce review-class consistency and exact
  CLI arity, canonicalize nested output, reject root/symlink escapes, use
  exclusive no-follow atomic generation, and derive
  collision-checked TACCESS identities and mapping hashes, and emit/check one
  deterministic generated artifact. Exact root commands and an Ubuntu gate run
  before the dependent macOS target job. The generated 18-row diff received
  separate human semantic review. The validator performs no free-text keyword
  or Markdown semantic/status parsing. The package and workflow are deliberately
  re-acknowledged at exact reviewed hashes without changing status or ownership;
  the committed discoverer/query-extractor path exclusions preserve contiguous
  forbidden-key tests without changing the source surface or 386-query inventories,
  and all 16 query owners remain unadvanced. Exact implementation commit
  `66d56bf1ee8302e63b5622c879e62dbbe4b7e95e` passed immutable Actions run
  `33853355777`; all ten verification requirements pass, and independent final
  adversarial review returned GO with no P0-P3 finding. The 386 source `QUERY-*` occurrence
  reconciliation remains a separate downstream slice. Synchronized conversion
  controls record 839 surfaces / 824 currently discovered, 395 target-mapped-or-
  later, 184 residuals, 46 blockers, and 66 slices / 157 claimed / 142
  implementation-advanced, with only the three established retired-path
  warnings. No Swift, schema, RLS, Sync, provider, Firebase, hosted, production,
  migration, release or cutover behavior advances;
  `EVID-TARGET-QUERY-LOGICAL-AUTHORITY-001`.

- Verified the decision-independent target query-port inventory control after
  exact READY commit `0ecabf4761874599d8a37a5a89ffced393b4cd63` passed
  immutable Actions run `33837081633`. Exactly `CONFIG-9B16CFCB67A4` and
  `CONFIG-C1C61B2D6569` advance to `verified`: a dependency-free Node lexical
  scanner and 20-test adversarial suite inventory every direct instance method
  in public exact-suffix `Querying` protocols or fail closed. Deterministic
  JSON/Markdown records exactly 16 verified owners, 16 protocols and 18 methods,
  all present `watch*` observations; only `ClientProjectDirectoryQuerying` and
  `OperationQuerying` have two methods. Stable TQUERY identity remains separate
  from normalized signature drift. Exact root generate/check/test commands and
  a Linux conversion-control gate now precede the dependent macOS target job.
  Human review of every generated row passed and remains distinct from machine
  freshness. Exact implementation commit
  `a359c8622069c2dc8b75ca09a8fd89b95713f1bb` passed immutable Actions run
  `33842465485`; `TQUERYCONTROL-TEST-001` through `-008` pass, and independent
  final review returned GO. The package and workflow hashes are
  deliberately re-acknowledged without changing their existing status or
  ownership; `FILE-208B7E9D7F47`, all 16 query owners, `FILE-063B0E6EC659` and
  `MAN-INDEX-001` are unchanged. Later slices must review every TQUERY into the
  logical access/index crosswalk and reconcile it against all 386 source
  `QUERY-*` occurrences. No query semantics, product behavior, logical/physical
  index, SQL/EXPLAIN, RLS, Sync, PowerSync, provider, hosted, production,
  migration, release or cutover work advances; `EVID-TARGET-QUERY-PORT-INVENTORY-001`.
  The synchronized ledger records 837 surfaces / 822 currently discovered, 393
  target-mapped-or-later, 184 residuals, 46 blockers, and 65 slices / 155
  claimed / 140 implementation-advanced, with only the three established
  retired-path warnings. Root review found and the implementation corrected
  nested string/regex declaration leakage, split multiline-return truncation,
  detached declaration prefixes, malformed header/generic/parameter/tail
  acceptance including nested component start/end states, comment-separated regex context and silent
  Unicode/backticked identifier omission; focused regressions cover every
  correction and identity input changes. The complete local gate passes: 20 focused Node tests,
  generation/check freshness,
  conversion/capability/query/residual/M0 controls,
  target isolation/contracts, all 316 Swift tests in 65 suites with warnings as
  errors, repeatable project generation, both staging builds, JSON validation
  and diff formatting. Immutable implementation CI is green and this separate
  docs-only promotion records verification.

- Rejected the Project-preference update application-use-case candidate before
  READY, commit or executable implementation. Independent authority review found
  that the existing provider-free read/update leaves prove only reusable
  preference-shaped representation and operation mechanics: neither canonical
  target specs nor confirmed decisions establish that Project budget pins must
  exist, survive migration, default to any category, fall back to Overall or
  another category in Project detail/cards, or write a fallback implicitly.
  Removed the two speculative Swift comment scaffolds, their implementation-slice
  dossier and evidence record. Added O-040 and its proposed decision packet;
  demoted exactly ten over-advanced source/integration surfaces to
  `characterized`, attached O-040 to those ten plus eight already-characterized
  surfaces, and left the verified preference primitive leaves verified. The
  corrected control plane records 387 target-mapped-or-later surfaces, 184
  residual surfaces, 46 blockers, 19 proposed packets and 38 product blockers.
  No source app, Firebase, MCP, provider, hosted, migration or production
  implementation changed. Exact remediation commit
  `471f61a004a92afa961aba41ea6544a90a391cda` passed immutable Actions run
  `33825756789`.

- Verified the bounded Item-to-Space assignment application use case
  after exact READY commit `d51ea1d338110d73a6c76ef3ffcf21f0b9113f99`
  passed immutable Actions run `33827181145`. Exactly two leaves,
  `SWIFT-0540BE125F5A` and `TEST-DA67EAC9C2EF`, now provide a public transient
  Account/scope/destination/typed-Item intent and one application boundary above
  verified assignment-operation and destination-directory contracts. The use
  case validates exact Account/scope, resolves a represented stable SpaceID,
  derives its revision from the row, constructs before one assigner call and
  validates afterward. All six Project/Inventory × ready/partial/stale paths
  dispatch; missing rows remain only not represented. Three pre-port application
  failures, all 16 port operation failures and cancellation remain exact; every
  other port error is bounded to `localAcceptanceFailed`. Primary and
  independent review found and corrected two issues: the first implementation
  leaked port-originated `ItemSpaceAssignmentUseCaseFailure`, and initial tests
  omitted some scope/quality combinations. An adversarial containment test and
  the full six-case matrix now pass; both reviewers returned GO with no
  remaining P0-P3. Seven focused tests prove `ITEMSPACEUSE-TEST-001` through
  `-008`; exact READY CI plus primary and independent corrected-diff reviews
  prove `-009`. Exact implementation commit
  `04331950dc9fe4dea32493e11a9c367530e3baea` passed immutable Actions run
  `33828908233`: traceability completed in 11 seconds and isolated target in
  6 minutes 32 seconds, with all steps green including all 309 tests in 64
  suites and both builds. `ITEMSPACEUSE-TEST-010` therefore passes, and the
  slice and both surfaces are verified. Clear/no-op, Item
  selection UI/read, archive, media/marker, scope movement, accounting/
  provenance, physical persistence, authorization, provider/schema/RLS/Sync,
  app/MCP, migration, hosted, production, release and cutover remain excluded.

- Verified the bounded Item Space-clearing application use case above
  verified `ItemSpaceClearingOperation.swift` at exact implementation
  `f5a7ac7598f77859239b66666bc703ee4639c233` / immutable run
  `33677087616`. Exact READY commit
  `8154f8bf0c63576e64ac609b1e1b18d53f60ed32` passed immutable Actions run
  `33831367527`; exact implementation commit
  `f7ce8bca5ef3d36fc621ed577e85b2d25c1fd7a4` changed only
  `ItemSpaceClearingUseCase.swift` (`SWIFT-EEAC86485FF6`) and
  `ItemSpaceClearingUseCaseTests.swift` (`TEST-CA84B398990C`). Immutable Actions
  run `33832447988` passed its isolated-target job with all 316 tests in 65
  suites and both builds, but traceability failed solely because the
  intentionally separate control checkpoint had not synchronized the two new
  leaf hashes. Exact synchronized implemented checkpoint
  `8181512d78783d9ae7561475ed0d63c42d1e9b1e` corrected those hashes plus
  dossier, manifest and evidence without executable changes; immutable Actions
  run `33833543735` passed traceability in 11 seconds and isolated target with
  all 316 tests in 65 suites, generated contracts, both builds and clean
  artifacts. The public transient non-Codable
  Account/scope/typed-Item-revision-current-Space intent constructs the verified
  draft/command before exactly one `ItemSpaceAssignmentClearing` call and
  validates its receipt afterward. Caller-supplied scope and current-Space values
  remain untrusted conflict evidence; stale assigned-looking evidence may
  dispatch, while trusted apply must validate actual placement, membership and
  authorization. Nil/no-current-Space intent is structurally unrepresentable,
  empty selection rejects, and no synthetic no-op receipt exists. Seven tests
  prove Project/Inventory single and mixed-Space dispatch, reordered canonical
  commands, literal reciprocal ownership, zero/one-call boundaries, all 15
  typed failures, cancellation, unknown-error containment, diagnostics,
  topology and exclusions. All ten dossier obligations pass; the slice and both
  leaves are verified. READY review missed a P3 free-text preservation-ID typo:
  `SWIFT-4D0D546A02D` should have been `SWIFT-4D0D546A02D8`. The manifest/
  classification/source status and
  frozen executable test scaffold used the correct ID, so no executable or
  status behavior was affected; the implemented checkpoint corrected the free
  text. Read/UI eligibility and mixed assigned/unassigned admission,
  archive/O-037,
  attachment references/bytes/O-023, marker mutation, destination/scope/
  accounting/provenance, physical persistence, authorization, provider/schema/
  RLS/Sync, app/MCP, migration, hosted, production, release and cutover remain
  excluded.

- Verified the bounded typed Client rename application dispatch after exact
  READY commit `9cc34f4ca6004e7c3b3e1816f07112c55a70fe54` passed immutable Actions run
  `33819792298`. Exactly two leaves, `SWIFT-2F4458F40735` and
  `TEST-341B2CD23B6A`, now provide a public non-Codable Account/Client/revision/
  `ClientDisplayName` intent and a generic one-call use case above verified
  `ClientRenameOperation.swift`. Construction occurs before the port boundary;
  receipt validation occurs afterward; all 12 typed failures and cancellation
  remain exact; only unknown port errors map to `localAcceptanceFailed`.
  Eight focused/all 302 tests in 63 suites, complete local controls, repeatable
  Xcode generation and both staging builds pass. One independent reviewer
  caught missing explicit UTF-8 byte-equality proof for the more-than-8-KiB
  Unicode payload; the corrected test compares actual and expected UTF-8 `Data`.
  Both independent implementation reviewers now return GO with no remaining
  P0-P3 finding. `CRENAMEUSE-TEST-001` through `-009` pass. Exact implementation
  commit `0f000b8e491019a9307c46437312b7ae0f5711dc` passed immutable Actions run
  `33821354656` (traceability 11 seconds; isolated target 6 minutes 59 seconds),
  satisfying `CRENAMEUSE-TEST-010`. The dossier and both leaves are verified.
  Every named source UI/service/model/validation/MCP surface and all
  persistence, authorization, provider/schema/
  RLS/Sync, migration, hosted and production behavior remain unadvanced.

- Implemented the bounded typed Project rename application dispatch after exact
  READY commit `dc7c9779` passed immutable Actions run `33808493496`. Two leaves,
  `SWIFT-5A812E7B8C95` and `TEST-E1BAA8DF70B4`, provide a public non-Codable
  Account/Project/revision/`ProjectDisplayName` intent and a generic one-call
  use case above verified `ProjectRenameOperation.swift`. The application
  boundary accepts no raw String and adds no name-normalization policy. Ten
  use case constructs before one call, validates afterward, preserves all 12
  typed failures plus cancellation and bounds unknown errors. Eight focused
  tests plus review satisfy `PRENAMEUSE-TEST-001` through
  `PRENAMEUSE-TEST-009`; exact implementation commit `9c8e27cf` / immutable
  Actions run `33816585123` satisfies `PRENAMEUSE-TEST-010`. All named source UI/service/model/validation/MCP surfaces,
  including ProjectDetailView and ProjectDetailContainer, retain their prior
  statuses and every persistence/authorization/provider/
  schema/RLS/Sync/migration/hosted/production exclusion remains binding. The
  local implementation gate passes 829/814 conversion inventory, 395/174/45 residual
  control, M0, isolation/contracts, all 294 target tests in 62 suites with
  warnings as errors, repeatable Xcode generation at `0657194a` / `388303af`,
  and both staging builds. Initial READY reviews corrected mirrored-proof risk,
  product/technical authority attribution, ProjectDetailView status coverage
  and rejection-recovery wording. Both independent implementation reviewers
  returned GO with no remaining P0-P3 finding. The dossier and both target
  leaves are verified.

- Rejected the chosen-Project note-creation application-use-case candidate
  before READY, commit or executable implementation. The first independent
  actual-diff reviewer caught omitted accounting for MCP validation helper
  `MCPMOD-DAB760104CEE`; the second found the blocking authority defect: current
  app entry points trim and accept any nonempty remainder, MCP requires at least
  three trimmed characters while forwarding original text, and target
  `ProjectNoteText` preserves any accepted nonblank bytes. No canonical target
  heading or confirmed decision chooses the shared user-visible behavior.
- Removed both speculative comment scaffolds, their dossier/evidence and target
  surface records. Added O-039 plus a proposed decision packet, corrected exact
  MCP source behavior and stale QuickNote target names, and attached O-039 to
  the eight source/integration surfaces whose shared submission behavior it
  blocks. The verified lower-level note representation/operation remains a
  provider-free representational superset; it does not authorize an app/MCP
  submission policy.
- A fresh strict-authority scout selected provider-free Client archive dispatch
  as the next candidate. Canonical Client lifecycle authority and D-006 support
  stable Account/Client/revision intent and archive-only orchestration without
  deciding merge, reassignment, dependency correction, UI, authorization,
  persistence, provider, migration or production behavior.
- The corrected preflight-rejection checkpoint passes conversion sync/check/
  report, capability/query/residual controls, M0, target isolation/generated
  contracts, JSON and diff validation, and all 261 target tests in 57 suites.
  It records 819 surfaces / 804 discovered, 385 mapped-or-later / 174 residual /
  45 blockers with only the three established retired-path warnings. No app,
  Firebase, MCP source, provider or production implementation file changed.
- Separated the supplied 197-path dirty snapshot into an independently verified
  16-path current Firebase implementation commit, a 64-path product-authority
  package with four supporting non-item audit/evidence paths, and the remaining
  conversion architecture/control/generated-evidence package. `firebase` and `main`
  now share exact source baseline `fe018501`; no conversion file was placed on
  either shared branch. See `EVID-GIT-BASELINE-001`.
- Established a machine-readable conversion manifest and objective milestone
  definitions.
- Added automatic discovery for Swift application/test files, Firestore rule
  surfaces, Firebase Functions, MCP modules/tools/resources, Firebase-related
  scripts, migration tooling, configuration, and existing tests.
- Added manual cross-cutting surfaces that static discovery cannot prove:
  production data profiling, Auth, Storage, dynamic/server-only data, indexes,
  hosting/deep links, offline behavior, local lifecycle, reports, release
  isolation, cutover, and observability.
- Added validation, milestone gating, and generated coverage reporting.
- Synchronized 674 repository-discovered and 12 manual cross-cutting surfaces.
- Verified the control tool with deterministic positive checks and intentional
  negative milestone-gate checks; see `EVID-CONTROL-001`.
- Characterized every production Firestore rule match, all 18 exported Cloud
  Functions, all five Function modules, the core Firebase Auth/account/invite
  boundary, MCP OAuth/Admin access, Storage/media behavior, and server-only
  dynamic collections.
- Classified all 686 surfaces: 680 characterized, four verified control/tool
  surfaces, and two intentionally blocked evidence surfaces. Zero surfaces are
  unclassified or lack behavior, evidence, or one classification batch.
- Published `current-backend-contract.md` and `EVID-SOURCE-BACKEND-001`,
  including current privilege defects, production/test rule drift, derived
  side effects, media durability, and explicit static-review limitations.
- Added a deterministic query extractor and generated a catalog from 170
  Firestore-candidate files: 74 contain 386 recognized reads, filters, ordering,
  pagination, listeners, collection groups, projections, and aggregates.
- Published `current-query-contract.md` and `EVID-QUERY-001`; static query and
  declared-index characterization is complete. Deployed index/runtime evidence
  remains open.
- Added separate fail-closed Firestore/Auth and Storage/reference profilers,
  a shared exact-target/redaction/hashed-artifact runtime, a mutation-API source
  guard, and gitignored production-derived output location.
- Resolved the exact target to project `ledger-nine4`, account
  `1dd4fd75-8eea-4f7a-98e7-bf45b987ae94`, and bucket
  `ledger-nine4.firebasestorage.app`. No production call was made because this
  host does not currently expose an acceptable service-account credential.
- Adopted the Capability Evolution Method: source mechanics and possibly stale
  specs are evidence, not automatic parity requirements. Every target slice now
  requires preserve/correct/improve/redesign/retire decisions and tests.
- Assigned all 41 Swift service/Auth and 47 MCP source modules to 11 initial
  user/operational capabilities in a deterministic generated catalog. The
  capability register records the dossier queue without inventing target tables.
- Completed the first static capability dossier for identity, account session,
  invites, MCP account binding, pending-work logout and the shared operation
  lifecycle. It links services, models, UI callers, Functions, tests and specs;
  separates preserved outcomes from defects/mechanics; and defines observable
  contracts/tests without selecting Auth or target tables.
- Updated the stale authentication/offline-access spec to reflect the confirmed
  offline-first target and current Firebase behavior while retaining A-007,
  A-016, unlock/recovery and logout product questions as explicit blockers.
- Completed the media, attachments, and offline-byte-durability static dossier.
  It links the iOS upload/queue/cache/model/presentation paths, every granular
  MCP media tool, parent callers/shapes, tests, fixtures and legacy migration
  utilities without treating Firebase URL/path mechanics as parity.
- Confirmed that durable offline media is not universal in the current app:
  several create/import flows enqueue bytes, while Transaction/account/detail
  paths upload directly; queue local-display APIs have no callers; enqueue can
  report an ID after local persistence failure; and placeholder records can
  outlive retained bytes.
- Defined a backend-neutral stable-attachment/durable-receipt contract,
  private/local-first display, idempotent/resumable verification, derivative
  state, shared-reference retention, MCP ingress security, migration
  reconciliation and offline/fault/security tests.
- Reconciled `offline-first.md` with the target attachment lifecycle, corrected
  the legacy proto media field in `data-model.md` to `photos`, and recorded
  O-023 for reference removal versus permanent byte deletion/retention.
- Characterized 44 additional local/media/UI/MCP/test/fixture/migration surfaces;
  old Supabase-to-Firebase and one-off repair tools are explicitly source-only,
  not target implementation.
- Completed the Projects/Clients/settings/reference-data static dossier. It
  identified free-text Client identity, partial Project setup, orphaning hard
  delete, cross-user preference access, reorder/array races and incomplete
  Space-template callers; recorded O-024–O-026; and characterized 54 surfaces.
- Completed the unified Item creation/accounting Link/legacy-capture static
  dossier. It defines one real-Item writer, stable offline identity,
  quantity-on-one-record semantics, relationship-derived Project sections,
  story-specific Link commands and source-only proto import; it characterized
  52 additional surfaces.
- Corrected stale target dual-read guidance: the running Firebase app remains
  unchanged before hard cutover, immutable exports are imported into isolated
  target staging, the final freeze/import resolves every proto, and the target
  contains no Firebase runtime Item/proto reader or writer.
- Recorded O-027 for the exact unified name/photo/note minimum-evidence rule
  rather than copying either contradictory current form.
- Completed the Inventory/provenance/Transaction/receipt/correction static
  dossier. It separates real scope-owner money, physical placement, open
  demand/credit, Transfer and correction; defines deterministic offline history
  readiness; and characterizes 81 additional Swift/MCP/test/migration surfaces.
- Corrected the older Vendor Credit proposal: D-001/D-007 prohibit its fourth
  target Transaction type. Actual vendor money received is a scope-relative
  Return; O-028 records the still-open non-cash cancellation/account-credit
  representation.
- Recorded O-029–O-032 for Transaction void/delete, receipt one-cent behavior,
  Item tax-basis inheritance and canonical posted-versus-draft minimum evidence.
- Completed the Invoicing/collection/budget static dossier. It traces live
  Invoice sources, Expense/Fee/manual paths, collection/correction, vendor
  document intake, budget projections, access filtering, app/MCP divergence,
  rules/Functions/tests and legacy repair/migration evidence; it characterizes
  62 additional surfaces.
- Defined one target-neutral whole-Invoice collection contract: authoritative
  source-set/revision validation, one actual positive Client payment, one
  Project Purchase, immutable frozen allocations, durable idempotent result,
  and no Invoice-link or collection-Purchase budget double count.
- Defined stable budget-contribution identity and one `ProjectBudgetSnapshot`
  read contract for paid/unpaid/recognized/category values, replacing current
  Transaction-only and cached-summary authority.
- Recorded O-033 for actual collection-payment variance and O-034 for
  sent-Invoice membership revision/resend/render/delivery audit.
- Completed the reporting/search/cross-domain static dossier and classified 42
  surfaces. Defined version/readiness-aware search, report and export snapshots,
  one canonical visibility-safe projection authority, stable cursors and
  private receipt delivery; recorded O-035/O-036.
- Completed the Spaces/review/work-queue static dossier and classified 33
  surfaces. Defined typed Space/checklist/assignment/archive/review operations,
  explicit review reasons and offline readiness; recorded O-037.
- Completed the platform/transport/release/migration-control static dossier and
  classified 101 surfaces. Defined the fail-closed environment manifest, small
  target composition root, Principal-bound/versioned MCP, release manifest,
  migration runner and observability controls; explicitly rejected Firebase
  adapters and reuse of the reverse Supabase-to-Firebase migration package.
- Completed the app-shell/shared-presentation/test-support static dossier and
  classified the final 115 surfaces. Preserved reusable UI/platform outcomes,
  redesigned typed snapshot/intent/readiness boundaries, retired placeholders
  and raw Item mutation coordinators, and separated target tests from source-era
  Firestore/Sale/payment mechanics.
- Ran the deterministic whole-manifest audit across 18 batches. M0 passes with
  686 recorded surfaces, zero unclassified/missing behavior/missing evidence/
  missing batch/source-drift/validation gaps. G0.5 capability synthesis is done;
  see `EVID-M0-COVERAGE-001`.
- Exactly mapped 39 target-relevant app-shell/presentation/test surfaces and
  eight identity/membership/session/MCP-account surfaces, including all required
  owner, target surface, security, Sync, migration, reconciliation, test and
  acceptance fields; see `EVID-M2-APP-SHELL-001` and `EVID-M2-IDENTITY-001`.
- Exactly mapped 15 of 19 target-relevant media surfaces to stable attachment
  identity, protected durable local bytes, private resolution, parent-specific
  operations, revision-safe order/primary changes, secure MCP ingress and
  migration/reconciliation tests. The four detach/delete tools remain honestly
  characterized because O-023 and the canonical reference/object profile can
  still change whether those target commands exist; see `EVID-M2-MEDIA-001`.
- Exactly mapped 38 of 41 target-relevant platform/control surfaces to fail-
  closed environment/composition, Principal-bound MCP, generated contracts,
  stable errors/capabilities, protected exports, observability, hosting and
  reproducible release authority. The concrete SDK lock graph, cross-cutting
  offline contract and price/tax helper retain exact A-003/A-004,
  A-015/A-016/physical-verification and O-008/O-031 holds; see
  `EVID-M2-PLATFORM-001`.
- Exactly mapped 36 of 52 target-relevant Client/Project/reference surfaces to
  stable Client relationships, durable Project setup, readiness-aware local
  queries, revisioned notes, own-Principal preferences, normalized reference
  reads, typed ports, MCP parity and semantic tests. Sixteen writer/deletion/
  correction surfaces retain exact O-024–O-026 holds; see
  `EVID-M2-PROJECT-REFERENCE-001`.
- Exactly mapped 14 of 31 target-relevant Item creation/Link surfaces to typed
  Item query/detail/accounting-section ports, one stable physical identity,
  bounded MCP queries, revisioned safe bulk operations and target semantic
  tests. Seventeen decision-sensitive writer/schema/import/retention surfaces
  remain honestly held; O-021 is explicitly UI-only; see
  `EVID-M2-ITEM-CREATION-001`.
- Exactly mapped 23 of 66 target-relevant Inventory/Transaction surfaces to
  typed Transaction boundaries, versioned local/MCP read models, offline-ready
  provenance history, typed corrections, exact-cent audit and semantic target
  tests. Forty-three decision-sensitive writer/schema/lifecycle/planning
  surfaces remain honestly held; O-038 now owns Inventory destination-planning
  retention, granularity and lifecycle; see
  `EVID-M2-INVENTORY-TRANSACTION-001`.
- Exactly mapped 21 of 44 target-relevant Invoicing/budget surfaces to stable
  contribution identity, Invoice/billing read models, download-time financial
  authorization, durable vendor-document intake, typed ports and semantic
  collection/contribution tests. Twenty-three decision-sensitive writer/
  lifecycle/display surfaces remain honestly held; see
  `EVID-M2-INVOICING-BUDGET-001`.
- Exactly mapped 16 of 27 target-relevant Space/review surfaces to stable
  Space/checklist/review identity, readiness-aware local queries, typed create/
  update/checklist/assignment operations and semantic target tests. Eleven
  archive/review-media/work-queue surfaces remain honestly held; see
  `EVID-M2-SPACES-REVIEW-001`.
- Exactly mapped 19 of 37 target-relevant reporting/search surfaces to named
  visibility-safe projections, stable search/lookup contracts, immutable report/
  export snapshots, protected artifact lifecycle and semantic tests. Eighteen
  report-semantic/delivery/posting surfaces remain honestly held; see
  `EVID-M2-REPORTING-SEARCH-001`.
- Exactly mapped 31 of 62 target-relevant backend/Auth/Functions/rules/Storage/
  query-control surfaces to capability-specific identity/handlers/RLS/Sync,
  private attachment Storage, query/index control and source-to-target
  migration contracts. Thirty-one decision/evidence-sensitive backend surfaces
  remain honestly held; see `EVID-M2-BACKEND-CONTROL-001`.
- Audited all 427 target-relevant source/control surfaces: 260 are exactly
  mapped, 167 retain
  explicit mapping-changing blockers, zero mapped entries lack any required
  field and zero residual entries have an empty blocker list; see
  `EVID-M2-WHOLE-MANIFEST-001`.
- Added a deterministic M2 residual generator/check and generated JSON/Markdown
  queue: 167 residual surfaces grouped under 44 validated product, architecture,
  spike, or production-evidence blockers. Unknown blockers and stale artifacts
  fail `npm run conversion:residuals:check`.
- Drafted seventeen senior-level product decision packets covering all 36 product
  blockers and all 160 product-dependent residual surfaces: O-007/O-015
  explicit Item facts/provenance; O-029/O-032 Transaction post/lifecycle;
  O-023 attachment
  retention; O-026 reference-data capabilities; O-031 Item tax/basis; O-009/
  O-034 typed adjustments/sent revisions; O-003/O-004/O-005/O-010 credit,
  zero-Invoice and signed-budget behavior; and O-008/O-030 exact receipt-line
  treatment/one-cent variance; and O-006/O-033 Expense field locks/exact
  collection payment; O-035/O-036 Client Summary/shared evidence; and O-037
  Space archive/assignment; O-002/O-011–O-014 Transfer edges; and O-016/O-017/
  O-027 Item capture/acquisition readiness; O-018/O-019/O-020/O-022 proto
  migration/authority cutoff; O-024/O-025 Project/Client lifecycle; O-028
  non-cash vendor adjustment/conserved balance; and O-038 Inventory destination
  planning retention/granularity/lifecycle. O-021 is explicitly UI-only and
  deferred to UX testing. These are proposals, not approvals;
  see `EVID-M2-DECISION-PACKETS-001`.
- Applied Supabase Postgres design guidance to the proposals: explicit relational
  authority, integer cents/`timestamptz`, indexed foreign keys and RLS predicates,
  partial/composite indexes for bounded query shapes, keyset pagination, short
  deterministic-lock-order transactions, least privilege and no premature
  partitioning. No DDL or target implementation was created.
- Converted the broad A-003/A-004/A-007/A-015/A-016 and physical-device spike
  criteria into an executable S0–S9 protocol with a disposable synthetic slice,
  7,000-Item reported-scale and 20,000-Item headroom fixtures, sixteen mandatory
  hard-failure tests, Auth/optimism comparisons, seven-day offline and media/
  revocation/evolution/restore cases, precommitted thresholds, cost review,
  machine-readable evidence layout, repetition and strict no-go semantics; see
  `EVID-M2-SPIKE-PROTOCOL-001`. Execution and provider approval remain blocked.
- Added a reviewed product-authority crosswalk and generated JSON/Markdown
  audit. All 686 surfaces now resolve through 18 classification batches to an
  explicit authority set: 573 product-governed and 113 technical/control.
  All five target specs registered at that checkpoint were explicitly
  distinguished from current
  product and historical evidence; see `EVID-PRODUCT-AUTHORITY-001`.
- Made authority coverage part of `conversion:check`: missing batch mappings,
  missing authority files, product batches without a canonical target spec,
  unused canonical target specs, unresolved surfaces and stale generated audit
  artifacts fail closed. The check now also compares live discovered hashes
  with the synchronized manifest instead of detecting source drift only after
  a sync.
- Added explicit canonical-target reconciliation to the Invoicing,
  Inventory/Transaction, Project/Client, reporting, identity, Spaces, app-shell,
  and platform dossiers. Current/historical Firebase-era specs remain behavior
  or migration evidence and cannot define the redesigned target.
- Added the required Vertical Slice Implementation Method, ignored dossier
  template, and generated slice JSON/Markdown audit. Slice requirements must
  name exact existing authority headings and trace reciprocally to executable
  verification obligations across domain, Postgres, handlers, Data API grants,
  RLS, Sync, offline, media, app/MCP, migration/reconciliation, operations and
  rollback.
- Conversion checking now enforces slice readiness, derived test kinds,
  implementation/passing/rehearsal evidence and bidirectional status agreement.
  An implemented-or-later target surface without exactly one correspondingly
  advanced slice fails. A valid temporary ready-slice control passed; invalid
  ready-slice and implemented-without-slice controls failed; see
  `EVID-SLICE-METHOD-001`.
- Adopted the long-running goal operating model: the goal owns the coherent
  outcome while repository instructions, execution state, slice dossiers,
  generated audits and evidence own durable truth. Fresh, resumed, handed-off
  and compacted agents must reconstruct state rather than trust conversation
  memory.
- Tightened `AGENTS.md` and the conversion README so target implementation reads
  the full method and active dossier, reconciles the working diff, reruns the
  conversion check and continues autonomously through routine checkpoints while
  respecting explicit decision/credential/spend/production/cutover boundaries.
- Added a narrow repository-local Codex `SessionStart` hook for `source=compact`.
  Its deterministic contract reads state version/checkpoint/next action, runs
  the conversion check and supplies bounded context to the immediate
  continuation. It does not mutate state or grant authority; one-time Codex hook
  trust and a live compaction observation remain before full evidence. See
  `EVID-CONTINUITY-001`.
- Added a pull-request conversion-control workflow using Node.js 22. It runs the
  conversion, capability, query, residual and M0 controls and rejects generated
  rewrites. The first workflow run and repository branch-protection requirement
  remain external verification/administration steps; no merge-enforcement claim
  is made yet.
- Started the first machine-enforced technical slice,
  `target-environment-isolation`, with exact architecture/conversion
  requirements, complete contract applicability, reciprocal verification, and
  explicit non-authority limits.
- Added the public, dependency-free `LedgerTargetCore` package. Its closed
  target environment manifest, exact contract/resource allowlists, safe
  diagnostics, deterministic per-Principal/Account local namespaces, persisted
  environment binding, PowerSync descriptor, and pre-dependency/local-state
  bootstrap gates import no provider SDK.
- Added 12 deterministic package tests. They pass for manifest validation,
  Firebase-kind refusal, mixed/production resource refusal, contract mismatch,
  safe diagnostics, pre-bootstrap refusal, restart-stable namespace isolation,
  required identity inputs, stale persisted-binding byte preservation, and
  matching-binding reopen.
- Added a separate reproducible `LedgerTarget.xcodeproj`, generated from
  `LedgerTargetProject.yml`; the source Firebase `LedgeriOS.xcodeproj`
  remains unchanged. The target project builds a fixed
  `apps.nine4.ledger.staging` / `Ledger STAGING` shell for macOS and iOS
  Simulator, links only the local target core, shows permanent staging/no-hosted-
  services banner code, and contains only unprovisioned synthetic identifiers.
- Added a fail-closed graph/import/source-contamination check and root commands
  for target checks, tests, generation, and both platform builds. Repeated
  XcodeGen output is byte-stable on this host.
- Extended the pull-request workflow with a separate macOS target job for the
  boundary check, 12 tests, both builds, and clean-diff verification. Its first
  external run remains pending; the slice therefore stays `in_progress` and
  `TARGET-ENV-TEST-005` remains planned.
- Recorded partial implementation evidence in
  `EVID-TARGET-ENVIRONMENT-001`. No hosted resource, credential, network
  backend, source Firebase implementation, production read/mutation, deployment,
  migration, release, or cutover was used.
- Opened draft pull request `#1` only as the review/CI surface for the isolated
  Supabase branch. GitHub Actions run `33555553117` passed both conversion
  traceability and isolated-target jobs at commit `2da54304`, including the
  target boundary check, 12 package tests, macOS build, generic iOS Simulator
  build and clean-diff verification. The Firebase worktree/branch remained
  unchanged; the draft was not merged and grants no deployment or cutover
  authority.
- Completed and verified the decision-independent
  `operation-lifecycle-and-readiness` technical slice. The dependency-free
  target core now owns typed Operation/Account/Principal IDs, a typed command
  envelope and closed preconditions, canonical epoch-millisecond codec and
  SHA-256 fingerprint, queued receipt versus authoritative snapshot/outcome,
  the closed lifecycle transition graph, stable error/retry/rejection values,
  an Account-scoped restartable reference journal, provider-free operation and
  health ports, and explicit subscription/pending/write-block readiness.
- Added eleven deterministic operation/restart/readiness tests. The first run
  exposed and then corrected a mismatched date decode strategy; the final 11
  operation tests and all 23 target-package tests pass. Exact replay,
  same-ID/different-payload refusal, transient requeue, permanent rejection
  without queue starvation, lost-response replay, illegal transition refusal,
  restart restoration, Account isolation, online/readiness separation,
  explicit required-update/contract blocks, retained original result/rejection
  evidence through supersession/resolution, and safe diagnostics are proven in
  `EVID-OPERATION-CORE-001`.
- Advanced the two target-only operation code/test surfaces to `verified`,
  extended the reviewed platform authority set to the operation/domain/port
  architecture files, and regenerated coverage/authority/slice audits. The
  initial checkpoint also overclaimed three broader current MCP/app/test-helper
  replacements; the later Phase 1 audit corrected those surfaces and removed
  them from the slice because concrete app/MCP/test-harness integration was
  explicitly not applicable. No Postgres schema, RLS, Data API grant, PowerSync
  Stream, provider adapter, hosted resource, Firebase implementation,
  migration, deployment or production operation was introduced.
- Implemented the decision-independent `versioned-contract-catalog` technical
  slice with one canonical registry and deterministic Swift, TypeScript and
  bounded MCP-resource projections. All projections embed catalog SHA-256
  `1a42004b…`, and the target TypeScript package pins compiler 5.9.3 with no
  runtime dependencies.
- Added strict shape/version/cross-reference/test-owner/size/leakage validation,
  reciprocal deprecation checks, generated-file freshness enforcement and
  nineteen intentional malformed-catalog controls. Six catalog tests and all
  29 target-package tests pass; strict TypeScript compilation, isolated target
  checks, macOS build, generic iOS Simulator build, clean source-project diff
  and diff formatting also pass locally. See `EVID-CONTRACT-CATALOG-001`.
- Advanced only the ten new target implementation surfaces to `implemented`.
  The ten broader current-MCP replacement surfaces deliberately remain
  `target_mapped` because product command/query DTOs, transport execution,
  container/deployment controls and full app/MCP parity are not implemented by
  this platform-only catalog. Exact-commit external CI remains the final
  `CONTRACT-CATALOG-TEST-003` obligation before verification.
- Parent-commit GitHub Actions run `33557226244` passed the isolated target job
  but failed conversion traceability because the query catalog had not been
  regenerated after new Swift/script candidates and the residual generator
  recognized only the literal `target_mapped` status. This checkpoint excludes
  target-only scripts from Firebase query-source candidates, treats every later
  lifecycle status as mapped-or-later, regenerates both artifacts, and passes
  the complete local workflow command set. The failed run is not accepted as
  verification; a new exact-commit run is required.
- Exact implementation commit `c79484a8` passed immutable GitHub Actions run
  `33559241558`: both conversion traceability and isolated-target jobs passed,
  including generated contract validation, the then-configured 12 environment
  tests, macOS and generic iOS Simulator builds, and clean-diff checks. All 29
  then-current package tests also passed locally; corrected cumulative run
  `33567370249` later passed the complete 47-test suite with the implementation
  unchanged. All three catalog obligations and exactly its ten target-only
  surfaces are now `verified`.
- Created and passed the ready gate for `shared-list-query-presentation`, then
  implemented target-only named query/sort/filter/action profiles, normalized
  search, stable-ID tie ordering, query-bound opaque cursors, local version/as-
  of snapshots, explicit readiness/empty/failure states, typed presentation
  intents, and a pure cached-first reducer. Raw not-found/authorization/
  authentication causes collapse internally before the public update boundary.
- Added three deterministic domain/restart/rejection tests; all 32 target tests,
  the target boundary guard, macOS build, generic iOS Simulator build and clean
  source-project diff pass locally. Only the two new target code/test surfaces
  are `implemented`; four broader current list-control replacements remain
  `target_mapped` pending concrete UI/accessibility and feature profiles. See
  `EVID-SHARED-LIST-001`.
- Exact implementation commit `587ce11e` passed immutable GitHub Actions run
  `33560578730`: both conversion traceability and isolated-target jobs passed,
  including the then-configured environment tests, generated contracts, target
  boundary checks, macOS and generic iOS Simulator builds, and clean tracked
  artifacts. Corrected cumulative run `33567370249` later passed all 47 target
  tests with the implementation unchanged. All four shared-list obligations and
  exactly its two target-only surfaces are now `verified`; the four concrete
  source UI replacements remain `target_mapped`.
- Created and passed the ready gate for
  `scoped-route-resolution-and-restoration`, then implemented target-only
  registered stable routes, bounded subject/parent scope, environment/
  Principal/Account restoration, opaque deterministic keys, activation-bound
  resolution, explicit not-synced/retry states, structural non-enumeration, and
  late-workspace-result refusal. Live resolution requests are intentionally not
  decodable without registry validation.
- Added three deterministic domain/restart/rejection tests; all 35 target tests,
  the target boundary and contract checks, macOS build, generic iOS Simulator
  build, clean source-project diff, and diff formatting pass locally. Only the
  two new target code/test surfaces are `implemented`; concrete current routes,
  views, workspace/Auth lifecycle, and accessibility remain unadvanced. See
  `EVID-SCOPED-ROUTE-001`.
- Exact implementation commit `bb978212` passed immutable GitHub Actions run
  `33562117852`: both conversion traceability and isolated-target jobs passed,
  including the then-configured environment tests, generated contracts, target
  boundary checks, macOS and generic iOS Simulator builds, and clean tracked
  artifacts. Corrected cumulative run `33567370249` later passed all 47 target
  tests with the implementation unchanged. All four scoped-route obligations
  and exactly its two target-only surfaces are now `verified`; current Firebase-
  era route/view surfaces remain unadvanced.
- Created and passed the ready gate for `typed-edit-draft-and-submission`, then
  implemented target-only unchanged/set/clear field values, typed Account/
  actor/contract/entity/revision-bound drafts, stable validation results,
  exact operation-envelope binding, and provider-free receipt/result
  presentation. Binding cannot be directly constructed or decoded; restart
  recreates it by revalidating the typed draft and queued envelope.
- Added four deterministic domain/restart/rejection/presentation tests; all 39
  target tests, target boundary and contract checks, macOS build, generic iOS
  Simulator build, clean source-project diff, and diff formatting pass locally.
  Only the two new target code/test surfaces are `implemented`; current editors,
  product field rules, commands/handlers, concrete UI, and MCP remain
  unadvanced. See `EVID-TYPED-EDIT-001`.
- Exact implementation commit `10a7db79` passed immutable GitHub Actions run
  `33563347569`: both conversion traceability and isolated-target jobs passed,
  including the then-configured environment tests, generated contracts, target
  boundary checks, macOS and generic iOS Simulator builds, and clean tracked
  artifacts. Corrected cumulative run `33567370249` later passed all 47 target
  tests with the implementation unchanged. All five typed-edit obligations and
  exactly its two target-only surfaces are now `verified`; current editors and
  feature commands remain unadvanced.
- Created and passed the ready gate for
  `privacy-safe-telemetry-and-correlation`. Exactly two comment-only target
  scaffolds are mapped to stable signal IDs, validated environment/build scope,
  domain-separated opaque correlation, exact allowlisted bounded values,
  canonical offline representation, and deterministic redaction/refusal.
  Current app/MCP logging remains unadvanced; no sink, emission, provider,
  hosted resource, credential, product event, migration or production action
  exists. See `EVID-TELEMETRY-001`.
- Implemented the ready telemetry slice with closed target signal and dimension
  IDs, generated telemetry-class validation, validated environment/build/
  contract scope, typed domain-separated HMAC-SHA256 correlation, exact
  dimension/correlation/unit/range allowlists, deterministic canonical bytes,
  a 1,536-byte envelope ceiling, and stable redaction/refusal by data class.
  Four focused tests and all 43 target tests pass, as do target boundary and
  generated-contract checks, macOS/iOS Simulator target builds, clean source-
  project isolation and diff formatting. Exactly the two target-only telemetry
  surfaces are `implemented`; current logging/telemetry surfaces remain
  `target_mapped`. Exact-commit CI is still required before verification.
- Exact implementation commit `4277afc5` passed immutable GitHub Actions run
  `33565583450`: both conversion traceability and isolated-target jobs passed,
  including the then-configured environment tests, generated contracts, target
  boundary checks, macOS and generic iOS Simulator builds, and clean tracked
  artifacts. Corrected cumulative run `33567370249` later passed all 47 target
  tests with the implementation unchanged. All four telemetry obligations and
  exactly its two target-only surfaces are now `verified`; current app/MCP/
  performance logging remains unadvanced.
- Created and passed the ready gate for
  `reproducible-release-manifest-and-artifact-integrity`. Exactly two comment-
  only target scaffolds are mapped to validated release build/channel/contract
  identity, immutable artifact and dependency-lock hashes, canonical manifest
  evidence, compatibility refusal, and an evidence-only non-authority boundary.
  Current release scripts remain unadvanced; no signer, upload, provider,
  hosted resource, deployment, migration execution, production release or
  cutover action exists. See `EVID-RELEASE-MANIFEST-001`.
- Implemented the ready release-manifest slice with closed release values,
  environment-derived build identity, exact generated-catalog and schema/query/
  operation/Sync binding, immutable artifact/dependency-lock byte evidence,
  deterministic canonical restart bytes/content digest, exact compatibility and
  tamper failures, fixed count/size ceilings, and a single evidence-only
  disposition. Four focused tests and all 47 target tests pass, as do target
  boundary and generated-contract checks, macOS/iOS Simulator target builds,
  clean source-project isolation and diff formatting. Exactly the two target-
  only release-manifest surfaces are `implemented`; current release scripts
  remain `target_mapped`. Exact-commit CI is still required before verification.
- Exact implementation commit `81726e3b` passed immutable GitHub Actions run
  `33567370249`: both conversion traceability and isolated-target jobs passed,
  including the corrected complete 47-test target package suite, generated
  contracts, target boundary checks, macOS and generic iOS Simulator builds,
  and clean tracked artifacts. All four release-manifest obligations and exactly
  its two target-only surfaces are now `verified`; current release scripts
  remain `target_mapped`.
- The same checkpoint corrected an inherited CI evidence gap: earlier isolated-
  target runs executed only the 12 environment tests despite evidence prose
  saying “all target tests.” The workflow now runs the complete package, prior
  evidence names the exact split instead of overstating the old runs, and
  immutable run `33567370249` supplies cumulative hosted proof for all 47
  unchanged target tests.
- Created and passed the ready gate for
  `protected-artifact-export-lifecycle`. Exactly two comment-only target
  scaffolds are mapped to an already-authorized immutable snapshot reference,
  policy-bounded short-lived lease lifecycle, deterministic restart evidence,
  typed destination/cleanup receipt and stable fail-closed results. The dossier
  explicitly cannot choose report contents, widen visibility, authorize client
  delivery, prove filesystem protection/deletion or settle O-023/O-036. No
  bytes, files, renderer, destination adapter, provider, migration or production
  action exists; see `EVID-PROTECTED-ARTIFACT-001`.
- Implemented the ready protected-artifact slice with fixed opaque export/
  snapshot IDs and visibility-scope digest, exact immutable snapshot/profile/
  authority binding, policy and request fingerprints, a path-free short-lived
  lease, replay-validated lifecycle, canonical restart evidence and evidence-
  only terminal receipts. Four focused tests and all 51 target tests pass, as do
  target boundary and generated-contract checks, macOS/iOS Simulator target
  builds, clean source-project isolation and diff formatting. Exactly the two
  target-only surfaces are `implemented`; current report/export/PDF/share/
  platform destination surfaces remain `target_mapped`. Exact-commit CI is
  still required before verification.
- Exact implementation commit `10d94f1f` passed immutable GitHub Actions run
  `33569882379`: both conversion traceability and isolated-target jobs passed,
  including all 51 target tests, generated contracts, target boundary checks,
  macOS and generic iOS Simulator builds, and clean tracked artifacts. All four
  protected-artifact obligations and exactly its two target-only surfaces are
  now `verified`; current report/export/PDF/share/platform destination surfaces
  remain `target_mapped`.
- Selected and passed the ready gate for
  `migration-run-plan-and-journal-integrity` only after confirming the boundary
  is explicitly owned by the migration/release architecture and reviewed
  platform dossier. Exactly two comment-only surfaces live under a separate
  target migration-control module; neither is linked into the target app.
- The ready dossier binds immutable source/target/Account/artifact/version
  evidence, deterministic journal/replay/resume semantics, exact per-entity
  outcomes, named reconciliation and permanent evidence-only non-authority to
  six planned domain/restart/rejection/migration/reconciliation/operational
  obligations. It cannot read an export, connect to a target, persist a journal,
  sign or approve a plan, execute/roll back a migration or authorize cutover.
- Extended automatic conversion discovery to the separate migration-core/test
  directories and re-acknowledged only the exact reviewed control-script hash.
  Sync/check/report pass at 725 recorded / 710 discovered surfaces with zero
  errors and the same three documented retired-path warnings. The existing
  reverse Supabase-to-Firebase package remains source-only and untouched.
- Implemented `LedgerTargetMigrationCore` as a second provider-free Swift
  package product that depends only on `LedgerTargetCore` and is linked by
  neither application project. The graph guard now validates the separate
  tooling/test edges, provider-import coverage and app/source-project exclusion.
- Added immutable source/target/Account/artifact/entity plan identity,
  canonical evidence-only plan bytes, monotonic replay-safe journal events,
  interruption/resume fingerprints, overflow-safe exact counts, terminal
  manifest/reconciliation closure and canonical restart/tamper refusal. No
  exporter, transform, loader, database/file/provider adapter, journal store,
  signer, operator authorization or executor exists.
- Bound every public journal boundary to the same exact plan policy and added a
  negative direct-decoding bypass fixture, so a structurally decodable but
  changed plan cannot start, append, encode or restore journal evidence.
- Four focused migration-integrity tests and all 55 target package tests pass
  locally, as do target boundary/contract checks, reproducible project
  generation and macOS/generic-iOS-Simulator staging builds. Five of six slice
  obligations pass locally; the exact-commit operational CI obligation remains
  planned, so exactly its two target-only surfaces are `implemented` rather
  than `verified`.
- Exact implementation commit `34d52dba` passed immutable GitHub Actions run
  `33573298495`: both conversion traceability and isolated-target jobs passed,
  including all 55 target tests, generated contracts, dependency/application-
  graph guards, macOS and generic iOS Simulator builds and clean tracked
  artifacts. All six migration-run obligations and exactly its two target-only
  surfaces are now `verified`.
- Selected `operational-health-and-objective-registry` only after auditing the
  architecture and reviewed `MAN-OBS-001`, `SWIFT-7B159D426B1D`,
  `SWIFT-2703ADAB66C5` and `TEST-ECE08B24ADCE` mappings. Those broader source
  outcomes remain `target_mapped`: a registry without actual emitters,
  lifecycle wiring, adapters, approved thresholds and physical evidence is not
  their replacement.
- Created exactly two comment-only target scaffolds and a ready dossier for
  provider-free health derivation, complete measurement/objective/alert/runbook
  topology, evidence-gated objective evaluation, spike-pending numeric budgets,
  canonical restart evidence and permanent candidate-only/non-authority.
  Conversion sync/check and residual controls pass at 727 recorded / 712
  discovered surfaces, 301 mapped, 164 residual and 43 blockers, with only the
  three documented retired-path warnings. No behavioral code, metric emission,
  hosted alert, provider, production threshold or operational action exists.
- Implemented the ready operational-health slice with one validated health
  snapshot over the shared SyncHealthSnapshot, explicit nonnegative ages and
  separate connectivity/Auth/subscription/checkpoint/queue/attachment/rejection/
  write/transient components. Online and synchronized remain independent,
  including offline-ready and online-unsynchronized states.
- Added the complete closed client/server/replication/cross-cutting measurement
  registry, seven exact-zero evidence-gated service objectives, twelve grouped/
  rate-limited alert candidates, twelve structurally complete runbook topics
  and twelve performance-budget measurements that remain pending the vertical
  spike with no numeric production threshold.
- Added bounded canonical health/registry evidence and stable refusal for
  invalid time/count, duplicate/missing/reference/policy/evidence, digest,
  canonical and size failures. Every policy remains candidate-only and every
  registry remains evidence-only; no type can emit/acknowledge/resolve an alert,
  execute a runbook or approve a threshold.
- Four focused operational-health tests and all 59 target package tests pass
  locally. Three of four slice obligations pass; exact-commit operational CI
  remains planned, so exactly the two target-only surfaces are `implemented`
  and the broader current observability/performance surfaces remain
  `target_mapped`.
- Exact implementation commit `4fdb363f` passed immutable GitHub Actions run
  `33576448917`: both conversion traceability and isolated-target jobs passed,
  including all 59 target tests, graph/generated-contract checks, macOS and
  generic iOS Simulator builds and clean tracked artifacts. All four
  operational-health obligations and exactly its two target-only surfaces are
  now `verified`; the broader current observability/performance/navigation/test
  surfaces remain `target_mapped`.
- Audited the remaining Phase 1 composition-root and deterministic test-support
  mappings and found one historical scope inconsistency: operation-lifecycle
  had verified `MCPMOD-DAB760104CEE`, `SWIFT-F26052171FEB`, and
  `FILE-F29942C1A7F4` even though its dossier explicitly omitted concrete
  app/MCP integration and a shared target harness. Corrected those three to
  `target_mapped`, removed them from the operation slice, retained only the two
  actual target files as verified, and updated evidence/tracker counts. No code
  or already-passing operation behavior changed.
- Extended conversion discovery to separate target test-support and self-test
  roots, acknowledged only the exact reviewed control-script hash, created two
  comment-only target scaffolds, and passed their deterministic-target-test-
  support ready mapping. The dossier binds validated synthetic environment/
  Principal/Account context, fixed clock/IDs/revisions, immutable scripted
  operation/readiness/failure adapters, canonical restart evidence and stable
  production/provider/tamper refusal to domain, offline and operational tests.
  Current Swift helper `TEST-6A6B0926E2EE` and MCP helper
  `FILE-F29942C1A7F4` remain `target_mapped`; no behavior, package target,
  application link, database, provider, hosted resource, product fixture,
  migration or production operation exists at this ready checkpoint.
- Implemented `LedgerTargetTestSupport` as a separate provider-free Swift
  package product depending only on `LedgerTargetCore`, plus a self-test target
  depending only on those two modules. Neither application project links the
  support module; the graph guard now enforces those edges, scans both support
  roots for provider imports and rejects application/source-project
  contamination.
- Added validated synthetic non-production context, finite domain-separated
  clock/Operation-ID/Entity-ID/revision schedules, immutable Account-scoped
  operation/unresolved/readiness/durability scripts, safe terminal failures,
  lifecycle/order/cross-reference validation and bounded canonical restart
  evidence with digest/tamper/noncanonical/size refusal. Decode reconstructs
  through the environment, schedule, operation-script and Sync-health
  validators rather than trusting Codable structure.
- Four focused test-support tests and all 63 target package tests pass locally,
  as do target graph/contract checks and macOS/generic-iOS-Simulator staging
  builds. Three of four slice obligations pass; exact-commit hosted CI remains
  planned, so exactly its two target-only surfaces are `implemented`. Current
  Swift/MCP helper surfaces remain `target_mapped`; no domain-specific product
  fixture, app/MCP wiring, local database, provider, hosted resource, Firebase
  change, migration or production operation was introduced.
- Exact implementation commit
  `986d633eec2884d1138e0613f9fc35d68ae913c3` passed immutable GitHub Actions
  run `33579458286`: conversion traceability and the isolated-target job both
  passed, including graph/generated-contract checks, all 63 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All four
  test-support obligations and exactly its two target-only surfaces are now
  `verified`; current Swift/MCP helper surfaces remain `target_mapped`.
- Audited the remaining Phase 1 dependency order and selected
  `validated-target-composition` as the next smallest decision-independent
  technical slice. Exactly two comment-only target scaffolds define the future
  explicit environment/version-bound composition contract and self-tests;
  current Firebase root `SWIFT-88C69E26FBA0`, target app/MCP wiring, provider
  adapters and target-environment package/project surfaces remain unadvanced.
- The ready dossier binds exact Phase 1, composition-root, feature-activation,
  dependency-rule and port-contract requirements to typed dependency/capability
  closure, reference-versus-runtime separation, canonical structural receipt,
  stable refusal and operational graph/source-isolation tests. No behavior,
  package target, application link, SDK, database, hosted service, product
  command, migration or production operation exists at this checkpoint.
- Implemented `LedgerTargetComposition` as a separate provider-free package
  product depending only on `LedgerTargetCore`; its self-test target may also
  depend on `LedgerTargetTestSupport`. Neither application project links the
  module, and the graph guard now enforces exact package edges, scans both new
  roots for provider imports, and rejects premature composition/source-project
  contamination.
- Added exact environment/use/version-bound dependency plans for the generated
  contract catalog, operation queries and Sync health; exact stable
  implementation/capability ownership; explicit reference-versus-runtime
  classes; typed port assembly; stable fail-closed dependency/catalog/
  capability results; and a bounded structural-only canonical receipt that
  restores through the same validators without reconstructing adapters.
- Three focused composition tests and all 66 target package tests pass locally,
  as do the target graph/generated-contract checks and macOS/generic-iOS-
  Simulator staging builds. Three of four slice obligations pass; exact-commit
  hosted CI remains planned, so exactly the two target-only composition
  surfaces are `implemented`. Current Firebase root, app/MCP integration,
  provider adapters and target application project surfaces remain unadvanced.
- Exact implementation commit
  `be88c5b9e42eef90018f84012f5a3e60f9631009` passed immutable GitHub Actions
  run `33581326840`: conversion traceability and isolated-target jobs both
  passed, including graph/generated-contract checks, all 66 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All four
  composition obligations and exactly its two target-only surfaces are now
  `verified`; current Firebase root, app/MCP/provider integration and target
  application project surfaces remain unadvanced.
- Audited the remaining Phase 1 foundations after composition and selected
  `exact-money-and-domain-identity` as the next smallest decision-independent
  technical slice. Exact signed integer-minor-unit representation, explicit
  currency identity and stable entity ID types are shared prerequisites for
  later product/database/migration slices and do not settle product signs,
  bounds, allocation, tax, rounding, posting or currency policy.
- Created exactly two comment-only target scaffolds in the existing provider-
  free core/test roots and a complete ready dossier covering stable IDs, Money/
  currency, checked arithmetic, restart decoding and malformed/cross-currency/
  overflow refusal. No behavior, product command/read model, app/MCP link,
  database, provider, hosted resource, source transform, migration or
  production operation exists at this checkpoint.
- Implemented the ready exact-money/domain-identity slice with distinct typed
  Client/Project/Item/Invoice/Transaction/Expense/Fee/Space/Attachment IDs,
  exactly-three-uppercase-ASCII-letter CurrencyCode, signed Int64-minor-unit
  Money, checked same-currency amount equality/order/add/subtract/negate, decode-
  through-validation and stable bounded failures.
- Three focused primitive tests and all 69 target package tests pass locally,
  as do the target graph/generated-contract checks and macOS/generic-iOS-
  Simulator staging builds. Canonical restart evidence emits exact integer
  boundaries; fractional numeric input, malformed identity/currency, cross-
  currency operations and every arithmetic overflow edge fail atomically.
- The evidence deliberately does not claim lexical rejection of every exactly
  integral decimal-form JSON token because Swift's standard Int64 decoder may
  accept a spelling such as `1.0`; canonical target encoding remains integer-
  only and the domain never stores or calculates floating-point money.
- Three of four slice obligations pass. Exact-commit hosted CI remains planned,
  so exactly the two target-only primitive surfaces are `implemented`, not
  `verified`. No product sign/bound/currency/rounding/tax policy, app/MCP link,
  database, provider, migration, hosted resource or production operation was
  introduced.
- Exact implementation commit
  `7133aef5a17f946f0f01c084015145592d7bc4ce` passed immutable GitHub Actions
  run `33582602647`: conversion traceability and isolated-target jobs both
  passed, including graph/generated-contract checks, all 69 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All four
  primitive obligations and exactly its two target-only surfaces are now
  `verified`; all product accounting, current app/MCP, database/provider,
  migration and production surfaces remain unadvanced.
- Audited the remaining Phase 1 boundary after exact primitives and selected
  `client-project-directory-read-contracts` as the first decision-independent
  product-domain foundation. D-006 and the canonical Client spec settle stable
  Account-scoped Client identity and required same-Account Project relationship;
  O-024/O-025 can remain fully open because mutation, reassignment, merge and
  deletion are excluded.
- Created exactly two comment-only target scaffolds in the existing provider-
  free core/test roots and a complete ready dossier for Client/Project summaries,
  exact ID/Account relationship validation, validated duplicate-free local list
  snapshots and the architecture-named `ClientProjectDirectoryQuerying` port.
  Postgres, handlers, Data API, RLS, Sync Streams, media, concrete app/MCP,
  migration, observability and rollout are explicit non-applicabilities.
- Extended only the reviewed Project/Client authority set with the architecture
  files needed by target implementation and mapped the two new target surfaces.
  Sync/check/report pass at 735 recorded / 720 discovered, 309 target-mapped or
  later / 473 target-relevant, 164 residual and 43 blockers, with only the three
  documented retired-path warnings. No behavioral code, source app/MCP surface,
  provider, database, hosted resource, migration or production operation exists
  at this ready checkpoint.
- Implemented the ready Client/Project directory slice with exact nonblank
  display values, finite ordered Client audit time, Account-scoped Client
  summaries, same-Account/exact-Client Project summaries, duplicate-free local
  Client/Project snapshots and the backend-neutral
  `ClientProjectDirectoryQuerying` watch port. Display names remain display-only:
  two equal names never collapse identity or repair a relationship.
- Added three focused domain/restart/refusal tests. They prove ready, partial and
  authoritative-empty local evidence, byte-identical canonical restart,
  construction/decode revalidation, same-name distinct Clients and atomic stable
  refusal for blank names, invalid time, Account/relationship mismatch,
  duplicate identity, incomplete authority and wrong-Account port use.
- All three focused tests and all 72 target tests pass locally, as do the target
  graph/generated-contract checks and macOS/generic-iOS-Simulator staging
  builds. Three of four slice obligations pass; exact-commit hosted CI remains
  planned, so exactly the two target-only directory surfaces are `implemented`.
  Current Project/app/MCP, schema/RLS/Sync/provider and migration surfaces remain
  unadvanced; no Firebase change, hosted resource or production operation was
  introduced.
- Exact implementation commit
  `3c0b58b66e61ab8351d823bf0e0bdcaca7d1c9ff` passed immutable GitHub Actions
  run `33584456794`: conversion traceability and isolated-target jobs both
  passed, including graph/generated-contract checks, all 72 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All four
  directory obligations and exactly its two target-only surfaces are now
  `verified`; current Project/app/MCP, schema/RLS/Sync/provider and migration
  surfaces remain unadvanced.
- Audited the remaining Phase 1/domain dependency order after Client/Project
  verification and selected `transaction-taxonomy-and-transfer-identity` as the
  smallest next decision-independent accounting foundation. D-001/D-002/D-007
  settle the exact scope-relative Purchase/Return meanings; D-003–D-006 settle
  project-only non-cash Transfer, exact same-Client routing and structural pair
  identity without choosing any open amount, Item, Invoice, Space, lifecycle or
  correction behavior.
- Created exactly two comment-only target scaffolds in the provider-free core/
  test roots and a complete ready dossier for the closed three-type taxonomy,
  explicit Inventory/Project owner scope, compatible record roles, exact-ID
  active-destination route, Operation-bound distinct Transfer pair, canonical
  restart and stable invalid-combination refusal.
- Extended only the reviewed Inventory/Transaction authority set with the
  architecture files needed by target implementation. Postgres, handlers, Data
  API, RLS, Sync Streams, media, concrete app/MCP, legacy enum migration,
  observability and activation are explicit non-applicabilities. D-017 and
  O-002/O-011–O-015/O-028–O-032 remain fully open for excluded effects.
- Sync/check/report pass at 737 recorded / 722 discovered, 311 target-mapped or
  later / 475 target-relevant, 164 residual and 43 blockers, with only the three
  documented retired-path warnings. M0 passes; M1 and M2 remain honestly
  blocked by the unchanged two and 164 prerequisites. No behavioral code,
  source app/MCP surface, provider, database, hosted resource, migration or
  production operation exists at this ready checkpoint.
- Implemented the ready Transaction taxonomy slice with the exact closed
  Purchase/Return/Transfer type, validated Inventory/Project owner scope,
  derived economic meaning, compatible standalone/source/destination roles,
  exact-ID same-Account/same-Client/distinct-Project active-destination route,
  Operation-bound distinct Transfer pair identity, decode revalidation and
  stable bounded failures. Display names carry no route authority.
- Added four focused domain/restart/refusal tests. They prove all valid scope-
  relative meanings, byte-identical canonical restart, equal-name/different-
  Client refusal, Inventory/cross-Account/cross-Client/same-Project/archived-
  destination refusal, duplicate pair refusal, malformed aggregate decoding
  and every stable diagnostic code.
- All four focused tests and all 76 target package tests pass locally, as do
  target graph/generated-contract checks and macOS/generic-iOS-Simulator
  staging builds. Four of five slice obligations pass; exact-commit hosted CI
  remains planned, so exactly the two target-only taxonomy surfaces are
  `implemented`. No writer, money rule, Item/Invoice/Space effect, correction/
  lifecycle behavior, schema/RLS/Sync/provider, app/MCP wiring, legacy import,
  Firebase change, hosted resource, migration or production operation was
  introduced.
- Exact implementation commit
  `031a240a703232216a4efff9686c1516a35a82f4` passed immutable GitHub Actions
  run `33585853504`: conversion traceability and isolated-target jobs both
  passed, including graph/generated-contract checks, all 76 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All five
  taxonomy obligations and exactly its two target-only surfaces are now
  `verified`; every excluded writer/accounting/provider/migration surface
  remains unadvanced.
- Audited the next Phase 1/domain dependency after exact Client/Project and
  Transfer-route verification and selected
  `transfer-destination-selection-contracts` as the smallest user-meaningful,
  decision-independent read boundary. D-003/D-005/D-006 and the canonical
  picker story settle exact same-Account/same-Client/distinct active-Project
  eligibility without choosing Items, amount, Invoice, Space, tag, correction,
  credit, persistence or provider behavior.
- Created exactly two comment-only target scaffolds in the provider-free core/
  test roots and a complete ready dossier for exact-ID filtering, validated
  candidate routes, source-bound directory/query fingerprints, deterministic
  order, available versus authoritative-empty versus incomplete local evidence,
  canonical restart and stable tamper/refusal behavior.
- Postgres, handlers, Data API, RLS, Sync Streams, local persistence, media,
  concrete app/MCP, source migration, observability and activation are explicit
  nonapplicabilities. Locally valid eligibility is not authorization. No
  behavioral code, current picker/app/MCP surface, Firebase change, provider,
  hosted resource, migration or production operation exists at this ready
  checkpoint.
- Implemented the ready Transfer destination-selection slice with exact
  same-Account/same-Client active-Project filtering, source and Business
  Inventory exclusion, validated direct routes, source-directory/query
  fingerprints, deterministic order, distinct available/authoritative-empty/
  incomplete states, decode revalidation and stable bounded failures. Partial
  or stale evidence may expose an already validated candidate while retaining
  its non-ready quality; an empty partial/stale directory never becomes an
  authoritative empty result.
- Added four focused domain/restart/refusal tests. They prove equal-name/
  different-Client exclusion, directory-order preservation, source/directory
  rebinding, ready/partial/stale evidence, byte-identical restart through the
  local read port, cross-Account/route/duplicate/completeness/fingerprint/
  malformed refusal and every public diagnostic code.
- All four focused tests and all 80 target package tests pass locally, as do
  target graph/generated-contract checks, macOS and generic-iOS-Simulator
  staging builds and diff formatting. Four of five obligations pass; exact-
  commit hosted CI remains planned, so exactly its two target-only surfaces are
  `implemented`. No Item selection, Transfer writer, server authorization,
  schema/RLS/Sync/provider, app/MCP wiring, Firebase change, migration, hosted
  resource or production operation was introduced.
- Exact implementation commit
  `6dc7d0c21ccd8c966b43b02240d14ad9fe79ea92` passed immutable GitHub Actions
  run `33587234037`: conversion traceability and isolated-target jobs both
  passed, including graph/generated-contract checks, all 80 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All five
  destination-selection obligations and exactly its two target-only surfaces
  are now `verified`; current picker/app/MCP, command, authorization, schema/
  RLS/Sync/provider and migration surfaces remain unadvanced.
- Audited the remaining Phase 1 dependency graph after exact Money,
  Purchase/Return taxonomy and Transfer destination verification and selected
  `non-item-receipt-line-reconstruction-contracts` as the smallest next
  decision-independent accounting value boundary. D-016 settles stable ordered
  embedded line identity/shape and exact reconstruction math without choosing
  billing, rounding, Item tax/basis or Transaction posting behavior.
- Created exactly two comment-only target scaffolds in the provider-free core/
  test roots and a complete ready dossier for stable ID/source wording,
  positive Money magnitude, increase/decrease effect, optional non-arithmetic
  quantity evidence, duplicate-free order, standalone Purchase/Return scope,
  exact increase/decrease/net/reconstructed/variance totals, canonical restart
  and stable classification/Account/currency/overflow/tamper refusal.
- O-008/O-030/O-031/O-032 remain fully open and outside the slice. Postgres,
  handlers, Data API, RLS, Sync Streams, local persistence, media, current app/
  MCP, source decoding/migration, observability and activation are explicit
  nonapplicabilities. No behavioral code, Firebase change, provider, hosted
  resource, migration or production operation exists at this ready checkpoint.
- Sync/check/report pass at 741 recorded / 726 discovered surfaces, 315 target-
  mapped or later / 479 target-relevant, 164 residual and 43 blockers, with only
  the three documented retired-path warnings. M0 passes; M1 and M2 remain
  honestly blocked by the unchanged two and 164 prerequisites.
- The existing 80 target tests, target graph/generated-contract checks, macOS
  and generic-iOS-Simulator staging builds and diff formatting all pass with the
  two comment-only receipt scaffolds. The receipt obligations remain planned;
  no executable receipt test or behavioral implementation is claimed at ready.
- Implemented only the ready provider-free receipt boundary: distinct line ID,
  source-preserving nonblank wording, positive exact-Money magnitude, increase/
  decrease effect, optional non-arithmetic quantity, duplicate-free source
  order, standalone Purchase/Return classification, exact increase/decrease/
  net/reconstructed/variance evidence, and a canonical SHA-256 fingerprint
  binding identity, classification, inputs, order and derived totals.
- Added four deterministic receipt tests. BLVD-like Purchase evidence exactly
  reconstructs 504,772 minor units; Wayfair-like Return evidence retains an
  exact negative-one-minor-unit variance without declaring completion. Tests
  also prove every reachable aggregation/reconstruction/variance overflow,
  mixed-currency refusal, byte-identical restart, stable diagnostics and atomic
  malformed/duplicate/reordered/derived-total/fingerprint tamper refusal.
- All four focused receipt tests and all 84 target package tests pass locally,
  as do target graph/generated-contract checks, macOS and generic-iOS-Simulator
  staging builds and diff formatting. `RECEIPT-TEST-001` through `-004` pass;
  exact-commit hosted `RECEIPT-TEST-005` remains planned, so exactly the two
  receipt surfaces are `implemented`, not `verified`.
- The receipt fingerprint is deterministic corruption/order evidence rather
  than authorization or proof of external authenticity. No completion verdict,
  Transaction writer/posting/sign policy, Item basis/tax allocation, billing,
  schema/RLS/Sync/provider, app/MCP, migration, Firebase change, hosted resource
  or production operation was introduced; O-008/O-030/O-031/O-032 remain open.
- Exact implementation commit
  `594aec1e68747fefe9fffd6a80d550c55d0c555d` passed immutable GitHub Actions
  run `33588870600`: conversion traceability passed in 11 seconds and the
  isolated-target job passed in 1 minute 31 seconds with all 84 target tests,
  graph/generated-contract checks, macOS and generic-iOS-Simulator builds and
  clean tracked artifacts. All five receipt obligations and exactly its two
  target-only surfaces are now `verified`; every excluded writer, current app/
  MCP, provider, migration and production surface remains unadvanced.
- Audited the remaining mapped Phase 1 product boundaries and selected
  `project-item-accounting-section-contracts` as the smallest next user-visible,
  decision-independent Item slice. D-019/D-022/D-023 and the canonical Item
  spec settle relationship-derived Unaccounted For / Accounted For state, one
  physical Item identity and Space/detail independence without choosing Item
  creation/Link, occurrence persistence, credit settlement or provider design.
- Created exactly two comment-only target scaffolds in the provider-free core/
  test roots and a complete ready dossier for exact Account/Project/Item-bound
  client-paid Purchase and billable charge/credit occurrence evidence,
  relationship-derived state, Unaccounted For first / Accounted For second,
  deterministic order, authoritative-empty versus incomplete/partial/stale
  local evidence, explicit unresolved rows when relationship absence is not
  authoritative, canonical restart and stable cross-scope/duplicate/tamper
  refusal.
- Extended only the reviewed Item-creation authority set with the Phase 1
  domain/read-model architecture files required by these two target surfaces.
  O-003/O-007/O-015/O-016/O-021/O-023/O-027 remain fully open and outside the
  slice. Postgres, handlers, Data API, RLS, Sync Streams, local persistence,
  media, current app/MCP, source migration, observability and activation are
  explicit nonapplicabilities.
- Sync/report pass at 743 recorded / 728 discovered surfaces, 317 target-mapped
  or later / 481 target-relevant, 164 residual and 43 blockers, with only the
  three documented retired-path warnings. No behavioral code, Firebase change,
  provider, hosted resource, migration or production operation exists at this
  ready checkpoint.
- Implemented only the ready provider-free Project Item accounting-section
  boundary: distinct Purchase-relationship/occurrence IDs, exact Account/
  Project/Client/Item-bound relationship evidence, charge/credit occurrences
  across available/live/frozen phases, relationship-derived product state, two
  deterministic ordered sections, explicit unresolved incomplete-local rows,
  local readiness/version/time and a canonical evidence fingerprint.
- A present qualifying relationship may prove Accounted For from partial/stale
  evidence. Missing relationship evidence proves Unaccounted For only when the
  relationship working set is authoritative; otherwise the Item stays outside
  both product sections as `relationshipEvidenceIncomplete`. Space never changes
  the resolution. Frozen occurrence evidence carries no amount or collection-
  transaction settlement semantics and therefore does not choose O-003.
- Added four deterministic accounting-section tests. They prove standalone
  current-Project Purchase classification, charge/credit and available/live/
  frozen qualification, one Item identity, source-order sectioning, Space
  independence, authoritative-empty versus incomplete/partial/stale truth,
  byte-identical restart through the scoped query port, every stable diagnostic,
  and atomic scope/Item/duplicate/phase/derived/fingerprint/malformed refusal.
- All four focused tests and all 88 target package tests pass locally, as do
  target graph/generated-contract checks, macOS and generic-iOS-Simulator
  staging builds and diff formatting. `ITEMACCOUNT-TEST-001` through `-004`
  pass; exact-commit hosted `ITEMACCOUNT-TEST-005` remains planned, so exactly
  the two Item-accounting surfaces are `implemented`, not `verified`.
- No Item writer/Link, occurrence persistence or transition, amount/category/
  budget effect, credit settlement, schema/RLS/Sync/provider, current app/MCP,
  source migration, Firebase change, hosted resource or production operation
  was introduced; O-003/O-007/O-015/O-016/O-021/O-023/O-027 remain open.
- Exact implementation commit
  `92e0b565d02f9a2ad3f96f195327bc2b12ae0e56` passed immutable GitHub Actions
  run `33591275648`: conversion traceability passed in 11 seconds and the
  isolated-target job passed in 1 minute 26 seconds with all 88 target tests,
  graph/generated-contract checks, macOS and generic-iOS-Simulator builds and
  clean tracked artifacts. All five Item-accounting obligations and exactly its
  two target-only surfaces are now `verified`; every excluded writer, current
  app/MCP, provider, migration and production surface remains unadvanced.
- Audited the attachment/offline boundary against the reviewed media dossier,
  offline contract, adapter ports and Phase 1 architecture and selected
  `attachment-capture-and-local-durability-receipt` as the smallest honest next
  technical slice. Stable ID/scope/byte-evidence/receipt semantics are settled;
  actual encrypted filesystem persistence and provider behavior are not.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for non-Codable raw capture input, exact environment/Principal/Account/parent
  binding, opaque local-object identity, positive byte count, SHA-256 evidence,
  canonical path-free receipt, a narrow capture-store port and stable refusal.
- O-023 remains open because the slice exposes no detach/delete/retention
  operation. A-003/A-004/A-016, O-022, SPIKE-MED-001, content/size/derivative
  policy, physical local durability, upload/display/provider, app/MCP,
  migration and production behavior remain explicitly outside the boundary.
- Implemented only the ready provider-free attachment receipt boundary:
  non-Codable raw capture bytes, stable Attachment and opaque local-object IDs,
  exact environment/Principal/Account/parent scope, integer timestamp, positive
  byte count/SHA-256 matching, canonical path-free fingerprinted receipt, a
  narrow capture-store port and closed bounded failures.
- Added four deterministic tests for matching scope/byte evidence, Attachment
  identity independent of opaque local-object identity, raw-byte/path/URL
  exclusion, byte-identical structured restart, every scope/identity/byte/
  malformed/tamper rejection and no false-success receipt from a failing test
  adapter. Four focused/all 92 target tests, graph/contracts and both staging
  builds pass locally.
- `ATTACHCAP-TEST-001` through `-004` pass locally. Deterministic receipt tests
  are not physical encrypted-filesystem or process/device-restart evidence.
- Exact implementation commit
  `1792a86292d1553a11d78ff977736f63f12cbbe4` passed immutable GitHub Actions
  run `33593116980`: conversion traceability passed in 8 seconds and the
  isolated-target job passed in 1 minute 33 seconds with all 92 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five attachment obligations and exactly its two
  target-only surfaces are now `verified`; every excluded filesystem/provider,
  current app/MCP, migration and production surface remains unadvanced.
- Audited the next Phase 1 dependency graph and selected
  `client-creation-operation-contracts` as the smallest user-meaningful command
  needed before Project setup. D-006 and the canonical Client spec settle one
  stable Account-scoped Client ID and display-name non-authority; O-025 remains
  open because rename/archive/merge/reassignment are excluded.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for exact Account/actor/contract/Operation/Client/name binding, the shared
  operation fingerprint/receipt/replay lifecycle, canonical restart, a narrow
  Client creation operation port and stable mismatch/tamper/local-failure
  refusal. No behavioral code or executable Client test exists at ready.
- Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
  durability, membership authorization, Auth/provider choice, current/target
  app/MCP, source migration, hosted resources and production remain explicit
  nonapplicabilities.
- Ready-gate sync/check and capability/query/residual controls pass at 747
  recorded / 732 discovered surfaces, 321 mapped / 164 residual / 43 blockers;
  M0 passes, M1/M2 retain the expected 2/164 blocks, and the existing 92 target
  tests, graph/contracts, both staging builds and diff formatting pass with no
  executable Client-creation behavior claimed.
- Implemented only the ready provider-free Client creation boundary: an exact
  Account/actor/contract/Client/name/time draft, minimal typed payload,
  precondition-free shared operation envelope, derived Client subject and
  fingerprint, receipt validator, narrow operation port and closed failures.
- Added four deterministic tests for same-name/different-ID identity, exact
  command scope, byte-identical structured restart, provider/path/credential
  exclusion, every binding/precondition/subject/fingerprint/receipt/malformed
  refusal and shared OperationJournal replay/same-ID-changed-payload behavior.
- Four focused/all 96 target tests, graph/contracts and both staging builds pass
  locally. `CLIENTCREATE-TEST-001` through `-004` pass; exact-commit hosted
  `CLIENTCREATE-TEST-005` remains planned, so exactly the two Client-creation
  surfaces are `implemented`, not `verified`.
- No Client row, authoritative apply, physical local durability, membership
  authorization, Client lifecycle/correction, Project setup/reassignment,
  schema/RLS/Sync/Auth/provider, current/target app/MCP, migration, hosted
  resource or production operation was introduced; O-025 remains open.
- Exact implementation commit
  `3b837af34bbbde9e7c4b6707f6366dc88d236957` passed immutable GitHub Actions
  run `33595993615`: conversion traceability passed in 10 seconds and the
  isolated-target job passed in 1 minute 50 seconds with all 96 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Client-create obligations and exactly its
  two target-only surfaces are now `verified`; every excluded server,
  authorization, provider, migration and production surface remains unadvanced.
- Audited the next Phase 1 dependency graph and selected
  `project-setup-operation-contracts` as the next smallest user-meaningful
  operation. D-006 settles stable Account-scoped Client identity; the reviewed
  capability contract and target architecture settle one Project setup intent
  with existing/new Client selection and the complete selected-category state.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for stable Project/Client identity, validated Project name/exact optional
  description, canonical duplicate-free category selection, absent/null/zero
  allocation, shared operation fingerprint/receipt/replay and stable refusal.
  No behavioral Project-setup code or executable test exists at ready.
- Corrected the target allocation guidance to retain exact non-negative
  integer-currency Money without inheriting the source UI's arbitrary 32-bit
  maximum. Empty category selection remains representable; category order is
  canonical rather than a business identity.
- Kept hero media entirely outside CreateProject under the separately verified
  attachment-capture receipt lifecycle. Media failure cannot invalidate a
  valid Project, and this slice makes no attachment-reference/upload claim.
- O-023/O-024/O-025/O-026 remain open: the slice neither changes attachment
  retention, deletes/edits/reassigns a Project, merges a Client nor mutates a
  shared category definition. Local command validation is not authorization.
- Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
  durability, Auth/provider choice, current/target app/MCP, source migration,
  hosted resources and production remain explicit nonapplicabilities.
- Ready-gate sync/check and capability/query/residual controls pass at 749
  recorded / 734 discovered surfaces, 323 mapped / 164 residual / 43 blockers;
  M0 passes, M1/M2 retain the expected 2/164 blocks, and the existing 96 target
  tests, graph/contracts, both staging builds and diff formatting pass with no
  executable Project-setup behavior claimed.
- Implemented only the ready provider-free Project setup boundary: stable
  existing/new Client selection, distinct BudgetCategoryID, exact non-negative
  nullable Money, canonical duplicate-free category state, Account/actor/
  contract/Project/name/description/time draft, precondition-free shared
  operation envelope, derived Project subject/fingerprint, receipt validator,
  narrow operation port and closed stable failures.
- Added four deterministic tests for stable existing/new Client and Project
  identity, empty/absent/null/zero category state, order-independent canonical
  encoding, byte-identical structured restart, provider/media/path/credential
  exclusion, every invalid/binding/precondition/subject/fingerprint/receipt/
  malformed refusal and shared OperationJournal replay/mismatch behavior.
- Four focused/all 100 target tests, graph/contracts and both staging builds pass
  locally. `PROJECTSETUP-TEST-001` through `-004` pass; exact-commit hosted
  `PROJECTSETUP-TEST-005` remains planned, so exactly the two Project-setup
  surfaces are `implemented`, not `verified`.
- No Project/Client/category row, authoritative apply, physical local
  durability, membership/category authorization, shared reference mutation,
  Project edit/reassignment/archive/delete, hero media, schema/RLS/Sync/Auth/
  provider, current/target app/MCP, migration, hosted resource or production
  operation was introduced; O-023/O-024/O-025/O-026 remain open.
- Exact implementation commit
  `8d8cd30f3b2ff8f582b8117f4799f732cca854a5` passed immutable GitHub Actions
  run `33599214652`: conversion traceability passed in 8 seconds and the
  isolated-target job passed in 2 minutes 53 seconds with all 100 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Project-setup obligations and exactly its
  two target-only surfaces are now `verified`; every excluded server,
  authorization, media, provider, migration and production surface remains
  unadvanced.
- Audited the next Phase 1 dependency graph and selected
  `project-archive-operation-contracts` as the next smallest user-meaningful
  operation. The reviewed capability contract defines ArchiveProject as a
  distinct always-safe history-preserving intent, and the exact target mapping
  already names its expected Project revision and shared operation receipt.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for stable Project identity, finite Account/actor/contract/time binding, one
  exact same-subject expected-revision precondition, shared operation
  fingerprint/receipt/replay and stable mismatch/tamper/local-failure refusal.
  No behavioral Project-archive code or executable test exists at ready.
- Explicitly excluded a generic lifecycle toggle, restore/unarchive and physical
  delete. O-024 remains open because no delete/discard/tombstone behavior is
  chosen; O-025 remains open because no Client relation/correction is carried.
- Postgres, authoritative history preservation, handlers, Data API grants, RLS,
  Sync Streams, physical local durability, authorization, Auth/provider choice,
  current/target app/MCP, source migration, hosted resources and production
  remain explicit nonapplicabilities.
- Ready-gate sync/check and capability/query/residual controls pass at 751
  recorded / 736 discovered surfaces, 325 mapped / 164 residual / 43 blockers;
  M0 passes, M1/M2 retain the expected 2/164 blocks, and the existing 100 target
  tests, graph/contracts, both staging builds and diff formatting pass with no
  executable Project-archive behavior claimed.
- Implemented only the ready provider-free Project archive boundary: typed
  expected revision, exact Account/actor/contract/Project/time draft, one-field
  archive payload, exactly one same-Project expected-revision precondition,
  shared operation envelope/fingerprint/receipt, narrow operation port and
  closed stable failures.
- Added four deterministic tests for exact archive-only scope, stable Project
  identity, canonical byte-identical restart, changed Account/actor/contract/
  payload/revision-subject/revision-value/precondition-count/command-subject/
  fingerprint/receipt/malformed refusal and shared OperationJournal replay/
  changed-Project-or-revision mismatch behavior.
- Four focused/all 104 target tests, graph/contracts and both staging builds pass
  locally. `PROJECTARCHIVE-TEST-001` through `-004` pass; exact-commit hosted
  `PROJECTARCHIVE-TEST-005` remains planned, so exactly the two Project-archive
  surfaces are `implemented`, not `verified`.
- No lifecycle row, authoritative archive or history-preservation result,
  physical local durability, membership/Project authorization, restore/delete/
  edit/reassignment, Client/category/media/accounting mutation, schema/RLS/
  Sync/Auth/provider, current/target app/MCP, migration, hosted resource or
  production operation was introduced; O-024/O-025 remain open.
- Exact implementation commit
  `7b30bd25a60f2a2a751c219b7745e0ec524f31b8` passed immutable GitHub Actions
  run `33601516220`: conversion traceability passed in 9 seconds and the
  isolated-target job passed in 2 minutes 16 seconds with all 104 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Project-archive obligations and exactly its
  two target-only surfaces are now `verified`; every excluded lifecycle-row,
  server, authorization, history-preservation, provider, migration and
  production surface remains unadvanced.
- Audited the next Phase 1 dependency graph and selected
  `budget-category-reference-read-contracts` because Project setup, Project
  category configuration and Item/Transaction routing depend on stable category
  identity/type/lifecycle/order before their later operations can be safe.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for stable Account/category identity, bounded display name, canonical general/
  itemized/fee kind, active/archived and system state, overall-budget exclusion,
  unique presentation order/revision, active/non-system/itemized eligibility and
  shared local-list readiness/restart/refusal.
- Kept financial visibility as an already-authorized visible subset: the local
  contract neither authorizes rows nor exposes hidden fee-category counts.
  O-026 remains open because no category Create/Update/Archive/Reorder command or
  administration capability exists; Project allocation configuration is also
  excluded.
- Ready-gate sync/check and capability/query/residual controls pass at 753
  recorded / 738 discovered surfaces, 327 mapped / 164 residual / 43 blockers;
  M0 passes, M1/M2 retain the expected 2/164 blocks, and the existing 104 target
  tests, graph/contracts, both staging builds and diff formatting pass with no
  executable budget-category reference behavior claimed.
- Implemented only the ready provider-free budget-category reference boundary:
  bounded normalized display name, exact general/itemized/fee kind, stable
  Account/category identity, lifecycle/system/overall-budget-exclusion/order/
  revision evidence, active/non-system/itemized eligibility, Account-exact
  local-list snapshots, visible-count privacy, canonical restart, one narrow
  query port and closed stable failures.
- A visible count is valid only when it equals the already-authorized rows
  actually present. The local contract cannot reveal hidden fee rows or counts,
  authorize a download or infer complete Account data beyond its explicit
  readiness evidence.
- Added four deterministic tests for exact visible category semantics, ready/
  partial/stale/authoritative-empty restart, invalid name/type/revision/time,
  scope/identity/name/order/count/malformed refusal and exact-Account port
  failure safety. Four focused/all 108 target tests in 24 suites pass locally,
  as do conversion/capability/query/residual controls, M0, graph/contracts,
  macOS and generic iOS Simulator staging builds and diff formatting.
- `CATEGORYREFERENCE-TEST-001` through `-004` pass locally. Exact-commit hosted
  `CATEGORYREFERENCE-TEST-005` remains planned, so exactly the two category-
  reference surfaces are `implemented`, not `verified`.
- No hidden fee visibility, category administration, Project allocation or
  budget calculation, physical local persistence, server/download
  authorization, schema/RLS/Sync/Auth/provider, current/target app/MCP, source
  migration, hosted resource or production operation was introduced. O-026
  remains open and unchanged.
- Exact implementation commit
  `713dcf579bc8634b6a429da2fa1e2a431b722b57` passed immutable GitHub Actions
  run `33606006684`: conversion traceability passed in 13 seconds and the
  isolated-target job passed in 1 minute 59 seconds with all 108 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five category-reference obligations and exactly
  its two target-only surfaces are now `verified`; every excluded mutation,
  server/authorization, provider, migration and production surface remains
  unadvanced.
- Audited the remaining Phase 1 Project/reference dependency graph and selected
  `project-category-configuration-read-contracts` as the next smallest complete
  user outcome. The verified Project setup contract already preserves the
  complete selected-category set, and the verified budget-category reference
  contract supplies stable visible category identity/type/lifecycle/order.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for exact Account/Project/category scope, one configuration revision,
  no-relationship versus enabled-without-allocation versus enabled-with-explicit-
  zero/positive Money, explicit incomplete relationship evidence, authorized
  visible-count privacy, shared local readiness/restart and one narrow read port.
- The slice cannot calculate paid/unpaid/recognized budget values or import
  current cached/Transaction-only spend as authority. It exposes no shared
  category or Project configuration writer; O-026 remains fully open and
  unchanged.
- Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
  durability, financial authorization, Auth/provider choice, current/target
  app/MCP, source migration, hosted resources and production remain explicit
  nonapplicabilities. No behavioral code or executable Project configuration
  test exists at ready.
- The ready gate passes at 755 recorded / 740 discovered surfaces, 329 mapped /
  164 residual / 43 blockers. Conversion, capability, query, residual, M0,
  target-environment and generated-contract controls pass; M1/M2 retain their
  expected 2/164 blockers. All existing 108 target tests in 24 suites, macOS and
  generic iOS Simulator staging builds, and diff formatting pass while the two
  scaffolds remain comment-only.
- Exact ready commit `0a34682693d13a0432d0fde54c9254d98641b0a4`
  passed immutable Actions run `33608479448`: traceability passed in 7 seconds,
  and the isolated target job passed in 2 minutes 54 seconds with all 108 then-
  existing tests, graph/contracts, both staging builds and clean artifacts.
- Implemented only the frozen provider-free Project category configuration read
  boundary: exact Account/Project/configuration revision, closed no-relationship/
  enabled-null/enabled-zero-or-positive/incomplete states, verified category
  evidence, visible-count privacy, canonical local restart, completeness-aware
  refusal, stable failures and one narrow read port.
- Added four deterministic tests covering exact relationship/allocation truth,
  ready/partial/stale/authoritative-empty restart, malformed/negative/scope/
  duplicate/count/completeness refusal and exact Account/Project port failure
  safety. Four focused/all 112 target tests in 25 suites pass locally, as do
  graph/contracts, target environment, macOS and generic iOS Simulator staging
  builds and diff formatting.
- `PROJECTCATEGORY-TEST-001` through `-004` pass locally. Exact-implementation-
  commit hosted `PROJECTCATEGORY-TEST-005` remains planned, so exactly the two
  Project category configuration surfaces are `implemented`, not `verified`.
- No budget/spend calculation, hidden row/count, category or Project
  configuration writer, physical persistence, server/download authorization,
  schema/RLS/Sync/Auth/provider, current/target app/MCP, source migration,
  hosted resource or production operation was introduced. O-026 remains open
  and unchanged.
- Exact implementation commit
  `40d20efb9fce0873008b29fec783f2bc28ba30c0` passed immutable GitHub Actions
  run `33610276267`: conversion traceability passed in 10 seconds and the
  isolated-target job passed in 1 minute 54 seconds with all 112 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Project category configuration obligations
  and exactly its two target-only surfaces are now `verified`; every excluded
  budget, mutation, authorization, provider, migration and production surface
  remains unadvanced.
- Audited the remaining Phase 1 Project/Client/reference dependency graph and
  selected `client-rename-operation-contracts` as the next smallest complete
  user outcome. Stable Client identity, creation and directory reads are already
  verified, and the canonical Client spec settles mutable current display text
  without making name an identity key.
- Deliberately did not select Client archive: whether active Projects block that
  operation remains part of the unapproved O-024/O-025 lifecycle packet. Client
  merge and Project reassignment also remain excluded. A rename carries no
  archive/delete/merge/reassignment or dependency-policy input.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for exact Account/actor/contract/Operation/Client/new-name/time binding, one
  same-subject expected Client revision, derived subject/fingerprint, canonical
  restart, atomic rebound refusal and one narrow rename port.
- The ready gate passes at 757 recorded / 742 discovered surfaces, 331 mapped /
  164 residual / 43 blockers. Conversion, capability, query, residual, M0,
  target-environment and generated-contract controls pass; M1/M2 retain their
  expected 2/164 blockers. All existing 112 target tests in 25 suites, macOS and
  generic iOS Simulator staging builds, and diff formatting pass while the two
  scaffolds remain comment-only.
- No executable Client rename, Client row/current-Project projection, frozen-
  history rewrite, physical persistence, server authorization/revision apply,
  schema/RLS/Sync/Auth/provider, current/target app/MCP, source migration,
  hosted resource or production operation exists at ready. O-024/O-025 remain
  open and unchanged.
- Implemented only the frozen provider-free Client rename boundary: validated
  stable Client/new-display-name intent, one exact Client revision, shared
  Account/actor/contract/Operation/time/subject/precondition/fingerprint/
  receipt lifecycle, decode-through-validation and one narrow operation port.
- Added four deterministic tests covering exact payload/command shape,
  byte-identical restart, malformed/rebound/tampered refusal, shared journal
  replay/mismatch behavior and no false receipt from a failing port. Four
  focused/all 116 target tests in 26 suites pass locally, as do target
  environment/generated-contract controls, macOS and generic iOS Simulator
  staging builds, conversion/capability/query/residual controls, M0 and diff
  formatting. M1/M2 retain exactly their expected 2/164 blockers.
- `CLIENTRENAME-TEST-001` through `-004` pass locally. Exact-implementation-
  commit hosted `CLIENTRENAME-TEST-005` remains planned, so exactly the two
  Client rename surfaces are `implemented`, not `verified`.
- No Client row/current-Project projection, frozen-history rewrite, archive/
  delete/merge/reassignment, physical persistence, authoritative authorization
  or revision apply, schema/RLS/Sync/Auth/provider, app/MCP, source migration,
  hosted resource or production operation was introduced. O-024/O-025 remain
  open and unchanged.
- Exact implementation commit
  `3282f8e38784e96d46e34f94fb045997f3f19bd3` passed immutable GitHub Actions
  run `33612902860`: conversion traceability passed in 9 seconds and the
  isolated-target job passed in 2 minutes 20 seconds with all 116 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Client rename obligations and exactly its
  two target-only surfaces are now `verified`; every excluded lifecycle,
  history, provider, migration and production surface remains unadvanced.
- Audited the remaining Phase 1 Project/Client/reference dependency graph and
  selected `project-rename-operation-contracts` as the next smallest complete
  user outcome. Stable Project/Client identity, Project setup/archive and
  directory reads are already verified; the canonical relationship and reviewed
  capability contract settle name-as-display semantics without making name an
  identity, relationship or authorization key.
- Deliberately did not combine Project rename with description/category/media
  edits or Client reassignment. Those are distinct operations; O-024/O-025
  remain open for physical delete and Client correction/merge/reassignment.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for exact Account/actor/contract/Operation/Project/new-name/time binding, one
  same-subject expected Project revision, derived subject/fingerprint, canonical
  restart, atomic rebound refusal and one narrow rename port.
- The ready gate passes at 759 recorded / 744 discovered surfaces, 333 mapped /
  164 residual / 43 blockers. Conversion, capability, query, residual, M0,
  target-environment and generated-contract controls pass; M1/M2 retain their
  expected 2/164 blockers. All existing 116 target tests in 26 suites, macOS and
  generic iOS Simulator staging builds, and diff formatting pass while the two
  scaffolds remain comment-only.
- No executable Project rename, Project row/downstream projection, Client/
  description/category/media/history/lifecycle change, physical persistence,
  server authorization/revision apply, schema/RLS/Sync/Auth/provider,
  current/target app/MCP, source migration, hosted resource or production
  operation exists at ready. O-024/O-025 remain open and unchanged.
- Exact ready commit `18ab228379e9d81db1dc35c16bf6eecc867b64cc`
  passed immutable GitHub Actions run `33614187250`: conversion traceability
  passed in 9 seconds and the isolated-target job passed in 3 minutes 1 second
  with all 116 then-existing target tests, graph/generated-contract checks,
  macOS and generic iOS Simulator builds and clean tracked artifacts.
- Implemented only the frozen provider-free Project rename boundary: validated
  stable Project/new-display-name intent, one exact Project revision, shared
  Account/actor/contract/Operation/time/subject/precondition/fingerprint/
  receipt lifecycle, decode-through-validation and one narrow operation port.
- Added four deterministic tests covering exact payload/command shape,
  byte-identical restart, malformed/rebound/tampered refusal, shared journal
  replay/mismatch behavior and no false receipt from a failing port. Four
  focused/all 120 target tests in 27 suites pass locally, as do target
  environment/generated-contract controls, macOS and generic iOS Simulator
  staging builds, conversion/capability/query/residual controls, M0 and diff
  formatting. M1/M2 retain exactly their expected 2/164 blockers.
- `PROJECTRENAME-TEST-001` through `-004` pass locally. Exact-implementation-
  commit hosted `PROJECTRENAME-TEST-005` remains planned, so exactly the two
  Project rename surfaces are `implemented`, not `verified`.
- No Project row/downstream projection, Client/description/category/media/
  history/lifecycle change, physical persistence, authoritative authorization
  or revision apply, schema/RLS/Sync/Auth/provider, app/MCP, source migration,
  hosted resource or production operation was introduced. O-024/O-025 remain
  open and unchanged.
- Exact implementation commit `7f395bbe99bdd4a564eef1fdbee664cb03519595`
  passed immutable GitHub Actions run `33615145061`: conversion traceability
  passed in 8 seconds and the isolated-target job passed in 2 minutes 11 seconds
  with all 120 target tests, graph/generated-contract checks, macOS and generic
  iOS Simulator builds and clean tracked artifacts. All five Project rename
  obligations and exactly its two target-only surfaces are now `verified`;
  every excluded relationship, details, lifecycle, provider, migration and
  production surface remains unadvanced.
- Audited the next Phase 1 Project/Client/reference dependency and selected
  `project-note-read-contracts` as the smallest complete decision-independent
  outcome. The reviewed target contract already settles stable note identity,
  creator/creation/source and revision/edit/tombstone evidence, deterministic
  bounded order and explicit incomplete local-history truth.
- Deliberately excluded Add/Edit/Remove commands, edit/delete role policy,
  physical persistence, RLS/Sync, indexed search, app/MCP wiring and Firebase
  note migration. The read values consume only already-authorized local rows and
  cannot make any of those decisions implicitly.
- Created exactly two comment-only target scaffolds plus one reciprocal seven-
  requirement/five-verification dossier. The planned implementation binds exact
  Account/Project/note scope, active-versus-tombstone content, immutable creator/
  creation/source evidence, revision and paired edit audit, newest-first
  `(createdAt,id)` order, structured continuation, local query identity and
  complete/incomplete Project-history readiness.
- The ready checkpoint records 761 surfaces, including 746 currently
  discovered, with 335 of 499 target-relevant surfaces mapped or later and 164
  residual surfaces under 43 explicit blockers. No executable Project-note
  behavior, provider connection, hosted resource, production read/mutation,
  app change, migration, deployment or cutover exists.
- Conversion, capability, query, residual, M0, target-environment and generated-
  contract checks pass. M1/M2 retain their expected 2/164 blockers. All 120
  existing target tests in 27 suites, macOS and generic iOS Simulator staging
  builds, generated target-project stability and diff formatting pass while
  both Project-note scaffolds remain comment-only.
- Exact ready commit `58319f2a89a81dd39dd8d624dba481b7d5b17abe`
  passed immutable GitHub Actions run `33616981355`: conversion traceability
  passed in 7 seconds and the isolated-target job passed in 2 minutes 22 seconds
  with all 120 then-existing tests, graph/generated-contract checks, macOS and
  generic iOS Simulator builds and clean tracked artifacts.
- Implemented only the frozen provider-free Project-note read boundary: stable
  Account/Project/note identity, validated text/source, immutable creator/
  creation evidence, revision and paired edit audit, non-content-bearing
  tombstones, bounded typed requests, derived query fingerprints, structured
  `(createdAt,id)` cursors, newest-first page validation, explicit complete/
  incomplete Project-history truth and one narrow read port.
- Added four deterministic tests covering active/edited/tombstoned values,
  same-time ID tie-breaks, bounded continuation, complete/partial/stale/empty
  restart, malformed/scope/audit/order/fingerprint/readiness refusal, exact
  request matching and no false page from a failing port.
- `PROJECTNOTE-TEST-001` through `-004` pass locally. Exact-implementation-
  commit hosted `PROJECTNOTE-TEST-005` remains planned, so exactly the two
  Project-note target surfaces are `implemented`, not `verified`.
- No note authorization/mutation, physical local persistence, schema/RLS/Sync/
  Auth/provider behavior, app/MCP/search wiring, source note migration, hosted
  resource or production operation was introduced.
- Exact implementation commit
  `b421f41948a23fa0918b5e33c0a4d436e5b87080` passed immutable GitHub Actions
  run `33618364544`: conversion traceability passed in 12 seconds and the
  isolated-target job passed in 2 minutes 21 seconds with all 124 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Project-note obligations and exactly its
  two target-only surfaces are now `verified`; every excluded mutation,
  provider, migration and production surface remains unadvanced.
- Exact verification-document commit `0b811864504a90294beefcf6e34b6e9adc73dfda`
  passed immutable GitHub Actions run `33618750372`; both conversion
  traceability and the isolated target environment completed successfully.
- Audited the next Phase 1 dependency and selected
  `project-note-creation-operation-contracts` as the smallest complete
  decision-independent operation. It owns only AddProjectNote intent; edit,
  remove and their role/revision policy remain separate and unimplemented.
- Froze seven exact requirements over stable Account/Project/note identity,
  nonblank text, requested source, the shared operation envelope/fingerprint/
  receipt/replay lifecycle, one derived parent Project reference and explicit
  exclusion of caller-authored authoritative creator/time/source evidence.
- The later trusted handler, not this provider-free command, must derive and
  verify the actor, assign final creation time/source and preflight Project
  existence/visibility without distinguishing missing from denied. No server
  handler, authorization, note row/projection, provider or app/MCP writer was
  introduced.
- Exactly two comment-only target surfaces are `target_mapped` under the ready
  dossier: `SWIFT-9CDB2BCAC71B` and `TEST-DB2559406D3D`. The ledger now records
  763 surfaces, including 748 currently discovered, and 337 of 501 target-
  relevant surfaces are mapped or later; the existing 164 residual surfaces
  remain under 43 explicit blockers.
- Conversion, capability, query, residual, M0, target-environment and generated-
  contract checks pass. M1/M2 retain their expected 2/164 blockers. All 124
  existing target tests in 28 suites, macOS and generic iOS Simulator staging
  builds, XcodeGen/source-project stability and diff formatting pass while both
  new scaffolds remain comment-only. Exact ready commit
  `d84dc10998981b54c847b112cf1e063bd1e74c29` passed immutable Actions run
  `33620363089`: conversion traceability passed in 11 seconds and the isolated
  target environment passed in 3 minutes 33 seconds.
- No physical local persistence, parent authorization, server audit assignment,
  schema/RLS/Sync/Auth/provider behavior, shipped-app/MCP change, source note
  migration, hosted resource, production read/mutation, deployment, release or
  cutover occurred.
- Implemented only the frozen provider-free AddProjectNote boundary:
  `ProjectNoteCreationDraft`, exact payload, precondition-free shared envelope,
  derived parent Project reference, canonical fingerprint/receipt validation,
  narrow create port and stable bounded failures.
- The command includes stable note identity, nonblank text and
  `requestedSource` intent, but excludes creator display, authoritative
  creation time, revision, edit audit, deletion evidence and authorization
  claims. Client actor/time/source intent cannot become authoritative without
  later trusted verification and assignment.
- Added four deterministic tests for exact command/payload/parent shape,
  byte-identical restart, blank/malformed/rebound/tampered refusal, shared
  OperationJournal replay/mismatch semantics and no false receipt.
- `PROJECTNOTECREATE-TEST-001` through `-004` pass locally. All 128 target
  tests in 29 suites, target graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass.
  M1/M2 retain exactly their expected 2/164 blockers.
- Exact implementation commit
  `15566c8dd766762656cb180a65caf0b4600841d5` passed immutable GitHub Actions
  run `33622056438`: conversion traceability passed in 8 seconds and the
  isolated target environment passed in 2 minutes 37 seconds with all 128
  target tests, dependency/environment and generated-contract checks, macOS
  and generic iOS Simulator staging builds and clean tracked artifacts.
- All five Project-note-creation obligations and exactly its two claimed target
  surfaces are now `verified`. Parent authorization, authoritative audit/source
  assignment, note persistence/projection, edit/remove role policy, schema/RLS/
  Sync/Auth/provider behavior, app/MCP, migration, hosted resources and
  production remain unadvanced.
- Exact Project-note-creation verification-document commit
  `b6e8e6cc179df8f670db689679a89dbf9b5f0cea` passed immutable GitHub Actions
  run `33622774880`: conversion traceability passed in 8 seconds and the full
  isolated target environment passed in 1 minute 58 seconds.
- Audited the next Phase 1 Project/Client/reference dependency and excluded
  Project-note edit/removal because their role policy remains deliberately
  unsettled. Selected `project-preference-read-contracts` as the next smallest
  complete dependency: current-Principal ordered pins, revision and local
  absence/readiness truth only.
- Froze seven exact requirements over stable Account/Principal/Project scope,
  ordered unique category identities, preference revision, derived query
  fingerprint, already-authorized visible count and stored/not-stored/not-
  available lookup. Pins remain presentation evidence and cannot supply or
  change canonical budget amounts or arithmetic.
- Exactly two comment-only target surfaces are `target_mapped` under the ready
  dossier: `SWIFT-C6AE96622805` and `TEST-96AAFA22224B`. Preference writes,
  first-use defaults, category visibility resolution, authentication, physical
  persistence, schema/RLS/Sync/provider behavior, app/MCP, source migration,
  hosted resources and production remain unadvanced.
- The ledger now records 765 surfaces, including 750 currently discovered, and
  339 of 503 target-relevant surfaces are mapped or later. The same 164
  residual surfaces remain under 43 explicit blockers; no product or provider
  gate was silently cleared.
- The complete local ready gate passes: all 128 existing target tests in 29
  suites while both scaffolds remain comment-only, target isolation/generated
  contracts, macOS and generic iOS Simulator staging builds, XcodeGen/source-
  project stability, conversion/capability/query/residual controls, M0 and clean
  diff formatting. M1/M2 retain exactly their expected 2/164 blockers.
- Exact ready commit `dfcc1419f59b058c1a4a467662cba8ff95dd5909`
  passed immutable GitHub Actions run `33623843538`: conversion traceability
  passed in 7 seconds and the isolated target environment passed in 1 minute
  50 seconds with all 128 then-existing tests, graph/generated-contract checks,
  both staging builds and clean tracked artifacts.
- Implemented only the frozen provider-free Project preference read boundary:
  exact Account/Principal/Project rows with ordered unique category pins and
  revision, a derived-fingerprint directory request, canonical local directory,
  stored/not-stored/not-available lookup, one narrow read port and stable
  bounded failures.
- Added four deterministic tests for exact personal scope/pin order, ready/
  partial/stale/authoritative-empty restart, authoritative absence versus local
  unavailability, cross-scope/duplicate/fingerprint/count/request/time/malformed
  refusal and exact/no-false-result port behavior.
- `PROJECTPREFERENCE-TEST-001` through `-004` pass locally. All 132 target tests
  in 30 suites, target graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass.
  Exact-implementation-commit hosted
  `PROJECTPREFERENCE-TEST-005` remains planned, so exactly the two claimed
  target surfaces are `implemented`, not `verified`.
- Exact implementation commit
  `59526ccc33c5317768dc0e986f6c91bf24b2a441` passed immutable GitHub Actions
  run `33624655214`: conversion traceability passed in 11 seconds and the
  isolated target environment passed in 2 minutes 2 seconds with all 132 target
  tests, dependency/environment and generated-contract checks, both staging
  builds and clean tracked artifacts.
- All five Project-preference obligations and exactly its two claimed target
  surfaces are now `verified`. Authentication/authorization implementation,
  physical persistence, preference writes, defaults/category resolution,
  budget calculation, schema/RLS/Sync/provider behavior, app/MCP, migration,
  hosted resources and production remain unadvanced.
- Exact Project-preference-read verification-document commit
  `f19492b800961a4db517eb7a91a1249841b5be5f` passed immutable GitHub Actions
  run `33625052445`: conversion traceability passed in 14 seconds and the full
  isolated target environment passed in 1 minute 46 seconds.
- Audited the next Phase 1 Project/Client/reference dependency and selected
  `project-preference-update-operation-contracts` as the next smallest complete
  mutation. Personal preference ownership is independent of O-026 shared-
  reference administration; the command cannot mutate a category, template or
  vendor suggestion.
- Froze seven exact requirements over one current-Principal Account/Project,
  complete ordered duplicate-free stable category pins, stored-empty support,
  explicit not-stored versus exact-revision concurrency, the shared operation
  lifecycle, canonical restart/refusal and one narrow provider-free port.
- Exactly two comment-only target surfaces are `target_mapped` under the ready
  dossier: `SWIFT-8668DE2251DE` and `TEST-AC9956AE9D5C`. Authentication,
  category mutation/resolution, first-use defaults, budget effects, physical
  persistence, schema/RLS/Sync/provider behavior, app/MCP, source migration,
  hosted resources and production remain unadvanced.
- The ledger now records 767 surfaces, including 752 currently discovered, and
  341 of 505 target-relevant surfaces are mapped or later. The same 164
  residual surfaces remain under 43 explicit blockers; no product or provider
  gate was silently cleared.
- The complete local ready gate passes: all 132 existing target tests in 30
  suites while both scaffolds remain comment-only, target isolation/generated
  contracts, macOS and generic iOS Simulator staging builds, repeatable
  XcodeGen/source-project stability, conversion/capability/query/residual
  controls, M0 and clean diff formatting. M1/M2 retain exactly their expected
  2/164 blockers.
- Exact ready commit `30a131e8305b838f32854601db44ae5aeacbfe7b`
  passed immutable GitHub Actions run `33626533989`: conversion traceability
  passed in 10 seconds and the isolated target environment passed in 2 minutes
  25 seconds with all 132 then-existing tests, graph/generated-contract checks,
  both staging builds and clean tracked artifacts.
- Implemented only the frozen provider-free Project preference update boundary:
  one exact Account/actor/Project, complete ordered duplicate-free pin
  replacement, explicit not-stored or exact-revision precondition, derived
  reference-data subject, shared operation lifecycle, canonical restart,
  stable bounded failures and one narrow update port.
- Added four deterministic tests for exact current-Principal payload/scope,
  absent/revision/stored-empty/reordered restart, duplicate/rebound/tampered
  refusal, shared OperationJournal replay/mismatch behavior and no false
  receipt.
- `PROJECTPREFERENCEUPDATE-TEST-001` through `-004` pass locally. All 136 target
  tests in 31 suites, target graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass.
  Exact-implementation-commit hosted `PROJECTPREFERENCEUPDATE-TEST-005`
  remains planned, so exactly the two claimed target surfaces are
  `implemented`, not `verified`.
- Exact implementation commit `0e652548d3d4009c392ddacb298d0ef66db61aa2`
  passed immutable GitHub Actions run `33628801064`: conversion traceability
  passed in 10 seconds and the isolated target environment passed in 2 minutes
  29 seconds with all 136 tests in 31 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five dossier obligations
  now pass and `SWIFT-8668DE2251DE` plus `TEST-AC9956AE9D5C` are verified.
- Exact Project-preference-update verification-document commit
  `da5cfa4a5ad8941656475644202b510c1ee593ad` passed immutable GitHub Actions
  run `33629389877`: conversion traceability passed in 8 seconds and the full
  isolated target environment passed in 2 minutes 32 seconds.
- Audited the next Project/Client/reference dependency and selected the
  vendor-suggestion reference read as the smallest complete decision-independent
  slice. O-026 governs mutation authority, not an already-authorized Account-
  scoped read; suggestion selection remains free-text source evidence rather
  than Vendor or accounting identity.
- Froze seven exact requirements and five verification obligations over stable
  suggestion identity, preserved bounded spelling, normalized comparison,
  lifecycle/revision/order, explicit local readiness/restart, atomic refusal and
  one narrow Account-exact query port.
- Exactly two comment-only target surfaces are `target_mapped` under the ready
  dossier: `SWIFT-111A94B464D5` and `TEST-A73A49564E8C`. Suggestion mutation,
  O-026 roles/capabilities, default seeding, canonical Vendor identity, physical
  persistence, schema/RLS/Sync/provider behavior, app/MCP, migration, hosted
  resources and production remain unadvanced.
- The ready ledger records 769 surfaces / 754 discovered, with 343 mapped, 164
  residual and 43 blockers. Thirty-two slices claim 85 target surfaces and 68
  are implemented or later. All 136 existing target tests in 31 suites,
  target isolation/generated contracts, both staging builds, repeatable
  XcodeGen/source-project stability, conversion/capability/query/residual
  controls, M0 and clean diff formatting pass; M1/M2 retain exactly their
  expected 2/164 blockers.
- Exact ready commit `3abee18e8011943e74185e43d1630aeb9fa2bff7`
  passed immutable GitHub Actions run `33631062466`: conversion traceability
  passed in 20 seconds and the isolated target environment passed in 2 minutes
  51 seconds with all 136 then-existing tests, graph/generated-contract checks,
  both staging builds and clean tracked artifacts.
- Implemented only the frozen provider-free vendor-suggestion read boundary:
  stable typed suggestion identity, exact Account scope, preserved control-free
  display spelling bounded to 200 UTF-8 bytes, normalized comparison, active/
  archive lifecycle, revision/order, local readiness/restart, atomic refusal and
  one narrow query port. Selection exposes only the preserved source string.
- Added four deterministic tests for exact values/source-text semantics,
  ready/partial/stale/authoritative-empty restart, invalid/cross-Account/
  duplicate/count/time/malformed refusal and exact/no-false-snapshot port
  behavior.
- `VENDORSUGGESTION-TEST-001` through `-004` pass locally. All 140 target tests
  in 32 suites, target graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass.
  Exact-implementation-commit hosted `VENDORSUGGESTION-TEST-005` also passes, so
  exactly the two claimed surfaces are `verified`.
- Exact implementation commit `519b4338c7cbe8cc63a01820116bef5283a8625a`
  passed immutable GitHub Actions run `33632364285`: conversion traceability
  passed in 10 seconds and the isolated target environment passed in 2 minutes
  38 seconds with all 140 tests in 32 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five dossier obligations
  now pass and `SWIFT-111A94B464D5` plus `TEST-A73A49564E8C` are verified.
- Exact vendor verification-document commit
  `08cc0472598a5f8171059d91f19f08024a3704f4` passed immutable Actions run
  `33632848448`: conversion traceability passed in 7 seconds and the isolated
  target environment passed in 2 minutes 58 seconds.
- Audited the next decision-independent Project/reference dependency and
  selected Space-template reads. Corrected `spaces.md` from `current_product` to
  registered canonical target authority for both affected batches because its
  existing target-state notice—not the Firebase checked-state-copy/no-op
  behavior—owns the redesigned contract.
- Added exactly two comment-only target scaffolds and the complete ready dossier
  for `SWIFT-77F812A8F463` and `TEST-CB30140F137B`. The frozen boundary covers
  stable Account/template/checklist/item identity, text, lifecycle/revision/
  explicit order, checklist structure with no checked state, local readiness/
  restart/refusal and one narrow Account query port.
- The synchronized ledger records 771 surfaces / 756 discovered, 345 mapped-or-
  later target-relevant surfaces, 164 residual surfaces and 43 validated
  blockers. Thirty-three slices claim 87 target surfaces. M0 passes; M1/M2
  retain exactly their expected 2/164 blockers.
- The complete local ready gate passes with all 140 existing target tests in 32
  suites, target graph/generated contracts, both staging builds, repeatable
  XcodeGen/source-project hashes, conversion/capability/query/residual controls,
  M0 and clean diff formatting.
- Exact comment-only ready commit
  `acc48f637d0f8702a83142f2ba94facd462b48ff` passed immutable Actions run
  `33634828042`: conversion traceability passed in 11 seconds and the isolated
  target environment passed in 2 minutes 7 seconds with all 140 then-existing
  tests, graph/generated-contract checks, both staging builds and clean tracked
  artifacts.
- Implemented only the frozen provider-free Space-template read boundary:
  distinct stable template/checklist/item identity, preserved required text,
  optional notes, lifecycle/revision/explicit deterministic order, local
  readiness/restart/refusal and one narrow Account query port. The target
  structure has no checked-state field and discards unknown stale source
  `isChecked` input on decode/re-encode.
- Added four deterministic tests for exact nested structure and active/archive
  selection, no checked-state carriage, ready/partial/stale/authoritative-empty
  restart, blank/cross-Account/nested-duplicate/count/time/malformed refusal and
  exact/no-false-snapshot query-port behavior.
- `SPACETEMPLATE-TEST-001` through `-004` pass locally. All 144 target tests in
  33 suites, target graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass.
  Exact-implementation-commit hosted `SPACETEMPLATE-TEST-005` also passes, so
  exactly the two claimed surfaces are `verified`.
- Exact implementation commit `f23afce3a95dbf9bb96d1716b73f65f79bbc2714`
  passed immutable GitHub Actions run `33636359059`: conversion traceability
  passed in 8 seconds and the isolated target environment passed in 2 minutes
  33 seconds with all 144 tests in 33 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five dossier obligations
  now pass; 72 target surfaces are implemented or later.
- Exact Space-template verification-document commit
  `58a7c406a0f35d510b57cbb3604623a9aea8c1bd` passed immutable Actions run
  `33636886779`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 2 minutes 25 seconds.
- Audited the next Project/Client/reference dependency against canonical target
  authority and selected Client archive. The spec defines archive as hiding one
  stable Client from new-project selection without deleting history; O-025
  continues to block merge and Project reassignment, not this exact intent.
- Added exactly two target-only comment scaffolds and a ready dossier for one
  expected-revision-aware `ArchiveClient` command. The frozen boundary cannot
  cascade to Projects, restore/delete/merge/rename a Client, rewrite frozen
  history or reassign a Project, and introduces no executable behavior before
  immutable ready-commit CI.
- The synchronized ledger now records 773 surfaces / 758 discovered, 347 mapped-
  or-later target-relevant surfaces, 164 residual surfaces and 43 validated
  blockers. Thirty-four slices claim 89 target surfaces; 72 target surfaces are
  implemented or later. M0 passes; M1/M2 retain exactly their expected 2/164
  blockers.
- The complete local Client-archive ready gate passes with all 144 existing
  target tests in 33 suites while both new files remain comment-only, target
  environment/generated contracts, both staging builds, conversion/capability/
  query/residual controls, M0 and clean diff formatting. Immutable exact-ready-
  commit CI remains the only prerequisite to bounded implementation.
- Exact comment-only ready commit
  `9f3a03dd257b350362d48ef8b5742dcd01131747` passed immutable Actions run
  `33638235220`: conversion traceability passed in 7 seconds and the isolated
  target environment passed in 2 minutes 20 seconds with all 144 then-existing
  tests, graph/generated-contract checks, both staging builds and clean tracked
  artifacts.
- Implemented only the frozen provider-free Client archive boundary: one stable
  Client ID, reused typed expected revision, exact same-subject precondition,
  shared envelope/fingerprint/receipt/replay lifecycle, canonical restart and
  stable refusal. There is no lifecycle boolean, Project list, cascade, hard
  delete, merge, rename, restore, history rewrite or reassignment input.
- Added four deterministic tests for exact scope/precondition, byte-identical
  restart, invalid/rebound/tampered evidence refusal, shared replay/mismatch
  semantics and no false receipt from a failing port. Four focused/all 148
  target tests in 34 suites, graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass
  locally. Exactly two surfaces are `implemented`; exact-commit CI remains.
- Exact implementation commit
  `e10be9ec731ee68ed14ff6e2b6d004b6d00d5baf` passed immutable GitHub Actions
  run `33639210706`: conversion traceability passed in 13 seconds and the
  isolated target environment passed in 2 minutes 58 seconds with all 148 tests
  in 34 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass and exactly the two Client-
  archive surfaces are now `verified`; 74 target surfaces are implemented or
  later.
- Exact Client-archive verification-document commit
  `1926a16e87e353853d3e439d62fbc88495ee1c0d` passed immutable Actions run
  `33639869188`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 2 minutes 35 seconds.
- Audited Project details as the next smallest complete dependency. The target
  taxonomy already separates `UpdateProjectDetails`; the preserved optional
  Project description is the only field it owns after Project rename, Client
  relationship, category configuration, media and lifecycle are excluded.
- Corrected `projects.md` from `current_product` to the seventh canonical target
  spec because it already separates Target Redesign Requirements from Firebase
  mechanics retained as migration evidence. Made the reviewed optional-
  description preserve/correct rule explicit without adding a new feature:
  trim outer whitespace, whitespace-only clears, and no other Project concern
  may change.
- Added exactly two target-only comment scaffolds and a ready dossier for one
  expected-revision-aware `UpdateProjectDetails` description replacement. No
  executable behavior exists before exact-ready-commit CI.
- The synchronized ledger now records 775 surfaces / 760 discovered, 349 mapped-
  or-later target-relevant surfaces, 164 residual surfaces and 43 validated
  blockers. Thirty-five slices claim 91 target surfaces; 74 are implemented or
  later. M0 passes; M1/M2 retain exactly their expected 2/164 blockers.
- The complete local Project-details ready gate passes with all 148 existing
  target tests in 34 suites while both new files remain comment-only, target
  environment/generated contracts, both staging builds, conversion/capability/
  query/residual controls, M0 and clean diff formatting. Immutable exact-ready-
  commit CI remains the only prerequisite to bounded implementation.
- Exact comment-only ready commit
  `119e04559fbf756e2481287963d0367d80d39846` passed immutable Actions run
  `33641244740`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 2 minutes 25 seconds with all 148 then-existing
  tests, graph/generated-contract checks, both staging builds and clean tracked
  artifacts.
- Implemented only the frozen provider-free Project-details boundary: one
  canonical optional-description replacement/clear, stable Project ID, reused
  typed expected revision, exact same-subject precondition, shared envelope/
  fingerprint/receipt/replay lifecycle, canonical restart and stable refusal.
  There is no name, Client, category, media, lifecycle, child, accounting,
  history or generic-field mutation input.
- Added four deterministic tests for normalized set/clear scope, byte-identical
  restart, noncanonical/malformed/rebound/tampered evidence refusal, shared
  replay/mismatch semantics and no false receipt from a failing port. Four
  focused/all 152 target tests in 35 suites, graph/generated contracts, both
  staging builds, conversion/capability/query/residual controls, M0 and clean
  artifacts pass locally. Exactly two surfaces are `implemented`; 76 target
  surfaces are implementation-advanced and exact-commit CI remains.
- Exact implementation commit
  `a532ac9dee5bedca6ade576657fc4fd971841854` passed immutable GitHub Actions
  run `33642777864`: conversion traceability passed in 10 seconds and the
  isolated target environment passed in 2 minutes 51 seconds with all 152 tests
  in 35 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass and exactly the two Project-
  details surfaces are now `verified`; 76 target surfaces are implemented or
  later.
- Exact Project-details verification-document commit
  `27b2123474957a448097078c7facbf6ed3d8c418` passed immutable GitHub Actions
  run `33643300146`: conversion traceability passed in 11 seconds and the
  isolated target environment passed in 3 minutes 4 seconds.
- Audited `ConfigureProjectCategories` and did not create a writer: verified
  requirement `PROJECTCATEGORY-REQ-004` keeps category mutation out while O-026
  shared-reference administration authority remains open.
- Selected direct `CreateSpace` as the next smallest complete decision-
  independent dependency. Clarified the existing canonical `spaces.md` target
  requirements for stable identity, exact Project-or-Business-Inventory scope,
  normalized required name and optional notes, separate child concerns, shared
  operation lifecycle and no accounting effects. O-023/O-026/O-037 are not
  resolved or bypassed.
- Added exactly two target-only comment scaffolds and a ready dossier for the
  provider-free direct Space-create operation. No executable behavior exists
  before exact-ready-commit CI.
- The synchronized ledger now records 777 surfaces / 762 discovered, 351
  mapped-or-later target-relevant surfaces, 164 residual surfaces and 43
  validated blockers. Thirty-six slices claim 93 target surfaces; 76 are
  implemented or later. M0 passes; M1/M2 retain exactly their expected 2/164
  blockers.
- The complete local Space-create ready gate passes with all 152 existing
  target tests in 35 suites while both new files remain comment-only, target
  environment/generated contracts, both staging builds, conversion/capability/
  query/residual controls, M0 and clean diff formatting. Immutable exact-ready-
  commit CI is the only prerequisite to bounded implementation.
- Exact comment-only Space-create ready commit
  `fd81c8aed1a88a3cbd8be742a784dd3d1ab72e93` passed immutable GitHub Actions
  run `33645504076`: conversion traceability passed in 20 seconds and the
  isolated target environment passed in 2 minutes 32 seconds with all 152 then-
  existing tests, graph/generated-contract checks, both staging builds and
  clean tracked artifacts.
- Implemented only the frozen provider-free direct Space-create boundary:
  stable Space identity; exact Project-or-Business-Inventory scope; canonical
  required name and optional notes; zero expected-revision preconditions;
  shared envelope/fingerprint/receipt/replay; canonical restart/refusal; stable
  diagnostics; and one narrow port. It contains no child, template, media,
  assignment, review, lifecycle, accounting, provider or authoritative-apply
  concern.
- Four focused and all 156 target tests in 36 suites pass locally, along with
  target isolation/generated contracts, both staging builds and clean diff
  formatting. The implementation acknowledges exact source hashes; 78 target
  surfaces are now implementation-advanced. Exact implementation-commit CI
  remains before verification.
- Exact Space-create implementation commit
  `03b545dffcaaf8ea37fc9f30f0e3f12b761610a4` passed immutable GitHub Actions
  run `33647113450`: conversion traceability passed in 7 seconds and the
  isolated target environment passed in 2 minutes 45 seconds with all 156 tests
  in 36 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass and exactly the two Space-create
  surfaces are now `verified`; 78 target surfaces are implemented or later.
- Exact Space-create verification-document commit
  `74d411f162633a9fcd03f7976e4b1f312a78473e` passed immutable GitHub Actions
  run `33650026503`: conversion traceability passed in 10 seconds and the
  isolated target environment passed in 2 minutes 28 seconds.
- Audited `UpdateSpaceDetails` as the next smallest complete decision-
  independent dependency. The canonical Space spec and reviewed capability
  dossier preserve name/optional-notes editing while replacing generic partial
  dictionaries and last-write-wins with one complete same-Space revisioned
  replacement. Scope, child state, media, assignment, review, lifecycle and
  accounting remain separate.
- Clarified that existing target rule in `spaces.md`, registered the reviewed
  Spaces capability dossier as conversion-control evidence, and added exactly
  two target-only comment scaffolds plus a ready dossier. No executable details-
  update behavior exists before exact-ready-commit CI.
- The synchronized ledger now records 779 surfaces / 764 discovered, 353
  mapped-or-later target-relevant surfaces, 164 residual surfaces and 43
  validated blockers. Thirty-seven slices claim 95 target surfaces; 78 are
  implemented or later. M0 passes; M1/M2 retain exactly their expected 2/164
  blockers.
- The complete local Space-details ready gate passes with all 156 existing
  target tests in 36 suites while both new files remain comment-only, target
  environment/generated contracts, both staging builds, conversion/capability/
  query/residual controls, M0 and clean diff formatting. Immutable exact-ready-
  commit CI is the only prerequisite to bounded implementation.
- Exact comment-only Space-details ready commit
  `938a30abdf816be63055f30a2d17c602f92e0611` passed immutable GitHub Actions
  run `33652799157`: conversion traceability passed in 10 seconds and the
  isolated target environment passed in 2 minutes 57 seconds with all 156 then-
  existing tests, graph/generated-contract checks, both staging builds and
  clean tracked artifacts.
- Implemented only the frozen provider-free Space-details boundary: reused
  canonical Space name/notes values; stable Space identity; typed expected
  revision; exactly one same-Space precondition; shared envelope/fingerprint/
  receipt/replay; canonical restart/refusal; stable diagnostics; and one narrow
  port. It contains no scope, child, template, media, assignment, review,
  lifecycle, accounting, provider or authoritative-apply concern.
- At the local implementation checkpoint, four focused and all 160 target tests
  in 37 suites passed, along with
  target isolation/generated contracts, both staging builds and clean diff
  formatting. The implementation acknowledged exact source hashes; 80 target
  surfaces were implementation-advanced and exact implementation-commit CI
  remained before verification.
- Exact Space-details implementation commit
  `1c8c12b4c593a43b3743fec41331dd852edbc10b` passed immutable GitHub Actions
  run `33654631876`: conversion traceability passed in 8 seconds and the
  isolated target environment passed in 2 minutes 31 seconds with all four
  focused/all 160 target tests in 37 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five obligations pass;
  exactly the two Space-details surfaces are now `verified`, and 80 target
  surfaces remain implemented or later.
- Exact Space-details verification-document commit
  `01d3638b2b7850f39a7a16e1b899b37ce441e189` passed immutable GitHub Actions
  run `33655871244`: conversion traceability passed in 8 seconds and the
  isolated target environment passed in 2 minutes 36 seconds.
- Audited `ReviseSpaceChecklists` as the next smallest complete decision-
  independent dependency. Canonical Space authority and the reviewed capability
  dossier preserve add/remove/rename/reorder/check/progress outcomes while
  replacing random decoded IDs and last-write-wins embedded-array updates with
  one complete revisioned hierarchy. Template administration, media, Item
  assignment, review, Space reconciliation, lifecycle and accounting remain
  separate and O-023/O-026/O-032/O-037 remain open.
- Clarified that target rule in `spaces.md`, added exactly two target-only
  comment scaffolds and froze the ready dossier. The synchronized ledger now
  records 781 surfaces / 766 discovered, 355 mapped-or-later target-relevant
  surfaces, 164 residual surfaces and 43 validated blockers. Thirty-eight
  slices claim 97 target surfaces; 80 are implemented or later. M0 passes;
  M1/M2 retain exactly their expected 2/164 blockers.
- The complete local Space-checklist ready gate passes with all 160 existing
  target tests in 37 suites while both new files remain comment-only, target
  environment/generated contracts, both staging builds, conversion/capability/
  query/residual controls, M0 and clean diff formatting. M1/M2 retain exactly
  their expected 2/164 prerequisite blockers. Immutable exact-ready-commit CI
  remains required before bounded implementation.
- Exact comment-only Space-checklist ready commit
  `68d2b4d071fdf96911d5cc0c1b6e71cd1b3c53b2` passed immutable GitHub Actions
  run `33658088408`: conversion traceability passed in 18 seconds and the
  isolated target environment passed in 2 minutes 6 seconds with all 160 then-
  existing target tests, graph/generated-contract checks, both staging builds
  and clean tracked artifacts.
- Implemented only the frozen provider-free checklist boundary: distinct stable
  checklist/item identities; canonical nonblank names/text; complete
  deterministic nested order; checked-state progress; valid empty clear and
  zero-item checklists; exact same-Space revision; shared envelope/fingerprint/
  receipt/replay; canonical restart/refusal; stable diagnostics; and one narrow
  port. It contains no scope/details/template/media/assignment/review/Space-
  completion/lifecycle/accounting/provider or authoritative-apply concern.
- Four focused and all 164 target tests in 38 suites pass locally, along with
  target isolation/generated contracts, conversion/capability/query/residual
  controls, M0, both staging builds and clean diff formatting. The
  implementation acknowledges exact source hashes; 82 target surfaces are
  implementation-advanced. Exact implementation-commit CI remains before
  verification.
- Exact Space-checklist implementation commit
  `8131e8570cda2d9ffa5a4e445bd6dfd50b8aefed` passed immutable GitHub Actions
  run `33659853864`: conversion traceability passed in 10 seconds and the
  isolated target environment passed in 2 minutes 36 seconds with all four
  focused/all 164 target tests in 38 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five obligations pass;
  exactly the two Space-checklist surfaces are now `verified`, and 82 target
  surfaces are implemented or later.
- The Space-checklist verification-document commit
  `3cfbcb5a70c0d3620aedf04a57bf46690cd6263a` passed both jobs in immutable
  Actions run `33660769158`, including all 164 then-existing target tests, both
  staging builds and clean tracked artifacts.
- Audited Item-to-Space assignment and withheld it because O-037 still owns
  archived destination/retained-assignment semantics; no proposed archive
  policy was promoted into code.
- Selected the decision-independent session-ending pending-work safety
  boundary. Canonical Auth/offline requirements now state the already-required
  exact environment/Principal/Account summary, four distinct pending-work
  counts, clean-zero rule, sync-first completion rule, exact-confirmed
  destructive exception, cancellation no-call and fail-closed interruption
  behavior while leaving Auth, offline lease, UI copy and physical cleanup open.
- Added exactly two comment-only target surfaces, the reviewed identity batch
  mapping, `session-ending-pending-work-contracts`, and
  `EVID-SESSION-ENDING-POLICY-001`. The ready dossier freezes eight requirements
  and five deterministic obligations; executable behavior remains absent until
  the exact ready checkpoint passes immutable CI.
- The complete local ready gate passes with all 164 existing target tests in 38
  suites, both staging builds, target isolation/generated contracts,
  conversion/capability/query/residual controls, M0 and clean formatting. The
  ledger records 783 surfaces / 768 discovered, 357 mapped / 164 residual / 43
  blockers; M1/M2 retain the expected 2/164 blockers with zero structural
  errors.
- Exact comment-only session-ending ready commit
  `caa9a9003c13782780d6107df805b95f2f9240ba` passed immutable GitHub Actions
  run `33662071456`: conversion traceability passed in 10 seconds and the
  isolated target environment passed in 2 minutes 23 seconds with all 164 then-
  existing tests, graph/generated-contract checks, both staging builds and
  clean tracked artifacts.
- Implemented only the frozen provider-free session-ending safety boundary:
  exact scoped four-class pending-work summaries; canonical summary/request
  fingerprints; clean/sync-first/exact-confirmed-destructive dispositions;
  cancellation no-request; fresh-summary, stale/regression and scope checks;
  stable diagnostics; and one narrow port. It contains no Auth, physical
  synchronization/cleanup, provider, media-retention, schema/RLS/Sync, app/MCP,
  migration or production behavior.
- Four focused and all 168 target tests in 39 suites pass locally, along with
  target isolation/generated contracts, both staging builds and clean diff
  formatting. Exact source hashes are acknowledged.
- Exact session-ending implementation commit
  `bf9a00ca45c8054018ab6f021aab13386ba24872` passed immutable GitHub Actions
  run `33663785835`: conversion traceability passed in 15 seconds and the
  isolated target environment passed in 2 minutes 32 seconds with all four
  focused/all 168 target tests in 39 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five obligations pass;
  exactly the two session-ending surfaces are now `verified`, and 84 target
  surfaces are implemented or later.
- The session-ending verification-document commit
  `41d96d7dd4d935bf6f320e55dcfe277b28ff3c9b` passed immutable Actions run
  `33664894237`: conversion traceability passed in 10 seconds and the isolated
  target environment passed in 2 minutes 23 seconds with all 168 then-existing
  tests, both staging builds and clean tracked artifacts.
- Audited Account discovery/selection against the canonicalized product spec,
  reviewed identity dossier, architecture and current app/MCP sources. The
  bounded target contract corrects discovery-error-as-empty, arbitrary/first/
  fallback selection and selection-as-listener-state without deciding Auth,
  offline lease, current membership or physical workspace activation.
- Added exactly two comment-only target surfaces,
  `account-discovery-and-selection-contracts`, and
  `EVID-ACCOUNT-DISCOVERY-SELECTION-001`. The ready dossier freezes eight
  requirements and five deterministic obligations. The ledger records 785
  surfaces / 770 discovered, 359 mapped / 164 residual / 43 blockers; 40
  slices claim 101 of 523 target-relevant surfaces while 84 are implementation-
  advanced.
- The complete local ready gate passes with all 168 existing target tests in 39
  suites, both staging builds, unchanged repeatable target graph, target
  isolation/generated contracts, conversion/capability/query/residual controls,
  M0 and clean formatting. M1/M2 retain the expected 2/164 blockers with zero
  structural errors.
- Exact Account-discovery ready commit
  `ae16ed4e62ee2abe7ab60f71a26a92824e70fa01` passed immutable Actions run
  `33666363647`: conversion traceability passed in 7 seconds and the isolated
  target environment passed in 3 minutes 34 seconds with all 168 then-existing
  target tests, graph/generated-contract checks, both staging builds and clean
  tracked artifacts.
- Implemented only the frozen provider-free Account-discovery/selection
  boundary: bounded visibility-safe Account summaries; exact environment/
  Principal/readiness/version/time/fingerprint snapshots; distinct waiting,
  snapshot and failed-with-cache states; deterministic remembered ordering with
  no automatic selection; exact-snapshot-bound non-authorizing selection
  intent; stable rejection diagnostics; and one narrow `AccountQuerying` port.
  Auth, membership proof, authorization, offline lease, persistence, physical
  activation/switching, schema/RLS/Sync, app/MCP, migration and production remain
  absent.
- Four focused and all 172 target tests in 40 suites pass locally, along with
  target isolation/generated contracts, both staging builds, repeatable target
  project generation, conversion/capability/query/residual controls, M0 and
  clean diff formatting. M1/M2 retain exactly 2/164 blockers with zero
  structural errors.
- Exact Account-discovery implementation commit
  `e2972b9c81055fdf936db81afc4bd7e5cd13d0fb` passed immutable Actions run
  `33668715587`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 3 minutes 8 seconds with all 172 target tests in
  40 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass; exactly the two Account-
  discovery/selection surfaces are now `verified`.
- Exact Account-discovery verification-document commit
  `4102365871ba3bde9b42e6132f98a02a1bbd3d69` passed immutable Actions run
  `33669255726`: conversion traceability passed in 9 seconds and the isolated
  target environment passed in 2 minutes 51 seconds with all 172 then-existing
  target tests, graph/generated-contract checks, both staging builds and clean
  tracked artifacts.
- Audited Item-to-Space assignment against canonical `spaces.md`, the one-Item
  identity/accounting boundary, the reviewed Spaces dossier, architecture and
  current Firebase assignment callers. The target keeps stable physical Item
  identity and same-scope placement while replacing independent writes and
  generic field updates with one atomic typed operation; it does not preserve
  Firebase mechanics.
- Selected `AssignItemsToSpace` as the next smallest complete decision-
  independent slice. O-037 remains open because archive/delete is absent;
  O-007/O-015 do not block a command that cannot change occurrence, provenance
  or accounting state. Clear assignment, scope movement, media and review are
  separate operations.
- Added exactly two comment-only target surfaces,
  `item-space-assignment-operation-contracts`, and
  `EVID-ITEM-SPACE-ASSIGNMENT-001`. The ready dossier freezes eight requirements
  and five deterministic obligations. The ledger records 787 surfaces / 772
  discovered, 361 mapped / 164 residual / 43 blockers; 41 slices claim 103 of
  525 target-relevant surfaces while 86 are implementation-advanced.
- The complete local ready gate passes with all 172 existing target tests in 40
  suites, both staging builds, unchanged repeatable target graph, target
  isolation/generated contracts, conversion/capability/query/residual controls,
  M0 and clean formatting. M1/M2 retain the expected 2/164 blockers with zero
  structural errors.
- Exact ready commit `30f4ab88cd526b89b09dc22f1f26cd66884b0b33`
  passed immutable Actions run `33670383410`: conversion traceability passed in
  14 seconds and the isolated target environment passed in 2 minutes 8 seconds
  with all 172 then-existing target tests, graph/generated-contract checks, both
  staging builds and clean tracked artifacts.
- Replaced exactly those two comment-only scaffolds with the bounded provider-
  free implementation. `ItemPlacementScope`, exact Space/Item revision inputs,
  canonical nonempty duplicate-free candidate sets, typed active/revision/scope
  preconditions, command/fingerprint/receipt reconstruction, 16 stable failure
  codes and the narrow `ItemSpaceAssigning` port now exist.
- Four focused/all 176 target tests in 41 suites pass locally, along with both
  staging builds, target isolation/generated contracts, conversion/capability/
  query/residual controls, M0, clean formatting and repeatable project/scheme
  hashes. M1/M2 retain exactly 2/164 blockers with zero structural errors. The
  source application project is unchanged.
- Exact implementation commit
  `c5fdf5c73763b5a629ff0416bebba92696af6581` passed immutable Actions run
  `33672006836`: conversion traceability passed in 9 seconds and the isolated
  target environment passed in 2 minutes 31 seconds with all 176 target tests
  in 41 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass; exactly the two Item-to-Space
  assignment surfaces are now `verified`.
- The Item-to-Space verification-document commit
  `6ff51992726a7a2d88739bf9e8a689bffe4b6de4` passed immutable Actions run
  `33672821325`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 3 minutes 5 seconds with all 176 then-existing
  target tests, both staging builds and clean tracked artifacts.
- Audited explicit Item Space clearing against canonical Space/Item authority,
  D-019/D-023, reviewed Spaces/media dossiers, architecture and current Item/
  Inventory/Project/Space/Search callers. The target replaces generic
  `spaceId: NSNull()` dictionaries, silent duplicate removal and independently
  chunked writes with one atomic typed operation while preserving authoritative
  closure of old green Item-linked Space-photo checkmark relationships without
  accepting marker data or deleting media bytes.
- Selected `ClearItemSpaceAssignments` as the next smallest complete decision-
  independent slice. O-037 remains open because archive/delete is absent and
  clear is explicit; O-023 remains open because no attachment reference or byte
  is removed; O-007/O-015 do not block non-accounting placement clear.
- Added exactly two comment-only target surfaces,
  `item-space-clearing-operation-contracts`, and
  `EVID-ITEM-SPACE-CLEARING-001`. The ready dossier freezes eight requirements
  and five deterministic obligations. The synchronized ledger records 789
  surfaces / 774 discovered, 363 mapped / 164 residual / 43 blockers; 42 slices
  claim 105 of 527 target-relevant surfaces while 88 are implementation-
  advanced.
- The complete local Item Space-clearing ready gate passes with all 176 existing
  target tests in 41 suites, both staging builds, unchanged repeatable target
  graph, target isolation/generated contracts, conversion/capability/query/
  residual controls, M0 and clean formatting. M1/M2 retain the expected 2/164
  blockers with zero structural errors.
- Exact ready commit `2a201de4109891323e51bbd273ed33723d970508`
  passed immutable Actions run `33675190031`: conversion traceability passed in
  11 seconds and the isolated target environment passed in 2 minutes with all
  176 then-existing target tests, graph/generated-contract checks, both staging
  builds and clean tracked artifacts.
- Replaced exactly those two comment-only scaffolds with the bounded provider-
  free implementation. Exact Project-or-Business-Inventory scope, canonical
  nonempty duplicate-free Item/revision/current-Space candidates including
  mixed source Spaces, deterministic scope/current-placement preconditions,
  command/fingerprint/receipt reconstruction, 15 stable failure codes and the
  narrow `ItemSpaceAssignmentClearing` port now exist. Marker closure remains a
  later trusted-handler effect and no media-deletion instruction is accepted.
- Four focused/all 180 target tests in 42 suites pass locally, along with both
  staging builds, target isolation/generated contracts, conversion/capability/
  query/residual controls, M0, clean formatting and repeatable project/scheme
  hashes. M1/M2 retain exactly 2/164 blockers with zero structural errors. The
  source application project is unchanged; exact implementation-commit CI
  was required before promotion.
- Exact implementation commit
  `f5a7ac7598f77859239b66666bc703ee4639c233` passed immutable Actions run
  `33677087616`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 2 minutes 25 seconds with all 180 target tests
  in 42 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass; exactly the two Item Space-
  clearing surfaces are now `verified`.
- The Item Space-clearing verification-document commit
  `2fd9ccaa183d7a840aa578192c7da3bf2b40c0db` passed immutable Actions run
  `33677528131`: conversion traceability passed in 9 seconds and the isolated
  target environment passed in 3 minutes 21 seconds with all 180 then-existing
  target tests, both staging builds and clean tracked artifacts.
- Audited the Space assignment destination picker against canonical Space/Item
  authority, the reviewed Spaces dossier, local-first architecture, the
  verified assignment operation and current Firebase callers. Some current
  callers supply exact Project/Inventory-filtered arrays while shared search
  flows may supply Account-wide Spaces; the target replaces caller-owned
  filtering with one exact operation-specific local directory.
- Selected `space-assignment-destination-read-contracts` as the next smallest
  complete decision-independent slice. O-037 does not block a directory that
  exposes only active destinations and cannot archive; O-023/O-032 do not block
  rows that carry no media or review state.
- Added exactly two comment-only target surfaces and the complete ready dossier.
  It freezes eight requirements and five domain/restart/rejection/port/
  operational obligations over exact Account/scope, active Space identity/name/
  revision, valid duplicate names, deterministic ordering and explicit local
  readiness without treating cached rows as authorization.
- Conversion synchronization and generated residuals pass at 791 recorded / 776
  discovered surfaces, 365 mapped / 164 residual / 43 blockers. Forty-three
  slices claim 107 of 529 target-relevant surfaces and 90 are implementation-
  advanced. The only warnings are the same three evidenced retired paths.
- The complete local ready gate passes all 180 existing target tests in 42
  suites, both staging builds, target isolation/generated contracts, conversion/
  capability/query/residual controls, M0, clean formatting and repeatable target
  project/scheme hashes. The source application project is unchanged. M1/M2
  retain exactly 2/164 coverage blockers with zero structural errors.
- Exact ready commit `5f4867af1cba9b860efe9de2a914782bb8010278`
  passed immutable Actions run `33679542831`: conversion traceability passed in
  8 seconds and the isolated target environment passed in 3 minutes 39 seconds
  with all 180 then-existing tests, generated contracts, graph checks, both
  staging builds and clean tracked artifacts.
- Adopted the controlled subagent model after an explicit risk/reward review.
  `parallel-subagent-workflow.md` keeps one canonical integration/control-plane
  owner and permits at most two write-capable workers, each owning one frozen
  slice in an exact-base isolated worktree. Worker results are untrusted
  candidate commits and cannot advance evidence or status.
- The first two implementation pilots require primary-agent review of every
  changed line, a separate read-only adversarial requirements/security/offline/
  test review, primary-agent focused and complete-gate reruns, and fresh exact-
  integration-commit CI. A critical/repeated-major finding, out-of-scope edit or
  evidence overclaim suspends further write delegation until the process is
  corrected.
- Recorded `SUBAGENT-PILOT-001` in `parallel-work-registry.json`, pinned to the
  exact ready commit and run above. Its dedicated branch/worktree may modify only
  the two Space assignment-destination implementation/test scaffolds; Firebase,
  docs/control/generated files, package/project graphs, MCP and hosted systems
  are forbidden.
- Completed the first isolated implementation candidate at
  `dd48f23557ed204244a68c4cf6896a58133276f4`. Its clean branch is descended
  from the exact ready commit and changes exactly the two allowlisted files.
- Applied the enhanced first-pilot quality gate: the integration agent reviewed
  every changed line and independently reran four focused and all 184 target
  tests in 43 suites; a separate read-only adversarial reviewer repeated the
  authority, negative, restart, scope and exclusion audit and found no P0-P2
  defect.
- Resolved the reviewer's nonblocking P3 documentation finding by clarifying
  that legitimate later revision/readiness snapshots remain valid while
  malformed, rebound or internally inconsistent evidence fails closed; no
  content-integrity or authorization proof is claimed.
- Integrated the candidate into the canonical branch at
  `0cca411d78d41281f3fb1f1d5c08c6518e2003b7`. The dossier and exactly its two
  surfaces are `implemented`, not `verified`.
- The complete local integration gate passes conversion sync/check/report,
  capability/query/residual controls, M0, target isolation/generated contracts,
  four focused/all 184 tests in 43 suites, repeatable project generation, both
  staging builds and clean formatting. Project/scheme hashes remain unchanged;
  M1/M2 retain exactly 2/164 coverage blockers and zero structural errors.
- Exact integration checkpoint
  `b0ffef836cc82f6011b802a5cb5f6a6ade05680a` passed immutable Actions run
  `33682239349`: traceability passed in 10 seconds and the isolated target job
  passed in 3 minutes 2 seconds with all 184 tests in 43 suites, target graph/
  contracts, both staging builds and clean artifacts.
- Promoted exactly the Space assignment-destination dossier and its two
  surfaces to `verified`; `SUBAGENT-PILOT-001` is complete with its worker,
  integration-agent and independent-review evidence preserved. One of two
  enhanced write pilots has now passed.
- Rejected the proposed Inventory purchase-planning second pilot before a ready
  dossier or worker launch. Root and independent authority review found that
  the shipped spec is current/migration evidence only, D-013 conflicts with
  legacy intended-category authority, and retention/granularity/lifecycle are
  unresolved. Removed the speculative scaffolds, demoted the two MCP planning
  tools and legacy category helper, added O-038 to all five affected surfaces,
  removed premature planning ports, and created a non-authoritative decision
  packet. Current deterministic state is 791 recorded / 776 discovered, 362
  mapped-or-later / 167 residual / 44 blockers with only the three documented
  retired-path warnings. No worker implementation was accepted.
- Re-ran the next-slice search under the strengthened feature-specific
  authority rule. Media primary/order and Project-note search were rejected as
  insufficiently specified. A strict scout and independent read-only
  adversarial preflight approved only a narrow provider-free Project budget
  segment DTO/query foundation from the pre-existing Budget Progress spec and
  D-012. The preflight required exact Account/Project/currency identity, signed
  client-paid and invoicing/unpaid Money, internally derived recognized value,
  positive collection-segment exchange with no recognized change, stable
  category order, distinct LocalDataVersion and accounting-authority/projection
  revision, explicit incomplete/empty truth, restart/refusal and exact-request
  port behavior. It prohibited calling the result the complete
  ProjectBudgetSnapshot or adding source resolution, settlement, reports,
  visual policy, providers or migration.
- Prepared `project-budget-segment-read-contracts` as `ready` with exactly two
  comment-only target surfaces, seven requirements and five planned
  verification obligations. The accompanying architecture clarification records
  technical request/port scope only; it is not product authority and did not
  exist at the reviewed base. Current deterministic state is 793 recorded / 778
  discovered, 364 mapped-or-later / 167 residual / 44 blockers, 44 slices
  claiming 109 of 531 target-relevant surfaces, and only the three documented
  retired-path warnings. No worker, provider, Firebase or production action has
  occurred.
- `SUBAGENT-PILOT-002` produced candidate `dc9f2601` from the exact green ready
  base and changed only the two allowlisted Swift paths. A precommit size check
  required simplification from approximately 1,076 to 768 added lines without
  dropping frozen coverage. The integration agent reviewed every changed line
  and reran five focused tests. An independent read-only adversarial reviewer
  verified exact ancestry/path scope, product authority, arithmetic, tamper,
  restart, exact-port/upstream-failure/cancellation and isolation behavior,
  passed five focused and all 189 target tests in 44 suites plus isolation, and
  found no P0-P3 defect. The candidate is integrated as `ddbe7d7b`; the slice
  is `implemented`, not verified. The complete local integration gate passes
  conversion/capability/query/residual/M0 controls, target isolation/generated
  app-MCP contracts, five focused/all 189 tests in 44 suites, repeatable project
  generation, both staging builds and clean formatting. Immutable exact-
  checkpoint CI remains required. No provider, Firebase or production action
  occurred.
- The complete local ready gate passed all 184 target tests in 43 suites,
  target isolation/contracts, repeatable project generation, both staging
  builds, conversion/capability/query/residual/M0 controls and the exact
  expected M1/M2 holds. Exact ready commit `43189f1a` passed immutable Actions
  run `33687191592`: conversion traceability in 11 seconds and the isolated
  target environment in 2 minutes 3 seconds. `SUBAGENT-PILOT-002` is now
  recorded from that exact base in its own branch/worktree with only the two
  scaffold Swift paths writable. No provider, Firebase or production action
  occurred.
- Exact integration checkpoint
  `8fce53b75029133b39fe182031df25ef011fc35e` passed immutable Actions run
  `33689446640`: conversion traceability passed in 11 seconds and the isolated
  target environment passed in 2 minutes 30 seconds with all 189 tests in 44
  suites, generated contracts, both staging builds and clean tracked artifacts.
  Promoted exactly the Project budget segment dossier and its two surfaces to
  `verified`. `SUBAGENT-PILOT-002` is complete, and both required enhanced
  write-capable pilots now preserve worker, every-line integration and
  independent adversarial review evidence. No provider, Firebase or production
  action occurred.
- Completed the first-two-pilot quality audit and retained its controls as
  permanent policy. Both accepted workers changed only their allowlisted paths
  and had no accepted P0-P2 defect, but review materially improved the work:
  pilot 1 received a P3 documentation correction, Inventory planning was
  rejected before delegation for missing authority/O-038, and pilot 2 was
  reduced from approximately 1,076 to 768 added lines before commit. Worker
  output remains untrusted until exact ancestry/path and line review, complete
  local gates, central regeneration and exact integrated-SHA CI pass;
  independent adversarial review remains mandatory for novel shared semantics
  and accounting/security/Sync/migration/provider/release risk.
- A fresh primary and independent read-only preflight approved
  `project-item-link-presentation-contracts` only as a narrow stateless leaf.
  Two comment-only target paths, six requirements and five planned obligations
  now cover exact Unaccounted/Accounted labels and order, authoritative
  Unaccounted-only Link availability, exact prompt/two-choice membership without
  imposing choice order, fail-closed Accounted/incomplete rows, side-effect-free
  dismissal, restart re-projection and provider isolation. The broader Link
  flow is NO-GO: no command/route, Purchase selection/eligibility, acquisition
  handling, transient persistence, Accounted-item behavior, app/MCP, schema/
  RLS/Sync/provider, migration or production authority exists. Deterministic
  state is 795 recorded / 780 discovered, 366 mapped-or-later / 167 residual /
  44 blockers with only the three documented retired-path warnings. No worker,
  provider, Firebase or production action occurred.
- Worker candidates `de476aed` and corrected `41a2033c` changed only the two
  registered Project selection paths and passed 7 focused/all 218 tests. Root
  every-line review added direct partial/stale selection, distinct insertion
  and both invalid completeness assertions. Independent adversarial review then
  found a P1 false-authoritative-empty defect: the shared list contract allows
  visible count to exceed represented rows, so empty active rows plus ready/
  complete evidence could not prove an omitted row was not active. Candidate
  `41a2033c` is rejected pending correction. The frozen contract now preserves
  and fingerprint-binds exact `sourceDirectoryRowCount`; `noActiveClient`
  requires ready, complete and source-exhaustive evidence, while a no-active
  non-exhaustive projection remains `directoryIncomplete`. The worker is
  correcting only its two owned paths. No provider, Firebase or production
  action occurred.
- Prepared the disjoint `transaction-type-choice-presentation-contracts`
  boundary after read-only scout and independent adversarial review. Preflight
  rejected a second classification aggregate, Business-owner wording and any
  array/declaration/filter/UI-order claim. The corrected leaf reuses the
  verified `TransactionClassification`, returns literal unordered membership,
  derives exact Purchase/Return/Transfer and Client/1584 titles plus the
  existing economic meaning, and makes Transfer source/destination roles
  presentation-equivalent. Exactly two target paths contain comments. The
  complete local ready gate passes at 805 recorded / 790 discovered surfaces,
  376 mapped / 167 residual / 44 blockers, all 211 tests in 48 suites,
  conversion/capability/query/residual controls, M0, target isolation/generated
  contracts, repeatable generation, both staging builds, clean formatting and
  an untouched Firebase checkout. Independent actual-diff review found one P3:
  the first draft could freeze declaration order, restarted five semantic pairs
  instead of all six valid role-bearing classifications, and described all
  public vocabulary rather than only display titles. The corrected obligations
  require literal Set membership plus count three and prohibit array/order
  equality, restart all six shapes with equal restored Transfer descriptors,
  and constrain exact display-title strings. Final independent re-review found
  no remaining P0-P3 issue. Immutable CI on the exact ready commit remains
  mandatory before delegation. No provider, Firebase or production action
  occurred.
- The complete Project Item Link presentation ready gate passes conversion,
  capability, query, regenerated residual and M0 controls, target isolation,
  generated app/MCP contracts, all 189 existing target tests in 44 suites,
  two identical project generations, macOS and iOS staging builds and clean
  formatting. The slice remains comment-only and cannot enter implementation
  until immutable CI passes on the exact ready commit.
- Exact ready commit `47f8fe0d148de617154e40da22bf02d2b47aefc2`
  passed immutable Actions run `33690917866`: conversion traceability passed in
  9 seconds and the isolated target environment passed in 2 minutes 14 seconds
  with all 189 existing tests, generated contracts, both staging builds and
  clean artifacts. Implemented only the two frozen presentation paths. The
  primary agent reviewed every changed line; an independent adversarial review
  found no P0-P2 defect and one P3 self-referential payer-membership assertion.
  That assertion now independently proves exhaustive enum membership and the
  literal unordered two-choice descriptor set; the reviewer confirmed the fix.
  Four focused/all 193 target tests in 45 suites, isolation, generated app/MCP
  contracts, repeatable project generation and both staging builds pass
  locally. The slice is `implemented`, not verified, until final synchronized
  controls and immutable exact-implementation-checkpoint CI pass. No provider,
  Firebase or production action occurred.
- Exact implementation commit
  `d7f4286be2a2fe7f4a8c8e7d59a59547114e47e4` passed immutable Actions run
  `33691932385`: conversion traceability passed in 10 seconds and the isolated
  target environment passed in 2 minutes 19 seconds with all 193 target tests
  in 45 suites, generated contracts, both staging builds and clean tracked
  artifacts. Promoted exactly the Project Item Link presentation dossier and
  its two surfaces to `verified`. The broader Link flow remains unimplemented
  and blocked from this leaf. No provider, Firebase or production action
  occurred.
- Prepared `space-core-details-read-contracts` as a bounded provider-free read
  with exactly two comment-only target paths, eight requirements and six
  planned obligations. Primary and independent adversarial preflight approved
  the slice only after clarifying that exact timestamps are not audit
  provenance, incomplete checklist counts are not authoritative, archived
  detail is not absence, nested Item IDs are unique within a checklist rather
  than globally, and zero-item progress has counts but no invented percentage.
  Deterministic state is 797 recorded / 782 discovered, 368 mapped-or-later /
  167 residual / 44 blockers, and 46 slices claim 113 of 535 target-relevant
  surfaces. The complete local ready gate passes conversion/target/generated-
  contract controls, all 193 existing tests in 45 suites, repeatable XcodeGen
  output and both staging builds. At that local checkpoint no worker
  implementation, provider, Firebase or production action had occurred;
  exact-ready-SHA immutable CI was the remaining prerequisite.
- Exact ready commit
  `8849344dc66d71d9dd9b9ba589a76deb007f3172` passed immutable Actions run
  `33693232878`: conversion traceability passed in 12 seconds and isolated
  target verification passed in 2 minutes 32 seconds with all 193 existing
  tests, generated contracts, both builds and clean tracked artifacts.
  `SUBAGENT-WORK-003` is recorded from that exact base in isolated branch/
  worktree `codex/supabase-slice-space-core-details` /
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_space_core_details`, with
  only the two Space core-details scaffold paths writable. Every-line primary
  review, independent adversarial review, complete local gates and exact
  integrated-SHA CI remain mandatory. No provider, Firebase or production
  action occurred.
- Space core-details candidate `1920389d28a71fff3b3233bef2971fe9525bc6e3`
  was integrated as `72b24afa`/`503b3839`/`05509124` after the primary agent
  reviewed every source/test line and an independent adversarial reviewer
  checked the exact frozen-base diff. The review process caught four concrete
  test-quality gaps: direct normalization refusal for notes/checklist names/item
  text, independent AccountID/SpaceID fingerprint binding, port-side request
  validation, and exact unique diagnostic-code stability. Each was corrected,
  re-reviewed and retested. Six focused and all 199 target tests in 46 suites,
  target isolation/generated-contract checks, repeatable project generation,
  both staging builds and clean diff checks pass with no remaining P0-P3
  finding. Exact integration checkpoint
  `d5afa699ce09c105a82b187f9953e06a09ac2b10` then passed immutable Actions
  run `33695588031`: conversion traceability passed in 10 seconds and isolated
  target verification passed in 3 minutes 16 seconds with all 199 tests,
  generated contracts, both builds and clean tracked artifacts. The slice and
  its two surfaces are `verified`. No provider, Firebase or production action
  occurred.
- Rescouted the next boundary after Space core details. A read-only scout and an
  independent adversarial reviewer approved only
  `project-core-details-read-contracts`: exact Account/Project/Client core
  identity, verified ProjectSummary fields, canonical optional description,
  exact locally observed Project revision and explicit local readiness/
  absence/failure truth. The review requires revision to remain local conflict-
  precondition evidence distinct from LocalDataVersion, accepts an active
  Project with an archived Client, and rejects any complete-workspace, current
  Firebase/app/MCP, child, media, accounting, mutation, authorization,
  provider/schema/RLS/Sync, migration or production claim. Two new target-only
  paths contain comments only. The complete local ready gate passes: all 199
  existing target tests in 46 suites, repeatable XcodeGen output, both staging
  builds, target isolation/generated contracts and clean-artifact checks pass.
  Exact ready commit `4fd81f477f87de9528c25559d0950dbdd0136717`
  passed immutable Actions run `33697079580`: traceability passed in 13 seconds
  and isolated target verification passed in 2 minutes 51 seconds. Registered
  `SUBAGENT-WORK-004` on branch
  `codex/supabase-slice-project-core-details` in isolated worktree
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_project_core_details`,
  with only the two scaffold paths writable. Every-line primary review,
  independent adversarial review, complete integration gates and exact
  integration-commit CI remain mandatory. No provider, Firebase or production
  action occurred.
- Registered worker candidate
  `c7719ce51a83989f399f0ed8c2fd9c1c0142da67` changed only the two
  `project-core-details-read-contracts` paths and passed six focused and all
  205 tests in 47 suites. Primary every-line review nevertheless found four
  omitted direct edge assertions: distinct multiple rows, negative visible
  count, stale-plus-complete evidence and the exhaustive waiting-state
  partition. Test-only correction
  `62d59f1d45a90cfbfb3fecc86486a9c95173d0d4` resolved all four. Primary and
  independent adversarial re-review pass with no remaining P0-P3 finding; the
  candidate was integrated as `bd576c52`/`01fc6a0f`. Complete local integration
  gates pass: conversion/capability/query/residual/M0 controls, target isolation
  and generated contracts, 6 focused and all 205 tests in 47 suites, repeatable
  project generation, both staging builds, clean formatting and no source-
  project change. M1/M2 remain at their exact expected 2/167 blockers.
  The local checkpoint was then held pending the immutable CI result recorded
  in the following entry. No provider, Firebase or production action occurred.
- Exact integration checkpoint
  `d460b02105cbb8446d69a09b4b246e0600d50fef` passed immutable Actions run
  `33698741756`: conversion traceability passed in 9 seconds and isolated target
  verification passed in 3 minutes 21 seconds with all 205 tests, generated
  contracts, both staging builds and clean tracked artifacts. Promoted exactly
  `project-core-details-read-contracts` and its two surfaces to `verified`.
  No provider, Firebase or production action occurred.
- Rescouted the next boundary after Project core details. A read-only scout and
  independent adversarial reviewer approved only
  `client-core-details-read-contracts`: exact Account/Client identity, verified
  ClientSummary fields, exact locally observed revision and explicit local
  readiness/absence/failure truth. The review requires byte-exact preservation
  of valid padded names, accepts equal finite audit timestamps without claiming
  provenance, keeps revision distinct from LocalDataVersion/updatedAt, and
  rejects any Client workspace/CRM, Project/count, Transfer, financial/history,
  mutation, authorization, persistence, provider/schema/RLS/Sync/Auth, app/MCP,
  migration or production claim. General Space lists and create-from-template
  were rejected because their product semantics remain unresolved. Two target-
  only paths contain comments. The complete local ready gate passes all 205
  target tests in 47 suites, conversion/capability/query/residual controls, M0,
  target isolation/generated contracts, repeatable project generation, both
  staging builds and clean diff formatting. At that ready-gate checkpoint,
  immutable CI on the exact ready commit remained the final prerequisite before
  delegation. No provider, Firebase or production action occurred.
- Exact ready commit `e925a7a07a0eccf5e1563c4b4a4abee58238e7db`
  passed immutable Actions run `33700564469`: traceability in 7 seconds and
  isolated target verification in 2 minutes 22 seconds. Created isolated branch
  `codex/supabase-slice-client-core-details` and worktree
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_client_core_details`, then
  registered active `SUBAGENT-WORK-005` with ownership of exactly the two Client
  core-details paths. Primary every-line and independent adversarial review,
  complete local integration gates and exact integration-commit CI remain
  mandatory; the candidate is not yet accepted or verified. No provider,
  Firebase or production action occurred.
- Worker candidate `549ecfa6896533fa34b9d8f81efb8e57559e6312`
  exactly descended from the ready commit and changed only the two registered
  Client paths. Primary every-line review found no implementation defect and
  independently reran 6 focused/all 211 target tests. Independent adversarial
  review found one P3 false-positive assertion: a catch-all helper could treat
  an unrelated error as success for valid waiting states. Test-only correction
  `cd433de292a917eaef3ee9db81ef89b52bc88c1e` now directly constructs and
  asserts `notRequested`/`loading`/`blocked` and requires exact
  `invalidWaitingState` for `ready`/`partial`/`stale`. Primary and independent
  re-review report no remaining P0-P3 issue. Integrated as
  `b96377d76df634210dfee4367deb34dbbfdf658d`/
  `de85667ce55fbc30b5ee576b2ba7c087d588ea53`. Central regeneration and the
  complete local integration gate pass: conversion/capability/query/residual/M0
  controls, target isolation/generated contracts, 6 focused and all 211 tests
  in 48 suites, repeatable project generation, both staging builds, clean
  formatting and untouched Firebase source checkout. M1/M2 remain at the exact
  expected 2/167 blockers. The local checkpoint was held pending the immutable
  CI result recorded in the following entry. No provider, Firebase or
  production action occurred.
- Exact integration checkpoint
  `6cea8459d0e50f1743004cdf11` passed immutable Actions run
  `33702499992`: conversion traceability passed in 13 seconds and isolated
  target verification passed in 3 minutes 39 seconds with all 211 tests,
  generated contracts, both staging builds and clean tracked artifacts.
  Promoted exactly `client-core-details-read-contracts` and its two registered
  surfaces to `verified`. No provider, Firebase or production action occurred.
- Verification-control commit `8aadd9015c8f552d824775027a8a11703f52fb41`
  passed immutable Actions run `33703099284`: conversion traceability and the
  isolated target job, all 211 tests, generated contracts, both staging builds
  and clean artifacts passed. The clean Client worker worktree was removed;
  its branch and reviewed candidate commits remain recoverable. No provider,
  Firebase or production action occurred.
- Rescouted the next Project setup boundary. Independent adversarial preflight
  rejected a duplicate Account-only Client query port and an unsupported final
  UI no-auto-selection rule before freeze. The corrected
  `project-existing-client-selection-read-contracts` boundary is a pure
  projection over the verified Client directory: active rows remain in exact
  upstream order, no selected/default value exists, an explicit projected
  ClientID produces only the verified `.existing` setup input, and a distinct
  evidence fingerprint binds ordered active rows, source fingerprint, visible
  count plus every other readiness field. This prevents removed/reordered rows
  or a changed-but-still-structurally-valid count from restarting as unchanged
  evidence without claiming authentication or row immutability. This visible-
  count omission was found during independent review of the actual ready diff;
  the correction and regenerated controls received final independent GO with
  no remaining P0-P3 finding.
  Exactly two target-only paths contain comments. The complete local ready gate
  passes at 803 recorded / 788 discovered surfaces, 374 mapped / 167 residual /
  44 blockers, all 211 tests in 48 suites, conversion/capability/query/residual
  controls, M0, target isolation/generated contracts, repeatable project
  generation, both staging builds, clean formatting and an untouched Firebase
  checkout. Exact ready-commit CI remains mandatory before delegation. A
  second read-only scout recommends the disjoint Transaction type-choice
  presentation boundary for later independent preflight; no second slice is
  frozen or implemented yet. No provider, Firebase or production action
  occurred.
- Exact ready commit `e6d805630c2ba1f366a6ecf1715a8cf0e60a90ee`
  passed immutable Actions run `33704608811`: conversion traceability and the
  isolated target job passed, including all 211 existing tests, generated
  contracts, both staging builds and clean tracked artifacts. Created isolated
  branch/worktree `codex/supabase-slice-project-existing-client-selection` /
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_project_existing_client_selection`
  at that exact commit and registered active `SUBAGENT-WORK-006`. The worker
  owns only the two Project existing-Client selection target paths. Primary
  every-line review, independent adversarial review, the complete integration
  gate and immutable CI on the exact integration commit remain mandatory. No
  provider, Firebase or production action occurred.
- `SUBAGENT-WORK-006` produced four bounded candidates from the exact ready
  base; final candidate `d206f5424c3f3bdb2b66f96d8b4acb35b425a9a3`
  changed only the two registered target paths. Root every-line review required
  four direct test-coverage corrections across the candidate sequence.
  Independent adversarial review rejected an earlier candidate for a P1 false-
  authoritative-empty defect: a visible count greater than represented source
  rows could hide an active Client. The correction stores and fingerprint-binds
  `sourceDirectoryRowCount`, validates the count relationship and permits
  `noActiveClient` only when ready, complete and source-exhaustive. Final root
  and independent review found no remaining P0-P3 issue; worker, root and
  reviewer focused runs pass all seven tests, and the worker full run passes all
  218 tests in 49 suites. The candidates were integrated as commits
  `63baff1a`, `cf9c666f`, `263e8ac7` and `b4e4edae`. The complete central
  integration gate passes: conversion sync/check/report,
  capability/query/residual/M0 controls, target environment/generated contracts,
  seven focused/all 218 tests in 49 suites, repeatable project generation, both
  staging builds, clean formatting and an untouched Firebase checkout.
  Immutable exact-integration-checkpoint CI remains pending.
  The disjoint `transaction-type-choice-presentation-contracts` ready gate also
  passed exact ready commit `5e79d83d` in immutable Actions run `33706147469`,
  and the corrected Project-selection control checkpoint `442ecfce` passed
  immutable run `33706591706`; that next slice has not been delegated. No
  provider, Firebase or production action occurred.
- Exact integration checkpoint `9ff6540760548377fd5c4f528974045777619aad`
  passed immutable Actions run `33707305340`: conversion traceability passed in
  12 seconds and isolated target verification passed in 2 minutes 44 seconds,
  including all 218 tests, generated contracts, both staging builds and clean
  tracked artifacts. Promoted exactly
  `project-existing-client-selection-read-contracts` and its two registered
  surfaces to `verified`. No provider, Firebase or production action occurred.
- Promotion-control commit `8cf4bec690345eacfe77b954d8deddabda0ec128`
  passed immutable Actions run `33707620621`: conversion traceability passed
  in 7 seconds and isolated target verification passed in 2 minutes 54 seconds
  with all 218 tests, generated contracts, both staging builds and clean
  tracked artifacts. Removed the clean Project-selection worker worktree while
  retaining its branch and reviewed candidates. Created isolated branch/worktree
  `codex/supabase-slice-transaction-type-choice` /
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_transaction_type_choice`
  at that exact green base and registered `SUBAGENT-WORK-007` with ownership of
  only the two Transaction type-choice target paths. Assignment-control CI,
  primary every-line review, independent adversarial review, complete local
  integration gates and exact integration-SHA CI remain mandatory. No provider,
  Firebase or production action occurred.
- Assignment-control commit `49289922cbfcc345c223d7589064df3519268349`
  passed immutable Actions run `33707949029`: conversion traceability passed in
  7 seconds and isolated target verification passed in 2 minutes 51 seconds,
  including all 218 existing tests, generated contracts, both staging builds
  and clean tracked artifacts. Released active `SUBAGENT-WORK-007` from exact
  green base `8cf4bec6`; it may change only the two registered Transaction type-
  choice paths and cannot promote status. Primary every-line review,
  independent adversarial review, complete central gates and immutable exact-
  integration-SHA CI remain mandatory. No provider, Firebase or production
  action occurred.
- `SUBAGENT-WORK-007` produced candidates `0170ac0a`, `f38258a5` and final
  `c22fac22565f1d48d9240698dbac0ab4a8016607` from exact base `8cf4bec6`;
  every candidate changed only the two registered paths. Primary every-line
  review found no implementation defect. Independent review rejected the first
  candidate for one P3 missing syntactically malformed JSON case. Review of the
  correction then found a second P3 evidence problem: the frozen wording could
  falsely imply the generic codec normalized a raw parser error into
  `TransactionTaxonomyFailure`. Final `c22fac22` directly proves raw
  `DecodingError`, explicitly not a taxonomy failure, and separately proves the
  test-only consumer normalizes it to rejected `invalidEncodedClassification`
  without a descriptor. Replacement independent final review found no code
  P0-P3 issue and approved the matching dossier correction. Integrated the
  candidate sequence as `5faf4b29`, `075fd70b` and `da63fb85`. Worker/root
  focused runs pass all six tests. The complete central gate passes all 224
  tests in 50 suites, conversion/M0 and target isolation/generated-contract
  controls, two identical generated-project hashes (`0657194a` project and
  `388303af` scheme), both staging builds and clean artifacts. Immutable exact-
  integration-SHA CI remains pending. No provider, Firebase or production
  action occurred.
- Recalibrated delegated-work economics after reviewing the completed worker
  topology. A worktree remains mandatory for any concurrent write-capable
  worker because it isolates the base, index, untracked files and candidate
  lineage, but two files are not themselves a sufficient reason to delegate.
  The default delegated outcome is now a coherent roughly 600–1,200-line,
  two-to-six-leaf-path slice; the integration agent normally keeps sub-300-line
  or sub-20-minute work. Independent review remains mandatory until five
  consecutive qualifying candidates; the Project selection P1 finding reset
  that counter and the corrected Transaction candidate is the first subsequent
  P0-P2-clean candidate. Risk domains always retain independent review.
- Exact Transaction type-choice checkpoint
  `fcff5b854b16d289dfcf159b31fcd45a973c7402` passed immutable Actions run
  `33717396519`: conversion traceability passed in 14 seconds and the isolated
  target job passed in 3 minutes 8 seconds with all 224 tests, generated
  contracts, repeatable project generation, both staging builds and clean
  tracked artifacts. Promoted the dossier, two surfaces, evidence and worker
  assignment to verified. No provider, Firebase or production action occurred.
- Verification-promotion commit
  `5960bd9d9d3a25050b027e727a0021bb8477b878` passed immutable Actions run
  `33717813102`: conversion traceability passed in 10 seconds and the isolated
  target job passed in 3 minutes 30 seconds. Removed the clean
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_transaction_type_choice`
  worker worktree after validating exact head `c22fac22`; retained branch
  `codex/supabase-slice-transaction-type-choice` and all reviewed candidate
  commits. No provider, Firebase or production action occurred.
- Applied the larger-slice delegation policy to the next scout. Its first
  recommendation, `CreateSpaceFromTemplate`, was withdrawn because it missed
  the explicit `e925a7a0` product-authority rejection; no relevant authority
  has since resolved O-026 or the Space-name, nested-ID, atomicity, provenance,
  scope/staleness and customization questions. Independent preflight of the
  replacement Project-browsing outcome rejected noncanonical sorting, fixed
  tabs, full-card naming, direct `ScopedRoute` construction, Client-lifecycle
  filtering and nonexhaustive empty claims. The corrected four-leaf-path
  `project-browsing-presentation-contracts` boundary preserves upstream order
  and covers only directory core rows, content-bound selection, exact
  `ProjectCoreDetailsRequest` derivation and request-validated detail-header
  truth. Four comment scaffolds are classified ready; no executable behavior,
  provider, Firebase or production action occurred.
- Passed the complete Project-browsing local ready gate: 809 recorded / 794
  discovered surfaces with zero errors and the three established retired-path
  warnings; 380 mapped / 167 residual / 44 blockers; M0; all 224 existing tests
  in 50 suites; generated contracts; two identical XcodeGen outputs; both
  staging builds; and clean diff formatting. The four comment-only scaffold
  hashes and stable generated project/scheme hashes are recorded in
  `EVID-PROJECT-BROWSING-PRESENTATION-001`. Actual-ready-diff review and exact-
  commit immutable CI remain required before delegation.
- Independent actual-ready-diff review found a P1 unrelated D-023 citation, a
  P1 missing exact Client-lifecycle authority and a P2 request-derivation shape
  that could be interpreted as replaying stale selection evidence. The dossier
  now uses D-006 only for Client/Project identity, cites `Client lifecycle`
  directly for archived-Client history and makes
  `detailRequest(validating: currentSnapshot)` the only request-producing call.
  Independent correction re-review inspected every changed/untracked path and
  returned GO with no remaining P0-P3 issue or overclaim. The diff is safe for
  the exact ready commit; immutable CI remains required before delegation.
- Exact ready commit `459a58123ac7241984ddee6d559e33f4bca931d4`
  passed immutable Actions run `33720134399`: conversion traceability and the
  isolated target job both succeeded. Created clean branch
  `codex/supabase-slice-project-browsing` and worktree
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_project_browsing` at that
  exact commit. Registered `SUBAGENT-WORK-008` with only the four Project-
  browsing implementation/test leaf paths writable; canonical docs, graphs,
  Firebase, providers and external systems remain forbidden. Assignment-control
  commit `2cd61b28` also passed both jobs in immutable run `33720523680`.
- Integrated corrected Project-browsing candidate `73f94525` after rejecting
  green initial candidate `964dbabc` for a P1 valid-sibling selection rebind and
  P2 manifest/API name mismatch. The correction fingerprints the exact selected
  row, directly tests sibling substitution, and exposes the frozen
  `ProjectDirectoryPresentationSnapshot` name. Both primary every-line and
  independent adversarial review report no remaining P0-P3. Seven focused and
  all 231 tests in 52 suites pass; conversion/capability/query/residual/M0,
  target isolation/generated contracts, repeatable project generation, both
  staging builds and clean formatting pass. Exact integration checkpoint
  `717a0eb89099676bd4c09d6b0665dd83ab9739d8` then passed both jobs in immutable
  Actions run `33723154735`; `PBROWSE-TEST-007`, the slice, its four surfaces
  and `SUBAGENT-WORK-008` are now `verified`.
- Promotion checkpoint `51e0544eed0388f274e7bf8963fa49fe84271826`
  passed immutable Actions run `33723771668`: conversion traceability completed
  in 47 seconds and the isolated target job completed in 2 minutes 1 second.
  After confirming the worker worktree was clean at reviewed candidate
  `73f94525`, removed
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_project_browsing` and
  retained branch `codex/supabase-slice-project-browsing` with both rejected and
  corrected candidate history recoverable. No Firebase, provider, hosted or
  production action occurred.
- Cleanup checkpoint `7b40a9660593b8a1ab3220b432da26e6d5f2dbbe`
  passed immutable Actions run `33724031789`: conversion traceability and the
  isolated target job both succeeded, including all 231 tests and both staging
  builds. The canonical Supabase worktree is clean and the Firebase checkout
  remains untouched at `fe018501`.
- Two read-only scouts independently audited the next candidate set. Rejected
  pinned-budget presentation because O-005 and category-visibility/missing-pin/
  card-fallback semantics remain open; rejected Project browsing shell as a
  duplicate/premature runtime boundary; rejected Transaction list/card under
  O-029/O-032; and rejected the general Space list under missing list authority
  plus O-037. A generic deterministic export renderer remains a viable later
  infrastructure candidate but cannot yet produce an approved named
  Transaction export profile. Selected the more complete
  `project-setup-form-presentation-contracts` boundary instead: two target-only
  comment scaffolds compose verified active-Client selection, category reference
  and Project setup command semantics, permit zero categories, preserve exact
  nullable allocations and require current-evidence validation before command
  derivation. No executable behavior or provider/Firebase/production action has
  occurred. The complete local ready gate passes with 811 recorded / 796
  discovered surfaces, zero errors and three established warnings; 382 mapped /
  167 residual / 44 blockers; M0; all 231 tests in 52 suites; target isolation
  and contracts; repeatable project generation; both staging builds and clean
  formatting. Independent actual-diff review rejected a P1 unsupported mixed-
  currency rule and P2 ambiguous creation-description behavior. The correction
  removes Project-wide currency invention, reuses the verified
  `ProjectDescriptionReplacement` normalizer and adds allocation-order plus
  represented new-Client-ID collision hardening. Correction re-review then
  found and corrected one P2 wording overclaim that could have treated a partial
  snapshot as complete. The final independent re-review returned GO with no
  remaining P0-P3 issue. Exact ready commit
  `a4dd7cbdca3dcf7b31c386e4f451ad320b7c8e62` passed both jobs in immutable
  Actions run `33726485780`. Created branch
  `codex/supabase-slice-project-setup-form` and temporary worktree
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_project_setup_form` at
  that exact commit. `SUBAGENT-WORK-009` grants only the two frozen Swift leaf
  paths. Assignment-control commit
  `10913c5761561ad9fdd0713627ae82396e9f3ff8` passed both jobs in immutable
  Actions run `33726899284`; `/root/project_setup_form_worker` is active in the
  temporary worktree. Primary every-line review, independent adversarial review,
  the complete integration gate and exact integration CI remain required.
- Worker candidate `7a881af2ff2ef86d1ef4ca4f08c7e604f0aacbe2`
  changed exactly the two allowlisted files and passed six focused plus all 237
  tests, but primary every-line review rejected it for a P2 gap: its restart
  test promised every-field binding while mutating only a representative subset.
  Corrected worker tip `37145ae3548e577469599ff2381c02258b01f130`
  adds a table-driven reciprocal matrix over every preparation, Client,
  category and selection field with layer-appropriate failures. Final primary
  and independent adversarial review return GO with no remaining P0-P3.
  Cherry-picked the implementation as `7365fbcb` and correction as `bfac9f7a`.
  The complete local integration gate passes: conversion/capability/query/
  residual/M0 controls; target isolation and generated contracts; six focused
  and all 237 tests in 53 suites; warnings-as-errors; repeatable XcodeGen hashes
  `0657194a` / `388303af`; macOS and generic iOS Simulator staging builds; clean
  formatting and exact two-path worker scope. Exact integration-commit CI
  `147d22de801b15794d8ebb4786eaea86e4346940` passed both jobs in immutable
  Actions run `33729967356`; the slice, both surfaces and `SUBAGENT-WORK-009`
  are now verified. Promotion CI and clean temporary-worktree removal remain.
- Promotion commit `5322adfca32ce5fd90f790f70ed584090ab5eee1`
  passed both jobs in immutable Actions run `33730394704` (traceability 9s;
  isolated target 2m21s). Confirmed the worker worktree clean at corrected tip
  `37145ae3548e577469599ff2381c02258b01f130`, removed
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_project_setup_form`, and
  retained branch `codex/supabase-slice-project-setup-form` plus both candidate
  commits. The canonical Supabase worktree is clean; Firebase remains untouched.
- Selected `space-checklist-editing-presentation-contracts` as the next bounded
  provider-free product slice. It claims only comment-only target leaves
  `LedgeriOS/LedgerTargetCore/SpaceChecklistEditingPresentation.swift`
  (`SWIFT-A9BCA70B7F9C`) and
  `LedgeriOS/LedgerTargetCoreTests/SpaceChecklistEditingPresentationTests.swift`
  (`TEST-94F32F5E9219`); source UI/test surfaces remain `target_mapped` and
  Firebase is unchanged. Independent authority preflight rejected the first
  draft for unsafe partial/stale replace-all admission, harmless-refresh
  overbinding, unsupported checklist reorder/cross-list movement and inability
  to retain blank intermediate form text. Corrected actual-diff review then
  required an exact ready-complete retryable-cache predicate, current/stale
  eligibility-transition tests, accurate source wording and this continuity
  checkpoint. Those corrections are applied. The complete local ready gate
  passes with 813 recorded / 798 discovered surfaces, zero errors and three
  established warnings; 384 mapped / 167 residual / 44 blockers; M0; all 237
  tests in 53 suites; warnings-as-errors; target isolation/contracts; repeatable
  project hashes `0657194a` / `388303af`; both staging builds; valid JSON and
  clean formatting. Final independent corrected-diff re-review found no
  remaining P0-P3. Exact ready commit
  `5c2a185be15189bc8aa1606f838eee5a362780fc` passed both jobs in immutable
  Actions run `33732917130` (traceability 8s; isolated target 3m12s). Created
  branch `codex/supabase-slice-space-checklist-edit` and temporary worktree
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_space_checklist_edit` at
  that exact commit. `SUBAGENT-WORK-010` grants only the two frozen Swift leaf
  paths. Assignment-control commit
  `cc6faddf707694e0c4a7af00a770d8a2672b8151` passed both jobs in immutable
  Actions run `33733387021` (traceability 10s; isolated target 3m0s).
  `/root/space_checklist_edit_worker` is active in the temporary worktree.
  Primary every-line review, independent adversarial review, the complete
  integration gate and exact integration-SHA CI remain required.
- Worker candidate `37714106e3fcc4271bcdc5ee93bb7a66c41eca23`
  changed exactly the two allowlisted files and passed six focused plus all 243
  tests, but primary and independent review rejected incomplete correct-layer,
  cached/current field, fingerprint, command-forwarding and token evidence.
  Expanded candidate `d50cc9e383f42ffe8519fd27980dfa96ea59ada4`
  closed those gaps and exposed a real nil-cache restart defect; review then
  caught that explicit `cached: null` was still noncanonical. Corrected tip
  `272b705e246cf505007f38a3d3d386dd8fbc127a` accepts only absent nil cache or a
  present nonnull strict snapshot and adds reciprocal retryable/unavailable/
  required-update plus Business Inventory coverage. Final primary and
  independent adversarial review return GO with no remaining P0-P3. The
  candidate was cherry-picked as `6859b59c`. The complete local integration
  gate passes conversion/capability/query/residual/M0 controls, target isolation
  and generated contracts, six focused and all 243 tests in 54 suites,
  warnings-as-errors, repeatable XcodeGen hashes `0657194a` / `388303af`, macOS
  and generic iOS Simulator staging builds, clean formatting and exact two-path
  worker scope. Exact integration-commit CI remains required before verification.
- Exact integration commit
  `5a5c67b1319e3fcc41290469f7f39db9d515b284` passed both jobs in immutable
  Actions run `33739849778` (conversion state and traceability 12s; isolated
  target environment 2m11s). The checklist-editing slice and both claimed
  surfaces are verified. Promotion-checkpoint CI must pass before the clean
  temporary worker worktree is removed; its branch will be retained.
- Promotion commit `fd54f8c5db700af6ab8833e195da04256836ea58`
  passed both jobs in immutable Actions run `33740343879` (conversion state and
  traceability 8s; isolated target environment 2m51s). Confirmed the worker
  worktree clean at corrected tip
  `272b705e246cf505007f38a3d3d386dd8fbc127a`, removed
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_space_checklist_edit`,
  and retained branch `codex/supabase-slice-space-checklist-edit` plus all three
  candidate commits. The canonical Supabase worktree is clean; Firebase remains
  untouched.
- A read-only scout selected direct Space creation ahead of Space-details
  editing and rejected the complete assignment picker because selected-Item/
  current-placement authority plus archive/no-op behavior are not settled.
  Independent preflight then rejected the first direct-create presentation
  draft for application-layer inversion, unsupported initial-field/cancellation
  policy, redundant fingerprints/restart claims, an unclosed current validator
  responsibility, O-026 overreach and an incomplete product outcome. The
  corrected `direct-space-creation-use-case-contracts` package keeps raw input
  transient, reuses only `SpaceDisplayName`/`SpaceCreationNotes`, and gives
  operation metadata, command assembly, one port call and receipt validation to
  `DirectSpaceCreationUseCase`. The two current Firebase validation surfaces are
  mapped to this canonical target replacement but remain untouched; only the
  two target leaf scaffolds may change. Two rejected never-committed scaffold
  records were removed from the uncommitted manifest rather than falsely
  retired. The complete local ready gate passes with 815 recorded / 800
  discovered surfaces, zero errors and three established warnings; 388 mapped /
  167 residual / 44 blockers; M0; all 243 tests in 54 suites; warnings-as-errors;
  target isolation/contracts; repeatable project hashes `0657194a` / `388303af`;
  both staging builds and clean formatting. Two independent corrected-diff
  reviews return GO after splitting D-023 accounting authority from direct-
  create scope, preventing raw port-error leakage and preserving exact receipt
  local state. Exact-ready-SHA CI was still required at that checkpoint. No extra slice worktree has been
  created; implementation will use one writer in this Supabase worktree plus
  read-only independent review. Firebase remains unchanged.
- Exact ready commit `b8869ac2a0b3cfc48c4c197cc39baa8ceec60cfe`
  passed both jobs in immutable Actions run `33744781549` (conversion
  traceability 16 seconds; isolated target 3 minutes 7 seconds). The direct
  implementation changed exactly the two frozen target leaves in the existing
  Supabase worktree. Independent review found nonreciprocal command-field checks,
  a normalized-failure fixture indistinguishable from the fallback, cross-scope
  duplicate-name evidence and missing exact empty/nil/long raw-value boundaries.
  The reviewers initially disagreed about `CancellationError`; architecture
  rules 7/8 resolved the distinction in favor of preserving structured-
  concurrency cancellation without choosing form-cancel UX while still
  normalizing unexpected transport failures. The correction exactly binds every
  caller and derived command field and closes every boundary matrix. Two independent
  final reviews return GO with no P0-P3. The complete local integration gate
  passes conversion/capability/query/residual/M0 controls, target isolation and
  generated contracts, six focused and all 249 tests in 55 suites, warnings-as-
  errors, repeatable project hashes `0657194a` / `388303af`, both staging builds,
  valid JSON and clean formatting. Exact implementation commit
  `c35f1cefc88d964035976d537c2f829b4db62a8a` passed immutable Actions run
  `33746648677` (traceability 10 seconds; isolated target 2 minutes 58 seconds).
  The four claimed responsibilities and slice are verified; Firebase remains
  unchanged.
- Verification-promotion commit
  `880727f74355699e10466e68d29e1265d5f95fe1` passed immutable Actions run
  `33747118216` (traceability 7 seconds; isolated target 2 minutes 39 seconds).
  The canonical Supabase worktree is clean, no extra slice worktree exists, and
  the current Firebase checkout remains untouched.
- A fresh scout from that verified baseline ranks a provider-free Space-details
  update use case first, ahead of chosen-Project note capture and Project archive
  dispatch. The candidate composes verified Space name/notes validation,
  single-Space core evidence, complete details-replacement operation and the
  verified direct-use-case orchestration precedent. It must not revive the
  removed direct-create form-presentation surfaces or claim initial form state,
  dirty/cancel UX, form restart, scope/lifecycle/child mutation, provider,
  migration or production behavior. Independent authority preflight was
  requested before any scaffold or prospective surface was added.
- Independent preflight returned conditional GO after two corrections. The
  entire source `EditSpaceDetailsModal` cannot advance because initial state,
  transient UI, immediate error display, dirty/no-op policy, dismissal, layout,
  copy and composition remain unconverted; only save-intent normalization and
  dispatch are mapped here. The use case also cannot consume Space-core update/
  readiness evidence or choose active/archive eligibility. The corrected ready
  dossier claims exactly new target surfaces `SWIFT-306643A5CD0D` and
  `TEST-235F73A8DC9E`; `SWIFT-9F4789704808` remains target_mapped with explicit
  partial-responsibility evidence. Two comment-only leaves freeze exact typed
  Account/Space/revision input, canonical text validation, application-owned
  complete-replacement command dispatch, receipt/error/cancellation behavior
  and exclusions. Canonical validation intentionally corrects the current
  newline-only-name hole. Control state is 817 recorded / 802 discovered with
  zero errors and three established warnings; 390 mapped-or-later / 167 residual
  / 44 blockers. Independent actual-ready-diff reviewers first caught five
  contract overclaims and a missing conversion-control crosswalk authority.
  The corrected package separates diagnostics privacy from command shape,
  avoids claiming physical effects, leaves dirty/no-op policy undecided,
  narrows metadata exclusions and assigns source-status semantics to the
  registered target-mapping control. Both reviewers return GO with no remaining
  P0-P3 finding. The complete local ready gate passes, including all 249 target
  tests in 55 suites, repeatable generation and both staging builds. Immutable
  exact-ready-SHA CI is the sole remaining prerequisite before implementation.
- Exact ready commit `b6a98ca0fd33bb170bd9e7f70e7dc8f76a17b19b`
  passed immutable Actions run `33749431949` (conversion traceability 9 seconds;
  isolated target 3 minutes 7 seconds). Implementation then changed exactly the
  two frozen target leaves. It adds transient raw input and canonical intent,
  assembles the existing complete-replacement command in the application layer,
  invokes the port once after validation, validates the receipt, preserves Swift
  cancellation and both normalized failure families, and bounds unexpected
  transport errors. Independent review found an imprecise no-base-detail claim,
  missing exact long-raw assertions and incomplete diagnostic-leakage checks;
  all were corrected and both final reviewers return GO with no P0-P3. Six
  focused and all 255 target tests in 56 suites, warnings-as-errors,
  conversion/target controls, stable project hashes `0657194a` / `388303af`,
  both staging builds, valid JSON and clean formatting pass locally. Exact
  implementation commit `f0d7c3fa950485857f23cd7faf9165e8ac23b562`
  passed immutable Actions run `33750834849` (traceability 11 seconds; isolated
  target 3 minutes 17 seconds). The slice and its two target leaves are verified;
  the current source modal remains target_mapped throughout.
- Verification-promotion commit
  `d74efb4424a559b007a032baa29d5a31af227754` passed immutable Actions run
  `33751486795`; the verified Space-details boundary is frozen at this baseline.
- Fresh authority preflight returned GO only for a strict archive-only Project
  application path above the existing verified archive operation. The ready
  package adds exactly comment-only target surfaces `SWIFT-7C5BD31FBF71` and
  `TEST-29C0CCC4353F`, with six reciprocal planned obligations. The future
  non-Codable intent carries exact Account/Project/expected revision; the use
  case adds operation metadata, constructs the existing command, makes exactly
  one post-construction port call, validates the receipt, preserves cancellation
  and normalized failure, and bounds raw errors. Source `ProjectDetailView`
  remains characterized under O-024. `MCPTOOL-921DA05B3330` remains target_mapped
  across the existing `ArchiveProjectCommand` and separate future
  `RestoreProjectCommand`, while this slice advances only archive and implements
  no MCP wiring. Control state is 819
  recorded / 804
  discovered, 392 mapped-or-later / 167 residual / 44 blockers, subject to the
  local sync/check recorded by this checkpoint. Two independent initial actual-
  diff reviews caught and drove correction of missing MCP source accounting and
  an incorrect attribution of exact revision mechanics to the Projects product
  spec. Corrected-diff review then caught that an archive-only command did not
  completely map the MCP tool's archive/restore Boolean. The source responsibility
  now maps to the existing `ArchiveProjectCommand` and separate future
  `RestoreProjectCommand`; verified archive-operation evidence owns only the
  implemented archive mechanics. Final review also corrected missing restore
  migration reconciliation and stale future-command wording, then caught that
  the first reconciliation edit had landed on the broad MCP module rather than
  the exact tool. The unrelated change is reverted and the tool now owns exact
  archive/restore reconciliation. The
  complete corrected local ready gate passes all 255 tests in 56
  suites with warnings as errors, target/conversion controls, repeatable hashes
  `0657194a` / `388303af`, both staging builds and clean formatting. Final corrected-
  diff re-review returned GO from both independent reviewers. Exact ready commit
  `bf4294727f4b2bde117dc0eaf9e74e9769fe8699` passed immutable run
  `33755885978` (traceability 7 seconds; isolated target 2 minutes 49 seconds).
- Implemented exactly the two frozen archive-use-case leaves. The non-Codable
  intent binds exact Account/Project/revision; the use case assembles the
  existing verified archive draft/command, invokes `ProjectArchiving` once after
  construction, validates the receipt, preserves cancellation and normalized
  failures, and bounds raw errors. Independent review found incomplete exact
  encoded-shape/diagnostic coverage and a physical-durability wording overclaim;
  both were corrected, and both final reviewers return GO with no P0-P3. Six
  focused and all 261 target tests in 57 suites pass with warnings as errors;
  target/conversion controls, repeatable hashes `0657194a` / `388303af`, both
  staging builds and clean formatting also pass. Exact implementation commit
  `232acf922b6c1ab1016017c3ebc3b926b164466c` passed immutable Actions run
  `33758116150` (traceability 9 seconds; isolated target 3 minutes 8 seconds).
  The dossier and both target surfaces are verified; source `ProjectDetailView`
  remains characterized and the archive/restore MCP surface remains mapped only.
- Verification-promotion commit
  `97cf6156ce4e93a29ded7465d4b1d083fab5c4ef` passed immutable Actions run
  `33759414349` (traceability 10 seconds; isolated target 2 minutes 56 seconds),
  freezing the verified archive-use-case boundary.
- Rejected the next chosen-Project note-creation use-case candidate before
  READY. The first actual-diff review caught omitted MCP validation-helper
  accounting; the second caught that the proposed blank-only/lossless-text rule
  silently chose among conflicting app, MCP and target behaviors without a
  canonical target heading or confirmed decision. Removed both comment
  scaffolds, their dossier/evidence and manifest records; no executable code was
  written or committed. O-039 now records the product choice and blocks eight
  relevant source/integration surfaces. Exact MCP behavior and stale QuickNote
  target names are corrected. Current control state is 819 recorded / 804
  discovered, 385 mapped-or-later / 174 residual / 45 blockers with only the
  three established retired-path warnings.
- The rejection/correction checkpoint is immutable at exact commit
  `7d759c8a6853b774a2077bd4a070b0188cb1abfd`; Actions run `33763753929`
  passed conversion traceability, all 261 target tests, generated contracts,
  both staging builds and clean tracked artifacts.
- Prepared the provider-free Client archive use-case READY package. Exactly
  `ClientArchiveUseCase.swift` (`SWIFT-7A484C80FD98`) and
  `ClientArchiveUseCaseTests.swift` (`TEST-E10E6D44CC8A`) are comment-only.
  Six authority-bound requirements and eight reciprocal obligations freeze
  exact Account/Client/revision intent, application-owned operation metadata,
  verified archive-command assembly, one post-construction port call, receipt
  validation, structured cancellation, normalized failure preservation and
  bounded raw-error mapping. The first deterministic sync caught and corrected
  an implementation-evidence-as-authority mistake before code or READY
  promotion. Current control state is 821 recorded / 806 discovered, 387
  mapped-or-later / 174 residual / 45 blockers with only the three established
  retired-path warnings. The complete local READY gate passes all 261 target
  tests in 57 suites with warnings as errors, conversion/capability/query/
  residual/M0 and target-isolation/generated-contract controls, JSON validation,
  repeatable Xcode generation at `0657194a` / `388303af`, both staging builds
  and clean diff formatting. Authority review caught one stale baseline/run
  reference; root review clarified that actor/time are separate application
  inputs rather than intent fields. Regenerated checks pass and both read-only
  reviewers return GO on the corrections. That reviewed package became the
  exact READY commit recorded next.
- Exact READY commit `a4bc1daa73f640a42f8b0de50240801619339f95`
  passed immutable Actions run `33765054735` (traceability 7 seconds; isolated
  target 2 minutes 33 seconds), authorizing only the two frozen leaves.
- A bounded writer then changed exactly those two leaves and no other path. The
  implementation defines the exact non-Codable Account/Client/revision intent,
  constructs the existing verified draft/command, invokes `ClientArchiving`
  once only after construction, validates the receipt, preserves every local
  state, structured cancellation and normalized failure, and bounds raw port
  errors. Root inspected every line and independently reran six focused plus all
  267 target tests in 58 suites with warnings as errors; both pass. The complete
  local implementation gate also passes conversion/capability/query/residual/
  M0 and target-isolation/generated-contract controls, repeatable Xcode hashes
  `0657194a` / `388303af`, both staging builds, JSON validation, exact-path
  scope and clean formatting. The first authority-focused review
  found that removing either declared `Equatable` or `Sendable` conformance
  would not fail a test; the added constrained compile-time assertion closes
  that proof gap without changing runtime behavior. Corrected-diff authority
  and adversarial continuity reviews both returned GO with no remaining P0-P3.
  Exact implementation commit
  `a5ba0ae31d7d2547398d4b63be1f0f4bc866148f` passed immutable Actions run
  `33767120461` (traceability 12 seconds; isolated target 3 minutes 3 seconds),
  including all target tests, both staging builds and clean tracked artifacts.
  The dossier and both target surfaces are verified; every exclusion remains
  binding.
- Exact Space-checklist verification-promotion commit
  `ecd0ca9fc2f11c4a4bd02f3687b6ba76209cb649` passed immutable Actions run
  `33789427209` (traceability 9 seconds; isolated target 2 minutes 49 seconds).
  Root and a separate strict-authority preflight then selected the Project
  setup selection-to-application boundary above verified
  ProjectSetupFormSelection/current ProjectSetupFormPreparation and
  ProjectSetupOperating.create contracts. Candidate paths independently hash
  to `SWIFT-EE8576F5CD39` and `TEST-BB8C5679BA31`; both are comment-only READY
  scaffolds with exact hashes recorded in `EVID-PROJECT-SETUP-USE-CASE-001`.
  The frozen boundary derives one verified command before exactly one port
  call, validates and returns its exact receipt, preserves both typed failure
  families plus cancellation, and bounds unknown port errors. Matching
  represented ready, partial and stale evidence remains admissible without a
  new readiness gate; changed evidence fails before dispatch and preparation
  evidence cannot enter the command. The complete local READY gate passes 825
  recorded / 813 automatic-inventory entries (810 currently discovered plus
  three retained missing-source warnings) with no other warning or error,
  391 mapped-or-later / 174 residual / 45 blockers, all 273 existing target
  tests in 59 suites with warnings as errors, repeatable Xcode hashes
  `0657194a` / `388303af`, both staging builds, JSON and clean formatting.
  O-023/O-024/O-025/O-026 and all UI/provider/production exclusions remain
  binding. Two independent actual-diff reviews found and verified corrections
  to a comment-only provider-coupling scanner false positive, optional-
  allocation JSON shape, existing-to-new Client delta wording and inventory-
  count precision; both return GO. Exact READY commit
  `863f6fce14332af0f43aa1a82480e44bc790ca56` passed immutable Actions run
  `33791245215` (traceability 12 seconds; isolated target 3 minutes 20 seconds),
  authorizing only the two frozen implementation leaves.
- A bounded writer changed exactly those two leaves. The implementation derives
  the existing verified CreateProjectCommand before one
  `ProjectSetupOperating.create` call, validates the receipt, preserves every
  local state, both typed failure families and cancellation, and bounds unknown
  port failures. Root inspected every line and independently reran six focused
  plus all 279 target tests in 60 suites with warnings as errors. Initial
  independent review found three P2 proof gaps: nil-description omission,
  same-identity existing-to-new Client discrimination and allocation-order
  equivalence. Corrected tests close all three; both final reviewers return GO
  with no remaining P0-P3. Target isolation/contracts, repeatable Xcode hashes
  `0657194a` / `388303af` and both staging builds pass locally. Exact
  implementation commit `d624c2e0a5c934cfeb8eadbead3f585f51e8942b`
  passed immutable Actions run `33793469069` (traceability 9 seconds; isolated
  target 4 minutes 13 seconds), including all target tests, both staging builds
  and clean tracked artifacts. The dossier and both target leaves are verified;
  NewProjectView, ProjectFormValidation/tests, ProjectService and every provider/
  production exclusion remain unadvanced.
- Verification-promotion commit
  `b0fcd6cbba8c7312fc4f4f8ae3d8c1c74f4a4b47` passed immutable Actions run
  `33768000016` (traceability 8 seconds; isolated target 2 minutes 57 seconds),
  freezing the Client archive use case.
- A bounded strict-authority scout ranked provider-free Space checklist revision
  submission first. Root independently confirmed `spaces.md` target authority,
  the verified Space core-details/editing-presentation/revision-operation chain,
  and that O-023/O-026/O-032/O-037 media/template/completion/archive questions
  do not govern this excluded scope. Two deterministic surface IDs resolve to comment-
  only `SpaceChecklistRevisionUseCase.swift` (`SWIFT-1FDB27E18B95`) and
  `SpaceChecklistRevisionUseCaseTests.swift` (`TEST-674E6F23E5BE`). The READY
  dossier freezes exact draft/current semantic revalidation, one verified command,
  one post-derivation port call, receipt validation, typed failure/cancellation
  preservation and permanent provider/production exclusions. The READY
  checkpoint control state was 823 recorded / 808 discovered, 389 mapped-or-later / 174 residual /
  45 blockers with only the three established retired-path warnings. The
  complete local READY gate passed all 267 existing target tests in 58 suites
  with warnings as errors, conversion/target controls, repeatable Xcode hashes
  `0657194a` / `388303af`, both staging builds, JSON and clean formatting. One
  reviewer found missing explicit proof for both admissible readiness paths;
  the corrected plan closed it and both independent reviewers returned GO.
  Exact READY commit `6534da3361b3b52b3713ac558799a1a70ab00f26`
  passed immutable Actions run `33785649411` (traceability 15 seconds; isolated
  target 3 minutes 48 seconds), authorizing only the two frozen leaves.
- A bounded writer then changed exactly those two leaves and no other path. The
  implementation reuses `SpaceChecklistEditingDraft.command`, derives before
  one `SpaceChecklistRevising` call, validates the receipt, preserves every
  local state plus both typed failure families and cancellation, and bounds raw
  errors. Root inspected every line and independently reran six focused plus
  all 273 target tests in 59 suites with warnings as errors. Repeatable Xcode
  hashes `0657194a` / `388303af` and both staging builds pass. Initial reviewers
  found only test-proof gaps: scope/lifecycle transparency, both revision
  boundaries on both readiness paths, long UTF-8 values and exact reciprocal
  field isolation. Corrected tests cover active/archived Project and Business
  Inventory evidence, more than 8 KB Unicode values, zero/maximum revision on
  both readiness paths and complete encoded leaf-delta sets. Both final reviews
  return GO with no remaining P0-P3. Complete local conversion/target controls,
  JSON, exact-path and formatting checks pass. Exact implementation commit
  `99574328837ff1dfd8924f2eda2e88a635ad5ba7` passed immutable Actions run
  `33788214259` (traceability 10 seconds; isolated target 3 minutes 4 seconds),
  including all target tests, both staging builds and clean tracked artifacts.
  The dossier and both target surfaces are verified; every exclusion remains
  binding.

- Exact Project-setup verification-promotion commit
  `0a8cc53a909951c31fc8be6377e2e5f62b93e87c` passed immutable Actions run
  `33794464360`, freezing that slice. Root and two read-only preflights then
  selected only the canonical description set/clear application boundary above
  verified `ProjectDetailsUpdateOperation.swift`; the older broad Edit Project
  surface is not target authority for this slice. Candidate paths independently
  resolve to `ProjectDetailsUpdateUseCase.swift` (`SWIFT-B95AD78B8CEC`) and
  `ProjectDetailsUpdateUseCaseTests.swift` (`TEST-315066B94566`). Both are
  comment-only. The `ready` dossier freezes a transient exact Account/
  Project/revision/raw-description input, canonical replacement/draft/command
  construction before one port call, receipt validation after it, all 13 typed
  failures, cancellation and bounded unknown errors. Ten tests remain planned.
  EditProjectModal, ProjectService/Protocol, Project model and update_project
  MCP tool retain their prior statuses; all read/readiness/lifecycle/no-op/UI,
  broader mutation, physical persistence, authorization, provider/schema/RLS/
  Sync, app/MCP, migration, hosted and production behavior remains excluded.
  The corrected local READY gate passes 827/812 conversion inventory, 393/174/
  45 residual control, M0, target isolation/contracts, all 279 target tests in
  60 suites with warnings as errors, repeatable generation at `0657194a` /
  `388303af`, both staging builds, JSON and formatting checks. Independent
  reviews caught and corrected a missing public initializer plus `@testable`
  masking (P1), comment-only lifecycle overstatement (P2), and stale gate
  evidence (P3); both corrected-diff reviewers return GO.
  Exact READY commit `22c6cc01d499ce024e1a4c4157bc3c5e5d5a680e`
  then passed immutable run `33797480692` (traceability 8 seconds; isolated
  target 3 minutes 36 seconds). Exactly the two frozen leaves now implement the
  public transient input and application path. Seven focused/all 286 target
  tests in 61 suites, target controls, repeatable generation and both builds
  pass locally. Independent implementation review caught and corrected missing
  revision-zero dispatch proof; both final reviewers returned GO. Conversion
  synchronization and complete controls passed after the implementation-hash
  update. Exact implementation commit
  `55baae9d47a40b14bd05418ca2bbf9cc2c11d480` passed immutable Actions run
  `33799751617` (traceability 15 seconds; isolated target 2 minutes 38 seconds),
  including all target tests, both staging builds and clean tracked artifacts.
  The dossier and both target leaves are verified.

- Exact Project-rename-use-case verification-promotion commit
  `2fa5a536d4b4b8b490da4c7fea2691b53aaf9d1a` freezes implementation commit
  `9c8e27cfb26252f6d068841a822be578412c82e6` / immutable Actions run
  `33816585123`. A feature-specific authority audit then selected only the typed
  Client display-name replacement application boundary above verified
  `ClientRenameOperation.swift`; standalone Client creation, note creation,
  lifecycle/correction and provider work remain outside. Exact READY commit
  `9cc34f4ca6004e7c3b3e1816f07112c55a70fe54` passed immutable Actions run
  `33819792298`, authorizing executable work in exactly
  `ClientRenameUseCase.swift` (`SWIFT-2F4458F40735`) and
  `ClientRenameUseCaseTests.swift` (`TEST-341B2CD23B6A`). Those leaves now
  implement the public non-Codable Account/Client/revision/`ClientDisplayName`
  intent and one-call application boundary. Eight focused/all 302 tests in 63
  suites, complete local controls, repeatable generation and both builds pass.
  Two independent implementation reviewers return GO after one caught and the
  implementation corrected missing explicit UTF-8 byte-equality proof for the
  large Unicode payload. `CRENAMEUSE-TEST-001` through `-009` pass locally;
  exact implementation commit `0f000b8e491019a9307c46437312b7ae0f5711dc` /
  immutable run `33821354656` passes and satisfies `-010`, promoting the dossier
  and both leaves to verified. Client reads/
  readiness/lifecycle/no-op/UI, Project reassignment/projection, frozen-history
  rewrite, broader mutation, physical persistence, authorization, provider/
  schema/RLS/Sync, app/MCP, migration, hosted and production behavior remain
  excluded.

## Next Action

Complete an independent actual-diff review of the READY Space core-details
package, correct every finding, run the complete local READY gate, then commit,
push and require immutable exact-head CI. Only after that exact READY commit is
green, implement the frozen eight leaves and shared touchpoints as one bounded
read workflow, review the executable SQL/RLS/Sync and offline/app diffs
independently, and pass complete local plus immutable exact-commit gates.

The Space core-details boundary must keep the existing active-only destination
RLS policy and streams unchanged, model checklists relationally, derive counts
only from complete evidence and add no Data API detail surface or writer. The
Project archival-review slice remains `implemented`, not `verified`, until
`PROJECTARCHIVALREVIEW-TEST-011` proves real authenticated PowerSync receipt and
membership-revocation eviction. Do not implement note creation/edit/delete/
search under O-039, broad Project MCP behavior under O-040, restore/delete/
reassignment/media choices, or weaken the blocked direct Space-create dossier
under O-044/O-045/O-046. Do not infer real PowerSync/Auth authorization from
local proof, advance A-003/A-004, provision hosted resources, access
production, migrate source data or modify Firebase.

Continue without waiting on the two M1 evidence blockers:

1. Treat `operation-lifecycle-and-readiness` and
   `EVID-OPERATION-CORE-001` as the shared semantic dependency for every later
   operation slice. Do not recreate queued/applied/rejected, idempotency,
   readiness or error behavior independently in app, MCP, SQL or adapters.
2. Treat `transaction-taxonomy-and-transfer-identity` and
   `EVID-TRANSACTION-TAXONOMY-001` as the sole shared semantic source for later
   Transaction classification, scope, route and pair identity. Do not recreate
   or extend that meaning independently in app, MCP, SQL or adapters.
3. Treat `non-item-receipt-line-reconstruction-contracts` and
   `EVID-RECEIPT-RECONSTRUCTION-001` as the sole shared semantic source for
   embedded receipt lines and exact reconstruction evidence. Do not recreate
   or extend that meaning independently in app, MCP, SQL or adapters. Treat the
   verified `project-item-accounting-section-contracts` and
   `EVID-PROJECT-ITEM-ACCOUNTING-001` as the sole shared read semantics for
   relationship-derived Project Item sections. Treat the verified
   `attachment-capture-and-local-durability-receipt` dossier and
   `EVID-ATTACHMENT-CAPTURE-001` as the sole shared semantic source for stable
   capture identity, exact local-byte evidence and success-shaped receipts.
   Treat the verified `client-creation-operation-contracts` dossier and
   `EVID-CLIENT-CREATION-001` as the sole Client-create semantic authority.
   Treat the verified `project-setup-operation-contracts` dossier and
   `EVID-PROJECT-SETUP-001` as the sole CreateProject semantic authority for
   existing/new Client selection and complete absent/null/zero category intent.
   Treat the verified `project-archive-operation-contracts` dossier and
   `EVID-PROJECT-ARCHIVE-001` as the sole ArchiveProject semantic authority.
   Treat the verified `budget-category-reference-read-contracts` dossier and
   `EVID-BUDGET-CATEGORY-REFERENCE-001` as the sole shared read semantics for
   category identity/kind/lifecycle/system/exclusion/order/revision,
   eligibility, visible-count privacy and local readiness. Treat the verified
   `project-category-configuration-read-contracts` dossier and
   `EVID-PROJECT-CATEGORY-CONFIGURATION-001` as the sole shared read semantics
   for exact Account/Project/category configuration state, absent/null/zero/
   positive allocation, incomplete relationship evidence and configuration
   revision. Treat the verified `client-rename-operation-contracts` dossier and
   `EVID-CLIENT-RENAME-001` as the sole RenameClient semantic authority.
   Treat the verified `project-rename-operation-contracts` dossier and
   `EVID-PROJECT-RENAME-001` as the sole RenameProject semantic authority.
   Treat the verified `project-note-read-contracts` dossier and
   `EVID-PROJECT-NOTE-READ-001` as the sole shared read semantics for stable
   Project-note identity, audit/tombstone evidence, deterministic bounded order
   and explicit offline-history completeness. Treat the verified
   `project-note-creation-operation-contracts` dossier and
   `EVID-PROJECT-NOTE-CREATION-001` as the lower-level typed AddProjectNote
   identity/envelope/representation authority only. It does not decide shared
   app/MCP create/edit normalization, controls, maximum size or minimum; O-039
   owns that unresolved product policy. Treat the verified
   `project-preference-read-contracts` dossier and
   `EVID-PROJECT-PREFERENCE-READ-001` only as a provider-free current-Principal
   Project preference-shaped read primitive. Treat the verified
   `project-preference-update-operation-contracts` dossier and
   `EVID-PROJECT-PREFERENCE-UPDATE-001` only as a provider-free ordered
   replacement/concurrency primitive. Neither is canonical approval that target
   Project budget pins exist. Do not create a preference application use case or
   advance any source/app/MCP/provider surface until O-040 independently resolves
   pin existence, migration survival, no-pin/default, Project-detail fallback,
   Project-card fallback and whether any fallback performs a write. Treat the
   verified `vendor-suggestion-reference-read-contracts`
   dossier and `EVID-VENDOR-SUGGESTION-REFERENCE-001` as the sole vendor-
   suggestion read semantics. Treat the verified
   `space-template-reference-read-contracts` dossier and
   `EVID-SPACE-TEMPLATE-REFERENCE-001` as the sole Space-template read semantics.
   Treat the verified `client-archive-operation-contracts` dossier and
   `EVID-CLIENT-ARCHIVE-001` as the sole ArchiveClient semantic authority.
   Treat the verified `project-details-update-operation-contracts` dossier and
   `EVID-PROJECT-DETAILS-UPDATE-001` as the sole UpdateProjectDetails semantic
   authority. Treat `space-creation-operation-contracts` and
   `EVID-SPACE-CREATION-001` as the sole direct provider-free CreateSpace
   semantic authority. Treat `space-details-update-operation-contracts` and
   `EVID-SPACE-DETAILS-UPDATE-001` as the sole provider-free
   UpdateSpaceDetails semantic authority. The exact implementation commit and
   both CI jobs are verified. Treat
   `space-checklist-revision-operation-contracts` and
   `EVID-SPACE-CHECKLIST-REVISION-001` as the sole provider-free
   ReviseSpaceChecklists semantic authority. Its exact implementation commit and
   both CI jobs are verified. Treat the verified
   `session-ending-pending-work-contracts` dossier and
   `EVID-SESSION-ENDING-POLICY-001` as the sole provider-free safety authority
   for exact pending-work summaries and clean/sync-first/destructive session
   dispositions. Its exact implementation commit and both CI jobs are
   verified. Treat the verified `account-discovery-and-selection-contracts`
   dossier and `EVID-ACCOUNT-DISCOVERY-SELECTION-001` as the sole authority for
   the bounded provider-free discovery/selection-intent boundary. Its exact
   implementation commit and both CI jobs are verified. Treat the verified
   `item-space-assignment-operation-contracts` dossier and
   `EVID-ITEM-SPACE-ASSIGNMENT-001` as the sole authority for the bounded
   provider-free AssignItemsToSpace boundary. Its exact implementation commit
   and both CI jobs are verified. Treat the verified
   `item-space-clearing-operation-contracts` dossier and
   `EVID-ITEM-SPACE-CLEARING-001` as the sole authority for explicit
   Item-placement clearing. Its exact implementation commit and both CI jobs
   are verified. Treat verified `item-space-clearing-use-case-contracts` and
   `EVID-ITEM-SPACE-CLEARING-USE-CASE-001` as the sole provider-free typed
   intent-to-clearing application authority. Its synchronized implemented
   checkpoint and complete immutable workflow are verified. Preserve the two
   verified leaves `ItemSpaceClearingUseCase.swift` (`SWIFT-EEAC86485FF6`) and
   `ItemSpaceClearingUseCaseTests.swift` (`TEST-CA84B398990C`) as dependencies
   for subsequent slices. They bind exact typed Account/scope/Item/revision/
   current-Space conflict evidence through the verified draft and command before
   exactly one clearer call, validate afterward, preserve all 15 operation
   failures plus cancellation and bound only unknown port errors. They do not
   treat scope/current-Space input as authoritative truth: stale assigned-looking
   evidence may dispatch and later conflict. Nil/no-current-Space intent is
   structurally unrepresentable, empty selection rejects, and no synthetic no-op
   receipt exists. Preserve every dependency, sibling and exact clear-space
   source ID/status enumerated in the dossier. Do not introduce mixed
   assigned/unassigned admission/filtering,
   read/UI eligibility, archive, attachment reference/byte deletion, marker
   mutation, destination assignment, scope movement, accounting/provenance,
   persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration,
   hosted or production behavior. Treat the verified `space-assignment-destination-read-contracts`
   dossier and
   `EVID-SPACE-ASSIGNMENT-DESTINATION-001` as the sole verified provider-free
   assignment-destination read semantics. Treat the verified
   `item-space-assignment-use-case-contracts` and
   `EVID-ITEM-SPACE-ASSIGNMENT-USE-CASE-001` as the sole provider-free
   local-destination-to-assignment application authority. Its exact
   implementation commit and both CI jobs are verified. Preserve exactly
   the two verified leaves `ItemSpaceAssignmentUseCase.swift`
   (`SWIFT-0540BE125F5A`) and `ItemSpaceAssignmentUseCaseTests.swift`
   (`TEST-DA67EAC9C2EF`) as dependencies for subsequent slices. The implementation
   validates the intent against the current directory Account/scope, resolves the
   destination only by represented stable ID, derives its expected revision from
   that row, constructs the verified command before exactly one assigner call,
   validates afterward, preserves pre-port application failures, port operation
   failures and cancellation, and bounds every other port error. Ready, partial
   and stale represented rows
   remain admissible; a missing row is not represented and never proves
   authoritative nonexistence. Do not introduce clearing/no-op, Item-selection
   UI/read, archive, media/marker, scope movement, accounting/provenance,
   persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration,
   hosted or production behavior. Treat the verified
   `project-budget-segment-read-contracts` dossier and
   `EVID-PROJECT-BUDGET-SEGMENT-001` as the sole provider-free source for exact
   Project category client-paid/invoicing-unpaid segments and their internally
   derived recognized value. Preserve both completed enhanced-pilot review
   records. Do not implement Inventory destination planning until O-038 is
   explicitly approved in canonical product authority. Both enhanced pilots
   passed; retain the conductor, isolated-worktree, frozen-slice, path-allowlist,
   independent review and exact-integration-SHA CI controls, and apply review
   depth according to novelty and accounting/security risk without allowing a
   worker to promote its own status or edit canonical integration controls.
   Treat the verified `project-item-accounting-section-contracts` resolution as
   the sole input authority for the verified
   `project-item-link-presentation-contracts` leaf as the sole target
   presentation authority for exact section/action/question/payer vocabulary,
   authoritative Unaccounted-only Link availability and no-action dismissal.
   Keep
   actual Link routes/commands, Purchase choice/eligibility, acquisition
   handling, correction/relink behavior, transient UI state, Accounted-item
   actions, app/MCP and provider/migration behavior outside this slice.
   Treat verified `space-core-details-read-contracts` and
   `EVID-SPACE-CORE-DETAILS-001` as the sole provider-free single-Space core
   detail read authority. Preserve the completed every-line and independent
   adversarial reviews, their four corrected findings and exact integration
   run `33695588031`. Do not let later slices recreate or extend timestamp provenance,
   authoritative partial counts, percentage policy, archive effects,
   Item/media/review/template/accounting, provider/schema/RLS/Sync, app/MCP,
   migration or production behavior.
   Treat verified `project-core-details-read-contracts` and
   `EVID-PROJECT-CORE-DETAILS-001` as the sole provider-free single-Project core
   read authority. Preserve the four corrected test-exhaustiveness findings and
   exact integration run `33698741756`; do not let later slices promote local
   revision to server-current authority or acquire workspace children, media,
   accounting, mutation, authorization, provider, schema/RLS/Sync, app/MCP,
   migration or production behavior. Treat verified
   `client-core-details-read-contracts` and
   `EVID-CLIENT-CORE-DETAILS-001` as the sole provider-free single-Client core
   read authority. Exact integration checkpoint `6cea8459` and immutable run
   `33702499992` satisfy the verification gate after corrected primary and
   independent adversarial review. Preserve the verified
   ClientSummary, locally observed Client revision and shared offline-readiness
   semantics. Preserve valid Client display text byte-for-byte, accept
   separately valid later name/time/lifecycle/revision snapshots, and do not
   let the slice become a Client workspace/CRM model or acquire Projects/counts,
   Transfer eligibility, media, accounting, history, mutation, authorization,
   provider, schema/RLS/Sync, app/MCP, migration or production behavior.
   Treat verified `project-existing-client-selection-read-contracts` and
   `EVID-PROJECT-EXISTING-CLIENT-SELECTION-001` as the frozen worker boundary.
   Preserve its pure projection over the existing directory port, absence of
   any selected/default value or final UI preselection policy, explicit active
   ClientID-to-`.existing` conversion, exact upstream order and content-bound
   evidence fingerprint including source-directory row count and visible count.
   Never claim `noActiveClient` unless ready, complete and source-exhaustive;
   non-exhaustive no-active evidence remains `directoryIncomplete`. Exact ready commit `e6d80563`
   passed immutable run `33704608811`. Corrected candidate `d206f542` changed
   only the two registered paths; primary every-line and independent
   adversarial review found no remaining P0-P3 issue after the reviews caught
   four direct-test gaps and the P1 false-authoritative-empty defect. All seven
   focused tests and root/worker full 218-test runs pass. The complete central
   integration gate also passes. Exact checkpoint `9ff65407` passed immutable
   run `33707305340`; preserve this boundary as verified.
   General Space lists
   remain rejected until filtering, ordering, search, count and archive
   semantics have product authority. Treat verified
   `transaction-type-choice-presentation-contracts` and
   `EVID-TRANSACTION-TYPE-CHOICE-PRESENTATION-001` as a frozen
   boundary. Preserve literal unordered Project purchase/return/transfer and
   Inventory purchase/return membership, exact Client/1584 owner vocabulary,
   existing economic meanings and source/destination Transfer equivalence.
   Do not recreate classification, invent menu/filter order, classify legacy
   records or acquire amount/status/action, app/MCP, provider/schema/RLS/Sync,
   migration or production behavior. Final candidate `c22fac22` changed only
   the two registered paths; primary and independent review found no code P0-P3
   issue after one P3 malformed-JSON test gap and one P3 evidence overclaim were
   corrected. Preserve the exact raw `DecodingError` versus test-consumer
   normalization distinction. Exact checkpoint `fcff5b85` passed immutable
   Actions run `33717396519` with all 224 tests, conversion/target controls,
   repeatable project generation and both staging builds; preserve the verified
   boundary.
   Treat verified `project-browsing-presentation-contracts` and
   `EVID-PROJECT-BROWSING-PRESENTATION-001` as the frozen presentation boundary.
   Preserve exact upstream order, Project-only active/archived segmentation,
   active-Project/archived-Client visibility, ready-complete-source-exhaustive
   absence, every-field evidence binding and selection-to-exact-detail-request
   composition. Request derivation must validate the current presentation
   snapshot and reject changed evidence first. Detail headers must preserve
   waiting, found ready/partial/stale,
   authoritative absence, unavailable and cached/no-cache retryable/required-
   update truth. Do not add a query port, sort/search, full Project card, tabs/
   children, navigation/route, mutation, authorization, persistence, app/MCP,
   provider/schema/RLS/Sync, migration or production behavior. Complete the
   exact ready-SHA CI, full local ready gate and independent actual-diff
   correction review are recorded as passing. Corrected candidate `73f94525`
   changed only the four registered leaf paths and passed primary every-line,
   independent adversarial and complete local integration gates. Exact
   checkpoint `717a0eb8` passed both CI jobs in immutable Actions run
   `33723154735`; preserve the verified boundary. Remove the clean isolated
   worker worktree after the synchronized verification-promotion checkpoint
   passes CI, retain its reviewed branch, record cleanup, and select the next
   coherent decision-independent slice through feature-specific product-
   authority preflight.
   Treat verified `project-setup-form-presentation-contracts` and
   `EVID-PROJECT-SETUP-FORM-PRESENTATION-001` as the sole provider-free form
   preparation boundary. Preserve exact Account scope, verified active-Client
   upstream order, category presentation order, independent readiness,
   explicit existing/preallocated-new Client identity, zero-category validity,
   exact nullable allocations, ProjectDescriptionReplacement normalization and
   current-evidence validation before the verified CreateProjectCommand exists.
   Do not duplicate or extend it in UI, providers or later operation slices.
   Treat verified `space-checklist-editing-presentation-contracts` and
   `EVID-SPACE-CHECKLIST-EDITING-PRESENTATION-001` as the next frozen boundary.
   The corrected ready package, exact ready-SHA CI and assignment-control CI
   pass. The reviewed implementation projects only ready-complete current or
   retryable-ready-complete cached Space
   evidence, retain raw blank intermediate text, preserve exact stable nested
   IDs/order tokens, edit checklist fields plus items only within their owning
   checklist, and derive the verified complete-replacement command after
   semantic-base validation that tolerates harmless refresh metadata. It must
   not add checklist reorder, cross-checklist movement, archived-action policy
   or any excluded provider/app behavior. Primary and independent every-line
   review, the complete local integration gate, exact integration-SHA CI and
   promotion-checkpoint CI pass after two candidate corrections. The clean
   temporary worktree is removed and its reviewed branch is retained. Preserve
   this contract when selecting the next coherent decision-independent slice.
   Treat verified `direct-space-creation-use-case-contracts` and
   `EVID-DIRECT-SPACE-CREATION-USE-CASE-001` as the sole provider-free direct-
   Space form-to-operation use-case boundary. It changes only
   `DirectSpaceCreationUseCase.swift` and its target tests.
   Preserve caller-supplied transient raw input, canonical name/notes conversion,
   application-owned operation metadata/command assembly, exactly one post-
   validation `SpaceCreating` call, receipt validation, Swift structured-
   concurrency cancellation and bounded transport-error mapping. Do not add
   initial-form defaults, form-cancel UX policy, form fingerprints/codecs,
   uniqueness queries, templates, SwiftUI, physical persistence, optimistic
   rows, authorization, provider/schema/RLS/Sync, app/MCP, migration or
   production behavior. Corrected implementation, two independent final
   reviews, the complete local gate and exact implementation commit
   `c35f1cef` / immutable run `33746648677` pass. Preserve this boundary and
   retain promotion commit `880727f7` / run `33747118216`. Treat verified
   `space-details-update-use-case-contracts` and
   `EVID-SPACE-DETAILS-UPDATE-USE-CASE-001` as the frozen provider-free Space-
   details submission boundary. It changes only `SpaceDetailsUpdateUseCase.swift` and its target tests and
   may replace only save-intent normalization/dispatch from the current modal;
   keep the full source surface target_mapped. Do not consume Space-core read/
   readiness updates, choose active/archive eligibility, or add initial state,
   dirty/no-op/cancel/dismissal/UI/form-restart behavior. Exact ready commit
   `b6a98ca0` / run `33749431949`, the corrected implementation, two independent
   final reviews, the complete local integration gate and exact implementation
   commit `f0d7c3fa` / immutable run `33750834849` pass. Preserve the verified
   boundary and keep the full source modal target_mapped. Treat verified
   `project-archive-use-case-contracts` and
   `EVID-PROJECT-ARCHIVE-USE-CASE-001` as the frozen archive application
   boundary. Exact ready commit `bf429472` / run `33755885978` and exact
   implementation commit `232acf92` / run `33758116150` pass. The implementation
   changes exactly `ProjectArchiveUseCase.swift` and
   `ProjectArchiveUseCaseTests.swift`; two independent final reviews, six focused
   and all 261 target tests, the complete local gate, repeatable generation and
   both staging builds pass. ProjectDetailView must remain characterized,
   `MCPTOOL-921DA05B3330` must remain target_mapped, and no excluded restore/
   lifecycle/UI/MCP/provider behavior may advance.
   Do not recreate the rejected Project-note use-case scaffolds or mark that
   product slice ready until O-039 is approved and canonical target note
   requirements record the chosen app/MCP normalization/minimum behavior.
   Treat verified `client-archive-use-case-contracts` and
   `EVID-CLIENT-ARCHIVE-USE-CASE-001` as the frozen selected-Client archive
   application boundary. Exact READY commit `a4bc1daa` / run `33765054735` and
   exact implementation commit `a5ba0ae3` / immutable run `33767120461` pass.
   Preserve exactly `ClientArchiveUseCase.swift` (`SWIFT-7A484C80FD98`) and
   `ClientArchiveUseCaseTests.swift` (`TEST-E10E6D44CC8A`) as the verified
   executable leaves. The frozen boundary remains exact
   AccountID/ClientID/ExpectedClientRevision intent, existing
   `ClientArchiveDraft`/`ArchiveClientCommand` assembly, one
   `ClientArchiving.archive` call after construction, receipt validation,
   structured cancellation, normalized failure preservation and bounded raw
   errors. Do not inspect Client rows, Project counts, history, lifecycle,
   readiness or permissions; do not add UI, optimistic projection, persistence,
   authorization, restore/delete/merge/rename/reassignment/cascade, provider,
   schema/RLS/Sync, app/MCP, migration, hosted or production behavior.
   Treat verified `space-checklist-revision-use-case-contracts` and
   `EVID-SPACE-CHECKLIST-REVISION-USE-CASE-001` as the frozen Space checklist
   application boundary. Exact READY commit `6534da33` / run `33785649411` and
   exact implementation commit `99574328` / immutable run `33788214259` pass.
   Preserve exactly the two
   executable leaves `SpaceChecklistRevisionUseCase.swift`
   (`SWIFT-1FDB27E18B95`) and `SpaceChecklistRevisionUseCaseTests.swift`
   (`TEST-674E6F23E5BE`) as verified. The frozen application path
   reuses existing SpaceChecklistEditingDraft/current SpaceCoreDetailsUpdate,
   derives one verified command before one port call, validates the receipt,
   preserves typed failures/cancellation and bounds raw errors. EditChecklistModal,
   UI/read admission, physical persistence, authorization, provider/schema/RLS/
   Sync, app/MCP, migration, hosted and production behavior must remain unchanged.
   Treat verified `project-setup-use-case-contracts` and
   `EVID-PROJECT-SETUP-USE-CASE-001` as the current frozen boundary. Exact READY
   commit `863f6fce` / run `33791245215` passed. The corrected implementation
   changes exactly `ProjectSetupUseCase.swift` (`SWIFT-EE8576F5CD39`) and
   `ProjectSetupUseCaseTests.swift` (`TEST-BB8C5679BA31`), composes the verified
   `ProjectSetupFormSelection` / current `ProjectSetupFormPreparation` with
   `ProjectSetupOperating.create`, and has two independent final GO reviews.
   Six focused/all 279 target tests, local target controls, repeatable generation
   and both staging builds pass. Exact implementation commit `d624c2e0` and
   immutable run `33793469069` pass; preserve the dossier and both leaves as
   verified. Preserve NewProjectView, ProjectFormValidation/current validation and
   ProjectService at their existing statuses; O-023/O-024/O-025/O-026 and UI/
   defaults/category mutation, physical persistence, authorization, provider/
   schema/RLS/Sync, app/MCP, migration, hosted and production behavior remain
   outside.
   Treat verified `project-details-update-use-case-contracts` and
   `EVID-PROJECT-DETAILS-UPDATE-USE-CASE-001` as the current frozen boundary. Preserve
   exactly the two implemented leaves `ProjectDetailsUpdateUseCase.swift`
   (`SWIFT-B95AD78B8CEC`) and `ProjectDetailsUpdateUseCaseTests.swift`
   (`TEST-315066B94566`). Exact implementation commit `55baae9d` and immutable
   run `33799751617` pass; preserve the dossier and both leaves as verified. Keep
   EditProjectModal, ProjectService/Protocol, Project model and update_project
   MCP tool at their prior statuses; do not add read/readiness/lifecycle/no-op/
   UI, broader mutation, persistence, authorization, provider/schema/RLS/Sync,
   app/MCP, migration, hosted or production behavior.
   Treat verified `project-rename-use-case-contracts` and
   `EVID-PROJECT-RENAME-USE-CASE-001` as the frozen application boundary.
   Preserve exact leaves `ProjectRenameUseCase.swift`
   (`SWIFT-5A812E7B8C95`) and `ProjectRenameUseCaseTests.swift`
   (`TEST-E1BAA8DF70B4`). Exact implementation commit `9c8e27cf` / immutable
   run `33816585123` passed, and both independent implementation reviewers
   returned GO. The boundary consumes an
   already-validated `ProjectDisplayName`; do not introduce raw String
   normalization, UI/no-op/read/readiness/lifecycle policy, broader mutation,
   persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration,
   hosted or production behavior. Preserve the verified rename operation/tests
   and directory dependency plus all named source statuses, including
   ProjectDetailView and ProjectDetailContainer.
   Treat verified `client-rename-use-case-contracts` and
   `EVID-CLIENT-RENAME-USE-CASE-001` as the frozen application boundary.
   Preserve exactly the two executable leaves `ClientRenameUseCase.swift`
   (`SWIFT-2F4458F40735`) and `ClientRenameUseCaseTests.swift`
   (`TEST-341B2CD23B6A`). Exact implementation commit `0f000b8e` / immutable
   run `33821354656` passed, and both independent implementation reviewers
   returned GO. The boundary consumes an already-validated `ClientDisplayName`,
   constructs the verified draft and command before exactly one
   `ClientRenaming.rename` call, validates the receipt afterward, preserves
   every typed failure plus cancellation and bounds only unknown port errors.
   Do not introduce raw String normalization, Client read/readiness/lifecycle/
   no-op/UI policy, Client archive/delete/merge, Project reassignment/current
   projection, frozen-history rewrite, persistence, authorization, provider/
   schema/RLS/Sync, app/MCP, migration, hosted or production behavior.
   Do not resurrect the rejected direct-create form draft or removed phantom IDs.
   Keep
   first-use defaults,
   category visibility resolution, authentication, physical persistence,
   authoritative parent preflight/audit assignment, note edit/remove/role
   policy, schema/RLS/Sync/Auth/provider behavior, app/MCP/search, migration,
   hosted resources and production access excluded unless their named gates
   are resolved.
4. Do not enter hosted/provider-specific Phase 2, identity/Auth, encrypted
   local persistence, media retention, or product-command work while its named
   A-/O-/credential/spend gates remain open.
5. Keep `target-environment-isolation` in progress with successful external CI
   recorded. Complete only the later signed/visual/physical staging and actual
   hosted-resource projection portions when their credentials/resources and
   authorization exist; do not wait on those gates before continuing other
   decision-independent target foundations and do not reattach target files to
   `LedgeriOS.xcodeproj`.
6. Keep the target projection explicitly `unprovisioned` until isolated hosted
   resource IDs, staging-only credentials, maximum spend/run-rate, cleanup
   owner, and the applicable spike authorization are explicit. Do not replace
   synthetic IDs with guesses or production identifiers.
7. Preserve the decision-packet queue as proposals until product approval. Every
   generated product blocker now has a packet; O-021 remains an explicit UI-only
   UX experiment rather than a schema gate.
8. Do not execute the prepared vertical-spike protocol until isolated hosted
   resources, staging-only credentials, maximum spend/run-rate, cleanup owner,
   device matrix, and pre-measurement hard caps are explicitly authorized. When
   authorized, begin at S0 and stop fail-closed on any unknown/production ID.
9. When the user approves a product decision, update its canonical spec and
   decision log first, then traceability, architecture, affected batch mappings/
   evidence and this state. Keep one target operation/query authority across app
   and MCP and do not create a Firebase application adapter.
10. Keep A-003/A-004 proposed until the isolated vertical spike passes. The spike
   may use synthetic staging only and must prove encrypted local durability,
   scoped Sync Streams, idempotent operations/rejection, media restart, RLS, and
   offline provenance before provider-specific architecture is approved.
11. When an external chmod-600 service-account JSON whose `project_id` is exactly
   `ledger-nine4`, or a separately proven canonical immutable production export,
   becomes available, run the fail-closed read-only profiling/reconciliation
   flow. Do not copy credentials into the repository, substitute authorized-user
   ADC, or treat emulator exports as production evidence without provenance.

M1 correctly remains blocked by `MAN-DATA-001` and `MAN-CUTOVER-001`. This does
not authorize target implementation and does not prevent honest bounded M2
mapping for ready capabilities.

## Active Blockers and Gates

- O-002 through O-043 remain product blockers where referenced by the decision
  traceability table.
- A-003 and A-004 remain proposed until the vertical spike passes.
- A-007 target authentication choice is open.
- A-015 optimistic complex-operation projection is blocked on the spike.
- A-016 offline authorization lease needs product/security approval.
- O-022 source freeze and rejected-write recovery is unresolved.
- Production data/Auth/Storage shape is statically cataloged but not confirmed
  by a canonical read-only profile/export.
- `MAN-INDEX-001` is statically characterized; deployed index/runtime evidence
  is still open.
- Production profiling is blocked on an external chmod-600 service-account JSON
  for `ledger-nine4`; the configured authorized-user ADC is deliberately not
  accepted by the profiler.
- Identity provider/correlation remains blocked on A-007; offline authorization
  lease/unlock remains blocked on A-016 and product/security approval.
- Attachment reference removal versus permanent byte deletion, shared-reference
  retention and financial/history evidence handling remain blocked on O-023.
- Project deletion, Client reassignment/merge and reference-data mutation
  authority remain blocked on O-024–O-026.
- Unified Item minimum identifying evidence remains blocked on O-027.
- Non-cash vendor credit, Transaction void/delete, receipt rounding/Item tax
  basis and canonical Transaction draft/posting remain blocked on O-028–O-032.
- Actual collection-payment variance and sent-Invoice membership/revision/
  delivery audit remain blocked on O-033/O-034. The safe provisional target
  rejects amount mismatches and does not expose sent-membership mutation.
- Client Summary financial meaning and client-shared receipt delivery remain
  blocked on O-035/O-036; report code cannot choose a metric or expose raw/
  expiring private-object URLs.
- Space archive effects on assigned Items remain blocked on O-037; the safe
  provisional behavior retains a resolvable archived placement and requires an
  explicit move/clear.

## Resume Commands

```bash
node scripts/supabase-conversion-ledger.mjs check
git status --short
node scripts/supabase-conversion-ledger.mjs report
npm run conversion:gate:m0
npm run conversion:gate:m1
npm run target:environment:check
npm run target:environment:test
npm run target:staging:build:macos
npm run target:staging:build:ios
```

If `check` reports new or missing surfaces, resolve discovery drift before
continuing implementation. If the user supplies a newer product decision, update
the decision log first, then traceability, manifest entries, and execution state.

## Last Verification

Verified 2026-08-31 at source baseline
`d83c64724fe4e92be27c62f425979bd30fcfc9bb` in the pre-existing dirty shared
worktree:

- `node --check scripts/supabase-conversion-ledger.mjs` — pass;
- `npm run conversion:sync` — 679 recorded / 667 automatic / 12 manual, zero
  errors and zero warnings;
- `npm run conversion:check` — pass;
- `npm run conversion:report` — pass;
- check invoked from `/tmp` by absolute script path — pass;
- M0 gate — correctly blocked by 677 unclassified surfaces; and
- cumulative M2 gate — correctly blocked by 678 prerequisite/target surfaces.

Backend characterization checkpoint verified later on 2026-08-31:

- four classification batches synchronized — 79 surfaces;
- 679 recorded / 667 automatic / 12 manual surfaces;
- 598 unclassified surfaces remain;
- 77 surfaces are characterized, three are blocked, and the control surface is
  verified;
- zero missing sources, structural errors, or warnings;
- M0 correctly blocked by 598 surfaces; and
- M1 correctly blocked by 601 prerequisite surfaces.

The static backend checkpoint is complete. M0 is not complete, and no
app/backend implementation or production operation has been performed.

Query/profiler checkpoint verified later on 2026-08-31:

- 684 recorded / 672 automatic / 12 manual surfaces;
- 595 unclassified surfaces remain;
- 84 surfaces are characterized, two are blocked, and three control/tool
  surfaces are verified;
- deterministic query generation/check passed with 170 candidates, 74 files
  containing recognized operations, and 386 occurrences;
- profiler syntax, help, mutation guard, and intentional missing-credential
  refusal passed;
- conversion sync/check/report passed with zero errors and warnings; and
- M0 correctly remains blocked by 595 unclassified surfaces.

No Firebase production read or mutation and no Supabase implementation occurred
at this checkpoint.

Capability guidance/catalog checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 595 unclassified surfaces remain;
- 84 surfaces are characterized, two are blocked, and four control/tool
  surfaces are verified;
- capability evolution is now a required G0.5 gate before target schema;
- all 88 Swift service/Auth and MCP files are assigned to 11 capability groups;
- capability generation/check passed with zero unassigned files;
- exact reviewed `acknowledgeSourceHash` is required for deliberate changes to
  previously characterized automatic surfaces; and
- intentional wrong-hash acknowledgment failed as required;
- conversion sync/check/report passed with zero errors and warnings; and
- production evidence and capability dossier decisions remain explicitly open.

Identity/lifecycle dossier checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 584 unclassified surfaces remain;
- 95 surfaces are characterized, two are blocked, and four control/tool
  surfaces are verified;
- 11 additional identity/session/model/UI/MCP/test surfaces were characterized;
- stale auth/offline spec assumptions were corrected without choosing a target
  provider or lease policy;
- conversion sync/check/report passed with zero errors and warnings; and
- M0 correctly remains blocked by 584 unclassified surfaces.

Media/attachment dossier checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 540 unclassified surfaces remain;
- 139 surfaces are characterized, two are blocked, and four control/tool
  surfaces are verified;
- 44 additional media/local/UI/MCP/test/fixture/migration surfaces were
  characterized by `M0-MEDIA-LIFECYCLE-001`;
- static source/spec review found no uniform current local-display or durable
  enqueue contract and did not treat those defects as target parity;
- O-023 and the target attachment lifecycle are traced through product,
  architecture, tracker, dossier and tests;
- classification JSON, conversion sync/check/report passed with zero errors and
  warnings; and
- M0 correctly remains blocked by 540 unclassified surfaces.

No Firebase production read or mutation and no Supabase/PowerSync application,
schema, Storage policy, or migration implementation occurred at this checkpoint.

Projects/Clients/reference-data dossier checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 486 unclassified surfaces remained;
- 193 surfaces were characterized, two blocked and four verified;
- 54 Project/Client/note/category/preference/vendor/template/UI/MCP/test
  surfaces were characterized by `M0-PROJECT-CLIENT-REFERENCE-001`;
- O-024–O-026 and the target-neutral Client/Project/reference contracts were
  traced through product, architecture, tracker, dossier and tests; and
- conversion sync/check/report passed with zero errors and warnings.

Unified Item creation/Link dossier checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 434 unclassified surfaces remain;
- 245 surfaces are characterized, two blocked and four verified;
- 52 Item/proto/service/model/UI/MCP/test surfaces were characterized by
  `M0-ITEM-CREATION-LINK-001`;
- stale runtime Firebase dual-read guidance was removed, and O-027 was added to
  the decision log and architecture traceability;
- classification JSON and conversion sync/check/report passed with zero errors
  and warnings; and
- M0 correctly remains blocked by 434 unclassified surfaces.

Inventory/provenance/Transaction dossier checkpoint verified later on
2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 353 unclassified surfaces remain;
- 326 surfaces are characterized, two blocked and four verified;
- 81 Inventory/Transaction/lineage/service/model/UI/MCP/test/migration surfaces
  were characterized by `M0-INVENTORY-TRANSACTION-001`;
- Vendor Credit target conflict and O-028–O-032 were traced through product,
  architecture, tracker, dossier and tests;
- classification JSON and conversion sync/check/report passed with zero errors
  and warnings; and
- M0 correctly remains blocked by 353 unclassified surfaces.

Invoicing/collection/budget dossier checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 291 unclassified surfaces remain;
- 388 surfaces are characterized, two blocked and four verified;
- 62 Invoice/Fee/budget/vendor-import/service/model/UI/MCP/test/migration
  surfaces were characterized by `M0-INVOICING-BUDGET-001`;
- O-033/O-034 and the target-neutral source, whole-collection, immutable-paid,
  and stable budget-contribution contracts were traced through product,
  architecture, tracker, dossier, evidence and tests;
- classification JSON, conversion sync/check/report, capability/query generated
  checks, and `git diff --check` passed with zero errors and warnings; and
- M0 correctly remains blocked by 291 unclassified surfaces.

No Firebase production read or mutation and no Supabase/PowerSync application,
schema, RLS, Sync Stream, migration or production operation occurred at this
checkpoint.

Reporting/search dossier checkpoint verified later on 2026-08-31:

- 42 report/search/export/calculation/MCP/test/manual surfaces were classified
  by `M0-REPORTING-SEARCH-001`;
- O-035/O-036 and the typed readiness/version/visibility-safe projection
  contracts were traced through product, architecture, tracker and evidence;
- conversion sync/check/report, capability/query checks and diff validation
  passed.

Spaces/review dossier checkpoint verified later on 2026-08-31:

- 33 Space/checklist/assignment/review/work-queue/MCP/test/migration surfaces
  were classified by `M0-SPACES-REVIEW-001`;
- O-037 and typed Space/review/archive/readiness contracts were traced through
  product, architecture, tracker and evidence; and
- conversion sync/check/report, capability/query checks and diff validation
  passed.

Platform/control dossier checkpoint verified later on 2026-08-31:

- 101 app-composition/environment/MCP/release/hosting/source-tool/reverse-
  migration surfaces were classified by `M0-PLATFORM-CONTROL-001`;
- target generic Firestore repositories, fallback production identities,
  unauthenticated MCP Account context, stale manual schema authority and reverse
  migration reuse were explicitly rejected; and
- conversion sync/check/report, capability/query checks and diff validation
  passed.

Whole-manifest M0 checkpoint verified later on 2026-08-31:

- 115 final app-shell/presentation/navigation/platform-capture/test surfaces
  were classified by `M0-APP-SHELL-PRESENTATION-001`;
- 685 total surfaces across 17 batches have 679 characterized, four verified
  and two explicitly blocked states;
- dispositions are 134 preserve, 186 redesign, 239 replace, 37 retire, 87
  source-only and two migrate;
- zero unclassified, missing behavior, missing evidence, missing batch,
  source-drift, structural-error or warning gaps remain;
- conversion sync/check/report, deterministic capability/query checks,
  classification JSON validation and `git diff --check` passed;
- `M0 PASS: Inventory classified`; and
- M1 correctly remains blocked by exactly `MAN-DATA-001` and
  `MAN-CUTOVER-001`.

No production Firebase read or mutation, Firebase application implementation,
Supabase/PowerSync schema/application implementation, migration, release, or
cutover occurred at this checkpoint.

M2 foundation checkpoint verified later on 2026-08-31:

- 62 target-relevant surfaces are exactly `target_mapped`: 39 app-shell, eight
  identity/session and 15 media/local-durability surfaces;
- the media batch has exactly four intentional mapping holds, all tied to O-023
  and the canonical production reference/object profile;
- mapped-field completeness checks found zero missing owner, target surface,
  security, Sync, migration, reconciliation, test or acceptance fields; and
- no production read/mutation or target implementation occurred.

M2 platform-control checkpoint verified later on 2026-08-31:

- 100 target-relevant surfaces are exactly `target_mapped`: the prior 62 plus
  38 platform/environment/MCP/release/control surfaces;
- the platform batch has exactly three intentional mapping holds tied to
  A-003/A-004, A-015/A-016/physical verification and O-008/O-031;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- A-003/A-004 remain proposed; no target implementation, production operation,
  deployment, release or cutover occurred.

M2 Client/Project/reference checkpoint verified later on 2026-08-31:

- 136 target-relevant surfaces are exactly `target_mapped`: the prior 100 plus
  36 Client/Project/reference surfaces;
- the batch has exactly 16 intentional holds tied only to O-024, O-025 or
  O-026, where the decision can change the command/retention/security boundary;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or Supabase/PowerSync implementation occurred.

M2 stable Item checkpoint verified later on 2026-08-31:

- 150 target-relevant surfaces are exactly `target_mapped`: the prior 136 plus
  14 Item query/port/bulk/test surfaces;
- the Item batch has exactly 17 intentional holds tied to A-015 or
  O-007/O-015–O-019/O-023/O-027; O-021 is recorded as UI-only, not an
  architecture blocker;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or target implementation occurred.

M2 stable reporting/search checkpoint verified later on 2026-08-31:

- 231 target-relevant surfaces are exactly `target_mapped`: the prior 212 plus
  19 reporting/search/export surfaces;
- the batch has exactly 18 intentional holds tied to A-015 or underlying
  accounting/report/delivery decisions, including O-035/O-036;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or target implementation occurred.

M2 whole-manifest stable-mapping audit verified later on 2026-08-31:

- all 427 target-relevant surfaces were audited across 17 batches;
- 263 are exactly `target_mapped` and 164 remain explicitly held;
- zero mapped entries are missing owner, target surface, security, Sync,
  migration, reconciliation, test or acceptance fields;
- zero held target-relevant entries have an empty blocker list;
- M0 passes, M1 remains blocked by exactly `MAN-DATA-001` and
  `MAN-CUTOVER-001`, and M2 correctly remains blocked by 164 surfaces; and
- no production operation, target implementation, deployment, release,
  migration or cutover occurred.

M2 stable Spaces/review checkpoint verified later on 2026-08-31:

- 212 target-relevant surfaces are exactly `target_mapped`: the prior 196 plus
  16 Space/review surfaces;
- the batch has exactly 11 intentional holds tied to O-023/O-026/O-032/O-037
  or A-015;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or target implementation occurred.

M2 stable Invoicing/budget checkpoint verified later on 2026-08-31:

- 196 target-relevant surfaces are exactly `target_mapped`: the prior 175 plus
  21 Invoicing/budget surfaces;
- the batch has exactly 23 intentional holds tied to mapping-changing A/O
  decisions, including explicit O-009/O-010 and O-033/O-034 coverage;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or target implementation occurred.

M2 stable Inventory/Transaction checkpoint verified later on 2026-08-31:

- 175 target-relevant surfaces are exactly `target_mapped`: the prior 150 plus
  25 Inventory/Transaction/provenance surfaces;
- the batch has exactly 41 intentional holds, each tied to a mapping-changing
  A/O decision rather than a generic implementation placeholder;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or target implementation occurred.

Complete product-packet/spike-protocol checkpoint verified later on 2026-08-31:

- 16 packet files cover all 35 generated product blockers and all 157 residual
  surfaces with any product blocker; O-021 is explicitly UI-only;
- the seven other residual surfaces depend only on architecture/spike, physical-
  target verification, or canonical-production-evidence blockers;
- the S0–S9 vertical-spike protocol and prepared evidence record cover A-003/
  A-004/A-007/A-015/A-016 and physical verification without approving them;
- all 63 required D-001–D-027/O-002–O-037 traceability rows exist exactly once;
- all relative Markdown links across 87 redesign architecture/program files
  resolve and all 16 packet index targets exist;
- all 16 packets pass the required decision/constraints/options/target/security/
  migration/tests/consequences/checklist structure audit;
- residual and query artifacts were regenerated; conversion sync/check/report,
  capability/query/residual checks and `git diff --check` pass;
- M0 passes at 686 total / 674 discovered surfaces, M1 correctly remains blocked
  by two surfaces, and M2 correctly remains blocked by 164 surfaces; and
- no production read/mutation, Firebase adapter/v2 implementation, target DDL/
  implementation/deployment, migration, release or cutover occurred.

Product-authority cross-reference checkpoint verified on 2026-09-01:

- all 686 surfaces resolve through 18 batches to reviewed authority sets: 573
  product-governed and 113 technical/control;
- all five target specs then registered were represented and explicitly separated from
  current-product, historical-evidence, architecture and conversion-control
  roles;
- the generated JSON records every stable surface ID and the generated Markdown
  publishes batch/spec counts; both are freshness-checked;
- explicit canonical-target reconciliation is present across the affected
  capability dossiers and the specs index now foregrounds the new redesign
  specs;
- conversion sync/check/report and M0 passed with 686 recorded / 674 discovered
  surfaces, zero errors and zero warnings; and
- no production read/mutation, Firebase application implementation, target DDL/
  implementation/deployment, migration, release or cutover occurred.

Vertical-slice implementation-method checkpoint verified on 2026-09-01:

- one required method now governs exact authority-to-requirement-to-contract-to-
  verification-to-evidence traceability for every future target slice;
- the template covers domain, Postgres, handlers, Data API grants, RLS, Sync,
  offline/local, media, app/MCP, migration/reconciliation, operations and
  rollout/rollback obligations;
- conversion checking accepts a fully traced ready dossier, rejects an
  incomplete ready dossier, and rejects an implemented target surface without
  a correspondingly advanced slice;
- the clean generated audit correctly reports zero slices, zero claimed target
  surfaces and zero implementation-advanced target surfaces because target
  implementation has not begun;
- conversion sync/check/report, capability/query/residual checks and M0 pass at
  686 recorded / 674 discovered surfaces with zero errors and warnings; and
- no production read/mutation, Firebase application implementation, target DDL/
  implementation/deployment, migration, release or cutover occurred.

Target-environment isolation checkpoint verified later on 2026-09-01:

- `target-environment-isolation` is the first active implementation dossier;
  four of five verification obligations pass and the external-CI/complete
  operational obligation remains planned;
- the provider-free `LedgerTargetCore` graph check passes and all 12 package
  tests pass;
- repeated XcodeGen generation produced stable target project/scheme hashes;
- the separate `LedgerTargetStaging` application builds for macOS and generic
  iOS Simulator with bundle `apps.nine4.ledger.staging`, product/display name
  `Ledger STAGING`, and no signing;
- the source Firebase `LedgeriOS.xcodeproj` has no checkpoint diff and the
  target graph contains no Firebase, Google Sign-In, Supabase, or PowerSync SDK;
- conversion sync/check pass at 699 recorded / 684 discovered surfaces with
  zero errors and three explained retired-path warnings;
- the target CI job is defined but has no external run evidence yet; and
- no hosted resource, credential, network backend, production read/mutation,
  deployment, migration, release, branch/ref operation, or cutover occurred.
